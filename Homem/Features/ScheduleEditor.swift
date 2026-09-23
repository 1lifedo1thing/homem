import SwiftUI

/// Only recognized cron shapes become visual controls. Everything else stays lossless.
struct ScheduleRepeat: Equatable {
    enum Frequency: String, CaseIterable {
        case minutes = "Every few minutes", hourly = "Hourly", daily = "Daily", weekly = "Weekly", monthly = "Monthly", custom = "Custom schedule"
    }
    var frequency: Frequency = .daily
    var minute = 0
    var hour = 9
    var interval = 15
    var monthDay = 1
    var weekdays: Set<Int> = [1, 2, 3, 4, 5]
    var custom = ""

    init(pattern: String = "0 9 * * *") {
        custom = pattern
        let parts = pattern.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count == 5, parts[3] == "*" else { frequency = .custom; return }
        if parts[0].hasPrefix("*/"), let count = Int(parts[0].dropFirst(2)), (1...59).contains(count), Array(parts.dropFirst()) == ["*", "*", "*", "*"] {
            frequency = .minutes; interval = count; return
        }
        guard let m = Int(parts[0]), (0...59).contains(m) else { frequency = .custom; return }
        minute = m
        if parts[1] == "*", parts[2] == "*", parts[4] == "*" { frequency = .hourly; return }
        guard let h = Int(parts[1]), (0...23).contains(h) else { frequency = .custom; return }
        hour = h
        if parts[2] == "*", parts[4] == "*" { frequency = .daily; return }
        if let day = Int(parts[2]), (1...31).contains(day), parts[4] == "*" { frequency = .monthly; monthDay = day; return }
        let days = parts[4].split(separator: ",").compactMap { Int($0) }
        if parts[2] == "*", !days.isEmpty, days.count == parts[4].split(separator: ",").count, days.allSatisfy({ (0...6).contains($0) }) {
            frequency = .weekly; weekdays = Set(days); return
        }
        frequency = .custom
    }
    var pattern: String {
        switch frequency {
        case .minutes: return "*/\(interval) * * * *"
        case .hourly: return "\(minute) * * * *"
        case .daily: return "\(minute) \(hour) * * *"
        case .weekly: return "\(minute) \(hour) * * \(weekdays.sorted().map(String.init).joined(separator: ","))"
        case .monthly: return "\(minute) \(hour) \(monthDay) * *"
        case .custom: return custom
        }
    }
    var time: Date {
        get { Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: hour, minute: minute)) ?? .now }
        set { hour = Calendar.current.component(.hour, from: newValue); minute = Calendar.current.component(.minute, from: newValue) }
    }
    var summary: String {
        let time = time.formatted(date: .omitted, time: .shortened)
        switch frequency {
        case .minutes: return AppLocalization.format("Every %lld minutes", interval)
        case .hourly: return AppLocalization.format("Hourly, at minute %lld", minute)
        case .daily: return AppLocalization.format("Daily at %@", time)
        case .weekly:
            let names = weekdays.sorted().map { Calendar.current.shortWeekdaySymbols[$0] }.joined(separator: ", ")
            return AppLocalization.format("%@ at %@", names, time)
        case .monthly: return AppLocalization.format("Day %lld of each month at %@", monthDay, time)
        case .custom: return "Custom schedule".localized
        }
    }
}

struct ScheduleDraft {
    static let executionKeys = ["run_target", "target_session_id", "runtime_type", "bot_agent_id", "acp_agent_id", "model_id", "acp_model_id", "reasoning_effort", "workdir_id"]
    var name: String
    var task: String
    var notes: String
    var enabled: Bool
    var repeatRule: ScheduleRepeat
    var limited: Bool
    var limit: Int
    var execution: JSONValue
    let originalExecution: JSONValue
    let originalLimit: JSONValue
    init(_ value: JSONValue) {
        name = value["name"].string; task = value["command"].string; notes = value["description"].string
        enabled = value["enabled"] != false
        repeatRule = ScheduleRepeat(pattern: value["pattern"].string.nonEmpty ?? "0 9 * * *")
        originalLimit = value["max_calls"]
        limited = !originalLimit.isNull
        limit = limited ? Int(originalLimit.number) : 10
        let source = value["execution"].isNull ? value : value["execution"]
        execution = .object(source.object.filter { Self.executionKeys.contains($0.key) })
        if execution["run_target"].string.isEmpty { execution["run_target"] = "new_session" }
        originalExecution = execution
    }
    mutating func changeTarget(_ target: String) {
        execution = ["run_target": .string(target)]
    }
    mutating func selectSession(_ id: String) {
        guard execution["target_session_id"].string != id else { return }
        for key in ["model_id", "acp_model_id", "reasoning_effort"] { execution[key] = .null }
        execution["target_session_id"] = .string(id)
    }
    mutating func selectAgent(_ id: String) {
        // The server resolves runtime/provider from the persisted agent ID.
        for key in ["runtime_type", "acp_agent_id", "model_id", "acp_model_id", "reasoning_effort"] { execution[key] = .null }
        execution["bot_agent_id"] = .string(id)
    }
    func body(editing: Bool) -> JSONValue {
        var result: JSONValue = ["name": .string(name.trimmingCharacters(in: .whitespacesAndNewlines)), "command": .string(task), "description": .string(notes), "enabled": .bool(enabled), "pattern": .string(repeatRule.pattern)]
        let max: JSONValue = limited ? .number(Double(limit)) : .null
        // null explicitly clears a previous limit; omitting it would keep the old one.
        if !editing || max != originalLimit { result["max_calls"] = max }
        let config = JSONValue.object(execution.object.filter { !$0.value.isNull })
        if editing {
            if execution != originalExecution { result["execution"] = config }
        } else {
            for (key, value) in config.object { result[key] = value }
        }
        return result
    }
    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !repeatRule.pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (repeatRule.frequency != .weekly || !repeatRule.weekdays.isEmpty) &&
        (!limited || (1...Int(Int32.max)).contains(limit)) && (execution["run_target"] != "existing_session" || !execution["target_session_id"].string.isEmpty)
    }
}

