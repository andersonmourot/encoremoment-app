import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// An ``EventStore`` backed by a REST API. This is the drop-in replacement for the
/// local stores once a real backend exists — the UI does not change, only the
/// store injected into `AppModel`.
///
/// ## Endpoint contract
/// All bodies are JSON with ISO-8601 dates.
/// ```
/// GET    /creators
/// GET    /creators/{id}
/// PUT    /creators/{id}            body: Creator
/// GET    /events?published=true
/// GET    /events?creator={id}
/// GET    /events/{id}
/// POST   /events                   body: Event
/// PUT    /events/{id}              body: Event
/// DELETE /events/{id}
/// POST   /events/{id}/media        body: MediaItem
/// DELETE /events/{id}/media/{mediaId}
/// ```
public actor APIEventStore: EventStore {
    private let baseURL: URL
    private let transport: HTTPTransport
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(baseURL: URL, transport: HTTPTransport = URLSessionTransport()) {
        self.baseURL = baseURL
        self.transport = transport

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    // MARK: Creators

    public func allCreators() async throws -> [Creator] {
        try await get("creators")
    }

    public func creator(id: UUID) async throws -> Creator? {
        try await getOptional("creators/\(id.uuidString)")
    }

    public func upsertCreator(_ creator: Creator) async throws {
        try await send("PUT", "creators/\(creator.id.uuidString)", body: creator)
    }

    // MARK: Events

    public func publishedEvents() async throws -> [Event] {
        try await get("events", query: [URLQueryItem(name: "published", value: "true")])
    }

    public func events(forCreator creatorId: UUID) async throws -> [Event] {
        try await get("events", query: [URLQueryItem(name: "creator", value: creatorId.uuidString)])
    }

    public func event(id: UUID) async throws -> Event? {
        try await getOptional("events/\(id.uuidString)")
    }

    public func createEvent(_ event: Event) async throws {
        try await send("POST", "events", body: event)
    }

    public func updateEvent(_ event: Event) async throws {
        try await send("PUT", "events/\(event.id.uuidString)", body: event)
    }

    public func deleteEvent(id: UUID) async throws {
        try await send("DELETE", "events/\(id.uuidString)")
    }

    // MARK: Media

    public func addMedia(_ item: MediaItem, toEvent eventId: UUID) async throws {
        try await send("POST", "events/\(eventId.uuidString)/media", body: item)
    }

    public func removeMedia(id: UUID, fromEvent eventId: UUID) async throws {
        try await send("DELETE", "events/\(eventId.uuidString)/media/\(id.uuidString)")
    }

    // MARK: Request helpers

    private func url(_ path: String, query: [URLQueryItem]) -> URL {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty { components.queryItems = query }
        return components.url!
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var request = URLRequest(url: url(path, query: query))
        request.httpMethod = "GET"
        let (data, http) = try await transport.send(request)
        try Self.validate(http)
        return try decode(data)
    }

    /// GET that returns `nil` on a 404 instead of throwing (used for single-resource fetches).
    private func getOptional<T: Decodable>(_ path: String) async throws -> T? {
        var request = URLRequest(url: url(path, query: []))
        request.httpMethod = "GET"
        let (data, http) = try await transport.send(request)
        if http.statusCode == 404 { return nil }
        try Self.validate(http)
        return try decode(data)
    }

    private func send<Body: Encodable>(_ method: String, _ path: String, body: Body) async throws {
        var request = URLRequest(url: url(path, query: []))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        let (_, http) = try await transport.send(request)
        try Self.validate(http)
    }

    private func send(_ method: String, _ path: String) async throws {
        var request = URLRequest(url: url(path, query: []))
        request.httpMethod = method
        let (_, http) = try await transport.send(request)
        try Self.validate(http)
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
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
