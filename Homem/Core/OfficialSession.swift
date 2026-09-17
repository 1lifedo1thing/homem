import Foundation

enum OfficialServer {
    static let origin = URL(string: "https://app.memoh.net")!
    static let apiURL = origin.appendingPathComponent("api/memoh")
    static let platformURL = origin.appendingPathComponent("api/v1")
    static let keychainAccount = "official-session|app.memoh.net"

    static func accepts(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return ["app.memoh.net", "memoh.net"].contains(domain)
            && cookie.isSecure && (cookie.expiresDate.map { $0 > Date() } ?? true)
    }
}

/// Only the official origin's cookies are transferred from the sign-in browser.
/// Identity-provider cookies and passwords never enter the native API client.
struct OfficialSession: Codable {
    struct Cookie: Codable {
        var name: String
        var value: String
        var domain: String
        var path: String
        var expires: Date?
        var httpOnly: Bool
        init(_ cookie: HTTPCookie) {
            name = cookie.name; value = cookie.value; domain = cookie.domain
            path = cookie.path; expires = cookie.expiresDate; httpOnly = cookie.isHTTPOnly
        }
        var httpCookie: HTTPCookie? {
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: name, .value: value, .domain: domain, .path: path, .secure: "TRUE"
            ]
            if httpOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
            if let expires { properties[.expires] = expires }
            return HTTPCookie(properties: properties)
        }
    }
    var cookies: [Cookie]
    var teamID: String
    init(cookies: [HTTPCookie], teamID: String = "") {
        self.cookies = cookies.filter(OfficialServer.accepts).map(Cookie.init)
        self.teamID = teamID
    }
    var validCookies: [HTTPCookie] { cookies.compactMap(\.httpCookie).filter(OfficialServer.accepts) }
    static func restore(account: String = OfficialServer.keychainAccount) -> OfficialSession? {
        guard let raw = Keychain.read(account), let data = Data(base64Encoded: raw),
              let value = try? JSONDecoder().decode(Self.self, from: data),
              !value.teamID.isEmpty, !value.validCookies.isEmpty else { return nil }
        return value
    }
    func save(account: String = OfficialServer.keychainAccount) throws {
        try Keychain.save(JSONEncoder().encode(self).base64EncodedString(), account: account)
    }
}

/// Platform identity is separate from the workspace API's authorization profile.
enum OfficialIdentity {
    static func account(_ response: JSONValue) -> JSONValue {
        let user = response["user"], profile = response["user_profile"]
        var result = response
        for key in ["id", "username", "email", "display_name", "avatar_url", "timezone"] {
            result[key] = .string(response[key].string.nonEmpty ?? profile[key].string.nonEmpty ?? user[key].string)
        }
        result["id"] = .string(response.text("id", "user_id").nonEmpty ?? user.text("id", "user_id"))
        return result
    }
    static func teams(_ response: JSONValue) -> [JSONValue] {
        response["teams"].array.map { item in
            var team = item["team"].isNull ? item : item["team"]
            if !item["role"].isNull { team["role"] = item["role"] }
            return team
        }.filter { !$0["team_id"].string.isEmpty }
    }
}

struct SavedAccount: Codable, Identifiable, Equatable {
    var id: String
    var server: String
    var identity: String
    var name: String
    var avatarURL: String
    var official: Bool
    var credentialKey: String { "saved-account|" + id }
    var host: String { URL(string: server)?.host ?? server }
}
