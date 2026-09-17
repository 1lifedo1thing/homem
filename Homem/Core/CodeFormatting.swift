import Foundation
import HighlightSwift

struct MarkdownSegment: Equatable {
    let text: String
    let language: String?
    let isCode: Bool

    /// Keep incomplete fences readable while a reply is streaming. A shorter fence
    /// inside a code block is content, not its closing delimiter.
    static func parse(_ markdown: String) -> [MarkdownSegment] {
        var result: [MarkdownSegment] = []
        var buffer = ""
        var fence: Character?
        var fenceLength = 0
        var language: String?
        func flush(code: Bool) {
            if !buffer.isEmpty { result.append(Self(text: buffer, language: code ? language : nil, isCode: code)) }
            buffer = ""
        }
        let lines = markdown.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let indent = line.prefix(while: { $0 == " " }).count
            let trimmed = line.dropFirst(indent)
            let marker = trimmed.first
            let count = trimmed.prefix(while: { $0 == marker }).count
            let remainder = trimmed.dropFirst(count).trimmingCharacters(in: .whitespacesAndNewlines)
            if let delimiter = fence {
                if indent <= 3, marker == delimiter, count >= fenceLength, remainder.isEmpty {
                    // The newline immediately before a closing fence is structural.
                    if buffer.hasSuffix("\n") { buffer.removeLast() }
                    flush(code: true)
                    language = nil
                    fenceLength = 0
                } else { buffer += line + (index < lines.count - 1 ? "\n" : "") }
            } else if indent <= 3, (marker == "`" || marker == "~"), count >= 3,
                      !(marker == "`" && remainder.contains("`")) {
                flush(code: false)
                fence = marker; fenceLength = count
                language = remainder.split(whereSeparator: \.isWhitespace).first.map(String.init)
            } else { buffer += line + (index < lines.count - 1 ? "\n" : "") }
            if fenceLength == 0 { fence = nil }
        }
        flush(code: fence != nil)
        return result
    }

}

struct ToolCodeContent: Equatable {
    let text: String
    let language: String
    init(_ value: JSONValue, language: String = "plaintext") {
        if case .string(let raw) = value {
            if let json = try? JSONValue.parse(raw), case .object = json {
                text = json.pretty; self.language = "json"
            } else if let json = try? JSONValue.parse(raw), case .array = json {
                text = json.pretty; self.language = "json"
            } else { text = raw; self.language = language }
        } else { text = value.pretty; self.language = "json" }
    }
}

/// HighlightSwift runs highlight.js locally. Preserve the original whitespace,
/// including indentation that its HTML conversion normally trims away.
enum CodeHighlighting {
    private static let highlighter = Highlight()
    static func render(_ code: String, language: String?, dark: Bool) async -> AttributedString {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, code.utf8.count <= 32_000,
              let range = code.range(of: trimmed), language != "plaintext", language != "text" else {
            return AttributedString(code)
        }
        do {
            let mode: HighlightMode = language.map { .languageAliasIgnoreIllegal($0.lowercased()) } ?? .automatic
            let result = try await highlighter.request(trimmed, mode: mode, colors: dark ? .dark(.github) : .light(.github))
            // Never let HTML normalization alter a command or its copied content.
            guard String(result.attributedText.characters) == trimmed else { return AttributedString(code) }
            return AttributedString(String(code[..<range.lowerBound])) + result.attributedText + AttributedString(String(code[range.upperBound...]))
        } catch { return AttributedString(code) }
    }
}
