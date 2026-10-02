import Foundation
import Security

enum ClientError: LocalizedError {
    case invalidURL, http(Int, String), invalidResponse, message(String)
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Enter a complete http:// or https:// API address without credentials, query, or fragment.".localized
        case .http(let status, let message): return "\(message) (HTTP \(status))"
        case .invalidResponse: return "The server returned an unexpected response. Check the API base address.".localized
        case .message(let s): return s
        }
    }
}

enum Keychain {
    private static let service = "ad.neko.homem"
    /// Drafts are intentionally local. Credentials and the account directory
    /// travel with the user's iCloud Keychain between Homem installations.
    static func isSyncedAccount(_ account: String) -> Bool {
        account.hasPrefix("saved-account|") || account.hasPrefix("official-session|") || account == SharedAccountDirectory.key
    }
    private static func query(_ account: String, synchronizable: Bool) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: synchronizable]
    }
    private static func read(_ account: String, synchronizable: Bool) -> String? {
        var q = query(account, synchronizable: synchronizable)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func read(_ account: String) -> String? {
        if isSyncedAccount(account), let value = read(account, synchronizable: true) { return value }
        guard let legacy = read(account, synchronizable: false) else { return nil }
        // Existing device-only items cannot change accessibility or sync class
        // in place. Copy first; never remove the working login on a failed copy.
        if isSyncedAccount(account) { try? save(legacy, account: account) }
        return legacy
    }
    static func save(_ value: String?, account: String) throws {
        let synced = isSyncedAccount(account)
        let q = query(account, synchronizable: synced)
        guard let value else {
            SecItemDelete(q as CFDictionary)
            if synced { SecItemDelete(query(account, synchronizable: false) as CFDictionary) }
            return
        }
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8),
                                         kSecAttrAccessible as String: synced ? kSecAttrAccessibleAfterFirstUnlock : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        // A failed refresh must not delete an existing saved login.
        var status = SecItemUpdate(q as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let add = q.merging(attributes) { _, new in new }
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw ClientError.message("Could not securely save this sign-in (\(status)).") }
        if synced { SecItemDelete(query(account, synchronizable: false) as CFDictionary) }
    }
    static func migrateDrafts(from oldScope: String, to newScope: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ad.neko.homem", kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let items = result as? [[String: Any]] else { return }
        let prefix = "draft|\(oldScope)|"
        for item in items {
            guard let key = item[kSecAttrAccount as String] as? String, key.hasPrefix(prefix), let value = read(key) else { continue }
            let destination = "draft|\(newScope)|" + key.dropFirst(prefix.count)
            do { try save(value, account: destination); try save(nil, account: key) } catch { /* Keep the original draft if migration fails. */ }
        }
    }
    static func removeDrafts(server: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ad.neko.homem", kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let items = result as? [[String: Any]] else { return }
        for item in items {
            if let account = item[kSecAttrAccount as String] as? String, account.hasPrefix("draft|\(server)|") { try? save(nil, account: account) }
        }
    }
}

final class SafeRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Never forward credentials or mutation bodies to a redirect target.
        completionHandler(nil)
    }
}
