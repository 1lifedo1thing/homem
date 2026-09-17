import Foundation
import Observation

@MainActor @Observable final class OfficialLogin {
    enum Step { case email, code, mfa, workspaces }
    var step: Step = .email
    var email = ""
    var code = ""
    var busy = false
    var error: String?
    var teams: [JSONValue] = []
    var resendAfter = Date.distantPast
    private var mfaToken = ""
    var client: APIClient
    init(client: APIClient? = nil) {
        self.client = client ?? APIClient(baseURL: OfficialServer.apiURL, officialSession: OfficialSession(cookies: []))
    }
    var validEmail: Bool {
        email.trimmingCharacters(in: .whitespacesAndNewlines).range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }
    var validCode: Bool { code.count == 6 && code.allSatisfy { $0.isASCII && $0.isNumber } }

    func sendCode() async throws {
        guard validEmail else { throw ClientError.message("Enter a valid email address.".localized) }
        guard Date() >= resendAfter else { throw ClientError.message("Wait before requesting another code.".localized) }
        email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = Locale.preferredLanguages.first?.lowercased() ?? "en"
        let locale = language.hasPrefix("zh") ? "zh-CN" : language.hasPrefix("ja") ? "ja-JP" : "en-US"
        let response = try await client.platformCall("/auth/email-code/send", method: "POST", body: [
            "email": .string(email), "preferred_locale": .string(locale)
        ])
        resendAfter = Date().addingTimeInterval(response["resend_after"].number > 0 ? response["resend_after"].number : 60)
        code = ""; error = nil; step = .code
    }
    func verifyCode() async throws {
        guard validCode else { throw ClientError.message("Enter the six-digit code.".localized) }
        let response: JSONValue
        if step == .mfa {
            response = try await client.platformCall("/auth/verify-mfa", method: "POST", body: ["mfa_token": .string(mfaToken), "totp_code": .string(code)])
        } else {
            response = try await client.platformCall("/auth/email-code/verify", method: "POST", body: ["email": .string(email), "code": .string(code)])
        }
        code = ""
        if response["mfa_required"].bool {
            guard !response["mfa_token"].string.isEmpty else { throw ClientError.invalidResponse }
            mfaToken = response["mfa_token"].string; step = .mfa
        } else { mfaToken = ""; try await loadWorkspaces() }
    }
    func loadWorkspaces() async throws {
        _ = try await client.platformCall("/users/me")
        let response = try await client.platformCall("/teams")
        teams = OfficialIdentity.teams(response)
        client.unauthorized = false
        step = .workspaces; error = nil
    }
    func useBrowserCookies(_ cookies: [HTTPCookie]) async throws {
        let session = OfficialSession(cookies: cookies)
        guard !session.validCookies.isEmpty else { throw ClientError.message("Finish signing in at app.memoh.net, then tap Continue in Homem.".localized) }
        client.session.invalidateAndCancel()
        client = APIClient(baseURL: OfficialServer.apiURL, officialSession: session)
        try await loadWorkspaces()
    }
    func changeEmail() {
        client.session.invalidateAndCancel()
        client = APIClient(baseURL: OfficialServer.apiURL, officialSession: OfficialSession(cookies: []))
        step = .email; code = ""; mfaToken = ""; error = nil; teams = []
    }
}
