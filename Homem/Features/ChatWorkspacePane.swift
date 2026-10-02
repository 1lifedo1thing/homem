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

private struct PaneDragHandle: View {
    var changed: (DragGesture.Value) -> Void
    var ended: () -> Void
    var cancelled: () -> Void
    @GestureState private var active = false
    var body: some View {
        Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
            .frame(width: Theme.controlSize, height: Theme.controlSize).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 6, coordinateSpace: .named("chatSplit"))
                .updating($active) { _, state, _ in state = true }
                .onChanged(changed).onEnded { _ in ended() })
            .onChange(of: active) { _, value in if !value { cancelled() } }
            .accessibilityLabel("Drag pane".localized).spatialHoverEffect()
    }
}

/// Keep the familiar header intact; content interaction tucks it away. A centered
/// edge handle reveals pane controls without competing corner buttons.
private struct WorkspacePaneSurface<Header: View, Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var titlesVisible: Bool
    let enabled: Bool
    let autoHide: Bool
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            header()
                .frame(height: enabled && titlesVisible ? 44 : 0)
                .clipped().opacity(enabled && titlesVisible ? 1 : 0)
                .accessibilityHidden(!enabled || !titlesVisible)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .simultaneousGesture(TapGesture().onEnded { focusContent() })
                .simultaneousGesture(DragGesture(minimumDistance: 12).onEnded { _ in focusContent() })
        }
        .background(Theme.canvas)
        .overlay(alignment: .top) {
            if enabled && !titlesVisible {
                Button { setVisible(true) } label: {
                    Image(systemName: "chevron.compact.down")
                        .font(.system(size: 18, weight: .semibold)).foregroundStyle(.secondary)
                        .frame(width: 56, height: Theme.paneGap)
                        .background(.regularMaterial, in: Capsule())
                        .frame(width: 64, height: 44, alignment: .top).contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.top, 4)
                    .accessibilityLabel("Show pane bars".localized)
                    .accessibilityIdentifier("showWorkspaceTitles")
            }
        }
    }
    private func focusContent() {
        guard enabled, autoHide, titlesVisible else { return }
        setVisible(false)
    }
    private func setVisible(_ visible: Bool) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { titlesVisible = visible }
    }
}

private struct PaneLift: ViewModifier {
    let active: Bool
    let translation: CGSize
    let reduceMotion: Bool
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(active ? 0.18 : 0), radius: active ? 14 : 0, y: active ? 6 : 0)
            .opacity(active ? 0.86 : 1)
            .offset(active && !reduceMotion ? translation : .zero)
            .zIndex(active ? 3 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86), value: active)
    }
}

struct WorkspaceCanvas<Primary: View>: View {
    @Environment(\.appAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draggedID: UUID?
    @State private var dragTranslation = CGSize.zero
    @State private var proposal: PaneDropProposal?
    @State private var layoutRevision = 0
    private var motion: Animation? { reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86) }
    @Binding var workspace: WorkspaceSnapshot
    @Binding var titlesVisible: Bool
    let autoHideTitles: Bool
    let api: APIClient
    let botID: String
    let botName: String
    @ViewBuilder let primary: () -> Primary

