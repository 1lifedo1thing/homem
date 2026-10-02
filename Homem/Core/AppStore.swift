import SwiftUI
import Observation

/// The launcher can select another connection without replacing the state used
/// by an already-open window. Credentials remain on the shared API client.
@MainActor @Observable private final class AccountConnection {
    var accountID: String?
    var id = UUID()
    var api: APIClient?
    var bots: [Record] = []
    var profile: JSONValue = .null
    var accountProfile: JSONValue = .null
    var workspace: JSONValue = .null
    var workspaces: [JSONValue] = []
    var selectedBotID = ""
    var modelCatalogRevision = 0
    var error: String?
    var loading = false
    @ObservationIgnored var agentWorkspaces: [String: AgentWorkspaceState] = [:]
    @ObservationIgnored var windowDrafts: [UUID: (scope: String, destination: ChatDestination)] = [:]

    func disconnect() {
        api?.invalidate()
        api = nil; accountID = nil; bots = []; profile = .null; accountProfile = .null
        workspace = .null; workspaces = []; selectedBotID = ""; error = nil; loading = false
        windowDrafts.removeAll(); agentWorkspaces.removeAll(); id = UUID()
    }
}

@MainActor @Observable private final class AccountConnections {
    let vault: AccountVault
    var savedAccounts: [SavedAccount]
    var windows: [String: AccountConnection] = [:]
    init(vault: AccountVault) { self.vault = vault; savedAccounts = vault.accounts }
    func retains(_ connection: AccountConnection) -> Bool { windows.values.contains { $0 === connection } }
}

@MainActor @Observable final class AppStore {
    private let accounts: AccountConnections
    private var connection = AccountConnection()
    private let selectsActiveAccount: Bool
    private var vault: AccountVault { accounts.vault }
    var savedAccounts: [SavedAccount] { accounts.savedAccounts }
    var activeAccountID: String? { connection.accountID }
    var connectionID: UUID { connection.id }
    private var agentWorkspaces: [String: AgentWorkspaceState] {
        get { connection.agentWorkspaces }
        set { connection.agentWorkspaces = newValue }
    }
    private var windowDrafts: [UUID: (scope: String, destination: ChatDestination)] {
        get { connection.windowDrafts }
        set { connection.windowDrafts = newValue }
    }

    func workspaceWindowRoute(botID: String, tool: ChatWorkspaceTool, conversation: ChatDestination? = nil,
                              directory: String = "/data", viewOnly: Bool = true) -> WorkspaceWindowRoute? {
        guard let api, !api.signedOut else { return nil }
        accounts.windows[api.draftScope] = connection
        return WorkspaceWindowRoute(scope: api.draftScope, botID: botID, tool: tool,
                                    conversation: conversation, directory: directory, viewOnly: viewOnly)
    }

    /// Restored windows resolve their own saved account, independent of the
    /// launcher's selection. Only the account ID and workspace route are saved.
    func windowStore(for route: WorkspaceWindowRoute) throws -> AppStore? {
        let state: AccountConnection
        if let cached = accounts.windows[route.scope], cached.api?.signedOut == false {
            state = cached
        } else if route.belongs(to: api), api?.signedOut == false {
            state = connection
        } else {
            guard let account = savedAccounts.first(where: {
                $0.official ? route.scope.hasPrefix($0.credentialKey + "|") : route.scope == $0.credentialKey
            }) else { return nil }
            let client = try vault.client(for: account)
            if account.official {
                let team = String(route.scope.dropFirst(account.credentialKey.count + 1))
                guard !team.isEmpty else { client.invalidate(); return nil }
                client.officialSession?.teamID = team
            }
            guard route.belongs(to: client) else { client.invalidate(); return nil }
            state = AccountConnection(); state.api = client; state.accountID = account.id
            state.accountProfile = ["display_name": .string(account.name), "avatar_url": .string(account.avatarURL)]
        }
        accounts.windows[route.scope] = state
        return AppStore(accounts: accounts, connection: state)
    }

