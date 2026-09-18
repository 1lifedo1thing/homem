import SwiftUI
import SwiftTerm

struct TerminalScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    var botID: String
    var embedded = false
    @State private var connectionID = UUID()
    var body: some View {
        Group {
            if embedded { terminal }
            else {
                terminal.navigationTitle("Terminal".localized).navigationBarTitleDisplayMode(.inline)
                    .toolbar(.hidden, for: .tabBar)
                    .toolbar { Button { connectionID = UUID() } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Reconnect terminal".localized) }
            }
        }.onChange(of: scenePhase) { _, phase in if phase == .active { connectionID = UUID() } }
    }
    private var terminal: some View {
        Group {
            if let api = store.api, !api.isDemo { NativeTerminal(api: api, botID: botID).id(connectionID) }
            else { EmptyState(title: "Terminal unavailable", symbol: "terminal", detail: "Connect your Memoh server to open an interactive workspace shell.") }
        }
    }
}

final class PaneTerminalInput: TerminalView {
    var focusChanged: ((Bool) -> Void)?
    override func becomeFirstResponder() -> Bool {
        let focused = super.becomeFirstResponder()
        focusChanged?(isFirstResponder)
        return focused
    }
    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        focusChanged?(isFirstResponder)
        return resigned
    }
}

/// The shortcut strip belongs to this pane, never to the screen-wide keyboard.
final class TerminalPaneView: UIView {
    let terminal = PaneTerminalInput(frame: .zero)
    private let control = UIButton(type: .system)
    private let keyboard = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.055, green: 0.07, blue: 0.08, alpha: 1)
        terminal.inputAccessoryView = nil
        let strip = UIScrollView()
        strip.showsHorizontalScrollIndicator = false
        strip.alwaysBounceHorizontal = false
        let keys = UIStackView()
        keys.axis = .horizontal
        keys.spacing = 4
        [terminal, strip, keyboard].forEach { addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        strip.addSubview(keys)
        keys.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            terminal.topAnchor.constraint(equalTo: topAnchor),
            terminal.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: trailingAnchor),
            terminal.bottomAnchor.constraint(equalTo: strip.topAnchor, constant: -4),
            strip.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 12),
            strip.trailingAnchor.constraint(equalTo: keyboard.leadingAnchor, constant: -4),
            strip.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -8),
            strip.heightAnchor.constraint(equalToConstant: 44),
            keyboard.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -12),
            keyboard.centerYAnchor.constraint(equalTo: strip.centerYAnchor),
            keyboard.widthAnchor.constraint(equalToConstant: 44),
            keyboard.heightAnchor.constraint(equalToConstant: 44),
            keys.leadingAnchor.constraint(equalTo: strip.contentLayoutGuide.leadingAnchor),
            keys.trailingAnchor.constraint(equalTo: strip.contentLayoutGuide.trailingAnchor),
            keys.topAnchor.constraint(equalTo: strip.contentLayoutGuide.topAnchor),
            keys.bottomAnchor.constraint(equalTo: strip.contentLayoutGuide.bottomAnchor),
            keys.heightAnchor.constraint(equalTo: strip.frameLayoutGuide.heightAnchor)
        ])
        func key(_ title: String, symbol: String? = nil, button: UIButton = UIButton(type: .system), action: @escaping () -> Void) {
            var config = UIButton.Configuration.plain()
            if let symbol { config.image = UIImage(systemName: symbol) } else { config.title = title }
            config.baseForegroundColor = .white
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var attributes = attributes
                attributes.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
                return attributes
            }
            button.configuration = config
            button.accessibilityLabel = title.localized
            button.addAction(UIAction { _ in action() }, for: .touchUpInside)
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            keys.addArrangedSubview(button)
        }
        key("Esc") { [weak self] in self?.terminal.send([0x1b]) }
        key("Control", button: control) { [weak self] in
            guard let self else { return }
            terminal.controlModifier.toggle()
            updateControl()
        }
        control.configuration?.title = "Ctrl"
        key("Tab", symbol: "arrow.right.to.line") { [weak self] in self?.terminal.send([0x09]) }
        for (name, symbol, suffix) in [("Left arrow", "arrow.left", "D"), ("Down arrow", "arrow.down", "B"), ("Up arrow", "arrow.up", "A"), ("Right arrow", "arrow.right", "C")] {
            key(name, symbol: symbol) { [weak self] in
                guard let self else { return }
                terminal.send(Array(("\u{1B}" + (terminal.getTerminal().applicationCursor ? "O" : "[") + suffix).utf8))
            }
        }
        let more = UIButton(type: .system)
        key("More keys", symbol: "ellipsis", button: more) {}
        more.showsMenuAsPrimaryAction = true
        more.menu = UIMenu(children: (0..<12).map { index in
            UIAction(title: "F\(index + 1)") { [weak self] _ in self?.terminal.send(EscapeSequences.cmdF[index]) }
        } + [("Home", "\u{1B}[H"), ("End", "\u{1B}[F"), ("Page up", "\u{1B}[5~"), ("Page down", "\u{1B}[6~"), ("Delete", "\u{1B}[3~")].map { title, sequence in
            UIAction(title: title.localized) { [weak self] _ in self?.terminal.send(Array(sequence.utf8)) }
        } + ["~", "|", "/", "-"].map { text in
            UIAction(title: text) { [weak self] _ in self?.terminal.insertText(text) }
        })
        keyboard.tintColor = .white
        keyboard.setImage(UIImage(systemName: "keyboard"), for: .normal)
        keyboard.accessibilityLabel = "Show keyboard".localized
        terminal.focusChanged = { [weak self] focused in
            self?.keyboard.setImage(UIImage(systemName: focused ? "keyboard.chevron.compact.down" : "keyboard"), for: .normal)
            self?.keyboard.accessibilityLabel = (focused ? "Hide keyboard" : "Show keyboard").localized
        }
        keyboard.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if terminal.isFirstResponder { terminal.resignFirstResponder() }
            else { terminal.becomeFirstResponder() }
        }, for: .touchUpInside)
        NotificationCenter.default.addObserver(self, selector: #selector(updateControl), name: .terminalViewControlModifierReset, object: terminal)
    }
    @objc private func updateControl() {
        control.isSelected = terminal.controlModifier
        control.backgroundColor = terminal.controlModifier ? tintColor.withAlphaComponent(0.35) : .clear
        control.layer.cornerRadius = 8
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { NotificationCenter.default.removeObserver(self) }
}

