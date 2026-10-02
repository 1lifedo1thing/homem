import SwiftUI
import AppKit

@main struct HomemMacApp: App {
    @State private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup("Homem", id: "workspace") {
            MacRoot().environment(store)
                .frame(minWidth: 820, minHeight: 540)
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unifiedCompact)
        .commands { MacWorkspaceCommands() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refreshSyncedAccounts() }
        }
        WindowGroup("Workspace", id: "workspace-tool", for: WorkspaceWindowRoute.self) { $route in
            MacDetachedWindow(route: route).environment(store)
                .frame(minWidth: 420, minHeight: 320)
        }
        .defaultSize(width: 900, height: 660)
        .windowToolbarStyle(.unifiedCompact)
        Settings { MacAccountSettings().environment(store).frame(width: 520, height: 380) }
    }
}

/// Metrics used by the shared, persisted split layout. Mac panes use system dividers.
enum Theme {
    static let minimumPaneWidth: CGFloat = 320
    static let paneGap: CGFloat = 1
}

struct MacWindowActions {
    var newChat: () -> Void
    var openTool: (ChatWorkspaceTool) -> Void
    var split: (ChatWorkspaceTool) -> Void
}
private struct MacWindowActionsKey: FocusedValueKey { typealias Value = MacWindowActions }
extension FocusedValues {
    var macWorkspace: MacWindowActions? {
        get { self[MacWindowActionsKey.self] }
        set { self[MacWindowActionsKey.self] = newValue }
    }
}
struct MacWorkspaceCommands: Commands {
    @FocusedValue(\.macWorkspace) private var actions
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Conversation") { actions?.newChat() }.keyboardShortcut("n", modifiers: [.command, .shift]).disabled(actions == nil)
        }
        CommandMenu("Workspace") {
            ForEach(ChatWorkspaceTool.allCases) { tool in
                Button("Open \(tool.title) in New Window") { actions?.openTool(tool) }
                    .keyboardShortcut(key(tool), modifiers: [.command, .shift]).disabled(actions == nil)
            }
            Divider()
            ForEach(ChatWorkspaceTool.allCases) { tool in
                Button("Split with \(tool.title)") { actions?.split(tool) }.disabled(actions == nil)
            }
        }
    }
    private func key(_ tool: ChatWorkspaceTool) -> KeyEquivalent {
        switch tool { case .chat: "c"; case .files: "f"; case .terminal: "t"; case .desktop: "d" }
    }
}

struct MacRoot: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        Group {
            if let api = store.api {
                MacWorkspace(api: api).id(store.connectionID)
            } else { MacLogin() }
        }
        .task(id: store.connectionID) { if store.api != nil { await store.reload() } }
        .task {
            while !Task.isCancelled {
                store.refreshSyncedAccounts()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
    }
}

