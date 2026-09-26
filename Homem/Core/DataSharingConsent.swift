import Foundation
import Observation
import CryptoKit

struct DataRecipient: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let endpoint: String
    let routingID: String
}

/// A receipt covers one account, workspace, disclosure version and set of recipients.
/// Only display metadata is retained; provider secrets are never stored here.
struct DataSharingDisclosure: Codable, Equatable {
    static let version = 1
    static let policyURL = URL(string: "https://docs.kitta.co/homem/")!
    let scope: String
    let server: String
    let recipients: [DataRecipient]
    var receiptKey: String { "data-sharing|" + scope }
    var fingerprint: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(self)) ?? Data()
        return "\(Self.version):" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    var accepted: Bool { Keychain.read(receiptKey) == fingerprint }
    func accept() throws { try Keychain.save(fingerprint, account: receiptKey) }
    func revoke() throws { try Keychain.save(nil, account: receiptKey) }

    static let providerPaths = ["/providers", "/memory-providers", "/search-providers", "/fetch-providers", "/speech-providers", "/transcription-providers", "/video-providers"]

    @MainActor static func load(scope: String, server: URL, fetch: (String) async throws -> JSONValue) async throws -> Self {
        var recipients: [DataRecipient] = []
        for path in providerPaths {
            let response: JSONValue
            do { response = try await fetch(path) }
            catch ClientError.http(let status, _) where path != "/providers" && [404, 405].contains(status) { continue }
            // Permission errors and malformed responses must not produce a misleading empty list.
            guard case .array = response else {
                guard ["items", "data", "providers"].contains(where: { if case .array = response[$0] { return true }; return false }) else { throw ClientError.invalidResponse }
                recipients += try parse(response.items, path: path)
                continue
            }
            recipients += try parse(response.items, path: path)
        }
        return Self(scope: scope, server: server.absoluteString, recipients: recipients.sorted { $0.id < $1.id })
    }
    static func parse(_ providers: [JSONValue], path: String) throws -> [DataRecipient] {
        try providers.filter { $0["enable"] != false }.map { provider in
            let name = provider.text("name", "provider")
            let config = provider["config"]
            let address = config.text("base_url", "baseURL", "api_base", "endpoint", "url")
            var endpoint = ""
            if !address.isEmpty {
                guard let url = URLComponents(string: address), let host = url.host, ["https", "http"].contains(url.scheme) else { throw ClientError.invalidResponse }
                // URL user info, query strings and paths can contain credentials.
                endpoint = (url.scheme ?? "https") + "://" + host + (url.port.map { ":\($0)" } ?? "")
            }
            guard !name.isEmpty || !endpoint.isEmpty else { throw ClientError.invalidResponse }
            let routing = address + "|" + provider.text("client_type", "provider") + "|" + provider["provider_template_id"].string
            let routingID = SHA256.hash(data: Data(routing.utf8)).map { String(format: "%02x", $0) }.joined()
            return DataRecipient(id: path + "/" + provider.text("id", "name", "provider"), name: name.nonEmpty ?? endpoint, endpoint: endpoint, routingID: routingID)
        }
    }
}

@MainActor @Observable final class DataSharingConsent {
    var disclosure: DataSharingDisclosure?
    var authorized = false
    var loading = false
    var error: String?
    private var revision = UUID()

    func refresh(scope: String, server: URL, fetch: (String) async throws -> JSONValue) async throws {
        let revision = revision
        loading = true
        defer { loading = false }
        do {
            let next = try await DataSharingDisclosure.load(scope: scope, server: server, fetch: fetch)
            try Task.checkCancellation()
            guard revision == self.revision else { throw CancellationError() }
            disclosure = next; authorized = next.accepted; error = nil
        } catch {
            authorized = false; self.error = "Unable to identify the services that receive your data. Try again or contact your server administrator.".localized
            throw error
        }
    }
    func accept() throws {
        guard let disclosure, error == nil, !loading else { throw ClientError.invalidResponse }
        try disclosure.accept(); authorized = true
    }
    func revoke() throws {
        revision = UUID(); authorized = false
        try disclosure?.revoke()
    }
    func requireAuthorization() throws {
        guard authorized, disclosure?.accepted == true else {
            authorized = false
            throw ClientError.message("Review AI data sharing and give permission before continuing.".localized)
        }
    }
}
