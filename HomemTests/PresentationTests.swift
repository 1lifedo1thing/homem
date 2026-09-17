import XCTest
@testable import Homem

final class PresentationTests: XCTestCase {
    func testActivityGroupingPreservesOrderAndPendingRequests() {
        let messages: [JSONValue] = [
            ["type": "tool", "name": "read_file"],
            ["type": "tool", "name": "exec", "approval": ["status": "pending"]],
            ["type": "text", "content": "Done"],
            ["type": "tool", "name": "update_schedule"]
        ]
        let groups = MessageGroup.group(messages)
        XCTAssertEqual(groups.map(\.messages.count), [2, 1, 1])
        XCTAssertEqual(groups.flatMap(\.messages), messages)
        XCTAssertEqual(groups[0].messages[1]["approval"]["status"], "pending")
        XCTAssertEqual(ToolPresentation.title("update_schedule"), "Schedule")
        XCTAssertEqual(ToolPresentation.title("some_private_tool_id"), "Tool activity")
    }
    func testTranslationsAreBundledAndPreserveUserContent() throws {
        for (language, expected) in [("zh-Hans", "智能体"), ("es", "Agentes"), ("ja", "エージェント")] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
            XCTAssertNotNil(Bundle(path: path))
            XCTAssertEqual(AppLocalization.text("Agents", language: language), expected)
            XCTAssertEqual(AppLocalization.text("Personal agent", language: language), "Personal agent")
            XCTAssertEqual(Record(value: ["display_name": "Max"]).title, "Max")
            XCTAssertFalse(AppLocalization.text("Message %@…", language: language).isEmpty)
            XCTAssertNotEqual(AppLocalization.text("Desktop unavailable", language: language), "Desktop unavailable")
        }
    }
    func testDesktopReadinessIncludesBrowserAndEnabledState() {
        var info: JSONValue = ["enabled": true, "available": true, "running": true]
        XCTAssertTrue(DesktopReadiness.ready(info))
        info["browser_available"] = false
        XCTAssertFalse(DesktopReadiness.ready(info))
        info["enabled"] = false
        XCTAssertNotNil(DesktopReadiness.blockingReason(info))
    }
    @MainActor func testPrivateAvatarCredentialsStayOnOriginalOrigin() throws {
        let api = APIClient(baseURL: URL(string: "https://private.example/api")!, token: "fixture-token")
        let own = try XCTUnwrap(api.avatarRequest(URL(string: "https://private.example/avatars/team.svg")!))
        XCTAssertEqual(own.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-token")
        for url in ["https://cdn.example/a.png", "http://private.example/a.png", "https://private.example:444/a.png", "data:image/png;base64,eA=="] {
            XCTAssertNil(try api.avatarRequest(URL(string: url)!))
        }
        XCTAssertEqual(JSONValue.object(["metadata": ["icon_url": "/icon.svg"]]).avatarURL, "/icon.svg")
    }
    func testAvatarRedirectsKeepCredentialsOnlyOnSameOrigin() throws {
        let source = URL(string: "https://memoh.example/avatars/a")!
        var request = URLRequest(url: URL(string: "https://memoh.example/avatars/b")!)
        request.setValue("Bearer fixture", forHTTPHeaderField: "Authorization")
        request.setValue("session=fixture", forHTTPHeaderField: "Cookie")
        request.setValue("fixture-team", forHTTPHeaderField: "X-Team-ID")
        XCTAssertEqual(AvatarRedirectDelegate.redirectedRequest(request, from: source)?.value(forHTTPHeaderField: "Authorization"), "Bearer fixture")
        request.url = URL(string: "https://cdn.example/avatar.png?signature=fixture")!
        let external = try XCTUnwrap(AvatarRedirectDelegate.redirectedRequest(request, from: source))
        XCTAssertEqual(external.url, request.url)
        XCTAssertEqual(external.allHTTPHeaderFields, ["Accept": "image/*"])
        request.url = URL(string: "http://memoh.example/avatar.png")!
        XCTAssertNil(AvatarRedirectDelegate.redirectedRequest(request, from: source))
        request.url = URL(string: "https://user:secret@cdn.example/avatar.png")!
        XCTAssertNil(AvatarRedirectDelegate.redirectedRequest(request, from: source))
    }
    func testSVGDataAvatarSupportsPercentEncoding() async throws {
        let data = try await AvatarImages.data(URL(string: "data:image/svg+xml,%3Csvg%20xmlns='http://www.w3.org/2000/svg'%3E%3C/svg%3E")!)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).hasPrefix("<svg"))
    }
}

@MainActor final class DesktopReadinessTests: XCTestCase {
    func testLegacyPrepareAndReadinessPolling() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let api = APIClient(baseURL: URL(string: "https://desktop.invalid/api")!, token: "fixture", session: URLSession(configuration: config))
        var infoCalls = 0
        var prepared = false
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture")
            if request.url!.path.hasSuffix("/prepare") {
                prepared = true
                return (200, Data("data: {\"type\":\"progress\",\"step\":\"starting\"}\n\ndata: {\"type\":\"complete\"}\n\n".utf8))
            }
            infoCalls += 1
            let ready = infoCalls >= 3
            return (200, try JSONValue.object(["enabled": true, "available": .bool(ready), "running": .bool(ready), "prepare_supported": false]).encoded)
        }
        defer { StubURLProtocol.handler = nil }
        var states: [String] = []
        try await DesktopReadiness.prepare(api: api, base: "/bots/test/container/display") { states.append($0) }
        XCTAssertTrue(prepared)
        XCTAssertEqual(infoCalls, 3)
        XCTAssertTrue(states.contains("Starting desktop"))
    }
    func testDisabledDesktopDoesNotPrepareOrConnect() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let api = APIClient(baseURL: URL(string: "https://desktop.invalid/api")!, session: URLSession(configuration: config))
        var count = 0
        StubURLProtocol.handler = { _ in count += 1; return (200, Data(#"{"enabled":false}"#.utf8)) }
        defer { StubURLProtocol.handler = nil }
        let model = DesktopModel(api: api, botID: "test")
        await model.connect()
        XCTAssertEqual(count, 1)
        XCTAssertEqual(model.status, "Disconnected")
        XCTAssertNotNil(model.error)
        XCTAssertNil(model.track)
    }
}