struct MacWorkspace: View {
    let api: APIClient
    @Environment(AppStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var sessions: [Record] = []
    @State private var search = ""
    @State private var section = "chats"
    @State private var loading = false
    @State private var error: String?
    @State private var newChat = false
    @State private var rename: Record?
    @State private var newTitle = ""
    @State private var delete: Record?
    @SceneStorage("nativeWindowID") private var windowID = UUID().uuidString
    private var botID: String { store.selectedBot?.id ?? "" }
    private var workspace: AgentWorkspaceState { store.chatWorkspace(for: botID, windowID: windowID) }
    private var conversation: ChatDestination? { workspace.snapshot.conversation }

    var body: some View {
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            Group {
                if section == "agents" { MacAgents(api: api) }
                else if section == "library", !botID.isEmpty { MacLibrary(api: api, botID: botID) }
                else if !botID.isEmpty { MacWorkspaceDetail(workspace: workspace, api: api, botID: botID, newChat: { newChat = true }) }
                else { ContentUnavailableView("No agents", systemImage: "person.2", description: Text("Create an agent on your Memoh server to get started.")) }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .navigationTitle(conversation?.title ?? store.selectedBot?.title ?? "Homem")
        .navigationSubtitle(store.workspaceName)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Menu {
                    ForEach(store.bots) { bot in
                        Button(bot.title) { store.selectedBotID = bot.id; section = "chats" }
                    }
                } label: { Label(store.selectedBot?.title ?? "Agents", systemImage: "person.crop.circle") }
                .help("Switch agent")
            }
            ToolbarItemGroup {
                Button { newChat = true } label: { Image(systemName: "square.and.pencil") }.help("New conversation")
                Menu {
                    ForEach(ChatWorkspaceTool.allCases) { tool in Button("Split with \(tool.title)", systemImage: tool.symbol) { split(tool) } }
                    Divider()
                    Picker("Arrangement", selection: Binding(get: { workspace.snapshot.arrangement }, set: { workspace.snapshot.arrangement = $0 })) {
                        Text("Side by side").tag(WorkspaceArrangement.columns)
                        Text("Stacked").tag(WorkspaceArrangement.rows)
                    }
                } label: { Image(systemName: "rectangle.split.2x1") }.help("Split workspace")
                Menu {
                    ForEach(ChatWorkspaceTool.allCases) { tool in Button("\(tool.title) Window", systemImage: tool.symbol) { open(tool) } }
                } label: { Image(systemName: "macwindow.badge.plus") }.help("Open a separate window")
            }
        }
        .focusedSceneValue(\.macWorkspace, MacWindowActions(newChat: { newChat = true }, openTool: open, split: split))
        .sheet(isPresented: $newChat) {
            MacNewConversation(api: api, botID: botID, botName: store.selectedBot?.title ?? "Agent") { destination in
                workspace.snapshot.conversation = destination; section = "chats"; Task { await load() }
            }
        }
        .alert("Rename Conversation", isPresented: Binding(get: { rename != nil }, set: { if !$0 { rename = nil } })) {
            TextField("Title", text: $newTitle)
            Button("Cancel", role: .cancel) { rename = nil }
            Button("Save") { if let item = rename { Task { await mutate(item, method: "PATCH", body: ["title": .string(newTitle)]) }; rename = nil } }
        }
        .alert("Delete Conversation?", isPresented: Binding(get: { delete != nil }, set: { if !$0 { delete = nil } })) {
            Button("Cancel", role: .cancel) { delete = nil }
            Button("Delete", role: .destructive) {
                if let item = delete { Task { await mutate(item, method: "DELETE") }; delete = nil }
            }
        } message: { Text("This removes the conversation from the server.") }
        .task(id: botID) { await load() }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            TextField("Search conversations", text: $search).textFieldStyle(.roundedBorder).padding(12)
            List(selection: Binding<String?>(get: {
                section == "chats" ? conversation.map { "session|" + $0.sessionID } ?? "chats" : section
            }, set: { value in
                guard let value else { return }
                if value.hasPrefix("session|"), let session = sessions.first(where: { "session|" + $0.id == value }) {
                    workspace.snapshot.conversation = route(session); section = "chats"
                } else { section = value }
            })) {
                Section {
                    Label("Chats", systemImage: "bubble.left.and.bubble.right").tag("chats")
                    Label("Agents", systemImage: "person.2").tag("agents")
                    Label("Library", systemImage: "books.vertical").tag("library")
                }
                Section("Recent Conversations") {
                    ForEach(sessions.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { session in
                        Label(session.title, systemImage: "bubble.left")
                            .lineLimit(1).padding(.vertical, 3).tag("session|" + session.id)
                        .contextMenu {
                            Button("Open in New Window") { openConversation(route(session)) }
                            Button("Open in Split") { workspace.snapshot.panes.append(WorkspacePane(tool: .chat, botID: botID, conversation: route(session))) }
                            Button("Rename") { newTitle = session.title; rename = session }
                            Button("Delete", role: .destructive) { delete = session }
                        }
                    }
                    if loading { ProgressView().controlSize(.small) }
                    if let error { Text(error).font(.caption).foregroundStyle(.red); Button("Retry") { Task { await load() } } }
                }
            }.listStyle(.sidebar)
            Divider()
            Menu {
                ForEach(store.savedAccounts) { account in
                    Button(account.name) { Task { do { try await store.switchAccount(account) } catch { self.error = error.localizedDescription } } }
                }
                if !store.workspaces.isEmpty {
                    Divider()
                    ForEach(Array(store.workspaces.enumerated()), id: \.offset) { _, team in
                        Button(team.text("name", "slug")) { Task { do { try await store.switchWorkspace(team) } catch { self.error = error.localizedDescription } } }
                    }
                }
                Divider()
                Button("Accounts & Settings…") { openSettings() }
            } label: {
                Text(store.accountName)
            }.menuStyle(.borderlessButton).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .accessibilityLabel("Account: \(store.accountName)")
        }
    }
    private func route(_ record: Record) -> ChatDestination {
        ChatDestination(botID: botID, sessionID: record.id, title: record.title, botName: store.selectedBot?.title ?? "Agent")
    }
    private func load() async {
        guard !botID.isEmpty else { return }
        let id = botID; loading = true; defer { loading = false }
        do {
            let records = try await api.call("/bots/\(id.pathComponent)/sessions", query: ["limit": "100"]).items.map(Record.init)
            guard id == botID else { return }; sessions = records; error = nil
        } catch { if id == botID { self.error = error.localizedDescription } }
    }
    private func mutate(_ item: Record, method: String, body: JSONValue? = nil) async {
        do {
            _ = try await api.call("/bots/\(botID.pathComponent)/sessions/\(item.id.pathComponent)", method: method, body: body)
            if conversation?.sessionID == item.id {
                if method == "DELETE" { workspace.snapshot.conversation = nil }
                else { workspace.snapshot.conversation?.title = newTitle }
            }
            await load()
        } catch { self.error = error.localizedDescription }
    }
    private func split(_ tool: ChatWorkspaceTool) {
        workspace.snapshot.panes.append(WorkspacePane(tool: tool, botID: botID, conversation: tool == .chat ? conversation : nil))
    }
    private func open(_ tool: ChatWorkspaceTool) {
        if let route = store.workspaceWindowRoute(botID: botID, tool: tool, conversation: tool == .chat ? conversation : nil) {
            openWindow(id: "workspace-tool", value: route)
        }
    }
    private func openConversation(_ destination: ChatDestination) {
        if let route = store.chatWindowRoute(for: destination) { openWindow(id: "workspace-tool", value: route) }
    }
}

