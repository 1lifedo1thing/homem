import SwiftUI

struct ResourceSpec: Hashable {
    var title: String
    var path: String
    var template: String
    var icon: String = "square.stack"
    var detailTemplate: String? = nil
    var canCreate = true
    var canEdit = true
    var canDelete = true
    var idKey = "id"
    static func bot(_ id: String, _ suffix: String, title: String, icon: String = "square.stack", detail: String? = nil) -> Self {
        .init(title: title, path: "/bots/\(id.pathComponent)/\(suffix)", template: "/bots/{bot_id}/\(suffix)", icon: icon, detailTemplate: detail)
    }
    static func memory(_ id: String) -> Self { .bot(id, "memory", title: "Memories", icon: "brain", detail: "/bots/{bot_id}/memory/{memory_id}") }
    static func schedules(_ id: String) -> Self { .bot(id, "schedule", title: "Schedules", icon: "clock.arrow.circlepath") }
    static func mcp(_ id: String) -> Self { .bot(id, "mcp", title: "MCP connections", icon: "point.3.connected.trianglepath.dotted") }
    static func skills(_ id: String) -> Self { var s = Self.bot(id, "container/skills", title: "Skills", icon: "sparkles"); s.canEdit = false; s.canDelete = false; return s }
    static func apps(_ id: String) -> Self { var s = Self.bot(id, "apps", title: "Installed apps", icon: "square.stack.3d.up", detail: "/bots/{bot_id}/apps/{installation_id}"); s.canEdit = false; return s }
    static func global(_ path: String, title: String, icon: String = "slider.horizontal.3") -> Self { .init(title: title, path: path, template: path, icon: icon) }
    var resolvedDetailTemplate: String { detailTemplate ?? template + "/{id}" }
    var substitutions: [String: String] {
        let parts = path.split(separator: "/")
        if parts.first == "bots", parts.count > 1 { return ["bot_id": String(parts[1])] }
        return [:]
    }
    var createOperation: APIOperation? { canCreate ? SchemaCatalog.shared.operation(template, "POST") : nil }
    var editOperation: APIOperation? { canEdit ? (SchemaCatalog.shared.operation(resolvedDetailTemplate, "PUT") ?? SchemaCatalog.shared.operation(resolvedDetailTemplate, "PATCH")) : nil }
    var deleteOperation: APIOperation? {
        guard canDelete else { return nil }
        return SchemaCatalog.shared.operation(resolvedDetailTemplate, "DELETE") ?? (template.hasSuffix("/memory") ? SchemaCatalog.shared.operation(template + "/{id}", "DELETE") : nil)
    }
}

struct ResourceLink: View {
    var title: String
    var icon: String
    var spec: ResourceSpec
    var body: some View { NavigationLink { ResourceListView(spec: spec) } label: { Label(title, systemImage: icon) } }
}

