import SwiftUI
import UniformTypeIdentifiers

struct NewChatDraft: Hashable {
    var text: String
    var attachments: [JSONValue]
    var targetID: String
}

struct RunLocation: Identifiable {
    let value: JSONValue
    var id: String { value["target_id"].string }
    var name: String { value["kind"] == "native" ? "Memoh workspace" : value["name"].string.nonEmpty ?? "Computer" }
    var symbol: String { value["kind"] == "native" ? "shippingbox" : "desktopcomputer" }
    var available: Bool {
        value["kind"] == "native"
            || (value["online"] != false && (value["status"] == "online" || value["status"].string.isEmpty && value["online"].bool))
    }
}

enum ChatAttachment {
    static func read(_ url: URL, existingCount: Int) throws -> JSONValue {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 10 * 1024 * 1024, existingCount < 5 else {
            throw ClientError.message("Attach up to five files, each smaller than 10 MB.")
        }
        let data = try Data(contentsOf: url)
        guard data.count <= 10 * 1024 * 1024 else { throw ClientError.message("This file is larger than 10 MB.") }
        let type = UTType(filenameExtension: url.pathExtension)
        let mime = type?.preferredMIMEType ?? "application/octet-stream"
        let kind =
            type?.conforms(to: .image) == true
            ? "image" : type?.conforms(to: .audio) == true ? "audio" : type?.conforms(to: .movie) == true ? "video" : "file"
        return [
            "type": .string(kind), "name": .string(url.lastPathComponent), "mime": .string(mime),
            "base64": .string("data:\(mime);base64,\(data.base64EncodedString())"),
        ]
    }
}

