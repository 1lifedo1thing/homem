import SwiftUI
import UniformTypeIdentifiers

struct ChatDestination: Hashable { var botID: String; var sessionID: String; var title: String; var botName: String; var firstMessage: NewChatDraft? = nil }

struct ConversationsView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.appAccent) private var accent
    @Environment(AppStore.self) private var store
    @State private var sessions: [Record] = []
    @State private var search = ""
    @State private var loading = false
    @State private var error: String?
    @State private var cursor = ""
    @State private var selection: ChatDestination?
    @State private var newChat = false
    @State private var rename: Record?
    @State private var newTitle = ""
    @State private var deletion: Record?
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List {
                if sizeClass == .regular {
                    HStack {
                        Text("Chats".localized).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                        Spacer()
                        composeButton
                    }.listRowSeparator(.hidden).listRowBackground(Color.clear).padding(.vertical, 8)
                }
                if let error = error ?? store.error { ErrorBanner(message: error) { Task { await load() } } }
                Section("Recent".localized) {
                    ForEach(sessions.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { session in
                        let destination = ChatDestination(botID: store.selectedBot?.id ?? "", sessionID: session.id, title: session.title, botName: store.selectedBot?.title ?? "Agent")
                        NavigationLink(value: destination) {
                            HStack(alignment: .top, spacing: 12) {
                                AgentAvatar(name: store.selectedBot?.title ?? "", avatarURL: store.selectedBot?.value.avatarURL ?? "", size: 30)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(session.title).font(.body.weight(.semibold)).lineLimit(2)
                                    HStack(spacing: 6) {
                                        Image(systemName: session.value["type"] == "schedule" ? "clock" : "bubble.left")
                                        Text(session.value["type"].string.fieldLabel.localized.nonEmpty ?? "Chat".localized)
                                        if let date = session.value["updated_at"].string.wireDate {
                                            Spacer(minLength: 4)
                                            Text(date, format: .dateTime.month(.abbreviated).day()).monospacedDigit()
                                        }
                                    }.font(.caption).foregroundStyle(.secondary)

                                }
                            }.padding(.vertical, 8)
                        }
                        .accessibilityIdentifier("conversation_" + session.id)
                        .contextMenu { Button("Rename".localized, systemImage: "pencil") { rename = session; newTitle = session.title }; Button("Delete".localized, systemImage: "trash", role: .destructive) { deletion = session } }
                        .swipeActions(allowsFullSwipe: false) { Button("Delete".localized) { deletion = session }.tint(.red) }
                    }
                    if !cursor.isEmpty { Button("Load more conversations".localized) { Task { await load(more: true) } } }
                    if sessions.isEmpty && !loading && error == nil { Text("Start a new conversation.".localized).foregroundStyle(.secondary).padding(.vertical) }
                }
            }.listStyle(.plain).scrollContentBackground(.hidden).background(Theme.canvas)
                .navigationSplitViewColumnWidth(min: 360, ideal: 400, max: 460)
                .navigationTitle(sizeClass == .regular ? "" : "Chats".localized)
                .searchable(text: $search, prompt: "Find a conversation")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { WorkspacePickerMenu() }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if sizeClass != .regular { composeButton }
                        AgentPickerMenu(selection: Binding(get: { store.selectedBot?.id ?? "" }, set: { store.selectedBotID = $0 }))
                    }
                }
                .navigationDestination(for: ChatDestination.self) { route in ChatScreen(destination: route) }
                .navigationDestination(item: $selection) { route in ChatScreen(destination: route) }
                .refreshable { await store.reload(); await load() }
                .task(id: store.selectedBot?.id) { await load() }
                .overlay { if loading && sessions.isEmpty { ProgressView() } }
                .sheet(isPresented: $newChat, onDismiss: { Task { await load() } }) {
                    NewConversationView(botID: store.selectedBot?.id ?? "") { route in
                        store.selectedBotID = route.botID
                        selection = route
                    }
                }
                .alert("Rename conversation".localized, isPresented: Binding(get: { rename != nil }, set: { if !$0 { rename = nil } })) {
                    TextField("Title".localized, text: $newTitle)
                    Button("Save".localized) { if let record = rename { Task { await update(record, method: "PATCH", body: ["title": .string(newTitle)]) } } }
                    Button("Cancel".localized, role: .cancel) { rename = nil }
                }
                .alert("Delete conversation?".localized, isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }), presenting: deletion) {
                    record in
                    Button("Delete".localized, role: .destructive) { Task { await update(record, method: "DELETE") } }
                    Button("Cancel".localized, role: .cancel) { deletion = nil }
                } message: { record in
                    Text(AppLocalization.format("“%@” will be permanently deleted.", record.title))
                }
        } detail: { EmptyState(title: "No conversations", symbol: "bubble.left.and.bubble.right", detail: "Choose a conversation or start a new one.") }
        .environment(\.expandChatWorkspace, { columnVisibility = .detailOnly })
    }
    private var composeButton: some View {
        Button { newChat = true } label: { Image(systemName: "square.and.pencil").frame(width: 44, height: 44) }
            .buttonStyle(.plain).foregroundStyle(accent)
            .accessibilityLabel("New conversation".localized).accessibilityIdentifier("newConversation").disabled(store.bots.isEmpty)
    }
    func load(more: Bool = false) async {
        guard let bot = store.selectedBot, let api = store.api else { return }
        let botID = bot.id
        loading = true; defer { loading = false }
        do {
            var query = ["types": "chat,discuss,acp_agent,schedule", "limit": "50"]
            if more { query["cursor"] = cursor }
            let value = try await api.call("/bots/\(bot.id.pathComponent)/sessions", query: query)
            guard store.selectedBot?.id == botID else { return }
            let incoming = value.items.map(Record.init)
            sessions = more ? sessions + incoming.filter { r in !sessions.contains { $0.id == r.id } } : incoming
            cursor = value["next_cursor"].string; error = nil
        } catch { self.error = error.localizedDescription }
    }
    func update(_ record: Record, method: String, body: JSONValue? = nil) async {
        guard let botID = record.value["bot_id"].string.nonEmpty ?? store.selectedBot?.id else { return }
        do { _ = try await store.api?.call("/bots/\(botID.pathComponent)/sessions/\(record.id.pathComponent)", method: method, body: body); await load() }
        catch { self.error = error.localizedDescription }
        rename = nil; deletion = nil
    }
}

