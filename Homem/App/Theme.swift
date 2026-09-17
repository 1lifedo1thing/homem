import SwiftUI
import ImageIO

enum Theme {
    static let canvas = Color(uiColor: .systemBackground)
    static let surface = Color(uiColor: .secondarySystemBackground)
    static let separator = Color(uiColor: .separator).opacity(0.35)
    static let cornerRadius: CGFloat = 16
    static let gutter: CGFloat = 20
    static let schemes = ["system", "memoh", "ocean", "forest", "rose", "amber"]
    static func accent(for scheme: String) -> Color {
        switch scheme {
        case "memoh": return .purple
        case "ocean": return .blue
        case "forest": return .green
        case "rose": return .pink
        case "amber": return .orange
        default: return Color(uiColor: .systemBlue)
        }
    }
    static let palette: [Color] = [.teal, .indigo, .orange, .pink, .blue]
    static func color(_ id: String) -> Color { palette[id.utf8.reduce(0) { ($0 + Int($1)) % palette.count }] }
}

/// Server-provided identities are shared by toolbar, dropdown, and content views.
/// Remote images use a separate, credential-free session, never the API session.
enum AvatarSource {
    static func url(_ value: String, baseURL: URL?) -> URL? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let origin = baseURL.flatMap { URL(string: "/", relativeTo: $0)?.absoluteURL }
        guard let url = URL(string: value, relativeTo: origin)?.absoluteURL,
              ["https", "http", "data"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil else { return nil }
        return url
    }
    static func initials(_ name: String) -> String {
        let parts = name.split { $0.isWhitespace || $0 == "-" || $0 == "_" }
        return parts.prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased().nonEmpty ?? "?"
    }
}

enum AvatarImages {
    static let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.totalCostLimit = 12 * 1024 * 1024
        return cache
    }()
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 25
        return URLSession(configuration: config)
    }()
    static func load(_ url: URL) async throws -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        let limit = 5 * 1024 * 1024
        let data: Data
        if url.scheme == "data" {
            let source = url.absoluteString
            guard source.utf8.count < limit * 2, let comma = source.firstIndex(of: ","),
                  source[..<comma].hasPrefix("data:image/"), source[..<comma].hasSuffix(";base64"),
                  let decoded = Data(base64Encoded: String(source[source.index(after: comma)...])), decoded.count <= limit else { return nil }
            data = decoded
        } else {
            let (bytes, response) = try await session.bytes(from: url)
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
                  response.expectedContentLength <= limit else { return nil }
            var buffer = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard buffer.count < limit else { return nil }
                buffer.append(byte)
            }
            data = buffer
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 240
              ] as CFDictionary) else { return nil }
        let image = UIImage(cgImage: thumbnail)
        cache.setObject(image, forKey: url as NSURL, cost: thumbnail.bytesPerRow * thumbnail.height)
        return image
    }
}

struct AgentAvatar: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appAccent) private var accent
    let name: String
    var avatarURL: String = ""
    var size: CGFloat = 48
    var symbol: String? = nil
    var baseURL: URL? = nil
    @State private var loaded: UIImage?
    @State private var loadedURL: URL?
    private var url: URL? { AvatarSource.url(avatarURL, baseURL: baseURL ?? store.api?.baseURL) }
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous).fill(Color(.tertiarySystemFill))
            if let loaded, loadedURL == url {
                Image(uiImage: loaded).resizable().scaledToFill()
            } else if let symbol {
                Image(systemName: symbol).font(.system(size: size * 0.42, weight: .medium)).foregroundStyle(.secondary)
            } else {
                Text(AvatarSource.initials(name)).font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous).strokeBorder(.primary.opacity(0.06), lineWidth: 0.5))
        .accessibilityHidden(true)
        .task(id: url) {
            loaded = nil; loadedURL = nil
            guard let url else { return }
            if let image = try? await AvatarImages.load(url), !Task.isCancelled { loaded = image; loadedURL = url }
        }
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(.caption2, design: .monospaced, weight: .semibold))
            .tracking(1.4).foregroundStyle(.secondary)
    }
}

struct WorkspaceIdentity: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        HStack(spacing: 8) {
            AgentAvatar(name: store.workspaceName, avatarURL: store.workspace["avatar_url"].string, size: 22, symbol: "square.stack.3d.up")
            Text(store.workspaceName).font(.subheadline.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
        }.accessibilityElement(children: .combine)
    }
}

struct StatusIndicator: View {
    let text: String
    var color: Color = .green
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(text).font(.caption.weight(.medium))
        }.foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
    }
}

struct DetailSurface: ViewModifier {
    func body(content: Content) -> some View {
        content.background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(Theme.separator, lineWidth: 0.5))
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

private struct AppAccentKey: EnvironmentKey {
    static let defaultValue = Theme.accent(for: "system")
}
extension EnvironmentValues {
    var appAccent: Color {
        get { self[AppAccentKey.self] }
        set { self[AppAccentKey.self] = newValue }
    }
}
