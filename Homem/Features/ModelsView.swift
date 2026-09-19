import SwiftUI

struct ModelsView: View {
    @Environment(AppStore.self) private var store
    var providerID: String? = nil
    @State private var catalog: ModelCatalog?
    var body: some View {
        Group {
            if let catalog { ModelsContent(catalog: catalog, providerID: providerID) }
            else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }.navigationTitle("Models".localized)
            .task {
                guard catalog == nil, let api = store.api else { return }
                let value = ModelCatalog(api: api)
                value.changed = { store.modelCatalogRevision += 1 }
                catalog = value; await value.load()
            }
    }
}

private struct ModelEdit: Identifiable {
    let id = UUID()
    let record: Record?
    let providerID: String
}
private struct ModelBulkAction: Identifiable {
    let id = UUID()
    let records: [Record]
    let enabled: Bool
    let scope: String
}

private struct ModelsContent: View {
    @Environment(AppStore.self) private var store
    @Bindable var catalog: ModelCatalog
    let providerID: String?
    @State private var search = ""
    @State private var edit: ModelEdit?
    @State private var deletion: Record?
    @State private var bulk: ModelBulkAction?
    @State private var importProvider: Record?
    private var groups: [ModelProviderGroup] { catalog.groups.filter { providerID == nil || $0.id == providerID } }
    private var allModels: [Record] { groups.flatMap(\.models) }
    private var matchingGroups: [ModelProviderGroup] {
        groups.compactMap { group in
            let items = group.models.filter { search.isEmpty || group.title.localizedCaseInsensitiveContains(search) || $0.title.localizedCaseInsensitiveContains(search) || $0.value["model_id"].string.localizedCaseInsensitiveContains(search) }
            guard search.isEmpty || !items.isEmpty else { return nil }
            return ModelProviderGroup(id: group.id, provider: group.provider, models: items)
        }
    }
    var body: some View {
        List {
            if let error = catalog.error { ErrorBanner(message: error) { Task { await catalog.load() } } }
            ForEach(matchingGroups) { group in
                Section {
                    ForEach(group.models) { model in
                        modelRow(model, managed: group.managed)
                    }
                    if group.models.isEmpty {
                        Text("No models".localized).font(.subheadline).foregroundStyle(.secondary)
                    }
                } header: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(group.title).font(.headline).foregroundStyle(.primary).textCase(nil)
                            Text(AppLocalization.format("%lld of %lld enabled", group.enabledCount, group.models.count)).font(.caption).textCase(nil)
                        }
                        Spacer(minLength: 8)
                        Menu {
                            // Bulk operations intentionally use the full group, not search results.
                            let full = groups.first { $0.id == group.id }?.models ?? []
                            Button("Enable all".localized, systemImage: "checkmark.circle") { bulk = ModelBulkAction(records: full, enabled: true, scope: group.title) }
                                .disabled(full.allSatisfy { ModelCatalog.enabled($0) })
                            Button("Disable all".localized, systemImage: "pause.circle") { bulk = ModelBulkAction(records: full, enabled: false, scope: group.title) }
                                .disabled(full.allSatisfy { !ModelCatalog.enabled($0) })
                            if !group.provider.isNull {
                                Divider()
                                Button("Refresh models".localized, systemImage: "arrow.clockwise") { importProvider = Record(value: group.provider) }
                                if !group.managed { Button("Add model".localized, systemImage: "plus") { edit = ModelEdit(record: nil, providerID: group.id) } }
                            }
                        } label: { Image(systemName: "ellipsis.circle").font(.body).frame(minWidth: 44, minHeight: 44) }
                            .disabled(catalog.working || catalog.loading).accessibilityLabel(AppLocalization.format("Actions for %@", group.title))
                    }.padding(.vertical, 4)
                }
            }
        }.navigationTitle("Models".localized).navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Search models".localized)
            .overlay {
                if catalog.loading && catalog.models.isEmpty { ProgressView() }
                else if matchingGroups.isEmpty && catalog.error == nil { ContentUnavailableView("No models".localized, systemImage: "cpu") }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Add model".localized, systemImage: "plus") { edit = ModelEdit(record: nil, providerID: providerID ?? "") }
                        Button("Refresh".localized, systemImage: "arrow.clockwise") { Task { await catalog.load() } }
                        Divider()
                        Button("Enable all".localized, systemImage: "checkmark.circle") { bulk = ModelBulkAction(records: allModels, enabled: true, scope: "All models".localized) }
                            .disabled(allModels.allSatisfy { ModelCatalog.enabled($0) })
                        Button("Disable all".localized, systemImage: "pause.circle") { bulk = ModelBulkAction(records: allModels, enabled: false, scope: "All models".localized) }
                            .disabled(allModels.allSatisfy { !ModelCatalog.enabled($0) })
                    } label: {
                        if catalog.bulkRunning { ProgressView() } else { Image(systemName: "ellipsis") }
                    }.disabled(catalog.working || catalog.loading).accessibilityLabel("Model actions".localized)
                }
            }
            .refreshable { await catalog.load() }
            .sheet(item: $edit, onDismiss: { Task { await catalog.load() } }) { selection in
                if let operation = SchemaCatalog.shared.operation(selection.record == nil ? "/models" : "/models/{id}", selection.record == nil ? "POST" : "PUT") {
                    SchemaEditor(title: selection.record == nil ? "Add model" : "Edit model", path: selection.record.map { "/models/" + $0.id.pathComponent } ?? "/models", operation: operation,
                                 initial: selection.record?.value ?? ["provider_id": .string(selection.providerID), "enable": true, "type": "chat"], onSaved: { _ in catalog.changed?() })
                }
            }
            .sheet(item: $importProvider, onDismiss: { Task { await catalog.load(); catalog.changed?() } }) { provider in
                NavigationStack {
                    Form {
                        Section(provider.title) {
                            ResourceActionButton(title: "Refresh models", path: "/providers/" + provider.id.pathComponent + "/import-models")
                        }
                    }.navigationTitle("Refresh models".localized).navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done".localized) { importProvider = nil } } }
                }
            }
            .alert(AppLocalization.format("Delete %@?", deletion?.title ?? "Model".localized), isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } })) {
                Button("Delete".localized, role: .destructive) { if let model = deletion { Task { await catalog.remove(model) } } }
                Button("Cancel".localized, role: .cancel) {}
            } message: { Text("This removes the model from your server. Agents using it may need another model.".localized) }
            .alert(bulk?.enabled == true ? "Enable all models?".localized : "Disable all models?".localized, isPresented: Binding(get: { bulk != nil }, set: { if !$0 { bulk = nil } })) {
                Button((bulk?.enabled == true ? "Enable all" : "Disable all").localized) {
                    if let action = bulk { Task { await catalog.setAll(action.records, enabled: action.enabled) } }
                }
                Button("Cancel".localized, role: .cancel) {}
            } message: {
                Text(AppLocalization.format("%@ · %lld models. Includes models hidden by search.", bulk?.scope ?? "", bulk?.records.count ?? 0))
            }
    }
    private func modelRow(_ model: Record, managed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.title).font(.body.weight(.medium)).foregroundStyle(ModelCatalog.enabled(model) ? .primary : .secondary).lineLimit(3)
                    if model.title != model.value["model_id"].string, !model.value["model_id"].string.isEmpty {
                        Text(model.value["model_id"].string).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(2)
                    }
                    if model.value["type"] == "embedding" { Text("Embedding".localized).font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Toggle("Enabled".localized, isOn: Binding(get: { ModelCatalog.enabled(model) }, set: { enabled in Task { await catalog.setEnabled(model, enabled: enabled) } }))
                    .labelsHidden().fixedSize().disabled(catalog.loading || catalog.bulkRunning || catalog.busyIDs.contains(model.id))
                    .accessibilityLabel(AppLocalization.format("Enable %@", model.title))
                Button { Task { await catalog.test(model) } } label: {
                    if catalog.busyIDs.contains(model.id) { ProgressView().frame(width: 44, height: 44) }
                    else { Image(systemName: "bolt").frame(width: 44, height: 44) }
                }.buttonStyle(.borderless).disabled(catalog.loading || catalog.bulkRunning || catalog.busyIDs.contains(model.id))
                    .accessibilityLabel(AppLocalization.format("Test %@", model.title))
                Menu {
                    if !managed {
                        Button("Edit".localized, systemImage: "slider.horizontal.3") { edit = ModelEdit(record: model, providerID: model.value["provider_id"].string) }
                        Button("Delete".localized, systemImage: "trash", role: .destructive) { deletion = model }
                    }
                    NavigationLink("Details".localized, systemImage: "info.circle") { List { JSONDetails(value: model.value) }.navigationTitle(model.title) }
                } label: { Image(systemName: "ellipsis").frame(width: 32, height: 44) }.disabled(catalog.loading || catalog.working)
                    .accessibilityLabel(AppLocalization.format("Actions for %@", model.title))
            }
            if let result = catalog.results[model.id] {
                let success = result["status"] == "ok"
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: success ? "checkmark.circle.fill" : "exclamationmark.circle")
                    Text(success ? "Connection successful".localized : result["message"].string.nonEmpty ?? "Test failed".localized)
                    if success, !result["latency_ms"].isNull { Text(AppLocalization.format("%@ ms", result["latency_ms"].scalar)).monospacedDigit() }
                }.font(.caption).foregroundStyle(success ? .green : .orange)
            }
            if let error = catalog.rowErrors[model.id] { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
        }.padding(.vertical, 5)
    }
}
