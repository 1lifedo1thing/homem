import SwiftUI

enum ChatWorkspaceTool: String, CaseIterable, Identifiable {
    case desktop, terminal
    var id: Self { self }
    var title: String { self == .desktop ? "Desktop" : "Terminal" }
    var chatTitle: String { self == .desktop ? "Chat + desktop" : "Chat + terminal" }
    var symbol: String { self == .desktop ? "desktopcomputer" : "terminal" }
}

enum ChatSplitLayout {
    static func fraction(_ value: Double) -> Double { min(0.65, max(0.25, value)) }
    static func paneHeight(available: CGFloat, fraction: Double) -> CGFloat {
        // Keep the composer and some conversation visible even above the keyboard.
        max(0, min(available * Self.fraction(fraction), available - 170))
    }
}

struct ChatWorkspacePane: View {
    let api: APIClient
    let botID: String
    let tool: ChatWorkspaceTool
    let select: (ChatWorkspaceTool) -> Void
    let close: () -> Void
    @State private var desktop: DesktopModel
    @State private var terminalID = UUID()

    init(api: APIClient, botID: String, tool: ChatWorkspaceTool,
         select: @escaping (ChatWorkspaceTool) -> Void, close: @escaping () -> Void) {
        self.api = api; self.botID = botID; self.tool = tool; self.select = select; self.close = close
        let model = DesktopModel(api: api, botID: botID)
        model.setViewOnly(true)
        _desktop = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Menu {
                    ForEach(ChatWorkspaceTool.allCases) { item in
                        Button(item.title.localized, systemImage: item.symbol) { select(item) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tool.symbol)
                        Text(tool.title.localized).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    }.font(.subheadline.weight(.medium))
                }.accessibilityLabel("Split view".localized)
                Spacer(minLength: 4)
                if tool == .desktop { DesktopModeButton(model: desktop) }
                Button {
                    if tool == .desktop { Task { desktop.disconnect(); await desktop.connect() } }
                    else { terminalID = UUID() }
                } label: { Image(systemName: "arrow.clockwise").frame(width: 40, height: 44) }
                    .accessibilityLabel((tool == .desktop ? "Reconnect desktop" : "Reconnect terminal").localized)
                Button(action: close) { Image(systemName: "xmark").frame(width: 40, height: 44) }
                    .accessibilityLabel("Close split view".localized).accessibilityIdentifier("closeChatSplit")
            }.buttonStyle(.plain).padding(.leading, 14).padding(.trailing, 4).background(.bar)
            Divider()
            if api.isDemo {
                ZStack {
                    Color(.secondarySystemBackground)
                    Label((tool == .desktop ? "Desktop unavailable" : "Terminal unavailable").localized, systemImage: tool.symbol)
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else if tool == .desktop {
                DesktopContent(model: desktop, embedded: true)
            } else {
                TerminalScreen(botID: botID, embedded: true).id(terminalID)
            }
        }
    }
}

struct DesktopModeButton: View {
    let model: DesktopModel
    var body: some View {
        Button { model.setViewOnly(!model.viewOnly) } label: {
            Label((model.viewOnly ? "View only" : "Control").localized,
                  systemImage: model.viewOnly ? "eye" : "hand.point.up.left")
                .font(.caption.weight(.medium)).lineLimit(1).padding(.horizontal, 8).frame(minHeight: 44)
        }.buttonStyle(.plain)
            .accessibilityLabel("View only".localized)
            .accessibilityValue((model.viewOnly ? "On" : "Off").localized)
            .accessibilityIdentifier("desktopViewOnly")
    }
}
