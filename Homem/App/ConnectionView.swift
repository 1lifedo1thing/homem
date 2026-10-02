import SwiftUI

struct ConnectionView: View {
    var isAddingAccount = false
    var onCancel: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var showAccounts = false
    @Environment(AppStore.self) private var store
    @State private var address: String = {
        let saved = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        return saved == OfficialServer.apiURL.absoluteString ? "" : saved
    }()
    @State private var username = ""
    @State private var password = ""
    @State private var token = ""
    @State private var useToken = false
    @State private var showCustomServer = false
    @State private var showOfficialSignIn = false
    @State private var busy = false
    @State private var connectionTask: Task<Void, Never>?
    @State private var error: String?
    private enum Field { case address, username, password, token }
    @FocusState private var focusedField: Field?
    var body: some View {
        Group {
            if isAddingAccount && showOfficialSignIn {
                OfficialSignInView(onCancel: { showOfficialSignIn = false })
            } else {
                #if os(visionOS)
                connectionForm.frame(width: isAddingAccount ? 560 : nil, height: isAddingAccount ? 660 : nil)
                #else
                connectionForm.frame(idealWidth: isAddingAccount ? 480 : nil,
                                     idealHeight: isAddingAccount ? (showCustomServer ? 620 : 260) : nil)
                #endif
            }
        }.onDisappear { connectionTask?.cancel() }
    }
    private var connectionForm: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    if !isAddingAccount {
                        VStack(spacing: 20) {
                            Image("WelcomeMark").resizable().scaledToFit()
                                .frame(width: 88, height: 88)
                                .clipShape(RoundedRectangle(cornerRadius: 22))
                                .accessibilityHidden(true)
                            VStack(spacing: 12) {
                                Text(Theme.onboardingTitle.localized).font(.system(.largeTitle, design: .rounded, weight: .bold))
                                Text("Chats, files, and agents in one place.".localized)
                                    .foregroundStyle(.secondary).lineSpacing(3)
                            }.multilineTextAlignment(.center)
                        }.padding(.top, 32).padding(.bottom, 8)
                    }
                    VStack(spacing: 16) {
                        Button { showOfficialSignIn = true } label: {
                            Label("Sign in to Memoh".localized, systemImage: "arrow.right")
                                .fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 8).signInActionLabel()
                        }.signInPrimaryAction().disabled(busy).accessibilityIdentifier("officialSignIn")
                        Text("Use your email — no password needed.".localized).font(.subheadline).foregroundStyle(.secondary)
                    }
                    #if os(visionOS)
                    Button { showCustomServer = true } label: {
                        Label("Use another server".localized, systemImage: "server.rack").signInActionLabel()
                    }.signInSecondaryAction().accessibilityIdentifier("customServerSignIn")
                        .navigationDestination(isPresented: $showCustomServer) { customServerScreen }
                    #else
                    DisclosureGroup("Use another server".localized, isExpanded: $showCustomServer) {
                        customServerForm.padding(.top, 16)
                    }
                    #endif
                }.padding(32).padding(.bottom, 24).frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
            }.dismissKeyboardOnScroll().background(Theme.groupedCanvas).navigationTitle(isAddingAccount ? "Add account".localized : "").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if isAddingAccount && showsRootAccountActions {
                        ToolbarItem(placement: .cancellationAction) {
                            cancelButton
                        }
                    } else if !isAddingAccount && showsRootAccountActions && !store.savedAccounts.isEmpty {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { showAccounts = true } label: { Text("Accounts".localized).signInActionLabel(fullWidth: false) }.disabled(busy)
                        }
                    }
                }
                .sheet(isPresented: $showAccounts) { AccountsView() }
                .onChange(of: store.connectionID) { _, _ in if isAddingAccount { dismiss() } }
                .sheet(isPresented: Binding(get: { !isAddingAccount && showOfficialSignIn }, set: { showOfficialSignIn = $0 })) { OfficialSignInView() }
        }.onDisappear { connectionTask?.cancel() }
    }
    private var showsRootAccountActions: Bool {
        #if os(visionOS)
        !showCustomServer
        #else
        true
        #endif
    }
    private var customServerScreen: some View {
        ScrollView {
            customServerForm.padding(32).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }.navigationTitle("Custom server".localized).navigationBarTitleDisplayMode(.inline)
            .background(Theme.canvas)
            .toolbar {
                if isAddingAccount {
                    // Keep Cancel away from the system's Back target.
                    ToolbarItem(placement: .topBarTrailing) { cancelButton }
                }
            }
            .onDisappear { connectionTask?.cancel() }
    }
    private var cancelButton: some View {
        Button {
            connectionTask?.cancel()
            if let onCancel { onCancel() } else { dismiss() }
        } label: { Text("Cancel".localized).signInActionLabel(fullWidth: false) }
    }
    private var customServerForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Custom server".localized).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            TextField("https://memoh.example.com/api", text: $address)
                .textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($focusedField, equals: .address).signInField().accessibilityIdentifier("serverAddress")
            Text("Use /api for the web server, or the direct backend address (usually port 8080).")
                .font(.caption).foregroundStyle(.secondary)
            if address.lowercased().hasPrefix("http://") {
                Label("This connection uses unencrypted HTTP.".localized, systemImage: "lock.open").font(.caption).foregroundStyle(.orange)
            }
            if useToken {
                SecureField("Access token".localized, text: $token)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().focused($focusedField, equals: .token)
                    .signInField().accessibilityIdentifier("serverToken")
            } else {
                TextField("Username".localized, text: $username)
                    .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focusedField, equals: .username).signInField().accessibilityIdentifier("serverUsername")
                SecureField("Password".localized, text: $password).textContentType(.password)
                    .focused($focusedField, equals: .password).signInField().accessibilityIdentifier("serverPassword")
            }
            Button { focusedField = nil; useToken.toggle(); error = nil } label: {
                Text(useToken ? "Use username and password".localized : "Use an access token".localized).signInActionLabel()
            }.font(.caption).signInSecondaryAction().accessibilityIdentifier("serverLoginMethod")
            if let error { ErrorBanner(message: error) }
            Button(action: startConnection) {
                HStack {
                    Spacer()
                    if busy { ProgressView().tint(.white) }
                    Text(busy ? "Connecting…".localized : "Connect to Memoh".localized).fontWeight(.semibold)
                    if !busy { Image(systemName: "arrow.right") }
                    Spacer()
                }.padding(.vertical, 8).signInActionLabel()
            }.signInPrimaryAction()
                .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (useToken ? token.isEmpty : username.isEmpty || password.isEmpty))
                .accessibilityIdentifier("connectServer")
        }.disabled(busy)
    }
    private func startConnection() {
        // Lock synchronously, before creating the task, so rapid pinches cannot
        // launch two account connections while the first task is being scheduled.
        guard !busy else { return }
        busy = true; error = nil; focusedField = nil
        connectionTask = Task { await connect() }
    }
    private func connect() async {
        defer { busy = false }
        do { try await store.connect(address: address, username: username, password: password, accessToken: useToken ? token : ""); password = ""; token = "" }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
