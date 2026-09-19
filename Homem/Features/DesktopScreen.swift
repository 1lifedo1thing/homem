import SwiftUI
import WebRTC
import Observation

struct DesktopScreen: View {
    @Environment(AppStore.self) private var store
    var botID: String
    var body: some View {
        if let api = store.api, !api.isDemo { DesktopContent(model: DesktopModel(api: api, botID: botID)).navigationTitle("Desktop".localized).navigationBarTitleDisplayMode(.inline) }
        else { EmptyState(title: "Desktop unavailable", symbol: "desktopcomputer", detail: "Connect to a server to use this agent’s desktop.").navigationTitle("Desktop".localized) }
    }
}

struct DesktopContent: View {
    @State var model: DesktopModel
    var embedded = false
    var isFullscreen = false
    @State private var keyboardVisible = false
    @State private var fullscreen = false
    @State private var modifiers = Set<UInt32>()
    @State private var dragging = false
    @State private var pointer = CGPoint.zero
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            if isFullscreen {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "arrow.down.right.and.arrow.up.left") }
                        .accessibilityLabel("Exit fullscreen".localized)
                    Spacer()
                    Text("Desktop".localized).font(.headline)
                    Spacer()
                    DesktopModeButton(model: model)
                }.padding(.horizontal, 16).frame(minHeight: 44)
            } else if !embedded {
                HStack {
                    StatusIndicator(text: model.status, color: model.status == "Connected" ? .green : .orange)
                    Spacer()
                    DesktopModeButton(model: model)
                }.padding(.horizontal, 12)
            }
            if let error = model.error {
                ErrorBanner(message: error) { Task { model.disconnect(); await model.connect() } }.padding()
            }
            GeometryReader { geometry in
                ZStack {
                    Color.black
                    if fullscreen { Color.clear }
                    else if let image = model.runtimeImage {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let track = model.track {
                        RemoteVideo(track: track, model: model).overlay { if !model.hasVideo { ProgressView().tint(.white) } }
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "desktopcomputer").font(.largeTitle)
                            Text(model.status.localized)
                            if model.error == nil { ProgressView().tint(.white) }
                        }.foregroundStyle(.white.opacity(0.7))
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    guard !model.viewOnly, model.status == "Connected", let point = model.point(value.location, in: geometry.size) else { return }
                    dragging = true; pointer = point; model.pointer(point, mask: 1)
                }.onEnded { _ in releasePointer() })
            }
            controls
            if !model.viewOnly, model.status == "Connected", !fullscreen {
                RemoteKeyboard(isActive: $keyboardVisible, onText: { text in
                    model.type(text, modifiers: modifiers.sorted()); modifiers.removeAll()
                }, onKey: { code, hardwareModifiers in
                    model.key(code, modifiers: Array(Set(hardwareModifiers).union(modifiers)).sorted())
                    modifiers.removeAll()
                }).frame(width: 1, height: 1).clipped()
            }
        }
        .background(Color(uiColor: .systemBackground))
        .fullScreenCover(isPresented: $fullscreen) {
            DesktopContent(model: model, isFullscreen: true)
        }
        .toolbar(embedded ? .automatic : .hidden, for: .tabBar)
        .task { if !isFullscreen { await model.connect() } }
        .onDisappear {
            keyboardVisible = false; modifiers.removeAll(); releasePointer()
            if !isFullscreen, !fullscreen { model.disconnect() }
        }
        .onChange(of: model.viewOnly) { _, viewOnly in
            if viewOnly { keyboardVisible = false; modifiers.removeAll(); dragging = false }
        }
        .onChange(of: model.status) { _, status in
            if status != "Connected" { keyboardVisible = false; modifiers.removeAll(); dragging = false }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { keyboardVisible = false; modifiers.removeAll(); releasePointer() }
            guard !isFullscreen else { return }
            if phase == .background { model.disconnect() }
            if phase == .active { Task { await model.connect() } }
        }
    }

    private var controls: some View {
        HStack(spacing: 4) {
            Button { keyboardVisible.toggle() } label: {
                Image(systemName: keyboardVisible ? "keyboard.chevron.compact.down" : "keyboard")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel((keyboardVisible ? "Hide keyboard" : "Show keyboard").localized)
            .disabled(model.viewOnly || model.status != "Connected")
            if !model.viewOnly {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        keyButton("Esc", 0xff1b)
                        keyButton("Tab", 0xff09)
                        modifierButton("Ctrl", 0xffe3)
                        modifierButton("Alt", 0xffe9)
                        modifierButton("Shift", 0xffe1)
                        modifierButton("Super", 0xffeb)
                        keyButton("←", 0xff51, label: "Left arrow")
                        keyButton("↑", 0xff52, label: "Up arrow")
                        keyButton("↓", 0xff54, label: "Down arrow")
                        keyButton("→", 0xff53, label: "Right arrow")
                        Menu {
                            Button("Backspace".localized) { sendKey(0xff08) }
                            Button("Delete".localized) { sendKey(0xffff) }
                            Button("Return".localized) { sendKey(0xff0d) }
                            Button("Home".localized) { sendKey(0xff50) }
                            Button("End".localized) { sendKey(0xff57) }
                            Button("Page up".localized) { sendKey(0xff55) }
                            Button("Page down".localized) { sendKey(0xff56) }
                            Button("Insert".localized) { sendKey(0xff63) }
                            Button("Ctrl + Alt + Delete") { model.key(0xffff, modifiers: [0xffe3, 0xffe9]); modifiers.removeAll() }
                            ForEach(1...12, id: \.self) { number in
                                Button("F\(number)") { sendKey(0xffbd + UInt32(number)) }
                            }
                        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                        .accessibilityLabel("More keys".localized)
                    }
                }.disabled(model.status != "Connected")
            } else { Spacer(minLength: 0) }
            Menu {
                Button("Right click".localized) { model.pointer(pointer, mask: 4); model.pointer(pointer, mask: 0) }
                    .disabled(model.viewOnly || model.status != "Connected")
                Button("Scroll up".localized) { model.pointer(pointer, mask: 8); model.pointer(pointer, mask: 0) }
                    .disabled(model.viewOnly || model.status != "Connected")
                Button("Scroll down".localized) { model.pointer(pointer, mask: 16); model.pointer(pointer, mask: 0) }
                    .disabled(model.viewOnly || model.status != "Connected")
                Button("Reconnect desktop".localized) { Task { model.disconnect(); await model.connect() } }
            } label: { Image(systemName: "computermouse").frame(width: 44, height: 44) }
            .accessibilityLabel("Desktop controls".localized)
            if !isFullscreen {
                Button { keyboardVisible = false; modifiers.removeAll(); releasePointer(); fullscreen = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44)
                }.accessibilityLabel("Fullscreen".localized)
            }
        }.buttonStyle(.plain).padding(.horizontal, 6).background(.bar)
    }
    private func keyButton(_ title: String, _ code: UInt32, label: String? = nil) -> some View {
        Button { sendKey(code) } label: { Text(title).font(.system(.caption, design: .monospaced)).frame(minWidth: 40, minHeight: 44) }
            .accessibilityLabel((label ?? title).localized)
    }
    private func modifierButton(_ title: String, _ code: UInt32) -> some View {
        Button {
            if modifiers.contains(code) { modifiers.remove(code) } else { modifiers.insert(code) }
        } label: {
            Text(title).font(.system(.caption, design: .monospaced)).frame(minWidth: 40, minHeight: 44)
                .background(modifiers.contains(code) ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.accessibilityValue((modifiers.contains(code) ? "On" : "Off").localized)
    }
    private func sendKey(_ code: UInt32) { model.key(code, modifiers: modifiers.sorted()); modifiers.removeAll() }
    private func releasePointer() { if dragging { model.pointer(pointer, mask: 0); dragging = false } }
}

/// UIKit owns composition and candidate selection; only committed text goes to the host.
struct RemoteKeyboard: UIViewRepresentable {
    @Binding var isActive: Bool
    let onText: (String) -> Void
    let onKey: (UInt32, [UInt32]) -> Void
    func makeUIView(context: Context) -> RemoteKeyboardView { RemoteKeyboardView() }
    func updateUIView(_ view: RemoteKeyboardView, context: Context) {
        view.onText = onText; view.onKey = onKey
        view.onDismiss = { if isActive { isActive = false } }
        if isActive, !view.isFirstResponder {
            // SwiftUI may attach this view to its window after updateUIView returns.
            view.wantsKeyboard = true
            DispatchQueue.main.async { [weak view] in
                guard let view, view.wantsKeyboard, view.window != nil else { return }
                view.becomeFirstResponder()
            }
        } else if !isActive { view.wantsKeyboard = false; view.resignFirstResponder() }
    }
    static func dismantleUIView(_ view: RemoteKeyboardView, coordinator: ()) {
        view.wantsKeyboard = false; view.onDismiss = nil; view.resignFirstResponder()
    }
}

final class RemoteKeyboardView: UITextView, UITextViewDelegate {
    var onText: ((String) -> Void)?
    var onKey: ((UInt32, [UInt32]) -> Void)?
    var onDismiss: (() -> Void)?
    var wantsKeyboard = false
    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        delegate = self
        autocorrectionType = .no; autocapitalizationType = .none; spellCheckingType = .no
        smartQuotesType = .no; smartDashesType = .no; smartInsertDeleteType = .no
        textContentType = nil; backgroundColor = .clear; textColor = .clear; tintColor = .clear
        isScrollEnabled = false
        inputAssistantItem.leadingBarButtonGroups = []; inputAssistantItem.trailingBarButtonGroups = []
        accessibilityLabel = "Type on remote desktop".localized
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func textViewDidChange(_ textView: UITextView) { flushCommittedText() }
    override func unmarkText() { super.unmarkText(); flushCommittedText() }
    func flushCommittedText() {
        guard markedTextRange == nil, !text.isEmpty else { return }
        let committed = text!
        text = ""
        onText?(committed)
    }
    override func deleteBackward() {
        if markedTextRange != nil || !text.isEmpty { super.deleteBackward() }
        else { onKey?(0xff08, []) }
    }
    func textViewDidEndEditing(_ textView: UITextView) { text = ""; onDismiss?() }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled = Set<UIPress>()
        for press in presses {
            guard let key = press.key, markedTextRange == nil else { unhandled.insert(press); continue }
            let special: UInt32?
            switch key.keyCode {
            case .keyboardEscape: special = 0xff1b
            case .keyboardTab: special = 0xff09
            case .keyboardReturnOrEnter, .keypadEnter: special = 0xff0d
            case .keyboardDeleteOrBackspace: special = 0xff08
            case .keyboardDeleteForward: special = 0xffff
            case .keyboardLeftArrow: special = 0xff51
            case .keyboardUpArrow: special = 0xff52
            case .keyboardRightArrow: special = 0xff53
            case .keyboardDownArrow: special = 0xff54
            case .keyboardHome: special = 0xff50
            case .keyboardEnd: special = 0xff57
            case .keyboardPageUp: special = 0xff55
            case .keyboardPageDown: special = 0xff56
            case .keyboardInsert: special = 0xff63
            case .keyboardF1, .keyboardF2, .keyboardF3, .keyboardF4, .keyboardF5, .keyboardF6, .keyboardF7, .keyboardF8, .keyboardF9, .keyboardF10, .keyboardF11, .keyboardF12: special = 0xffbe + UInt32(key.keyCode.rawValue - UIKeyboardHIDUsage.keyboardF1.rawValue)
            default: special = nil
            }
            var modifiers: [UInt32] = []
            if key.modifierFlags.contains(.control) { modifiers.append(0xffe3) }
            if key.modifierFlags.contains(.alternate) { modifiers.append(0xffe9) }
            if key.modifierFlags.contains(.command) { modifiers.append(0xffeb) }
            if key.modifierFlags.contains(.shift) { modifiers.append(0xffe1) }
            if let special { onKey?(special, modifiers) }
            else if !key.modifierFlags.intersection([.control, .command]).isEmpty,
                    let scalar = key.charactersIgnoringModifiers.unicodeScalars.first {
                onKey?(RemoteKeyInput.keysym(scalar), modifiers)
            } else { unhandled.insert(press) }
        }
        if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
    }
}

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
    var track: RTCVideoTrack?
    var runtimeImage: UIImage?
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
        runtimeImage = UIImage(cgImage: image); videoSize = CGSize(width: image.width, height: image.height)
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
