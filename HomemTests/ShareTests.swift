import XCTest
@testable import Homem

final class ShareTests: XCTestCase {
    func testFileCopiesPreserveDuplicatesAndMultipartPayload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = directory.appendingPathComponent("source")
        let staged = directory.appendingPathComponent("staged")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = source.appendingPathComponent("note.txt")
        try Data("日本語\nshared fixture".utf8).write(to: input)
        let first = try SharedFiles.copy(input, into: staged)
        let second = try SharedFiles.copy(input, into: staged)
        XCTAssertEqual(first.name, "note.txt")
        XCTAssertEqual(second.name, "note (2).txt")
        XCTAssertEqual(try Data(contentsOf: first.url), try Data(contentsOf: input))
        XCTAssertEqual(SharedFiles.safeName("../../notes\r\n\".txt"), "notes___.txt")
        let payload = try SharedFiles.multipart(file: first, destination: "/data/Shared-fixture/note.txt", boundary: "fixture-boundary", directory: staged)
        let body = try String(contentsOf: payload, encoding: .utf8)
        XCTAssertTrue(body.contains("name=\"path\"\r\n\r\n/data/Shared-fixture/note.txt\r\n"))
        XCTAssertTrue(body.contains("filename=\"note.txt\""))
        XCTAssertTrue(body.contains("日本語\nshared fixture"))
        XCTAssertTrue(body.hasSuffix("\r\n--fixture-boundary--\r\n"))
    }
    func testOversizedFilesAndDirectoriesAreRejectedBeforeCopying() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertThrowsError(try SharedFiles.copy(folder, into: folder))
        let large = folder.appendingPathComponent("large.bin")
        FileManager.default.createFile(atPath: large.path, contents: nil)
        let handle = try FileHandle(forWritingTo: large)
        try handle.truncate(atOffset: UInt64(SharedFiles.maxBytes + 1)); try handle.close()
        XCTAssertThrowsError(try SharedFiles.copy(large, into: folder))
    }
    @MainActor func testShareClientRefreshesCustomCredentialsAndRejectsRemovedAccount() async throws {
        let account = SavedAccount(id: UUID().uuidString, server: "https://share.invalid/api", identity: "fixture", name: "Fixture", avatarURL: "", official: false)
        try Keychain.save("old-token", account: account.credentialKey)
        defer { try? Keychain.save(nil, account: account.credentialKey); StubURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let client = try ShareUploadClient(account: account, session: URLSession(configuration: config))
        var requests = 0
        StubURLProtocol.handler = { request in
            requests += 1
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            if request.url!.path == "/api/auth/refresh" { return (200, Data(#"{"access_token":"new-token"}"#.utf8)) }
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer old-token" { return (401, Data("{}".utf8)) }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer new-token")
            return (200, Data(#"{"items":[{"id":"fixture-bot"}]}"#.utf8))
        }
        let value = try await client.call("/bots")
        XCTAssertEqual(value.items.first?["id"], "fixture-bot")
        XCTAssertEqual(requests, 3)
        XCTAssertEqual(Keychain.read(account.credentialKey), "new-token")
        try Keychain.save(nil, account: account.credentialKey)
        do { _ = try await client.call("/bots"); XCTFail("Removed accounts must stop requests") } catch {}
        XCTAssertEqual(requests, 3)
    }
}
