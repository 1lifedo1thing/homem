import SwiftUI

struct DataSharingGate: View {
    @Environment(AppStore.self) private var store
    let api: APIClient
    @State private var saveError: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Allow AI data sharing?".localized, systemImage: "hand.raised.fill").font(.title2.bold())
                    Text("Before you use connected features, review what leaves your device and who receives it. Nothing is sent to AI services by this consent screen.".localized)
                }
                if let disclosure = api.dataSharing.disclosure { DataSharingDetails(disclosure: disclosure) }
                if api.dataSharing.loading { ProgressView() }
                if let error = saveError ?? api.dataSharing.error {
                    Section { Text(error).foregroundStyle(.red); Button("Try again".localized) { Task { await refresh() } } }
                }
                Section {
                    Button("Allow and continue".localized) {
                        do { try api.dataSharing.accept() } catch { saveError = error.localizedDescription }
                    }.disabled(api.dataSharing.disclosure == nil || api.dataSharing.error != nil || api.dataSharing.loading)
                        .accessibilityIdentifier("allowDataSharing")
                    Button("Don't allow".localized, role: .cancel) {
                        do { try api.dataSharing.revoke(); store.disconnect() } catch { saveError = error.localizedDescription }
                    }.accessibilityIdentifier("declineDataSharing")
                }
            }.navigationTitle("AI data sharing".localized).navigationBarTitleDisplayMode(.inline)
                .task { await refresh() }
        }
    }
    private func refresh() async {
        saveError = nil
        do { try await api.refreshDataSharing() } catch { /* The gate displays the failure and stays closed. */ }
    }
}

struct DataSharingSettings: View {
    @Environment(AppStore.self) private var store
    @State private var error: String?
    var body: some View {
        Form {
            if let disclosure = store.api?.dataSharing.disclosure { DataSharingDetails(disclosure: disclosure) }
            if let error { Text(error).foregroundStyle(.red) }
            Section {
                Button("Withdraw permission and disconnect".localized, role: .destructive) {
                    do { try store.api?.dataSharing.revoke(); store.disconnect() } catch { self.error = error.localizedDescription }
                }.accessibilityIdentifier("withdrawDataSharing")
            }
        }.navigationTitle("AI data sharing".localized)
    }
}
