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

enum ChatWorkspaceTool: String, CaseIterable, Identifiable, Codable {
    case chat, files, terminal, desktop
    var id: Self { self }
    var title: String { switch self { case .chat: "Chat"; case .files: "Files"; case .terminal: "Terminal"; case .desktop: "Desktop" } }
    var symbol: String { switch self { case .chat: "bubble.left"; case .files: "folder"; case .terminal: "terminal"; case .desktop: "desktopcomputer" } }
}

struct WorkspacePane: Identifiable, Equatable, Codable {
    var id = UUID()
    var tool: ChatWorkspaceTool
    var botID = ""
    var conversation: ChatDestination?
    var directory = "/data"
    var viewOnly = true
}

struct WorkspaceSnapshot: Codable, Equatable {
    var primaryID = UUID()
    var conversation: ChatDestination?
    var panes: [WorkspacePane] = []
    var arrangement = WorkspaceArrangement.automatic
    var primaryIndex = 0
    var columnFraction = 0.45
    var rowFraction = 0.45
    var orderedIDs: [UUID] {
        var ids = panes.map(\.id)
        ids.insert(primaryID, at: min(max(0, primaryIndex), ids.count))
        return ids
    }
    mutating func move(_ source: UUID, to target: UUID) {
        var ids = orderedIDs
        guard let from = ids.firstIndex(of: source), let to = ids.firstIndex(of: target), from != to else { return }
        ids.remove(at: from); ids.insert(source, at: to)
        primaryIndex = ids.firstIndex(of: primaryID) ?? 0
        let existing = Dictionary(uniqueKeysWithValues: panes.map { ($0.id, $0) })
        panes = ids.compactMap { existing[$0] }
    }
    mutating func remove(_ id: UUID) {
        let order = orderedIDs.filter { $0 != id }
        panes.removeAll { $0.id == id }
        primaryIndex = order.firstIndex(of: primaryID) ?? 0
    }
}

@MainActor @Observable final class AgentWorkspaceState {
    var snapshot: WorkspaceSnapshot { didSet { persist() } }
    private let key: String
    private let defaults: UserDefaults
    init(scope: String, botID: String, defaults: UserDefaults = .standard) {
        key = "agent-workspace." + Data((scope + "|" + botID).utf8).base64EncodedString()
        self.defaults = defaults
        snapshot = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(WorkspaceSnapshot.self, from: $0) } ?? WorkspaceSnapshot()
    }
    private func persist() {
        // ChatDestination deliberately excludes unsent attachments/messages from disk.
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: key) }
    }
}

enum WorkspaceArrangement: String, CaseIterable, Identifiable, Codable {
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
    @Binding var workspace: WorkspaceSnapshot
    let api: APIClient
    let botID: String
    let botName: String
    @ViewBuilder let primary: () -> Primary

