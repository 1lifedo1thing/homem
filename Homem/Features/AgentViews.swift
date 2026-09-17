import SwiftUI

struct AgentsView: View {
    @Environment(\.appAccent) private var accent
    @Environment(AppStore.self) private var store
    @State private var create = false
    @State private var search = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Good company.\nGreat possibilities.").font(.system(.title, design: .rounded, weight: .bold))
                        Text("A home for every kind of intelligence.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "sun.max").font(.title).foregroundStyle(.orange).padding(.top, 5)
                }
                if let error = store.error { ErrorBanner(message: error) { Task { await store.reload() } } }
                HStack { Text("YOUR WORKSPACE").font(.caption2.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary); Spacer(); Text("\(store.bots.count) agents").font(.caption).foregroundStyle(.secondary) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                    ForEach(store.bots.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { bot in
                        NavigationLink { AgentDetailView(bot: bot) } label: { AgentCard(bot: bot) }.buttonStyle(.plain)
                    }
                    Button { create = true } label: {
                        VStack(spacing: 12) { Image(systemName: "plus.circle").font(.largeTitle); Text("Make room for someone new").font(.subheadline.weight(.medium)); Text("Create an agent").font(.caption).foregroundStyle(.secondary) }
                            .foregroundStyle(accent).frame(maxWidth: .infinity, minHeight: 155).background(accent.opacity(0.035), in: RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).stroke(accent.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [5, 5])))
                    }.accessibilityIdentifier("createAgent")
                }
                if store.isDemo { DemoBadge() }
            }.padding(22).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }.background(Color(.systemGroupedBackground)).navigationTitle("Agents")
            .searchable(text: $search, prompt: "Find an agent")
            .toolbar { Button { create = true } label: { Image(systemName: "plus") }.accessibilityLabel("Create agent") }
            .refreshable { await store.reload() }
            .sheet(isPresented: $create, onDismiss: { Task { await store.reload() } }) {
                if let op = SchemaCatalog.shared.operation("/bots", "POST") { SchemaEditor(title: "Create an agent", path: "/bots", operation: op) }
            }
    }
}

struct AgentCard: View {
    let bot: Record
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack { AgentAvatar(name: bot.title, size: 55); Spacer(); StatusPill(text: bot.value["is_active"].bool ? "Active" : "Paused", color: bot.value["is_active"].bool ? .green : .secondary) }
            VStack(alignment: .leading, spacing: 6) {
                Text(bot.title).font(.title3.weight(.semibold))
                Text(bot.value["metadata"]["description"].string.nonEmpty ?? "Your own agent, with a workspace and memory.").font(.subheadline).foregroundStyle(.secondary).lineLimit(2).frame(minHeight: 38, alignment: .top)
            }
            Divider()
            HStack { Label("Workspace", systemImage: "square.grid.2x2"); Spacer(); Image(systemName: "arrow.up.right") }.font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }.padding(20).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }
}

