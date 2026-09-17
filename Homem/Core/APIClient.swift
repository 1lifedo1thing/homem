import Foundation
import Security
import Observation

enum ClientError: LocalizedError {
    case invalidURL, http(Int, String), invalidResponse, message(String)
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Enter a complete http:// or https:// API address without credentials, query, or fragment."
        case .http(let status, let message): return "\(message) (HTTP \(status))"
        case .invalidResponse: return "The server returned an unexpected response. Check the API base address."
        case .message(let s): return s
        }
    }
}

enum Keychain {
    static func read(_ account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ad.neko.homem", kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ value: String?, account: String) throws {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ad.neko.homem", kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
        guard let value else { return }
        var add = q
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw ClientError.message("Could not securely save this sign-in (\(status)).") }
    }
    static func removeDrafts(server: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ad.neko.homem", kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let items = result as? [[String: Any]] else { return }
        for item in items {
            if let account = item[kSecAttrAccount as String] as? String, account.hasPrefix("draft|\(server)|") { try? save(nil, account: account) }
        }
    }
}

final class SafeRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Never forward credentials or mutation bodies to a redirect target.
        completionHandler(nil)
    }
}

@MainActor @Observable final class APIClient {
    var baseURL: URL
    var token: String
    var isDemo: Bool
    var unauthorized = false
    var signedOut = false
    var officialSession: OfficialSession?
    var isOfficial: Bool { officialSession != nil }
    var persistOfficialSession = false
    let session: URLSession
    let demo = DemoServer()
    private var refreshTask: Task<String, Error>?

