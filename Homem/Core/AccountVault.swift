import Foundation

/// Only display metadata is stored in preferences. Tokens and cookie sessions stay in Keychain.
struct AccountVault {
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var accounts: [SavedAccount] {
        if defaults === UserDefaults.standard, Keychain.read(SharedAccountDirectory.key) != nil {
            return SharedAccountDirectory.restore().accounts
        }
        guard let data = defaults.data(forKey: "savedAccounts") else { return [] }
        return (try? JSONDecoder().decode([SavedAccount].self, from: data)) ?? []
    }
    var activeID: String? {
        let local = defaults.string(forKey: "activeAccountID")
        if let local, accounts.contains(where: { $0.id == local }) { return local }
        // A fresh installation can open an account arriving from iCloud Keychain.
        guard defaults === UserDefaults.standard, defaults.data(forKey: "savedAccounts") == nil else { return nil }
        let directory = SharedAccountDirectory.restore()
        return directory.activeID ?? directory.accounts.first?.id
    }
    var migrated: Bool { defaults.bool(forKey: "accountsMigrated") || !accounts.isEmpty }
    func save(_ account: SavedAccount, secret: String) throws {
        try Keychain.save(secret, account: account.credentialKey)
        var list = accounts
        if let index = list.firstIndex(where: { $0.id == account.id }) { list[index] = account }
        else { list.append(account) }
        defaults.set(try JSONEncoder().encode(list), forKey: "savedAccounts")
        defaults.set(true, forKey: "accountsMigrated")
        if defaults === UserDefaults.standard { try SharedAccountDirectory(accounts: list, activeID: activeID).save() }
    }
    func activate(_ id: String?) {
        defaults.set(id, forKey: "activeAccountID")
        publishShareAccounts()
    }
    private func publishShareAccounts() {
        guard defaults === UserDefaults.standard else { return }
        try? SharedAccountDirectory(accounts: accounts, activeID: activeID).save()
    }
    func remove(_ account: SavedAccount) {
        try? Keychain.save(nil, account: account.credentialKey)
        Keychain.removeDrafts(server: account.credentialKey)
        let remaining = accounts.filter { $0.id != account.id }
        defaults.set(try? JSONEncoder().encode(remaining), forKey: "savedAccounts")
        if defaults === UserDefaults.standard {
            try? SharedAccountDirectory(accounts: remaining, activeID: activeID == account.id ? nil : activeID).save()
        }
        if activeID == account.id { activate(nil) }
        else { publishShareAccounts() }
    }
    @MainActor func client(for account: SavedAccount) throws -> APIClient {
        let base = try APIClient.normalizedURL(account.server)
        let client: APIClient
        if account.official {
            guard let session = OfficialSession.restore(account: account.credentialKey) else { throw ClientError.message("Sign in to Memoh again to continue.".localized) }
            client = APIClient(baseURL: base, officialSession: session)
            client.persistOfficialSession = true
        } else {
            guard let token = Keychain.read(account.credentialKey), !token.isEmpty else { throw ClientError.message("Sign in to Memoh again to continue.".localized) }
            client = APIClient(baseURL: base, token: token)
        }
        client.credentialAccount = account.credentialKey
        return client
    }
}
