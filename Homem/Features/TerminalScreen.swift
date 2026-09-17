import SwiftUI
import SwiftTerm

struct TerminalScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    var botID: String
    @State private var connectionID = UUID()
    var body: some View {
        Group {
            if let api = store.api, !api.isDemo { NativeTerminal(api: api, botID: botID).id(connectionID) }
            else { EmptyState(title: "Terminal unavailable", symbol: "terminal", detail: "Connect your Memoh server to open an interactive workspace shell.") }
        }.navigationTitle("Terminal".localized).navigationBarTitleDisplayMode(.inline)
            .toolbar { Button { connectionID = UUID() } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Reconnect terminal".localized) }
            .onChange(of: scenePhase) { _, phase in if phase == .active { connectionID = UUID() } }
    }
}

struct NativeTerminal: UIViewRepresentable {
    let api: APIClient
    let botID: String
    func makeCoordinator() -> Coordinator { Coordinator(api: api, botID: botID) }
    func makeUIView(context: Context) -> TerminalView {
        let terminal = TerminalView(frame: .zero)
        terminal.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        terminal.nativeBackgroundColor = UIColor(red: 0.055, green: 0.07, blue: 0.08, alpha: 1)
        terminal.nativeForegroundColor = UIColor(red: 0.85, green: 0.9, blue: 0.87, alpha: 1)
        terminal.terminalDelegate = context.coordinator
        context.coordinator.terminal = terminal
        context.coordinator.connect()
        terminal.accessibilityLabel = "Interactive workspace terminal".localized
        return terminal
    }
    func updateUIView(_ view: TerminalView, context: Context) {}
    static func dismantleUIView(_ view: TerminalView, coordinator: Coordinator) { coordinator.close() }

    @MainActor final class Coordinator: NSObject, @preconcurrency TerminalViewDelegate {
        let api: APIClient
        let botID: String
        weak var terminal: TerminalView?
        var socket: URLSessionWebSocketTask?
        var receiver: Task<Void, Never>?
        init(api: APIClient, botID: String) { self.api = api; self.botID = botID }
        func connect() {
            receiver = Task { [weak self] in
                guard let self else { return }
                do {
                    let socket = try await self.api.socket("/bots/\(self.botID.pathComponent)/container/terminal/ws", query: ["cols": "80", "rows": "24"])
                    self.socket = socket
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
        func close() { receiver?.cancel(); socket?.cancel(with: .goingAway, reason: nil); socket = nil }
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
