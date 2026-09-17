import SwiftUI

struct SettingsView: View {
    @Environment(\.appAccent) private var accent
    @Environment(AppStore.self) private var store
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("color-scheme") private var colorScheme = "system"
    @Environment(\.openURL) private var openURL
    @State private var signOut = false
    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    AgentAvatar(name: store.accountName, avatarURL: store.accountAvatarURL, size: 48)
                    VStack(alignment: .leading, spacing: 4) { Text(store.accountName).font(.headline); Text(store.isDemo ? "Demo workspace".localized : store.api?.baseURL.host ?? "Connected server".localized).font(.caption).foregroundStyle(.secondary) }
                }.padding(.vertical, 8)
                NavigationLink("Profile".localized, systemImage: "person") { SettingsDocumentView(title: "Profile", path: "/users/me", template: "/users/me") }
                if store.api?.isOfficial != true { OperationButton(title: "Change password", path: "/users/me/password", template: "/users/me/password", method: "PUT") }
            }
            Section("Workspace".localized) { WorkspaceIdentity() }
            Section("Intelligence".localized) {
                ResourceLink(title: "Providers", icon: "network", spec: .global("/providers", title: "Providers"))
                ResourceLink(title: "Models", icon: "cpu", spec: .global("/models", title: "Models"))
                ResourceLink(title: "Memory providers", icon: "brain", spec: .global("/memory-providers", title: "Memory providers"))
                ResourceLink(title: "Search providers", icon: "magnifyingglass", spec: .global("/search-providers", title: "Search providers"))
                ResourceLink(title: "Fetch providers", icon: "globe", spec: .global("/fetch-providers", title: "Fetch providers"))
            }
            Section("Connections".localized) {
                ResourceLink(title: "Email providers", icon: "envelope", spec: .global("/email-providers", title: "Email providers"))
                ResourceLink(title: "Speech models", icon: "waveform", spec: .global("/speech-models", title: "Speech models"))
                ResourceLink(title: "Transcription models", icon: "text.bubble", spec: .global("/transcription-models", title: "Transcription models"))
                ResourceLink(title: "Video models", icon: "video", spec: .global("/video-models", title: "Video models"))
                ResourceLink(title: "Remote runtimes", icon: "server.rack", spec: .global("/users/me/runtimes", title: "Remote runtimes"))
                if store.canAdmin { ResourceLink(title: "People", icon: "person.2", spec: .global("/users", title: "People")) }
            }
            Section("Preferences".localized) {
                Picker("Appearance".localized, selection: $appearance) { Text("System".localized).tag("system"); Text("Light".localized).tag("light"); Text("Dark".localized).tag("dark") }.accessibilityIdentifier("appearancePicker")
                Picker("Color scheme".localized, selection: $colorScheme) { ForEach(Theme.schemes, id: \.self) { Text(($0 == "memoh" ? "Memoh".localized : $0.capitalized).localized).tag($0) } }.accessibilityIdentifier("accentPicker")
                Button { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } } label: {
                    HStack { Text("App language".localized); Spacer(); Text(Locale.current.localizedString(forLanguageCode: Bundle.main.preferredLocalizations.first ?? "en") ?? "").foregroundStyle(.secondary) }
                }.accessibilityHint("Change the app language in iOS Settings.".localized)
                NavigationLink("Advanced server controls".localized, systemImage: "wrench.and.screwdriver") { OperationBrowser() }
                NavigationLink("About Homem".localized, systemImage: "info.circle") { AboutView() }
            }
            Section {
                Button(store.isDemo ? "Connect your server".localized : "Sign out".localized, role: store.isDemo ? nil : .destructive) { if store.isDemo { store.signOut() } else { signOut = true } }
            } footer: { Text("Homem 1.0 · Native Swift client for Memoh".localized) }
        }.navigationTitle("Settings".localized)
            .alert("Sign out of Memoh?".localized, isPresented: $signOut) { Button("Sign out".localized, role: .destructive) { store.signOut() } }
    }
}

