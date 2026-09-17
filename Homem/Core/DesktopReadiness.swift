import Foundation

/// Follows Memoh's prepare → poll → offer sequence, including older hosted responses.
enum DesktopReadiness {
    static func ready(_ info: JSONValue) -> Bool {
        info["enabled"] != false && info["available"].bool && info["running"].bool
            && info["desktop_available"] != false && info["browser_available"] != false
    }
    static func blockingReason(_ info: JSONValue) -> String? {
        if info["enabled"] == false { return "Desktop is turned off for this agent." }
        switch info["unavailable_reason"].string {
        case "workspace is not reachable", "container not reachable": return "Start this workspace before opening its desktop."
        case "manager not configured": return "This server does not support desktops."
        case "gstreamer unavailable": return "Desktop video is unavailable on this server."
        default: return nil
        }
    }
    @MainActor static func prepare(api: APIClient, base: String, progress: @escaping (String) -> Void) async throws {
        var info = try await api.call(base)
        try Task.checkCancellation()
        if let reason = blockingReason(info) { throw ClientError.message(reason.localized) }
        if ready(info) { return }
        progress("Preparing desktop")
        // prepare_supported was not populated by some hosted versions; do not reject those.
        _ = try await api.streamOperation(base + "/prepare", method: "POST", body: nil) { event in
            switch event["step"].string {
            case "installing", "toolkit", "system", "browser": progress("Setting up desktop")
            case "starting", "desktop": progress("Starting desktop")
            default: progress("Preparing desktop")
            }
        }
        for _ in 0..<13 {
            try Task.checkCancellation()
            info = try await api.call(base)
            if ready(info) { return }
            if let reason = blockingReason(info) { throw ClientError.message(reason.localized) }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw ClientError.message("The desktop is not ready yet. Try again shortly.".localized)
    }
}
