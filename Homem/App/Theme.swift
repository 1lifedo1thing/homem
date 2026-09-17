import SwiftUI
import ImageIO
import WebKit

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
/// Public images are credential-free; private images receive credentials only on the server origin.
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
    static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 12 * 1024 * 1024
        return cache
    }()
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 25
        return URLSession(configuration: config, delegate: AvatarRedirectDelegate(), delegateQueue: nil)
    }()
    static func load(_ url: URL) async throws -> UIImage? {
        decode(try await data(url))
    }
    static func data(_ url: URL, request: URLRequest? = nil, session authenticatedSession: URLSession? = nil) async throws -> Data {

        let limit = 5 * 1024 * 1024
        let data: Data
        if url.scheme == "data" {
            let source = url.absoluteString
            guard source.utf8.count < limit * 3, let comma = source.firstIndex(of: ","),
                  source[..<comma].hasPrefix("data:image/") else { throw ClientError.invalidResponse }
            let payload = String(source[source.index(after: comma)...])
            let decoded = source[..<comma].hasSuffix(";base64") ? Data(base64Encoded: payload) : payload.removingPercentEncoding.map { Data($0.utf8) }
            guard let decoded, decoded.count <= limit else { throw ClientError.invalidResponse }
            data = decoded
        } else {
            let (bytes, response) = try await (authenticatedSession ?? session).bytes(for: request ?? URLRequest(url: url))
            DebugDiagnostics.record("Avatar HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0), host \(url.host ?? "local"), type \(response.mimeType ?? "unknown")")
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
                  response.expectedContentLength <= limit else { throw ClientError.invalidResponse }
            var buffer = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard buffer.count < limit else { throw ClientError.invalidResponse }
                buffer.append(byte)
            }
            data = buffer
        }
        return data
    }
    static func decode(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 240
              ] as CFDictionary) else { return nil }
        let image = UIImage(cgImage: thumbnail)
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
    var imageAPI: APIClient? = nil
    private var client: APIClient? { imageAPI ?? store.api }
    @State private var loaded: UIImage?
    @State private var loadedURL: URL?
    @State private var svg: String?
    private var url: URL? { AvatarSource.url(avatarURL, baseURL: baseURL ?? client?.baseURL) }
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous).fill(Color(.tertiarySystemFill))
            if let loaded, loadedURL == url {
                Image(uiImage: loaded).resizable().scaledToFill()
            } else if let svg, loadedURL == url {
                AvatarSVG(source: svg)
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
            loaded = nil; loadedURL = nil; svg = nil
            guard let url else { return }
            let request = try? client?.avatarRequest(url)
            let cacheKey = ((request == nil ? "public" : String(describing: ObjectIdentifier(client!))) + "|" + url.absoluteString) as NSString
            if let cached = AvatarImages.cache.object(forKey: cacheKey) { loaded = cached; loadedURL = url; return }
            let data: Data
            do { data = try await AvatarImages.data(url, request: request) }
            catch { DebugDiagnostics.record("Avatar load failed: \((error as NSError).domain) \((error as NSError).code)"); return }
            guard !Task.isCancelled else { return }
            if let source = String(data: data, encoding: .utf8), source.contains("<svg") {
                svg = source
            } else {
                loaded = await Task.detached(priority: .utility) { AvatarImages.decode(data) }.value
                if let loaded { AvatarImages.cache.setObject(loaded, forKey: cacheKey, cost: data.count) }
            }
            DebugDiagnostics.record("Avatar decoded: raster=\(loaded != nil), svg=\(svg != nil), bytes=\(data.count)")
            loadedURL = url
        }
    }
}

/// SVG team icons are common on Memoh. Render artwork with scripts and network access disabled.
private struct AvatarSVG: UIViewRepresentable {
    let source: String
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false; view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false; view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.source != source else { return }
        context.coordinator.source = source
        view.loadHTMLString("<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'; img-src data:;\"><style>html,body{margin:0;width:100%;height:100%;overflow:hidden}svg{width:100%;height:100%}</style>" + source, baseURL: nil)
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var source = "" }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.localized.uppercased()).font(.system(.caption2, design: .monospaced, weight: .semibold))
            .tracking(1.4).foregroundStyle(.secondary)
    }
}

struct WorkspaceIdentity: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        HStack(spacing: 8) {
            AgentAvatar(name: store.workspaceName, avatarURL: store.workspace.avatarURL, size: 26)
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
            Text(text.localized).font(.caption.weight(.medium))
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
        HStack(spacing: 5) { Circle().fill(color).frame(width: 5, height: 5); Text(text.localized).font(.caption2.weight(.medium)) }
            .foregroundStyle(color).padding(.horizontal, 9).padding(.vertical, 5).background(color.opacity(0.09), in: Capsule())
    }
}

struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)? = nil
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            Text(message.localized).font(.subheadline)
            Spacer(minLength: 0)
            if let retry { Button("Retry".localized, action: retry).font(.subheadline.weight(.semibold)) }
        }.padding().background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 14)).accessibilityElement(children: .combine)
    }
}

struct EmptyState: View {
    let title: String
    let symbol: String
    let detail: String
    var body: some View { ContentUnavailableView(title.localized, systemImage: symbol, description: Text(detail.localized)) }
}

struct DemoBadge: View {
    var body: some View { Label("Demo workspace".localized, systemImage: "sparkles").font(.caption.weight(.medium)).foregroundStyle(.secondary) }
}

extension NavigationLink where Label == SwiftUI.Label<Text, Image> {
    init(_ title: String, systemImage: String, @ViewBuilder destination: () -> Destination) {
        self.init(destination: destination, label: { SwiftUI.Label(title.localized, systemImage: systemImage) })
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
