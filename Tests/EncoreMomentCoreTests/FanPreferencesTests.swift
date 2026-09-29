import XCTest
@testable import EncoreMomentCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class FanMockTransport: HTTPTransport, @unchecked Sendable {
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

final class FanPreferencesTests: XCTestCase {
    func testFavoriteAndFollowToggling() {
        var prefs = FanPreferences()
        let event = UUID(), creator = UUID()

        XCTAssertFalse(prefs.isFavorite(event))
        prefs.setFavorite(event, true)
        XCTAssertTrue(prefs.isFavorite(event))
        prefs.setFavorite(event, false)
        XCTAssertFalse(prefs.isFavorite(event))

        prefs.setFollowing(creator, true)
        XCTAssertTrue(prefs.isFollowing(creator))
        prefs.setFollowing(creator, false)
        XCTAssertFalse(prefs.isFollowing(creator))

        prefs.setBlocked(creator, true)
        XCTAssertTrue(prefs.isBlocked(creator))
        prefs.setBlocked(creator, false)
        XCTAssertFalse(prefs.isBlocked(creator))
    }

    func testDecodesWithoutBlockedCreatorIDs() throws {
        // Responses/files from older app versions lack blockedCreatorIDs.
        let json = """
        {"favoriteEventIDs":[],"followedCreatorIDs":[]}
        """.data(using: .utf8)!
        let prefs = try JSONDecoder().decode(FanPreferences.self, from: json)
        XCTAssertTrue(prefs.blockedCreatorIDs.isEmpty)
    }

    func testInMemoryStoreRoundTrip() async throws {
        let store = InMemoryFanPreferencesStore()
        let event = UUID()
        let updated = try await store.setFavorite(eventID: event, true)
        XCTAssertTrue(updated.isFavorite(event))
        let reloaded = try await store.preferences()
        XCTAssertEqual(reloaded.favoriteEventIDs, [event])
    }

    func testFileStorePersistsAcrossInstances() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("fan.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let event = UUID(), creator = UUID()
        let store = try FileFanPreferencesStore(fileURL: url)
        try await store.setFavorite(eventID: event, true)
        try await store.setFollowing(creatorID: creator, true)

        let reopened = try FileFanPreferencesStore(fileURL: url)
        let prefs = try await reopened.preferences()
        XCTAssertEqual(prefs.favoriteEventIDs, [event])
        XCTAssertEqual(prefs.followedCreatorIDs, [creator])
    }

    func testDefaultMergeUnionsPreferences() async throws {
        let existing = UUID(), incoming = UUID(), creator = UUID()
        let store = InMemoryFanPreferencesStore(FanPreferences(favoriteEventIDs: [existing]))
        let merged = try await store.merge(FanPreferences(favoriteEventIDs: [incoming], followedCreatorIDs: [creator]))
        XCTAssertEqual(merged.favoriteEventIDs, [existing, incoming])
        XCTAssertEqual(merged.followedCreatorIDs, [creator])
    }

    func testAPIStoreToggleUsesCorrectMethodAndPath() async throws {
        let event = UUID()
        let prefs = FanPreferences(favoriteEventIDs: [event])
        let payload = try JSONEncoder().encode(prefs)
        let transport = FanMockTransport { _ in (200, payload) }
        let store = APIFanPreferencesStore(baseURL: URL(string: "https://api.encoremoment.app")!, transport: transport)

        let added = try await store.setFavorite(eventID: event, true)
        XCTAssertEqual(added.favoriteEventIDs, [event])
        XCTAssertEqual(transport.requests.last?.httpMethod, "POST")
        XCTAssertEqual(transport.requests.last?.url?.path, "/me/favorites/\(event.uuidString)")

        _ = try await store.setFavorite(eventID: event, false)
        XCTAssertEqual(transport.requests.last?.httpMethod, "DELETE")

        _ = try await store.merge(prefs)
        XCTAssertEqual(transport.requests.last?.httpMethod, "PUT")
        XCTAssertEqual(transport.requests.last?.url?.path, "/me/preferences")
    }

    func testAPIStoreBlockUsesCorrectMethodAndPath() async throws {
        let creator = UUID()
        let payload = try JSONEncoder().encode(FanPreferences(blockedCreatorIDs: [creator]))
        let transport = FanMockTransport { _ in (200, payload) }
        let store = APIFanPreferencesStore(baseURL: URL(string: "https://api.encoremoment.app")!, transport: transport)

        let blocked = try await store.setBlocked(creatorID: creator, true)
        XCTAssertEqual(blocked.blockedCreatorIDs, [creator])
        XCTAssertEqual(transport.requests.last?.httpMethod, "POST")
        XCTAssertEqual(transport.requests.last?.url?.path, "/me/blocks/\(creator.uuidString)")

        _ = try await store.setBlocked(creatorID: creator, false)
        XCTAssertEqual(transport.requests.last?.httpMethod, "DELETE")
        XCTAssertEqual(transport.requests.last?.url?.path, "/me/blocks/\(creator.uuidString)")
    }

    func testAPIStoreBlockedCreatorsDecodesList() async throws {
        let creator = Creator(displayName: "Blocked One", handle: "blocked_one")
        let payload = try JSONEncoder().encode([creator])
        let transport = FanMockTransport { _ in (200, payload) }
        let store = APIFanPreferencesStore(baseURL: URL(string: "https://api.encoremoment.app")!, transport: transport)

        let blocked = try await store.blockedCreators()
        XCTAssertEqual(blocked, [creator])
        XCTAssertEqual(transport.requests.last?.httpMethod, "GET")
        XCTAssertEqual(transport.requests.last?.url?.path, "/me/blocks")
    }

    func testFeedFiltersByFavoritesAndFollows() {
        let creatorA = UUID(), creatorB = UUID()
        let e1 = Event(creatorId: creatorA, title: "A1", date: Date(timeIntervalSince1970: 100))
        let e2 = Event(creatorId: creatorB, title: "B1", date: Date(timeIntervalSince1970: 200))
        let e3 = Event(creatorId: creatorA, title: "A2", date: Date(timeIntervalSince1970: 300))
        let events = [e1, e2, e3]

        let followed = EventFeed.events(events, byCreators: [creatorA])
        XCTAssertEqual(Set(followed.map(\.id)), [e1.id, e3.id])

        let favorites = EventFeed.events(events, withIDs: [e1.id, e2.id])
        XCTAssertEqual(favorites.map(\.id), [e2.id, e1.id]) // newest first
    }
}
