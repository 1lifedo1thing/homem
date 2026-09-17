import SwiftUI

struct MessageGroup: Identifiable {
    let id: Int
    var messages: [JSONValue]
    var isToolGroup: Bool { messages.first?["type"].string == "tool" }
    static func group(_ messages: [JSONValue]) -> [MessageGroup] {
        var result: [MessageGroup] = []
        for (index, message) in messages.enumerated() {
            if message["type"] == "tool", result.last?.isToolGroup == true {
                result[result.count - 1].messages.append(message)
            } else { result.append(MessageGroup(id: index, messages: [message])) }
        }
        return result
    }
}

struct MessageSequence: View {
    let messages: [JSONValue]
    let model: ChatModel
    var body: some View {
        ForEach(MessageGroup.group(messages)) { group in
            if group.isToolGroup { ToolActivityView(messages: group.messages, model: model) }
            else { ForEach(Array(group.messages.enumerated()), id: \.offset) { _, message in MessageBlockView(message: message, model: model) } }
        }
    }
}

enum ToolPresentation {
    static func title(_ name: String) -> String {
        let name = name.lowercased()
        if name.contains("search") { return "Search" }
        if name.contains("schedule") { return "Schedule" }
        if name.contains("memory") { return "Memory" }
        if name.contains("read") || name.contains("list_files") { return "Read files" }
        if name.contains("write") || name.contains("edit") || name.contains("patch") { return "Update files" }
        if name.contains("browser") || name.contains("fetch") { return "Browse" }
        if name.contains("exec") || name.contains("shell") || name.contains("terminal") { return "Run command" }
        return "Tool activity"
    }
}

struct ToolActivityView: View {
    let messages: [JSONValue]
    let model: ChatModel
    @State private var expanded = false
    private var running: Bool { messages.contains { $0["running"].bool } }
    private var failed: Bool { messages.contains { $0["status"] == "error" || $0["status"] == "failed" || $0["output"]["is_error"].bool } }
    private var title: String {
        if messages.count == 1 { return ToolPresentation.title(messages[0]["name"].string).localized }
        return running ? AppLocalization.format("Working · %lld actions", messages.count) : AppLocalization.format("%lld actions", messages.count)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() } } label: {
                HStack(spacing: 7) {
                    if running { ProgressView().controlSize(.mini) }
                    else { Image(systemName: failed ? "exclamationmark.circle" : "checkmark").font(.caption) }
                    Text(title).font(.caption.weight(.medium)).lineLimit(2)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).rotationEffect(.degrees(expanded ? 90 : 0))
                    Spacer(minLength: 0)
                }.foregroundStyle(failed ? .orange : .secondary).frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("toolActivity")
                .accessibilityValue((expanded ? "Expanded" : "Collapsed").localized)
            if expanded {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(message["name"].string).font(.caption.monospaced().weight(.medium))
                                .foregroundStyle(.secondary).textSelection(.enabled)
                            if !message["input"].isNull { payload(message["input"], title: "Input".localized, language: inputLanguage(message)) }
                            if !message["output"].isNull { payload(message["output"], title: "Output".localized) }
                            if !message["diff"].string.isEmpty {
                                CodeBlockView(code: message["diff"].string, language: "diff", title: "Changes".localized)
                            }
                        }
                    }
                }.padding(.leading, 18).padding(.bottom, 8)
            }
            // Requests needing an answer must remain visible even when activity is collapsed.
            ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                if message["approval"]["status"] == "pending" { ApprovalView(approval: message["approval"], model: model) }
                if message["user_input"]["status"] == "pending" { UserInputView(input: message["user_input"], model: model) }
            }
        }
    }
    private func inputLanguage(_ message: JSONValue) -> String {
        let name = message["name"].string.lowercased()
        return ["exec", "shell", "terminal"].contains(where: name.contains) ? "bash" : "plaintext"
    }
    private func payload(_ value: JSONValue, title: String, language: String = "plaintext") -> some View {
        let content = ToolCodeContent(value, language: language)
        return CodeBlockView(code: content.text, language: content.language, title: title)
    }

}