    var body: some View {
        GeometryReader { proxy in
            // Read reserved regions before crossing the UIKit hosting boundary.
            PaneSurfaceHost { surface(division: activeDivision(in: proxy)) }
        }
    }
    private func activeDivision(in proxy: GeometryProxy) -> CGRect? {
        #if HOMEM_DUO_SDK
        if #available(iOS 27.1, *) {
            return proxy.reservedRegions(kind: .division, layoutDirectionBehavior: .fixed).first?.frame
        }
        #endif
        return nil
    }
    private func surface(division: CGRect?) -> some View {
        GeometryReader { proxy in
            let order = workspace.orderedIDs
            let layout = WorkspaceGeometry.make(size: proxy.size, count: workspace.panes.count + 1, arrangement: workspace.arrangement,
                                                columnFraction: workspace.columnFraction, rowFraction: workspace.rowFraction, division: division, docking: workspace.docking, order: order)
            let axes: Axis.Set = [layout.size.width > proxy.size.width + 1 ? .horizontal : [],
                                  layout.size.height > proxy.size.height + 1 ? .vertical : []]
            ScrollView(axes) {
                ZStack(alignment: .topLeading) {
                    WorkspacePaneSurface(titlesVisible: $titlesVisible, enabled: !workspace.panes.isEmpty, autoHide: autoHideTitles) {
                        HStack {
                            dragHandle(workspace.primaryID, layout: layout, viewport: proxy.size, division: division)
                            Label("Chat".localized, systemImage: "bubble.left").font(.subheadline.weight(.medium))
                            Spacer()
                            Text(botName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }.padding(.trailing, 14).frame(height: Theme.controlSize).background(Theme.surface)
                    } content: {
                        primary()
                    }
                        .paneFrame(layout.frames[order.firstIndex(of: workspace.primaryID) ?? 0])
                        .modifier(PaneLift(active: draggedID == workspace.primaryID, translation: dragTranslation, reduceMotion: reduceMotion))
                        .animation(motion, value: layoutRevision)
                    ForEach($workspace.panes) { $pane in
                        if let index = order.firstIndex(of: pane.id) {
                            ChatWorkspacePane(api: api, defaultBotID: botID, pane: $pane, titlesVisible: $titlesVisible, autoHideTitles: autoHideTitles,
                                move: { direction in
                                    let ids = workspace.orderedIDs
                                    if let current = ids.firstIndex(of: pane.id), ids.indices.contains(current + direction) {
                                        withAnimation(motion) { workspace.move(pane.id, to: ids[current + direction]); layoutRevision += 1 }
                                    }
                                }, close: { withAnimation(motion) { workspace.remove(pane.id); layoutRevision += 1 } },
                                dragChanged: { updateDrag(pane.id, value: $0, layout: layout, viewport: proxy.size, division: division) },
                                dragEnded: finishDrag, dragCancelled: cancelDrag)
                                .id(pane.id.uuidString + pane.botID + pane.tool.rawValue)
                                .paneFrame(layout.frames[index])
                                .modifier(PaneLift(active: draggedID == pane.id, translation: dragTranslation, reduceMotion: reduceMotion))
                                .animation(motion, value: layoutRevision)
                        }
                    }
                    ForEach(Array(layout.dividers.enumerated()), id: \.offset) { index, frame in
                        let vertical = frame.width == Theme.paneGap
                        ChatPaneDivider(fraction: dividerBinding(index, vertical: vertical, layout: layout),
                                        vertical: vertical, available: layout.dividerExtents.indices.contains(index) ? layout.dividerExtents[index] : (vertical ? layout.size.width - Theme.paneGap : layout.size.height - Theme.paneGap))
                            .paneFrame(frame)
                    }
                    if let proposal {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(accent.opacity(0.13))
                            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(accent, lineWidth: 2) }
                            .paneFrame(proposal.preview.insetBy(dx: 3, dy: 3))
                            .allowsHitTesting(false).accessibilityHidden(true).zIndex(2)
                            .animation(motion, value: proposal.preview)
                    }
                }.frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
                    .coordinateSpace(name: "chatSplit")
            }.contentMargins(0, for: .scrollContent).scrollBounceBehavior(.basedOnSize)
        }.background(Theme.surface).clipped()
    }
    private func dividerBinding(_ index: Int, vertical: Bool, layout: WorkspaceGeometry) -> Binding<Double> {
        if layout.dividerPaths.indices.contains(index) {
            let path = layout.dividerPaths[index]
            return Binding(get: { workspace.docking?.fraction(at: path) ?? 0.5 }, set: { workspace.docking?.setFraction($0, at: path) })
        }
        return vertical ? $workspace.columnFraction : $workspace.rowFraction
    }
    private func dragHandle(_ id: UUID, layout: WorkspaceGeometry, viewport: CGSize, division: CGRect?) -> some View {
        PaneDragHandle(changed: { updateDrag(id, value: $0, layout: layout, viewport: viewport, division: division) },
                       ended: finishDrag, cancelled: cancelDrag)
    }
    private func updateDrag(_ id: UUID, value: DragGesture.Value, layout: WorkspaceGeometry, viewport: CGSize, division: CGRect?) {
        draggedID = id
        dragTranslation = value.translation
        proposal = PaneDropProposal.make(source: id, location: value.location, workspace: workspace,
                                         layout: layout, viewport: viewport, division: division)
    }
    private func finishDrag() {
        withAnimation(motion) {
            if let id = draggedID, let proposal {
                if let docking = proposal.docking { workspace.docking = docking }
                else { workspace.move(id, to: proposal.target) }
                layoutRevision += 1
            }
            draggedID = nil; dragTranslation = .zero; proposal = nil
        }
    }
    private func cancelDrag() {
        withAnimation(motion) { draggedID = nil; dragTranslation = .zero; proposal = nil }
    }
}

