import Foundation
import CoreGraphics

/// RFB 3.8 (RFC 6143), carried by the official runtime gateway's authenticated socket.
/// Only None authentication is accepted here: the gateway authenticates the connection.
struct RFBClient {
    enum Failure: Error { case incomplete, invalid, unsupported }
    enum Phase { case version, security, result, initial, messages }
    private var phase = Phase.version
    private var buffer = [UInt8]()
    private var rectangles: Int?
    private(set) var width = 0
    private(set) var height = 0
    private(set) var pixels = [UInt8]() // little-endian BGRX, as requested in SetPixelFormat
    private(set) var revision = 0
    private let limit = 64 * 1_024 * 1_024

    mutating func receive(_ data: Data) throws -> [Data] {
        guard buffer.count + data.count <= limit else { throw Failure.invalid }
        buffer.append(contentsOf: data)
        var output = [Data]()
        var consumed = 0
        while consumed < buffer.count {
            var reader = Reader(bytes: buffer, offset: consumed)
            do {
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
                    var encodings = Data([2, 0, 0, 4])
                    for encoding: Int32 in [5, 1, 0, -223] { encodings.appendBE(UInt32(bitPattern: encoding)) }
                    output.append(encodings); output.append(updateRequest(incremental: false)); phase = .messages
                case .messages:
                    if let remaining = rectangles, remaining > 0 {
                        let x = Int(try reader.u16()), y = Int(try reader.u16())
                        let w = Int(try reader.u16()), h = Int(try reader.u16())
                        let encoding = Int32(bitPattern: try reader.u32())
                        if encoding == -223 {
                            try resize(w, h)
                        } else {
                            guard x + w <= width, y + h <= height else { throw Failure.invalid }
                            // Decode a whole rectangle before applying it. Partial socket messages never
                            // alter the framebuffer or advance the protocol state.
                            let patch: [UInt8]
                            switch encoding {
                            case 0: patch = try reader.take(w * h * 4)
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
                            case 5: patch = try Self.hextile(&reader, width: w, height: h)
                            default: throw Failure.unsupported
                            }
                            for row in 0..<h {
                                pixels.replaceSubrange(((y + row) * width + x) * 4..<((y + row) * width + x + w) * 4, with: patch[row * w * 4..<(row + 1) * w * 4])
                            }
                        }
                        rectangles = remaining - 1
                        if remaining == 1 { revision += 1; rectangles = nil; output.append(updateRequest(incremental: true)) }
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
    private static func hextile(_ reader: inout Reader, width: Int, height: Int) throws -> [UInt8] {
        var result = [UInt8](repeating: 0, count: width * height * 4)
        var background = [UInt8](repeating: 0, count: 4), foreground = background
        func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: [UInt8]) {
            for row in y..<y+h { for col in x..<x+w { let i = (row * width + col) * 4; result.replaceSubrange(i..<i+4, with: color) } }
        }
        for ty in stride(from: 0, to: height, by: 16) {
            for tx in stride(from: 0, to: width, by: 16) {
                let w = min(16, width - tx), h = min(16, height - ty)
                let flags = try reader.byte()
                guard flags & 0xe0 == 0 else { throw Failure.invalid }
                if flags & 1 != 0 {
                    let raw = try reader.take(w * h * 4)
                    for row in 0..<h { let i = ((ty + row) * width + tx) * 4; result.replaceSubrange(i..<i+w*4, with: raw[row*w*4..<(row+1)*w*4]) }
                    continue
                }
                if flags & 2 != 0 { background = try reader.take(4) }
                if flags & 4 != 0 { foreground = try reader.take(4) }
                fill(tx, ty, w, h, background)
                if flags & 8 != 0 {
                    let count = Int(try reader.byte())
                    for _ in 0..<count {
                        let color = flags & 16 != 0 ? try reader.take(4) : foreground
                        let xy = Int(try reader.byte()), wh = Int(try reader.byte())
                        let x = xy >> 4, y = xy & 15, sw = (wh >> 4) + 1, sh = (wh & 15) + 1
                        guard x + sw <= w, y + sh <= h else { throw Failure.invalid }
                        fill(tx + x, ty + y, sw, sh, color)
                    }
                }
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
        mutating func byte() throws -> UInt8 { try take(1)[0] }
        mutating func u16() throws -> UInt16 { let b = try take(2); return UInt16(b[0]) << 8 | UInt16(b[1]) }
        mutating func u32() throws -> UInt32 { let b = try take(4); return b.reduce(0) { $0 << 8 | UInt32($1) } }
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
        while !Task.isCancelled {
            let message = try await socket.receive()
            guard case .data(let data) = message else { throw RFBClient.Failure.invalid }
            let previous = decoder.revision
            for response in try decoder.receive(data) { try await send(response) }
            if decoder.revision != previous, let image = decoder.image() { await frame(image) }
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
