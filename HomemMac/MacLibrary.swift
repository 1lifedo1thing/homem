import SwiftUI

/// The same API operations and schemas power management on every platform.
struct MacLibrary: View {
    let api: APIClient
    let botID: String
    @Environment(AppStore.self) private var store
    @State private var selection = "Memories"
    private var resources: [ResourceSpec] {
        var values: [ResourceSpec] = [
            .memory(botID), .schedules(botID), .mcp(botID), .skills(botID), .apps(botID),
            .bot(botID, "agents", title: "Agent runtimes", icon: "cpu", detail: "/bots/{bot_id}/agents/{id}"),
            .bot(botID, "connectors", title: "Connected accounts", icon: "link", detail: "/bots/{bot_id}/connectors/{connection_id}")
        ]
        if store.canAdmin { values += [
            .global("/models", title: "Models", icon: "cpu"), .global("/providers", title: "Providers", icon: "network"),
            .global("/search-providers", title: "Search providers", icon: "magnifyingglass"), .global("/fetch-providers", title: "Web fetch providers", icon: "globe"),
            .global("/speech-models", title: "Speech models", icon: "waveform"), .global("/transcription-models", title: "Transcription models", icon: "mic")
        ] }
        let canManage = store.canAdmin || store.bots.first { $0.id == botID }?.value["current_user_permissions"].array.contains("manage") == true
        if !canManage { values = values.map { var spec = $0; spec.canCreate = false; spec.canEdit = false; spec.canDelete = false; return spec } }
        return values
    }
    var body: some View {
        HSplitView {
            List(selection: $selection) {
                Section("Agent Library") {
                    ForEach(resources.filter { $0.path.hasPrefix("/bots/") }, id: \.title) { spec in Label(spec.title.localized, systemImage: spec.icon).tag(spec.title) }
                }
                if store.canAdmin { Section("Workspace Settings") {
                    ForEach(resources.filter { !$0.path.hasPrefix("/bots/") }, id: \.title) { spec in Label(spec.title.localized, systemImage: spec.icon).tag(spec.title) }
                } }
            }.listStyle(.sidebar).frame(minWidth: 180, idealWidth: 220, maxWidth: 280)
            if let spec = resources.first(where: { $0.title == selection }) {
                MacResourceList(api: api, spec: spec).id(spec.path)
            }
        }
    }
}

struct MacResourceList: View {
    let api: APIClient
    let spec: ResourceSpec
    @State private var records: [Record] = []
    @State private var selection: String?
    @State private var search = ""
    @State private var editing = false
    @State private var creating = false
    @State private var deleting = false
    @State private var busy = false
    @State private var error: String?
    private var selected: Record? { records.first { $0.id == selection } }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(spec.title.localized).font(.headline)
                Spacer()
                TextField("Search", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }.help("Refresh")
                if spec.createOperation != nil { Button { creating = true } label: { Image(systemName: "plus") }.help("Add item") }
            }.controlSize(.small).padding(12)
            if let error { MacError(message: error) { Task { await load() } } }
            HSplitView {
                List(records.filter { search.isEmpty || $0.value.pretty.localizedCaseInsensitiveContains(search) }, selection: $selection) { record in
                    VStack(alignment: .leading, spacing: 4) { Text(record.title); if !record.subtitle.isEmpty { Text(record.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2) } }.padding(.vertical, 4).tag(record.id)
                }.frame(minWidth: 180, idealWidth: 260)
                if let selected {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(selected.title).font(.title2.weight(.semibold))
                            ForEach(selected.value.object.keys.sorted(), id: \.self) { key in
                                if !["api_key", "token", "secret", "password"].contains(key) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(key.fieldLabel.localized).font(.caption).foregroundStyle(.secondary)
                                        let value = selected.value[key]
                                        if value.object.isEmpty && value.array.isEmpty { Text(value.scalar).textSelection(.enabled) }
                                        else { DisclosureGroup("Details") { MacCode(text: value.pretty, language: "json") } }
                                    }
                                }
                            }
                            HStack {
                                if spec.editOperation != nil { Button("Edit…") { editing = true } }
                                if spec.deleteOperation != nil { Button("Delete…", role: .destructive) { deleting = true } }
                            }
                        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(minWidth: 260)
                } else { ContentUnavailableView("Select an item", systemImage: spec.icon).frame(minWidth: 260) }
            }
            if busy { ProgressView().controlSize(.small).padding(8) }
        }
        .task { await load() }
        .sheet(isPresented: $creating) {
            if let op = spec.createOperation { MacResourceEditor(api: api, title: "Add \(spec.title.localized)", path: spec.path, operation: op) { Task { await load() } } }
        }
        .sheet(isPresented: $editing) {
            if let selected, let op = spec.editOperation { MacResourceEditor(api: api, title: selected.title, path: spec.itemPath(selected), operation: op, initial: selected.value) { Task { await load() } } }
        }
        .alert("Delete Item?", isPresented: $deleting) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { if let selected { Task { do { _ = try await api.call(spec.itemPath(selected), method: "DELETE"); selection = nil; await load() } catch { self.error = error.localizedDescription } } } }
        } message: { Text("This removes the selected item from your Memoh server.") }
    }
    private func load() async {
        busy = true; defer { busy = false }
        do { records = try await api.call(spec.path).items.map(spec.record); error = nil } catch { self.error = error.localizedDescription }
    }
}

