import Foundation
import Observation

@MainActor @Observable final class MarketplaceCatalog {
    let api: APIClient
    var records: [Record] = []
    var error: String?
    var loading = false
    var hasMore = true
    var nextPage = 1
    var query = ""
    var loadedQuery: String?
    private var generation = UUID()
    init(api: APIClient) { self.api = api }
    func search(_ text: String, debounce: Bool = true) async {
        let request = UUID(); generation = request
        query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        records = []; error = nil; nextPage = 1; hasMore = true; loading = false; loadedQuery = nil
        if debounce {
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
        }
        guard request == generation, !Task.isCancelled else { return }
        await loadMore()
    }
    func loadMore() async {
        guard !loading, hasMore else { return }
        let request = generation, page = nextPage
        loading = true; error = nil
        defer { if request == generation { loading = false } }
        do {
            let value = try await api.call("/supermarket/apps", query: ["q": query, "page": String(page), "limit": "30"])
            guard request == generation, !Task.isCancelled else { return }
            let incoming = value.items.map { item -> Record in
                var item = item
                if !item["app_id"].string.isEmpty { item["id"] = .string(item["registry_id"].string + "/" + item["app_id"].string) }
                return Record(value: item)
            }
            var existing = Set(records.map(\.id))
            let added = incoming.filter { existing.insert($0.id).inserted }
            records.append(contentsOf: added)
            loadedQuery = query
            nextPage = page + 1
            let limit = value["limit"].number > 0 ? Int(value["limit"].number) : 30
            hasMore = !added.isEmpty && (value["total"].isNull ? incoming.count >= limit : page * limit < Int(value["total"].number))
        } catch { if request == generation && !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

enum MarketplaceIconSource {
    static func path(_ icon: JSONValue, dark: Bool, detail: Bool = false) -> String? {
        let variants = (dark ? ["dark"] : []) + (detail ? ["detail", "card"] : ["card", "detail"])
        for variant in variants {
            let digest = icon[variant]["digest"].string
            if digest.count == 64 && digest.allSatisfy({ "0123456789abcdef".contains($0) }) {
                return "supermarket/artifacts/icon/" + digest
            }
        }
        return nil
    }
}