    init(baseURL: URL, token: String = "", isDemo: Bool = false, session: URLSession? = nil, officialSession: OfficialSession? = nil) {
        self.baseURL = baseURL; self.token = token; self.isDemo = isDemo
        self.officialSession = officialSession
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 120
        self.session = session ?? URLSession(configuration: config, delegate: SafeRedirectDelegate(), delegateQueue: nil)
        if let officialSession {
            for cookie in officialSession.validCookies { self.session.configuration.httpCookieStorage?.setCookie(cookie) }
        }
    }
    static func normalizedURL(_ input: String) throws -> URL {
        guard var c = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(c.scheme?.lowercased() ?? ""), let host = c.host, !host.isEmpty,
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil else { throw ClientError.invalidURL }
        c.scheme = c.scheme?.lowercased()
        while c.path.hasSuffix("/") { c.path.removeLast() }
        guard let url = c.url else { throw ClientError.invalidURL }; return url
    }
    func request(_ path: String, method: String = "GET", query: [String: String] = [:], body: JSONValue? = nil) throws -> URLRequest {
        try request(at: baseURL, path: path, method: method, query: query, body: body)
    }
    private func request(at base: URL, path: String, method: String, query: [String: String], body: JSONValue?, includeTeam: Bool = true) throws -> URLRequest {
        if isOfficial, base != OfficialServer.apiURL && base != OfficialServer.platformURL { throw ClientError.invalidURL }
        guard path.hasPrefix("/"), !path.contains("://"), !path.contains("?"), !path.contains("#"), !path.split(separator: "/").contains(".."),
              var c = URLComponents(url: base, resolvingAgainstBaseURL: false) else { throw ClientError.invalidURL }
        c.percentEncodedPath = c.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty ? path : c.percentEncodedPath + path
        if !query.isEmpty { c.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = c.url else { throw ClientError.invalidURL }
        var r = URLRequest(url: url); r.httpMethod = method
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        if let officialSession {
            r.setValue(OfficialServer.origin.absoluteString, forHTTPHeaderField: "Origin")
            if includeTeam, !officialSession.teamID.isEmpty { r.setValue(officialSession.teamID, forHTTPHeaderField: "X-Team-ID") }
            let cookies = session.configuration.httpCookieStorage?.cookies(for: url)?.filter(OfficialServer.accepts) ?? []
            for (key, value) in HTTPCookie.requestHeaderFields(with: cookies) { r.setValue(value, forHTTPHeaderField: key) }
        } else if !token.isEmpty { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { r.httpBody = try body.encoded; r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return r
    }
    func platformCall(_ path: String, method: String = "GET", body: JSONValue? = nil) async throws -> JSONValue {
        guard isOfficial else { throw ClientError.invalidURL }
        let data = try await perform(request(at: OfficialServer.platformURL, path: path, method: method, query: [:], body: body, includeTeam: path == "/ws-tickets"), retry: false)
        if data.isEmpty { return [:] }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
    func call(_ path: String, method: String = "GET", query: [String: String] = [:], body: JSONValue? = nil) async throws -> JSONValue {
        guard !signedOut else { throw ClientError.message("This session has signed out.") }
        if isDemo { return try demo.call(path, method: method, query: query, body: body) }
        let data = try await perform(request(path, method: method, query: query, body: body))
        if data.isEmpty { return .object([:]) }
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { throw ClientError.invalidResponse }
        return value
    }
    func perform(_ request: URLRequest, retry: Bool = true) async throws -> Data {
        guard !signedOut else { throw ClientError.message("This session has signed out.") }
        let (data, response) = try await session.data(for: request)
        guard !signedOut else { throw ClientError.message("This session has signed out.") }
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        if isOfficial, let url = http.url, url.host == OfficialServer.origin.host, url.scheme == "https" {
            let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, entry in
                if let key = entry.key as? String, let value = entry.value as? String { result[key] = value }
            }
            for cookie in HTTPCookie.cookies(withResponseHeaderFields: headers, for: url) {
                if cookie.expiresDate.map({ $0 <= Date() }) == true { session.configuration.httpCookieStorage?.deleteCookie(cookie) }
                else if OfficialServer.accepts(cookie) { session.configuration.httpCookieStorage?.setCookie(cookie) }
            }
        }
        if let officialSession, persistOfficialSession {
            try OfficialSession(cookies: session.configuration.httpCookieStorage?.cookies ?? [], teamID: officialSession.teamID).save()
        }
        if http.statusCode == 401, retry, !isOfficial, !token.isEmpty, !request.url!.path.hasSuffix("/auth/refresh") {
            do {
                if refreshTask == nil {
                    refreshTask = Task { [self] in
                        let data = try await perform(self.request("/auth/refresh", method: "POST"), retry: false)
                        let value = try JSONDecoder().decode(JSONValue.self, from: data)
                        guard !value["access_token"].string.isEmpty else { throw ClientError.invalidResponse }
                        return value["access_token"].string
                    }
                }
                let next = try await refreshTask!.value; refreshTask = nil
                guard !signedOut else { throw ClientError.message("This session has signed out.") }
                try Keychain.save(next, account: baseURL.absoluteString); token = next
                var renewed = request; renewed.setValue("Bearer \(next)", forHTTPHeaderField: "Authorization")
                return try await perform(renewed, retry: false)
            } catch { refreshTask = nil; unauthorized = true; throw error }
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { unauthorized = true }
            let value = (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .null
            let message = value.text("message", "error", "detail", "title").nonEmpty ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw ClientError.http(http.statusCode, message)
        }
        return data
    }
    func socketRequest(_ path: String, query: [String: String] = [:]) async throws -> URLRequest {
        var query = query
        if let officialSession {
            let ticket = try await platformCall("/ws-tickets", method: "POST")
            guard !ticket["ticket"].string.isEmpty else { throw ClientError.invalidResponse }
            query["ticket"] = ticket["ticket"].string
            query["team_id"] = officialSession.teamID
        }
        var r = try request(path, query: query)
        var c = URLComponents(url: r.url!, resolvingAgainstBaseURL: false)!
        c.scheme = c.scheme == "https" ? "wss" : "ws"; r.url = c.url
        return r
    }
    func socket(_ path: String, query: [String: String] = [:]) async throws -> URLSessionWebSocketTask {
        let r = try await socketRequest(path, query: query)
        let socket = session.webSocketTask(with: r); socket.resume(); return socket
    }
    func streamOperation(_ path: String, method: String, query: [String: String] = [:], body: JSONValue?, onEvent: (JSONValue) -> Void) async throws -> JSONValue {
        if isDemo { throw ClientError.message("This operation requires a connected Memoh server.") }
        var request = try request(path, method: method, query: query, body: body)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 1200
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1200; config.timeoutIntervalForResource = 1800
        let streamingSession = URLSession(configuration: config, delegate: SafeRedirectDelegate(), delegateQueue: nil)
        defer { streamingSession.invalidateAndCancel() }
        let (bytes, response) = try await streamingSession.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw ClientError.message("The server rejected the operation. Check your connection and permissions.") }
        var parser = SSEParser()
        var last: JSONValue = .null
        var completed = false
        // AsyncBytes.lines discards blank lines, which delimit SSE events.
        // Parse the bytes so adjacent progress events remain separate frames.
        for try await byte in bytes {
            if let data = parser.consume(byte: byte), let event = try? JSONValue.parse(data) {
                last = event; onEvent(event)
                if event["type"] == "error" { throw ClientError.message(event.text("message", "detail", "code").nonEmpty ?? "The operation failed.") }
                if ["done", "completed", "complete"].contains(event["type"].string) { completed = true }
            }
        }
        guard completed else { throw ClientError.message("The operation stream ended before completion. Refresh its status before retrying.") }
        return last
    }
    func upload(path: String, fileURL: URL, destination: String) async throws -> JSONValue {
        guard !isDemo else { throw ClientError.message("File uploads require a connected Memoh server.") }
        let access = fileURL.startAccessingSecurityScopedResource(); defer { if access { fileURL.stopAccessingSecurityScopedResource() } }
        let file = try Data(contentsOf: fileURL)
        guard file.count <= 50 * 1_024 * 1_024 else { throw ClientError.message("Choose a file smaller than 50 MB.") }
        let boundary = "Homem-\(UUID().uuidString)"
        var data = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"path\"\r\n\r\n\(destination)\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent.replacingOccurrences(of: "\"", with: "_").replacingOccurrences(of: "\r", with: "_").replacingOccurrences(of: "\n", with: "_"))\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8)
        data.append(file); data.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var r = try request(path, method: "POST"); r.httpBody = data
        r.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        return try JSONDecoder().decode(JSONValue.self, from: await perform(r))
    }
}

struct SSEParser {
    private var data: [String] = []
    private var lineBytes: [UInt8] = []
    private var previousWasCR = false
    mutating func consume(byte: UInt8) -> String? {
        if byte == 10, previousWasCR { previousWasCR = false; return nil }
        previousWasCR = byte == 13
        guard byte == 10 || byte == 13 else { lineBytes.append(byte); return nil }
        let line = String(decoding: lineBytes, as: UTF8.self)
        lineBytes.removeAll(keepingCapacity: true)
        return consume(line)
    }
    mutating func consume(_ line: String) -> String? {
        if line.isEmpty {
            guard !data.isEmpty else { return nil }
            defer { data.removeAll(keepingCapacity: true) }
            return data.joined(separator: "\n")
        }
        if line.hasPrefix("data:") {
            var content = String(line.dropFirst(5)); if content.hasPrefix(" ") { content.removeFirst() }; data.append(content)
        }
        return nil
    }
}
