import XCTest
@testable import Homem

@MainActor final class ModelCatalogTests: XCTestCase {
    override func tearDown() { StubURLProtocol.handler = nil; super.tearDown() }
    func client() -> APIClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        return APIClient(baseURL: URL(string: "https://models.invalid/api")!, session: URLSession(configuration: config))
    }
    func testGroupsKeepProvidersDistinctAndManagedCatalogRestrictions() {
        let catalog = ModelCatalog(api: client())
        catalog.providers = [Record(value: ["id": "a", "name": "Same", "client_type": "openai-codex"]), Record(value: ["id": "b", "name": "Same", "client_type": "openai-responses"])]
        catalog.models = [
            Record(value: ["id": "one", "provider_id": "a", "name": "One"]),
            Record(value: ["id": "hidden", "provider_id": "a", "config": ["catalog_available": false]]),
            Record(value: ["id": "two", "provider_id": "b", "name": "Two", "enable": false])
        ]
        XCTAssertEqual(catalog.groups.map(\.id), ["a", "b"])
        XCTAssertEqual(catalog.groups.map { $0.models.count }, [1, 1])
        XCTAssertEqual(catalog.groups.map(\.managed), [true, false])
        XCTAssertEqual(catalog.groups.map(\.enabledCount), [1, 0])
    }
    func testToggleUsesUUIDAndPreservesLatestConfiguration() async throws {
        let catalog = ModelCatalog(api: client())
        let original = Record(value: ["id": "internal-uuid", "model_id": "gpt/example", "name": "Original", "enable": true])
        catalog.models = [original]
        var methods: [String] = []
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/models/internal-uuid")
            methods.append(request.httpMethod!)
            if request.httpMethod == "GET" {
                return (200, try JSONValue.object(["id": "internal-uuid", "model_id": "gpt/example", "name": "Renamed elsewhere", "provider_id": "provider", "type": "chat", "enable": true, "config": ["future_option": ["keep": true]]]).encoded)
            }
            let body = try modelTestBody(request)
            XCTAssertEqual(body["enable"], false)
            XCTAssertEqual(body["name"], "Renamed elsewhere")
            XCTAssertEqual(body["config"]["future_option"]["keep"], true)
            XCTAssertTrue(body["id"].isNull)
            return (200, Data("{}".utf8))
        }
        await catalog.setEnabled(original, enabled: false)
        XCTAssertEqual(methods, ["GET", "PUT"])
        XCTAssertEqual(catalog.models.first?.title, "Renamed elsewhere")
        XCTAssertFalse(ModelCatalog.enabled(catalog.models[0]))
        XCTAssertTrue(catalog.rowErrors.isEmpty)
    }
    func testBulkPartialFailureTestResultAndIndividualDeletion() async throws {
        let catalog = ModelCatalog(api: client())
        catalog.models = ["good", "bad", "off"].map { Record(value: ["id": .string($0), "model_id": .string($0), "enable": .bool($0 != "off")]) }
        var touched: [String] = []
        var changes = 0; catalog.changed = { changes += 1 }
        StubURLProtocol.handler = { request in
            let id = request.url!.lastPathComponent
            touched.append(id)
            if id == "test" { return (200, Data(#"{"status":"auth_error","reachable":true,"message":"Invalid API key"}"#.utf8)) }
            if request.httpMethod == "GET" { return (200, try JSONValue.object(["id": .string(id), "model_id": .string(id), "enable": true]).encoded) }
            if id == "bad" { return (403, Data(#"{"message":"Not allowed"}"#.utf8)) }
            return (200, Data("{}".utf8))
        }
        await catalog.setAll(catalog.models, enabled: false)
        XCTAssertEqual(catalog.models.map { ModelCatalog.enabled($0) }, [false, true, false])
        XCTAssertFalse(touched.contains("off"))
        XCTAssertNotNil(catalog.rowErrors["bad"])
        XCTAssertNotNil(catalog.error)
        XCTAssertEqual(changes, 1)
        await catalog.test(catalog.models[1])
        XCTAssertEqual(catalog.results["bad"]?["status"], "auth_error")
        await catalog.remove(catalog.models[0])
        XCTAssertEqual(catalog.models.map(\.id), ["bad", "off"])
        XCTAssertFalse(catalog.working)
    }
}

private func modelTestBody(_ request: URLRequest) throws -> JSONValue {
    if let data = request.httpBody { return try JSONDecoder().decode(JSONValue.self, from: data) }
    guard let stream = request.httpBodyStream else { throw ClientError.invalidResponse }
    stream.open(); defer { stream.close() }
    var data = Data(); var bytes = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable {
        let count = stream.read(&bytes, maxLength: bytes.count)
        guard count >= 0 else { throw ClientError.invalidResponse }
        if count == 0 { break }
        data.append(contentsOf: bytes.prefix(count))
    }
    return try JSONDecoder().decode(JSONValue.self, from: data)
}
