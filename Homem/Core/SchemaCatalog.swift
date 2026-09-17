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
