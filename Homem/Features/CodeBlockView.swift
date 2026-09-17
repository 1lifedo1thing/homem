import SwiftUI

struct CodeBlockView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appAccent) private var accent
    let code: String
    var language: String? = nil
    var title: String? = nil
    @State private var highlighted: AttributedString?
    @State private var renderedRequest: RenderRequest?
    @State private var expanded = false
    @State private var copied = false
    @ScaledMetric(relativeTo: .footnote) private var maximumHeight = 420

    private var lines: [String] { code.components(separatedBy: "\n") }
    private var isLong: Bool { lines.count > 18 || code.count > 4_000 }
    private var displayed: String { expanded ? code : String(lines.prefix(18).joined(separator: "\n").prefix(4_000)) }
    private var request: RenderRequest { RenderRequest(code: displayed, language: language, dark: colorScheme == .dark) }
    private struct RenderRequest: Equatable { let code: String; let language: String?; let dark: Bool }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(title ?? language?.nonEmpty ?? "Code".localized)
                    .font(.caption.weight(.medium)).lineLimit(1)
                if title != nil, let language, language != "plaintext" {
                    Text(language).font(.caption.monospaced()).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 8)
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption).frame(width: 44, height: 44)
                }.buttonStyle(.plain).foregroundStyle(copied ? accent : .secondary)
                    .accessibilityLabel((copied ? "Copied" : "Copy").localized)
                    .task(id: copied) {
                        guard copied else { return }
                        try? await Task.sleep(for: .seconds(2))
                        if !Task.isCancelled { copied = false }
                    }
            }.foregroundStyle(.secondary).padding(.leading, 12).padding(.trailing, 2)
            Divider().opacity(0.5)
            ScrollView([.horizontal, .vertical]) {
                Text(renderedRequest == request ? highlighted ?? AttributedString(displayed) : AttributedString(displayed))
                    .font(.system(.footnote, design: .monospaced)).lineSpacing(3)
                    .textSelection(.enabled).fixedSize(horizontal: true, vertical: true)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }.defaultScrollAnchor(.topLeading).frame(maxHeight: maximumHeight).fixedSize(horizontal: false, vertical: true)
            if isLong {
                Button { expanded.toggle() } label: {
                    HStack(spacing: 5) {
                        Text((expanded ? "Show less" : "Show more").localized)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    }.font(.caption.weight(.medium)).frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.plain).foregroundStyle(accent)
            }
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.06)))
        .task(id: request) {
            let current = request
            // Coalesce streamed tokens and cancel work for offscreen blocks.
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let result = await CodeHighlighting.render(current.code, language: current.language, dark: current.dark)
            guard !Task.isCancelled else { return }
            highlighted = result; renderedRequest = current
        }
    }
}
