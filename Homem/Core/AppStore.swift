import SwiftUI
import Observation

@MainActor @Observable final class AppStore {
    var api: APIClient?
    var bots: [Record] = []
    var profile: JSONValue = .null
    var workspace: JSONValue = .null
    var workspaceName: String { workspace.text("name", "slug").nonEmpty ?? (isDemo ? "Demo workspace".localized : api?.isOfficial == true ? "Memoh workspace".localized : api?.baseURL.host ?? "Workspace".localized) }
    var error: String?
    var loading = false
    var selectedBotID: String = ""
    var isDemo: Bool { api?.isDemo == true }
    var canAdmin: Bool { profile["role"].string == "admin" }
    var selectedBot: Record? { bots.first { $0.id == selectedBotID } ?? bots.first }
    init() {
        if ProcessInfo.processInfo.arguments.contains("--ui-onboarding") { return }
        if ProcessInfo.processInfo.arguments.contains("--demo") { enterDemo() }
        else if let base = UserDefaults.standard.string(forKey: "serverURL"), let url = try? APIClient.normalizedURL(base) {
            if url == OfficialServer.apiURL, let session = OfficialSession.restore() {
                api = APIClient(baseURL: url, officialSession: session)
                api?.persistOfficialSession = true
            } else if let token = Keychain.read(base) { api = APIClient(baseURL: url, token: token) }
        }
    }
    func enterDemo() {
        workspace = .null
        api = APIClient(baseURL: URL(string: "https://demo.invalid/api")!, isDemo: true)
        if ProcessInfo.processInfo.arguments.contains("--ui-tool-activity") {
            api!.demo.collections["messages/welcome"] = [["turn_id": "tools", "role": "assistant", "messages": [
                ["id": 1, "type": "tool", "name": "read_file", "input": ["path": "/data/notes.txt"], "output": "Read notes."],
                ["id": 2, "type": "tool", "name": "web_search", "input": ["query": "weather"], "output": "Found results."],
                ["id": 3, "type": "tool", "name": "update_schedule", "input": ["name": "Morning"], "output": "Schedule updated."],
                ["id": 4, "type": "text", "content": "Your schedule is up to date."]
            ]]]
        }
        bots = api!.demo.collections["/bots", default: []].map(Record.init)
        profile = api!.demo.documents["/users/me"] ?? .null
        selectedBotID = bots.first?.id ?? ""
    }
    func connect(address: String, username: String, password: String, accessToken: String) async throws {
        let url = try APIClient.normalizedURL(address)
        let client = APIClient(baseURL: url, token: accessToken.trimmingCharacters(in: .whitespacesAndNewlines))
        if client.token.isEmpty {
            let login = try await client.call("/auth/login", method: "POST", body: ["username": .string(username), "password": .string(password)])
            client.token = login["access_token"].string
            guard !client.token.isEmpty else { throw ClientError.invalidResponse }
        }
        let user = try await client.call("/users/me")
        try Keychain.save(client.token, account: url.absoluteString)
        UserDefaults.standard.set(url.absoluteString, forKey: "serverURL")
        profile = user; bots = []; workspace = .null; api = client
        await reload()
    }
    func reload() async {
        guard let api else { return }
        loading = true; defer { loading = false }
        do {
            async let botResult = api.call("/bots")
            async let userResult = api.call("/users/me")
            let (botValue, user) = try await (botResult, userResult)
            guard self.api === api else { return }
            bots = botValue.items.map(Record.init); profile = user
            if !bots.contains(where: { $0.id == selectedBotID }) { selectedBotID = bots.first?.id ?? "" }
            error = nil
            if api.isOfficial, let result = try? await api.platformCall("/teams"), self.api === api {
                workspace = result["teams"].array.map { $0["team"].isNull ? $0 : $0["team"] }
                    .first { $0["team_id"].string == api.officialSession?.teamID } ?? .null
            }
        } catch { self.error = error.localizedDescription }
    }
    func connectOfficial(client: APIClient, teamID: String, workspace: JSONValue = .null) async throws {
        guard client.isOfficial, !teamID.isEmpty else { throw ClientError.invalidResponse }
        client.officialSession?.teamID = teamID
        // Verify the workspace API before replacing any existing connection.
        let user = try await client.call("/users/me")
        let botValue = try await client.call("/bots")
        let saved = OfficialSession(cookies: client.session.configuration.httpCookieStorage?.cookies ?? [], teamID: teamID)
        guard !saved.validCookies.isEmpty else { throw ClientError.message("Sign in to Memoh again to continue.".localized) }
        try Task.checkCancellation()
        try saved.save()
        client.unauthorized = false
        client.persistOfficialSession = true
        UserDefaults.standard.set(OfficialServer.apiURL.absoluteString, forKey: "serverURL")
        self.workspace = workspace
        profile = user; bots = botValue.items.map(Record.init); selectedBotID = bots.first?.id ?? ""; api = client
    }
    func signOut() {
        api?.signedOut = true
        if let api, !api.isDemo { try? Keychain.save(nil, account: api.baseURL.absoluteString); Keychain.removeDrafts(server: api.baseURL.absoluteString) }
        if api?.isOfficial == true {
            try? Keychain.save(nil, account: OfficialServer.keychainAccount)
            for cookie in api?.session.configuration.httpCookieStorage?.cookies ?? [] { api?.session.configuration.httpCookieStorage?.deleteCookie(cookie) }
        }
        api?.session.invalidateAndCancel(); api = nil; bots = []; profile = .null; workspace = .null; error = nil
    }
}
