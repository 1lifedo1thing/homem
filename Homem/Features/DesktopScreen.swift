import SwiftUI
import WebRTC
import Observation

struct DesktopScreen: View {
    @Environment(AppStore.self) private var store
    var botID: String
    var body: some View {
        if let api = store.api, !api.isDemo { DesktopContent(model: DesktopModel(api: api, botID: botID)) }
        else { EmptyState(title: "Their desktop, in your hand", symbol: "desktopcomputer", detail: "Connect a Memoh server with a display-enabled workspace to view and control its desktop.").navigationTitle("Desktop") }
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
            HStack { StatusPill(text: model.status, color: model.status == "Connected" ? .green : .orange); Spacer(); Text("Touch to click · Drag to move").font(.caption).foregroundStyle(.secondary) }.padding(12)
            if let error = model.error { ErrorBanner(message: error).padding() }
            GeometryReader { geometry in
                ZStack {
                    Color.black
                    if let track = model.track { RemoteVideo(track: track, model: model) }
                    else { VStack(spacing: 16) { Image(systemName: "desktopcomputer").font(.largeTitle); Text(model.status); if model.error == nil { ProgressView().tint(.white) } }.foregroundStyle(.white.opacity(0.7)) }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    guard model.status == "Connected", let point = model.point(value.location, in: geometry.size) else { return }
                    dragging = true; pointer = point; model.pointer(point, mask: 1)
                }.onEnded { _ in if dragging { model.pointer(pointer, mask: 0); dragging = false } })
            }
            HStack {
                Button("Esc") { model.key(0xff1b) }
                Button("Tab") { model.key(0xff09) }
                Button { model.key(0xff08) } label: { Image(systemName: "delete.left") }.accessibilityLabel("Backspace")
                Button { model.pointer(pointer, mask: 8); model.pointer(pointer, mask: 0) } label: { Image(systemName: "arrow.up") }.accessibilityLabel("Scroll up")
                Button { model.pointer(pointer, mask: 16); model.pointer(pointer, mask: 0) } label: { Image(systemName: "arrow.down") }.accessibilityLabel("Scroll down")
                Spacer()
                Button("Right click") { model.pointer(pointer, mask: 4); model.pointer(pointer, mask: 0) }
            }.font(.caption).buttonStyle(.bordered).padding(10)
            HStack {
                TextField("Type on remote desktop", text: $keyboard).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder).onSubmit { typeText() }
                Button("Type") { typeText() }.disabled(keyboard.isEmpty)
                Button { model.key(0xff0d) } label: { Image(systemName: "return") }.accessibilityLabel("Return")
            }.padding(.horizontal).padding(.bottom, 12)
        }.navigationTitle("Desktop").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button { Task { await model.connect() } } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Reconnect desktop") }
            .task { await model.connect() }.onDisappear { model.disconnect() }
            .onChange(of: scenePhase) { _, phase in if phase == .background { model.disconnect() }; if phase == .active { Task { await model.connect() } } }
    }
    func typeText() { for c in keyboard.unicodeScalars { model.key(c.value > 255 ? 0x01000000 | c.value : c.value) }; keyboard = "" }
}

@MainActor @Observable final class DesktopModel: NSObject {
    let api: APIClient
    let botID: String
    var status = "Connecting"
    var error: String?
    var track: RTCVideoTrack?
    var videoSize = CGSize(width: 1280, height: 720)
    private var peer: RTCPeerConnection?
    private var channel: RTCDataChannel?
    private var displaySessionID = ""
    private var generation = UUID()
    private let factory = RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(), decoderFactory: RTCDefaultVideoDecoderFactory())
    var base: String { "/bots/\(botID.pathComponent)/container/display" }
    init(api: APIClient, botID: String) { self.api = api; self.botID = botID; super.init() }
    func connect() async {
        disconnect(); let attempt = generation
        error = nil; status = "Preparing desktop"
        do {
            let info = try await api.call(base)
            if !info["available"].bool || !info["running"].bool {
                guard info["prepare_supported"].bool else { throw ClientError.message(info["unavailable_reason"].string.nonEmpty ?? "This workspace does not have a desktop. Enable desktop support in its runtime.") }
                var request = try api.request(base + "/prepare", method: "POST"); request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                let (bytes, response) = try await api.session.bytes(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw ClientError.message("The server could not prepare this desktop.") }
                for try await line in bytes.lines where line.hasPrefix("data:") {
                    guard attempt == generation else { return }
                    if let event = try? JSONValue.parse(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)) {
                        if event["type"] == "error" || event["status"] == "error" { throw ClientError.message(event["message"].string.nonEmpty ?? event["error"].string) }
                        status = event["message"].string.nonEmpty ?? "Preparing desktop"
                    }
                }
            }
            guard attempt == generation else { return }
            status = "Connecting"
            let config = RTCConfiguration(); config.sdpSemantics = .unifiedPlan
            let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
            guard let pc = factory.peerConnection(with: config, constraints: constraints, delegate: self) else { throw ClientError.message("Could not create a native WebRTC connection.") }
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
            let answer = try await api.call(base + "/webrtc/offer", method: "POST", body: ["type": "offer", "sdp": .string(pc.localDescription?.sdp ?? offer.sdp), "candidate_host": .string(api.baseURL.host ?? "")])
            guard attempt == generation else {
                if !answer["session_id"].string.isEmpty { _ = try? await api.call(base + "/sessions/" + answer["session_id"].string.pathComponent, method: "DELETE") }
                return
            }
            displaySessionID = answer["session_id"].string
            guard !answer["sdp"].string.isEmpty else { throw ClientError.invalidResponse }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in pc.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: answer["sdp"].string)) { e in if let e { continuation.resume(throwing: e) } else { continuation.resume() } } }
        } catch { if attempt == generation { self.error = error.localizedDescription; status = "Disconnected" } }
    }
    func disconnect() {
        generation = UUID(); channel?.close(); peer?.close(); peer = nil; track = nil; status = "Disconnected"
        if !displaySessionID.isEmpty { let path = base + "/sessions/" + displaySessionID.pathComponent; displaySessionID = ""; Task { _ = try? await api.call(path, method: "DELETE") } }
    }
    func input(_ value: JSONValue) {
        guard channel?.readyState == .open, let data = try? value.encoded else { return }
        channel?.sendData(RTCDataBuffer(data: data, isBinary: false))
    }
    func pointer(_ point: CGPoint, mask: Int) { input(["type": "pointer", "x": .number(point.x.rounded()), "y": .number(point.y.rounded()), "button_mask": .number(Double(mask))]) }
    func key(_ code: UInt32) { input(["type": "key", "keysym": .number(Double(code)), "down": true]); input(["type": "key", "keysym": .number(Double(code)), "down": false]) }
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
        switch newState { case .connected, .completed: self.status = "Connected"; case .failed, .disconnected, .closed: self.status = "Disconnected"; default: self.status = "Connecting" }
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
        func videoView(_ videoView: RTCVideoRenderer, didChangeVideoSize size: CGSize) { Task { @MainActor in if size.width > 0 && size.height > 0 { model.videoSize = size } } }
    }
}
