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
    var submitTitle: String = "Save"
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
                if fields.isEmpty && !operation.bodySchema.isNull {
                    Section("Configuration".localized) { ResourceFormField(name: "Configuration", schema: schema, required: true, value: $draft, path: path) }
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
                    ToolbarItem(placement: .confirmationAction) { Button { Task { await save() } } label: { if busy { ProgressView() } else { Text(operation.method == "DELETE" ? "Delete".localized : submitTitle.localized).fontWeight(.semibold) } }.disabled(busy) }
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
        ResourceFormField(name: key, schema: s, required: schema["required"].array.contains(.string(key)), value: binding, path: path)
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
                    ForEach(schema["enum"].array, id: \.self) { v in Text(v.scalar.fieldLabel.localized).tag(v.scalar) }
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
            if op.bodySchema.isNull {
                ResourceActionButton(title: title, path: path, method: method,
                                     destructive: method == "DELETE", streaming: op.definition["produces"].array.contains("text/event-stream"))
            } else {
                Button(title.localized) { show = true }
                    .sheet(isPresented: $show) { SchemaEditor(title: title, path: path, operation: op, submitTitle: title) }
            }
        }
    }
}
