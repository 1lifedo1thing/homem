import Foundation

/// Compiles the app's unchanged networking/runtime sources for a fast macOS wire check.
/// Start fixture-server.py first. This does not replace iOS or real-server testing.
@main struct WireSmoke {
    @MainActor static func main() async throws {
        let api = APIClient(baseURL: URL(string: "http://127.0.0.1:18765/api")!)
        let login = try await api.call("/auth/login", method: "POST", body: ["username": "fixture", "password": "fixture-password"])
        api.token = login["access_token"].string
        let bots = try await api.call("/bots")
        precondition(bots.items.first?["id"] == "fixture-bot")
        var events: [JSONValue] = []
        let result = try await api.streamOperation("/test/stream", method: "POST", body: [:]) { events.append($0) }
        precondition(events.map { $0["type"].string } == ["started", "step", "done"])
        precondition(result["id"] == "fixture-install")
        print("PASS: HTTP authentication, bot listing, SSE progress/completion")
        let model = ChatModel(api: api, botID: "fixture-bot", sessionID: "fixture-session")
        await model.start(); defer { model.stop() }
        let readyDeadline = Date().addingTimeInterval(20)
        while model.connection != "Connected", Date() < readyDeadline { try await Task.sleep(for: .milliseconds(100)) }
        precondition(model.connection == "Connected", "WebSocket did not connect")
        let initialCount = model.history.count
        let prompt = "Wire smoke \(UUID().uuidString)"
        model.draft = prompt
        let sent = await model.send(); precondition(sent)
        let deadline = Date().addingTimeInterval(20)
        while (model.history.count <= initialCount || model.active), Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        precondition(model.history.contains { $0["messages"].array.first?["content"] == "Verified native WebSocket response." })
        precondition(model.pending.isEmpty && !model.active)
        precondition(model.visibleTurns.filter { $0["role"] == "user" && $0["text"].string == prompt }.count == 1)
        print("PASS: WebSocket admission, snapshots, deltas, history reconciliation, deduplication")
    }
}
