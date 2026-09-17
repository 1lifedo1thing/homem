import SwiftUI
import AuthenticationServices

struct AuthorizationView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    var path: String
    var isMCP: Bool = false
    @State private var status: JSONValue = .null
    @State private var authorization: JSONValue = .null
    @State private var error: String?
    @State private var busy = false
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var authSession: BrowserAuthorization?
    var body: some View {
        Form {
            Section {
                Label(status["has_token"].bool ? "Account connected" : "Connect an account", systemImage: status["has_token"].bool ? "checkmark.shield" : "lock.shield").font(.headline)
                if !status.isNull { JSONDetails(value: status) }
            }
            if isMCP { Section("OAuth client (if required)".localized) { TextField("Client ID".localized, text: $clientID).textInputAutocapitalization(.never).autocorrectionDisabled(); SecureField("Client secret".localized, text: $clientSecret) } }
            Section {
                Button("Authorize account".localized) { Task { await authorize() } }.disabled(busy)
                if let url = URL(string: authorization.text("auth_url", "authorization_url")), !isMCP { Link("Open sign-in page".localized, destination: url) }
                let device = authorization["device"].isNull ? status["device"] : authorization["device"]
                if !device["user_code"].string.isEmpty {
                    LabeledContent("Device code".localized) { Text(device["user_code"].string).font(.title3.monospaced().bold()).textSelection(.enabled) }
                    if let url = URL(string: device["verification_uri"].string) { Link("Enter code in browser".localized, destination: url) }
                    Button("Check device authorization".localized) { Task { await poll() } }.disabled(busy)
                }
                Button("Refresh status".localized) { Task { await load() } }
            }
            if busy { ProgressView() }
            if let error { ErrorBanner(message: error) }
        }.navigationTitle("Account authorization".localized).navigationBarTitleDisplayMode(.inline).task { await load() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await load() } } }
    }
    func load() async { do { status = try await store.api?.call(path + "/oauth/status") ?? .null; error = nil } catch { self.error = error.localizedDescription } }
    func poll() async {
        busy = true; defer { busy = false }
        do { status = try await store.api?.call(path + "/oauth/poll", method: "POST") ?? .null; error = nil } catch { self.error = error.localizedDescription }
    }
    func authorize() async {
        guard let api = store.api else { return }; busy = true; defer { busy = false }
        do {
            if isMCP {
                var body: JSONValue = ["callback_url": "homem://oauth/mcp/callback"]
                if !clientID.isEmpty { body["client_id"] = .string(clientID) }
                if !clientSecret.isEmpty { body["client_secret"] = .string(clientSecret) }
                authorization = try await api.call(path + "/oauth/authorize", method: "POST", body: body)
                guard let url = URL(string: authorization["authorization_url"].string) else { throw ClientError.invalidResponse }
                let session = BrowserAuthorization(); authSession = session
                let callback = try await session.start(url: url)
                let query = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
                if let reason = query.first(where: { $0.name == "error" })?.value { throw ClientError.message(reason) }
                guard let code = query.first(where: { $0.name == "code" })?.value, let state = query.first(where: { $0.name == "state" })?.value else { throw ClientError.message("The authorization callback is missing its code or state.".localized) }
                _ = try await api.call(path + "/oauth/exchange", method: "POST", body: ["code": .string(code), "state": .string(state)])
                clientSecret = ""; await load()
            } else { authorization = try await api.call(path + "/oauth/authorize") }
        } catch { self.error = error.localizedDescription }
    }
}

@MainActor final class BrowserAuthorization: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    func start(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "homem") { url, error in
                if let error { continuation.resume(throwing: error) }
                else if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: ClientError.invalidResponse) }
            }
            session.presentationContextProvider = self
            self.session = session
            if !session.start() { continuation.resume(throwing: ClientError.message("Could not open the authorization browser.".localized)) }
        }
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
