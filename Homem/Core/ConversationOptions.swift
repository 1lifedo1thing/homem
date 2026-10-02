import Foundation
import UniformTypeIdentifiers

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
