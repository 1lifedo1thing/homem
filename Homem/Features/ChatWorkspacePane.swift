import SwiftUI

private struct ExpandChatWorkspaceKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var expandChatWorkspace: () -> Void {
        get { self[ExpandChatWorkspaceKey.self] }
        set { self[ExpandChatWorkspaceKey.self] = newValue }
    }
}

enum ChatWorkspaceTool: String, CaseIterable, Identifiable {
    case chat, files, terminal, desktop
    var id: Self { self }
    var title: String { switch self { case .chat: "Chat"; case .files: "Files"; case .terminal: "Terminal"; case .desktop: "Desktop" } }
    var symbol: String { switch self { case .chat: "bubble.left"; case .files: "folder"; case .terminal: "terminal"; case .desktop: "desktopcomputer" } }
}

struct WorkspacePane: Identifiable, Equatable {
    let id = UUID()
    let tool: ChatWorkspaceTool
}

enum WorkspaceArrangement: String, CaseIterable, Identifiable {
    case automatic, columns, rows, grid
    var id: Self { self }
    var title: String { switch self { case .automatic: "Automatic"; case .columns: "Side by side"; case .rows: "Stacked"; case .grid: "Grid" } }
}

enum ChatSplitLayout {
    static func fraction(_ value: Double) -> Double { min(0.65, max(0.25, value)) }
    static func usesColumns(width: CGFloat) -> Bool { width >= 700 }
    static func columnFraction(_ value: Double, available: CGFloat) -> Double {
        let minimum = min(0.5, 300 / max(available, 1))
        return min(1 - minimum, max(minimum, value))
    }
    static func paneHeight(available: CGFloat, fraction: Double) -> CGFloat {
        // Keep the composer and some conversation visible even above the keyboard.
        max(0, min(available * Self.fraction(fraction), available - 170))
    }
}

/// Frames share a single coordinate space, keeping pane identity stable during
/// resize, reordering and changes between arrangements.
struct WorkspaceGeometry {
    var frames: [CGRect]
    var size: CGSize
    var dividers: [CGRect] = []

    static func make(size proposed: CGSize, count: Int, arrangement: WorkspaceArrangement,
                     columnFraction: Double = 0.45, rowFraction: Double = 0.45) -> Self {
        let width = max(1, proposed.width), height = max(1, proposed.height)
        let count = max(1, count), gap: CGFloat = 24
        if count == 1 { return Self(frames: [CGRect(x: 0, y: 0, width: width, height: height)], size: CGSize(width: width, height: height)) }
        if arrangement == .automatic, width >= 700, count <= 3 {
            let usableWidth = width - gap
            let left = usableWidth * ChatSplitLayout.columnFraction(columnFraction, available: usableWidth)
            let right = usableWidth - left
            let totalHeight = max(height, count == 3 ? 480 : 260)
            var frames = [CGRect(x: 0, y: 0, width: left, height: totalHeight)]
            var dividers = [CGRect(x: left, y: 0, width: gap, height: totalHeight)]
            if count == 2 {
                frames.append(CGRect(x: left + gap, y: 0, width: right, height: totalHeight))
            } else {
                let top = (totalHeight - gap) * ChatSplitLayout.fraction(rowFraction)
                frames.append(CGRect(x: left + gap, y: 0, width: right, height: top))
                frames.append(CGRect(x: left + gap, y: top + gap, width: right, height: totalHeight - gap - top))
                dividers.append(CGRect(x: left + gap, y: top, width: right, height: gap))
            }
            return Self(frames: frames, size: CGSize(width: width, height: totalHeight), dividers: dividers)
        }
        if arrangement == .automatic, width < 700, count == 2 {
            let totalHeight = max(300, height)
            let top = ChatSplitLayout.paneHeight(available: totalHeight - gap, fraction: rowFraction)
            return Self(frames: [CGRect(x: 0, y: top + gap, width: width, height: totalHeight - top - gap),
                                 CGRect(x: 0, y: 0, width: width, height: top)],
                        size: CGSize(width: width, height: totalHeight),
                        dividers: [CGRect(x: 0, y: top, width: width, height: gap)])
        }
        let columns: Int
        switch arrangement {
        case .columns: columns = count
        case .rows: columns = 1
        case .automatic, .grid: columns = width >= 700 ? 2 : 1
        }
        let rows = (count + columns - 1) / columns
        let cellWidth = max(min(width, 320), (width - CGFloat(columns - 1) * gap) / CGFloat(columns))
        let cellHeight = max(300, (height - CGFloat(rows - 1) * gap) / CGFloat(rows))
        let frames = (0..<count).map { index in
            CGRect(x: CGFloat(index % columns) * (cellWidth + gap), y: CGFloat(index / columns) * (cellHeight + gap), width: cellWidth, height: cellHeight)
        }
        return Self(frames: frames, size: CGSize(width: CGFloat(columns) * (cellWidth + gap) - gap,
                                                height: CGFloat(rows) * (cellHeight + gap) - gap))
    }
}

