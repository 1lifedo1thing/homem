import SwiftUI
import UniformTypeIdentifiers

/// An action belongs to the resource being viewed; identifiers never become form fields.
struct ResourceActionButton: View {
    @Environment(AppStore.self) private var store
    let title: String
    let path: String
    var method = "POST"
    var destructive = false
    var streaming = false
    var onFinished: (() async -> Void)? = nil
    @State private var busy = false
    @State private var confirm = false
    @State private var message: String?
    @State private var progress = ""
    @State private var error: String?
    var bodyView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(role: destructive ? .destructive : nil) {
                if destructive { confirm = true } else { Task { await run() } }
            } label: {
                HStack { Text(title.localized); Spacer(); if busy { ProgressView() } }
            }.disabled(busy)
            if let error { ErrorBanner(message: error) }
            if let message { Label(message, systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary) }
            if !progress.isEmpty { CodeBlockView(code: progress, language: "plaintext", title: "Progress".localized) }
        }.alert(title.localized, isPresented: $confirm) {
            Button(title.localized, role: .destructive) { Task { await run() } }
            Button("Cancel".localized, role: .cancel) {}
        } message: { Text("This changes the selected resource on your server.".localized) }
    }
    var body: some View { bodyView }
    private func run() async {
        guard let api = store.api else { return }
        busy = true; error = nil; message = nil; progress = ""
        defer { busy = false }
        do {
            let result: JSONValue
            if streaming {
                result = try await api.streamOperation(path, method: method, query: [:], body: payload) { event in
                    let line = event.text("message", "data", "detail", "status")
                    if !line.isEmpty { progress = String((progress + "\n" + line).suffix(12000)) }
                }
            } else { result = try await api.call(path, method: method, body: payload) }
            if result["success"] == false || result["ok"] == false || result["status"] == "failed" {
                throw ClientError.message(result.text("message", "error").nonEmpty ?? "The action could not be completed.".localized)
            }
            message = "Completed".localized
            await onFinished?()
        } catch { self.error = error.localizedDescription }
    }
    // Keep the request payload separate from SwiftUI's body property.
    private var payload: JSONValue? { requestBody }
    var requestBody: JSONValue? = nil
}

struct MemoryMaintenanceView: View {
    @Environment(AppStore.self) private var store
    let botID: String
    @State private var ratio = "0.5"
    @State private var days = 30
    @State private var status: JSONValue = .null
    var base: String { "/bots/\(botID.pathComponent)/memory" }
    var body: some View {
        Form {
            Section("Summarize memories".localized) {
                Picker("Keep".localized, selection: $ratio) {
                    Text("Most detail".localized).tag("0.8")
                    Text("Balanced".localized).tag("0.5")
                    Text("Essentials".localized).tag("0.3")
                }
                Stepper(AppLocalization.format("Older than %d days", days), value: $days, in: 0...3650)
                ResourceActionButton(title: "Summarize memories", path: base + "/compact", destructive: true,
                                     requestBody: ["ratio": .number(Double(ratio) ?? 0.5), "decay_days": .number(Double(days))])
                    .disabled(status["compact"]["semantic"] == false)
            }
            Section("Memory files".localized) {
                ResourceActionButton(title: "Import memory files", path: base + "/ingest").disabled(status["can_manual_sync"] == false)
                ResourceActionButton(title: "Rebuild memory index", path: base + "/rebuild", destructive: true).disabled(status["compact"]["rebuild_index"] == false)
            }
            Section {
                NavigationLink("Memory graph".localized) { MemoryGraphView(path: base + "/graph") }
                NavigationLink("Memory usage".localized) { ReadOnlyDocumentView(title: "Memory usage", path: base + "/usage") }
            }
        }.navigationTitle("Memory maintenance".localized)
            .task { status = (try? await store.api?.call(base + "/status")) ?? .null }
    }
}

