import SwiftUI
import WebKit

struct OfficialSignInView: View {
    @Environment(\.appAccent) private var accent
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var login = OfficialLogin()
    @State private var browser: WKWebView?
    @State private var browserHost = "app.memoh.net"
    private enum Field { case email, code }
    @FocusState private var focusedField: Field?
    @State private var browserLoading = false
    @State private var browserError: String?
    @State private var task: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                if let browser {
                    VStack(spacing: 0) {
                        Label(browserHost, systemImage: "lock.fill").font(.caption.monospaced()).padding(.top, 8)
                        if browserLoading { ProgressView().padding(8) }
                        OfficialBrowser(
                            webView: browser, onHostChange: { browserHost = $0 }, onLoading: { browserLoading = $0 },
                            onError: { browserError = $0 })
                        if let browserError {
                            ErrorBanner(message: browserError) {
                                self.browserError = nil
                                browser.reload()
                            }.padding(.horizontal)
                        }
                        Text("After signing in, tap Continue. You can switch to email at any time.".localized).font(.caption).foregroundStyle(
                            .secondary
                        ).padding(.horizontal)
                        if let error = login.error { ErrorBanner(message: error).padding(.horizontal) }
                        Button("Continue in Homem".localized) {
                            run {
                                let cookies = await browser.configuration.websiteDataStore.httpCookieStore.allCookies()
                                try await login.useBrowserCookies(cookies)
                                self.browser = nil
                                try await connectSingleWorkspace()
                            }
                        }.buttonStyle(.borderedProminent).disabled(login.busy).padding()
                    }
                } else {
                    signInForm
                }
            }.navigationTitle("Sign in to Memoh".localized).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel".localized) {
                            task?.cancel()
                            dismiss()
                        }
                    }
                    if browser != nil {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Use email".localized) {
                                browser = nil
                                login.error = nil
                            }.disabled(login.busy)
                        }
                    }
                }
                .interactiveDismissDisabled(login.busy)
        }.onDisappear {
            task?.cancel()
            browser?.stopLoading()
            if store.api !== login.client { login.client.session.invalidateAndCancel() }
        }
    }
    private var signInForm: some View {
        Form {
            signInHeader
            loginFields
            if let error = login.error { Section { ErrorBanner(message: error) } }
            if login.busy { Section { ProgressView("Connecting to Memoh…".localized) } }
            Section {
                Button(login.step == .workspaces ? "Open Memoh in browser".localized : "Continue in browser".localized) { openBrowser() }
                    .disabled(login.busy).accessibilityIdentifier("officialBrowser")
            } footer: {
                Text("Prefer GitHub or Google? Continue on the official website.".localized)
            }
        }.scrollDismissesKeyboard(.interactively)
            .task { updateFocus() }
            .onChange(of: login.step) { _, _ in updateFocus() }
    }
    private func updateFocus() {
        switch login.step {
        case .email: focusedField = .email
        case .code, .mfa: focusedField = .code
        case .workspaces: focusedField = nil
        }
    }
    private var heading: String {
        switch login.step {
        case .email: return "Welcome to Memoh"
        case .code: return "Check your inbox"
        case .mfa: return "One more step"
        case .workspaces: return "Your workspaces"
        }
    }
    private var subtitle: String {
        switch login.step {
        case .email: return "Enter your email to sign in or create an account."
        case .code: return AppLocalization.format("We sent a six-digit code to %@.", login.email)
        case .mfa: return "Enter the code from your authenticator app."
        case .workspaces: return "Choose where you’d like to continue."
        }
    }
    private var signInHeader: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("app.memoh.net", systemImage: "checkmark.seal.fill").font(.subheadline).foregroundStyle(accent)
                Text(heading.localized).font(.title2.bold())
                Text(subtitle.localized).font(.subheadline).foregroundStyle(.secondary)
            }.padding(.vertical, 12)
        }.listRowBackground(Color.clear)
    }
    @ViewBuilder private var loginFields: some View {
        switch login.step {
        case .email:
            Section {
                TextField("Email address".localized, text: $login.email)
                    .textContentType(.emailAddress).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focusedField, equals: .email).submitLabel(.continue)
                    .onSubmit { if login.validEmail { sendCode() } }
                    .disabled(login.busy).accessibilityIdentifier("officialEmail")
                Button {
                    sendCode()
                } label: {
                    HStack {
                        Spacer()
                        if login.busy { ProgressView() }
                        Text((login.busy ? "Sending…" : "Send sign-in code").localized)
                        Spacer()
                    }
                }.buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(login.busy || !login.validEmail).accessibilityIdentifier("sendOfficialCode")
            } footer: {
                Text("No password to remember. Your session is saved securely on this device.".localized)
            }
        case .code, .mfa:
            Section {
                TextField("114514", text: $login.code)
                    .accessibilityLabel(login.step == .mfa ? "Authenticator code".localized : "Email code".localized)
                    .textContentType(.oneTimeCode).keyboardType(.numberPad)
                    .font(.title2.monospaced()).tracking(6).focused($focusedField, equals: .code)
                    .disabled(login.busy).accessibilityIdentifier("officialCode")
                    .onChange(of: login.code) { _, value in
                        let digits = String(value.filter { $0.isASCII && $0.isNumber }.prefix(6))
                        if digits != value {
                            login.code = digits
                            return
                        }
                        if login.validCode && !login.busy { verifyCode() }
                    }
                Button(login.busy ? "Verifying…".localized : "Verify and continue".localized) { verifyCode() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(login.busy || !login.validCode)
                if login.step == .code {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let seconds = max(0, Int(ceil(login.resendAfter.timeIntervalSince(context.date))))
                        Button(seconds > 0 ? AppLocalization.format("Resend in %llds", seconds) : "Resend code".localized) { run { try await login.sendCode() } }
                            .disabled(login.busy || seconds > 0)
                    }
                }
                Button("Use a different email".localized) {
                    login.changeEmail()
                    focusedField = .email
                }.disabled(login.busy)
            } footer: {
                if login.step == .code {
                    Text("You can paste your code or use the suggestion above the keyboard. Check spam if it hasn’t arrived.".localized)
                }
            }
        case .workspaces:
            Section("Choose your workspace".localized) {
                ForEach(login.teams, id: \.self) { team in
                    Button {
                        run {
                            try await store.connectOfficial(client: login.client, teamID: team["team_id"].string, workspace: team)
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            AgentAvatar(name: team.text("name", "slug"), avatarURL: team.avatarURL, size: 42, symbol: "square.stack.3d.up", baseURL: OfficialServer.origin)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(team.text("name", "slug").nonEmpty ?? "Memoh workspace".localized).font(.headline).foregroundStyle(.primary)
                                if let description = team["description"].string.nonEmpty { Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                            }
                            Spacer()
                            Image(systemName: "arrow.right").font(.subheadline.weight(.semibold))
                        }.padding(.vertical, 6)
                    }.disabled(login.busy)
                }
                if login.teams.isEmpty {
                    Text("Finish creating or joining a workspace on Memoh, then return here.".localized)
                }
                Button("Refresh workspaces".localized) { run { try await login.loadWorkspaces() } }.disabled(login.busy)
            }
        }
    }
    private func sendCode() {
        focusedField = nil
        run {
            try await login.sendCode()
            focusedField = .code
        }
    }
    private func verifyCode() {
        focusedField = nil
        run {
            try await login.verifyCode()
            try await connectSingleWorkspace()
        }
    }
    private func connectSingleWorkspace() async throws {
        guard login.step == .workspaces, login.teams.count == 1, let team = login.teams.first else { return }
        try await store.connectOfficial(client: login.client, teamID: team["team_id"].string, workspace: team)
        dismiss()
    }
    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard !login.busy else { return }
        login.busy = true
        login.error = nil
        task = Task { @MainActor in
            defer { login.busy = false }
            do { try await action() } catch { if !Task.isCancelled { login.error = error.localizedDescription } }
        }
    }
    private func openBrowser() {
        focusedField = nil
        browserError = nil
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
    var onLoading: (Bool) -> Void
    var onError: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onHostChange: onHostChange, onLoading: onLoading, onError: onError) }
    func makeUIView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.load(URLRequest(url: OfficialServer.origin.appendingPathComponent("login")))
        return webView
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let onHostChange: (String) -> Void
        let onLoading: (Bool) -> Void
        let onError: (String) -> Void
        init(onHostChange: @escaping (String) -> Void, onLoading: @escaping (Bool) -> Void, onError: @escaping (String) -> Void) {
            self.onHostChange = onHostChange
            self.onLoading = onLoading
            self.onError = onError
        }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { onLoading(true) }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onLoading(false) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
        private func failed(_ error: Error) {
            onLoading(false)
            if (error as NSError).code != NSURLErrorCancelled { onError(error.localizedDescription) }
        }
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            onHostChange(webView.url?.host ?? "app.memoh.net")
        }
        func webView(
            _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            decisionHandler(navigationAction.request.url?.scheme == "https" ? .allow : .cancel)
        }
        func webView(
            _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.request.url?.scheme == "https" { webView.load(navigationAction.request) }
            return nil
        }
    }
}
