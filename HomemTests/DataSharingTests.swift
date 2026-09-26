import XCTest
@testable import Homem

@MainActor final class DataSharingTests: XCTestCase {
    private var receiptKeys: [String] = []
    override func tearDown() {
        for key in receiptKeys { try? Keychain.save(nil, account: key) }
        StubURLProtocol.handler = nil
        super.tearDown()
    }
    private func client() -> APIClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let api = APIClient(baseURL: URL(string: "https://consent.invalid/api")!, token: "test", session: URLSession(configuration: config))
        api.credentialAccount = UUID().uuidString
        receiptKeys.append("data-sharing|" + api.draftScope)
        return api
    }
    private func providers(_ endpoint: String = "https://api.openai.com/v1") -> JSONValue {
        ["items": [["id": "one", "name": "OpenAI", "config": ["base_url": .string(endpoint)]]]]
    }
    func testNoMutationBeforePermissionAndWithdrawalBlocksAgain() async throws {
        let api = client(); let response = providers()
        var mutations = 0
        StubURLProtocol.handler = { request in
            if request.httpMethod != "GET" { mutations += 1; return (200, Data("{}".utf8)) }
            return (200, try (request.url!.path == "/api/providers" ? response : JSONValue.array([])).encoded)
        }
        do { _ = try await api.call("/bots/one/messages", method: "POST", body: ["text": "private"]); XCTFail("Must require consent") } catch {}
        XCTAssertEqual(mutations, 0)
        XCTAssertFalse(api.dataSharing.authorized)
        XCTAssertEqual(api.dataSharing.disclosure?.recipients.first?.name, "OpenAI")
        try api.dataSharing.accept()
        _ = try await api.call("/bots/one/messages", method: "POST", body: ["text": "permitted"])
        XCTAssertEqual(mutations, 1)
        try api.dataSharing.revoke()
        do { _ = try await api.call("/bots/one/messages", method: "POST"); XCTFail("Withdrawal must block") } catch {}
        XCTAssertEqual(mutations, 1)
    }
    func testChangedEndpointRequiresFreshConsentAndDoesNotSend() async throws {
        let api = client()
        var endpoint = "https://first.invalid/v1", mutations = 0
        StubURLProtocol.handler = { request in
            if request.httpMethod != "GET" { mutations += 1; return (200, Data("{}".utf8)) }
            let result: JSONValue = request.url!.path == "/api/providers" ? ["items": [["id": "one", "name": "Gateway", "config": ["base_url": .string(endpoint)]]]] : []
            return (200, try result.encoded)
        }
        try await api.refreshDataSharing(); try api.dataSharing.accept()
        endpoint = "https://first.invalid/different-provider/v1"
        do { _ = try await api.call("/models/one/test", method: "POST"); XCTFail("Changed recipient must block") } catch {}
        XCTAssertEqual(mutations, 0)
        XCTAssertFalse(api.dataSharing.authorized)
        XCTAssertEqual(api.dataSharing.disclosure?.recipients.first?.endpoint, "https://first.invalid")
    }
    func testReceiptIsolationAndSanitization() throws {
        let recipients = try DataSharingDisclosure.parse([["id": "one", "name": "Gateway", "config": ["base_url": "https://user:secret@proxy.invalid:8443/token-secret?api_key=private#private"]]], path: "/providers")
        XCTAssertEqual(recipients.first?.endpoint, "https://proxy.invalid:8443")
        let scope = UUID().uuidString
        let first = DataSharingDisclosure(scope: scope + "|team-one", server: "https://server.invalid", recipients: recipients)
        receiptKeys.append(first.receiptKey)
        try first.accept(); XCTAssertTrue(first.accepted)
        XCTAssertFalse(DataSharingDisclosure(scope: scope + "|team-two", server: first.server, recipients: recipients).accepted)
        XCTAssertFalse(DataSharingDisclosure(scope: first.scope, server: "https://other.invalid", recipients: recipients).accepted)
        XCTAssertThrowsError(try DataSharingDisclosure.parse([["id": "hidden"]], path: "/providers"))
    }
    func testDiscoveryFailureClosesGateAndPreservesChatDraft() async throws {
        let api = client()
        StubURLProtocol.handler = { _ in (403, Data("{}".utf8)) }
        let chat = ChatModel(api: api, botID: "one", sessionID: "one")
        chat.draft = "Do not transmit"
        let sent = await chat.send()
        XCTAssertFalse(sent); XCTAssertEqual(chat.draft, "Do not transmit")
        XCTAssertTrue(chat.pending.isEmpty)
        XCTAssertFalse(api.dataSharing.authorized)
        XCTAssertNotNil(api.dataSharing.error)
    }
    func testStreamsAndSocketsCannotBypassConsent() async throws {
        let api = client(); let response = providers()
        var contentRequests = 0
        StubURLProtocol.handler = { request in
            if !request.url!.path.contains("providers") { contentRequests += 1 }
            return (200, try (request.url!.path == "/api/providers" ? response : JSONValue.array([])).encoded)
        }
        do { _ = try await api.streamOperation("/stream", method: "POST", body: ["text": "private"]) { _ in }; XCTFail("Stream must block") } catch {}
        do { _ = try await api.socket("/web/ws"); XCTFail("Socket must block") } catch {}
        XCTAssertEqual(contentRequests, 0)
    }
    func testShareExtensionBlocksUploadUntilMatchingPermission() async throws {
        let account = SavedAccount(id: UUID().uuidString, server: "https://share.invalid/api", identity: "test", name: "Test", avatarURL: "", official: false)
        try Keychain.save("test", account: account.credentialKey)
        defer { try? Keychain.save(nil, account: account.credentialKey) }
        receiptKeys.append("data-sharing|" + account.credentialKey)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let api = try ShareUploadClient(account: account, session: URLSession(configuration: config))
        let response = providers(); var mutations = 0
        StubURLProtocol.handler = { request in
            if request.httpMethod != "GET" { mutations += 1; return (200, Data("{}".utf8)) }
            return (200, try (request.url!.path == "/api/providers" ? response : JSONValue.array([])).encoded)
        }
        do { _ = try await api.call("/bots/one/container/fs/mkdir", method: "POST"); XCTFail("Share must block") } catch {}
        XCTAssertEqual(mutations, 0)
        try api.dataSharing.accept()
        _ = try await api.call("/bots/one/container/fs/mkdir", method: "POST")
        XCTAssertEqual(mutations, 1)
        try api.dataSharing.revoke()
        do { _ = try await api.call("/bots/one/container/fs/mkdir", method: "POST"); XCTFail("Revoked share must block") } catch {}
        XCTAssertEqual(mutations, 1)
    }
    func testAuthenticationDoesNotRequireAIConsent() async throws {
        let api = client(); var requests = 0
        StubURLProtocol.handler = { request in
            requests += 1
            XCTAssertEqual(request.url?.path, "/api/auth/login")
            return (200, Data(#"{"access_token":"fixture"}"#.utf8))
        }
        _ = try await api.call("/auth/login", method: "POST", body: ["username": "fixture", "password": "fixture"])
        XCTAssertEqual(requests, 1); XCTAssertNil(api.dataSharing.disclosure)
    }
}
