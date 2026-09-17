import SwiftUI

struct ConnectionView: View {
    @Environment(\.appAccent) private var accent
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
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack { Image(systemName: "house.and.flag.fill").font(.title2).foregroundStyle(accent); Text("homem").font(.title2.weight(.bold)); Spacer() }
                        .padding(.top, 16)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Memoh, on your iPhone.".localized).font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text("Chats, files, and agents in one place.".localized).foregroundStyle(.secondary).lineSpacing(3)
                    }
                    VStack(alignment: .leading, spacing: 15) {
                        Label("Official Memoh".localized, systemImage: "checkmark.seal.fill").font(.caption.weight(.semibold)).foregroundStyle(accent)
                        Text("Continue with your Memoh account.".localized).font(.headline)
                        Text("Use your email — no password needed.".localized).font(.subheadline).foregroundStyle(.secondary)
                        Button { showOfficialSignIn = true } label: {
                            HStack { Spacer(); Text("Sign in to Memoh".localized).fontWeight(.semibold); Image(systemName: "arrow.right"); Spacer() }.padding(.vertical, 8)
                        }.buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("officialSignIn")
                    }
                    DisclosureGroup("Use another server".localized, isExpanded: $showCustomServer) {
                      VStack(alignment: .leading, spacing: 15) {
                        Text("Custom server".localized).font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary)
                        TextField("https://memoh.example.com/api", text: $address).textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("serverAddress")
                            .padding(14).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                        Text("Use /api for the web server, or the direct backend address (usually port 8080).").font(.caption).foregroundStyle(.secondary)
                        if address.lowercased().hasPrefix("http://") { Label("This connection uses unencrypted HTTP.".localized, systemImage: "lock.open").font(.caption).foregroundStyle(.orange) }
                        if useToken {
                            SecureField("Access token".localized, text: $token).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                        } else {
                            TextField("Username".localized, text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                            SecureField("Password".localized, text: $password).textContentType(.password).textFieldStyle(.roundedBorder)
                        }
                        Button(useToken ? "Use username and password".localized : "Use an access token".localized) { useToken.toggle() }.font(.caption)
                        if let error { ErrorBanner(message: error) }
                        Button { Task { await connect() } } label: {
                            HStack { Spacer(); if busy { ProgressView().tint(.white) }; Text(busy ? "Connecting…".localized : "Connect to Memoh".localized).fontWeight(.semibold); if !busy { Image(systemName: "arrow.right") }; Spacer() }.padding(.vertical, 8)
                        }.buttonStyle(.borderedProminent).controlSize(.large).disabled(busy || address.isEmpty || (useToken ? token.isEmpty : username.isEmpty || password.isEmpty))
                            .accessibilityIdentifier("connectServer")
                      }.padding(.top, 16)
                    }
                    Button { store.enterDemo() } label: { HStack { Spacer(); Text("Explore the demo".localized); Image(systemName: "arrow.up.right"); Spacer() } }.accessibilityIdentifier("exploreDemo")
                    Text("Your sign-in is saved securely on this device.".localized).font(.caption2).foregroundStyle(.tertiary).frame(maxWidth: .infinity)
                }.padding(24).frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
            }.scrollDismissesKeyboard(.interactively).background(Color(.systemGroupedBackground)).navigationBarHidden(true)
                .sheet(isPresented: $showOfficialSignIn) { OfficialSignInView() }
        }
    }
    private func connect() async {
        busy = true; error = nil; defer { busy = false }
        do { try await store.connect(address: address, username: username, password: password, accessToken: useToken ? token : ""); password = ""; token = "" }
        catch { self.error = error.localizedDescription }
    }
}
