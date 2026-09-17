import SwiftUI
import WebKit

struct OfficialSignInView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var login = OfficialLogin()
    @State private var browser: WKWebView?
    @State private var browserHost = "app.memoh.net"
    @State private var task: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                if let browser {
                    VStack(spacing: 0) {
                        Label(browserHost, systemImage: "lock.fill").font(.caption.monospaced()).padding(.top, 8)
                        Text("Sign in at app.memoh.net, then continue in Homem. If a provider doesn’t support embedded browsers, use email sign-in.")
                            .font(.caption).foregroundStyle(.secondary).padding()
                        OfficialBrowser(webView: browser) { browserHost = $0 }
                        if let error = login.error { ErrorBanner(message: error).padding(.horizontal) }
                        Button("Continue in Homem") {
                            run {
                                let cookies = await browser.configuration.websiteDataStore.httpCookieStore.allCookies()
                                try await login.useBrowserCookies(cookies)
                                self.browser = nil
                            }
                        }.buttonStyle(.borderedProminent).disabled(login.busy).padding()
                    }
                } else {
                    Form {
                        Section {
                            Label("Official Memoh", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.accent)
                            Text("app.memoh.net").font(.caption).foregroundStyle(.secondary)
                        }
                        switch login.step {
                        case .email:
                            Section {
                                TextField("Email address", text: $login.email)
                                    .textContentType(.emailAddress).keyboardType(.emailAddress)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .accessibilityIdentifier("officialEmail")
                                Button("Send sign-in code") { run { try await login.sendCode() } }
                                    .disabled(login.busy || !login.validEmail).accessibilityIdentifier("sendOfficialCode")
                            } header: { Text("Sign in or sign up") } footer: { Text("Memoh will email you a six-digit code. New accounts follow Memoh’s registration policy.") }
                        case .code, .mfa:
                            Section {
                                TextField(login.step == .mfa ? "Authenticator code" : "Email code", text: $login.code)
                                    .textContentType(.oneTimeCode).keyboardType(.numberPad)
                                    .accessibilityIdentifier("officialCode")
                                Button("Verify and continue") { run { try await login.verifyCode() } }
                                    .disabled(login.busy || !login.validCode)
                                if login.step == .code {
                                    TimelineView(.periodic(from: .now, by: 1)) { context in
                                        let seconds = max(0, Int(ceil(login.resendAfter.timeIntervalSince(context.date))))
                                        Button(seconds > 0 ? "Resend in \(seconds)s" : "Resend code") { run { try await login.sendCode() } }
                                            .disabled(login.busy || seconds > 0)
                                    }
                                }
                                Button("Use a different email") { login.changeEmail() }.disabled(login.busy)
                            } header: { Text(login.step == .mfa ? "Two-factor authentication" : "Check your inbox") }
                            footer: { Text(login.step == .mfa ? "Enter the code from your authenticator app." : "Enter the code sent to \(login.email).") }
                        case .workspaces:
                            Section("Choose your workspace") {
                                ForEach(login.teams, id: \.self) { team in
                                    Button(team.text("name", "slug").nonEmpty ?? "Memoh workspace") {
                                        run {
                                            try await store.connectOfficial(client: login.client, teamID: team["team_id"].string)
                                            dismiss()
                                        }
                                    }.disabled(login.busy)
                                }
                                if login.teams.isEmpty {
                                    Text("Finish creating or joining a workspace on Memoh, then return here.")
                                }
                                Button("Refresh workspaces") { run { try await login.loadWorkspaces() } }.disabled(login.busy)
                            }
                        }
                        if let error = login.error { Section { ErrorBanner(message: error) } }
                        if login.busy { Section { ProgressView("Connecting to Memoh…") } }
                        Section {
                            Button(login.step == .workspaces ? "Open Memoh in browser" : "Continue in browser") { openBrowser() }
                                .disabled(login.busy).accessibilityIdentifier("officialBrowser")
                        } footer: { Text("The official website also offers GitHub and Google sign-in. Your sign-in session is stored securely in Keychain after you select a workspace.") }
                    }
                }
            }.navigationTitle("Sign in to Memoh").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { task?.cancel(); dismiss() } }
                    if browser != nil { ToolbarItem(placement: .topBarTrailing) { Button("Use email") { browser = nil; login.error = nil }.disabled(login.busy) } }
                }
                .interactiveDismissDisabled(login.busy)
        }.onDisappear { task?.cancel(); browser?.stopLoading(); if store.api !== login.client { login.client.session.invalidateAndCancel() } }
    }
    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard !login.busy else { return }
        login.busy = true; login.error = nil
        task = Task { @MainActor in
            defer { login.busy = false }
            do { try await action() } catch { if !Task.isCancelled { login.error = error.localizedDescription } }
        }
    }
    private func openBrowser() {
        run {
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .nonPersistent()
            for cookie in login.client.session.configuration.httpCookieStorage?.cookies ?? [] where OfficialServer.accepts(cookie) {
                await config.websiteDataStore.httpCookieStore.setCookie(cookie)
            }
            try Task.checkCancellation()
            let view = WKWebView(frame: .zero, configuration: config)
            view.allowsBackForwardNavigationGestures = true
            browser = view
        }
    }
}

private struct OfficialBrowser: UIViewRepresentable {
    let webView: WKWebView
    var onHostChange: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onHostChange: onHostChange) }
    func makeUIView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator; webView.uiDelegate = context.coordinator
        webView.load(URLRequest(url: OfficialServer.origin.appendingPathComponent("login")))
        return webView
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let onHostChange: (String) -> Void
        init(onHostChange: @escaping (String) -> Void) { self.onHostChange = onHostChange }
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            onHostChange(webView.url?.host ?? "app.memoh.net")
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.request.url?.scheme == "https" ? .allow : .cancel)
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.request.url?.scheme == "https" { webView.load(navigationAction.request) }
            return nil
        }
    }
}
