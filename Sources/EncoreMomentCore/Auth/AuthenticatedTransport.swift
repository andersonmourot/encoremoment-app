import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Wraps another ``HTTPTransport`` and attaches a bearer token (when available)
/// to every request, so ``APIEventStore`` can make authenticated mutations.
///
/// The token is read lazily via a closure so it always reflects the latest
/// signed-in state without rebuilding the store.
public struct AuthenticatedTransport: HTTPTransport {
    private let base: HTTPTransport
    private let tokenProvider: @Sendable () -> String?

    public init(base: HTTPTransport = URLSessionTransport(), tokenProvider: @escaping @Sendable () -> String?) {
        self.base = base
        self.tokenProvider = tokenProvider
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var request = request
        if let token = tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return try await base.send(request)
    }
}
