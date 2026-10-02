import XCTest
import Security
@testable import Homem

final class KeychainTests: XCTestCase {
    func testSignInCanBeSavedUpdatedReadAndDeleted() throws {
        let account = "keychain-regression-" + UUID().uuidString
        defer { try? Keychain.save(nil, account: account) }
        try Keychain.save("fixture-first", account: account)
        XCTAssertEqual(Keychain.read(account), "fixture-first")
        try Keychain.save("fixture-refreshed", account: account)
        XCTAssertEqual(Keychain.read(account), "fixture-refreshed")
        try Keychain.save(nil, account: account)
        XCTAssertNil(Keychain.read(account))
    }
    func testSavedAccountUsesSynchronizableKeychainAndMigratesLocalItem() throws {
        let account = "saved-account|keychain-regression-" + UUID().uuidString
        defer { try? Keychain.save(nil, account: account) }
        let legacy: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                     kSecAttrService as String: "ad.neko.homem",
                                     kSecAttrAccount as String: account,
                                     kSecAttrSynchronizable as String: false,
                                     kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                     kSecValueData as String: Data("old-token".utf8)]
        XCTAssertEqual(SecItemAdd(legacy as CFDictionary, nil), errSecSuccess)
        XCTAssertEqual(Keychain.read(account), "old-token")
        var synced = legacy
        synced.removeValue(forKey: kSecAttrAccessible as String)
        synced.removeValue(forKey: kSecValueData as String)
        synced[kSecAttrSynchronizable as String] = true
        synced[kSecReturnData as String] = true
        var result: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(synced as CFDictionary, &result), errSecSuccess)
        XCTAssertEqual(String(data: try XCTUnwrap(result as? Data), encoding: .utf8), "old-token")
        try Keychain.save("new-token", account: account)
        XCTAssertEqual(Keychain.read(account), "new-token")
        try Keychain.save(nil, account: account)
        XCTAssertNil(Keychain.read(account))
    }
}
