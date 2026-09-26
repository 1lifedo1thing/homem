import SwiftUI

struct DataSharingDetails: View {
    let disclosure: DataSharingDisclosure
    var body: some View {
        Section("Data sent".localized) {
            Text("When you use connected features, your server receives your messages, conversation history, files and photos you attach or upload, voice recordings, agent instructions, memories, and tool inputs and results. These may contain personal information.".localized)
            Text("Your server forwards the content needed for your request to its configured AI and other service providers to generate answers, process media, search, remember information, and run tools. Terminal input and desktop controls go to your remote workspace; files and results there may be used by an agent.".localized)
        }
        Section("Who receives it".localized) {
            Text(disclosure.server).font(.body.monospaced()).textSelection(.enabled)
            Text("The following services are reported by this server. A custom endpoint may be a gateway that forwards requests to the provider chosen by your administrator.".localized)
                .font(.footnote).foregroundStyle(.secondary)
            ForEach(disclosure.recipients) { recipient in
                VStack(alignment: .leading, spacing: 4) {
                    Text(recipient.name).fontWeight(.medium)
                    if !recipient.endpoint.isEmpty { Text(recipient.endpoint).font(.caption.monospaced()).foregroundStyle(.secondary) }
                }
            }
            if disclosure.recipients.isEmpty { Text("No enabled providers were reported. Your selected server still receives the information described above.".localized) }
        }
        Section("Your choice".localized) {
            Text("Allow only if you trust this server and these recipients. Their retention and processing policies apply. You can withdraw permission in Settings → AI data sharing. This stops new sharing from Homem; it does not delete data already sent or stop tasks already running on the server.".localized)
            Link("Privacy policy".localized, destination: DataSharingDisclosure.policyURL)
        }
    }
}

