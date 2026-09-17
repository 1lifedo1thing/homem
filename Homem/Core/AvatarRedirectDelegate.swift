import Foundation

/// Images may redirect to object storage. API sessions still reject all redirects.
final class AvatarRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static func redirectedRequest(_ request: URLRequest, from previousURL: URL, originalRequest: URLRequest? = nil) -> URLRequest? {
        guard let next = request.url,
              ["https", "http"].contains(next.scheme?.lowercased() ?? ""),
              next.user == nil, next.password == nil,
              !(previousURL.scheme == "https" && next.scheme != "https") else { return nil }
        // Construct a fresh request: assigning an empty header dictionary can retain
        // existing fields in Foundation. Never carry authentication to object storage.
        var safe = URLRequest(url: next, cachePolicy: request.cachePolicy, timeoutInterval: request.timeoutInterval)
        let authenticated = originalRequest ?? request
        if let origin = authenticated.url,
           next.scheme == previousURL.scheme, next.host == previousURL.host, next.port == previousURL.port,
           next.scheme == origin.scheme, next.host == origin.host, next.port == origin.port {
            safe.allHTTPHeaderFields = authenticated.allHTTPHeaderFields
        }
        safe.setValue("image/*", forHTTPHeaderField: "Accept")
        return safe
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let previousURL = response.url else { completionHandler(nil); return }
        completionHandler(Self.redirectedRequest(request, from: previousURL, originalRequest: task.originalRequest))
    }
}
