import XCTest
@testable import Homem

/// Run scripts/fixture-server.py before these tests. No production credentials needed.
@MainActor final class IntegrationTests: XCTestCase {
    func connectedClient() async throws -> APIClient {
        let url = URL(string: "http://127.0.0.1:18765/api")!
        let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 15
        let api = APIClient(baseURL: url, session: URLSession(configuration: config))
        do { _ = try await api.session.data(from: URL(string: "http://127.0.0.1:18765/health")!) }
        catch {
            if ProcessInfo.processInfo.environment["CI_XCODE_CLOUD"] == "TRUE" { throw error }
            throw XCTSkip("Start scripts/fixture-server.py for wire integration tests: \(error.localizedDescription)")
        }
        let response = try await api.call("/auth/login", method: "POST", body: ["username": "fixture", "password": "fixture-password"])
        api.token = response["access_token"].string
        return api
    }
    func testRealHTTPAndStreamOperation() async throws {
        let api = try await connectedClient()
        let bots = try await api.call("/bots")
        XCTAssertEqual(bots.items.first?["id"], "fixture-bot")
        var events: [JSONValue] = []
        let result = try await api.streamOperation("/test/stream", method: "POST", body: [:]) { events.append($0) }
        XCTAssertEqual(events.map { $0["type"].string }, ["started", "step", "done"])
        XCTAssertEqual(result["id"], "fixture-install")
    }
    func testRealWebSocketAdmissionDeltaAndHistoryReconciliation() async throws {
        let api = try await connectedClient()
        let model = ChatModel(api: api, botID: "fixture-bot", sessionID: "fixture-session")
        await model.start(); defer { model.stop() }
        let readyDeadline = Date().addingTimeInterval(20)
        while model.connection != "Connected", Date() < readyDeadline { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertEqual(model.connection, "Connected")
        let initialCount = model.history.count
        let prompt = "A real URLSession WebSocket request \(UUID().uuidString)"
        model.draft = prompt
        let sent = await model.send(); XCTAssertTrue(sent)
        let deadline = Date().addingTimeInterval(20)
        while (model.history.count <= initialCount || model.active), Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(model.history.contains { $0["messages"].array.first?["content"] == "Verified native WebSocket response." })
        XCTAssertTrue(model.pending.isEmpty)
        XCTAssertFalse(model.active)
        let users = model.visibleTurns.filter { $0["role"] == "user" && $0["text"].string == prompt }
        XCTAssertEqual(users.count, 1)
    }
}