struct AgentDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let bot: Record
    @State private var edit = false
    @State private var delete = false
    @State private var error: String?
    private var current: Record { store.bots.first { $0.id == bot.id } ?? bot }
    private var base: String { "/bots/\(bot.id.pathComponent)" }
    private var manage: Bool { current.value["current_user_permissions"].array.contains("manage") || store.canAdmin }
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 15) {
                    HStack { AgentAvatar(name: current.title, size: 72); Spacer(); StatusPill(text: current.value["is_active"].bool ? "Active" : "Paused", color: current.value["is_active"].bool ? .green : .secondary) }
                    Text(current.title).font(.largeTitle.weight(.bold))
                    Text(current.value["metadata"]["description"].string.nonEmpty ?? "A dedicated workspace, tools, and memories. All yours.").foregroundStyle(.secondary)
                }.padding(.vertical, 8)
            }
            Section("Workspace") {
                NavigationLink { WorkspaceView(botID: bot.id, name: current.title) } label: { Label("Files, terminal & desktop", systemImage: "desktopcomputer") }
                ResourceLink(title: "Conversations", icon: "bubble.left.and.bubble.right", spec: .bot(bot.id, "sessions", title: "Conversations", detail: "/bots/{bot_id}/sessions/{session_id}"))
                ResourceLink(title: "Memories", icon: "brain", spec: .memory(bot.id))
                ResourceLink(title: "Schedules", icon: "clock", spec: .schedules(bot.id))
            }
            if manage {
                Section("Configuration") {
                    NavigationLink { SettingsDocumentView(title: "Agent settings", path: base + "/settings", template: "/bots/{bot_id}/settings") } label: { Label("Model & behavior", systemImage: "slider.horizontal.3") }
                    ResourceLink(title: "Agent runtimes", icon: "cpu", spec: .bot(bot.id, "agents", title: "Agent runtimes"))
                    NavigationLink { ChannelsView(botID: bot.id) } label: { Label("Channels", systemImage: "antenna.radiowaves.left.and.right") }
                    ResourceLink(title: "MCP connections", icon: "point.3.connected.trianglepath.dotted", spec: .mcp(bot.id))
                    ResourceLink(title: "Skills", icon: "sparkles", spec: .skills(bot.id))
                    ResourceLink(title: "Apps", icon: "square.stack.3d.up", spec: .apps(bot.id))
                    ResourceLink(title: "Email bindings", icon: "envelope", spec: .bot(bot.id, "email-bindings", title: "Email bindings"))
                    ResourceLink(title: "Workspace access", icon: "person.2", spec: .bot(bot.id, "user-access", title: "Workspace access", detail: "/bots/{bot_id}/user-access/{grant_id}"))
                }
            }
            Section("Insights") {
                NavigationLink("Health checks", systemImage: "heart.text.clipboard") { ReadOnlyDocumentView(title: "Health checks", path: base + "/checks") }
                NavigationLink("Token usage", systemImage: "chart.bar") { ReadOnlyDocumentView(title: "Token usage", path: base + "/token-usage") }
                NavigationLink("Schedule history", systemImage: "clock.arrow.circlepath") { ReadOnlyDocumentView(title: "Schedule history", path: base + "/schedule/logs") }
                NavigationLink("Compaction history", systemImage: "archivebox") { ReadOnlyDocumentView(title: "Compaction history", path: base + "/compaction/logs") }
            }
            if manage {
                Section {
                    NavigationLink("Backups", systemImage: "externaldrive") { BackupView(botID: bot.id) }
                    NavigationLink("Advanced controls", systemImage: "wrench.and.screwdriver") { OperationBrowser(prefix: "/bots/{bot_id}", substitutions: ["bot_id": bot.id, "id": bot.id]) }
                    Button(current.value["is_active"].bool ? "Pause agent" : "Resume agent") { Task { await toggle() } }
                    Button("Delete agent", role: .destructive) { delete = true }
                }
            }
            if let error { ErrorBanner(message: error) }
        }.navigationTitle(current.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { if manage { Button("Edit") { edit = true } } }
            .sheet(isPresented: $edit, onDismiss: { Task { await store.reload() } }) { if let op = SchemaCatalog.shared.operation("/bots/{id}", "PUT") { SchemaEditor(title: "Edit agent", path: base, operation: op, initial: current.value) } }
            .confirmationDialog("Delete \(current.title)?", isPresented: $delete, titleVisibility: .visible) { Button("Delete agent", role: .destructive) { Task { do { _ = try await store.api?.call(base, method: "DELETE"); await store.reload(); dismiss() } catch { self.error = error.localizedDescription } } } } message: { Text("This permanently removes the agent and its associated data. Export a backup first if needed.") }
    }
    func toggle() async { do { _ = try await store.api?.call(base, method: "PUT", body: ["is_active": .bool(!current.value["is_active"].bool)]); await store.reload() } catch { self.error = error.localizedDescription } }
}

struct SettingsDocumentView: View {
    @Environment(AppStore.self) private var store
    var title: String
    var path: String
    var template: String
    @State private var value: JSONValue = .null
    @State private var error: String?
    @State private var edit = false
    var body: some View {
        List { if !value.isNull { JSONDetails(value: value) }; if let error { ErrorBanner(message: error) { Task { await load() } } } }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Edit") { edit = true }.disabled(value.isNull) }
            .task { await load() }.refreshable { await load() }
            .sheet(isPresented: $edit, onDismiss: { Task { await load() } }) {
                if let op = SchemaCatalog.shared.operation(template, "PUT") { SchemaEditor(title: title, path: path, operation: op, initial: value) }
            }
    }
    func load() async { do { value = try await store.api?.call(path) ?? .null; error = nil } catch { self.error = error.localizedDescription } }
}

