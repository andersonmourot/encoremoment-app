import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A ``FanPreferencesStore`` backed by the REST API, so a signed-in fan's
/// favorites and follows sync across devices.
///
/// ## Endpoint contract
/// All bodies are JSON. The mutating endpoints return the updated ``FanPreferences``.
/// ```
/// GET    /me/preferences
/// PUT    /me/preferences            body: FanPreferences (union-merge)
/// POST   /me/favorites/{eventId}
/// DELETE /me/favorites/{eventId}
/// POST   /me/follows/{creatorId}
/// DELETE /me/follows/{creatorId}
/// ```
/// Requires an authenticated transport (the app wraps ``AuthenticatedTransport``).
public actor APIFanPreferencesStore: FanPreferencesStore {
    private let baseURL: URL
    private let transport: HTTPTransport
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(baseURL: URL, transport: HTTPTransport = URLSessionTransport()) {
        self.baseURL = baseURL
        self.transport = transport
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    public func preferences() async throws -> FanPreferences {
        try await request("GET", "me/preferences")
    }

    @discardableResult
    public func setFavorite(eventID: UUID, _ isFavorite: Bool) async throws -> FanPreferences {
        try await request(isFavorite ? "POST" : "DELETE", "me/favorites/\(eventID.uuidString)")
    }

    @discardableResult
    public func setFollowing(creatorID: UUID, _ isFollowing: Bool) async throws -> FanPreferences {
        try await request(isFollowing ? "POST" : "DELETE", "me/follows/\(creatorID.uuidString)")
    }

    @discardableResult
    public func merge(_ other: FanPreferences) async throws -> FanPreferences {
        var request = URLRequest(url: baseURL.appendingPathComponent("me/preferences"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(other)
        let (data, http) = try await transport.send(request)
        try Self.validate(http)
        return try decode(data)
    }

    private func request(_ method: String, _ path: String) async throws -> FanPreferences {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        let (data, http) = try await transport.send(request)
        try Self.validate(http)
        return try decode(data)
    }

    private func decode(_ data: Data) throws -> FanPreferences {
        do {
            return try decoder.decode(FanPreferences.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    private static func validate(_ response: HTTPURLResponse) throws {
        guard (200..<300).contains(response.statusCode) else {
            throw APIError.http(status: response.statusCode)
        }
    }
}
