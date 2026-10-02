import SwiftUI
import Observation
#if os(macOS)
import AppKit
#else
import UIKit
#endif
#if !os(visionOS) && !os(macOS)
import WebRTC
#endif

enum RemoteKeyInput {
    static func keysym(_ scalar: Unicode.Scalar) -> UInt32 {
        switch scalar.value {
        case 8: return 0xff08
        case 9: return 0xff09
        case 10, 13: return 0xff0d
        case 27: return 0xff1b
        case 127: return 0xffff
        default: return scalar.value > 255 ? 0x01000000 | scalar.value : scalar.value
        }
    }
    static func codes(_ text: String) -> [UInt32] {
        text.replacingOccurrences(of: "\r\n", with: "\n").unicodeScalars.map(keysym)
    }
}

@MainActor @Observable final class DesktopModel: NSObject {
    let api: APIClient
    let botID: String
    var status = "Connecting" { didSet { DebugDiagnostics.record("Desktop stage: \(status)") } }
    var error: String?
    var track: RTCVideoTrack? {
        didSet {
            #if !os(macOS)
            pictureInPicture.updateTrack(track)
            #endif
        }
    }
    #if !os(macOS)
    @ObservationIgnored lazy var pictureInPicture = DesktopPictureInPicture(model: self)
    var runtimeImage: UIImage?
    #else
    var runtimeImage: NSImage?
    #endif
    private(set) var viewOnly = false
    private var pressedPointer = CGPoint.zero
    private var pressedButtons = 0
    private var runtime: (any DesktopTransport)?
    typealias RuntimeFactory = @MainActor (APIClient, String) async throws -> any DesktopTransport
    private let runtimeFactory: RuntimeFactory
    private let waitForNetwork: @Sendable () async throws -> Void
    private let recoveryDelay: @Sendable (Int) -> Duration
    private var runtimeTask: Task<Void, Never>?
    private var inputTask: Task<Void, Never>?
    var hasVideo = false
    var videoSize = CGSize(width: 1280, height: 720)
    private var peer: RTCPeerConnection?
    private var channel: RTCDataChannel?
    private var displaySessionID = ""
    private var generation = UUID()
    private var connecting = false
    private var watchdog: Task<Void, Never>?
    private var recovery: Task<Void, Never>?
    private var retries = 0
    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        return RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(), decoderFactory: RTCDefaultVideoDecoderFactory())
    }()
    var base: String { "/bots/\(botID.pathComponent)/container/display" }
    init(api: APIClient, botID: String,
         waitForNetwork: @escaping @Sendable () async throws -> Void = { try await DesktopRecovery.waitForNetwork() },
         recoveryDelay: @escaping @Sendable (Int) -> Duration = { DesktopRecovery.delay(attempt: $0) },
         runtimeFactory: RuntimeFactory? = nil) {
        self.api = api; self.botID = botID
        self.waitForNetwork = waitForNetwork; self.recoveryDelay = recoveryDelay
        self.runtimeFactory = runtimeFactory ?? { api, base in
            let session = try await api.call(base + "/runtime-session", method: "POST")
            let socket = try await api.runtimeDisplaySocket(sessionID: session["session_id"].string, token: session["token"].string)
            return RuntimeDesktopConnection(socket: socket)
        }
        super.init()
    }
    func connect(retrying: Bool = false) async {
        if !retrying { retries = 0 }
        guard !connecting, peer == nil, runtime == nil else { return }
        let previousFrame = retrying ? runtimeImage : nil
        disconnect(); runtimeImage = previousFrame
        let attempt = generation
        connecting = true
        defer { if generation == attempt { connecting = false } }
        error = nil; status = "Preparing desktop"
        do {
            if api.isOfficial {
                let connection = try await runtimeFactory(api, base)
                guard attempt == generation else { await connection.close(); return }
                runtime = connection; status = "Connecting"
                watchConnection(attempt)
                runtimeTask = Task { [weak self] in
                    do {
                        try await connection.run { [weak self] image in
                            await self?.receiveFrame(image, attempt: attempt)
                        }
                    } catch {
                        guard let self, self.generation == attempt else { return }
                        DebugDiagnostics.record("Desktop gateway failed: \((error as NSError).domain) \((error as NSError).code)")
                        self.connectionFailed(error)
                    }
                }
                return
            }
            try await DesktopReadiness.prepare(api: api, base: base) { [weak self] status in
                guard self?.generation == attempt else { return }
                self?.status = status
            }
            guard attempt == generation else { return }
            status = "Connecting"
            let config = RTCConfiguration(); config.sdpSemantics = .unifiedPlan
            let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
            guard let pc = Self.factory.peerConnection(with: config, constraints: constraints, delegate: self) else { throw ClientError.message("Could not create a native WebRTC connection.".localized) }
            peer = pc
            let dataConfig = RTCDataChannelConfiguration(); dataConfig.isOrdered = true
            channel = pc.dataChannel(forLabel: "display-input", configuration: dataConfig)
            let transceiver = RTCRtpTransceiverInit(); transceiver.direction = .recvOnly
            pc.addTransceiver(of: .video, init: transceiver)
            let offer: RTCSessionDescription = try await withCheckedThrowingContinuation { continuation in pc.offer(for: constraints) { sdp, error in if let error { continuation.resume(throwing: error) } else if let sdp { continuation.resume(returning: sdp) } else { continuation.resume(throwing: ClientError.invalidResponse) } } }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in pc.setLocalDescription(offer) { e in if let e { continuation.resume(throwing: e) } else { continuation.resume() } } }
            let deadline = Date().addingTimeInterval(10)
            while pc.iceGatheringState != .complete && Date() < deadline { try await Task.sleep(for: .milliseconds(100)); guard attempt == generation else { return } }
            guard attempt == generation else { return }
            var request = try api.request(base + "/webrtc/offer", method: "POST", body: ["type": "offer", "sdp": .string(pc.localDescription?.sdp ?? offer.sdp), "candidate_host": .string(api.baseURL.host ?? "")])
            request.timeoutInterval = 120
            DebugDiagnostics.record("Desktop sending offer")
            let answer = try JSONDecoder().decode(JSONValue.self, from: await api.perform(request))
            guard attempt == generation else {
                if !answer["session_id"].string.isEmpty { _ = try? await api.call(base + "/sessions/" + answer["session_id"].string.pathComponent, method: "DELETE") }
                return
            }
            DebugDiagnostics.record("Desktop received answer; candidates=\(answer["sdp"].string.components(separatedBy: "a=candidate:").count - 1)")
            displaySessionID = answer["session_id"].string
            guard !answer["sdp"].string.isEmpty else { throw ClientError.invalidResponse }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in pc.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: answer["sdp"].string)) { e in if let e { continuation.resume(throwing: e) } else { continuation.resume() } } }
            guard attempt == generation else { return }
            watchConnection(attempt)

        } catch {
            if attempt == generation {
                DebugDiagnostics.record("Desktop error: \(error.localizedDescription)")
                if error is CancellationError { disconnect() }
                else { connectionFailed(error) }
            }
        }
    }
    private func watchConnection(_ attempt: UUID) {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(25)) } catch { return }
            guard let self, generation == attempt, status != "Connected" || !hasVideo else { return }
            connectionFailed(URLError(.timedOut))
        }
    }
    private func receiveFrame(_ image: CGImage, attempt: UUID) {
        guard generation == attempt else { return }
        if !hasVideo { DebugDiagnostics.record("Desktop gateway frame: \(image.width)x\(image.height)") }
        #if os(macOS)
        runtimeImage = NSImage(cgImage: image, size: .zero)
        #else
        pictureInPicture.display(image)
        runtimeImage = UIImage(cgImage: image)
        #endif
        videoSize = CGSize(width: image.width, height: image.height)
        hasVideo = true; retries = 0; if status != "Connected" { status = "Connected" }; watchdog?.cancel()
    }
    private func connectionFailed(_ failure: Error) {
        let frame = runtimeImage
        disconnect()
        let networkFailure = DesktopRecovery.isNetworkFailure(failure)
        guard api.isOfficial, DesktopRecovery.canRetry(failure), networkFailure || retries < 3 else {
            error = failure is ClientError ? failure.localizedDescription : "The desktop connection was lost. Try reconnecting.".localized
            return
        }
        retries = min(retries + 1, 6)
        runtimeImage = frame; status = DesktopRecovery.isOffline(failure) ? "Waiting for network" : "Reconnecting"; error = nil
        let attempt = generation, delay = recoveryDelay(retries), waitForNetwork = waitForNetwork
        recovery = Task { [weak self] in
            do {
                if networkFailure { try await waitForNetwork() }
                try await Task.sleep(for: delay)
            } catch { return }
            guard let self, self.generation == attempt, !Task.isCancelled else { return }
            self.recovery = nil
            await self.connect(retrying: true)
        }
    }
    func disconnect() {
        pressedButtons = 0
        inputTask?.cancel(); inputTask = nil
        recovery?.cancel(); recovery = nil
        runtimeTask?.cancel(); runtimeTask = nil
        if let runtime { Task { await runtime.close() } }; runtime = nil; runtimeImage = nil
        generation = UUID(); connecting = false; watchdog?.cancel(); watchdog = nil; channel?.close(); channel = nil; peer?.close(); peer = nil; track = nil; hasVideo = false; status = "Disconnected"
        if !displaySessionID.isEmpty { let path = base + "/sessions/" + displaySessionID.pathComponent; displaySessionID = ""; Task { _ = try? await api.call(path, method: "DELETE") } }
    }
    func setViewOnly(_ enabled: Bool) {
        // Release a held mouse button before blocking further remote input.
        if enabled, !viewOnly, pressedButtons != 0 { pointer(pressedPointer, mask: 0) }
        viewOnly = enabled
    }
    func input(_ value: JSONValue) {
        guard !viewOnly, channel?.readyState == .open, let data = try? value.encoded else { return }
        channel?.sendData(RTCDataBuffer(data: data, isBinary: false))
    }
    private func enqueue(_ data: Data, on runtime: any DesktopTransport) {
        let previous = inputTask, attempt = generation
        inputTask = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled, generation == attempt else { return }
            do { try await runtime.send(data) }
            catch { if generation == attempt { connectionFailed(error) } }
        }
    }
    func pointer(_ point: CGPoint, mask: Int) {
        guard !viewOnly, status == "Connected" else { return }
        pressedPointer = point; pressedButtons = mask
        if let runtime { enqueue(RFBClient.pointer(x: Int(point.x.rounded()), y: Int(point.y.rounded()), mask: mask), on: runtime); return }
        input(["type": "pointer", "x": .number(point.x.rounded()), "y": .number(point.y.rounded()), "button_mask": .number(Double(mask))])
    }
    func type(_ text: String, modifiers: [UInt32] = []) {
        for code in RemoteKeyInput.codes(text) { key(code, modifiers: modifiers) }
    }
    func key(_ code: UInt32, modifiers: [UInt32] = []) {
        guard !viewOnly, status == "Connected" else { return }
        let events = modifiers.map { ($0, true) } + [(code, true), (code, false)] + modifiers.reversed().map { ($0, false) }
        if let runtime {
            // A complete keystroke is one ordered write. Independent Tasks per key
            // used to interleave down/down/up/up, dropping repeated characters.
            var data = Data()
            for (key, down) in events { data.append(RFBClient.key(key, down: down)) }
            enqueue(data, on: runtime)
        } else {
            for (key, down) in events { input(["type": "key", "keysym": .number(Double(key)), "down": .bool(down)]) }
        }
    }
    func point(_ touch: CGPoint, in size: CGSize) -> CGPoint? {
        let scale = min(size.width / videoSize.width, size.height / videoSize.height)
        guard scale > 0 else { return nil }
        let x = (touch.x - (size.width - videoSize.width * scale) / 2) / scale
        let y = (touch.y - (size.height - videoSize.height * scale) / 2) / scale
        guard x >= 0 && y >= 0 && x < videoSize.width && y < videoSize.height else { return nil }
        return CGPoint(x: x, y: y)
    }
}

extension DesktopModel: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) { Task { @MainActor in if self.peer === peerConnection { self.track = stream.videoTracks.first } } }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) { Task { @MainActor in
        guard self.peer === peerConnection else { return }
        DebugDiagnostics.record("Desktop ICE: \(newState.rawValue)")
        switch newState { case .connected, .completed: self.status = "Connected"; case .failed, .closed:
            self.disconnect()
            self.error = "The desktop connection was lost. Try reconnecting.".localized
        case .disconnected: self.status = "Reconnecting"; self.watchConnection(self.generation); default: self.status = "Connecting" }
    } }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams: [RTCMediaStream]) { Task { @MainActor in if self.peer === peerConnection { self.track = rtpReceiver.track as? RTCVideoTrack } } }
}