struct ChatScreen: View {
    @Environment(AppStore.self) private var store
    let destination: ChatDestination
    var body: some View {
        if let api = store.api { ChatContent(model: ChatModel(api: api, botID: destination.botID, sessionID: destination.sessionID), destination: destination).id(destination.sessionID) }
    }
}

private struct IdentifiedChat: Identifiable { let route: ChatDestination; var id: String { route.sessionID } }

struct ChatContent: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appAccent) private var accent
    @Environment(\.expandChatWorkspace) private var expandWorkspace
    @State var model: ChatModel
    let destination: ChatDestination
    var allowsWorkspace = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var attachments: [JSONValue] = []
    @State private var filePicker = false
    @State private var editTurn: JSONValue?
    @State private var editText = ""
    @State private var forked: ChatDestination?
    @FocusState private var composerFocused: Bool
    @State private var voice = VoiceRecorder()
    @State private var sentFirstMessage = false
    @State private var workspacePanes: [WorkspacePane] = []
    @State private var paneArrangement = WorkspaceArrangement.automatic
    private var canvas: some View {
        WorkspaceCanvas(panes: $workspacePanes, arrangement: paneArrangement,
                        api: model.api, botID: destination.botID, botName: destination.botName) {
            transcript
        }
    }
    @ViewBuilder private var presentedCanvas: some View {
        if allowsWorkspace {
            canvas
        .toolbar(workspacePanes.isEmpty ? .visible : .hidden, for: .tabBar)
        .navigationTitle(destination.title).navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Section("Add pane".localized) {
                            ForEach(ChatWorkspaceTool.allCases) { tool in
                                Button(tool.title.localized, systemImage: tool.symbol) {
                                    composerFocused = false
                                    workspacePanes.append(WorkspacePane(tool: tool))
                                    expandWorkspace()
                                }
                            }
                        }
                        if !workspacePanes.isEmpty {
                            Picker("Arrange panes".localized, selection: $paneArrangement) {
                                ForEach(WorkspaceArrangement.allCases) { item in
                                    Text(item.title.localized).tag(item)
                                }
                            }
                            Button("Chat only".localized, systemImage: "bubble.left") { workspacePanes.removeAll() }
                        }
                    } label: { Image(systemName: "rectangle.badge.plus") }
                        .accessibilityLabel("Add pane".localized).accessibilityIdentifier("chatSplitView")
                }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    NavigationLink("Workspace".localized, systemImage: "folder") { WorkspaceView(botID: destination.botID, name: destination.botName) }
                    NavigationLink("Session controls".localized, systemImage: "slider.horizontal.3") { OperationBrowser(prefix: "/bots/{bot_id}/sessions/{session_id}", substitutions: ["bot_id": destination.botID, "session_id": destination.sessionID]) }
                    Button("Refresh history".localized, systemImage: "arrow.clockwise") { Task { await model.loadHistory() } }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
            .navigationDestination(item: $forked) { ChatScreen(destination: $0) }
        } else {
            canvas.sheet(item: Binding(get: { forked.map(IdentifiedChat.init) }, set: { forked = $0?.route })) { item in
                NavigationStack { ChatScreen(destination: item.route) }
            }
        }
    }
    var body: some View {
        presentedCanvas
        .task {
            if !sentFirstMessage, let first = destination.firstMessage {
                sentFirstMessage = true
                model.workspaceTargetID = first.targetID
                model.draft = first.text
                // Queue before connecting, so navigation or reconnects cannot send twice.
                _ = await model.send(attachments: first.attachments)
            }
            await model.start()
        }.onDisappear { model.stop(); voice.cancel() }
        .task(id: model.draft) { do { try await Task.sleep(for: .milliseconds(600)); model.saveDraft() } catch {} }
        .onChange(of: store.modelCatalogRevision) { _, _ in Task { await model.loadModels() } }
        .onChange(of: scenePhase) { _, phase in if phase == .background { model.stop() }; if phase == .active { Task { await model.start() } } }
        .fileImporter(isPresented: $filePicker, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
            do { for url in try result.get() { try attach(url) } } catch { model.error = error.localizedDescription }
        }
        .alert("Edit message".localized, isPresented: Binding(get: { editTurn != nil }, set: { if !$0 { editTurn = nil } })) {
            TextField("Message".localized, text: $editText)
            Button("Send".localized) { if let turn = editTurn { Task { await model.mutateTurn(turn, type: "edit_message", text: editText) } } }
            Button("Cancel".localized, role: .cancel) { editTurn = nil }
        }
    }
    private var transcript: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    HStack { AgentAvatar(name: destination.botName, avatarURL: store.bots.first { $0.id == destination.botID }?.value.avatarURL ?? "", size: 34); VStack(alignment: .leading, spacing: 3) { Text(destination.botName).font(.subheadline.weight(.semibold)); Text(model.connection.localized).font(.caption).foregroundStyle(.secondary) }; Spacer(); if model.api.isDemo { DemoBadge() } }.padding(.bottom, 8)
                    if model.hasMore { Button("Load earlier messages".localized) { Task { await model.loadHistory(older: true) } }.frame(maxWidth: .infinity) }
                    if model.history.isEmpty && !model.loading && !model.active { EmptyState(title: "What’s on your mind?", symbol: "sparkle", detail: "Ask a question, share a file, or start with an idea.").padding(.top, 30) }
                    ForEach(Array(model.visibleTurns.enumerated()), id: \.offset) { _, turn in
                        TurnView(turn: turn, agentName: destination.botName, model: model)
                            .contextMenu {
                                Button("Copy".localized, systemImage: "doc.on.doc") { UIPasteboard.general.string = turn["role"] == "user" ? turn["text"].string : turn["messages"].array.map { $0["content"].string }.joined(separator: "\n") }
                                if turn["role"] == "assistant" { Button("Read aloud".localized, systemImage: "speaker.wave.2") { voice.speak(turn["messages"].array.filter { $0["type"] == "text" }.map { $0["content"].string }.joined(separator: "\n")) } }
                                if !model.api.isDemo && !model.active {
                                    Button("Retry from here".localized, systemImage: "arrow.clockwise") { Task { await model.mutateTurn(turn, type: "retry_message") } }
                                    if turn["role"] == "user" { Button("Edit message".localized, systemImage: "pencil") { editTurn = turn; editText = turn["text"].string } }
                                    if turn["runtime_forkable"].bool { Button("Fork conversation".localized, systemImage: "arrow.triangle.branch") { Task { await fork(turn) } } }
                                }
                            }
                    }
                    if model.active { HStack(spacing: 8) { ProgressView().controlSize(.small); Text(model.runtime.run["status"] == "waiting_decision" ? "Waiting for your response".localized : "Working…".localized).font(.caption).foregroundStyle(.secondary) } }
                    if let error = model.error { ErrorBanner(message: error) { Task { await model.loadHistory() } } }
                    Color.clear.frame(height: 1).id("bottom")
                }.padding(22).frame(maxWidth: 840).frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.visibleTurns.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: workspacePanes.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: composerFocused) { _, focused in if focused { proxy.scrollTo("bottom", anchor: .bottom) } }
            composer
            }
        }
    }
    private var composer: some View {
        VStack(spacing: 10) {
            if voice.recording {
                HStack { Label("Recording · up to 5 minutes".localized, systemImage: "record.circle").font(.caption).foregroundStyle(.red); Spacer(); Button("Cancel".localized) { voice.cancel() }; Button("Attach".localized) { if let url = voice.finish() { do { try attach(url); try? FileManager.default.removeItem(at: url) } catch { model.error = error.localizedDescription } } } }.font(.caption)
            }
            if let error = voice.error { Text(error).font(.caption).foregroundStyle(.red) }
            if !attachments.isEmpty {
                ScrollView(.horizontal) { HStack { ForEach(Array(attachments.enumerated()), id: \.offset) { i, item in Button { attachments.remove(at: i) } label: { Label(item["name"].string, systemImage: "xmark.circle.fill").font(.caption).padding(8).background(.quaternary, in: Capsule()) } } } }
            }
            HStack(alignment: .bottom, spacing: 12) {
                Menu {
                    Button("Attach a file".localized, systemImage: "paperclip") { filePicker = true }
                    Button("Record voice message".localized, systemImage: "mic") { Task { await voice.start() } }.disabled(voice.recording)
                } label: { Image(systemName: "plus").font(.title3).frame(width: 32, height: 42) }.accessibilityLabel("Add attachment".localized)
                TextField(AppLocalization.format("Message %@…", destination.botName), text: $model.draft, axis: .vertical).lineLimit(1...7).padding(.vertical, 10).focused($composerFocused).accessibilityIdentifier("messageComposer")
                if model.active {
                    Menu {
                        Button("Stop response".localized, role: .destructive) { Task { await model.control("abort") } }
                        if !model.draft.isEmpty {
                            Button("Send as follow-up".localized) { Task { await queue("follow-up-queue") } }
                            Button("Steer current response".localized) { Task { await queue("steer-queue") } }
                        }
                    } label: { Image(systemName: "stop.circle.fill").font(.title).frame(width: 42, height: 42) }.accessibilityLabel("Response controls".localized)
                } else {
                    Button { Task { if await model.send(attachments: attachments) { attachments = []; composerFocused = false } } } label: { Image(systemName: "arrow.up").font(.body.weight(.semibold)).foregroundStyle(.white).frame(width: 40, height: 40).background(accent, in: Circle()) }
                        .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty).accessibilityLabel("Send message".localized).accessibilityIdentifier("sendMessage")
                }
            }.padding(.horizontal, 10).padding(.vertical, 5).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24)).overlay(RoundedRectangle(cornerRadius: 24).stroke(.quaternary))
            HStack {
                Menu {
                    Picker("Model".localized, selection: $model.modelID) { Text("Agent default".localized).tag(""); ForEach(model.models) { Text($0.title).tag($0.id) } }
                    Picker("Reasoning".localized, selection: $model.effort) { ForEach(["", "none", "minimal", "low", "medium", "high", "xhigh", "max"], id: \.self) { Text($0.isEmpty ? "Default reasoning".localized : $0.capitalized.localized).tag($0) } }
                } label: { Label(model.models.first { $0.id == model.modelID }?.title ?? "Agent default".localized, systemImage: "sparkle").font(.caption) }
                Spacer()
                if !model.effort.isEmpty { Text(model.effort.capitalized.localized).font(.caption).foregroundStyle(.secondary) }
                if composerFocused {
                    Button { composerFocused = false } label: { Image(systemName: "keyboard.chevron.compact.down").frame(width: 44, height: 32) }
                        .accessibilityLabel("Hide keyboard".localized).accessibilityIdentifier("hideChatKeyboard")
                }
            }.padding(.horizontal, 6)
        }.padding(.horizontal, 16).padding(.vertical, 10).frame(maxWidth: 840).frame(maxWidth: .infinity).background(.bar)
    }
    func attach(_ url: URL) throws {
        attachments.append(try ChatAttachment.read(url, existingCount: attachments.count))
    }

    func queue(_ kind: String) async {
        do { _ = try await model.api.call(model.sessionPath + "/" + kind, method: "POST", body: ["text": .string(model.draft), "invocation_id": .string(UUID().uuidString.lowercased())]); model.draft = "" } catch { model.error = error.localizedDescription }
    }
    func fork(_ turn: JSONValue) async {
        do { let value = try await model.api.call(model.sessionPath + "/fork", method: "POST", body: ["turn_id": turn["turn_id"]]); forked = .init(botID: destination.botID, sessionID: value["id"].string, title: value["title"].string, botName: destination.botName) } catch { model.error = error.localizedDescription }
    }
}

