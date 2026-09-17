import XCTest
@testable import Homem

@MainActor final class OfficialLoginTests: XCTestCase {
    override func tearDown() { StubURLProtocol.responseHeaders = [:]; StubURLProtocol.handler = nil; super.tearDown() }
    func cookie(domain: String = "app.memoh.net", path: String = "/", secure: Bool = true, expires: Date = Date().addingTimeInterval(3600)) -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [.name: "session", .value: "fixture-session", .domain: domain, .path: path, .expires: expires]
        if secure { properties[.secure] = "TRUE" }
        return HTTPCookie(properties: properties)!
    }
    func client(cookies: [HTTPCookie] = [], teamID: String = "") -> APIClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        return APIClient(baseURL: OfficialServer.apiURL, session: URLSession(configuration: config), officialSession: OfficialSession(cookies: cookies, teamID: teamID))
    }
    func testCookiesAreScopedAndRoundTripWithoutIdentityProviderCredentials() throws {
        let session = OfficialSession(cookies: [cookie(), cookie(domain: "github.com"), cookie(domain: "memoh.net.evil.example"), cookie(secure: false), cookie(expires: .distantPast)], teamID: "team-1")
        let restored = try JSONDecoder().decode(OfficialSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(restored.validCookies.count, 1)
        XCTAssertFalse(restored.validCookies[0].isHTTPOnly)
        let api = client(cookies: restored.validCookies, teamID: restored.teamID)
        let request = try api.request("/bots")
        XCTAssertEqual(request.url?.absoluteString, "https://app.memoh.net/api/memoh/bots")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Team-ID"), "team-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "session=fixture-session")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        api.baseURL = URL(string: "https://third-party.example/api")!
        XCTAssertThrowsError(try api.request("/bots"))
        let custom = APIClient(baseURL: api.baseURL, token: "custom-token")
        XCTAssertNil(try custom.request("/bots").value(forHTTPHeaderField: "Cookie"))
    }
    func testEmailCodeSetsCookieAndLoadsNestedWorkspaceMemberships() async throws {
        let api = client(); let login = OfficialLogin(client: api)
        login.email = " person@example.com "
        var paths: [String] = []
        StubURLProtocol.handler = { request in
            paths.append(request.url!.path)
            StubURLProtocol.responseHeaders = [:]
            switch request.url!.path {
            case "/api/v1/auth/email-code/send":
                let body = try officialTestBody(request)
                XCTAssertEqual(body["email"], "person@example.com")
                return (200, Data(#"{"resend_after":90}"#.utf8))
            case "/api/v1/auth/email-code/verify":
                StubURLProtocol.responseHeaders = ["Set-Cookie": "session=verified; Path=/; Secure; HttpOnly"]
                return (200, Data("{}".utf8))
            case "/api/v1/users/me":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "session=verified")
                return (200, Data(#"{"user":{"id":"person"}}"#.utf8))
            case "/api/v1/teams":
                return (200, Data(#"{"teams":[{"team":{"team_id":"team-1","name":"My workspace","avatar_url":"https://cdn.example/workspace.png"},"role":"TEAM_ROLE_OWNER"}]}"#.utf8))
            default: XCTFail("Unexpected endpoint"); return (404, Data())
            }
        }
        try await login.sendCode()
        XCTAssertEqual(login.step, .code)
        XCTAssertGreaterThan(login.resendAfter.timeIntervalSinceNow, 80)
        do { try await login.sendCode(); XCTFail("Must respect resend cooldown") } catch {}
        login.code = "123456"; try await login.verifyCode()
        XCTAssertEqual(login.step, .workspaces)
        XCTAssertEqual(login.teams.first?["team_id"], "team-1")
        XCTAssertEqual(login.teams.first?["avatar_url"], "https://cdn.example/workspace.png")
        XCTAssertEqual(paths.count, 4)
        XCTAssertFalse(api.persistOfficialSession)
        XCTAssertTrue(api.session.configuration.httpCookieStorage?.cookies?.first?.isHTTPOnly == true)
    }
    func testMFAAndInvalidCodeNeverCompleteSignInPrematurely() async throws {
        let login = OfficialLogin(client: client()); login.email = "person@example.com"; login.step = .code; login.code = "111111"
        StubURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("email-code/verify") { return (200, Data(#"{"mfa_required":true,"mfa_token":"challenge"}"#.utf8)) }
            XCTAssertEqual(request.url!.path, "/api/v1/auth/verify-mfa")
            let body = try officialTestBody(request)
            XCTAssertEqual(body["mfa_token"], "challenge")
            XCTAssertEqual(body["totp_code"], "222222")
            return (401, Data(#"{"message":"Invalid code"}"#.utf8))
        }
        try await login.verifyCode(); XCTAssertEqual(login.step, .mfa)
        login.code = "222222"
        do { try await login.verifyCode(); XCTFail("Invalid MFA must fail") } catch {}
        XCTAssertEqual(login.step, .mfa); XCTAssertTrue(login.teams.isEmpty)
    }
    func testOfficialSocketUsesTicketAndTeamWithoutBearerRefresh() async throws {
        let api = client(cookies: [cookie()], teamID: "team-1")
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/ws-tickets")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Team-ID"), "team-1")
            return (200, Data(#"{"ticket":"one-time-ticket"}"#.utf8))
        }
        let request = try await api.socketRequest("/bots/bot/web/ws")
        let url = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(url.scheme, "wss")
        XCTAssertEqual(url.queryItems?.first(where: { $0.name == "ticket" })?.value, "one-time-ticket")
        XCTAssertEqual(url.queryItems?.first(where: { $0.name == "team_id" })?.value, "team-1")
        var requests = 0
        StubURLProtocol.handler = { _ in requests += 1; return (401, Data(#"{"message":"Session expired"}"#.utf8)) }
        do { _ = try await api.call("/bots"); XCTFail("Expected expired session") } catch {}
        XCTAssertEqual(requests, 1); XCTAssertTrue(api.unauthorized)
    }
}

private func officialTestBody(_ request: URLRequest) throws -> JSONValue {
    if let data = request.httpBody { return try JSONDecoder().decode(JSONValue.self, from: data) }
    guard let stream = request.httpBodyStream else { throw ClientError.invalidResponse }
    stream.open(); defer { stream.close() }
    var data = Data(); var bytes = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable {
        let count = stream.read(&bytes, maxLength: bytes.count)
        guard count >= 0 else { throw ClientError.invalidResponse }
        if count == 0 { break }
        data.append(contentsOf: bytes.prefix(count))
    }
    return try JSONDecoder().decode(JSONValue.self, from: data)
}
