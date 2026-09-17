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
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(AppStore.self) private var store
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let bot = store.selectedBot {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                        shortcut("Memories", icon: "brain", spec: .memory(bot.id))
                        shortcut("Schedules", icon: "clock.arrow.circlepath", spec: .schedules(bot.id))
                    }
                    VStack(spacing: 0) {
                        resource("Skills", icon: "sparkles", spec: .skills(bot.id))
                        Divider().padding(.leading, 54)
                        resource("Installed apps", icon: "square.stack.3d.up", spec: .apps(bot.id))
                        Divider().padding(.leading, 54)
                        resource("Connected tools", icon: "point.3.connected.trianglepath.dotted", spec: .mcp(bot.id))
                    }.background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
                }
                NavigationLink { MarketplaceView() } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "storefront").font(.title2).foregroundStyle(accent)
                            .frame(width: 46, height: 46)
                            .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Supermarket".localized).font(.headline).foregroundStyle(.primary)
                            Text("Apps and skills".localized).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
                        .contentShape(RoundedRectangle(cornerRadius: 20))
                }.buttonStyle(.plain).accessibilityLabel("Supermarket".localized)
                if store.isDemo { DemoBadge() }
            }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.background(Theme.canvas).navigationTitle("Library".localized)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { WorkspacePickerMenu() }
                ToolbarItem(placement: .topBarTrailing) {
                    AgentPickerMenu(selection: Binding(get: { store.selectedBot?.id ?? "" }, set: { store.selectedBotID = $0 }))
                }
            }
    }
    private func shortcut(_ title: String, icon: String, spec: ResourceSpec) -> some View {
        NavigationLink { ResourceListView(spec: spec) } label: {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: icon).font(.system(size: 26, weight: .regular)).foregroundStyle(accent)
                    .frame(height: 30).accessibilityHidden(true)
                HStack(alignment: .firstTextBaseline) {
                    Text(title.localized).font(.headline).foregroundStyle(.primary)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
                .contentShape(RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain).accessibilityLabel(title.localized)
    }
    private func resource(_ title: String, icon: String, spec: ResourceSpec) -> some View {
        NavigationLink { ResourceListView(spec: spec) } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 19)).foregroundStyle(accent).frame(width: 26).accessibilityHidden(true)
                Text(title.localized).font(.body).foregroundStyle(.primary)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }.padding(.horizontal, 16).padding(.vertical, 17).frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title.localized)
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


struct WorkspacePickerMenu: View {
    @Environment(AppStore.self) private var store
    @State private var accounts = false
    @State private var busy = false
    @State private var error: String?
    @State private var menuImages: [String: UIImage] = [:]
    var body: some View {
        Menu {
            if !store.workspaces.isEmpty {
                Picker("Workspace".localized, selection: Binding(get: { store.api?.officialSession?.teamID ?? "" }, set: { id in
                    guard let team = store.workspaces.first(where: { $0["team_id"].string == id }) else { return }
                    busy = true
                    Task {
                        defer { busy = false }
                        do { try await store.switchWorkspace(team) }
                        catch { self.error = error.localizedDescription }
                    }
                })) {
                    ForEach(store.workspaces, id: \.self) { team in
                        Label {
                            Text(team.text("name", "slug"))
                        } icon: {
                            if let image = menuImages[team["team_id"].string] { Image(uiImage: image).renderingMode(.original) }
                            else { Image(systemName: "square.stack") }
                        }.tag(team["team_id"].string)
                    }
                }.pickerStyle(.inline).disabled(busy)
            }
            if !store.workspaces.isEmpty { Divider() }
            Button("Accounts".localized, systemImage: "person.crop.circle") { accounts = true }
        } label: {
            HStack(spacing: 5) {
                if busy { ProgressView() }
                else { AgentAvatar(name: store.workspaceName, avatarURL: store.workspace.avatarURL, size: 28) }
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            }.frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Workspace".localized).accessibilityValue(store.workspaceName)
        .accessibilityIdentifier("workspacePicker")
        .sheet(isPresented: $accounts) { AccountsView() }
        .alert("Workspace".localized, isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK".localized) { error = nil }
        } message: { Text(error ?? "") }
        .task(id: store.workspaces) {
            for team in store.workspaces {
                guard let url = AvatarSource.url(team.avatarURL, baseURL: store.api?.baseURL),
                      let data = try? await AvatarImages.data(url, request: try? store.api?.avatarRequest(url)),
                      let image = AvatarImages.decode(data), !Task.isCancelled else { continue }
                menuImages[team["team_id"].string] = UIGraphicsImageRenderer(size: CGSize(width: 22, height: 22)).image { _ in
                    UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 22, height: 22), cornerRadius: 5).addClip()
                    let scale = max(22 / image.size.width, 22 / image.size.height)
                    let width = image.size.width * scale, height = image.size.height * scale
                    image.draw(in: CGRect(x: (22 - width) / 2, y: (22 - height) / 2, width: width, height: height))
                }
            }
        }
    }
}

struct AccountsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var add = false
    @State private var busy: String?
    @State private var error: String?
    @State private var removal: SavedAccount?
    var body: some View {
        NavigationStack {
            List {
                ForEach(store.savedAccounts) { account in
                    Button {
                        busy = account.id
                        Task {
                            defer { busy = nil }
                            do { try await store.switchAccount(account); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            SavedAccountAvatar(account: account)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(account.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                                Text(account.host).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if busy == account.id { ProgressView() }
                            else if account.id == store.activeAccountID { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }.padding(.vertical, 4)
                    }.disabled(busy != nil)
                        .swipeActions(allowsFullSwipe: false) {
                            Button("Remove account".localized, role: .destructive) { removal = account }
                        }
                        .contextMenu { Button("Remove account".localized, systemImage: "trash", role: .destructive) { removal = account } }
                }
                Button("Add account".localized, systemImage: "plus") { add = true }.accessibilityIdentifier("addAccount")
                if let error { ErrorBanner(message: error) }
            }.navigationTitle("Accounts".localized).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done".localized) { dismiss() } } }
                .sheet(isPresented: $add) { ConnectionView(isAddingAccount: true) }
                .alert("Remove account?".localized, isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }), presenting: removal) { account in
                    Button("Remove account".localized, role: .destructive) { store.removeAccount(account); removal = nil }
                    Button("Cancel".localized, role: .cancel) { removal = nil }
                } message: { account in Text(AppLocalization.format("Remove %@ from this device?", account.name)) }
        }
    }
}


private struct SavedAccountAvatar: View {
    @Environment(AppStore.self) private var store
    let account: SavedAccount
    @State private var client: APIClient?
    var body: some View {
        Group {
            if let client { AgentAvatar(name: account.name, avatarURL: account.avatarURL, size: 36, imageAPI: client) }
            else { AgentAvatar(name: account.name, size: 36) }
        }.task(id: account.id) {
            client = (try? store.avatarClient(for: account)) ?? URL(string: account.server).map { APIClient(baseURL: $0) }
        }.onDisappear { client?.invalidate(); client = nil }
    }
}
