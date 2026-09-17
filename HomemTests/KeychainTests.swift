import XCTest
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
}
