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
