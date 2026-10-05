import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A ``SocialStore`` backed by the REST API.
///
/// ## Endpoint contract
/// ```
/// GET    /events/{id}/comments                (public)        -> [Comment]
/// POST   /events/{id}/comments                (auth)          -> Comment    { "body": "..." }
/// DELETE /events/{id}/comments/{commentId}    (auth)          -> 204
/// GET    /events/{id}/comments/{commentId}/likes             -> LikeSummary
/// POST   /events/{id}/comments/{commentId}/like              -> LikeSummary
/// DELETE /events/{id}/comments/{commentId}/like              -> LikeSummary
/// GET    /events/{id}/media/{mediaId}/likes                  -> LikeSummary
/// POST   /events/{id}/media/{mediaId}/like                   -> LikeSummary
/// DELETE /events/{id}/media/{mediaId}/like                   -> LikeSummary
/// GET    /events/{id}/likes                   (optional auth) -> LikeSummary
/// POST   /events/{id}/like                    (auth)          -> LikeSummary
/// DELETE /events/{id}/like                    (auth)          -> LikeSummary
/// ```
/// Like/comment writes need a bearer token, supplied by the app's
/// ``AuthenticatedTransport``; reads work anonymously.
public actor APISocialStore: SocialStore {
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

    private struct CommentBody: Encodable { let body: String }

    public func comments(forEvent eventID: UUID) async throws -> [Comment] {
        try await request("events/\(eventID.uuidString)/comments", method: "GET")
    }

    @discardableResult
    public func addComment(eventID: UUID, body: String) async throws -> Comment {
        try await request(
            "events/\(eventID.uuidString)/comments",
            method: "POST",
            body: CommentBody(body: body)
        )
    }

    public func deleteComment(id: UUID, eventID: UUID) async throws {
        try await send("events/\(eventID.uuidString)/comments/\(id.uuidString)", method: "DELETE")
    }

    public func commentLikeSummary(commentID: UUID, eventID: UUID) async throws -> LikeSummary {
        try await request("events/\(eventID.uuidString)/comments/\(commentID.uuidString)/likes", method: "GET")
    }

    @discardableResult
    public func setCommentLike(commentID: UUID, eventID: UUID, _ liked: Bool) async throws -> LikeSummary {
        try await request(
            "events/\(eventID.uuidString)/comments/\(commentID.uuidString)/like",
            method: liked ? "POST" : "DELETE"
        )
    }

    public func mediaLikeSummary(mediaID: UUID, eventID: UUID) async throws -> LikeSummary {
        try await request("events/\(eventID.uuidString)/media/\(mediaID.uuidString)/likes", method: "GET")
    }

    @discardableResult
    public func setMediaLike(mediaID: UUID, eventID: UUID, _ liked: Bool) async throws -> LikeSummary {
        try await request(
            "events/\(eventID.uuidString)/media/\(mediaID.uuidString)/like",
            method: liked ? "POST" : "DELETE"
        )
    }

    public func likeSummary(forEvent eventID: UUID) async throws -> LikeSummary {
        try await request("events/\(eventID.uuidString)/likes", method: "GET")
    }

    public func likeSummaries(forEvent eventID: UUID) async throws -> EventLikeSummaries {
        try await request("events/\(eventID.uuidString)/likes/all", method: "GET")
    }

    @discardableResult
    public func setLike(eventID: UUID, _ liked: Bool) async throws -> LikeSummary {
        try await request("events/\(eventID.uuidString)/like", method: liked ? "POST" : "DELETE")
    }

    // MARK: Helpers

    private func makeRequest(_ path: String, method: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        return request
    }

    /// Sends a request expecting no response body.
    private func send(_ path: String, method: String) async throws {
        let (_, http) = try await transport.send(makeRequest(path, method: method))
        try Self.validate(http)
    }

    /// Sends a request and decodes a JSON response.
    private func request<T: Decodable>(_ path: String, method: String) async throws -> T {
        let (data, http) = try await transport.send(makeRequest(path, method: method))
        try Self.validate(http)
        return try decode(data)
    }

    /// Sends a request with a JSON body and decodes a JSON response.
    private func request<Body: Encodable, T: Decodable>(_ path: String, method: String, body: Body) async throws -> T {
        var request = makeRequest(path, method: method)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        let (data, http) = try await transport.send(request)
        try Self.validate(http)
        return try decode(data)
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
