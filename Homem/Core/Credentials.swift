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
    static func read(_ account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ad.neko.homem", kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ value: String?, account: String) throws {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ad.neko.homem", kSecAttrAccount as String: account]
        guard let value else { SecItemDelete(q as CFDictionary); return }
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        // A failed refresh must not delete an existing saved login.
        var status = SecItemUpdate(q as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let add = q.merging(attributes) { _, new in new }
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw ClientError.message("Could not securely save this sign-in (\(status)).") }
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
