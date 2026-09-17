import Foundation

/// Shared with the extension through Homem's existing Keychain access group.
/// The extension never needs the containing app's preferences or a copy of tokens.
struct SharedAccountDirectory: Codable {
    var accounts: [SavedAccount]
    var activeID: String?
    static let key = "share-account-directory"
    static func restore() -> Self {
        guard let raw = Keychain.read(key), let data = Data(base64Encoded: raw),
              let directory = try? JSONDecoder().decode(Self.self, from: data) else {
            return Self(accounts: [], activeID: nil)
        }
        return directory
    }
    func save() throws {
        try Keychain.save(JSONEncoder().encode(self).base64EncodedString(), account: Self.key)
    }
}
