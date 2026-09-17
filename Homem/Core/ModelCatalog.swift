import Foundation
import Observation

struct ModelProviderGroup: Identifiable {
    let id: String
    let provider: JSONValue
    let models: [Record]
    var title: String { provider["name"].string.nonEmpty ?? "Other models".localized }
    var managed: Bool { ["openai-codex", "github-copilot"].contains(provider["client_type"].string) }
    var enabledCount: Int { models.filter { ModelCatalog.enabled($0) }.count }
}

@MainActor @Observable final class ModelCatalog {
    let api: APIClient
    var models: [Record] = []
    var providers: [Record] = []
    var loading = false
    var error: String?
    var busyIDs: Set<String> = []
    var bulkRunning = false
    var results: [String: JSONValue] = [:]
    var rowErrors: [String: String] = [:]
    var changed: (() -> Void)?
    var working: Bool { bulkRunning || !busyIDs.isEmpty }
    init(api: APIClient) { self.api = api }
    nonisolated static func enabled(_ model: Record) -> Bool { model.value["enable"] != false }
    nonisolated static func updateBody(_ value: JSONValue, enabled: Bool) -> JSONValue {
        var body: JSONValue = .object(value.object.filter { ["model_id", "name", "provider_id", "type", "config"].contains($0.key) })
        body["enable"] = .bool(enabled)
        return body
    }
    var groups: [ModelProviderGroup] {
        let ids = Set(models.map { $0.value["provider_id"].string }).union(providers.map(\.id))
        return ids.map { id in
            let provider = providers.first { $0.id == id }?.value ?? .null
            let managed = ["openai-codex", "github-copilot"].contains(provider["client_type"].string)
            let items = models.filter { $0.value["provider_id"].string == id && (!managed || $0.value["config"]["catalog_available"] != false) }
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            return ModelProviderGroup(id: id, provider: provider, models: items)
        }.sorted {
            let order = $0.title.localizedStandardCompare($1.title)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }
    func load() async {
        guard !working else { return }
        loading = true; defer { loading = false }
        do {
            async let modelResponse = api.call("/models")
            async let providerResponse = api.call("/providers")
            let (modelValue, providerValue) = try await (modelResponse, providerResponse)
            guard !Task.isCancelled else { return }
            models = modelValue.items.map(Record.init); providers = providerValue.items.map(Record.init); error = nil
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func update(_ model: Record, enabled: Bool) async throws {
        busyIDs.insert(model.id); rowErrors[model.id] = nil
        defer { busyIDs.remove(model.id) }
        // PUT replaces configuration. Fetch the current document before changing
        // the flag so another screen's edits and unknown config keys survive.
        let latest = try await api.call("/models/" + model.id.pathComponent)
        let body = Self.updateBody(latest, enabled: enabled)
        _ = try await api.call("/models/" + model.id.pathComponent, method: "PUT", body: body)
        if let index = models.firstIndex(where: { $0.id == model.id }) {
            var value = latest; value["id"] = .string(model.id); value["enable"] = .bool(enabled)
            models[index] = Record(value: value)
        }
        if !bulkRunning { changed?() }
    }
    func setEnabled(_ model: Record, enabled: Bool) async {
        guard !loading, !bulkRunning, !busyIDs.contains(model.id) else { return }
        do { try await update(model, enabled: enabled) }
        catch { rowErrors[model.id] = error.localizedDescription }
    }
    func setAll(_ records: [Record], enabled: Bool) async {
        guard !loading, !working else { return }
        bulkRunning = true; error = nil
        defer { bulkRunning = false; changed?() }
        var failures = 0
        for model in records where Self.enabled(model) != enabled {
            guard !Task.isCancelled else { return }
            do { try await update(model, enabled: enabled) }
            catch { rowErrors[model.id] = error.localizedDescription; failures += 1 }
        }
        if failures > 0 { error = AppLocalization.format("Could not update %lld models. See the affected rows and try again.", failures) }
    }
    func test(_ model: Record) async {
        guard !loading, !bulkRunning, !busyIDs.contains(model.id) else { return }
        busyIDs.insert(model.id); rowErrors[model.id] = nil; results[model.id] = nil
        defer { busyIDs.remove(model.id) }
        do { results[model.id] = try await api.call("/models/" + model.id.pathComponent + "/test", method: "POST") }
        catch { rowErrors[model.id] = error.localizedDescription }
    }
    func remove(_ model: Record) async {
        guard !loading, !working else { return }
        busyIDs.insert(model.id); rowErrors[model.id] = nil
        defer { busyIDs.remove(model.id) }
        do {
            _ = try await api.call("/models/" + model.id.pathComponent, method: "DELETE")
            models.removeAll { $0.id == model.id }; results[model.id] = nil; changed?()
        } catch { rowErrors[model.id] = error.localizedDescription }
    }
}