struct ResourceListView: View {
    @Environment(AppStore.self) private var store
    let spec: ResourceSpec
    @State private var records: [Record] = []
    @State private var loading = false
    @State private var error: String?
    @State private var search = ""
    @State private var create = false
    @State private var deletion: Record?
    var filtered: [Record] { search.isEmpty ? records : records.filter { $0.value.pretty.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        List {
            if let error { ErrorBanner(message: error) { Task { await load() } } }
            ForEach(filtered) { record in
                NavigationLink { ResourceDetailView(spec: spec, record: record) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: spec.icon).foregroundStyle(Theme.accent).frame(width: 28).padding(.top, 3)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(record.title).font(.body.weight(.medium)).lineLimit(4)
                            if !record.subtitle.isEmpty { Text(record.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                            if !record.value["pattern"].string.isEmpty { Text(record.value["pattern"].string).font(.caption.monospaced()).foregroundStyle(.secondary) }
                        }
                        Spacer(minLength: 0)
                        if !record.value["enabled"].isNull { Image(systemName: record.value["enabled"].bool ? "checkmark.circle.fill" : "pause.circle").foregroundStyle(record.value["enabled"].bool ? .green : .secondary) }
                    }.padding(.vertical, 5)
                }.swipeActions { if spec.deleteOperation != nil { Button("Delete", role: .destructive) { deletion = record } } }
            }
        }
        .overlay { if loading && records.isEmpty { ProgressView() } else if records.isEmpty && error == nil { EmptyState(title: "No \(spec.title.lowercased()) yet", symbol: spec.icon, detail: spec.createOperation == nil ? "Pull to refresh your workspace." : "Use the + button to add your first one.") } }
        .searchable(text: $search, prompt: "Search \(spec.title.lowercased())")
        .navigationTitle(spec.title)
        .toolbar { if spec.createOperation != nil { Button { create = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add \(spec.title)") } }
        .toolbar {
            Menu {
                if spec.template.hasSuffix("/memory") {
                    NavigationLink("Memory graph", systemImage: "point.3.filled.connected.trianglepath.dotted") { MemoryGraphView(path: spec.path + "/graph") }
                    if let op = SchemaCatalog.shared.operation(spec.template + "/search", "POST") { NavigationLink("Semantic search") { OperationView(operation: op, suppliedPath: spec.path + "/search") } }
                    if let op = SchemaCatalog.shared.operation(spec.template + "/compact", "POST") { NavigationLink("Compact memories") { OperationView(operation: op, suppliedPath: spec.path + "/compact") } }
                    NavigationLink("Memory usage") { ReadOnlyDocumentView(title: "Memory usage", path: spec.path + "/usage") }
                }
                NavigationLink("More actions") { OperationBrowser(prefix: spec.template, substitutions: spec.substitutions) }
            } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("More resource actions")
        }
        .task { await load() }.refreshable { await load() }
        .sheet(isPresented: $create, onDismiss: { Task { await load() } }) {
            if let operation = spec.createOperation { SchemaEditor(title: "Add \(spec.title)", path: spec.path, operation: operation) }
        }
        .confirmationDialog("Delete \(deletion?.title ?? "item")?", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let deletion { Task { await remove(deletion) } } }
        } message: { Text("This removes the item from your Memoh server.") }
    }
    private func load() async {
        guard let api = store.api else { return }; loading = true; defer { loading = false }
        do { records = try await api.call(spec.path).items.map(Record.init); error = nil } catch { self.error = error.localizedDescription }
    }
    private func remove(_ record: Record) async {
        do { _ = try await store.api?.call(spec.path + "/" + record.id.pathComponent, method: "DELETE"); deletion = nil; await load() }
        catch { self.error = error.localizedDescription }
    }
}

struct ResourceDetailView: View {
    @Environment(AppStore.self) private var store
    let spec: ResourceSpec
    let record: Record
    @State private var value: JSONValue = .null
    @State private var edit = false
    var body: some View {
        List {
            JSONDetails(value: value.isNull ? record.value : value)
            if spec.template.hasSuffix("/schedule") {
                Section { NavigationLink("Execution history") { ReadOnlyDocumentView(title: "Execution history", path: spec.path + "/\(record.id.pathComponent)/logs") } }
            }
            if spec.template.hasSuffix("/mcp") || spec.template == "/providers" || spec.template == "/models" {
                Section {
                    let suffix = spec.template.hasSuffix("/mcp") ? "/probe" : "/test"
                    OperationButton(title: "Test connection", path: spec.path + "/" + record.id.pathComponent + suffix, template: spec.resolvedDetailTemplate + suffix, method: "POST")
                }
            }
            if spec.template.hasSuffix("/mcp") || spec.template == "/providers" || spec.template == "/email-providers" {
                Section { NavigationLink("Connect account", systemImage: "lock.shield") { AuthorizationView(path: spec.path + "/" + record.id.pathComponent, isMCP: spec.template.hasSuffix("/mcp")) } }
            }
            Section { NavigationLink("More actions", systemImage: "slider.horizontal.3") { OperationBrowser(prefix: spec.resolvedDetailTemplate, substitutions: substitutions) } }
        }.navigationTitle(record.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { if spec.editOperation != nil { Button("Edit") { edit = true } } }
            .sheet(isPresented: $edit, onDismiss: { Task { await load() } }) { if let op = spec.editOperation { SchemaEditor(title: "Edit \(record.title)", path: spec.path + "/" + record.id.pathComponent, operation: op, initial: value.isNull ? record.value : value) } }
            .task { await load() }
    }
    var substitutions: [String: String] {
        var result = ["id": record.id, "memory_id": record.id, "installation_id": record.id]
        let parts = spec.path.split(separator: "/")
        if parts.first == "bots", parts.count > 1 { result["bot_id"] = String(parts[1]) }
        return result
    }
    func load() async {
        guard SchemaCatalog.shared.operation(spec.resolvedDetailTemplate, "GET") != nil else { return }
        do { value = try await store.api?.call(spec.path + "/" + record.id.pathComponent) ?? record.value } catch { /* Keep the successfully loaded list representation. */ }
    }
}

struct JSONDetails: View {
    let value: JSONValue
    var body: some View {
        if !value.object.isEmpty {
            ForEach(value.object.keys.sorted(), id: \.self) { key in
                let item = value[key]
                if !item.isNull {
                    if case .object = item { Section(key.fieldLabel) { JSONDetails(value: item) } }
                    else if case .array = item {
                        Section(key.fieldLabel) {
                            ForEach(Array(item.array.enumerated()), id: \.offset) { _, v in
                                if v.object.isEmpty { Text(v.scalar).textSelection(.enabled) }
                                else { DisclosureGroup(v.displayTitle.nonEmpty ?? "Details") { JSONDetails(value: v) } }
                            }
                        }
                    }
                    else if key.lowercased().contains("secret") || key.lowercased().contains("token") && !key.contains("tokens") || key.lowercased().contains("api_key") || key.lowercased().contains("password") { LabeledContent(key.fieldLabel, value: "••••••••") }
                    else if let url = URL(string: item.string), ["https", "http"].contains(url.scheme ?? "") { Link(key.fieldLabel, destination: url) }
                    else if item.scalar.count > 90 { VStack(alignment: .leading, spacing: 8) { Text(key.fieldLabel).font(.caption).foregroundStyle(.secondary); Text(item.scalar).textSelection(.enabled) } }
                    else { LabeledContent(key.fieldLabel) { Text(item.scalar).textSelection(.enabled) } }
                }
            }
        } else { Text(value.pretty).font(.system(.footnote, design: .monospaced)).textSelection(.enabled) }
    }
}

struct ReadOnlyDocumentView: View {
    @Environment(AppStore.self) private var store
    var title: String
    var path: String
    var query: [String: String] = [:]
    @State private var value: JSONValue = .null
    @State private var error: String?
    var body: some View {
        List { if let error { ErrorBanner(message: error) { Task { await load() } } }; if !value.isNull { JSONDetails(value: value) } }
            .overlay { if value.isNull && error == nil { ProgressView() } }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline).task { await load() }.refreshable { await load() }
    }
    func load() async { do { value = try await store.api?.call(path, query: query) ?? .null; error = nil } catch { self.error = error.localizedDescription } }
}
