import Foundation
#if canImport(L10n_swift)
import L10n_swift
#endif

/// App-owned copy uses L10n-swift. The catalog compiles to its supported .strings format.
/// Server data and user-authored names/messages are never passed through localization.
enum AppLocalization {
    #if canImport(L10n_swift)
    private static let lock = NSRecursiveLock()
    private static var engines: [String: L10n] = [:]
    private static func engine(language: String?) -> L10n {
        let language = language ?? Bundle.main.preferredLocalizations.first ?? "en"
        if let engine = engines[language] { return engine }
        let engine = L10n(bundle: .main, language: language)
        engine.logger = nil
        engines[language] = engine
        return engine
    }
    static func text(_ key: String, language: String? = nil) -> String {
        lock.lock(); defer { lock.unlock() }
        return engine(language: language).string(for: key)
    }
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        lock.lock(); defer { lock.unlock() }
        let engine = engine(language: nil)
        return engine.string(format: engine.string(for: key), args: arguments)
    }
    #else
    // The standalone macOS wire-contract CLI is compiled without app dependencies.
    static func text(_ key: String, language: String? = nil) -> String { key }
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: key, locale: Locale.current, arguments: arguments)
    }
    #endif
}
extension String {
    var localized: String { AppLocalization.text(self) }
}
