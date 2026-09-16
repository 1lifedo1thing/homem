import SwiftUI

struct ConnectionView: View {
    @Environment(AppStore.self) private var store
    @State private var address = UserDefaults.standard.string(forKey: "serverURL") ?? ""
    @State private var username = ""
    @State private var password = ""
    @State private var token = ""
    @State private var useToken = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack { Image(systemName: "house.and.flag.fill").font(.title2).foregroundStyle(Theme.accent); Text("homem").font(.title2.weight(.bold)); Spacer(); Text("FOR MEMOH").font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(.secondary) }
                        .padding(.top, 30)
                    ZStack {
                        Circle().fill(Theme.accent.opacity(0.06)).frame(width: 210, height: 210)
                        Circle().stroke(Theme.accent.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 6])).frame(width: 180, height: 180)
                        AgentAvatar(name: "Atlas", size: 82).rotationEffect(.degrees(-9)).offset(x: -50, y: 10)
                        AgentAvatar(name: "Mika", size: 66).rotationEffect(.degrees(12)).offset(x: 48, y: -38)
                        AgentAvatar(name: "Sage", size: 48).rotationEffect(.degrees(-5)).offset(x: 52, y: 52)
                    }.frame(maxWidth: .infinity).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your agents.\nRight at home.").font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text("A little closer to everything you’re building. Connect Memoh and bring your workspace with you.").foregroundStyle(.secondary).lineSpacing(3)
                    }
                    VStack(alignment: .leading, spacing: 15) {
                        Text("CONNECT YOUR SERVER").font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary)
                        TextField("https://memoh.example.com/api", text: $address).textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("serverAddress")
                            .padding(14).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                        Text("Use /api for the web server, or the direct backend address (usually port 8080).").font(.caption).foregroundStyle(.secondary)
                        if address.lowercased().hasPrefix("http://") { Label("This connection uses unencrypted HTTP.", systemImage: "lock.open").font(.caption).foregroundStyle(.orange) }
                        if useToken {
                            SecureField("Access token", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                        } else {
                            TextField("Username", text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                            SecureField("Password", text: $password).textContentType(.password).textFieldStyle(.roundedBorder)
                        }
                        Button(useToken ? "Use username and password" : "Use an access token") { useToken.toggle() }.font(.caption)
                        if let error { ErrorBanner(message: error) }
                        Button { Task { await connect() } } label: {
                            HStack { Spacer(); if busy { ProgressView().tint(.white) }; Text(busy ? "Connecting…" : "Connect to Memoh").fontWeight(.semibold); if !busy { Image(systemName: "arrow.right") }; Spacer() }.padding(.vertical, 8)
                        }.buttonStyle(.borderedProminent).controlSize(.large).disabled(busy || address.isEmpty || (useToken ? token.isEmpty : username.isEmpty || password.isEmpty))
                            .accessibilityIdentifier("connectServer")
                    }
                    Button { store.enterDemo() } label: { HStack { Spacer(); Text("Explore the demo"); Image(systemName: "arrow.up.right"); Spacer() } }.accessibilityIdentifier("exploreDemo")
                    Text("Native on iPhone and iPad · Credentials stay in Keychain").font(.caption2).foregroundStyle(.tertiary).frame(maxWidth: .infinity)
                }.padding(28).frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
            }.background(Color(.systemGroupedBackground)).navigationBarHidden(true)
        }
    }
    private func connect() async {
        busy = true; error = nil; defer { busy = false }
        do { try await store.connect(address: address, username: username, password: password, accessToken: useToken ? token : ""); password = ""; token = "" }
        catch { self.error = error.localizedDescription }
    }
}
