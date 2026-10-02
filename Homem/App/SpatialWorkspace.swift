import SwiftUI

/// Window values contain navigation only; credentials and unsent messages never
/// cross the scene restoration boundary. The ID restores this specific window.
struct WorkspaceWindowRoute: Codable, Hashable {
    var id = UUID()
    var scope: String
    var botID: String
    var tool: ChatWorkspaceTool
    var conversation: ChatDestination?
    var directory: String
    var viewOnly: Bool

    init(scope: String, botID: String, tool: ChatWorkspaceTool, conversation: ChatDestination? = nil,
         directory: String = "/data", viewOnly: Bool = true) {
        self.scope = scope; self.botID = botID; self.tool = tool
        self.conversation = conversation
        self.conversation?.firstMessage = nil
        self.directory = directory; self.viewOnly = viewOnly
    }
    @MainActor func belongs(to api: APIClient?) -> Bool { api?.draftScope == scope }
}

private struct WorkspaceSceneIDKey: EnvironmentKey {
    static let defaultValue: String? = nil
}
extension EnvironmentValues {
    var workspaceSceneID: String? {
        get { self[WorkspaceSceneIDKey.self] }
        set { self[WorkspaceSceneIDKey.self] = newValue }
    }
}

#if os(visionOS) || targetEnvironment(macCatalyst)
/// SwiftUI restores a separate identity for every main or detached window.
struct SpatialSceneRoot<Content: View>: View {
    @SceneStorage("workspaceSceneID") private var sceneID = UUID().uuidString
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().modifier(SpatialScenePresentation(sceneID: sceneID))
    }
}

/// Value-based tool windows restore their ID from the WindowGroup value instead
/// of reading SceneStorage while the system measures a not-yet-installed scene.
struct SpatialScenePresentation: ViewModifier {
    let sceneID: String
    func body(content: Content) -> some View {
        content.environment(\.workspaceSceneID, sceneID)
            #if os(visionOS)
            .environment(\.defaultMinListRowHeight, 60)
            #endif
    }
}

struct SpatialWorkspaceWindow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var windowStore: AppStore?
    let route: WorkspaceWindowRoute?
    var body: some View {
        Group {
            if let route, let windowStore, route.belongs(to: windowStore.api) {
                NavigationStack {
                    SpatialWindowContent(route: route)
                        #if os(visionOS)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                accountLabel(windowStore)
                            }
                        }
                        #endif
                }.environment(windowStore).id(windowStore.connectionID)
                    #if targetEnvironment(macCatalyst)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        VStack(spacing: 0) {
                            Divider()
                            accountLabel(windowStore)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                        }.background(Theme.canvas)
                    }
                    #endif
            } else {
                VStack(spacing: 24) {
                    ContentUnavailableView("Workspace unavailable".localized, systemImage: "rectangle.on.rectangle.slash",
                        description: Text("Open the workspace and reconnect to this account to use this window.".localized))
                    HStack(spacing: 20) {
                        Button("Open workspace".localized) { openWindow(id: "workspace") }
                        Button("Close window".localized) { dismiss() }
                    }.padding(.bottom, 32)
                }
            }
        }.frame(minWidth: 640, minHeight: 480)
            .task(id: (route?.id.uuidString ?? "") + store.connectionID.uuidString) {
                guard let route else { return }
                windowStore = try? store.windowStore(for: route)
                if let windowStore, windowStore.bots.isEmpty { await windowStore.reload() }
            }
    }
    private func accountLabel(_ windowStore: AppStore) -> some View {
        Label(windowStore.accountName, systemImage: "person.crop.circle")
            .labelStyle(.titleAndIcon).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            .help(windowStore.workspaceName)
            .accessibilityIdentifier("windowAccount")
    }
}