struct ChannelsView: View {
    @Environment(AppStore.self) private var store
    var botID: String
    @State private var channels: [Record] = []
    @State private var error: String?
    var body: some View {
        List {
            Section { Text("Connect your agent to the places you already talk. Configuration fields are defined by each channel adapter.").foregroundStyle(.secondary).font(.subheadline) }
            ForEach(channels) { channel in
                let platform = channel.value.text("type", "platform", "id")
                NavigationLink(channel.title) { ChannelDetailView(botID: botID, platform: platform, metadata: channel.value) }
            }
            if let error { ErrorBanner(message: error) }
        }.navigationTitle("Channels").task { do { channels = try await store.api?.call("/channels").items.map(Record.init) ?? [] } catch { self.error = error.localizedDescription } }
    }
}

struct ChannelDetailView: View {
    @Environment(AppStore.self) private var store
    var botID: String
    var platform: String
    var metadata: JSONValue
    @State private var config: JSONValue = [:]
    @State private var error: String?
    @State private var edit = false
    var path: String { "/bots/\(botID.pathComponent)/channel/\(platform.pathComponent)" }
    var body: some View {
        List {
            Section("Channel") { JSONDetails(value: metadata) }
            if !config.object.isEmpty { Section("Configuration") { JSONDetails(value: config) } }
            if let error { ErrorBanner(message: error) }
            Section { Button("Configure channel") { edit = true }; OperationButton(title: "Enable or disable", path: path + "/status", template: "/bots/{id}/channel/{platform}/status", method: "PATCH") }
        }.navigationTitle(platform.fieldLabel).task { await load() }
            .sheet(isPresented: $edit, onDismiss: { Task { await load() } }) { ChannelConfigEditor(path: path, platform: platform, metadata: metadata, initial: config) }
    }
    func load() async { do { config = try await store.api?.call(path) ?? [:]; error = nil } catch { self.error = error.localizedDescription } }
}

struct ChannelConfigEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var path: String
    var platform: String
    var metadata: JSONValue
    var initial: JSONValue
    @State private var credentials: JSONValue = [:]
    @State private var disabled = false
    @State private var busy = false
    @State private var error: String?
    var fields: [String] { metadata["config_schema"]["fields"].object.keys.sorted { metadata["config_schema"]["fields"][$0]["order"].number < metadata["config_schema"]["fields"][$1]["order"].number } }
    var body: some View {
        NavigationStack {
            Form {
                Section { Toggle("Enabled", isOn: Binding(get: { !disabled }, set: { disabled = !$0 })) }
                Section("Connection") {
                    if fields.isEmpty { JSONInput(value: $credentials) }
                    ForEach(fields, id: \.self) { key in
                        let field = metadata["config_schema"]["fields"][key]
                        if field["type"] == "secret" {
                            SecureField(field["title"].string.nonEmpty ?? key.fieldLabel, text: Binding(get: { credentials[key].string }, set: { credentials[key] = .string($0) })).textInputAutocapitalization(.never).autocorrectionDisabled()
                        } else {
                            SchemaField(name: key, schema: converted(field), required: field["required"].bool, value: Binding(get: { credentials[key] }, set: { credentials[key] = $0 }))
                        }
                    }
                }
                if let error { ErrorBanner(message: error) }
            }.navigationTitle(platform.fieldLabel).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(busy) } }
                .onAppear { credentials = initial["credentials"].isNull ? [:] : initial["credentials"]; disabled = initial["disabled"].bool }
        }
    }
    func converted(_ field: JSONValue) -> JSONValue { var value = field; if value["type"] == "bool" { value["type"] = "boolean" }; if value["type"] == "enum" { value["type"] = "string" }; return value }
    func save() async {
        busy = true; defer { busy = false }
        do {
            for key in fields {
                let field = metadata["config_schema"]["fields"][key]
                if field["required"].bool && (credentials[key].isNull || credentials[key] == "") { throw ClientError.message("\(key.fieldLabel) is required.") }
                if field["type"] != "secret" { try SchemaCatalog.shared.validate(credentials[key], schema: converted(field), name: key) }
            }
            _ = try await store.api?.call(path, method: "PUT", body: ["credentials": credentials, "disabled": .bool(disabled)])
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