struct WorkspaceCanvas<Primary: View>: View {
    @Binding var panes: [WorkspacePane]
    let arrangement: WorkspaceArrangement
    let api: APIClient
    let botID: String
    let botName: String
    @ViewBuilder let primary: () -> Primary
    @State private var columnFraction = 0.45
    @State private var rowFraction = 0.45

    var body: some View { PaneSurfaceHost { surface } }

    private var surface: some View {
        GeometryReader { proxy in
            let layout = WorkspaceGeometry.make(size: proxy.size, count: panes.count + 1, arrangement: arrangement,
                                                columnFraction: columnFraction, rowFraction: rowFraction)
            let axes: Axis.Set = [layout.size.width > proxy.size.width + 1 ? .horizontal : [],
                                  layout.size.height > proxy.size.height + 1 ? .vertical : []]
            ScrollView(axes) {
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        if !panes.isEmpty {
                            HStack {
                                Label("Chat".localized, systemImage: "bubble.left").font(.subheadline.weight(.medium))
                                Spacer()
                                Text(botName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }.padding(.horizontal, 14).frame(height: 44).background(Theme.surface)
                            Divider()
                        }
                        primary()
                    }.background(Theme.canvas).paneFrame(layout.frames[0])
                    ForEach(panes) { pane in
                        if let index = panes.firstIndex(where: { $0.id == pane.id }) {
                            ChatWorkspacePane(api: api, botID: botID, tool: pane.tool,
                                move: { direction in move(pane.id, direction: direction) },
                                close: { panes.removeAll { $0.id == pane.id } })
                                .paneFrame(layout.frames[index + 1])
                        }
                    }
                    ForEach(Array(layout.dividers.enumerated()), id: \.offset) { index, frame in
                        let vertical = frame.width == 24
                        ChatPaneDivider(fraction: vertical ? $columnFraction : $rowFraction,
                                        vertical: vertical,
                                        available: vertical ? layout.size.width - 24 : layout.size.height - 24)
                            .paneFrame(frame)
                    }
                }.frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
                    .coordinateSpace(name: "chatSplit")
            }.contentMargins(0, for: .scrollContent).scrollBounceBehavior(.basedOnSize)
        }.background(Theme.surface).clipped()
    }
    private func move(_ id: UUID, direction: Int) {
        guard let index = panes.firstIndex(where: { $0.id == id }), panes.indices.contains(index + direction) else { return }
        panes.swapAt(index, index + direction)
    }
}