struct AboutView: View {
    @Environment(\.appAccent) private var accent
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) { Image(systemName: "house.and.flag.fill").font(.largeTitle).foregroundStyle(accent); Text("Homem").font(.largeTitle.bold()); Text("An independent app for Memoh.".localized).foregroundStyle(.secondary) }.padding(.vertical)
                LabeledContent("Version".localized, value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))")
                LabeledContent("Bundle ID".localized, value: "ad.neko.homem")
            }
            Section("Open source".localized) {
                Link("Memoh · AGPL-3.0", destination: URL(string: "https://github.com/felinics/Memoh")!)
                Link("SwiftTerm · MIT", destination: URL(string: "https://github.com/migueldeicaza/SwiftTerm")!)
                Link("L10n-swift · MIT", destination: URL(string: "https://github.com/Decybel07/L10n-swift")!)
                Link("WebRTC · BSD", destination: URL(string: "https://webrtc.org")!)
                NavigationLink("License notices".localized) { LicenseNoticesView() }
                Text("API baseline: 51bb207 (17 September 2026). Feature availability depends on your server, runtime, and permissions.").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("About".localized)
    }
}

struct LicenseNoticesView: View {
    let documents = ["THIRD_PARTY_NOTICES", "AGPL-3.0", "SwiftTerm-LICENSE", "WebRTC-LICENSE", "L10n-swift-LICENSE"]
    var body: some View {
        List(documents, id: \.self) { name in
            NavigationLink(name) {
                ScrollView {
                    Text(Bundle.main.url(forResource: name, withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "See the source distribution for this license.")
                        .font(.footnote.monospaced()).textSelection(.enabled).padding()
                }.navigationTitle(name).navigationBarTitleDisplayMode(.inline)
            }
        }.navigationTitle("Licenses".localized)
    }
}

struct MarketplaceView: View {
    @Environment(AppStore.self) private var store
    @State private var records: [Record] = []
    @State private var error: String?
    @State private var search = ""
    var body: some View {
        List {
            Section { Text("Apps and skills".localized).font(.title3.weight(.semibold)).padding(.vertical, 10) }
            ForEach(records.filter { search.isEmpty || $0.value.pretty.localizedCaseInsensitiveContains(search) }) { record in
                NavigationLink { MarketplaceDetailView(record: record) } label: { VStack(alignment: .leading, spacing: 5) { Text(record.title).font(.headline); Text(record.subtitle).font(.caption).foregroundStyle(.secondary) } }
            }
            if let error { ErrorBanner(message: error) }
            if store.isDemo { Text("Connect your server to browse its live app registries.".localized).foregroundStyle(.secondary) }
        }.navigationTitle("Supermarket".localized).searchable(text: $search)
            .task { do { records = try await store.api?.call("/supermarket/apps").items.map(Record.init) ?? [] } catch { self.error = error.localizedDescription } }
    }
}

struct MarketplaceDetailView: View {
    @Environment(AppStore.self) private var store
    var record: Record
    @State private var install = false
    @State private var descriptor: JSONValue = .null
    @State private var error: String?
    var body: some View {
        List {
            JSONDetails(value: descriptor.isNull ? record.value : descriptor)
            if let error { ErrorBanner(message: error) }
            Section("Install into".localized) { BotPicker(); Button("Install app".localized) { install = true }.disabled(store.selectedBot == nil || descriptor["revision"].string.isEmpty) }
        }.navigationTitle(record.title).navigationBarTitleDisplayMode(.inline)
            .task {
                do { descriptor = try await store.api?.call("/supermarket/registries/\(record.value["registry_id"].string.pathComponent)/apps/\(record.value["app_id"].string.pathComponent)") ?? .null } catch { self.error = error.localizedDescription }
            }
            .sheet(isPresented: $install) {
                if let bot = store.selectedBot, let op = SchemaCatalog.shared.operation("/bots/{bot_id}/apps", "POST") {
                    SchemaEditor(title: "Install app", path: "/bots/\(bot.id.pathComponent)/apps", operation: op, initial: ["registry_id": descriptor["registry_id"], "app_id": descriptor["app_id"], "revision": descriptor["revision"]])
                }
            }
    }
}
