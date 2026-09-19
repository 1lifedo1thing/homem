import SwiftUI

/// Server identifiers are selected from the owning collection, never typed from memory.
enum ResourceFormReferences {
    static func source(for name: String, path: String) -> String? {
        let parts = path.split(separator: "/")
        let bot = parts.first == "bots" && parts.count > 1 ? "/bots/\(parts[1])" : nil
        if let source = AgentSettingsFields.source(name, botID: parts.count > 1 ? String(parts[1]).removingPercentEncoding ?? String(parts[1]) : "") { return source }
        switch name {
        case "bot_id": return "/bots"
        case "user_id", "owner_user_id": return bot.map { $0 + "/user-access/candidates" } ?? "/users"
        case "channel_identity_id": return bot.map { $0 + "/acl/channel-identities" }
        case "provider_id":
            for kind in ["speech", "transcription", "video"] where path.hasPrefix("/\(kind)-") { return "/\(kind)-providers" }
            return "/providers"
        case "model_id", "chat_model_id", "image_model_id", "compaction_model_id": return "/models"
        case "search_provider_id": return "/search-providers"
        case "fetch_provider_id": return "/fetch-providers"
        case "memory_provider_id": return "/memory-providers"
        case "bot_agent_id", "default_bot_agent_id": return bot.map { $0 + "/agents" }
        case "runtime_id": return "/users/me/runtimes"
        case "session_id": return bot.map { $0 + "/sessions" }
        case "workdir_id": return bot.map { $0 + "/workdirs" }
        case "target_id": return bot.map { $0 + "/workspace-targets" }
        default: return nil
        }
    }
    static func label(_ name: String) -> String {
        let names = ["user_id": "Person", "owner_user_id": "Owner", "channel_identity_id": "Channel account", "provider_id": "Provider", "model_id": "Model", "bot_id": "Agent", "bot_agent_id": "Agent runtime", "session_id": "Conversation", "runtime_id": "Computer", "workdir_id": "Working directory", "target_id": "Run on", "snapshot_name": "Name"]
        return names[name] ?? AgentSettingsFields.label(name)
    }
}

struct ResourceFormField: View {
    let name: String
    let schema: JSONValue
    let required: Bool
    @Binding var value: JSONValue
    let path: String
    var body: some View {
        if let source = ResourceFormReferences.source(for: name, path: path) {
            ResourceReferencePicker(title: ResourceFormReferences.label(name), source: source, required: required, value: $value)
        } else if schema["type"] == "array" {
            NavigationLink {
                ResourceArrayEditor(title: ResourceFormReferences.label(name), schema: SchemaCatalog.shared.resolve(schema["items"]), value: $value, path: path)
            } label: {
                LabeledContent(ResourceFormReferences.label(name).localized, value: "\(value.array.count)")
            }
        } else if !schema["properties"].object.isEmpty {
            NavigationLink(ResourceFormReferences.label(name).localized) {
                Form {
                    ForEach(SchemaCatalog.shared.fields(schema), id: \.self) { key in
                        AnyView(ResourceFormField(name: key, schema: SchemaCatalog.shared.resolve(schema["properties"][key]), required: schema["required"].array.contains(.string(key)), value: Binding(get: { value[key] }, set: { value[key] = $0 }), path: path))
                    }
                }.navigationTitle(ResourceFormReferences.label(name).localized)
            }
        } else if schema["type"] == "object" || schema.object.isEmpty {
            NavigationLink(ResourceFormReferences.label(name).localized) { ResourceDictionaryEditor(value: $value, path: path).navigationTitle(ResourceFormReferences.label(name).localized) }
        } else {
            SchemaField(name: name, schema: fieldSchema, required: required, value: $value,
                        displayName: ResourceFormReferences.label(name).localized, showDescription: false)
        }
    }
    private var fieldSchema: JSONValue {
        var s = schema
        if name == "effect" && s["enum"].array.isEmpty { s["enum"] = ["allow", "deny"] }
        return s
    }
}

struct ResourceReferencePicker: View {
    @Environment(AppStore.self) private var store
    let title: String
    let source: String
    let required: Bool
    @Binding var value: JSONValue
    @State private var choices: [Record] = []
    @State private var error: String?
    @State private var loading = true
    private var selection: Binding<String> { Binding(get: { value.string }, set: { value = $0.isEmpty ? .null : .string($0) }) }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(title.localized, selection: selection) {
                Text((required ? "Choose" : "Default").localized).tag("")
                if !value.string.isEmpty && !choices.contains(where: { $0.id == value.string }) { Text("Current selection".localized).tag(value.string) }
                ForEach(choices) { row in Text(row.title).tag(row.id) }
            }.disabled(loading)
            if let error { ErrorBanner(message: error) { Task { await load() } } }
        }.task(id: source) { await load() }
    }
    private func load() async {
        loading = true; defer { loading = false }
        do {
            let response = try await store.api?.call(source) ?? .null
            let rows = response.items.isEmpty ? (response["targets"].array.isEmpty ? response["candidates"].array : response["targets"].array) : response.items
            choices = rows.map { value in
                var row = value
                if row["id"].string.isEmpty { row["id"] = .string(row.text("user_id", "channel_identity_id", "runtime_id", "target_id")) }
                if row.displayTitle == row["id"].string { row["display_name"] = .string(row.text("display_name", "username", "name", "title", "platform").nonEmpty ?? "Untitled".localized) }
                return Record(value: row)
            }.filter { !$0.value["id"].string.isEmpty }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct ResourceArrayEditor: View {
    let title: String
    let schema: JSONValue
    @Binding var value: JSONValue
    let path: String
    var body: some View {
        Form {
            ForEach(value.array.indices, id: \.self) { index in
                ResourceFormField(name: "Value", schema: schema, required: false, value: Binding(get: { value.array.indices.contains(index) ? value.array[index] : .null }, set: { new in var rows = value.array; guard rows.indices.contains(index) else { return }; rows[index] = new; value = .array(rows) }), path: path)
            }.onDelete { offsets in var rows = value.array; rows.remove(atOffsets: offsets); value = .array(rows) }
            Button("Add value".localized, systemImage: "plus") {
                let initial: JSONValue = schema["type"] == "object" ? [:] : schema["type"] == "boolean" ? false : .string("")
                value = .array(value.array + [initial])
            }
        }.navigationTitle(title.localized)
    }
}

struct ResourceDictionaryEditor: View {
    @Binding var value: JSONValue
    let path: String
    @State private var adding = false
    @State private var key = ""
    var body: some View {
        Form {
            ForEach(value.object.keys.sorted(), id: \.self) { key in
                ResourceFormField(name: key, schema: inferred(value[key]), required: false, value: Binding(get: { value[key] }, set: { value[key] = $0 }), path: path)
                    .swipeActions { Button("Delete".localized, role: .destructive) { var object = value.object; object.removeValue(forKey: key); value = .object(object) } }
            }
            Button("Add setting".localized, systemImage: "plus") { key = ""; adding = true }
        }.alert("Add setting".localized, isPresented: $adding) {
            TextField("Name".localized, text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Add".localized) { let name = key.trimmingCharacters(in: .whitespaces); if !name.isEmpty && value[name].isNull { value[name] = "" } }
            Button("Cancel".localized, role: .cancel) {}
        }
    }
    private func inferred(_ item: JSONValue) -> JSONValue {
        switch item {
        case .bool: return ["type": "boolean"]
        case .number: return ["type": "number"]
        case .array: return ["type": "array", "items": item.array.first.map(inferred) ?? ["type": "string"]]
        case .object: return ["type": "object"]
        default: return ["type": "string"]
        }
    }
}
