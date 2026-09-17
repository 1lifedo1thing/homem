import SwiftUI
import WebRTC
import Observation

struct DesktopScreen: View {
    @Environment(AppStore.self) private var store
    var botID: String
    var body: some View {
        if let api = store.api, !api.isDemo { DesktopContent(model: DesktopModel(api: api, botID: botID)) }
        else { EmptyState(title: "Desktop unavailable", symbol: "desktopcomputer", detail: "Connect to a server to use this agent’s desktop.").navigationTitle("Desktop".localized) }
    }
}

struct DesktopContent: View {
    @State var model: DesktopModel
    @State private var keyboard = ""
    @State private var dragging = false
    @State private var pointer = CGPoint.zero
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        VStack(spacing: 0) {
            HStack { StatusIndicator(text: model.status, color: model.status == "Connected" ? .green : .orange); Spacer(); Text("Touch to click · Drag to move".localized).font(.caption).foregroundStyle(.secondary) }.padding(12)
            if let error = model.error { ErrorBanner(message: error) { Task { model.disconnect(); await model.connect() } }.padding() }
            GeometryReader { geometry in
                ZStack {
                    Color.black
                    if let image = model.runtimeImage { Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity) }
                    else if let track = model.track { RemoteVideo(track: track, model: model).overlay { if !model.hasVideo { ProgressView().tint(.white) } } }
                    else { VStack(spacing: 16) { Image(systemName: "desktopcomputer").font(.largeTitle); Text(model.status.localized); if model.error == nil { ProgressView().tint(.white) } }.foregroundStyle(.white.opacity(0.7)) }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    guard model.status == "Connected", let point = model.point(value.location, in: geometry.size) else { return }
                    dragging = true; pointer = point; model.pointer(point, mask: 1)
                }.onEnded { _ in if dragging { model.pointer(pointer, mask: 0); dragging = false } })
            }
            HStack {
                Button("Esc".localized) { model.key(0xff1b) }
                Button("Tab".localized) { model.key(0xff09) }
                Button { model.key(0xff08) } label: { Image(systemName: "delete.left") }.accessibilityLabel("Backspace".localized)
                Button { model.pointer(pointer, mask: 8); model.pointer(pointer, mask: 0) } label: { Image(systemName: "arrow.up") }.accessibilityLabel("Scroll up".localized)
                Button { model.pointer(pointer, mask: 16); model.pointer(pointer, mask: 0) } label: { Image(systemName: "arrow.down") }.accessibilityLabel("Scroll down".localized)
                Spacer()
                Button("Right click".localized) { model.pointer(pointer, mask: 4); model.pointer(pointer, mask: 0) }
            }.font(.caption).buttonStyle(.bordered).padding(10)
            HStack {
                TextField("Type on remote desktop".localized, text: $keyboard).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder).onSubmit { typeText() }
                Button("Type".localized) { typeText() }.disabled(keyboard.isEmpty)
                Button { model.key(0xff0d) } label: { Image(systemName: "return") }.accessibilityLabel("Return".localized)
            }.padding(.horizontal).padding(.bottom, 12)
        }.navigationTitle("Desktop".localized).navigationBarTitleDisplayMode(.inline)
            .toolbar { Button { Task { model.disconnect(); await model.connect() } } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Reconnect desktop".localized) }
            .task { await model.connect() }.onDisappear { model.disconnect() }
            .onChange(of: scenePhase) { _, phase in if phase == .background { model.disconnect() }; if phase == .active { Task { await model.connect() } } }
    }
    func typeText() { for c in keyboard.unicodeScalars { model.key(c.value > 255 ? 0x01000000 | c.value : c.value) }; keyboard = "" }
}

