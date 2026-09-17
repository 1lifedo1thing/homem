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
                HStack(spacing: 14) {
                    AgentAvatar(name: store.selectedBot?.title ?? "Library", avatarURL: store.selectedBot?.value["avatar_url"].string ?? "", size: 36)
                    VStack(alignment: .leading, spacing: 5) {
                        Eyebrow(text: "AGENT")
                        Text(store.selectedBot?.title ?? "Library").font(.title2.bold())
                    }
                    Spacer()
                }.padding(.vertical, 8)
                WorkspaceIdentity()
            }.listRowBackground(Color.clear)

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
        }.scrollContentBackground(.hidden).background(Theme.canvas).navigationTitle("Library")
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
        HStack {
            Text("Agent")
            Spacer()
            Text(store.selectedBot?.title ?? "Choose an agent").foregroundStyle(.secondary)
            AgentPickerMenu(selection: Binding(get: { store.selectedBot?.id ?? "" }, set: { store.selectedBotID = $0 }))
        }
    }
}

/// A toolbar-anchored dropdown keeps real avatars visible in every option.
struct AgentPickerMenu: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appAccent) private var accent
    @Binding var selection: String
    @State private var presented = false
    private var selected: Record? { store.bots.first { $0.id == selection } }

    var body: some View {
        Button { presented.toggle() } label: {
            HStack(spacing: 5) {
                AgentAvatar(name: selected?.title ?? "Agent", avatarURL: selected?.value["avatar_url"].string ?? "", size: 28)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            }.frame(minWidth: 44, minHeight: 44)
        }
        .disabled(store.bots.isEmpty)
        .accessibilityLabel("Choose agent")
        .accessibilityValue(selected?.title ?? "No agent selected")
        .accessibilityIdentifier("agentPickerMenu")
        .popover(isPresented: $presented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 0) {
                HStack { Eyebrow(text: "AGENTS"); Spacer(); Text("\(store.bots.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                    .padding(.horizontal, 18).padding(.vertical, 16)
                Divider()
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(store.bots) { bot in
                            Button {
                                selection = bot.id
                                presented = false
                            } label: {
                                HStack(spacing: 12) {
                                    AgentAvatar(name: bot.title, avatarURL: bot.value["avatar_url"].string, size: 40)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(bot.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                                        Text(bot.value["is_active"].bool ? "Active" : "Paused").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 8)
                                    if bot.id == selection { Image(systemName: "checkmark").font(.subheadline.bold()).foregroundStyle(accent) }
                                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(bot.id == selection ? accent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 14))
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityLabel(bot.title)
                                .accessibilityValue(bot.id == selection ? "Selected" : "")
                        }
                    }.padding(6)
                }.frame(maxHeight: 340)
            }.frame(width: 300).fixedSize(horizontal: false, vertical: true)
                .presentationCompactAdaptation(.popover)
        }
    }
}
