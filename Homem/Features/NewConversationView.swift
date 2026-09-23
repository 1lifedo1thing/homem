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
    var name: String { value["kind"] == "native" ? "Memoh workspace".localized : value["name"].string.nonEmpty ?? "Computer".localized }
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
            throw ClientError.message("Attach up to five files, each smaller than 10 MB.".localized)
        }
        let data = try Data(contentsOf: url)
        guard data.count <= 10 * 1024 * 1024 else { throw ClientError.message("This file is larger than 10 MB.".localized) }
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

/// Runtime identity is separate from the bot whose workspace hosts the conversation.
enum ChatAgentType: String {
    case memoh, codex, claudeCode = "claude-code", acp
    var title: String {
        switch self { case .memoh: "Memoh"; case .codex: "Codex"; case .claudeCode: "Claude Code"; case .acp: "ACP" }
    }
    var asset: String { "Runtime-" + rawValue }
    static func resolve(runtime: String, provider: String = "") -> Self {
        let runtime = runtime.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch runtime {
        case "codex": return .codex
        case "claude-code", "claude_code": return .claudeCode
        case "acp", "acp_agent":
            switch provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "codex": return .codex
            case "claude-code": return .claudeCode
            default: return .acp
            }
        default: return .memoh
        }
    }
    static func session(_ value: JSONValue) -> Self {
        resolve(runtime: value["runtime_type"].string.nonEmpty ?? (value["type"] == "acp_agent" ? "acp_agent" : "model"),
                provider: value["runtime_metadata"]["acp_agent_id"].string.nonEmpty ?? value["metadata"]["acp_agent_id"].string)
    }
}

struct ConversationAgent: Identifiable {
    let value: JSONValue
    var id: String { value["id"].string }
    var isMemoh: Bool { id.isEmpty }
    var runtime: String { isMemoh ? "model" : value["runtime"].string == "acp" ? "acp_agent" : value["runtime"].string }
    var type: ChatAgentType { ChatAgentType.resolve(runtime: runtime, provider: value["metadata"]["provider"].string) }
    var name: String { value["name"].string.nonEmpty ?? type.title }
    static let memoh = ConversationAgent(value: .null)
    static func enabled(in response: JSONValue) -> [Self] {
        response.items.filter {
            !$0["id"].string.isEmpty && $0["enabled"] != false
                && ["codex", "claude-code", "acp"].contains($0["runtime"].string)
        }.map(Self.init)
    }
    func sessionBody(title: String, settings: JSONValue = .null) -> JSONValue {
        var body: JSONValue = ["title": .string(title), "channel_type": "local", "type": "chat",
                               "session_mode": "chat", "runtime_type": .string(runtime)]
        if !isMemoh { body["bot_agent_id"] = .string(id) }
        if runtime == "acp_agent" {
            let isDefault = settings["default_bot_agent_id"].string == id
            body["runtime_metadata"] = [
                "acp_agent_id": value["metadata"]["provider"],
                "project_path": .string(isDefault ? settings["chat_acp_project_path"].string.nonEmpty ?? "/data" : "/data"),
                "acp_project_mode": .string(isDefault ? settings["chat_acp_project_mode"].string.nonEmpty ?? "project" : "project")
            ]
        }
        return body
    }
}

struct ChatAgentIndicator: View {
    let type: ChatAgentType
    var body: some View {
        HStack(spacing: 4) {
            Image(type.asset).resizable().scaledToFit().frame(width: 14, height: 14).accessibilityHidden(true)
            Text(type.title)
        }.accessibilityElement(children: .combine)
    }
}