struct TurnView: View {
    @Environment(\.appAccent) private var accent
    let turn: JSONValue
    let agentName: String
    let model: ChatModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(turn["role"] == "user" ? "You".localized : turn["role"] == "system" ? "Workspace".localized : agentName).font(.caption2.weight(.bold)).tracking(1.5).foregroundStyle(.secondary)
            if turn["role"] == "user" { MarkdownContent(text: turn["text"].string).frame(maxWidth: .infinity, alignment: .leading).padding(16).background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 18)) }
            ForEach(Array(turn["attachments"].array.enumerated()), id: \.offset) { _, item in AttachmentView(item: item, model: model) }
            MessageSequence(messages: turn["messages"].array, model: model)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MessageBlockView: View {
    let message: JSONValue
    let model: ChatModel
    var body: some View {
        switch message["type"].string {
        case "text": MarkdownContent(text: message["content"].string)
        case "reasoning": DisclosureGroup { MarkdownContent(text: message["content"].string).foregroundStyle(.secondary) } label: { Label("Thinking".localized, systemImage: "sparkles").font(.subheadline).foregroundStyle(.secondary) }
        case "tool": ToolActivityView(messages: [message], model: model)
        case "attachments": ForEach(Array(message["attachments"].array.enumerated()), id: \.offset) { _, item in AttachmentView(item: item, model: model) }
        case "error": ErrorBanner(message: message["content"].string)
        default: if !message["content"].string.isEmpty { Text(message["content"].string).font(.callout).foregroundStyle(.secondary) }
        }
    }
}