struct ScheduleEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appAccent) private var accent
    let path: String
    let operation: APIOperation
    let onSaved: ((JSONValue) -> Void)?
    @State private var draft: ScheduleDraft
    @State private var busy = false
    @State private var error: String?
    @State private var targetIsExternal: Bool? = nil
    private var editing: Bool { operation.method != "POST" }
    private var botPath: String { "/" + path.split(separator: "/").prefix(2).joined(separator: "/") }
    private var isExternal: Bool {
        if draft.execution["run_target"] == "existing_session" { return targetIsExternal ?? true }
        return !draft.execution["bot_agent_id"].string.isEmpty || ["acp_agent", "codex", "claude-code"].contains(draft.execution["runtime_type"].string)
    }
    init(path: String, operation: APIOperation, initial: JSONValue, onSaved: ((JSONValue) -> Void)?) {
        self.path = path; self.operation = operation; self.onSaved = onSaved
        _draft = State(initialValue: ScheduleDraft(initial))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name".localized, text: $draft.name)
                    Toggle("Enabled".localized, isOn: $draft.enabled)
                }
                Section("Task".localized) {
                    TextField("What should the agent do?".localized, text: $draft.task, axis: .vertical).lineLimit(4...10)
                }
                Section {
                    Picker("Repeat".localized, selection: $draft.repeatRule.frequency) {
                        ForEach(ScheduleRepeat.Frequency.allCases, id: \.self) { Text($0.rawValue.localized).tag($0) }
                    }
                    repeatControls
                } header: { Text("When".localized) } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if draft.repeatRule.frequency != .custom { Text(draft.repeatRule.summary) }
                        Text("Times follow the agent’s time zone.".localized)
                        if draft.repeatRule.frequency == .monthly && draft.repeatRule.monthDay > 28 { Text("Months without this day are skipped.".localized) }
                    }
                }
                Section("Conversation".localized) {
                    Picker("Run in".localized, selection: Binding(get: { draft.execution["run_target"].string }, set: { draft.changeTarget($0) })) {
                        Text("New conversation each time".localized).tag("new_session")
                        Text("Existing conversation".localized).tag("existing_session")
                    }
                    if draft.execution["run_target"] == "existing_session" {
                        ResourceReferencePicker(title: "Conversation", source: botPath + "/sessions", required: true, value: Binding(get: { draft.execution["target_session_id"] }, set: { draft.selectSession($0.string); targetIsExternal = nil }), sessionModes: ["chat", "schedule"], onSelection: { row in targetIsExternal = row.map { ChatAgentType.session($0.value) != .memoh } })
                    } else {
                        ResourceReferencePicker(title: "Agent runtime", source: botPath + "/agents", required: false, value: Binding(get: { draft.execution["bot_agent_id"] }, set: { draft.selectAgent($0.string) }), defaultTitle: draft.execution["bot_agent_id"].string.isEmpty && isExternal ? ChatAgentType.resolve(runtime: draft.execution["runtime_type"].string, provider: draft.execution["acp_agent_id"].string).title : "Memoh")
                        if draft.execution["bot_agent_id"].string.isEmpty && isExternal {
                            LabeledContent("Current selection".localized, value: ChatAgentType.resolve(runtime: draft.execution["runtime_type"].string, provider: draft.execution["acp_agent_id"].string).title)
                            Button("Use Memoh".localized) { draft.selectAgent("") }
                        }
                        ResourceReferencePicker(title: "Working directory", source: botPath + "/workdirs", required: false, value: executionBinding("workdir_id"))
                    }
                }
                Section {
                    Toggle("Limit runs".localized, isOn: $draft.limited)
                    if draft.limited {
                        Stepper(value: $draft.limit, in: 1...Int(Int32.max)) {
                            LabeledContent("Total runs".localized) {
                                TextField("10", value: $draft.limit, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(minWidth: 45)
                            }
                        }
                    }
                } footer: { Text("Turn off the limit to repeat until paused.".localized) }
                Section {
                    DisclosureGroup("Advanced options".localized) {
                        TextField("Notes".localized, text: $draft.notes, axis: .vertical).lineLimit(2...5)
                        // Existing external overrides survive edits, and can be cleared without a raw payload.
                        if !isExternal {
                            ResourceReferencePicker(title: "Model", source: "/models", required: false, value: executionBinding("model_id"), chatModelsOnly: true)
                            Picker("Reasoning effort".localized, selection: Binding(get: { draft.execution["reasoning_effort"].string }, set: { draft.execution["reasoning_effort"] = .string($0) })) {
                                Text("Default".localized).tag("")
                                ForEach(["disable", "minimal", "low", "medium", "high", "xhigh", "max"], id: \.self) { Text($0.fieldLabel.localized).tag($0) }
                                let current = draft.execution["reasoning_effort"].string
                                if !current.isEmpty && !["disable", "minimal", "low", "medium", "high", "xhigh", "max"].contains(current) { Text(current).tag(current) }
                            }
                        } else if !draft.execution["acp_model_id"].string.isEmpty {
                            LabeledContent("Model".localized, value: draft.execution["acp_model_id"].string)
                        }
                        if !draft.execution["acp_model_id"].string.isEmpty || !draft.execution["reasoning_effort"].string.isEmpty {
                            Button("Use default model and reasoning".localized) {
                                for key in ["model_id", "acp_model_id", "reasoning_effort"] { draft.execution[key] = .null }
                            }
                        }
                    }
                }
                if let error { Section { ErrorBanner(message: error) } }
            }
            .navigationTitle((editing ? "Edit schedule" : "New schedule").localized).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel".localized) { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: { if busy { ProgressView() } else { Text("Save".localized).bold() } }.disabled(busy || !draft.canSave)
                }
            }
            .disabled(busy)
            .onChange(of: draft.repeatRule.frequency) { old, new in
                if new == .custom {
                    var previous = draft.repeatRule; previous.frequency = old
                    draft.repeatRule.custom = previous.pattern
                }
            }
        }.interactiveDismissDisabled(busy)
    }
    @ViewBuilder private var repeatControls: some View {
        switch draft.repeatRule.frequency {
        case .minutes:
            Stepper(AppLocalization.format("Every %lld minutes", draft.repeatRule.interval), value: $draft.repeatRule.interval, in: 1...59)
        case .hourly:
            Stepper(AppLocalization.format("Minute %lld", draft.repeatRule.minute), value: $draft.repeatRule.minute, in: 0...59)
        case .daily, .weekly, .monthly:
            DatePicker("Time".localized, selection: $draft.repeatRule.time, displayedComponents: .hourAndMinute)
            if draft.repeatRule.frequency == .weekly {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) { weekdayButtons }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 52))], spacing: 6) { weekdayButtons }
                }.padding(.vertical, 4)
            }
            if draft.repeatRule.frequency == .monthly { Stepper(AppLocalization.format("Day %lld", draft.repeatRule.monthDay), value: $draft.repeatRule.monthDay, in: 1...31) }
        case .custom:
            TextField("Cron expression".localized, text: $draft.repeatRule.custom).font(.body.monospaced()).textInputAutocapitalization(.never).autocorrectionDisabled()
        }
    }
    private var weekdayButtons: some View {
        ForEach(0..<7, id: \.self) { offset in
            let day = (Calendar.current.firstWeekday - 1 + offset) % 7
            let selected = draft.repeatRule.weekdays.contains(day)
            Button {
                if selected { draft.repeatRule.weekdays.remove(day) } else { draft.repeatRule.weekdays.insert(day) }
            } label: {
                Text(Calendar.current.shortWeekdaySymbols[day]).font(.caption.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                    .background(selected ? accent.opacity(0.16) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(.plain).foregroundStyle(selected ? accent : .primary)
                .accessibilityLabel(Calendar.current.weekdaySymbols[day]).accessibilityAddTraits(selected ? .isSelected : [])
        }
    }
    private func executionBinding(_ key: String) -> Binding<JSONValue> { Binding(get: { draft.execution[key] }, set: { draft.execution[key] = $0 }) }
    private func save() async {
        guard let api = store.api else { return }
        busy = true; error = nil; defer { busy = false }
        do { let result = try await api.call(path, method: operation.method, body: draft.body(editing: editing)); onSaved?(result); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

struct ScheduleDetails: View {
    let value: JSONValue
    var body: some View {
        Section {
            LabeledContent("Repeat".localized, value: ScheduleRepeat(pattern: value["pattern"].string).summary)
            LabeledContent("Status".localized, value: (value["enabled"].bool ? "Enabled" : "Paused").localized)
            if !value["max_calls"].isNull { LabeledContent("Total runs".localized, value: value["max_calls"].scalar) }
            if !value["current_calls"].isNull { LabeledContent("Completed runs".localized, value: value["current_calls"].scalar) }
        }
        Section("Task".localized) { Text(value["command"].string).textSelection(.enabled) }
        if !value["description"].string.isEmpty { Section("Notes".localized) { Text(value["description"].string) } }
        if ScheduleRepeat(pattern: value["pattern"].string).frequency == .custom {
            Section("Custom schedule".localized) { Text(value["pattern"].string).font(.body.monospaced()).textSelection(.enabled) }
        }
    }
}