    var body: some View { PaneSurfaceHost { surface } }
    private var surface: some View {
        GeometryReader { proxy in
            let layout = WorkspaceGeometry.make(size: proxy.size, count: workspace.panes.count + 1, arrangement: workspace.arrangement,
                                                columnFraction: workspace.columnFraction, rowFraction: workspace.rowFraction)
            let order = workspace.orderedIDs
            let axes: Axis.Set = [layout.size.width > proxy.size.width + 1 ? .horizontal : [],
                                  layout.size.height > proxy.size.height + 1 ? .vertical : []]
            ScrollView(axes) {
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        if !workspace.panes.isEmpty {
                            HStack {
                                paneHandle(workspace.primaryID)
                                Label("Chat".localized, systemImage: "bubble.left").font(.subheadline.weight(.medium))
                                Spacer()
                                Text(botName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }.padding(.trailing, 14).frame(height: 44).background(Theme.surface)
                            Divider()
                        }
                        primary()
                    }.background(Theme.canvas)
                        .dropDestination(for: String.self) { values, _ in drop(values, onto: workspace.primaryID) }
                        .paneFrame(layout.frames[order.firstIndex(of: workspace.primaryID) ?? 0])
                    ForEach($workspace.panes) { $pane in
                        if let index = order.firstIndex(of: pane.id) {
                            ChatWorkspacePane(api: api, defaultBotID: botID, pane: $pane,
                                move: { direction in
                                    let ids = workspace.orderedIDs
                                    if let current = ids.firstIndex(of: pane.id), ids.indices.contains(current + direction) {
                                        workspace.move(pane.id, to: ids[current + direction])
                                    }
                                }, close: { workspace.remove(pane.id) })
                                .id(pane.id.uuidString + pane.botID + pane.tool.rawValue)
                                .dropDestination(for: String.self) { values, _ in drop(values, onto: pane.id) }
                                .paneFrame(layout.frames[index])
                        }
                    }
                    ForEach(Array(layout.dividers.enumerated()), id: \.offset) { _, frame in
                        let vertical = frame.width == 24
                        ChatPaneDivider(fraction: vertical ? $workspace.columnFraction : $workspace.rowFraction,
                                        vertical: vertical, available: vertical ? layout.size.width - 24 : layout.size.height - 24)
                            .paneFrame(frame)
                    }
                }.frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
                    .coordinateSpace(name: "chatSplit")
            }.contentMargins(0, for: .scrollContent).scrollBounceBehavior(.basedOnSize)
        }.background(Theme.surface).clipped()
    }
    private func drop(_ values: [String], onto target: UUID) -> Bool {
        guard let value = values.first, value.hasPrefix("homem-pane:"),
              let source = UUID(uuidString: String(value.dropFirst("homem-pane:".count))),
              workspace.orderedIDs.contains(source), source != target else { return false }
        workspace.move(source, to: target); return true
    }
    private func paneHandle(_ id: UUID) -> some View {
        Image(systemName: "line.3.horizontal").foregroundStyle(.secondary).frame(width: 40, height: 44)
            .contentShape(Rectangle()).draggable("homem-pane:" + id.uuidString)
            .accessibilityLabel("Drag pane".localized)
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
    @Environment(AppStore.self) private var store
    let api: APIClient
    let defaultBotID: String
    @Binding var pane: WorkspacePane
    let move: (Int) -> Void
    let close: () -> Void
    @State private var desktop: DesktopModel
    @State private var terminalID = UUID()
    private var botID: String { pane.botID.nonEmpty ?? defaultBotID }
    private var tool: ChatWorkspaceTool { pane.tool }
    init(api: APIClient, defaultBotID: String, pane: Binding<WorkspacePane>, move: @escaping (Int) -> Void, close: @escaping () -> Void) {
        self.api = api; self.defaultBotID = defaultBotID; _pane = pane; self.move = move; self.close = close
        let model = DesktopModel(api: api, botID: pane.wrappedValue.botID.nonEmpty ?? defaultBotID)
        model.setViewOnly(pane.wrappedValue.viewOnly)
        _desktop = State(initialValue: model)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Image(systemName: "line.3.horizontal").foregroundStyle(.secondary).frame(width: 36, height: 44)
                    .contentShape(Rectangle()).draggable("homem-pane:" + pane.id.uuidString)
                    .accessibilityLabel("Drag pane".localized)
                Menu {
                    Picker("Show".localized, selection: $pane.tool) {
                        ForEach(ChatWorkspaceTool.allCases) { item in Label(item.title.localized, systemImage: item.symbol).tag(item) }
                    }
                    Picker("Agent".localized, selection: Binding(get: { botID }, set: { pane.botID = $0; pane.conversation = nil; pane.directory = "/data" })) {
                        ForEach(store.bots) { bot in Text(bot.title).tag(bot.id) }
                    }
                    Button("Move earlier".localized, systemImage: "arrow.up") { move(-1) }
                    Button("Move later".localized, systemImage: "arrow.down") { move(1) }
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Label(tool.title.localized, systemImage: tool.symbol).font(.subheadline.weight(.medium)).lineLimit(1)
                        Text(store.bots.first { $0.id == botID }?.title ?? "Agent".localized).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }.accessibilityLabel("Switch pane".localized)
                Spacer(minLength: 4)
                if tool == .desktop { DesktopModeButton(model: desktop) }
                if tool == .desktop || tool == .terminal {
                    Button {
                        if tool == .desktop { Task { desktop.disconnect(); await desktop.connect() } }
                        else { terminalID = UUID() }
                    } label: { Image(systemName: "arrow.clockwise").frame(width: 40, height: 44) }
                        .accessibilityLabel((tool == .desktop ? "Reconnect desktop" : "Reconnect terminal").localized)
                }
                Button(action: close) { Image(systemName: "xmark").frame(width: 40, height: 44) }.accessibilityLabel("Close pane".localized)
            }.buttonStyle(.plain).padding(.trailing, 4).frame(height: 44).background(Theme.surface)
            Divider()
            switch tool {
            case .desktop:
                if api.isDemo { EmptyState(title: "Desktop unavailable", symbol: tool.symbol, detail: "Connect to a server to use this agent’s desktop.") }
                else { DesktopContent(model: desktop, embedded: true) }
            case .terminal: TerminalScreen(botID: botID, embedded: true).id(terminalID)
            case .files: PaneFiles(botID: botID, path: $pane.directory)
            case .chat: PaneConversationPicker(initialBotID: botID, selection: $pane.conversation)
            }
        }.background(Theme.canvas).clipped()
            .onChange(of: desktop.viewOnly) { _, value in pane.viewOnly = value }
    }
}

