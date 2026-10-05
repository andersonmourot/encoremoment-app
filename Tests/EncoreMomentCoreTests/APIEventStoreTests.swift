import XCTest
@testable import EncoreMomentCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A transport that answers requests from a closure and records what it was asked.
private final class MockTransport: HTTPTransport, @unchecked Sendable {
    typealias Handler = (URLRequest) throws -> (Int, Data)
    private let handler: Handler
    private(set) var requests: [URLRequest] = []

    init(_ handler: @escaping Handler) { self.handler = handler }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let (status, data) = try handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}

final class APIEventStoreTests: XCTestCase {
    private let baseURL = URL(string: "https://api.encoremoment.app/v1")!

    private func encodedEvents(_ events: [Event]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(events)
    }

    func testPublishedEventsHitsCorrectEndpointAndDecodes() async throws {
        let sample = SampleData.events
        let payload = try encodedEvents(sample)
        let transport = MockTransport { _ in (200, payload) }
        let store = APIEventStore(baseURL: baseURL, transport: transport)

        let events = try await store.publishedEvents()
        XCTAssertEqual(events.count, sample.count)

        let req = transport.requests.first!
        XCTAssertEqual(req.httpMethod, "GET")
        XCTAssertEqual(req.url?.path, "/v1/events")
        XCTAssertEqual(req.url?.query, "published=true&limit=500&offset=0")
    }

    func testEventsForCreatorQuery() async throws {
        let transport = MockTransport { _ in (200, try self.encodedEvents([])) }
        let store = APIEventStore(baseURL: baseURL, transport: transport)
        _ = try await store.events(forCreator: SampleData.aurora.id)
        XCTAssertEqual(transport.requests.first?.url?.query, "creator=\(SampleData.aurora.id.uuidString)")
    }

    func testCreateEventPostsEncodedBody() async throws {
        let transport = MockTransport { _ in (201, Data()) }
        let store = APIEventStore(baseURL: baseURL, transport: transport)
        let event = Event(creatorId: SampleData.aurora.id, title: "API Event")
        try await store.createEvent(event)

        let req = transport.requests.first!
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.url?.path, "/v1/events")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sent = try decoder.decode(Event.self, from: req.httpBody ?? Data())
        XCTAssertEqual(sent.title, "API Event")
    }

    func testEventNotFoundReturnsNil() async throws {
        let transport = MockTransport { _ in (404, Data()) }
        let store = APIEventStore(baseURL: baseURL, transport: transport)
        let event = try await store.event(id: UUID())
        XCTAssertNil(event)
    }

    func testServerErrorThrows() async {
        let transport = MockTransport { _ in (500, Data()) }
        let store = APIEventStore(baseURL: baseURL, transport: transport)
        do {
            _ = try await store.publishedEvents()
            XCTFail("Expected http error")
        } catch let error as APIError {
            XCTAssertEqual(error, .http(status: 500))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDeleteEventSendsDelete() async throws {
        let transport = MockTransport { _ in (204, Data()) }
        let store = APIEventStore(baseURL: baseURL, transport: transport)
        let id = UUID()
        try await store.deleteEvent(id: id)
        let req = transport.requests.first!
        XCTAssertEqual(req.httpMethod, "DELETE")
        XCTAssertEqual(req.url?.path, "/v1/events/\(id.uuidString)")
    }

    func testRemoveMediaPath() async throws {
        let transport = MockTransport { _ in (204, Data()) }
        let store = APIEventStore(baseURL: baseURL, transport: transport)
        let eventId = UUID()
        let mediaId = UUID()
        try await store.removeMedia(id: mediaId, fromEvent: eventId)
        XCTAssertEqual(
            transport.requests.first?.url?.path,
            "/v1/events/\(eventId.uuidString)/media/\(mediaId.uuidString)"
        )
    }
}
