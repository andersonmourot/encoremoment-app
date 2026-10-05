import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Minimal HTTP abstraction used by ``APIEventStore``.
///
/// Injecting this (rather than `URLSession` directly) keeps the store testable
/// without `URLProtocol`, which is unreliable on non-Apple platforms.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Default `URLSession`-backed transport.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response): (Data, URLResponse) = try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, let response {
                    continuation.resume(returning: (data, response))
                } else {
                    continuation.resume(throwing: APIError.invalidResponse)
                }
            }
            task.resume()
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        return (data, http)
    }
}

/// Errors raised by the networking layer.
public enum APIError: Error, Equatable, Sendable {
    case invalidResponse
    case http(status: Int)
    case decoding(String)
}

/// A transport wrapper that honors `ETag`/`If-None-Match` on GET requests.
///
/// Cached entries are keyed by URL plus the Authorization header, so a signed-in
/// user's filtered responses never leak into anonymous or other users' caches.
/// A 304 rewrites itself into a 200 with the cached body, so callers see no
/// difference versus a plain fetch.
public actor ETagCachingTransport: HTTPTransport {
    private struct Entry: Sendable {
        let etag: String
        let body: Data
        let status: Int
    }

    private let wrapped: HTTPTransport
    private var cache: [String: Entry] = [:]

    public init(wrapping transport: HTTPTransport) {
        self.wrapped = transport
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard request.httpMethod == "GET", let url = request.url else {
            return try await wrapped.send(request)
        }
        let key = "\(url.absoluteString)|\(request.value(forHTTPHeaderField: "Authorization") ?? "")"
        var outgoing = request
        if let entry = cache[key] {
            outgoing.setValue(entry.etag, forHTTPHeaderField: "If-None-Match")
        }
        let (data, response) = try await wrapped.send(outgoing)
        if response.statusCode == 304, let entry = cache[key],
           let fresh = HTTPURLResponse(
               url: url, statusCode: entry.status,
               httpVersion: nil, headerFields: nil
           ) {
            return (entry.body, fresh)
        }
        if (200..<300).contains(response.statusCode),
           let etag = response.value(forHTTPHeaderField: "ETag") {
            cache[key] = Entry(etag: etag, body: data, status: response.statusCode)
        }
        return (data, response)
    }

    /// Drops every cached entry (e.g. after a mutating action you know changed
    /// the payload, or on sign-in/out).
    public func invalidateAll() {
        cache.removeAll()
    }
}
