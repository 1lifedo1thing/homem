import XCTest
import WebRTC
import CoreGraphics
@testable import Homem

/// A real local WebRTC peer answers through the HTTP test transport. No production session is used.
@MainActor final class DesktopConnectionTests: XCTestCase {
    func testOfficialDesktopRecoversAfterNetworkDropAndStopsWhenDismissed() async throws {
        let api = APIClient(baseURL: OfficialServer.apiURL, officialSession: OfficialSession(cookies: []))
        var connections = [RecoverableDesktopFixture]()
        let model = DesktopModel(api: api, botID: "fixture") { _, _ in
            let connection = RecoverableDesktopFixture()
            connections.append(connection)
            return connection
        }
        await model.connect()
        try await waitUntil { model.hasVideo }
        XCTAssertEqual(model.status, "Connected")
        await connections[0].drop()
        try await waitUntil { connections.count == 2 && model.status == "Connected" }
        XCTAssertNil(model.error)
        model.disconnect()
        let count = connections.count
        try await Task.sleep(for: .seconds(1.2))
        XCTAssertEqual(connections.count, count)
        XCTAssertEqual(model.status, "Disconnected")
        XCTAssertNil(model.runtimeImage)
    }
    func testOfficialDesktopCancelsPendingRecoveryOnDismissal() async throws {
        let api = APIClient(baseURL: OfficialServer.apiURL, officialSession: OfficialSession(cookies: []))
        var count = 0
        let model = DesktopModel(api: api, botID: "fixture") { _, _ in count += 1; throw URLError(.networkConnectionLost) }
        await model.connect()
        XCTAssertEqual(model.status, "Reconnecting")
        model.disconnect()
        try await Task.sleep(for: .seconds(1.2))
        XCTAssertEqual(count, 1)
        XCTAssertEqual(model.status, "Disconnected")
    }
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(30)) }
        XCTAssertTrue(condition())
    }
    func testNativeOfferReceivesVideoTrackAndCleansUpSession() async throws {
        let remote = DesktopPeerFixture()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DesktopOfferProtocol.self]
        let api = APIClient(baseURL: URL(string: "http://127.0.0.1/api")!, session: URLSession(configuration: config))
        var closed = false
        DesktopOfferProtocol.handler = { request in
            if request.httpMethod == "DELETE" { closed = true; return Data() }
            if request.url!.path.hasSuffix("/offer") {
                var data = request.httpBody
                if data == nil, let stream = request.httpBodyStream {
                    stream.open(); defer { stream.close() }
                    var buffer = [UInt8](repeating: 0, count: 4096); var body = Data()
                    while stream.hasBytesAvailable { let size = stream.read(&buffer, maxLength: buffer.count); if size <= 0 { break }; body.append(buffer, count: size) }
                    data = body
                }
                let offer = try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap(data))
                XCTAssertTrue(offer["sdp"].string.contains("m=video"))
                XCTAssertTrue(offer["sdp"].string.contains("a=recvonly"))
                let answer = try await remote.answer(offer["sdp"].string)
                return try JSONValue.object(["type": "answer", "sdp": .string(answer), "session_id": "native-test"]).encoded
            }
            return Data(#"{"enabled":true,"available":true,"running":true}"#.utf8)
        }
        defer { DesktopOfferProtocol.handler = nil; remote.peer.close() }
        let model = DesktopModel(api: api, botID: "fixture")
        await model.connect()
        let deadline = Date().addingTimeInterval(12)
        while (model.track == nil || model.status != "Connected"), Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertNil(model.error)
        XCTAssertEqual(model.status, "Connected")
        XCTAssertNotNil(model.track)
        model.videoSize = CGSize(width: 1280, height: 720)
        XCTAssertNil(model.point(CGPoint(x: 0, y: 0), in: CGSize(width: 400, height: 800)))
        let point = try XCTUnwrap(model.point(CGPoint(x: 200, y: 400), in: CGSize(width: 400, height: 800)))
        XCTAssertEqual(point.x, 640, accuracy: 1); XCTAssertEqual(point.y, 360, accuracy: 1)
        model.disconnect()
        let closeDeadline = Date().addingTimeInterval(3)
        while !closed, Date() < closeDeadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(closed)
        XCTAssertNil(model.track)
    }
}

private final class DesktopOfferProtocol: URLProtocol, @unchecked Sendable {
    @MainActor static var handler: ((URLRequest) async throws -> Data)?
    private var responseTask: Task<Void, Never>?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        responseTask = Task { @MainActor in
            do {
                let data = try await Self.handler!(request)
                guard !Task.isCancelled else { return }
                client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch { client?.urlProtocol(self, didFailWithError: error) }
        }
    }
    override func stopLoading() { responseTask?.cancel() }
}

@MainActor private final class DesktopPeerFixture: NSObject, RTCPeerConnectionDelegate {
    let factory: RTCPeerConnectionFactory
    var peer: RTCPeerConnection!
    override init() {
        RTCInitializeSSL()
        factory = RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(), decoderFactory: RTCDefaultVideoDecoderFactory())
        super.init()
        let config = RTCConfiguration(); config.sdpSemantics = .unifiedPlan
        peer = factory.peerConnection(with: config, constraints: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil), delegate: self)
        let track = factory.videoTrack(with: factory.videoSource(), trackId: "desktop-video")
        peer.add(track, streamIds: ["desktop"])
    }
    func answer(_ sdp: String) async throws -> String {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in peer.setRemoteDescription(RTCSessionDescription(type: .offer, sdp: sdp)) { error in if let error { c.resume(throwing: error) } else { c.resume() } } }
        let answer: RTCSessionDescription = try await withCheckedThrowingContinuation { c in peer.answer(for: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)) { sdp, error in if let sdp { c.resume(returning: sdp) } else { c.resume(throwing: error ?? ClientError.invalidResponse) } } }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in peer.setLocalDescription(answer) { error in if let error { c.resume(throwing: error) } else { c.resume() } } }
        let deadline = Date().addingTimeInterval(5)
        while peer.iceGatheringState != .complete, Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        return peer.localDescription!.sdp
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}

private actor RecoverableDesktopFixture: DesktopTransport {
    private var interrupted = false
    func run(frame: @Sendable (CGImage) async -> Void) async throws {
        let bytes = Data(repeating: 127, count: 16)
        let provider = CGDataProvider(data: bytes as CFData)!
        let image = CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        await frame(image)
        while !interrupted { try await Task.sleep(for: .milliseconds(30)) }
        throw URLError(.networkConnectionLost)
    }
    func drop() { interrupted = true }
    func close() { interrupted = true }
    func send(_ data: Data) async throws {}
}
