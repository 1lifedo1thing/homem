import SwiftUI
import Observation

@MainActor @Observable final class AppStore {
    var api: APIClient?
    var bots: [Record] = []
    var profile: JSONValue = .null
    var error: String?
    var loading = false
    var selectedBotID: String = ""
    var isDemo: Bool { api?.isDemo == true }
    var canAdmin: Bool { profile["role"].string == "admin" }
    var selectedBot: Record? { bots.first { $0.id == selectedBotID } ?? bots.first }
    init() {
        if ProcessInfo.processInfo.arguments.contains("--ui-onboarding") { return }
        if ProcessInfo.processInfo.arguments.contains("--demo") { enterDemo() }
        else if let base = UserDefaults.standard.string(forKey: "serverURL"), let url = try? APIClient.normalizedURL(base), let token = Keychain.read(base) {
            api = APIClient(baseURL: url, token: token)
        }
    }
    func enterDemo() {
        api = APIClient(baseURL: URL(string: "https://demo.invalid/api")!, isDemo: true)
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
        profile = user; bots = []; api = client
        await reload()
    }
    func reload() async {
        guard let api else { return }
        loading = true; defer { loading = false }
        do {
            async let botResult = api.call("/bots")
            async let userResult = api.call("/users/me")
            let (botValue, user) = try await (botResult, userResult)
            bots = botValue.items.map(Record.init); profile = user
            if !bots.contains(where: { $0.id == selectedBotID }) { selectedBotID = bots.first?.id ?? "" }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    func signOut() {
        api?.signedOut = true
        if let api, !api.isDemo { try? Keychain.save(nil, account: api.baseURL.absoluteString); Keychain.removeDrafts(server: api.baseURL.absoluteString) }
        api?.session.invalidateAndCancel(); api = nil; bots = []; profile = .null; error = nil
    }
}
