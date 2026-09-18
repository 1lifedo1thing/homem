import SwiftUI

private struct ExpandChatWorkspaceKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var expandChatWorkspace: () -> Void {
        get { self[ExpandChatWorkspaceKey.self] }
        set { self[ExpandChatWorkspaceKey.self] = newValue }
    }
}

enum ChatWorkspaceTool: String, CaseIterable, Identifiable {
    case desktop, terminal
    var id: Self { self }
    var title: String { self == .desktop ? "Desktop" : "Terminal" }
    var chatTitle: String { self == .desktop ? "Chat + desktop" : "Chat + terminal" }
    var symbol: String { self == .desktop ? "desktopcomputer" : "terminal" }
}

enum ChatSplitLayout {
    static func fraction(_ value: Double) -> Double { min(0.65, max(0.25, value)) }
    static func usesColumns(width: CGFloat) -> Bool { width >= 700 }
    static func columnFraction(_ value: Double, available: CGFloat) -> Double {
        let minimum = min(0.5, 300 / max(available, 1))
        return min(1 - minimum, max(minimum, value))
    }
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
    let allowsSelection: Bool
    @State private var desktop: DesktopModel
    @State private var terminalID = UUID()

    init(api: APIClient, botID: String, tool: ChatWorkspaceTool, allowsSelection: Bool = true,
         select: @escaping (ChatWorkspaceTool) -> Void, close: @escaping () -> Void) {
        self.api = api; self.botID = botID; self.tool = tool; self.select = select; self.close = close
        self.allowsSelection = allowsSelection
        let model = DesktopModel(api: api, botID: botID)
        model.setViewOnly(true)
        _desktop = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if allowsSelection {
                    Menu {
                        ForEach(ChatWorkspaceTool.allCases) { item in
                            Button(item.title.localized, systemImage: item.symbol) { select(item) }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Label(tool.title.localized, systemImage: tool.symbol).lineLimit(1)
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                        }.font(.subheadline.weight(.medium))
                    }.accessibilityLabel("Split view".localized)
                } else {
                    Label(tool.title.localized, systemImage: tool.symbol).font(.subheadline.weight(.medium)).lineLimit(1)
                }
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

/// A generous hit area around a quiet handle; also adjustable with VoiceOver.
struct ChatPaneDivider: View {
    @Binding var fraction: Double
    let vertical: Bool
    let available: CGFloat
    @State private var startFraction: Double?

    private func clamped(_ value: Double) -> Double {
        vertical ? ChatSplitLayout.columnFraction(value, available: available) : ChatSplitLayout.fraction(value)
    }

    var body: some View {
        Capsule().fill(.tertiary)
            .frame(width: vertical ? 4 : 32, height: vertical ? 32 : 4)
            .frame(maxWidth: vertical ? nil : .infinity, maxHeight: vertical ? .infinity : nil)
            .frame(width: vertical ? 24 : nil, height: vertical ? nil : 24)
            .background(Theme.surface).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("chatSplit")).onChanged { value in
                if startFraction == nil { startFraction = clamped(fraction) }
                let translation = vertical ? value.translation.width : value.translation.height
                fraction = clamped((startFraction ?? fraction) + translation / max(available, 1))
            }.onEnded { _ in startFraction = nil })
            .accessibilityElement().accessibilityLabel("Resize split view".localized)
            .accessibilityValue(Text(clamped(fraction), format: .percent.precision(.fractionLength(0))))
            .accessibilityAdjustableAction { direction in
                fraction = clamped(clamped(fraction) + (direction == .increment ? 0.05 : -0.05))
            }
    }
}
