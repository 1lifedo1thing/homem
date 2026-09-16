import Foundation

@MainActor final class DemoServer {
    var collections: [String: [JSONValue]] = [:]
    var documents: [String: JSONValue] = [:]
    init() {
        collections["/bots"] = [
            ["id": "atlas", "name": "atlas", "display_name": "Atlas", "is_active": true, "status": "ready", "metadata": ["description": "Research, ideas, and a little perspective."], "current_user_permissions": ["chat", "manage"]],
            ["id": "mika", "name": "mika", "display_name": "Mika", "is_active": true, "status": "ready", "metadata": ["description": "Your thoughtful coding companion."], "current_user_permissions": ["chat", "manage"]],
            ["id": "sage", "name": "sage", "display_name": "Sage", "is_active": false, "status": "stopped", "metadata": ["description": "A calmer way to plan your day."], "current_user_permissions": ["chat", "manage"]]
        ]
        collections["/bots/atlas/sessions"] = [
            ["id": "welcome", "bot_id": "atlas", "title": "A place for your next idea", "type": "chat", "updated_at": "2026-09-16T14:00:00Z"],
            ["id": "research", "bot_id": "atlas", "title": "A weekend in Kyoto", "type": "chat", "updated_at": "2026-09-15T12:00:00Z"]
        ]
        collections["/bots/mika/sessions"] = [["id": "code", "bot_id": "mika", "title": "Making something useful", "type": "chat", "updated_at": "2026-09-16T13:00:00Z"]]
        collections["/bots/sage/sessions"] = []
        collections["messages/welcome"] = [
            ["turn_id": "one", "role": "user", "text": "What can we do here?", "timestamp": "2026-09-16T14:00:00Z"],
            ["turn_id": "two", "role": "assistant", "messages": [["id": 1, "type": "text", "content": "Welcome home. I’m **Atlas**, your research companion.\n\nWe can explore an idea, work through a question, or turn a little curiosity into something useful.\n\nThis is a **demo workspace**. Connect your Memoh server to talk with your own agents, browse their files, and pick up where you left off."]], "timestamp": "2026-09-16T14:00:01Z"]
        ]
        for bot in ["atlas", "mika", "sage"] {
            let base = "/bots/\(bot)"
            collections[base + "/memory"] = [["id": "memory-1", "memory": "Prefers thoughtful answers with concrete examples.", "created_at": "2026-09-16T09:00:00Z"], ["id": "memory-2", "memory": "Interested in native apps, design, and good coffee.", "created_at": "2026-09-15T09:00:00Z"]]
            collections[base + "/schedule"] = bot == "atlas" ? [["id": "morning", "name": "Morning perspective", "description": "A small briefing to start the day.", "command": "Summarize the most interesting technology news today.", "pattern": "0 9 * * *", "enabled": true, "run_target": "new_session", "current_calls": 12]] : []
            collections[base + "/mcp"] = [["id": "filesystem", "name": "Workspace tools", "type": "stdio", "enabled": true, "config": ["command": "workspace-tools"]]]
            collections[base + "/agents"] = [["id": "native", "name": "Memoh", "type": "native", "enabled": true]]
            collections[base + "/container/skills"] = [["name": "research", "description": "Turn open questions into useful findings."]]
            for suffix in ["apps", "dependencies", "connectors", "workdirs", "container/snapshots", "email-bindings", "email-outbox", "user-access", "schedule/logs", "compaction/logs", "hooks/events"] { collections[base + "/" + suffix] = [] }
            documents[base + "/settings"] = ["chat_model_id": "demo-model", "language": "en", "max_context_tokens": 32000]
            documents[base + "/container"] = ["status": "running", "runtime": "docker", "image": "memoh/workspace", "id": .string("workspace-\(bot)")]
            documents[base + "/token-usage"] = ["total_tokens": 28450, "input_tokens": 21340, "output_tokens": 7110]
            documents[base + "/checks"] = ["state": "ok", "issues": []]
            documents[base + "/memory/graph"] = ["nodes": [["id": "design", "label": "Design", "count": 4], ["id": "native", "label": "Native apps", "count": 3], ["id": "coffee", "label": "Coffee", "count": 2], ["id": "examples", "label": "Clear examples", "count": 6]], "edges": [["source": "design", "target": "native", "weight": 2], ["source": "native", "target": "examples", "weight": 3], ["source": "coffee", "target": "design", "weight": 1]]]
        }
        collections["/providers"] = [["id": "demo-provider", "name": "Example provider", "type": "openai", "base_url": "https://api.example.com/v1"]]
        collections["/models"] = [["id": "demo-model", "name": "Default model", "type": "chat", "model_id": "example-model", "provider_id": "demo-provider"]]
        collections["/channels"] = [["id": "telegram", "type": "telegram", "name": "Telegram"], ["id": "discord", "type": "discord", "name": "Discord"], ["id": "feishu", "type": "feishu", "name": "Lark"]]
        for path in ["/memory-providers", "/search-providers", "/fetch-providers", "/email-providers", "/speech-providers", "/speech-models", "/transcription-providers", "/video-providers", "/users/me/runtimes", "/supermarket/apps", "/users"] { collections[path] = [] }
        documents["/users/me"] = ["id": "demo-user", "username": "explorer", "display_name": "Explorer", "role": "admin", "timezone": "Asia/Tokyo"]
    }
    func call(_ path: String, method: String, query: [String: String], body: JSONValue?) throws -> JSONValue {
        let body = body ?? .object([:])
        if path.hasSuffix("/messages"), method == "GET" { return ["items": .array(collections["messages/" + (query["session_id"] ?? "")] ?? [])] }
        if path.hasSuffix("/container/fs/list") {
            let dir = query["path"] ?? "/data"
            return ["entries": .array(dir == "/data" ? [["name": "notes", "path": "/data/notes", "isDir": true], ["name": "AGENTS.md", "path": "/data/AGENTS.md", "isDir": false, "size": 248]] : [["name": "welcome.md", "path": .string(dir + "/welcome.md"), "isDir": false, "size": 124]])]
        }
        if path.hasSuffix("/container/fs/read") { return ["content": "# A workspace of your own\n\nYour agent’s files live here. Connect a server to read and edit real files.\n", "revision": "demo"] }
        if path.hasSuffix("/memory/search") {
            let all = collections[String(path.dropLast(7))] ?? []
            return ["results": .array(all.filter { $0.displayTitle.localizedCaseInsensitiveContains(body["query"].string) })]
        }
        if method == "GET" {
            if let values = collections[path] { return ["items": .array(values)] }
            if let value = documents[path] { return value }
            let parent = (path as NSString).deletingLastPathComponent
            if let value = collections[parent]?.first(where: { $0.stableID == (path as NSString).lastPathComponent }) { return value }
            throw ClientError.message("This feature needs a connected server. Demo mode includes sample chats, agents, memories, schedules, and files.")
        }
        if method == "POST", collections[path] != nil {
            var value = body; value["id"] = .string(UUID().uuidString)
            if path.hasSuffix("/memory") { value["memory"] = body["message"] }
            collections[path, default: []].append(value); return value
        }
        let parent = (path as NSString).deletingLastPathComponent
        if let index = collections[parent]?.firstIndex(where: { $0.stableID == (path as NSString).lastPathComponent }) {
            if method == "DELETE" { collections[parent]?.remove(at: index); return [:] }
            if ["PUT", "PATCH"].contains(method) {
                var value = collections[parent]![index]
                for (k, v) in body.object { value[k] = v }
                collections[parent]![index] = value; return value
            }
        }
        if method == "PUT", documents[path] != nil { documents[path] = body; return body }
        throw ClientError.message("This action requires a connected Memoh server.")
    }
}
