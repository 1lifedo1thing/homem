import Foundation

/// Lossless wire values keep plugin configuration and new server fields intact.
enum JSONValue: Codable, Hashable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    subscript(_ key: String) -> JSONValue {
        get { object[key] ?? .null }
        set { var o = object; o[key] = newValue; self = .object(o) }
    }
    var object: [String: JSONValue] { if case .object(let v) = self { return v }; return [:] }
    var array: [JSONValue] { if case .array(let v) = self { return v }; return [] }
    var string: String { if case .string(let v) = self { return v }; return "" }
    var bool: Bool { if case .bool(let v) = self { return v }; return false }
    var number: Double { if case .number(let v) = self { return v }; return 0 }
    var isNull: Bool { self == .null }
    var scalar: String {
        switch self { case .string(let s): return s; case .bool(let b): return b ? "true" : "false"; case .number(let n): return n == n.rounded() ? String(format: "%.0f", n) : String(n); default: return pretty }
    }
    var pretty: String {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? String(data: e.encode(self), encoding: .utf8)) ?? "null"
    }
    var encoded: Data { get throws { try JSONEncoder().encode(self) } }
    static func parse(_ text: String) throws -> JSONValue { try JSONDecoder().decode(Self.self, from: Data(text.utf8)) }
    var items: [JSONValue] {
        if case .array(let values) = self { return values }
        for key in ["items", "results", "entries", "memories", "data", "models", "providers", "sessions", "skills", "apps", "installations", "dependencies", "records"] {
            if case .array(let values) = self[key] { return values }
        }
        return []
    }
    func text(_ keys: String...) -> String { keys.map { self[$0].string }.first { !$0.isEmpty } ?? "" }
    var avatarURL: String { text("avatar_url", "icon_url", "image_url").nonEmpty ?? self["metadata"].text("avatar_url", "icon_url") }
    var displayTitle: String { text("display_name", "title", "name", "memory", "content", "message", "model_id", "id") }
    var stableID: String { text("id", "turn_id", "item_id", "path", "name", "key", "dep_id", "slug", "type") }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByDictionaryLiteral, ExpressibleByArrayLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral {
    init(stringLiteral value: String) { self = .string(value) }
    init(dictionaryLiteral elements: (String, JSONValue)...) { self = .object(Dictionary(elements, uniquingKeysWith: { _, b in b })) }
    init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(integerLiteral value: Int) { self = .number(Double(value)) }
}

extension String {
    var wireDate: Date? {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return format.date(from: self) ?? ISO8601DateFormatter().date(from: self)
    }
    var fieldLabel: String { replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").capitalized }
    var nonEmpty: String? { isEmpty ? nil : self }
    var pathComponent: String { addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_.~"))) ?? self }
}

struct Record: Identifiable, Hashable {
    var value: JSONValue
    var id: String { value.stableID.nonEmpty ?? value.pretty }
    var title: String { value.displayTitle.nonEmpty ?? "Untitled" }
    var subtitle: String { value.text("description", "status", "type", "provider_type", "updated_at") }
}