/// UIKit resets inherited navigation safe-area insets once, at the workspace
/// boundary. All child panes then lay out in their actual available rectangle.
private struct PaneSurfaceHost<Content: View>: UIViewControllerRepresentable {
    @Environment(\.workspaceSceneID) private var workspaceSceneID
    @Environment(\.defaultMinListRowHeight) private var minimumRowHeight
    @Environment(AppStore.self) private var store
    @Environment(\.appAccent) private var accent
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @ViewBuilder let content: () -> Content
    private var root: some View {
        content().environment(store).environment(\.appAccent, accent).tint(accent)
            .environment(\.workspaceSceneID, workspaceSceneID)
            .environment(\.defaultMinListRowHeight, minimumRowHeight)
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
    @Binding var titlesVisible: Bool
    let autoHideTitles: Bool
    let move: (Int) -> Void
    let close: () -> Void
    let dragChanged: (DragGesture.Value) -> Void
    let dragEnded: () -> Void
    let dragCancelled: () -> Void
    @State private var desktop: DesktopModel
    @State private var terminalID = UUID()
    private var botID: String { pane.botID.nonEmpty ?? defaultBotID }
    private var tool: ChatWorkspaceTool { pane.tool }
    init(api: APIClient, defaultBotID: String, pane: Binding<WorkspacePane>, titlesVisible: Binding<Bool>, autoHideTitles: Bool, move: @escaping (Int) -> Void, close: @escaping () -> Void,
         dragChanged: @escaping (DragGesture.Value) -> Void, dragEnded: @escaping () -> Void, dragCancelled: @escaping () -> Void) {
        _titlesVisible = titlesVisible; self.autoHideTitles = autoHideTitles
        self.dragChanged = dragChanged; self.dragEnded = dragEnded; self.dragCancelled = dragCancelled
        self.api = api; self.defaultBotID = defaultBotID; _pane = pane; self.move = move; self.close = close
        let model = DesktopModel(api: api, botID: pane.wrappedValue.botID.nonEmpty ?? defaultBotID)
        model.setViewOnly(pane.wrappedValue.viewOnly)
        _desktop = State(initialValue: model)
    }
    var body: some View {
        WorkspacePaneSurface(titlesVisible: $titlesVisible, enabled: true, autoHide: autoHideTitles) {
            HStack(spacing: 0) {
                PaneDragHandle(changed: dragChanged, ended: dragEnded, cancelled: dragCancelled)
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
                    }.frame(minWidth: Theme.controlSize, minHeight: Theme.controlSize)
                }.accessibilityLabel("Switch pane".localized).spatialHoverEffect()
                Spacer(minLength: 4)
                if tool == .desktop { DesktopModeButton(model: desktop) }
                if tool == .desktop || tool == .terminal {
                    Button {
                        if tool == .desktop { Task { desktop.disconnect(); await desktop.connect() } }
                        else { terminalID = UUID() }
                    } label: { Image(systemName: "arrow.clockwise").frame(width: Theme.controlSize, height: Theme.controlSize) }
                        .accessibilityLabel((tool == .desktop ? "Reconnect desktop" : "Reconnect terminal").localized)
                }
                Button(action: close) { Image(systemName: "xmark").frame(width: Theme.controlSize, height: Theme.controlSize) }.accessibilityLabel("Close pane".localized).spatialHoverEffect()
            }.buttonStyle(.plain).padding(.trailing, 4).frame(height: Theme.controlSize).background(Theme.surface)
        } content: {
            switch tool {
            case .desktop:
                DesktopContent(model: desktop, embedded: true, onClosePane: close)
            case .terminal: TerminalScreen(botID: botID, embedded: true).id(terminalID)
            case .files: PaneFiles(botID: botID, path: $pane.directory)
            case .chat: PaneConversationPicker(initialBotID: botID, selection: $pane.conversation)
            }
        }.background(Theme.canvas).clipped()
            .onChange(of: desktop.viewOnly) { _, value in pane.viewOnly = value }
    }
}

struct PaneFiles: View {
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

struct PaneConversationPicker: View {
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
                .font(.caption.weight(.medium)).lineLimit(1).padding(.horizontal, 8).frame(minHeight: Theme.controlSize)
        }.buttonStyle(.plain)
            .accessibilityLabel("View only".localized)
            .accessibilityValue((model.viewOnly ? "On" : "Off").localized)
            .accessibilityIdentifier("desktopViewOnly").spatialHoverEffect()
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
            .frame(width: vertical ? Theme.paneGap : nil, height: vertical ? nil : Theme.paneGap)
            .background(Theme.surface).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("chatSplit")).onChanged { value in
                if startFraction == nil { startFraction = clamped(fraction) }
                let translation = vertical ? value.translation.width : value.translation.height
                fraction = clamped((startFraction ?? fraction) + translation / max(available, 1))
            }.onEnded { _ in startFraction = nil })
            .spatialHoverEffect()
            .accessibilityElement().accessibilityLabel("Resize split view".localized)
            .accessibilityValue(Text(clamped(fraction), format: .percent.precision(.fractionLength(0))))
            .accessibilityAdjustableAction { direction in
                fraction = clamped(clamped(fraction) + (direction == .increment ? 0.05 : -0.05))
            }
    }
}
