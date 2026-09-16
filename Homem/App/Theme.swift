import SwiftUI

enum Theme {
    static let accent = Color(red: 0.12, green: 0.43, blue: 0.39)
    static let palette: [Color] = [.teal, .indigo, .orange, .pink, .blue]
    static func color(_ id: String) -> Color { palette[id.utf8.reduce(0) { ($0 + Int($1)) % palette.count }] }
}

struct AgentAvatar: View {
    let name: String
    var size: CGFloat = 48
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.32).fill(Theme.color(name).gradient)
            Image(systemName: name.lowercased().contains("mika") ? "terminal" : name.lowercased().contains("sage") ? "leaf" : "sparkle")
                .font(.system(size: size * 0.43, weight: .medium)).foregroundStyle(.white)
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct StatusPill: View {
    var text: String
    var color: Color = .green
    var body: some View {
        HStack(spacing: 5) { Circle().fill(color).frame(width: 5, height: 5); Text(text).font(.caption2.weight(.medium)) }
            .foregroundStyle(color).padding(.horizontal, 9).padding(.vertical, 5).background(color.opacity(0.09), in: Capsule())
    }
}

struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)? = nil
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            Text(message).font(.subheadline)
            Spacer(minLength: 0)
            if let retry { Button("Retry", action: retry).font(.subheadline.weight(.semibold)) }
        }.padding().background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 14)).accessibilityElement(children: .combine)
    }
}

struct EmptyState: View {
    let title: String
    let symbol: String
    let detail: String
    var body: some View { ContentUnavailableView(title, systemImage: symbol, description: Text(detail)) }
}

struct DemoBadge: View {
    var body: some View { Label("Demo workspace", systemImage: "sparkles").font(.caption.weight(.medium)).foregroundStyle(.secondary) }
}

extension NavigationLink where Label == SwiftUI.Label<Text, Image> {
    init(_ title: String, systemImage: String, @ViewBuilder destination: () -> Destination) {
        self.init(destination: destination, label: { SwiftUI.Label(title, systemImage: systemImage) })
    }
}
