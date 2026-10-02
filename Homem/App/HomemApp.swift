import SwiftUI

@main struct HomemApp: App {
    @State private var store = AppStore()
    var body: some Scene {
        #if os(visionOS)
        WindowGroup(id: "workspace") {
            SpatialSceneRoot {
                root.frame(minWidth: 640, minHeight: 480)
            }.modifier(AppPresentation(store: store))
        }
        .defaultSize(width: 900, height: 720)
        .windowResizability(.contentMinSize)

        WindowGroup("Workspace".localized, id: "workspace-tool", for: WorkspaceWindowRoute.self) { $route in
            SpatialWorkspaceWindow(route: route)
                .modifier(SpatialScenePresentation(sceneID: route?.id.uuidString ?? "unconfigured-tool-window"))
                .modifier(AppPresentation(store: store))
        }
        .defaultSize(width: 960, height: 720)
        .windowResizability(.contentMinSize)
        #elseif targetEnvironment(macCatalyst)
        WindowGroup(id: "workspace") {
            SpatialSceneRoot { root.frame(minWidth: 760, minHeight: 560) }
                .modifier(AppPresentation(store: store))
        }
        .defaultSize(width: 1120, height: 800)

        WindowGroup("Workspace".localized, id: "workspace-tool", for: WorkspaceWindowRoute.self) { $route in
            SpatialWorkspaceWindow(route: route)
                .modifier(SpatialScenePresentation(sceneID: route?.id.uuidString ?? "unconfigured-tool-window"))
                .modifier(AppPresentation(store: store))
        }
        .defaultSize(width: 960, height: 720)
        #else
        WindowGroup { root.modifier(AppPresentation(store: store)) }
        #endif
    }
    private var root: some View {
        Group {
            if store.api != nil { HomeShell().id(store.connectionID) }
            else { ConnectionView() }
        }
        .modifier(SyncedAccountRefresh(store: store))
    }
}

private struct SyncedAccountRefresh: ViewModifier {
    let store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    func body(content: Content) -> some View {
        content
            .task {
                store.refreshSyncedAccounts()
                // Keychain may receive account metadata and its secret at
                // different times during a fresh device's first iCloud sync.
                for delay in [2, 6, 12] {
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled else { return }
                    store.refreshSyncedAccounts()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.refreshSyncedAccounts() }
            }
    }
}

private struct AppPresentation: ViewModifier {
    let store: AppStore
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("color-scheme") private var colorScheme = "system"
    func body(content: Content) -> some View {
        content.environment(store)
            .environment(\.appAccent, Theme.accent(for: colorScheme))
            .tint(Theme.accent(for: colorScheme))
            #if !os(visionOS)
            .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
            #endif
    }
}