private struct PaneFiles: View {
    let botID: String
    @Binding var path: String
    @State private var selectedFile: Record?
    var body: some View {
        FileBrowserView(botID: botID, path: path, embedded: true, openFile: { file in
            if file.value["isDir"].bool { path = file.value["path"].string }
            else { selectedFile = file }
        }, goBack: path == "/data" ? nil : { path = (path as NSString).deletingLastPathComponent })
            .id(path)
            .sheet(item: $selectedFile) { file in
                NavigationStack { FileEditorView(botID: botID, path: file.value["path"].string, onClose: { selectedFile = nil }) }
            }
    }
}

private struct PaneConversationPicker: View {
    @Environment(AppStore.self) private var store
    let initialBotID: String
    @Binding var selection: ChatDestination?
    @State private var botID = ""
    @State private var sessions: [Record] = []
    @State private var error: String?
    @State private var newChat = false
    var body: some View {
        VStack(spacing: 0) {
            if let route = selection, let api = store.api {
                HStack {
                    Button { selection = nil } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("Choose a conversation".localized)
                    Text(route.title).font(.subheadline).lineLimit(1)
                    Spacer()
                }.background(Theme.surface)
                ChatContent(model: ChatModel(api: api, botID: route.botID, sessionID: route.sessionID), destination: route, allowsWorkspace: false,
                            onFirstMessageQueued: { if selection?.sessionID == route.sessionID { selection?.firstMessage = nil } }).id(route.sessionID)
            } else {
                List {
                    Picker("Agent".localized, selection: $botID) { ForEach(store.bots) { bot in Text(bot.title).tag(bot.id) } }
                    Button("New conversation".localized, systemImage: "square.and.pencil") { newChat = true }
                    if let error { ErrorBanner(message: error) }
                    ForEach(sessions) { session in
                        Button(session.title) { selection = ChatDestination(botID: botID, sessionID: session.id, title: session.title, botName: store.bots.first { $0.id == botID }?.title ?? "Agent") }.foregroundStyle(.primary)
                    }
                }
            }
        }
        .onAppear { if botID.isEmpty { botID = selection?.botID ?? initialBotID } }
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