struct SnapshotsView: View {
    @Environment(AppStore.self) private var store
    let botID: String
    @State private var snapshots: [Record] = []
    @State private var selected: Record?
    @State private var name = ""
    @State private var create = false
    @State private var busy = false
    @State private var loading = true
    @State private var error: String?
    var base: String { "/bots/\(botID.pathComponent)/container/snapshots" }
    var body: some View {
        List {
            if let error { ErrorBanner(message: error) { Task { await load() } } }
            ForEach(snapshots) { snapshot in
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(snapshot.value.text("display_name", "name", "runtime_snapshot_name").nonEmpty ?? "Snapshot".localized)
                        if let date = snapshot.value["created_at"].string.wireDate { Text(date, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Button("Restore".localized) { selected = snapshot }
                        .disabled(busy || snapshot.value["version"].number <= 0 || !snapshot.value["managed"].bool)
                }
            }
        }.navigationTitle("Snapshots".localized)
            .overlay { if loading { ProgressView() } else if snapshots.isEmpty && error == nil { ContentUnavailableView("No snapshots".localized, systemImage: "camera") } }
            .toolbar { Button("Create snapshot".localized, systemImage: "plus") { create = true }.disabled(busy) }
            .task { await load() }.refreshable { await load() }
            .alert("Create snapshot".localized, isPresented: $create) {
                TextField("Name".localized, text: $name)
                Button("Create".localized) { Task { await perform("", body: ["snapshot_name": .string(name)]) } }
                Button("Cancel".localized, role: .cancel) {}
            }
            .alert("Restore snapshot?".localized, isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
                Button("Restore".localized, role: .destructive) {
                    if let snapshot = selected { Task { await perform("/rollback", body: ["version": snapshot.value["version"]]); selected = nil } }
                }
                Button("Cancel".localized, role: .cancel) { selected = nil }
            } message: { Text("The workspace will return to this snapshot. Later changes may be lost.".localized) }
    }
    private func load() async {
        loading = true; defer { loading = false }
        do {
            let response = try await store.api?.call(base) ?? .null
            snapshots = response["snapshots"].array.map { item in var row = item; row["id"] = .string(item["version"].isNull ? item.text("name", "runtime_snapshot_name") : item["version"].scalar); return Record(value: row) }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func perform(_ suffix: String, body: JSONValue) async {
        busy = true; defer { busy = false }
        do { _ = try await store.api?.call(base + suffix, method: "POST", body: body); name = ""; await load() }
        catch { self.error = error.localizedDescription }
    }
}

struct ArchiveToolsView: View {
    @Environment(AppStore.self) private var store
    let botID: String
    let files: [Record]
    @State private var selection = Set<String>()
    @State private var download: URL?
    @State private var busy = false
    @State private var error: String?
    var base: String { "/bots/\(botID.pathComponent)/container/fs" }
    var body: some View {
        List {
            Section("Download archive".localized) {
                ForEach(files) { file in
                    Toggle(file.value["name"].string, isOn: Binding(get: { selection.contains(file.value["path"].string) }, set: {
                        if $0 { selection.insert(file.value["path"].string) } else { selection.remove(file.value["path"].string) }
                    }))
                }
                Button { Task { await archive() } } label: { HStack { Text("Create archive".localized); if busy { ProgressView() } } }.disabled(selection.isEmpty || busy)
                if let download { ShareLink("Save or share archive".localized, item: download) }
            }
            Section("Extract archive".localized) {
                ForEach(files.filter { !$0.value["isDir"].bool && Self.isArchive($0.value["name"].string) }) { file in
                    ResourceActionButton(title: file.value["name"].string, path: base + "/extract", destructive: true, requestBody: ["path": file.value["path"]])
                }
            }
            if let error { ErrorBanner(message: error) }
        }.navigationTitle("Archives".localized).navigationBarTitleDisplayMode(.inline)
    }
    static func isArchive(_ name: String) -> Bool { [".zip", ".tar.gz", ".tgz"].contains { name.lowercased().hasSuffix($0) } }
    private func archive() async {
        guard let api = store.api else { return }
        busy = true; error = nil; defer { busy = false }
        do {
            let data = try await api.perform(api.request(base + "/archive", method: "POST", body: ["paths": .array(selection.sorted().map(JSONValue.string))]))
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("Archive.tar.gz"); try data.write(to: file); download = file
        } catch { self.error = error.localizedDescription }
    }
}

struct GitBranchView: View {
    @Environment(AppStore.self) private var store
    let path: String
    @State private var branch = ""
    @State private var branches: [String] = []
    @State private var current = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        Form {
            Picker("Branch".localized, selection: $branch) { ForEach(branches, id: \.self) { Text($0).tag($0) } }
            Button("Switch branch".localized) { Task { await change() } }.disabled(busy || branch.isEmpty || branch == current)
            if busy { ProgressView() }
            if let error { ErrorBanner(message: error) }
        }.navigationTitle("Git branch".localized).task { await load() }
    }
    private func load() async {
        do { let value = try await store.api?.call(path + "/git-branch") ?? .null; current = value["branch"].string; branches = value["branches"].array.map(\.string); if !current.isEmpty && !branches.contains(current) { branches.insert(current, at: 0) }; branch = current; busy = value["busy"].bool }
        catch { self.error = error.localizedDescription }
    }
    private func change() async {
        busy = true; error = nil; defer { busy = false }
        do { _ = try await store.api?.call(path + "/git-branch", method: "POST", body: ["branch": .string(branch)]); await load() }
        catch { self.error = error.localizedDescription }
    }
}

struct MCPTransferView: View {
    @Environment(AppStore.self) private var store
    let botID: String
    @State private var importing = false
    @State private var download: URL?
    @State private var error: String?
    @State private var busy = false
    var base: String { "/bots/\(botID.pathComponent)/mcp-ops" }
    var body: some View {
        Form {
            Section {
                Button("Import connections".localized) { importing = true }.disabled(busy)
                Button("Export connections".localized) { Task { await export() } }.disabled(busy)
                if let download { ShareLink("Save or share connections".localized, item: download) }
            } footer: { Text("Connection files can contain credentials. Share them only with people you trust.".localized) }
            if busy { ProgressView() }
            if let error { ErrorBanner(message: error) }
        }.navigationTitle("Transfer connections".localized)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                Task {
                    busy = true; defer { busy = false }
                    do {
                        let url = try result.get(), access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let data = try Data(contentsOf: url)
                        let value = try JSONDecoder().decode(JSONValue.self, from: data)
                        guard !value["mcpServers"].object.isEmpty else { throw ClientError.message("Choose an MCP connection file.".localized) }
                        _ = try await store.api?.call(base + "/import", method: "PUT", body: value); error = nil
                    } catch { self.error = error.localizedDescription }
                }
            }
    }
    private func export() async {
        busy = true; defer { busy = false }
        do {
            let value = try await store.api?.call(base + "/export") ?? .null
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("mcp-connections.json"); try value.encoded.write(to: url); download = url; error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct DependencyDetailView: View {
    @Environment(AppStore.self) private var store
    let botID: String
    let record: Record
    @State private var version = ""
    @State private var installedVersion = ""
    @State private var ready = false
    @State private var reason = ""
    @State private var script = ""
    @State private var error: String?
    var base: String { "/bots/\(botID.pathComponent)/dependencies/\(record.id.pathComponent)" }
    var body: some View {
        Form {
            Section {
                Text(record.title).font(.headline)
                if !installedVersion.isEmpty { LabeledContent("Installed version".localized, value: installedVersion) }
                if !reason.isEmpty { Text(reason).foregroundStyle(.secondary) }
                if let error { ErrorBanner(message: error) { Task { await preflight() } } }
            }
            Section("Version".localized) {
                TextField("Latest version".localized, text: $version).textInputAutocapitalization(.never).autocorrectionDisabled()
                ResourceActionButton(title: "Install", path: base + "/install", streaming: true, onFinished: { await preflight() }, requestBody: versionBody).disabled(!ready)
                ResourceActionButton(title: "Update", path: base + "/update", streaming: true, onFinished: { await preflight() }, requestBody: versionBody).disabled(!ready)
                ResourceActionButton(title: "Reinstall", path: base + "/reinstall", destructive: true, streaming: true, onFinished: { await preflight() }, requestBody: versionBody).disabled(!ready)
                ResourceActionButton(title: "Restore previous version", path: base + "/rollback", destructive: true, onFinished: { await preflight() }).disabled(!ready)
            }
            if !script.isEmpty { Section("Installation script".localized) { CodeBlockView(code: script, language: "bash") } }
        }.navigationTitle(record.title).navigationBarTitleDisplayMode(.inline)
            .task {
                await preflight()
                if let value = try? await store.api?.call(base + "/script") { script = value.text("script", "content") }
            }
    }
    private var versionBody: JSONValue {
        var result: JSONValue = [:]
        if !version.trimmingCharacters(in: .whitespaces).isEmpty { result["version"] = .string(version.trimmingCharacters(in: .whitespaces)) }
        if !record.value["definition_revision"].string.isEmpty { result["definition_revision"] = record.value["definition_revision"] }
        return result
    }
    private func preflight() async {
        do {
            let result = try await store.api?.call("/bots/\(botID.pathComponent)/dependencies/preflight", method: "POST", body: ["dependency_ids": [.string(record.id)]]) ?? .null
            let item = result["items"].array.first ?? .null
            installedVersion = item["installed_version"].string
            let state = item["state"].string
            ready = result["workspace_state"] == "running" && ["satisfied", "missing"].contains(state)
            reason = ready ? "" : "Start the workspace and check that this dependency supports it.".localized
            error = nil
        } catch { ready = false; self.error = error.localizedDescription }
    }
}

struct ConversationSettingsView: View {
    @Environment(AppStore.self) private var store
    let botID: String
    let sessionID: String
    @State private var name = ""
    @State private var originalName = ""
    @State private var supportsGoal = false
    @State private var saving = false
    @State private var error: String?
    var base: String { "/bots/\(botID.pathComponent)/sessions/\(sessionID.pathComponent)" }
    var body: some View {
        Form {
            Section("Conversation".localized) {
                TextField("Title".localized, text: $name)
                Button("Save".localized) { Task { await save() } }.disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty || name == originalName)
            }
            Section("Context".localized) {
                ResourceActionButton(title: "Summarize conversation", path: base + "/compact", destructive: true)
                NavigationLink("Context usage".localized) { ReadOnlyDocumentView(title: "Context usage", path: base + "/context-lifecycle") }
            }
            if supportsGoal { Section("Goal".localized) {
                ResourceActionButton(title: "Pause goal", path: base + "/runtime-controls/goal", requestBody: ["action": "pause"])
                ResourceActionButton(title: "Clear goal", path: base + "/runtime-controls/goal", destructive: true, requestBody: ["action": "clear"])
            } }
            if let error { ErrorBanner(message: error) }
        }.navigationTitle("Conversation settings".localized).navigationBarTitleDisplayMode(.inline)
            .task { do { let result = try await store.api?.call(base) ?? .null; name = result.text("title", "name"); originalName = name; supportsGoal = (try? await store.api?.call(base + "/runtime-controls"))?["capabilities"]["goal"].bool ?? false } catch { self.error = error.localizedDescription } }
    }
    private func save() async {
        saving = true; defer { saving = false }
        do { _ = try await store.api?.call(base, method: "PATCH", body: ["title": .string(name)]); originalName = name; error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct AccessSettingsView: View {
    @Environment(AppStore.self) private var store
    let botID: String
    @State private var effect = "deny"
    @State private var original = "deny"
    @State private var loaded = false
    @State private var busy = false
    @State private var error: String?
    var base: String { "/bots/\(botID.pathComponent)" }
    var body: some View {
        Form {
            Section("Default access".localized) {
                Picker("Unmatched requests".localized, selection: $effect) {
                    Text("Deny".localized).tag("deny"); Text("Allow".localized).tag("allow")
                }.disabled(!loaded || busy)
                if effect != original { Button("Save".localized) { Task { await save() } }.disabled(busy) }
            }
            Section {
                ResourceLink(title: "Access rules", icon: "list.bullet.rectangle", spec: .bot(botID, "acl/rules", title: "Access rules", detail: "/bots/{bot_id}/acl/rules/{rule_id}"))
                ResourceLink(title: "Workspace access", icon: "person.2", spec: .bot(botID, "user-access", title: "Workspace access", detail: "/bots/{bot_id}/user-access/{grant_id}"))
                ResourceLink(title: "Channel managers", icon: "person.badge.shield.checkmark", spec: .bot(botID, "channel-managers", title: "Channel managers", detail: "/bots/{bot_id}/channel-managers/{channel_identity_id}"))
                OperationButton(title: "Transfer ownership", path: base + "/owner", template: "/bots/{id}/owner", method: "PUT")
            }
            if let error { ErrorBanner(message: error) }
        }.navigationTitle("Access & permissions".localized)
            .task {
                do { let value = try await store.api?.call(base + "/acl/default-effect") ?? .null; effect = value.text("default_effect", "effect").nonEmpty ?? "deny"; original = effect; loaded = true }
                catch { self.error = error.localizedDescription }
            }
    }
    private func save() async {
        busy = true; defer { busy = false }
        do { _ = try await store.api?.call(base + "/acl/default-effect", method: "PUT", body: ["default_effect": .string(effect)]); original = effect; error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct ServerConnectionsView: View {
    var body: some View {
        List {
            Section("Account".localized) {
                ResourceLink(title: "Linked channels", icon: "bubble.left.and.bubble.right", spec: .init(title: "Linked channels", path: "/users/me/channel-identities", template: "/users/me/channel-identities", detailTemplate: "/users/me/channel-identities/{channel_identity_id}"))
                ResourceLink(title: "Remote runtimes", icon: "desktopcomputer", spec: .global("/users/me/runtimes", title: "Remote runtimes"))
            }
            Section("Models".localized) {
                ResourceLink(title: "Speech providers", icon: "waveform", spec: .global("/speech-providers", title: "Speech providers"))
                ResourceLink(title: "Transcription providers", icon: "text.bubble", spec: .global("/transcription-providers", title: "Transcription providers"))
                ResourceLink(title: "Video providers", icon: "video", spec: .global("/video-providers", title: "Video providers"))
            }
        }.navigationTitle("Connections".localized)
    }
}

struct MemorySearchView: View {
    @Environment(AppStore.self) private var store
    let botID: String
    @State private var query = ""
    @State private var records: [Record] = []
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        List {
            ForEach(records) { record in
                NavigationLink { ResourceDetailView(spec: .memory(botID), record: record) } label: { Text(record.title).lineLimit(5) }
            }
            if let error { ErrorBanner(message: error) }
        }.navigationTitle("Search memories".localized)
            .searchable(text: $query, prompt: "Search memories".localized).onSubmit(of: .search) { Task { await search() } }
            .overlay { if busy { ProgressView() } }
    }
    private func search() async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { records = []; return }
        busy = true; defer { busy = false }
        do { records = try await store.api?.call("/bots/\(botID.pathComponent)/memory/search", method: "POST", body: ["query": .string(query)]).items.map(Record.init) ?? []; error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct ResourceDetailActions: View {
    let spec: ResourceSpec
    let record: Record
    private var path: String { spec.itemPath(record) }
    private var mediaModels: String { spec.template.replacingOccurrences(of: "-providers", with: "-models") }
    var body: some View {
        if spec.template.hasSuffix("/workdirs") {
            Section { NavigationLink("Git branch".localized, systemImage: "arrow.triangle.branch") { GitBranchView(path: path) } }
        } else if spec.template.hasSuffix("/apps") {
            Section("Installation".localized) {
                ResourceActionButton(title: "Resume installation", path: path + "/resume", streaming: true)
                if !record.value["app_id"].string.isEmpty && !record.value["registry_id"].string.isEmpty {
                    ResourceActionButton(title: "Update app", path: spec.path + "/update", streaming: true,
                                         requestBody: ["app_id": record.value["app_id"], "registry_id": record.value["registry_id"], "release": true])
                }
            }
        } else if spec.template.hasSuffix("/connectors") {
            Section { NavigationLink("Account authorization".localized) { ConnectorAccountView(path: path) } }
        } else if ["/speech-providers", "/transcription-providers", "/video-providers"].contains(spec.template) {
            Section {
                ResourceLink(title: "Models", icon: "cpu", spec: .init(title: "Models", path: path + "/models", template: spec.resolvedDetailTemplate + "/models", detailTemplate: mediaModels + "/{id}", detailCollectionPath: mediaModels, canCreate: false))
                OperationButton(title: "Refresh models", path: path + "/import-models", template: spec.resolvedDetailTemplate + "/import-models", method: "POST")
            }
        } else if ["/speech-models/{id}", "/transcription-models/{id}"].contains(spec.resolvedDetailTemplate) {
            Section { OperationButton(title: "Test model", path: path + "/test", template: spec.resolvedDetailTemplate + "/test", method: "POST") }
        }
    }
}

struct WorkspaceComputersView: View {
    @Environment(AppStore.self) private var store
    let botID: String
    @State private var targets: [Record] = []
    @State private var computer: JSONValue = .null
    @State private var error: String?
    var base: String { "/bots/\(botID.pathComponent)/workspace-targets" }
    var body: some View {
        List {
            Section("Computers".localized) {
                ForEach(targets) { target in
                    NavigationLink {
                        Form {
                            LabeledContent("Status".localized, value: (target.value["online"].bool ? "Online" : "Offline").localized)
                            if !target.value["primary"].bool {
                                ResourceActionButton(title: "Use by default", path: base + "/primary", method: "PUT", onFinished: { await load() }, requestBody: ["target_id": .string(target.id)])
                            }
                            OperationButton(title: "Tool approval", path: base + "/" + target.id.pathComponent + "/tool-approval", template: "/bots/{bot_id}/workspace-targets/{target_id}/tool-approval", method: "PUT")
                            if !target.value["runtime_id"].string.isEmpty {
                                ResourceActionButton(title: "Disconnect computer", path: base + "/" + target.id.pathComponent, method: "DELETE", destructive: true, onFinished: { await load() })
                            }
                        }.navigationTitle(target.title)
                    } label: {
                        Label { HStack { Text(target.title); Spacer(); if target.value["primary"].bool { Text("Default".localized).font(.caption).foregroundStyle(.secondary) } } } icon: { Image(systemName: "desktopcomputer") }
                    }
                }
            }
            Section("Connect a computer".localized) {
                ResourceReferencePicker(title: "Computer", source: "/users/me/runtimes", required: true, value: $computer)
                if !computer.string.isEmpty {
                    ResourceActionButton(title: "Connect", path: base + "/remotes/" + computer.string.pathComponent, method: "PUT", onFinished: { computer = .null; await load() })
                }
            }
            if let error { ErrorBanner(message: error) { Task { await load() } } }
        }.navigationTitle("Computers".localized).task { await load() }.refreshable { await load() }
    }
    private func load() async {
        do {
            let result = try await store.api?.call(base) ?? .null
            targets = result["targets"].array.map { item in var row = item; row["id"] = row["target_id"]; if row["name"].string.isEmpty { row["name"] = .string("Workspace".localized) }; return Record(value: row) }; error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct AgentAutomationView: View {
    let botID: String
    var body: some View {
        List {
            NavigationLink("Events".localized) { ReadOnlyDocumentView(title: "Events", path: "/bots/\(botID.pathComponent)/hooks/events") }
            OperationButton(title: "Test automation", path: "/bots/\(botID.pathComponent)/hooks/test", template: "/bots/{bot_id}/hooks/test", method: "POST")
            NavigationLink("Configuration files".localized) { FileBrowserView(botID: botID, path: "/data") }
        }.navigationTitle("Automation".localized)
    }
}

/// Connect-It completes its callback on the server, then the app refreshes on return.
struct ConnectorAccountView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    let path: String
    @State private var connection: JSONValue = .null
    @State private var busy = false
    @State private var error: String?
    @State private var authorizationURL: URL?
    var body: some View {
        Form {
            if !connection.isNull {
                LabeledContent("Status".localized, value: connection["status"].string.fieldLabel.localized)
                Toggle("Enabled".localized, isOn: Binding(get: { connection["enabled"].bool }, set: { enabled in Task { await setEnabled(enabled) } })).disabled(busy)
            }
            Button("Reconnect account".localized) { Task { await authorize() } }.disabled(busy)
            if let authorizationURL { Link("Open sign-in page".localized, destination: authorizationURL) }
            Button("Refresh status".localized) { Task { await load() } }.disabled(busy)
            if busy { ProgressView() }
            if let error { ErrorBanner(message: error) }
        }.navigationTitle("Account authorization".localized).task { await load() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await load() } } }
    }
    private func load() async {
        do { connection = try await store.api?.call(path) ?? .null; error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func setEnabled(_ enabled: Bool) async {
        busy = true; defer { busy = false }
        do { _ = try await store.api?.call(path, method: "PATCH", body: ["enabled": .bool(enabled)]); await load() }
        catch { self.error = error.localizedDescription }
    }
    private func authorize() async {
        busy = true; error = nil; defer { busy = false }
        do {
            let response = try await store.api?.call(path + "/reauth", method: "POST") ?? .null
            guard let url = URL(string: response["authorization_url"].string), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { throw ClientError.invalidResponse }
            authorizationURL = url
            openURL(url)
        } catch { self.error = error.localizedDescription }
    }
}