/// UIKit resets inherited navigation safe-area insets once, at the workspace
/// boundary. All child panes then lay out in their actual available rectangle.
private struct PaneSurfaceHost<Content: View>: UIViewControllerRepresentable {
    @Environment(AppStore.self) private var store
    @Environment(\.appAccent) private var accent
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @ViewBuilder let content: () -> Content
    private var root: some View {
        content().environment(store).environment(\.appAccent, accent).tint(accent)
            .environment(\.scenePhase, scenePhase).environment(\.colorScheme, colorScheme).environment(\.locale, locale)
    }
    func makeUIViewController(context: Context) -> UIHostingController<AnyView> {
        let controller = UIHostingController(rootView: AnyView(root))
        controller.safeAreaRegions = []
        controller.view.backgroundColor = .clear
        return controller
    }
    func updateUIViewController(_ controller: UIHostingController<AnyView>, context: Context) {
        controller.rootView = AnyView(root)
    }
}

private extension View {
    func paneFrame(_ rect: CGRect) -> some View {
        frame(width: rect.width, height: rect.height).clipped().offset(x: rect.minX, y: rect.minY)
    }
}

struct ChatWorkspacePane: View {
    let api: APIClient
    let botID: String
    let tool: ChatWorkspaceTool
    let move: (Int) -> Void
    let close: () -> Void
    @State private var desktop: DesktopModel
    @State private var terminalID = UUID()

    init(api: APIClient, botID: String, tool: ChatWorkspaceTool,
         move: @escaping (Int) -> Void, close: @escaping () -> Void) {
        self.api = api; self.botID = botID; self.tool = tool; self.move = move; self.close = close
        let model = DesktopModel(api: api, botID: botID)
        model.setViewOnly(true)
        _desktop = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Menu {
                    Button("Move earlier".localized, systemImage: "arrow.up") { move(-1) }
                    Button("Move later".localized, systemImage: "arrow.down") { move(1) }
                } label: {
                    Label(tool.title.localized, systemImage: tool.symbol)
                        .font(.subheadline.weight(.medium)).lineLimit(1)
                }
                Spacer(minLength: 4)
                if tool == .desktop { DesktopModeButton(model: desktop) }
                if tool == .terminal { TerminalKeyboardButton() }
                if tool == .desktop || tool == .terminal {
                    Button {
                        if tool == .desktop { Task { desktop.disconnect(); await desktop.connect() } }
                        else { terminalID = UUID() }
                    } label: { Image(systemName: "arrow.clockwise").frame(width: 40, height: 44) }
                        .accessibilityLabel((tool == .desktop ? "Reconnect desktop" : "Reconnect terminal").localized)
                }
                Button(action: close) { Image(systemName: "xmark").frame(width: 40, height: 44) }
                    .accessibilityLabel("Close pane".localized)
            }.buttonStyle(.plain).padding(.leading, 14).padding(.trailing, 4)
                .frame(height: 44).background(Theme.surface)
            Divider()
            switch tool {
            case .desktop:
                if api.isDemo { EmptyState(title: "Desktop unavailable", symbol: tool.symbol, detail: "Connect to a server to use this agent’s desktop.") }
                else { DesktopContent(model: desktop, embedded: true) }
            case .terminal:
                TerminalScreen(botID: botID, embedded: true).id(terminalID)
            case .files:
                PaneFiles(botID: botID)
            case .chat:
                PaneConversationPicker(initialBotID: botID)
            }
        }.background(Theme.canvas).clipped()
    }
}

private struct PaneFiles: View {
    let botID: String
    @State private var path = "/data"
    @State private var selectedFile: Record?
    var body: some View {
        FileBrowserView(botID: botID, path: path, embedded: true, openFile: { file in
            if file.value["isDir"].bool { path = file.value["path"].string }
            else { selectedFile = file }
        }, goBack: path == "/data" ? nil : { path = (path as NSString).deletingLastPathComponent })
            .id(path)
            .sheet(item: $selectedFile) { file in
                NavigationStack {
                    FileEditorView(botID: botID, path: file.value["path"].string, onClose: { selectedFile = nil })
                }
            }
    }
}

