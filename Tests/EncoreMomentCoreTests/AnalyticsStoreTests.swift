import XCTest
@testable import EncoreMomentCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class AnalyticsMockTransport: HTTPTransport, @unchecked Sendable {
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

final class AnalyticsStoreTests: XCTestCase {
    func testInMemoryRecordsViewsAndDownloads() async throws {
        let store = InMemoryAnalyticsStore()
        let event = UUID()
        try await store.recordView(eventID: event)
        try await store.recordView(eventID: event)
        try await store.recordDownloads(eventID: event, count: 3)
        try await store.recordDownloads(eventID: event, count: 0) // ignored

        let stats = try await store.stats(forEvent: event)
        XCTAssertEqual(stats.views, 2)
        XCTAssertEqual(stats.downloads, 3)
    }

    func testInMemoryUnknownEventIsZero() async throws {
        let store = InMemoryAnalyticsStore()
        let stats = try await store.stats(forEvent: UUID())
        XCTAssertEqual(stats.views, 0)
        XCTAssertEqual(stats.downloads, 0)
    }

    func testInMemoryCreatorStatsListsAllSeeded() async throws {
        let a = EventStats(eventID: UUID(), views: 5, downloads: 1)
        let b = EventStats(eventID: UUID(), views: 2, downloads: 9)
        let store = InMemoryAnalyticsStore([a, b])
        let all = try await store.creatorStats()
        XCTAssertEqual(Set(all.map(\.eventID)), [a.eventID, b.eventID])
    }

    func testAPIRecordUsesCorrectMethodAndPath() async throws {
        let event = UUID()
        let transport = AnalyticsMockTransport { _ in (204, Data()) }
        let store = APIAnalyticsStore(baseURL: URL(string: "https://api.encoremoment.app")!, transport: transport)

        try await store.recordView(eventID: event)
        XCTAssertEqual(transport.requests.last?.httpMethod, "POST")
        XCTAssertEqual(transport.requests.last?.url?.path, "/events/\(event.uuidString)/view")

        try await store.recordDownloads(eventID: event, count: 4)
        XCTAssertEqual(transport.requests.last?.url?.path, "/events/\(event.uuidString)/download")
        XCTAssertEqual(transport.requests.last?.url?.query, "count=4")
    }

    func testAPIDecodesCreatorStats() async throws {
        let stats = [EventStats(eventID: UUID(), views: 7, downloads: 2)]
        let payload = try JSONEncoder().encode(stats)
        let transport = AnalyticsMockTransport { _ in (200, payload) }
        let store = APIAnalyticsStore(baseURL: URL(string: "https://api.encoremoment.app")!, transport: transport)

        let result = try await store.creatorStats()
        XCTAssertEqual(result, stats)
        XCTAssertEqual(transport.requests.last?.url?.path, "/me/stats")
    }
}
