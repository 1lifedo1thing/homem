import Foundation
import Network

enum DesktopRecovery {
    static func canRetry(_ failure: Error) -> Bool {
        if let client = failure as? ClientError, case .http(let status, _) = client { return status >= 500 }
        let error = failure as NSError
        if error.domain == NSURLErrorDomain {
            return [URLError.timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
                    .dnsLookupFailed, .notConnectedToInternet, .resourceUnavailable].contains { $0.rawValue == error.code }
        }
        // URLSession WebSockets can expose BSD socket failures directly instead
        // of wrapping them as URLError.networkConnectionLost.
        if error.domain == NSPOSIXErrorDomain {
            let transient: [POSIXErrorCode] = [.ENOTCONN, .ECONNRESET, .ECONNABORTED, .EPIPE,
                                               .ETIMEDOUT, .ECONNREFUSED, .ENETDOWN, .ENETUNREACH, .EHOSTUNREACH]
            return transient.contains { Int($0.rawValue) == error.code }
        }
        return false
    }
    static func isNetworkFailure(_ failure: Error) -> Bool {
        let error = failure as NSError
        return (error.domain == NSURLErrorDomain || error.domain == NSPOSIXErrorDomain) && canRetry(failure)
    }
    static func isOffline(_ failure: Error) -> Bool {
        (failure as? URLError)?.code == .notConnectedToInternet
    }
    static func delay(attempt: Int) -> Duration {
        .seconds(min(30, 1 << min(max(0, attempt - 1), 5)))
    }
    /// A missing route must not burn through the retry budget. Cancellation on
    /// pane dismissal also stops this monitor, so it cannot reopen a closed pane.
    static func waitForNetwork() async throws {
        let monitor = NWPathMonitor()
        let updates = AsyncStream<Bool> { continuation in
            monitor.pathUpdateHandler = { continuation.yield($0.status == .satisfied) }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue.global(qos: .utility))
        }
        defer { monitor.cancel() }
        for await available in updates {
            try Task.checkCancellation()
            if available { return }
        }
        throw CancellationError()
    }

}

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
        DebugDiagnostics.record("Desktop readiness: enabled=\(info["enabled"].bool), available=\(info["available"].bool), running=\(info["running"].bool)")
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