struct NewConversationView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var botID: String
    var onCreated: (ChatDestination) -> Void
    @State private var text = ""
    @State private var attachments: [JSONValue] = []
    @State private var agents: [ConversationAgent] = []
    @State private var agentID = ""
    @State private var agentPicker = false
    @State private var loadingAgents = false
    @State private var agentError: String?
    @State private var agentSettings: JSONValue = .null
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
    private var selectedAgent: ConversationAgent { agents.first { $0.id == agentID } ?? .memoh }
    private var location: RunLocation? { locations.first { $0.id == targetID } }
    private var canSend: Bool {
        bot != nil && !busy && !loadingLocations && !loadingAgents && (targetID.isEmpty || locations.contains { $0.id == targetID && $0.available })
            && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 16) {
                            AgentAvatar(name: bot?.title ?? "Agent", avatarURL: bot?.value.avatarURL ?? "", size: 44)
                            VStack(alignment: .leading, spacing: 6) {
                                Eyebrow(text: "TO")
                                Text(bot?.title ?? "Choose an agent".localized).font(.system(.title2, weight: .bold)).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }
                        Divider()
                        runtimeAgentButton
                        if selectedAgent.isMemoh { runLocationButton }
                        else { Label("Memoh workspace".localized, systemImage: "shippingbox").font(.subheadline).foregroundStyle(.secondary) }
                    }.padding(.vertical, 8)
                    if let agentError {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(agentError).font(.caption).foregroundStyle(.secondary)
                            Button("Try again".localized) { Task { await loadAgents() } }.font(.caption)
                        }
                    }
                    if loadingLocations { ProgressView("Finding run locations…".localized).font(.caption) }
                    if let locationError {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(locationError).font(.caption).foregroundStyle(.secondary)
                            Button("Try again".localized) { Task { await loadLocations() } }.font(.caption)
                        }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 16) {
                        TextField(AppLocalization.format("Message %@…", bot?.title ?? "Agent".localized), text: $text, axis: .vertical)
                            .lineLimit(5...12).focused($focused).accessibilityIdentifier("newChatMessage")
                        ForEach(Array(attachments.enumerated()), id: \.offset) { index, item in
                            HStack {
                                Label(item["name"].string, systemImage: "paperclip").lineLimit(1)
                                Spacer()
                                Button {
                                    attachments.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }.accessibilityLabel(AppLocalization.format("Remove %@", item["name"].string))
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
                .navigationTitle("New chat".localized).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel".localized) { dismiss() }.disabled(busy) }
                    ToolbarItem(placement: .topBarTrailing) { AgentPickerMenu(selection: $botID).disabled(busy) }
                }
                .interactiveDismissDisabled(busy).disabled(busy)
                .task(id: botID) {
                    targetID = ""
                    agentID = ""; agents = []; agentSettings = .null
                    async let locations: Void = loadLocations()
                    async let agents: Void = loadAgents()
                    _ = await (locations, agents)
                }
                .fileImporter(isPresented: $filePicker, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
                    do {
                        for url in try result.get() { attachments.append(try ChatAttachment.read(url, existingCount: attachments.count)) }
                    } catch { self.error = error.localizedDescription }
                }
        }
    }
    private var runtimeAgentButton: some View {
        Button { agentPicker = true } label: {
            HStack(spacing: 12) {
                Image(selectedAgent.type.asset).resizable().scaledToFit().frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedAgent.name).font(.subheadline.weight(.semibold))
                    if selectedAgent.name != selectedAgent.type.title {
                        Text(selectedAgent.type.title).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if loadingAgents { ProgressView() }
                else { Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
            }.frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(loadingAgents)
            .accessibilityLabel("Conversation agent".localized).accessibilityValue(selectedAgent.name)
            .accessibilityIdentifier("newChatAgent")
            .popover(isPresented: $agentPicker) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Conversation agent".localized).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(12)
                        ForEach([ConversationAgent.memoh] + agents) { agent in
                            Button {
                                agentID = agent.id; targetID = ""; agentPicker = false
                            } label: {
                                HStack(spacing: 12) {
                                    Image(agent.type.asset).resizable().scaledToFit().frame(width: 26, height: 26)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(agent.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                        if agent.name != agent.type.title { Text(agent.type.title).font(.caption).foregroundStyle(.secondary) }
                                    }
                                    Spacer(minLength: 4)
                                    if agent.id == agentID { Image(systemName: "checkmark").foregroundStyle(.tint) }
                                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("conversationAgent_" + (agent.isMemoh ? "memoh" : agent.id))
                        }
                    }.padding(6)
                }.frame(width: 300).frame(maxHeight: 360).fixedSize(horizontal: false, vertical: true)
                    .presentationCompactAdaptation(.popover)
            }
    }
    private func loadAgents() async {
        guard let api = store.api else { return }
        let requestedBot = botID
        loadingAgents = true; agentError = nil
        do {
            async let response = api.call("/bots/\(requestedBot.pathComponent)/agents")
            async let settings = try? api.call("/bots/\(requestedBot.pathComponent)/settings")
            let (catalog, defaults) = try await (response, settings)
            guard requestedBot == botID, !Task.isCancelled else { return }
            agents = ConversationAgent.enabled(in: catalog)
            agentSettings = defaults ?? .null
            let preferred = agentSettings["default_bot_agent_id"].string
            agentID = agents.contains { $0.id == preferred } ? preferred : ""
        } catch {
            guard requestedBot == botID, !Task.isCancelled else { return }
            agents = []; agentID = ""
            agentError = "Couldn’t load agents. You can still chat with Memoh.".localized
        }
        if requestedBot == botID { loadingAgents = false }
    }
    private var runLocationButton: some View {
        #if targetEnvironment(macCatalyst)
        Menu {
            Picker("Workspace".localized, selection: $targetID) {
                Label("Agent default".localized, systemImage: "arrow.triangle.branch").tag("")
                ForEach(locations) { target in
                    Label(target.name, systemImage: target.symbol).tag(target.id).disabled(!target.available)
                }
            }.pickerStyle(.inline)
        } label: { runLocationLabel }
        .disabled(loadingLocations)
        .accessibilityLabel(AppLocalization.format("Run on, %@", location?.name ?? "Agent default".localized))
        .accessibilityIdentifier("newChatRunLocation")
        #else
        Button { locationPicker = true } label: { runLocationLabel }
        .buttonStyle(.plain).disabled(loadingLocations)
            .accessibilityLabel(AppLocalization.format("Run on, %@", location?.name ?? "Agent default".localized))
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
        #endif
    }
    private var runLocationLabel: some View {
        HStack(spacing: 12) {
            AgentAvatar(name: location?.name ?? "Workspace", size: 32, symbol: location?.symbol ?? "arrow.triangle.branch")
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: "RUN ON")
                Text(location?.name ?? "Agent default".localized).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
            }
            Spacer(minLength: 8)
            if let location { StatusIndicator(text: location.available ? "Online" : "Offline", color: location.available ? .green : .secondary) }
            Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(.secondary)
        }.frame(minHeight: 48).contentShape(Rectangle())
    }
    private func locationOption(id: String, name: String, symbol: String, detail: String, available: Bool) -> some View {
        Button {
            targetID = id
            locationPicker = false
        } label: {
            HStack(spacing: 12) {
                AgentAvatar(name: name, size: 40, symbol: symbol)
                VStack(alignment: .leading, spacing: 4) {
                    Text(id.isEmpty ? name.localized : name).font(.headline).foregroundStyle(.primary)
                    Text(detail.localized).font(.caption).foregroundStyle(.secondary)
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
                Label("Attach".localized, systemImage: "plus")
            }.disabled(attachments.count >= 5)
            Spacer()
            if focused {
                Button {
                    focused = false
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down").frame(width: 44, height: 44)
                }.accessibilityLabel("Hide keyboard".localized)
            }
            Button {
                Task { await create() }
            } label: {
                HStack {
                    if busy { ProgressView() } else { Image(systemName: "arrow.up") }
                    Text((busy ? "Starting…" : "Send").localized)
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
                body: selectedAgent.sessionBody(title: title, settings: agentSettings))
            guard !session["id"].string.isEmpty else { throw ClientError.invalidResponse }
            onCreated(
                ChatDestination(
                    botID: bot.id, sessionID: session["id"].string, title: title, botName: bot.title,
                    firstMessage: NewChatDraft(text: message, attachments: attachments, targetID: selectedAgent.isMemoh ? targetID : "native")))
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
