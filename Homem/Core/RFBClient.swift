import Foundation
import CoreGraphics
import zlib

/// RFB 3.8 (RFC 6143), carried by the official runtime gateway's authenticated socket.
/// Only None authentication is accepted here: the gateway authenticates the connection.
struct RFBClient {
    enum Failure: Error { case incomplete, invalid, unsupported }
    enum Phase { case version, security, result, initial, messages }
    private var phase = Phase.version
    private var buffer = [UInt8]()
    private var rectangles: Int?
    private var hextile: HextileRectangle?
    private var inflater: RFBInflater?
    private struct HextileRectangle {
        let x: Int, y: Int, width: Int, height: Int
        var tileX = 0, tileY = 0
        var background: [UInt8] = [0, 0, 0, 0]
        var foreground: [UInt8] = [0, 0, 0, 0]
    }
    private(set) var width = 0
    private(set) var height = 0
    private(set) var pixels = [UInt8]() // little-endian BGRX, as requested in SetPixelFormat
    private(set) var revision = 0
    private let limit = 64 * 1_024 * 1_024
    var diagnosticState: String { "\(phase), revision=\(revision), buffered=\(buffer.count), size=\(width)x\(height), tile=\(hextile?.tileY ?? -1)" }

    mutating func receive(_ data: Data) throws -> [Data] {
        guard buffer.count + data.count <= limit else { throw Failure.invalid }
        buffer.append(contentsOf: data)
        var output = [Data]()
        var consumed = 0
        while consumed < buffer.count {
            var reader = Reader(bytes: buffer, offset: consumed)
            do {
                // Commit complete tiles as they arrive. Replaying an entire incomplete
                // framebuffer rectangle for every socket fragment can starve the socket.
                if var tile = hextile {
                    let w = min(16, tile.width - tile.tileX), h = min(16, tile.height - tile.tileY)
                    let patch = try Self.decodeTile(&reader, width: w, height: h,
                                                    background: &tile.background, foreground: &tile.foreground)
                    apply(patch, x: tile.x + tile.tileX, y: tile.y + tile.tileY, width: w, height: h)
                    tile.tileX += w
                    if tile.tileX == tile.width { tile.tileX = 0; tile.tileY += h }
                    if tile.tileY == tile.height {
                        hextile = nil
                        finishRectangle(output: &output)
                    } else { hextile = tile }
                    consumed = reader.offset
                    continue
                }
                switch phase {
                case .version:
                    let version = try reader.take(12)
                    guard String(bytes: version, encoding: .ascii) == "RFB 003.008\n" else { throw Failure.unsupported }
                    output.append(Data("RFB 003.008\n".utf8)); phase = .security
                case .security:
                    let count = try reader.byte()
                    guard count > 0, try reader.take(Int(count)).contains(1) else { throw Failure.unsupported }
                    output.append(Data([1])); phase = .result
                case .result:
                    guard try reader.u32() == 0 else { throw Failure.invalid }
                    output.append(Data([1])); phase = .initial
                case .initial:
                    let w = Int(try reader.u16()), h = Int(try reader.u16())
                    _ = try reader.take(16)
                    let nameLength = Int(try reader.u32())
                    guard nameLength <= 1_024 * 1_024 else { throw Failure.invalid }
                    _ = try reader.take(nameLength)
                    try resize(w, h)
                    output.append(Data([0, 0, 0, 0, 32, 24, 0, 1, 0, 255, 0, 255, 0, 255, 16, 8, 0, 0, 0, 0]))
                    var encodings = Data([2, 0, 0, 5])
                    for encoding: Int32 in [6, 5, 1, 0, -223] { encodings.appendBE(UInt32(bitPattern: encoding)) }
                    output.append(encodings); output.append(updateRequest(incremental: false)); phase = .messages
                case .messages:
                    if let remaining = rectangles, remaining > 0 {
                        let x = Int(try reader.u16()), y = Int(try reader.u16())
                        let w = Int(try reader.u16()), h = Int(try reader.u16())
                        let encoding = Int32(bitPattern: try reader.u32())
                        if encoding == -223 {
                            try resize(w, h)
                        } else {
                            guard w > 0, h > 0, x + w <= width, y + h <= height else { throw Failure.invalid }
                            if encoding == 5 {
                                hextile = HextileRectangle(x: x, y: y, width: w, height: h)
                                consumed = reader.offset
                                continue
                            }
                            // Raw and copy rectangles commit only after their complete payload arrives.
                            let patch: [UInt8]
                            switch encoding {
                            case 0: patch = try reader.take(w * h * 4)
                            case 6:
                                let length = Int(try reader.u32())
                                guard length <= limit else { throw Failure.invalid }
                                let compressed = try reader.take(length)
                                if inflater == nil { inflater = try RFBInflater() }
                                patch = try inflater!.decode(compressed, expected: w * h * 4)
                            case 1:
                                let sx = Int(try reader.u16()), sy = Int(try reader.u16())
                                guard sx + w <= width, sy + h <= height else { throw Failure.invalid }
                                var copy = [UInt8]()
                                copy.reserveCapacity(w * h * 4)
                                for row in 0..<h {
                                    let start = ((sy + row) * width + sx) * 4
                                    copy.append(contentsOf: pixels[start..<start + w * 4])
                                }
                                patch = copy
                            default: throw Failure.unsupported
                            }
                            apply(patch, x: x, y: y, width: w, height: h)
                        }
                        finishRectangle(output: &output)
                    } else {
                        switch try reader.byte() {
                        case 0:
                            _ = try reader.byte()
                            let count = Int(try reader.u16())
                            if count == 0 { output.append(updateRequest(incremental: true)) }
                            else { rectangles = count }
                        case 2: break // Bell; do not play unexpected audio.
                        case 3:
                            _ = try reader.take(3)
                            let length = Int(try reader.u32())
                            guard length <= 1_024 * 1_024 else { throw Failure.invalid }
                            _ = try reader.take(length) // Remote clipboard never replaces the local clipboard.
                        default: throw Failure.unsupported
                        }
                    }
                }
                consumed = reader.offset
            } catch Failure.incomplete { break }
        }
        if consumed > 0 { buffer.removeFirst(consumed) }
        return output
    }