@MainActor @Observable final class DesktopModel: NSObject {
    let api: APIClient
    let botID: String
    var status = "Connecting" { didSet { DebugDiagnostics.record("Desktop stage: \(status)") } }
    var error: String?
    var track: RTCVideoTrack?
    var runtimeImage: UIImage?
    private var runtime: (any DesktopTransport)?
    typealias RuntimeFactory = @MainActor (APIClient, String) async throws -> any DesktopTransport
    private let runtimeFactory: RuntimeFactory
    private var runtimeTask: Task<Void, Never>?
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
    init(api: APIClient, botID: String, runtimeFactory: RuntimeFactory? = nil) {
        self.api = api; self.botID = botID
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
        runtimeImage = UIImage(cgImage: image); videoSize = CGSize(width: image.width, height: image.height)
        hasVideo = true; retries = 0; if status != "Connected" { status = "Connected" }; watchdog?.cancel()
    }
    private func connectionFailed(_ failure: Error) {
        let frame = runtimeImage
        disconnect()
        let canRetry: Bool
        if let http = failure as? ClientError, case .http(let status, _) = http { canRetry = status >= 500 }
        else { canRetry = failure is URLError || (failure as NSError).domain == NSURLErrorDomain }
        guard api.isOfficial, canRetry, retries < 3 else {
            error = failure is ClientError ? failure.localizedDescription : "The desktop connection was lost. Try reconnecting.".localized
            return
        }
        retries += 1
        runtimeImage = frame; status = "Reconnecting"; error = nil
        let attempt = generation, delay = 1 << (retries - 1)
        recovery = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, self.generation == attempt, !Task.isCancelled else { return }
            self.recovery = nil
            await self.connect(retrying: true)
        }
    }
    func disconnect() {
        recovery?.cancel(); recovery = nil
        runtimeTask?.cancel(); runtimeTask = nil
        if let runtime { Task { await runtime.close() } }; runtime = nil; runtimeImage = nil
        generation = UUID(); connecting = false; watchdog?.cancel(); watchdog = nil; channel?.close(); channel = nil; peer?.close(); peer = nil; track = nil; hasVideo = false; status = "Disconnected"
        if !displaySessionID.isEmpty { let path = base + "/sessions/" + displaySessionID.pathComponent; displaySessionID = ""; Task { _ = try? await api.call(path, method: "DELETE") } }
    }
    func input(_ value: JSONValue) {
        guard channel?.readyState == .open, let data = try? value.encoded else { return }
        channel?.sendData(RTCDataBuffer(data: data, isBinary: false))
    }
    func pointer(_ point: CGPoint, mask: Int) {
        if let runtime { Task { try? await runtime.send(RFBClient.pointer(x: Int(point.x.rounded()), y: Int(point.y.rounded()), mask: mask)) }; return }
        input(["type": "pointer", "x": .number(point.x.rounded()), "y": .number(point.y.rounded()), "button_mask": .number(Double(mask))]) }
    func key(_ code: UInt32) {
        if let runtime { Task { try? await runtime.send(RFBClient.key(code, down: true)); try? await runtime.send(RFBClient.key(code, down: false)) }; return }
        input(["type": "key", "keysym": .number(Double(code)), "down": true]); input(["type": "key", "keysym": .number(Double(code)), "down": false]) }
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

struct RemoteVideo: UIViewRepresentable {
    let track: RTCVideoTrack
    let model: DesktopModel
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView(frame: .zero); view.videoContentMode = .scaleAspectFit; view.delegate = context.coordinator
        track.add(view); context.coordinator.track = track; return view
    }
    func updateUIView(_ view: RTCMTLVideoView, context: Context) { if context.coordinator.track !== track { context.coordinator.track?.remove(view); track.add(view); context.coordinator.track = track } }
    static func dismantleUIView(_ view: RTCMTLVideoView, coordinator: Coordinator) { coordinator.track?.remove(view) }
    final class Coordinator: NSObject, RTCVideoViewDelegate {
        var track: RTCVideoTrack?
        let model: DesktopModel
        init(model: DesktopModel) { self.model = model }
        func videoView(_ videoView: RTCVideoRenderer, didChangeVideoSize size: CGSize) { Task { @MainActor in if size.width > 0 && size.height > 0 { model.videoSize = size; model.hasVideo = true; DebugDiagnostics.record("Desktop frame size: \(size)") } } }
    }
}