struct MarkdownContent: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(MarkdownSegment.parse(text).enumerated()), id: \.offset) { _, part in
                if part.isCode {
                    CodeBlockView(code: part.text, language: part.language)
                } else {
                    Text(inlineMarkdown(part.text.trimmingCharacters(in: .newlines))).textSelection(.enabled).lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
    private func inlineMarkdown(_ text: String) -> AttributedString {
        var result = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        for run in result.runs where run.inlinePresentationIntent?.contains(.code) == true {
            result[run.range].font = .system(.body, design: .monospaced)
            result[run.range].backgroundColor = Color(.tertiarySystemFill)
        }
        return result
    }
}

struct ApprovalView: View {
    let approval: JSONValue
    let model: ChatModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Permission requested".localized, systemImage: "hand.raised").font(.subheadline.weight(.semibold))
            if approval["can_approve"].bool {
                if approval["options"].array.isEmpty {
                    HStack { Button("Allow once".localized) { respond("approve") }.buttonStyle(.borderedProminent); Button("Decline".localized, role: .destructive) { respond("reject") }.buttonStyle(.bordered) }
                } else { ForEach(approval["options"].array, id: \.self) { option in Button(option["name"].string.nonEmpty ?? option["id"].string) { respond(option["kind"].string.hasPrefix("reject") ? "reject" : "approve", option: option["id"].string) }.buttonStyle(.bordered) } }
            } else { Text("A workspace manager must approve this action.").font(.caption).foregroundStyle(.secondary) }
        }
    }
    func respond(_ decision: String, option: String = "") { Task { await model.control("tool_approval_response", extra: ["decision_id": approval["approval_id"], "decision": .string(decision), "option_id": .string(option)]) } }
}

