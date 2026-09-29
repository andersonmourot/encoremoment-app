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
