import Foundation

struct APIOperation: Identifiable, Hashable {
    var path: String
    var method: String
    var definition: JSONValue
    var id: String { method + " " + path }
    var title: String { definition["summary"].string.nonEmpty ?? path }
    var parameters: [JSONValue] { definition["parameters"].array }
    var bodySchema: JSONValue { parameters.first { $0["in"].string == "body" }?["schema"] ?? .null }
}

struct SchemaCatalog {
    static let shared = SchemaCatalog()
    let spec: JSONValue
    let operations: [APIOperation]
    init() {
        if let url = Bundle.main.url(forResource: "memoh-openapi", withExtension: "json"), let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(JSONValue.self, from: data) { spec = value } else { spec = [:] }
        operations = spec["paths"].object.flatMap { path, value in value.object.map { APIOperation(path: path, method: $0.key.uppercased(), definition: $0.value) } }.sorted { $0.id < $1.id }
    }
    func resolve(_ value: JSONValue) -> JSONValue {
        if let ref = value["$ref"].string.split(separator: "/").last { return spec["definitions"][String(ref)] }
        return value
    }
    func operation(_ path: String, _ method: String) -> APIOperation? { operations.first { $0.path == path && $0.method == method } }
    func schema(_ path: String, _ method: String) -> JSONValue { resolve(operation(path, method)?.bodySchema ?? .null) }
    func fields(_ schema: JSONValue) -> [String] {
        let resolved = resolve(schema)
        let required = Set(resolved["required"].array.map(\.string))
        let priority = ["name", "display_name", "title", "type", "provider_id", "model_id", "base_url", "api_key", "enabled", "pattern", "command", "message"]
        return resolved["properties"].object.keys.sorted {
            let a = priority.firstIndex(of: $0) ?? (required.contains($0) ? 100 : 200)
            let b = priority.firstIndex(of: $1) ?? (required.contains($1) ? 100 : 200)
            return a == b ? $0 < $1 : a < b
        }
    }
    func validate(_ value: JSONValue, schema raw: JSONValue, name: String = "Configuration") throws {
        let schema = resolve(raw)
        if value.isNull { return }
        let type = schema["type"].string
        switch (type, value) {
        case ("boolean", .bool), ("string", .string), ("number", .number), ("integer", .number), ("object", .object), ("array", .array), ("", _): break
        default: throw ClientError.message(AppLocalization.format("Check the value for %@.", name.fieldLabel.localized))
        }
        if type == "integer", value.number != value.number.rounded() { throw ClientError.message(AppLocalization.format("%@ must be a whole number.", name.fieldLabel.localized)) }
        if let minimum = schema.object["minimum"], value.number < minimum.number { throw ClientError.message(AppLocalization.format("%@ must be at least %@.", name.fieldLabel.localized, minimum.scalar)) }
        if let maximum = schema.object["maximum"], value.number > maximum.number { throw ClientError.message(AppLocalization.format("%@ must be at most %@.", name.fieldLabel.localized, maximum.scalar)) }
        for key in schema["required"].array.map(\.string) where value[key].isNull || value[key] == .string("") { throw ClientError.message(AppLocalization.format("%@ is required.", key.fieldLabel.localized)) }
        for (key, child) in value.object { if !schema["properties"][key].isNull { try validate(child, schema: schema["properties"][key], name: key) } }
        if type == "array" { for child in value.array { try validate(child, schema: schema["items"], name: name) } }
    }
}

/// Settings references keep server IDs on the wire and names in the UI.
enum AgentSettingsFields {
    static let groups: [(String, [String])] = [
        ("Conversation", ["chat_model_id", "default_bot_agent_id", "reasoning_effort", "language", "timezone"]),
        ("Providers", ["search_provider_id", "fetch_provider_id", "memory_provider_id"]),
        ("Media", ["image_model_id", "tts_model_id", "transcription_model_id", "video_model_id"]),
        ("Behavior", ["display_enabled", "show_tool_calls_in_im", "persist_full_tool_results", "tool_approval_config"]),
        ("Context", ["compaction_enabled", "compaction_model_id", "compaction_threshold", "compaction_target_percent", "discuss_probe_model_id"]),
        ("Advanced options", ["chat_runtime", "chat_acp_agent_id", "chat_acp_project_mode", "chat_acp_project_path", "command_ui_language", "acl_default_effect", "overlay_enabled", "overlay_provider", "overlay_config"])
    ]
    static let labels: [String: String] = [
        "chat_model_id": "Chat model", "default_bot_agent_id": "Default agent", "reasoning_effort": "Reasoning effort",
        "search_provider_id": "Search provider", "fetch_provider_id": "Web fetch provider", "memory_provider_id": "Memory provider",
        "image_model_id": "Image model", "tts_model_id": "Speech model", "transcription_model_id": "Transcription model", "video_model_id": "Video model",
        "display_enabled": "Desktop enabled", "show_tool_calls_in_im": "Show tool calls in messages", "persist_full_tool_results": "Keep full tool results",
        "tool_approval_config": "Tool approval", "compaction_enabled": "Summarize long conversations", "compaction_model_id": "Summary model",
        "compaction_threshold": "Context threshold", "compaction_target_percent": "Target context (%)", "discuss_probe_model_id": "Discussion model",
        "chat_runtime": "Run conversations with", "chat_acp_agent_id": "Agent profile", "chat_acp_project_mode": "Project mode", "chat_acp_project_path": "Project folder",
        "command_ui_language": "Command language", "acl_default_effect": "Default access", "overlay_enabled": "Private network enabled",
        "overlay_provider": "Network provider", "overlay_config": "Network settings"
    ]
    static func label(_ key: String) -> String { labels[key] ?? key.fieldLabel }
    static func source(_ key: String, botID: String) -> String? {
        switch key {
        case "search_provider_id": return "/search-providers"
        case "fetch_provider_id": return "/fetch-providers"
        case "memory_provider_id": return "/memory-providers"
        case "tts_model_id": return "/speech-models"
        case "transcription_model_id": return "/transcription-models"
        case "video_model_id": return "/video-models"
        case "default_bot_agent_id": return "/bots/\(botID.pathComponent)/agents"
        case "chat_acp_agent_id": return "/acp-profiles"
        case "chat_model_id", "image_model_id", "compaction_model_id", "discuss_probe_model_id": return "/models"
        default: return nil
        }
    }
    static func providerSource(_ source: String) -> String? {
        switch source {
        case "/models": return "/providers"
        case "/speech-models": return "/speech-providers"
        case "/transcription-models": return "/transcription-providers"
        case "/video-models": return "/video-providers"
        default: return nil
        }
    }
    static func options(_ records: [JSONValue], key: String, selected: String) -> [Record] {
        records.filter { row in
            guard !row["id"].string.isEmpty else { return false }
            if row["id"].string == selected { return true }
            if row["enable"] == false || row["enabled"] == false { return false }
            if key == "image_model_id" { return row["config"]["compatibilities"].array.contains("image-output") || row["type"] == "image" }
            if ["chat_model_id", "compaction_model_id", "discuss_probe_model_id"].contains(key) { return row["type"].string.isEmpty || row["type"] == "chat" }
            return true
        }.map(Record.init).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    static func changes(from original: JSONValue, to draft: JSONValue, allowed: Set<String>) -> JSONValue {
        // Empty strings deliberately survive: references use "" to clear, omission to keep.
        .object(draft.object.filter { allowed.contains($0.key) && !$0.value.isNull && $0.value != original[$0.key] })
    }
}
