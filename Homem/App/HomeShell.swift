import SwiftUI

struct HomeShell: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TabView {
            ConversationsView().tabItem { Label("Chats".localized, systemImage: "bubble.left.and.bubble.right") }
            NavigationStack { AgentsView() }.tabItem { Label("Agents".localized, systemImage: "square.grid.2x2") }
            NavigationStack { LibraryView() }.tabItem { Label("Library".localized, systemImage: "books.vertical") }
            NavigationStack { SettingsView() }.tabItem { Label("Settings".localized, systemImage: "slider.horizontal.3") }
        }
        .task { await store.reload() }
        .onChange(of: scenePhase) { _, value in if value == .active { Task { await store.reload() } } }
        .alert("Sign in again".localized, isPresented: Binding(get: { store.api?.unauthorized == true }, set: { _ in })) {
            Button("Sign in".localized) { store.signOut() }
        } message: { Text("Your Memoh session has expired. Sign in to reconnect to your server.".localized) }
    }
}

struct LibraryView: View {
    @Environment(\.appAccent) private var accent
    @Environment(AppStore.self) private var store
    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    AgentAvatar(name: store.selectedBot?.title ?? "Library", avatarURL: store.selectedBot?.value.avatarURL ?? "", size: 36)
                    VStack(alignment: .leading, spacing: 5) {
                        Eyebrow(text: "Agent")
                        Text(store.selectedBot?.title ?? "Library".localized).font(.title2.bold())
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
            Section("Discover".localized) {
                NavigationLink { MarketplaceView() } label: { Label("Supermarket".localized, systemImage: "storefront") }
            }
            if store.isDemo { Section { DemoBadge() } }
        }.scrollContentBackground(.hidden).background(Theme.canvas).navigationTitle("Library".localized)
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
            Text("Agent".localized)
            Spacer()
            Text(store.selectedBot?.title ?? "Choose an agent".localized).foregroundStyle(.secondary)
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

    @State private var menuImages: [String: UIImage] = [:]
    var body: some View {
        #if targetEnvironment(macCatalyst)
        Menu {
            Picker("Agent".localized, selection: $selection) {
                ForEach(store.bots) { bot in
                    Label {
                        Text(bot.title)
                    } icon: {
                        if let image = menuImages[bot.id] { Image(uiImage: image).renderingMode(.original) }
                        else { Image(systemName: "person.crop.square") }
                    }.tag(bot.id)
                }
            }.pickerStyle(.inline)
        } label: { pickerLabel }
        .disabled(store.bots.isEmpty)
        .accessibilityLabel("Choose agent".localized)
        .accessibilityValue(selected?.title ?? "No agent selected")
        .accessibilityIdentifier("agentPickerMenu")
        .task(id: store.bots.map { $0.id + $0.value.avatarURL }.joined()) {
            for bot in store.bots {
                guard let url = AvatarSource.url(bot.value.avatarURL, baseURL: store.api?.baseURL) else { continue }
                let request = try? store.api?.avatarRequest(url)
                if let data = try? await AvatarImages.data(url, request: request), !Task.isCancelled {
                    if let image = AvatarImages.decode(data) {
                        // Native menus use the UIImage's intrinsic size, not SwiftUI's frame.
                        let size = CGSize(width: 22, height: 22)
                        menuImages[bot.id] = UIGraphicsImageRenderer(size: size).image { _ in
                            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 5).addClip()
                            let scale = max(size.width / image.size.width, size.height / image.size.height)
                            let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                            image.draw(in: CGRect(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2, width: drawn.width, height: drawn.height))
                        }
                    }
                }
            }
        }
        #else
        Button { presented.toggle() } label: { pickerLabel }
        .disabled(store.bots.isEmpty)
        .accessibilityLabel("Choose agent".localized)
        .accessibilityValue(selected?.title ?? "No agent selected")
        .accessibilityIdentifier("agentPickerMenu")
        .popover(isPresented: $presented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 0) {
                HStack { Eyebrow(text: "Agents"); Spacer(); Text("\(store.bots.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
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
                                    AgentAvatar(name: bot.title, avatarURL: bot.value.avatarURL, size: 40)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(bot.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                                        Text(bot.value["is_active"].bool ? "Active".localized : "Paused".localized).font(.caption).foregroundStyle(.secondary)
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
        #endif
    }
    private var pickerLabel: some View {
        HStack(spacing: 5) {
            AgentAvatar(name: selected?.title ?? "Agent", avatarURL: selected?.value.avatarURL ?? "", size: 28)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
        }.frame(minWidth: 44, minHeight: 44)
    }
}
