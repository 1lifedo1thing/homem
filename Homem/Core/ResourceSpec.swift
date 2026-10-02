import Foundation

struct ResourceSpec: Hashable {
    var title: String
    var path: String
    var template: String
    var icon: String = "square.stack"
    var detailTemplate: String? = nil
    var detailCollectionPath: String? = nil
    var canCreate = true
    var canEdit = true
    var canDelete = true
    var idKey = "id"
    static func bot(_ id: String, _ suffix: String, title: String, icon: String = "square.stack", detail: String? = nil) -> Self {
        .init(title: title, path: "/bots/\(id.pathComponent)/\(suffix)", template: "/bots/{bot_id}/\(suffix)", icon: icon, detailTemplate: detail)
    }
    static func memory(_ id: String) -> Self { .bot(id, "memory", title: "Memories", icon: "brain", detail: "/bots/{bot_id}/memory/{memory_id}") }
    static func schedules(_ id: String) -> Self { .bot(id, "schedule", title: "Schedules", icon: "clock.arrow.circlepath") }
    static func mcp(_ id: String) -> Self { .bot(id, "mcp", title: "MCP connections", icon: "point.3.connected.trianglepath.dotted") }
    static func skills(_ id: String) -> Self { var s = Self.bot(id, "container/skills", title: "Skills", icon: "sparkles"); s.canEdit = false; s.canDelete = false; return s }
    static func apps(_ id: String) -> Self { var s = Self.bot(id, "apps", title: "Installed apps", icon: "square.stack.3d.up", detail: "/bots/{bot_id}/apps/{installation_id}"); s.canEdit = false; return s }
    static func global(_ path: String, title: String, icon: String = "slider.horizontal.3") -> Self { .init(title: title, path: path, template: path, icon: icon) }
    func itemPath(_ record: Record) -> String { (detailCollectionPath ?? path) + "/" + record.id.pathComponent }
    var resolvedDetailTemplate: String { detailTemplate ?? template + "/{id}" }
    var substitutions: [String: String] {
        let parts = path.split(separator: "/")
        if parts.first == "bots", parts.count > 1 { return ["bot_id": String(parts[1])] }
        return [:]
    }
    func record(_ item: JSONValue) -> Record {
        var value = item
        if template.hasSuffix("/connectors") {
            value["id"] = item["connection_id"]
            value["display_name"] = .string(item.text("alias", "connector_type").nonEmpty ?? "Account".localized)
        } else if template.hasSuffix("/channel-managers") {
            value["id"] = item["channel_identity_id"]
            value["display_name"] = .string(item.text("channel_identity_display_name", "channel_subject_id", "channel_type").nonEmpty ?? "Channel account".localized)
        } else if template.hasSuffix("/user-access") {
            value["display_name"] = .string(item.text("user_display_name", "user_username").nonEmpty ?? "Person".localized)
        }
        return Record(value: value)
    }
    var createOperation: APIOperation? { canCreate ? SchemaCatalog.shared.operation(template, "POST") : nil }
    var editOperation: APIOperation? { canEdit ? (SchemaCatalog.shared.operation(resolvedDetailTemplate, "PUT") ?? SchemaCatalog.shared.operation(resolvedDetailTemplate, "PATCH")) : nil }
    var deleteOperation: APIOperation? {
        guard canDelete else { return nil }
        return SchemaCatalog.shared.operation(resolvedDetailTemplate, "DELETE") ?? (template.hasSuffix("/memory") ? SchemaCatalog.shared.operation(template + "/{id}", "DELETE") : nil)
    }
}

