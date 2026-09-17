import SwiftUI

struct HomeShell: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TabView {
            ConversationsView().tabItem { Label("Chats", systemImage: "bubble.left.and.bubble.right") }
            NavigationStack { AgentsView() }.tabItem { Label("Agents", systemImage: "square.grid.2x2") }
            NavigationStack { LibraryView() }.tabItem { Label("Library", systemImage: "books.vertical") }
            NavigationStack { SettingsView() }.tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        }
        .task { await store.reload() }
        .onChange(of: scenePhase) { _, value in if value == .active { Task { await store.reload() } } }
        .alert("Sign in again", isPresented: Binding(get: { store.api?.unauthorized == true }, set: { _ in })) {
            Button("Sign in") { store.signOut() }
        } message: { Text("Your Memoh session has expired. Sign in to reconnect to your server.") }
    }
}

struct LibraryView: View {
    @Environment(\.appAccent) private var accent
    @Environment(AppStore.self) private var store
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "square.stack.3d.up.fill").font(.largeTitle).foregroundStyle(accent)
                    Text("More possibility.\nLess busywork.").font(.title2.weight(.bold))
                    Text("Memories, recurring work, and tools that make your agents yours.").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 12)
            }
            if !store.bots.isEmpty {
                if let bot = store.selectedBot {
                    Section {
                        ResourceLink(title: "Memories", icon: "brain", spec: .memory(bot.id))
                        ResourceLink(title: "Schedules", icon: "clock.arrow.circlepath", spec: .schedules(bot.id))
                        ResourceLink(title: "Skills", icon: "sparkles", spec: .skills(bot.id))
                        ResourceLink(title: "Installed apps", icon: "square.stack.3d.up", spec: .apps(bot.id))
                        ResourceLink(title: "MCP connections", icon: "point.3.connected.trianglepath.dotted", spec: .mcp(bot.id))
                    }
                }
            }
            Section("Discover") {
                NavigationLink { MarketplaceView() } label: { Label("Supermarket", systemImage: "storefront") }
            }
            if store.isDemo { Section { DemoBadge() } }
        }.navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    AgentPickerMenu(selection: Binding(get: { store.selectedBot?.id ?? "" }, set: { store.selectedBotID = $0 }))
                }
            }
    }
}

struct BotPicker: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        @Bindable var store = store
        Picker("Agent", selection: $store.selectedBotID) { ForEach(store.bots) { bot in Text(bot.title).tag(bot.id) } }
    }
}

/// The same selected-agent menu anchors chat and workspace navigation.
struct AgentPickerMenu: View {
    @Environment(AppStore.self) private var store
    @Binding var selection: String
    private var selected: Record? { store.bots.first { $0.id == selection } }

    var body: some View {
        Menu {
            Picker("Agent", selection: $selection) {
                ForEach(store.bots) { bot in Text(bot.title).tag(bot.id) }
            }
        } label: {
            HStack(spacing: 5) {
                AgentAvatar(name: selected?.title ?? "Agent", size: 28)
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
            }.frame(minWidth: 44, minHeight: 44)
        }
        .disabled(store.bots.isEmpty)
        .accessibilityLabel("Choose agent")
        .accessibilityValue(selected?.title ?? "No agent selected")
        .accessibilityIdentifier("agentPickerMenu")
    }
}
