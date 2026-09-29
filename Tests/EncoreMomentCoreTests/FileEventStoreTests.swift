import XCTest
@testable import EncoreMomentCore

final class FileEventStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("em-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("store.json")
    }

    func testSeedsAndPersistsOnFirstLaunch() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = try FileEventStore(fileURL: url, seed: SampleData.makeState())
        let events = try await store.publishedEvents()
        XCTAssertEqual(events.count, 3)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testReloadsPersistedStateInNewInstance() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let first = try FileEventStore(fileURL: url, seed: StoreState(creators: [SampleData.aurora]))
        let event = Event(creatorId: SampleData.aurora.id, title: "Persisted Event")
        try await first.createEvent(event)

        // A brand new instance pointing at the same file must see the change.
        let second = try FileEventStore(fileURL: url)
        let reloaded = try await second.event(id: event.id)
        XCTAssertEqual(reloaded?.title, "Persisted Event")
    }

    func testFailedMutationDoesNotPersist() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = try FileEventStore(fileURL: url, seed: StoreState(creators: [SampleData.aurora]))
        // Invalid title should throw and leave nothing behind.
        do {
            try await store.createEvent(Event(creatorId: SampleData.aurora.id, title: "  "))
            XCTFail("Expected validation error")
        } catch {}

        let reloaded = try FileEventStore(fileURL: url)
        let events = try await reloaded.events(forCreator: SampleData.aurora.id)
        XCTAssertTrue(events.isEmpty)
    }

    func testAddMediaPersists() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = try FileEventStore(fileURL: url, seed: SampleData.makeState())
        let eventId = SampleData.events[0].id
        let item = MediaItem(eventId: eventId, kind: .photo, url: URL(string: "https://x/p.jpg")!)
        try await store.addMedia(item, toEvent: eventId)

        let reloaded = try FileEventStore(fileURL: url)
        let event = try await reloaded.event(id: eventId)
        XCTAssertTrue(event?.media.contains(where: { $0.id == item.id }) ?? false)
    }
}