struct MacWorkspaceDetail: View {
    @Bindable var workspace: AgentWorkspaceState
    let api: APIClient
    let botID: String
    let newChat: () -> Void
    var body: some View {
        Group {
            if workspace.snapshot.arrangement == .rows {
                VSplitView { panes }
            } else { HSplitView { panes } }
        }
    }
    @ViewBuilder private var panes: some View {
        MacPane(api: api, botID: botID, tool: .chat, conversation: workspace.snapshot.conversation, newChat: newChat)
            .frame(minWidth: 320, idealWidth: 520, maxWidth: .infinity, minHeight: 220)
            .background(MacSplitBalance(count: 1 + workspace.snapshot.panes.count))
        ForEach($workspace.snapshot.panes) { $pane in
            MacPane(api: api, botID: pane.botID.nonEmpty ?? botID, tool: pane.tool, conversation: pane.conversation, directory: pane.directory, newChat: newChat,
                    close: { workspace.snapshot.remove(pane.id) })
                .frame(minWidth: 300, idealWidth: 520, maxWidth: .infinity, minHeight: 220)
        }
    }
}

struct MacPane: View {
    let api: APIClient
    let botID: String
    let tool: ChatWorkspaceTool
    var conversation: ChatDestination?
    var directory = "/data"
    var newChat: () -> Void = {}
    var close: (() -> Void)?
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(conversation?.title ?? tool.title, systemImage: tool.symbol).lineLimit(1)
                Spacer()
                if let close { Button(action: close) { Image(systemName: "xmark") }.buttonStyle(.plain).help("Close pane") }
            }.font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).frame(height: 34).background(.bar)
            Divider()
            Group {
                switch tool {
                case .chat:
                    if let conversation { MacChat(api: api, destination: conversation).id(conversation.sessionID) }
                    else {
                        VStack(spacing: 16) {
                            MacAvatar(name: "Homem", size: 52)
                            Text("Start a conversation").font(.title2.weight(.semibold))
                            Text("Choose a recent chat or start something new.").foregroundStyle(.secondary)
                            Button("New Conversation", action: newChat).buttonStyle(.borderedProminent)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                case .files: MacFiles(api: api, botID: botID, initialPath: directory)
                case .terminal: MacTerminal(api: api, botID: botID)
                case .desktop: MacDesktop(api: api, botID: botID)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct MacDetachedWindow: View {
    var route: WorkspaceWindowRoute?
    @Environment(AppStore.self) private var launcher
    @Environment(\.openWindow) private var openWindow
    @State private var store: AppStore?
    @State private var error: String?
    @State private var newChat = false
    @State private var conversation: ChatDestination?
    @State private var panes: [WorkspacePane] = []
    var body: some View {
        Group {
            if let route, let store, let api = store.api, !api.signedOut, route.belongs(to: api) {
                HSplitView {
                    MacPane(api: api, botID: route.botID, tool: route.tool, conversation: conversation ?? route.conversation, directory: route.directory, newChat: { newChat = true }).frame(minWidth: 320, idealWidth: 520, maxWidth: .infinity)
                    ForEach(panes) { pane in
                        MacPane(api: api, botID: pane.botID, tool: pane.tool, conversation: pane.conversation, newChat: { newChat = true }, close: { panes.removeAll { $0.id == pane.id } }).frame(minWidth: 300, idealWidth: 520, maxWidth: .infinity)
                    }
                }
                    .environment(store)
                    .navigationTitle("\(route.tool.title) · \(store.bots.first { $0.id == route.botID }?.title ?? "Homem")")
                    .navigationSubtitle(store.accountName)
                    .focusedSceneValue(\.macWorkspace, MacWindowActions(newChat: { newChat = true }, openTool: { tool in
                        if let next = store.workspaceWindowRoute(botID: route.botID, tool: tool, conversation: tool == .chat ? conversation ?? route.conversation : nil) { openWindow(id: "workspace-tool", value: next) }
                    }, split: { tool in
                        panes.append(WorkspacePane(tool: tool, botID: route.botID, conversation: tool == .chat ? conversation ?? route.conversation : nil))
                    }))
                    .sheet(isPresented: $newChat) {
                        MacNewConversation(api: api, botID: route.botID, botName: store.bots.first { $0.id == route.botID }?.title ?? "Agent") { conversation = $0 }
                    }
            } else if let error { ContentUnavailableView("Workspace unavailable", systemImage: "lock", description: Text(error)) }
            else { ProgressView() }
        }
        .task(id: route) {
            guard let route else { error = "Open a tool from the Workspace menu."; return }
            do {
                store = try launcher.windowStore(for: route)
                if store == nil { error = "Sign in to this account again in Homem." }
                else { await store?.reload() }
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct MacAvatar: View {
    var name: String
    var size: CGFloat = 30
    var body: some View {
        Text(name.prefix(1).uppercased()).font(.system(size: size * 0.43, weight: .semibold))
            .frame(width: size, height: size).foregroundStyle(.white)
            .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }
}

/// Set an even starting position when a pane is added; AppKit retains subsequent
/// divider drags and resizing. This avoids a Table's intrinsic width squeezing chat.
private struct MacSplitBalance: NSViewRepresentable {
    let count: Int
    func makeNSView(context: Context) -> BalanceView { BalanceView() }
    func updateNSView(_ view: BalanceView, context: Context) { view.configure(count: count) }
    final class BalanceView: NSView {
        private var count = 1
        private var applied = 0
        func configure(count: Int) {
            guard self.count != count else { return }
            self.count = count; applied = 0; schedule()
        }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); schedule() }
        private func schedule() {
            guard count > 1 else { return }
            DispatchQueue.main.async { [weak self] in self?.balance(attempt: 0) }
        }
        private func balance(attempt: Int) {
            guard applied != count, count > 1, let content = window?.contentView else { return }
            let center = convert(NSPoint(x: bounds.midX, y: bounds.midY), to: content)
            func find(_ view: NSView) -> NSSplitView? {
                if let split = view as? NSSplitView, split.arrangedSubviews.count == count,
                   let first = split.arrangedSubviews.first,
                   first.convert(first.bounds, to: content).contains(center) { return split }
                for child in view.subviews { if let split = find(child) { return split } }
                return nil
            }
            if let split = find(content), (split.isVertical ? split.bounds.width : split.bounds.height) > 0 {
                let pane = convert(bounds, to: split)
                let start = split.isVertical ? pane.minX : pane.minY
                let end = split.isVertical ? split.bounds.maxX : split.bounds.maxY
                let available = end - start
                for divider in 0..<(count - 1) { split.setPosition(start + available * CGFloat(divider + 1) / CGFloat(count), ofDividerAt: divider) }
                applied = count
            } else if attempt < 3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.balance(attempt: attempt + 1) }
            }
        }
    }
}
