import SwiftUI

@main struct HomemApp: App {
    @State private var store = AppStore()
    @AppStorage("appearance") private var appearance = "system"
    var body: some Scene {
        WindowGroup {
            Group {
                if store.api != nil { HomeShell().id(store.api!.baseURL.absoluteString) }
                else { ConnectionView() }
            }
            .environment(store)
            .tint(Theme.accent)
            .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
        }
    }
}