    private mutating func resize(_ w: Int, _ h: Int) throws {
        guard w > 0, h > 0, w <= 8192, h <= 8192, w * h * 4 <= limit else { throw Failure.invalid }
        width = w; height = h; pixels = .init(repeating: 0, count: w * h * 4)
    }
    private func updateRequest(incremental: Bool) -> Data {
        var data = Data([3, incremental ? 1 : 0, 0, 0, 0, 0])
        data.appendBE(UInt16(width)); data.appendBE(UInt16(height)); return data
    }
    func image() -> CGImage? {
        guard width > 0, height > 0, let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue).union(.byteOrder32Little),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
    static func pointer(x: Int, y: Int, mask: Int) -> Data {
        var data = Data([5, UInt8(clamping: mask)])
        data.appendBE(UInt16(clamping: x)); data.appendBE(UInt16(clamping: y)); return data
    }
    static func key(_ code: UInt32, down: Bool) -> Data {
        var data = Data([4, down ? 1 : 0, 0, 0]); data.appendBE(code); return data
    }
    private mutating func finishRectangle(output: inout [Data]) {
        guard let remaining = rectangles else { return }
        rectangles = remaining - 1
        if remaining == 1 {
            revision += 1; rectangles = nil
            output.append(updateRequest(incremental: true))
        }
    }
    private mutating func apply(_ patch: [UInt8], x: Int, y: Int, width w: Int, height h: Int) {
        for row in 0..<h {
            let start = ((y + row) * width + x) * 4
            pixels.replaceSubrange(start..<start + w * 4, with: patch[row * w * 4..<(row + 1) * w * 4])
        }
    }
    private static func decodeTile(_ reader: inout Reader, width: Int, height: Int,
                                   background: inout [UInt8], foreground: inout [UInt8]) throws -> [UInt8] {
        let flags = try reader.byte()
        guard flags & 0xe0 == 0 else { throw Failure.invalid }
        if flags & 1 != 0 { return try reader.take(width * height * 4) }
        if flags & 2 != 0 { background = try reader.take(4) }
        if flags & 4 != 0 { foreground = try reader.take(4) }
        var result = [UInt8](repeating: 0, count: width * height * 4)
        func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: [UInt8]) {
            for row in y..<y+h { for col in x..<x+w {
                let i = (row * width + col) * 4
                result[i] = color[0]; result[i + 1] = color[1]
                result[i + 2] = color[2]; result[i + 3] = color[3]
            } }
        }
        fill(0, 0, width, height, background)
        if flags & 8 != 0 {
            let count = Int(try reader.byte())
            for _ in 0..<count {
                let color = flags & 16 != 0 ? try reader.take(4) : foreground
                let xy = Int(try reader.byte()), wh = Int(try reader.byte())
                let x = xy >> 4, y = xy & 15, w = (wh >> 4) + 1, h = (wh & 15) + 1
                guard x + w <= width, y + h <= height else { throw Failure.invalid }
                fill(x, y, w, h, color)
            }
        }
        return result
    }
    private struct Reader {
        let bytes: [UInt8]
        var offset: Int
        mutating func take(_ count: Int) throws -> [UInt8] {
            guard count >= 0, count <= bytes.count - offset else { throw Failure.incomplete }
            defer { offset += count }; return Array(bytes[offset..<offset + count])
        }
        mutating func byte() throws -> UInt8 {
            guard offset < bytes.count else { throw Failure.incomplete }
            defer { offset += 1 }; return bytes[offset]
        }
        mutating func u16() throws -> UInt16 { let b = try take(2); return UInt16(b[0]) << 8 | UInt16(b[1]) }
        mutating func u32() throws -> UInt32 { let b = try take(4); return b.reduce(0) { $0 << 8 | UInt32($1) } }
    }
}

