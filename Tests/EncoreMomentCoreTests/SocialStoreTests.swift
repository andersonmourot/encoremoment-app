import XCTest
@testable import EncoreMomentCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class SocialMockTransport: HTTPTransport, @unchecked Sendable {
    typealias Handler = (URLRequest) throws -> (Int, Data)
    private let handler: Handler
    private(set) var requests: [URLRequest] = []
    init(_ handler: @escaping Handler) { self.handler = handler }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let (status, data) = try handler(request)
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

final class SocialStoreTests: XCTestCase {
    func testInMemoryAddAndListComments() async throws {
        let store = InMemorySocialStore(viewerName: "DJ Aurora")
        let event = UUID()
        let created = try await store.addComment(eventID: event, body: "  Great set!  ")
        XCTAssertEqual(created.body, "Great set!") // trimmed
        XCTAssertEqual(created.authorName, "DJ Aurora")

        let comments = try await store.comments(forEvent: event)
        XCTAssertEqual(comments.count, 1)
        XCTAssertEqual(comments.first?.body, "Great set!")
    }

    func testInMemoryRejectsEmptyComment() async throws {
        let store = InMemorySocialStore()
        do {
            _ = try await store.addComment(eventID: UUID(), body: "   ")
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? SocialStoreError, .invalidComment)
        }
    }

    func testInMemoryDeleteComment() async throws {
        let store = InMemorySocialStore()
        let event = UUID()
        let c = try await store.addComment(eventID: event, body: "remove me")
        try await store.deleteComment(id: c.id, eventID: event)
        let comments = try await store.comments(forEvent: event)
        XCTAssertTrue(comments.isEmpty)
    }

    func testInMemoryLikeToggle() async throws {
        let store = InMemorySocialStore()
        let event = UUID()
        var summary = try await store.likeSummary(forEvent: event)
        XCTAssertEqual(summary.count, 0)
        XCTAssertFalse(summary.likedByViewer)

        summary = try await store.setLike(eventID: event, true)
        XCTAssertEqual(summary.count, 1)
        XCTAssertTrue(summary.likedByViewer)

        summary = try await store.setLike(eventID: event, false)
        XCTAssertEqual(summary.count, 0)
        XCTAssertFalse(summary.likedByViewer)
    }

    func testAPIAddCommentSendsBodyToCorrectPath() async throws {
        let event = UUID()
        let returned = Comment(eventID: event, authorID: UUID(), authorName: "Me", body: "hello")
        let transport = SocialMockTransport { _ in
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            return (200, try encoder.encode(returned))
        }
        let store = APISocialStore(baseURL: URL(string: "https://api.encoremoment.app")!, transport: transport)
        let result = try await store.addComment(eventID: event, body: "hello")

        XCTAssertEqual(result.body, "hello")
        let req = transport.requests.last!
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.url?.path, "/events/\(event.uuidString)/comments")
        let sent = try JSONSerialization.jsonObject(with: req.httpBody!) as? [String: String]
        XCTAssertEqual(sent?["body"], "hello")
    }

    func testAPILikeUsesPostAndUnlikeUsesDelete() async throws {
        let event = UUID()
        let transport = SocialMockTransport { _ in
            (200, try JSONEncoder().encode(LikeSummary(eventID: event, count: 1, likedByViewer: true)))
        }
        let store = APISocialStore(baseURL: URL(string: "https://api.encoremoment.app")!, transport: transport)

        _ = try await store.setLike(eventID: event, true)
        XCTAssertEqual(transport.requests.last?.httpMethod, "POST")
        XCTAssertEqual(transport.requests.last?.url?.path, "/events/\(event.uuidString)/like")

        _ = try await store.setLike(eventID: event, false)
        XCTAssertEqual(transport.requests.last?.httpMethod, "DELETE")
    }

    func testAPIDeleteCommentUsesDeleteVerbAndPath() async throws {
        let event = UUID()
        let commentID = UUID()
        let transport = SocialMockTransport { _ in (204, Data()) }
        let store = APISocialStore(baseURL: URL(string: "https://api.encoremoment.app")!, transport: transport)

        try await store.deleteComment(id: commentID, eventID: event)
        XCTAssertEqual(transport.requests.last?.httpMethod, "DELETE")
        XCTAssertEqual(transport.requests.last?.url?.path, "/events/\(event.uuidString)/comments/\(commentID.uuidString)")
    }
}