struct NewConversationView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var botID: String
    var onCreated: (ChatDestination) -> Void
    @State private var text = ""
    @State private var attachments: [JSONValue] = []
    @State private var locations: [RunLocation] = []
    @State private var targetID = ""
    @State private var loadingLocations = false
    @State private var locationError: String?
    @State private var error: String?
    @State private var busy = false
    @State private var filePicker = false
    @State private var locationPicker = false
    @FocusState private var focused: Bool
    private var bot: Record? { store.bots.first { $0.id == botID } }
    private var location: RunLocation? { locations.first { $0.id == targetID } }
    private var canSend: Bool {
        bot != nil && !busy && !loadingLocations && (targetID.isEmpty || locations.contains { $0.id == targetID && $0.available })
            && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 16) {
                            AgentAvatar(name: bot?.title ?? "Agent", avatarURL: bot?.value["avatar_url"].string ?? "", size: 44)
                            VStack(alignment: .leading, spacing: 6) {
                                Eyebrow(text: "TO")
                                Text(bot?.title ?? "Choose an agent").font(.system(.title2, weight: .bold)).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }
                        Divider()
                        runLocationButton
                    }.padding(.vertical, 8)
                    if loadingLocations { ProgressView("Finding run locations…").font(.caption) }
                    if let locationError {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(locationError).font(.caption).foregroundStyle(.secondary)
                            Button("Try again") { Task { await loadLocations() } }.font(.caption)
                        }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 16) {
                        TextField("Message \(bot?.title ?? "your agent")…", text: $text, axis: .vertical)
                            .lineLimit(5...12).focused($focused).accessibilityIdentifier("newChatMessage")
                        ForEach(Array(attachments.enumerated()), id: \.offset) { index, item in
                            HStack {
                                Label(item["name"].string, systemImage: "paperclip").lineLimit(1)
                                Spacer()
                                Button {
                                    attachments.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }.accessibilityLabel("Remove \(item["name"].string)")
                            }.font(.subheadline)
                        }

                    }.padding(.vertical, 8)
                    if let error { ErrorBanner(message: error) }
                }.padding(Theme.gutter).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }.scrollDismissesKeyboard(.interactively).background(Theme.canvas)
                .safeAreaInset(edge: .bottom) {
                    composerActions.padding(.horizontal, 22).padding(.vertical, 12)
                        .frame(maxWidth: 640).frame(maxWidth: .infinity).background(.bar)
                }
                .navigationTitle("New chat").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
                    ToolbarItem(placement: .topBarTrailing) { AgentPickerMenu(selection: $botID).disabled(busy) }
                }
                .interactiveDismissDisabled(busy).disabled(busy)
                .task(id: botID) {
                    targetID = ""
                    await loadLocations()
                }
                .fileImporter(isPresented: $filePicker, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
                    do {
                        for url in try result.get() { attachments.append(try ChatAttachment.read(url, existingCount: attachments.count)) }
                    } catch { self.error = error.localizedDescription }
                }
        }
    }
    private var runLocationButton: some View {
        Button { locationPicker = true } label: {
            HStack(spacing: 12) {
                AgentAvatar(name: location?.name ?? "Workspace", size: 32, symbol: location?.symbol ?? "arrow.triangle.branch")
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "RUN ON")
                    Text(location?.name ?? "Agent default").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                }
                Spacer(minLength: 8)
                if let location { StatusIndicator(text: location.available ? "Online" : "Offline", color: location.available ? .green : .secondary) }
                Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            }.frame(minHeight: 48).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(loadingLocations)
            .accessibilityLabel("Run on, " + (location?.name ?? "Agent default"))
            .accessibilityIdentifier("newChatRunLocation")
            .popover(isPresented: $locationPicker, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(text: "RUN LOCATION").padding(18)
                    Divider()
                    ScrollView {
                        VStack(spacing: 2) {
                            locationOption(id: "", name: "Agent default", symbol: "arrow.triangle.branch", detail: "Use this agent’s preferred workspace", available: true)
                            ForEach(locations) { target in
                                locationOption(id: target.id, name: target.name, symbol: target.symbol,
                                               detail: target.available ? "Online" : "Offline", available: target.available)
                            }
                        }.padding(6)
                    }.frame(maxHeight: 340)
                }.frame(width: 300).fixedSize(horizontal: false, vertical: true).presentationCompactAdaptation(.popover)
            }
    }
    private func locationOption(id: String, name: String, symbol: String, detail: String, available: Bool) -> some View {
        Button {
            targetID = id
            locationPicker = false
        } label: {
            HStack(spacing: 12) {
                AgentAvatar(name: name, size: 40, symbol: symbol)
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.headline).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if targetID == id { Image(systemName: "checkmark").font(.subheadline.bold()) }
            }.padding(12).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!available).opacity(available ? 1 : 0.45)
            .accessibilityLabel(name).accessibilityValue(targetID == id ? "Selected" : detail)
    }
    private var composerActions: some View {
        HStack {
            Button {
                filePicker = true
            } label: {
                Label("Attach", systemImage: "plus")
            }.disabled(attachments.count >= 5)
            Spacer()
            if focused {
                Button {
                    focused = false
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down").frame(width: 44, height: 44)
                }.accessibilityLabel("Hide keyboard")
            }
            Button {
                Task { await create() }
            } label: {
                HStack {
                    if busy { ProgressView() } else { Image(systemName: "arrow.up") }
                    Text(busy ? "Starting…" : "Send")
                }
            }.buttonStyle(.borderedProminent).disabled(!canSend).accessibilityIdentifier("startConversation")
        }
    }
    private func loadLocations() async {
        guard let api = store.api else { return }
        let requestedBot = botID
        loadingLocations = true
        locationError = nil
        locations = []
        do {
            let response = try await api.call("/bots/\(requestedBot.pathComponent)/workspace-targets")
            guard requestedBot == botID, !Task.isCancelled else { return }
            locations = response["targets"].array.map(RunLocation.init).filter { !$0.id.isEmpty }
        } catch {
            guard requestedBot == botID, !Task.isCancelled else { return }
            locationError = "Run locations couldn’t be loaded. You can still use the agent’s default workspace."
        }
        if requestedBot == botID { loadingLocations = false }
    }
    private func create() async {
        guard canSend, let api = store.api, let bot else { return }
        busy = true
        error = nil
        defer { busy = false }
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = String((message.nonEmpty ?? attachments.first?["name"].string ?? "New chat").prefix(80))
        do {
            let session = try await api.call(
                "/bots/\(bot.id.pathComponent)/sessions", method: "POST",
                body: ["title": .string(title), "channel_type": "local", "type": "chat"])
            guard !session["id"].string.isEmpty else { throw ClientError.invalidResponse }
            onCreated(
                ChatDestination(
                    botID: bot.id, sessionID: session["id"].string, title: title, botName: bot.title,
                    firstMessage: NewChatDraft(text: message, attachments: attachments, targetID: targetID)))
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
