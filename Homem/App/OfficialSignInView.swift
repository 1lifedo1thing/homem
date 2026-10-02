import SwiftUI
import WebKit

struct OfficialSignInView: View {
    var onCancel: (() -> Void)?
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
    @State private var formHeight: CGFloat = 320

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
                        Button {
                            run {
                                let cookies = await browser.configuration.websiteDataStore.httpCookieStore.allCookies()
                                try await login.useBrowserCookies(cookies)
                                self.browser = nil
                                try await connectSingleWorkspace()
                            }
                        } label: { Text("Continue in Homem".localized).signInActionLabel() }
                        .signInPrimaryAction().disabled(login.busy).padding(24)
                    }
                } else {
                    signInForm
                }
            }.navigationTitle("Sign in to Memoh".localized).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            task?.cancel()
                            if let onCancel { onCancel() } else { dismiss() }
                        } label: { Text("Cancel".localized).signInActionLabel(fullWidth: false) }
                    }
                    if browser != nil {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                browser = nil
                                login.error = nil
                            } label: { Text("Use email".localized).signInActionLabel(fullWidth: false) }
                            .disabled(login.busy)
                        }
                    }
                }
                .interactiveDismissDisabled(login.busy)
        }
        .modifier(SignInPresentation(browser: browser != nil, formHeight: formHeight))
        .onDisappear {
            task?.cancel()
            browser?.stopLoading()
            if store.api !== login.client { login.client.session.invalidateAndCancel() }
        }
    }
    private var signInForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(subtitle).font(.body).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 20) {
                    switch login.step {
                    case .email:
                        TextField("Email address".localized, text: $login.email)
                            .textContentType(.emailAddress).keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($focusedField, equals: .email).submitLabel(.continue)
                            #if !os(visionOS)
                            .onSubmit { if login.validEmail && !login.busy { sendCode() } }
                            #endif
                            .signInField()
                            .disabled(login.busy).accessibilityIdentifier("officialEmail")
                        Button { sendCode() } label: { actionLabel("Send sign-in code") }
                            .signInPrimaryAction()
                            .disabled(login.busy || !login.validEmail).accessibilityIdentifier("sendOfficialCode")
                    case .code, .mfa:
                        TextField("000000", text: $login.code)
                            .accessibilityLabel(login.step == .mfa ? "Authenticator code".localized : "Email code".localized)
                            .textContentType(.oneTimeCode).keyboardType(.numberPad)
                            .font(.title2.monospaced()).tracking(6).focused($focusedField, equals: .code)
                            .signInField()
                            .disabled(login.busy).accessibilityIdentifier("officialCode")
                            .onChange(of: login.code) { _, value in
                                let digits = String(value.filter { $0.isASCII && $0.isNumber }.prefix(6))
                                if digits != value { login.code = digits; return }
                                #if !os(visionOS)
                                if login.validCode && !login.busy { verifyCode() }
                                #endif
                            }
                        Button { verifyCode() } label: { actionLabel("Verify and continue") }
                            .signInPrimaryAction().disabled(login.busy || !login.validCode)
                            .accessibilityIdentifier("verifyOfficialCode")
                        codeRecoveryActions
                    case .workspaces:
                        ForEach(login.teams, id: \.self) { team in
                            Button {
                                run { try await store.connectOfficial(client: login.client, teamID: team["team_id"].string, workspace: team); dismiss() }
                            } label: {
                                HStack(spacing: 12) {
                                    AgentAvatar(name: team.text("name", "slug"), avatarURL: team.avatarURL, size: 36, baseURL: OfficialServer.origin, imageAPI: login.client)
                                    Text(team.text("name", "slug").nonEmpty ?? "Memoh workspace".localized).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }.padding(14).signInActionLabel().background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                            }.buttonStyle(.plain).spatialHoverEffect().disabled(login.busy)
                        }
                        if login.busy { ProgressView().frame(maxWidth: .infinity) }
                        if login.teams.isEmpty { Text("Finish creating or joining a workspace on Memoh, then return here.".localized).font(.subheadline).foregroundStyle(.secondary) }
                        Button { run { try await login.loadWorkspaces() } } label: { Text("Refresh workspaces".localized).signInActionLabel() }
                            .signInSecondaryAction().disabled(login.busy)
                    }
                }
                if let error = login.error { ErrorBanner(message: error) }
                Button(action: openBrowser) {
                    Text(login.step == .workspaces ? "Open Memoh in browser".localized : "Continue in browser".localized).signInActionLabel()
                }.font(.subheadline).frame(maxWidth: .infinity).signInSecondaryAction().disabled(login.busy).accessibilityIdentifier("officialBrowser")
            }.padding(32).frame(maxWidth: 520)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: SignInFormHeight.self, value: proxy.size.height)
                    }
                }
                .frame(maxWidth: .infinity)
        }.background(Theme.canvas).dismissKeyboardOnScroll()
            .onPreferenceChange(SignInFormHeight.self) { height in
                if height > 0, abs(formHeight - height) > 1 { formHeight = height }
            }
            .task { updateFocus() }.onChange(of: login.step) { _, _ in updateFocus() }
    }
    private var codeRecoveryActions: some View {
        Group {
            #if os(visionOS)
            HStack(spacing: 20) { recoveryButtons }
            #else
            HStack { recoveryButtons }.font(.footnote)
            #endif
        }
    }
    @ViewBuilder private var recoveryButtons: some View {
        if login.step == .code {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = max(0, Int(ceil(login.resendAfter.timeIntervalSince(context.date))))
                Button { run { try await login.sendCode() } } label: {
                    Text(seconds > 0 ? AppLocalization.format("Resend in %llds", seconds) : "Resend code".localized)
                        .monospacedDigit().signInActionLabel()
                }.signInSecondaryAction().disabled(login.busy || seconds > 0).accessibilityIdentifier("resendOfficialCode")
            }
        }
        #if !os(visionOS)
        Spacer()
        #endif
        Button { login.changeEmail(); updateFocus() } label: {
            Text("Use a different email".localized).signInActionLabel()
        }.signInSecondaryAction().disabled(login.busy).accessibilityIdentifier("changeOfficialEmail")
    }
    private func actionLabel(_ title: String) -> some View {
        HStack(spacing: 10) {
            if login.busy { ProgressView().tint(.white) }
            Text(title.localized).fontWeight(.semibold)
        }.frame(maxWidth: .infinity).padding(.vertical, 5).signInActionLabel()
    }
    private func updateFocus() {
        #if os(visionOS)
        // Do not move the keyboard or select a new target as a network request
        // finishes. Eye input should choose the next field deliberately.
        focusedField = nil
        #else
        switch login.step { case .email: focusedField = .email; case .code, .mfa: focusedField = .code; case .workspaces: focusedField = nil }
        #endif
    }
    private var subtitle: String {
        switch login.step {
        case .email: return "Enter your email to sign in or create an account.".localized
        case .code: return AppLocalization.format("We sent a six-digit code to %@.", login.email)
        case .mfa: return "Enter the code from your authenticator app.".localized
        case .workspaces: return "Choose where you’d like to continue.".localized
        }
    }
    private func sendCode() {
        guard login.validEmail else { return }
        focusedField = nil
        run {
            try await login.sendCode()
            updateFocus()
        }
    }
    private func verifyCode() {
        guard login.validCode else { return }
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

private struct SignInFormHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// A short form gets a fitted sheet on expanded displays. The scroll view can
/// still shrink above the keyboard, and the browser retains a full-page canvas.
private struct SignInPresentation: ViewModifier {
    let browser: Bool
    let formHeight: CGFloat
    @ViewBuilder func body(content: Content) -> some View {
        #if os(visionOS)
        // A fitted form changes position under the user's gaze as the code,
        // cooldown, or error appears. Reserve one stable canvas for all steps.
        content.frame(width: browser ? 760 : 560, height: browser ? 720 : 660)
            .presentationSizing(.fitted)
        #else
        if #available(iOS 18.0, *) {
            if browser {
                content.frame(idealWidth: 720, idealHeight: 680).presentationSizing(.page)
            } else {
                content.frame(idealWidth: 480, idealHeight: formHeight + 64)
                    .presentationSizing(.fitted)
            }
        } else { content }
        #endif
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
