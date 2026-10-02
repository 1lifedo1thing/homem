#if DEBUG
import Foundation

/// Only the UI test runner opts into this transport. Test responses come from
/// the loopback fixture server; this file compiles to nothing in Release.
@MainActor enum OfficialLoginFixture {
    static func client() -> APIClient? {
        guard ProcessInfo.processInfo.environment["HOMEM_OFFICIAL_LOGIN_FIXTURE"] == "1" else { return nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OfficialLoginFixtureProtocol.self]
        return APIClient(baseURL: OfficialServer.apiURL, session: URLSession(configuration: config), officialSession: OfficialSession(cookies: []))
    }
}

private final class OfficialLoginFixtureProtocol: URLProtocol, @unchecked Sendable {
    private var forwardingTask: URLSessionDataTask?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let original = request.url, original.host == "app.memoh.net",
              let local = URL(string: "http://127.0.0.1:18765" + original.path) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
        }
        var forwarded = request
        forwarded.url = local
        forwardingTask = URLSession.shared.dataTask(with: forwarded) { [weak self] data, response, error in
            guard let self else { return }
            if let error { client?.urlProtocol(self, didFailWithError: error); return }
            guard let response = response as? HTTPURLResponse,
                  let translated = HTTPURLResponse(url: original, statusCode: response.statusCode, httpVersion: nil,
                    headerFields: response.allHeaderFields as? [String: String]) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
            }
            client?.urlProtocol(self, didReceive: translated, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data ?? Data())
            client?.urlProtocolDidFinishLoading(self)
        }
        forwardingTask?.resume()
    }
    override func stopLoading() { forwardingTask?.cancel() }
}
#endif