struct MacResourceEditor: View {
    let api: APIClient
    let title: String
    let path: String
    let operation: APIOperation
    var initial: JSONValue = .null
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var value: JSONValue = [:]
    @State private var complex: [String: String] = [:]
    @State private var references: [String: [Record]] = [:]
    @State private var busy = false
    @State private var error: String?
    private var schema: JSONValue { SchemaCatalog.shared.resolve(operation.bodySchema) }
    private var fields: [String] { SchemaCatalog.shared.fields(schema) }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text(title).font(.title2.weight(.semibold)); Spacer() }.padding(20)
            Form {
                ForEach(fields, id: \.self) { key in field(key) }
                if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            }.formStyle(.grouped)
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Save") { save() }.keyboardShortcut(.defaultAction).disabled(busy) }.padding(20)
        }.frame(width: 560, height: 600)
        .task {
            for key in fields {
                let field = SchemaCatalog.shared.resolve(schema["properties"][key])
                if !initial[key].isNull && !isSecret(key) { value[key] = initial[key] }
                else if !field["default"].isNull { value[key] = field["default"] }
                if ["object", "array"].contains(field["type"].string) { complex[key] = value[key].isNull ? "" : value[key].pretty }
                let source = key == "provider_id" ? "/providers" : key == "model_id" ? "/models" : AgentSettingsFields.source(key, botID: path.split(separator: "/").dropFirst().first.map(String.init) ?? "")
                if let source, let response = try? await api.call(source) { references[key] = response.items.map(Record.init) }
            }
        }
    }
    @ViewBuilder private func field(_ key: String) -> some View {
        let prop = SchemaCatalog.shared.resolve(schema["properties"][key])
        let label = AgentSettingsFields.label(key).localized
        if prop["type"] == "boolean" {
            Toggle(label, isOn: Binding(get: { value[key].bool }, set: { value[key] = .bool($0) }))
        } else if !prop["enum"].array.isEmpty {
            Picker(label, selection: string(key)) { Text("Default").tag(""); ForEach(prop["enum"].array, id: \.self) { Text($0.scalar).tag($0.scalar) } }
        } else if let options = references[key], !options.isEmpty {
            Picker(label, selection: string(key)) {
                Text("None").tag("")
                ForEach(options) { Text($0.title).tag($0.id) }
                if !value[key].string.isEmpty && !options.contains(where: { $0.id == value[key].string }) { Text(value[key].string).tag(value[key].string) }
            }
        } else if ["object", "array"].contains(prop["type"].string) {
            DisclosureGroup(label) { TextEditor(text: Binding(get: { complex[key] ?? "" }, set: { complex[key] = $0 })).font(.system(size: 12, design: .monospaced)).frame(height: 120) }
        } else if isSecret(key) {
            SecureField(label, text: string(key))
        } else {
            TextField(label, text: string(key), axis: .vertical).lineLimit(1...6)
        }
    }
    private func isSecret(_ key: String) -> Bool { key.contains("password") || key.contains("api_key") || key == "secret" || key == "token" }
    private func string(_ key: String) -> Binding<String> { Binding(get: { value[key].isNull ? "" : value[key].scalar }, set: { value[key] = .string($0) }) }
    private func save() {
        busy = true
        Task {
            defer { busy = false }
            do {
                var body: JSONValue = [:]
                for key in fields {
                    let prop = SchemaCatalog.shared.resolve(schema["properties"][key])
                    if ["object", "array"].contains(prop["type"].string) { if let text = complex[key], !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { body[key] = try JSONValue.parse(text) } }
                    else if ["integer", "number"].contains(prop["type"].string) {
                        if !value[key].isNull && !value[key].scalar.isEmpty {
                            guard let number = Double(value[key].scalar) else { throw ClientError.message("\(key.fieldLabel) must be a number.") }; body[key] = .number(number)
                        }
                    } else if !value[key].isNull { body[key] = value[key] }
                }
                if path.hasSuffix("/settings") && !initial.isNull {
                    body = AgentSettingsFields.changes(from: initial, to: body, allowed: Set(fields))
                }
                try SchemaCatalog.shared.validate(body, schema: schema)
                _ = try await api.call(path, method: operation.method, body: body)
                onSave(); dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