private struct PaneConversationPicker: View {
    @Environment(AppStore.self) private var store
    let initialBotID: String
    @State private var botID = ""
    @State private var sessions: [Record] = []
    @State private var selection: ChatDestination?
    @State private var error: String?
    @State private var newChat = false
    var body: some View {
        VStack(spacing: 0) {
            if let route = selection, let api = store.api {
                HStack {
                    Button { selection = nil } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                        .accessibilityLabel("Choose a conversation".localized)
                    Text(route.title).font(.subheadline).lineLimit(1)
                    Spacer()
                }.background(Theme.surface)
                ChatContent(model: ChatModel(api: api, botID: route.botID, sessionID: route.sessionID), destination: route, allowsWorkspace: false)
                    .id(route.sessionID)
            } else {
                List {
                    Picker("Agent".localized, selection: $botID) {
                        ForEach(store.bots) { bot in Text(bot.title).tag(bot.id) }
                    }
                    Button("New conversation".localized, systemImage: "square.and.pencil") { newChat = true }
                    if let error { ErrorBanner(message: error) }
                    ForEach(sessions) { session in
                        Button(session.title) {
                            selection = ChatDestination(botID: botID, sessionID: session.id, title: session.title,
                                                        botName: store.bots.first { $0.id == botID }?.title ?? "Agent")
                        }.foregroundStyle(.primary)
                    }
                }
            }
        }
        .onAppear { if botID.isEmpty { botID = initialBotID } }
        .task(id: botID) {
            guard !botID.isEmpty else { return }
            sessions = []; error = nil
            do {
                let result = try await store.api?.call("/bots/\(botID.pathComponent)/sessions", query: ["types": "chat,discuss,acp_agent", "limit": "50"]).items.map(Record.init) ?? []
                if !Task.isCancelled { sessions = result }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
        .sheet(isPresented: $newChat) { NewConversationView(botID: botID) { selection = $0 } }
    }
}

struct DesktopModeButton: View {
    let model: DesktopModel
    var body: some View {
        Button { model.setViewOnly(!model.viewOnly) } label: {
            Label((model.viewOnly ? "View only" : "Control").localized,
                  systemImage: model.viewOnly ? "eye" : "hand.point.up.left")
                .font(.caption.weight(.medium)).lineLimit(1).padding(.horizontal, 8).frame(minHeight: 44)
        }.buttonStyle(.plain)
            .accessibilityLabel("View only".localized)
            .accessibilityValue((model.viewOnly ? "On" : "Off").localized)
            .accessibilityIdentifier("desktopViewOnly")
    }
}

/// A generous hit area around a quiet handle; also adjustable with VoiceOver.
struct ChatPaneDivider: View {
    @Binding var fraction: Double
    let vertical: Bool
    let available: CGFloat
    @State private var startFraction: Double?

    private func clamped(_ value: Double) -> Double {
        vertical ? ChatSplitLayout.columnFraction(value, available: available) : ChatSplitLayout.fraction(value)
    }

    var body: some View {
        Capsule().fill(.tertiary)
            .frame(width: vertical ? 4 : 32, height: vertical ? 32 : 4)
            .frame(maxWidth: vertical ? nil : .infinity, maxHeight: vertical ? .infinity : nil)
            .frame(width: vertical ? 24 : nil, height: vertical ? nil : 24)
            .background(Theme.surface).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("chatSplit")).onChanged { value in
                if startFraction == nil { startFraction = clamped(fraction) }
                let translation = vertical ? value.translation.width : value.translation.height
                fraction = clamped((startFraction ?? fraction) + translation / max(available, 1))
            }.onEnded { _ in startFraction = nil })
            .accessibilityElement().accessibilityLabel("Resize split view".localized)
            .accessibilityValue(Text(clamped(fraction), format: .percent.precision(.fractionLength(0))))
            .accessibilityAdjustableAction { direction in
                fraction = clamped(clamped(fraction) + (direction == .increment ? 0.05 : -0.05))
            }
    }
}