struct NativeTerminal: UIViewRepresentable {
    let api: APIClient
    let botID: String
    func makeCoordinator() -> Coordinator { Coordinator(api: api, botID: botID) }
    func makeUIView(context: Context) -> TerminalPaneView {
        let pane = TerminalPaneView(frame: .zero)
        let terminal = pane.terminal
        terminal.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        terminal.nativeBackgroundColor = UIColor(red: 0.055, green: 0.07, blue: 0.08, alpha: 1)
        terminal.nativeForegroundColor = UIColor(red: 0.85, green: 0.9, blue: 0.87, alpha: 1)
        terminal.terminalDelegate = context.coordinator
        context.coordinator.terminal = terminal
        context.coordinator.connect()
        terminal.accessibilityLabel = "Interactive workspace terminal".localized
        return pane
    }
    func updateUIView(_ view: TerminalPaneView, context: Context) {}
    static func dismantleUIView(_ view: TerminalPaneView, coordinator: Coordinator) { _ = view.terminal.resignFirstResponder(); coordinator.close() }

    @MainActor final class Coordinator: NSObject, @preconcurrency TerminalViewDelegate {
        let api: APIClient
        let botID: String
        weak var terminal: TerminalView?
        var socket: URLSessionWebSocketTask?
        var receiver: Task<Void, Never>?
        var heartbeat: Task<Void, Never>?
        init(api: APIClient, botID: String) { self.api = api; self.botID = botID }
        func connect() {
            receiver = Task { [weak self] in
                guard let self else { return }
                do {
                    let socket = try await self.api.socket("/bots/\(self.botID.pathComponent)/container/terminal/ws", query: ["cols": "80", "rows": "24"])
                    guard !Task.isCancelled else { socket.cancel(with: .goingAway, reason: nil); return }
                    self.socket = socket
                    // Keep idle shells alive through reverse proxies, just like chat
                    // and the desktop transport. A failed ping wakes the receive loop.
                    self.heartbeat = Task {
                        while !Task.isCancelled {
                            do {
                                try await Task.sleep(for: .seconds(20))
                                let deadline = Task { try await Task.sleep(for: .seconds(10)); socket.cancel(with: .goingAway, reason: nil) }
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
                    defer { self.heartbeat?.cancel(); self.heartbeat = nil }
                    if let terminal = self.terminal {
                        let size = terminal.getTerminal()
                        try await socket.send(.string("{\"type\":\"resize\",\"cols\":\(size.cols),\"rows\":\(size.rows)}"))
                    }
                    while !Task.isCancelled {
                        let message = try await socket.receive()
                        switch message {
                        case .data(let data): self.terminal?.feed(byteArray: Array(data)[...])
                        case .string(let text): self.terminal?.feed(text: text)
                        @unknown default: break
                        }
                    }
                } catch { if !Task.isCancelled { self.terminal?.feed(text: "\r\n\u{1B}[31mConnection closed: \(error.localizedDescription)\u{1B}[0m\r\nUse Reconnect to open a new shell.\r\n") } }
            }
        }
        func close() { heartbeat?.cancel(); heartbeat = nil; receiver?.cancel(); socket?.cancel(with: .goingAway, reason: nil); socket = nil }
        func send(source: TerminalView, data: ArraySlice<UInt8>) { Task { do { try await socket?.send(.data(Data(data))) } catch { source.feed(text: "\r\nSend failed: \(error.localizedDescription)\r\n") } } }
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) { Task { try? await socket?.send(.string("{\"type\":\"resize\",\"cols\":\(newCols),\"rows\":\(newRows)}")) } }
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) { /* Remote terminal output cannot open URLs without a user-facing confirmation flow. */ }
        func bell(source: TerminalView) { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
        func clipboardCopy(source: TerminalView, content: Data) {}
        func clipboardRead(source: TerminalView) -> Data? { nil }
        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