struct UserInputView: View {
    @Environment(\.appAccent) private var accent
    let input: JSONValue
    let model: ChatModel
    @State private var drafts: [String: UserInputDraft] = [:]
    @State private var submitting = false
    @FocusState private var focusedQuestion: String?
    private var questions: [JSONValue] { input["questions"].array }
    private var answers: [JSONValue]? { UserInputDraft.answers(for: questions, drafts: drafts) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(questions, id: \.self) { question in
                let id = UserInputDraft.questionID(question)
                let draft = drafts[id, default: UserInputDraft()]
                VStack(alignment: .leading, spacing: 10) {
                    Text(question.text("text", "question", "title", "prompt"))
                        .font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    if question["kind"] != "text" {
                        VStack(spacing: 6) {
                            ForEach(question["options"].array, id: \.self) { option in
                                choice(option.text("label", "title", "id"), detail: option["description"].string,
                                       selected: draft.optionIDs.contains(option["id"].string), multiple: question["kind"] == "multi_select") {
                                    drafts[id, default: UserInputDraft()].select(option["id"].string, question: question)
                                    if !drafts[id, default: UserInputDraft()].customSelected { focusedQuestion = nil }
                                }.accessibilityIdentifier("answerOption_" + id + "_" + option["id"].string)
                            }
                            if question["allow_custom"].bool {
                                choice("Write my own answer".localized, selected: draft.customSelected, multiple: question["kind"] == "multi_select") {
                                    drafts[id, default: UserInputDraft()].selectCustom(question: question)
                                    focusedQuestion = drafts[id, default: UserInputDraft()].customSelected ? id : nil
                                }.accessibilityIdentifier("customAnswer_" + id)
                            }
                        }
                    }
                    if question["kind"] == "text" || draft.customSelected {
                        TextField(question["placeholder"].string.nonEmpty ?? "Your answer".localized,
                                  text: Binding(get: { drafts[id, default: UserInputDraft()].text }, set: { drafts[id, default: UserInputDraft()].text = $0 }), axis: .vertical)
                            .font(.body).lineLimit(2...6).focused($focusedQuestion, equals: id)
                            .padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(accent.opacity(0.3), lineWidth: 1))
                            .accessibilityIdentifier("answerText_" + id)
                    }
                }
            }
            Button {
                guard let answers, !submitting else { return }
                focusedQuestion = nil
                submitting = true
                Task {
                    defer { submitting = false }
                    await model.control("user_input_response", extra: ["decision_id": input["user_input_id"], "answers": .array(answers)])
                }
            } label: {
                HStack(spacing: 8) {
                    if submitting { ProgressView().tint(.white) }
                    Text("Send answers".localized).fontWeight(.semibold)
                }.frame(maxWidth: .infinity).padding(.vertical, 4)
            }.buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(!input["can_respond"].bool || answers == nil || submitting)
                .accessibilityIdentifier("sendUserInputAnswers")
        }.padding(.vertical, 8)
            .disabled(!input["can_respond"].bool || submitting)
            .onChange(of: input["user_input_id"]) { _, _ in drafts = [:]; focusedQuestion = nil }
    }
    private func choice(_ title: String, detail: String = "", selected: Bool, multiple: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: multiple ? (selected ? "checkmark.square.fill" : "square") : (selected ? "largecircle.fill.circle" : "circle"))
                    .font(.system(size: 20)).foregroundStyle(selected ? accent : .secondary).padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }.fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }.padding(12).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background(selected ? accent.opacity(0.08) : Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? accent.opacity(0.45) : .clear, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityValue(selected ? "Selected".localized : "")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct AttachmentView: View {
    let item: JSONValue
    let model: ChatModel
    @State private var downloaded: URL?
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading) {
            if let downloaded { ShareLink(item: downloaded) { Label(item["name"].string.nonEmpty ?? "Attachment", systemImage: "square.and.arrow.up") } }
            else { Button { Task { await download() } } label: { Label(item["name"].string.nonEmpty ?? "Attachment", systemImage: "paperclip") } }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }.font(.subheadline)
    }
    func download() async {
        do {
            let data: Data
            if let encoded = item["base64"].string.split(separator: ",", maxSplits: 1).last, let d = Data(base64Encoded: String(encoded)) { data = d }
            else if !item["path"].string.isEmpty { data = try await model.api.perform(model.api.request(model.prefix + "/container/fs/download", query: ["path": item["path"].string])) }
            else if let url = URL(string: item["url"].string), ["https", "http"].contains(url.scheme ?? "") { let (d, response) = try await URLSession.shared.data(from: url); guard let h = response as? HTTPURLResponse, (200..<300).contains(h.statusCode) else { throw ClientError.invalidResponse }; data = d }
            else { throw ClientError.message("This attachment has no downloadable content.".localized) }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent((item["name"].string as NSString).lastPathComponent.nonEmpty ?? "attachment")
            try data.write(to: url, options: .atomic); downloaded = url
        } catch { self.error = error.localizedDescription }
    }
}
