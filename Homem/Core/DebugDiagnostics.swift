import Foundation
import OSLog

/// Debug builds record connection stages only, never credentials or message content.
enum DebugDiagnostics {
    private static let logger = Logger(subsystem: "ad.neko.homem", category: "Connection")
    static func record(_ event: String) {
        #if DEBUG
        logger.notice("\(event, privacy: .public)")
        #endif
    }
}
