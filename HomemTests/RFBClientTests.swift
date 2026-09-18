import XCTest
@testable import Homem

final class RFBClientTests: XCTestCase {
    private func ready(width: UInt16 = 2, height: UInt16 = 2) throws -> RFBClient {
        var client = RFBClient()
        XCTAssertEqual(try client.receive(Data("RFB 003.008\n".utf8)), [Data("RFB 003.008\n".utf8)])
        XCTAssertEqual(try client.receive(Data([1, 1])), [Data([1])])
        XCTAssertEqual(try client.receive(Data([0, 0, 0, 0])), [Data([1])])
        var initial = Data(); initial.be(width); initial.be(height)
        initial.append(Data(repeating: 0, count: 20))
        let responses = try client.receive(initial)
        XCTAssertEqual(responses.count, 3)
        XCTAssertEqual(responses[0].count, 20)
        XCTAssertEqual(responses[2].first, 3)
        return client
    }
    private func rectangle(x: UInt16 = 0, y: UInt16 = 0, width: UInt16, height: UInt16, encoding: Int32, body: [UInt8]) -> Data {
        var data = Data([0, 0, 0, 1])
        for n in [x, y, width, height] { data.be(n) }
        data.be(UInt32(bitPattern: encoding)); data.append(contentsOf: body); return data
    }
    func testFragmentedHandshakeAndRawFrame() throws {
        var client = RFBClient()
        var output = [Data]()
        for byte in Data("RFB 003.008\n".utf8) { output += try client.receive(Data([byte])) }
        XCTAssertEqual(output, [Data("RFB 003.008\n".utf8)])
        client = try ready()
        let pixels: [UInt8] = [0, 0, 255, 0, 0, 255, 0, 0, 255, 0, 0, 0, 255, 255, 255, 0]
        let update = rectangle(width: 2, height: 2, encoding: 0, body: pixels)
        for byte in update.dropLast() { _ = try client.receive(Data([byte])); XCTAssertEqual(client.revision, 0) }
        XCTAssertEqual(try client.receive(Data([update.last!])).count, 1)
        XCTAssertEqual(client.pixels, pixels); XCTAssertEqual(client.revision, 1)
        XCTAssertEqual(client.image()?.width, 2)
    }
    func testCopyRectanglePreservesOverlappingSource() throws {
        var client = try ready(width: 3, height: 1)
        _ = try client.receive(rectangle(width: 3, height: 1, encoding: 0, body: [1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0]))
        _ = try client.receive(rectangle(x: 1, width: 2, height: 1, encoding: 1, body: [0, 0, 0, 0]))
        XCTAssertEqual(client.pixels, [1, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0])
    }
    func testHextileColorsAndFragmentation() throws {
        var client = try ready()
        // Background blue, foreground red, one 1x1 rectangle at (1,1).
        let update = rectangle(width: 2, height: 2, encoding: 5, body: [14, 255, 0, 0, 0, 0, 0, 255, 0, 1, 0x11, 0])
        for byte in update { _ = try client.receive(Data([byte])) }
        XCTAssertEqual(client.pixels, [255, 0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 0, 0, 255, 0])
        XCTAssertEqual(client.revision, 1)
    }
    func testHextileRetainsColorsAcrossFragmentedRawAndEdgeTiles() throws {
        var client = try ready(width: 34, height: 17)
        let blue: [UInt8] = [255, 0, 0, 0], red: [UInt8] = [0, 0, 255, 0]
        var body: [UInt8] = [6] + blue + red // First tile sets both colors.
        body += [1] + Array(repeating: [UInt8](repeating: 42, count: 4), count: 256).flatMap { $0 }
        body += [8, 1, 0, 0x1f] // Right edge: 2x16 in retained foreground.
        body += [0, 0, 8, 1, 0, 0x10] // Bottom edge: inherited background and 2x1 foreground.
        let update = rectangle(width: 34, height: 17, encoding: 5, body: body)
        for start in stride(from: 0, to: update.count, by: 7) {
            _ = try client.receive(update.subdata(in: start..<min(start + 7, update.count)))
            if start + 7 < update.count { XCTAssertEqual(client.revision, 0) }
        }
        var expected: [UInt8] = []
        for y in 0..<17 { for x in 0..<34 {
            expected += x >= 32 ? red : (y < 16 && x >= 16 ? [42, 42, 42, 42] : blue)
        } }
        XCTAssertEqual(client.pixels, expected)
        XCTAssertEqual(client.revision, 1)
    }
    func testLargeFragmentedHextileFrame() throws {
        var client = try ready(width: 1024, height: 768)
        // A detailed screen can use raw tiles across a single large Hextile rectangle.
        let tile: [UInt8] = [1] + Array(repeating: [UInt8(17), 34, 51, 0], count: 256).flatMap { $0 }
        let body = Array(repeating: tile, count: 64 * 48).flatMap { $0 }
        let update = rectangle(width: 1024, height: 768, encoding: 5, body: body)
        for start in stride(from: 0, to: update.count, by: 4096) {
            _ = try client.receive(update.subdata(in: start..<min(start + 4096, update.count)))
        }
        XCTAssertEqual(client.revision, 1)
        XCTAssertEqual(client.pixels, Array(repeating: [UInt8(17), 34, 51, 0], count: 1024 * 768).flatMap { $0 })
    }
    func testZlibStreamContinuesAcrossFragmentedRectangles() throws {
        var client = try ready()
        // Two Z_SYNC_FLUSH chunks of the same zlib stream, not independent streams.
        let bodies: [[UInt8]] = [
            [0, 0, 0, 15, 120, 156, 98, 100, 98, 102, 96, 68, 194, 0, 0, 0, 0, 255, 255],
            [0, 0, 0, 11, 250, 255, 239, 47, 10, 6, 0, 0, 0, 255, 255]
        ]
        for (index, body) in bodies.enumerated() {
            let update = rectangle(width: 2, height: 2, encoding: 6, body: body)
            for byte in update.dropLast() { _ = try client.receive(Data([byte])); XCTAssertEqual(client.revision, index) }
            _ = try client.receive(Data([update.last!]))
            XCTAssertEqual(client.revision, index + 1)
        }
        XCTAssertEqual(client.pixels, Array(repeating: [UInt8(255), 254, 253, 0], count: 4).flatMap { $0 })
    }
    func testZlibRejectsOversizedOutputAndInvalidPayloads() throws {
        var client = try ready()
        let body: [UInt8] = [0, 0, 0, 15, 120, 156, 98, 100, 98, 102, 96, 68, 194, 0, 0, 0, 0, 255, 255]
        XCTAssertThrowsError(try client.receive(rectangle(width: 1, height: 1, encoding: 6, body: body)))
        client = try ready()
        XCTAssertThrowsError(try client.receive(rectangle(width: 2, height: 2, encoding: 6, body: [0, 0, 0, 2, 255, 255])))
        client = try ready()
        XCTAssertThrowsError(try client.receive(rectangle(width: 2, height: 2, encoding: 6, body: [255, 255, 255, 255])))
    }
    func testResizeAndInvalidRectangles() throws {
        var client = try ready()
        _ = try client.receive(rectangle(width: 4, height: 3, encoding: -223, body: []))
        XCTAssertEqual(client.width, 4); XCTAssertEqual(client.height, 3)
        XCTAssertEqual(client.pixels.count, 48)
        XCTAssertThrowsError(try client.receive(rectangle(x: 3, width: 2, height: 1, encoding: 0, body: [])))
        client = try ready()
        XCTAssertThrowsError(try client.receive(rectangle(width: 65535, height: 65535, encoding: -223, body: [])))
    }
    func testRejectsUnexpectedSecurityAndInvalidHextile() throws {
        var client = RFBClient()
        _ = try client.receive(Data("RFB 003.008\n".utf8))
        XCTAssertThrowsError(try client.receive(Data([1, 2])))
        client = try ready()
        XCTAssertThrowsError(try client.receive(rectangle(width: 2, height: 2, encoding: 5, body: [8, 1, 0x11, 0xff])))
    }
    func testInputWireFormat() {
        XCTAssertEqual(RFBClient.pointer(x: 256, y: 512, mask: 1), Data([5, 1, 1, 0, 2, 0]))
        XCTAssertEqual(RFBClient.key(0xff1b, down: true), Data([4, 1, 0, 0, 0, 0, 255, 27]))
        XCTAssertEqual(RFBClient.key(0xff1b, down: false), Data([4, 0, 0, 0, 0, 0, 255, 27]))
    }
}
private extension Data {
    mutating func be<T: FixedWidthInteger>(_ value: T) { var n = value.bigEndian; Swift.withUnsafeBytes(of: &n) { append(contentsOf: $0) } }
}