private struct SpatialWindowContent: View {
    @Environment(AppStore.self) private var store
    let route: WorkspaceWindowRoute
    @State private var directory: String
    @State private var conversation: ChatDestination?
    init(route: WorkspaceWindowRoute) {
        self.route = route
        _directory = State(initialValue: route.directory)
        _conversation = State(initialValue: route.conversation)
    }
    private var botName: String { store.bots.first { $0.id == route.botID }?.title ?? route.conversation?.botName ?? "Agent".localized }
    var body: some View {
        Group {
            switch route.tool {
            case .chat:
                if let conversation { ChatScreen(destination: conversation, onFirstMessageQueued: { self.conversation?.firstMessage = nil }) }
                else { PaneConversationPicker(initialBotID: route.botID, selection: $conversation) }
            case .files: PaneFiles(botID: route.botID, path: $directory)
            case .terminal: TerminalScreen(botID: route.botID)
            case .desktop: DesktopScreen(botID: route.botID, initialViewOnly: route.viewOnly)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("spatialContent_" + route.tool.rawValue)
        .accessibilityValue(store.accountName)
        .navigationTitle(route.tool == .chat ? (conversation?.title ?? "Chats".localized) : "\(route.tool.title.localized) · \(botName)")
        #if targetEnvironment(macCatalyst)
        .navigationBarTitleDisplayMode(.inline)
        .modifier(WorkspaceWindowFocus(botID: route.botID, conversation: conversation))
        #endif
        .toolbar {
            if route.tool != .chat {
                ToolbarItem(placement: .topBarTrailing) { SpatialWindowMenu(botID: route.botID) }
            }
        }
    }
}

/// Native buttons and menus supply system gaze feedback and keyboard access.
struct SpatialWindowMenu: View {
    let botID: String
    var conversation: ChatDestination? = nil
    var body: some View {
        Menu {
            WorkspaceWindowButtons(botID: botID, conversation: conversation)
        } label: { Label("New window".localized, systemImage: "macwindow.badge.plus") }
        .accessibilityIdentifier("spatialNewWindow")
    }
}

struct WorkspaceWindowButtons: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    let botID: String
    var conversation: ChatDestination? = nil
    var body: some View {
        ForEach(ChatWorkspaceTool.allCases) { tool in
            Button(tool.title.localized, systemImage: tool.symbol) {
                guard let route = store.workspaceWindowRoute(botID: botID, tool: tool,
                    conversation: tool == .chat ? conversation : nil) else { return }
                openWindow(id: "workspace-tool", value: route)
            }.accessibilityIdentifier("newWindow_" + tool.rawValue)
        }
    }
}

#if targetEnvironment(macCatalyst)
private struct WorkspaceWindowActions {
    let open: (ChatWorkspaceTool) -> Void
}
private struct WorkspaceWindowActionsKey: FocusedValueKey {
    typealias Value = WorkspaceWindowActions
}
private extension FocusedValues {
    var workspaceWindows: WorkspaceWindowActions? {
        get { self[WorkspaceWindowActionsKey.self] }
        set { self[WorkspaceWindowActionsKey.self] = newValue }
    }
}

struct WorkspaceWindowFocus: ViewModifier {
    @Environment(AppStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    let botID: String
    var conversation: ChatDestination? = nil
    func body(content: Content) -> some View {
        content.focusedSceneValue(\.workspaceWindows, WorkspaceWindowActions { tool in
            guard let route = store.workspaceWindowRoute(botID: botID, tool: tool,
                conversation: tool == .chat ? conversation : nil) else { return }
            openWindow(id: "workspace-tool", value: route)
        })
    }
}

struct WorkspaceWindowCommands: Commands {
    @FocusedValue(\.workspaceWindows) private var windows
    var body: some Commands {
        CommandMenu("Workspace".localized) {
            Section("New window".localized) {
                ForEach(ChatWorkspaceTool.allCases) { tool in
                    Button(tool.title.localized, systemImage: tool.symbol) { windows?.open(tool) }
                        .keyboardShortcut(shortcut(for: tool), modifiers: [.command, .shift])
                        .disabled(windows == nil)
                }
            }
        }
    }
    private func shortcut(for tool: ChatWorkspaceTool) -> KeyEquivalent {
        switch tool {
        case .chat: "n"
        case .files: "f"
        case .terminal: "t"
        case .desktop: "d"
        }
    }
}
#endif
#endif
