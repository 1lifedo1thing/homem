import XCTest
import WebRTC
@testable import Homem

/// A real local WebRTC peer answers through the HTTP test transport. No production session is used.
@MainActor final class DesktopConnectionTests: XCTestCase {
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