    private init(accounts: AccountConnections, connection: AccountConnection) {
        self.accounts = accounts; self.connection = connection; selectsActiveAccount = false
    }
    /// New-chat payloads stay in memory until the destination window starts.
    /// Scene restoration carries navigation only and cannot replay a message.
    func chatWindowRoute(for destination: ChatDestination) -> WorkspaceWindowRoute? {
        guard let route = workspaceWindowRoute(botID: destination.botID, tool: .chat, conversation: destination) else { return nil }
        if destination.firstMessage != nil { windowDrafts[route.id] = (route.scope, destination) }
        return route
    }
    func takeWindowDraft(for destination: ChatDestination, windowID: String?) -> NewChatDraft? {
        guard let windowID, let id = UUID(uuidString: windowID), let pending = windowDrafts[id],
              pending.scope == api?.draftScope, pending.destination.botID == destination.botID,
              pending.destination.sessionID == destination.sessionID else { return nil }
        windowDrafts.removeValue(forKey: id)
        return pending.destination.firstMessage
    }
    func chatWorkspace(for botID: String, windowID: String? = nil) -> AgentWorkspaceState {
        let accountScope = api?.draftScope ?? "disconnected"
        let scope = windowID.map { accountScope + "|window:" + $0 } ?? accountScope
        let key = scope + "|" + botID
        if let existing = agentWorkspaces[key] { return existing }
        let state = AgentWorkspaceState(scope: scope, botID: botID, defaults: vault.defaults)
        agentWorkspaces[key] = state
        return state
    }
    var modelCatalogRevision: Int { get { connection.modelCatalogRevision } set { connection.modelCatalogRevision = newValue } }
    var workspaces: [JSONValue] { get { connection.workspaces } set { connection.workspaces = newValue } }
    var api: APIClient? { get { connection.api } set { connection.api = newValue } }
    var bots: [Record] { get { connection.bots } set { connection.bots = newValue } }
    var profile: JSONValue { get { connection.profile } set { connection.profile = newValue } }
    var accountProfile: JSONValue { get { connection.accountProfile } set { connection.accountProfile = newValue } }
    var accountName: String { accountProfile.text("display_name", "username").nonEmpty ?? profile.text("display_name", "username").nonEmpty ?? "Your account".localized }
    var accountAvatarURL: String { accountProfile.avatarURL.nonEmpty ?? profile.avatarURL }
    var workspace: JSONValue { get { connection.workspace } set { connection.workspace = newValue } }
    var workspaceName: String { workspace.text("name", "slug").nonEmpty ?? (api?.isOfficial == true ? "Memoh workspace".localized : api?.baseURL.host ?? "Workspace".localized) }
    var error: String? { get { connection.error } set { connection.error = newValue } }
    var loading: Bool { get { connection.loading } set { connection.loading = newValue } }
    var selectedBotID: String { get { connection.selectedBotID } set { connection.selectedBotID = newValue } }
    var canAdmin: Bool { profile["role"].string == "admin" }
    var selectedBot: Record? { bots.first { $0.id == selectedBotID } ?? bots.first }
    init(vault: AccountVault = AccountVault(), restore: Bool = true) {
        accounts = AccountConnections(vault: vault); selectsActiveAccount = true
        connection.accountID = vault.activeID
        guard restore else { return }
        if ProcessInfo.processInfo.arguments.contains("--ui-onboarding") { return }
        if let id = activeAccountID, let account = savedAccounts.first(where: { $0.id == id }) {
            api = try? vault.client(for: account)
        }
        else if !vault.migrated, let base = vault.defaults.string(forKey: "serverURL"), let url = try? APIClient.normalizedURL(base) {
            if url == OfficialServer.apiURL, let session = OfficialSession.restore() {
                api = APIClient(baseURL: url, officialSession: session)
                api?.persistOfficialSession = true
            } else if let token = Keychain.read(base) { api = APIClient(baseURL: url, token: token) }
        }
    }
    func refreshSyncedAccounts() {
        if ProcessInfo.processInfo.arguments.contains("--ui-onboarding") { return }
        accounts.savedAccounts = vault.accounts
        if let id = connection.accountID, api != nil, !savedAccounts.contains(where: { $0.id == id }) {
            let scopes = accounts.windows.filter { $0.value.accountID == id }.map(\.key)
            for scope in scopes { accounts.windows.removeValue(forKey: scope)?.disconnect() }
            connection.disconnect()
        }
        guard api == nil, selectsActiveAccount, let id = vault.activeID,
              let account = savedAccounts.first(where: { $0.id == id }),
              let client = try? vault.client(for: account) else { return }
        connection.accountID = id
        api = client
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
        try Task.checkCancellation()
        let accountID = try saveAccount(client, user: user, account: user)
        replaceClient(client, accountID: accountID)
        profile = user
    }
    func reload() async {
        guard let api else { return }
        let loadingConnection = connection
        loadingConnection.loading = true; defer { loadingConnection.loading = false }
        do {
            async let botResult = api.call("/bots")
            async let userResult = api.call("/users/me")
            let (botValue, user) = try await (botResult, userResult)
            guard self.api === api else { return }
            bots = botValue.items.map(Record.init); profile = user
            if !bots.contains(where: { $0.id == selectedBotID }) { selectedBotID = bots.first?.id ?? "" }
            error = nil
            if api.isOfficial { await loadOfficialIdentity(api) }
            guard self.api === api else { return }
            // Import the existing single login once; refresh display metadata on later loads.
            try saveAccount(api, user: profile, account: api.isOfficial ? accountProfile : profile, preferredID: activeAccountID)
        } catch { if self.api === api && !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func loadOfficialIdentity(_ client: APIClient) async {
        async let account = try? client.platformCall("/users/me")
        async let teams = try? client.platformCall("/teams")
        let (user, result) = await (account, teams)
        guard api === client else { return }
        if let user { accountProfile = OfficialIdentity.account(user) }
        if let result {
            workspaces = OfficialIdentity.teams(result)
            workspace = workspaces.first { $0["team_id"].string == client.officialSession?.teamID } ?? .null
        }
        DebugDiagnostics.record("Identity avatars: account=\(!accountAvatarURL.isEmpty), workspace=\(!workspace.avatarURL.isEmpty)")
    }
    func connectOfficial(client: APIClient, teamID: String, workspace: JSONValue = .null, preferredID: String? = nil, replacing: APIClient? = nil) async throws {
        guard client.isOfficial, !teamID.isEmpty else { throw ClientError.invalidResponse }
        client.officialSession?.teamID = teamID
        async let userResult = client.call("/users/me")
        async let botResult = client.call("/bots")
        async let identityResult = client.platformCall("/users/me")
        let (user, botValue, identity) = try await (userResult, botResult, identityResult)
        let account = OfficialIdentity.account(identity)
        try Task.checkCancellation()
        if let replacing, api !== replacing { throw CancellationError() }
        let accountID = try saveAccount(client, user: user, account: account, preferredID: preferredID)
        client.unauthorized = false; client.persistOfficialSession = true
        replaceClient(client, accountID: accountID)
        self.workspace = workspace; accountProfile = account; profile = user
        bots = botValue.items.map(Record.init); selectedBotID = bots.first?.id ?? ""
        await loadOfficialIdentity(client)
    }
    @discardableResult private func saveAccount(_ client: APIClient, user: JSONValue, account: JSONValue, preferredID: String? = nil) throws -> String {
        guard !client.signedOut else { throw CancellationError() }
        let previous = savedAccounts.first { $0.id == preferredID }
        let identity = account.text("id", "user_id", "email", "username").nonEmpty ?? previous?.identity ?? user.text("id", "user_id", "username")
        let server = client.baseURL.absoluteString
        let match = savedAccounts.first { !$0.identity.isEmpty && $0.identity == identity && $0.server == server && $0.official == client.isOfficial }
        let id = preferredID ?? match?.id ?? UUID().uuidString
        let record = SavedAccount(id: id, server: server, identity: identity, name: account.text("display_name", "username", "email").nonEmpty ?? user.text("display_name", "username").nonEmpty ?? client.baseURL.host ?? "Memoh", avatarURL: account.avatarURL.nonEmpty ?? user.avatarURL, official: client.isOfficial)
        let secret: String
        if let session = client.officialSession {
            let teamID = selectsActiveAccount ? session.teamID : OfficialSession.restore(account: record.credentialKey)?.teamID ?? session.teamID
            let saved = OfficialSession(cookies: client.session.configuration.httpCookieStorage?.cookies ?? [], teamID: teamID)
            guard !saved.validCookies.isEmpty else { throw ClientError.message("Sign in to Memoh again to continue.".localized) }
            secret = try JSONEncoder().encode(saved).base64EncodedString()
        } else { secret = client.token }
        let legacyKey = client === api && client.credentialAccount == nil ? (client.isOfficial ? OfficialServer.keychainAccount : server) : nil
        try vault.save(record, secret: secret)
        client.credentialAccount = record.credentialKey
        accounts.savedAccounts = vault.accounts
        if client === api {
            connection.accountID = id
            if selectsActiveAccount { vault.activate(id) }
        }
        if let legacyKey {
            Keychain.migrateDrafts(from: server, to: client.draftScope)
            try? Keychain.save(nil, account: legacyKey)
        }
        return id
    }
    private func selectConnection(_ next: AccountConnection) {
        guard connection !== next else { return }
        #if !os(macOS)
        DesktopPictureInPicture.stopActive(disconnect: true)
        #endif
        if !accounts.retains(connection) { connection.disconnect() }
        connection = next
        if selectsActiveAccount { vault.activate(next.accountID) }
    }
    private func replaceClient(_ client: APIClient?, accountID: String? = nil) {
        // Reauthentication updates the original account's windows together.
        let next = client.flatMap { accounts.windows[$0.draftScope] } ?? AccountConnection()
        if next.api !== client { next.disconnect() }
        next.api = client; next.accountID = accountID
        selectConnection(next)
        if selectsActiveAccount { vault.activate(accountID) }
    }
    func avatarClient(for account: SavedAccount) throws -> APIClient { try vault.client(for: account) }
    func switchAccount(_ account: SavedAccount) async throws {
        guard account.id != activeAccountID || api == nil else { return }
        let client = try vault.client(for: account)
        if let existing = accounts.windows[client.draftScope], existing.api?.signedOut == false, existing.api?.unauthorized == false {
            client.invalidate()
            selectConnection(existing)
        } else { replaceClient(client, accountID: account.id) }
        accountProfile = ["display_name": .string(account.name), "avatar_url": .string(account.avatarURL)]
        await reload()
    }
    func switchWorkspace(_ team: JSONValue) async throws {
        guard let current = api, let session = current.officialSession, team["team_id"].string != session.teamID else { return }
        let scope = (current.credentialAccount ?? current.baseURL.absoluteString) + "|" + team["team_id"].string
        if let existing = accounts.windows[scope], let client = existing.api, !client.signedOut, !client.unauthorized {
            try OfficialSession(cookies: client.session.configuration.httpCookieStorage?.cookies ?? [], teamID: team["team_id"].string)
                .save(account: client.credentialAccount ?? OfficialServer.keychainAccount)
            selectConnection(existing)
            await reload()
            return
        }
        let credentials = OfficialSession(cookies: current.session.configuration.httpCookieStorage?.cookies ?? [], teamID: team["team_id"].string)
        let client = APIClient(baseURL: OfficialServer.apiURL, officialSession: credentials)
        try await connectOfficial(client: client, teamID: team["team_id"].string, workspace: team, preferredID: activeAccountID, replacing: current)
    }
    func removeAccount(_ account: SavedAccount) {
        let active = account.id == activeAccountID
        let scopes = accounts.windows.filter { $0.value.accountID == account.id || $0.value.api?.credentialAccount == account.credentialKey }.map(\.key)
        for scope in scopes { accounts.windows.removeValue(forKey: scope)?.disconnect() }
        if active { connection.disconnect(); replaceClient(nil) }
        vault.remove(account); accounts.savedAccounts = vault.accounts
    }
    func signOut() {
        if let account = savedAccounts.first(where: { $0.id == activeAccountID }) { removeAccount(account) }
        else {
            let current = connection
            accounts.windows = accounts.windows.filter { $0.value !== current }
            current.disconnect(); replaceClient(nil)
        }
    }
}