/// Zlib encoding (6) keeps one compression stream for the entire connection.
/// Only complete rectangle payloads enter the inflater, so fragmented input cannot
/// consume stream state twice. Output is bounded by the validated rectangle size.
private final class RFBInflater {
    private let stream: UnsafeMutablePointer<z_stream>
    init() throws {
        let stream = UnsafeMutablePointer<z_stream>.allocate(capacity: 1)
        stream.initialize(to: z_stream())
        guard inflateInit_(stream, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            stream.deinitialize(count: 1); stream.deallocate()
            throw RFBClient.Failure.invalid
        }
        self.stream = stream
    }
    deinit { inflateEnd(stream); stream.deinitialize(count: 1); stream.deallocate() }
    func decode(_ input: [UInt8], expected: Int) throws -> [UInt8] {
        var output = [UInt8](repeating: 0, count: expected + 1)
        let status = input.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                stream.pointee.next_in = UnsafeMutablePointer(mutating: source.baseAddress)
                stream.pointee.avail_in = uInt(source.count)
                stream.pointee.next_out = destination.baseAddress
                stream.pointee.avail_out = uInt(destination.count)
                defer { stream.pointee.next_in = nil; stream.pointee.next_out = nil }
                return inflate(stream, Z_SYNC_FLUSH)
            }
        }
        guard status == Z_OK || status == Z_STREAM_END,
              stream.pointee.avail_in == 0, stream.pointee.avail_out == 1 else { throw RFBClient.Failure.invalid }
        output.removeLast()
        return output
    }
}

private extension Data {
    mutating func appendBE<T: FixedWidthInteger>(_ value: T) { var big = value.bigEndian; Swift.withUnsafeBytes(of: &big) { append(contentsOf: $0) } }
}

protocol DesktopTransport: Sendable {
    func run(frame: @Sendable (CGImage) async -> Void) async throws
    func send(_ data: Data) async throws
    func close() async
}

/// Serializes protocol decoding and input writes away from SwiftUI's main actor.
actor RuntimeDesktopConnection: DesktopTransport {
    private let socket: URLSessionWebSocketTask
    private var decoder = RFBClient()
    private var writes: Task<Void, Error>?
    private var heartbeat: Task<Void, Never>?
    private let heartbeatInterval: Duration
    private let pingTimeout: Duration
    init(socket: URLSessionWebSocketTask, heartbeatInterval: Duration = .seconds(20), pingTimeout: Duration = .seconds(10)) {
        self.socket = socket; self.heartbeatInterval = heartbeatInterval; self.pingTimeout = pingTimeout
    }
    func run(frame: @Sendable (CGImage) async -> Void) async throws {
        let socket = socket
        heartbeat = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: heartbeatInterval)
                    let deadline = Task { try await Task.sleep(for: pingTimeout); socket.cancel(with: .goingAway, reason: nil) }
                    defer { deadline.cancel() }
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        socket.sendPing { error in
                            if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                        }
                    }
                } catch {
                    if !Task.isCancelled { socket.cancel(with: .goingAway, reason: nil) }
                    return
                }
            }
        }
        defer { heartbeat?.cancel(); heartbeat = nil }
        do {
            while !Task.isCancelled {
                let message = try await socket.receive()
                guard case .data(let data) = message else { throw RFBClient.Failure.invalid }
                let previous = decoder.revision
                for response in try decoder.receive(data) { try await send(response) }
                if decoder.revision != previous, let image = decoder.image() { await frame(image) }
            }
        } catch {
            // Protocol stage and status codes only; never log tickets, pixels or input.
            DebugDiagnostics.record("Desktop socket ended: HTTP=\((socket.response as? HTTPURLResponse)?.statusCode ?? 0), close=\(socket.closeCode.rawValue), RFB=\(decoder.diagnosticState)")
            throw error
        }
    }
    func send(_ data: Data) async throws {
        let previous = writes
        let socket = socket
        let next = Task { try await previous?.value; try Task.checkCancellation(); try await socket.send(.data(data)) }
        writes = next
        try await next.value
    }
    func close() { heartbeat?.cancel(); heartbeat = nil; writes?.cancel(); writes = nil; socket.cancel(with: .goingAway, reason: nil) }
}
