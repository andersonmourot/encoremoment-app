import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// An ``AnalyticsStore`` backed by the REST API.
///
/// ## Endpoint contract
/// ```
/// POST /events/{id}/view               (public)         -> 204
/// POST /events/{id}/download?count=N   (public)         -> 204
/// GET  /events/{id}/stats              (creator-owner)  -> EventStats
/// GET  /me/stats                       (creator)        -> [EventStats]
/// ```
/// The read routes require an authenticated transport (the app wraps
/// ``AuthenticatedTransport``); the increment routes are anonymous.
public actor APIAnalyticsStore: AnalyticsStore {
    private let baseURL: URL
    private let transport: HTTPTransport
    private let decoder = JSONDecoder()

    public init(baseURL: URL, transport: HTTPTransport = URLSessionTransport()) {
        self.baseURL = baseURL
        self.transport = transport
    }

    public func recordView(eventID: UUID) async throws {
        try await post("events/\(eventID.uuidString)/view")
    }

    public func recordDownloads(eventID: UUID, count: Int) async throws {
        guard count > 0 else { return }
        try await post(
            "events/\(eventID.uuidString)/download",
            query: [URLQueryItem(name: "count", value: String(count))]
        )
    }

    public func stats(forEvent eventID: UUID) async throws -> EventStats {
        try await get("events/\(eventID.uuidString)/stats")
    }

    public func creatorStats() async throws -> [EventStats] {
        try await get("me/stats")
    }

    // MARK: Helpers

    private func url(_ path: String, query: [URLQueryItem]) -> URL {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty { components.queryItems = query }
        return components.url!
    }

    private func post(_ path: String, query: [URLQueryItem] = []) async throws {
        var request = URLRequest(url: url(path, query: query))
        request.httpMethod = "POST"
        let (_, http) = try await transport.send(request)
        try Self.validate(http)
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        var request = URLRequest(url: url(path, query: []))
        request.httpMethod = "GET"
        let (data, http) = try await transport.send(request)
        try Self.validate(http)
        do {
            return try decoder.decode(T.self, from: data)
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
