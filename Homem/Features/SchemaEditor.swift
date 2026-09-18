import SwiftUI

struct SchemaEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var title: String
    var path: String
    var operation: APIOperation
    var initial: JSONValue = .object([:])
    var query: [String: String] = [:]
    var onSaved: ((JSONValue) -> Void)? = nil
    @State private var draft: JSONValue = .object([:])
    @State private var busy = false
    @State private var error: String?
    @State private var advanced = false
    @State private var progress = ""
    private var schema: JSONValue { SchemaCatalog.shared.resolve(operation.bodySchema) }
    private var fields: [String] { SchemaCatalog.shared.fields(schema) }
    var body: some View {
        NavigationStack {
            Form {
                if !operation.definition["description"].string.isEmpty { Section { Text(operation.definition["description"].string).font(.subheadline).foregroundStyle(.secondary) } }
                if fields.isEmpty && !operation.bodySchema.isNull {
                    Section("Configuration".localized) { JSONInput(value: $draft) }
                } else {
                    Section {
                        ForEach(Array(fields.prefix(10)), id: \.self) { key in field(key) }
                    }
                    if fields.count > 10 {
                        Section { DisclosureGroup("Advanced options".localized, isExpanded: $advanced) { ForEach(Array(fields.dropFirst(10)), id: \.self) { key in field(key) } } }
                    }
                }
                if let error { Section { ErrorBanner(message: error) } }
                if !progress.isEmpty { Section("Progress".localized) { Text(progress).font(.caption.monospaced()) } }
                if store.isDemo { Section { DemoBadge() } }
            }.navigationTitle(title.localized).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel".localized) { dismiss() }.disabled(busy) }
                    ToolbarItem(placement: .confirmationAction) { Button { Task { await save() } } label: { if busy { ProgressView() } else { Text(operation.method == "DELETE" ? "Delete".localized : "Save".localized).fontWeight(.semibold) } }.disabled(busy) }
                }
                .onAppear {
                    let allowed = Set(fields)
                    draft = .object(initial.object.filter { allowed.contains($0.key) })
                    if fields.isEmpty { draft = initial }
                    if path.hasSuffix("/schedule"), initial.object.isEmpty { draft["enabled"] = true; draft["run_target"] = "new_session" }
                    if path == "/bots", initial.object.isEmpty { draft["is_active"] = true; draft["timezone"] = .string(TimeZone.current.identifier) }
                }
        }.interactiveDismissDisabled(busy)
    }
    @ViewBuilder private func field(_ key: String) -> some View {
        let s = SchemaCatalog.shared.resolve(schema["properties"][key])
        let binding = Binding<JSONValue>(get: { draft[key] }, set: { draft[key] = $0 })
        SchemaField(name: key, schema: s, required: schema["required"].array.contains(.string(key)), value: binding)
    }
    private func save() async {
        busy = true; error = nil; defer { busy = false }
        do {
            for required in schema["required"].array.map(\.string) {
                if draft[required].isNull || draft[required] == .string("") { throw ClientError.message(AppLocalization.format("%@ is required.", required.fieldLabel.localized)) }
            }
            // Optional empty fields are omitted; explicitly entered false and zero remain intact.
            let body = JSONValue.object(draft.object.filter { !$0.value.isNull })
            try SchemaCatalog.shared.validate(body, schema: schema)
            guard let api = store.api else { return }
            let result: JSONValue
            if operation.definition["produces"].array.contains("text/event-stream") {
                result = try await api.streamOperation(path, method: operation.method, query: query, body: operation.bodySchema.isNull ? nil : body) { event in
                    let line = event.text("message", "data", "detail", "status")
                    if !line.isEmpty { progress = String((progress + "\n" + line).suffix(12000)) }
                }
            } else { result = try await api.call(path, method: operation.method, query: query, body: operation.bodySchema.isNull ? nil : body) }
            onSaved?(result); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct SchemaField: View {
    let name: String
    let schema: JSONValue
    var required: Bool
    @Binding var value: JSONValue
    var displayName: String? = nil
    var showDescription = true
    private var label: String { (displayName ?? name.fieldLabel.localized) + (required ? " *" : "") }
    private var stringBinding: Binding<String> { Binding(get: { value.isNull ? "" : value.scalar }, set: { value = $0.isEmpty ? .null : .string($0) }) }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !schema["enum"].array.isEmpty {
                Picker(label, selection: stringBinding) {
                    Text("Default".localized).tag("")
                    ForEach(schema["enum"].array, id: \.self) { v in Text(v.scalar).tag(v.scalar) }
                }
            } else if schema["type"].string == "boolean" {
                Toggle(label, isOn: Binding(get: { value.bool }, set: { value = .bool($0) }))
            } else if ["integer", "number"].contains(schema["type"].string) {
                LabeledContent(label) {
                    TextField("Default".localized, text: Binding(get: { value.isNull ? "" : value.scalar }, set: { value = $0.isEmpty ? .null : Double($0).map(JSONValue.number) ?? .string($0) }))
                        .keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing)
                }
            } else if !schema["properties"].object.isEmpty {
                DisclosureGroup(label) {
                    ForEach(SchemaCatalog.shared.fields(schema), id: \.self) { key in
                        AnyView(SchemaField(name: key, schema: SchemaCatalog.shared.resolve(schema["properties"][key]), required: schema["required"].array.contains(.string(key)), value: Binding(get: { value[key] }, set: { value[key] = $0 }), showDescription: showDescription))
                    }
                }
            } else if ["object", "array"].contains(schema["type"].string) || !schema["properties"].object.isEmpty || schema.object.isEmpty {
                DisclosureGroup(label) { JSONInput(value: $value) }
            } else if name.contains("key") && !name.hasSuffix("_id") || name.contains("password") || name.contains("secret") || name == "token" {
                SecureField(label, text: stringBinding).textInputAutocapitalization(.never).autocorrectionDisabled()
            } else if displayName != nil {
                LabeledContent(label) {
                    TextField("Default".localized, text: stringBinding, axis: .vertical)
                        .multilineTextAlignment(.trailing).lineLimit(1...4)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
            } else {
                TextField(label, text: stringBinding, axis: .vertical).lineLimit(1...8).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            if showDescription && !schema["description"].string.isEmpty { Text(schema["description"].string).font(.caption2).foregroundStyle(.secondary) }
        }.padding(.vertical, 2)
    }
}

struct JSONInput: View {
    @Binding var value: JSONValue
    @State private var text = ""
    @State private var invalid = false
    var body: some View {
        TextEditor(text: $text).font(.system(.footnote, design: .monospaced)).frame(minHeight: 150).autocorrectionDisabled().textInputAutocapitalization(.never)
            .onAppear { text = value.isNull ? "{}" : value.pretty }
            .onChange(of: text) { _, v in
                if let parsed = try? JSONValue.parse(v) { value = parsed; invalid = false }
                else { value = .string(v); invalid = true }
            }
        if invalid { Text("Enter valid JSON before saving.".localized).font(.caption).foregroundStyle(.red) }
    }
}

struct OperationButton: View {
    var title: String
    var path: String
    var template: String
    var method: String
    @State private var show = false
    var body: some View {
        if let op = SchemaCatalog.shared.operation(template, method) {
            Button(title.localized) { show = true }.sheet(isPresented: $show) { OperationView(operation: op, suppliedPath: path) }
        }
    }
}

struct OperationBrowser: View {
    var prefix = ""
    var substitutions: [String: String] = [:]
    @State private var search = ""
    private var operations: [APIOperation] { SchemaCatalog.shared.operations.filter { $0.path.hasPrefix(prefix) && (search.isEmpty || ($0.title + $0.path).localizedCaseInsensitiveContains(search)) } }
    var body: some View {
        List {
            Section { Text("Advanced server controls. Forms follow the API version bundled with Homem. Your server enforces permissions and feature availability.".localized).font(.caption).foregroundStyle(.secondary) }
            ForEach(operations) { op in
                NavigationLink { OperationView(operation: op, substitutions: substitutions) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(op.title)
                        Text(op.method + " " + op.path).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
        }.navigationTitle("Advanced controls".localized).searchable(text: $search)
    }
}

struct OperationView: View {
    @Environment(AppStore.self) private var store
    var operation: APIOperation
    var substitutions: [String: String] = [:]
    var suppliedPath: String? = nil
    @State private var values: [String: String] = [:]
    @State private var result: JSONValue = .null
    @State private var error: String?
    @State private var busy = false
    @State private var edit = false
    @State private var confirm = false
    private var parameters: [JSONValue] { operation.parameters.filter { ["path", "query"].contains($0["in"].string) && !(suppliedPath != nil && $0["in"].string == "path") } }
    private var path: String {
        if let suppliedPath { return suppliedPath }
        return values.reduce(operation.path) { $0.replacingOccurrences(of: "{\($1.key)}", with: $1.value.pathComponent) }
    }
    private var query: [String: String] { Dictionary(uniqueKeysWithValues: parameters.filter { $0["in"].string == "query" }.compactMap { p in let k = p["name"].string; guard let v = values[k], !v.isEmpty else { return nil }; return (k, v) }) }
    var body: some View {
        Form {
            Section { Text(operation.definition["description"].string.nonEmpty ?? operation.title).font(.subheadline).foregroundStyle(.secondary) }
            if !parameters.isEmpty { Section("Parameters".localized) { ForEach(parameters, id: \.self) { p in
                TextField(p["name"].string.fieldLabel + (p["required"].bool ? " *" : ""), text: Binding(get: { values[p["name"].string] ?? "" }, set: { values[p["name"].string] = $0 })).textInputAutocapitalization(.never).autocorrectionDisabled()
            } } }
            Section {
                if operation.parameters.contains(where: { $0["type"].string == "file" }) || operation.path.hasSuffix("/ws") || operation.method == "GET" && operation.definition["produces"].array.contains("text/event-stream") {
                    Text("Use the dedicated workspace, chat, or backup screen for this streaming or file operation.".localized).foregroundStyle(.secondary)
                } else {
                    Button(operation.method == "GET" ? "Load".localized : operation.bodySchema.isNull ? "Run action".localized : "Configure action".localized, role: operation.method == "DELETE" ? .destructive : nil) {
                        if operation.method == "DELETE" { confirm = true }
                        else if !operation.bodySchema.isNull { edit = true }
                        else { Task { await run() } }
                    }.disabled(busy || path.contains("{") || parameters.contains { $0["required"].bool && (values[$0["name"].string] ?? "").isEmpty })
                }
                if busy { ProgressView() }
            }
            if let error { ErrorBanner(message: error) }
            if !result.isNull { Section("Result".localized) { JSONDetails(value: result) } }
        }.navigationTitle(operation.title).navigationBarTitleDisplayMode(.inline)
            .onAppear { values = substitutions }
            .sheet(isPresented: $edit) { SchemaEditor(title: operation.title, path: path, operation: operation, query: query, onSaved: { result = $0 }) }
            .confirmationDialog("\(operation.title)?", isPresented: $confirm, titleVisibility: .visible) { Button("Delete".localized, role: .destructive) { Task { await run() } } } message: { Text("This action changes data on your server and may not be reversible.".localized) }
    }
    func run() async {
        busy = true; defer { busy = false }
        do {
            if operation.definition["produces"].array.contains("text/event-stream"), let api = store.api { result = try await api.streamOperation(path, method: operation.method, query: query, body: nil) { result = $0 } }
            else { result = try await store.api?.call(path, method: operation.method, query: query) ?? .null }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}
