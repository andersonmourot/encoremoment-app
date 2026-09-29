import XCTest
@testable import EncoreMomentCore

final class EventStoreTests: XCTestCase {
    func testSeededStoreReturnsPublishedEventsSortedByDate() async throws {
        let store = SampleData.makeStore()
        let events = try await store.publishedEvents()
        XCTAssertEqual(events.count, 3)
        // Newest first.
        XCTAssertEqual(events.first?.title, "Summer Fest 2026")
        for i in 1..<events.count {
            XCTAssertGreaterThanOrEqual(events[i - 1].date, events[i].date)
        }
    }

    func testEventsForCreatorAreScoped() async throws {
        let store = SampleData.makeStore()
        let auroraEvents = try await store.events(forCreator: SampleData.aurora.id)
        XCTAssertEqual(auroraEvents.count, 2)
        XCTAssertTrue(auroraEvents.allSatisfy { $0.creatorId == SampleData.aurora.id })
    }

    func testCreateEventRequiresExistingCreator() async {
        let store = InMemoryEventStore()
        let event = Event(creatorId: UUID(), title: "Orphan Event")
        do {
            try await store.createEvent(event)
            XCTFail("Expected creatorNotFound")
        } catch let error as EventStoreError {
            XCTAssertEqual(error, .creatorNotFound(event.creatorId))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCreateEventRejectsEmptyTitle() async throws {
        let store = InMemoryEventStore(creators: [SampleData.aurora])
        let event = Event(creatorId: SampleData.aurora.id, title: "   ")
        do {
            try await store.createEvent(event)
            XCTFail("Expected validation error")
        } catch let error as EventStoreError {
            XCTAssertEqual(error, .validation("Event title must be 1–100 characters."))
        }
    }

    func testAddAndRemoveMedia() async throws {
        let store = InMemoryEventStore(creators: [SampleData.aurora])
        let event = Event(creatorId: SampleData.aurora.id, title: "Empty Event")
        try await store.createEvent(event)

        let item = MediaItem(eventId: event.id, kind: .photo, url: URL(string: "https://x/p.jpg")!)
        try await store.addMedia(item, toEvent: event.id)

        var fetched = try await store.event(id: event.id)
        XCTAssertEqual(fetched?.media.count, 1)

        try await store.removeMedia(id: item.id, fromEvent: event.id)
        fetched = try await store.event(id: event.id)
        XCTAssertEqual(fetched?.media.count, 0)
    }

    func testAddMediaRejectsMismatchedEventId() async throws {
        let store = InMemoryEventStore(creators: [SampleData.aurora])
        let event = Event(creatorId: SampleData.aurora.id, title: "Event")
        try await store.createEvent(event)
        let item = MediaItem(eventId: UUID(), kind: .photo, url: URL(string: "https://x/p.jpg")!)
        do {
            try await store.addMedia(item, toEvent: event.id)
            XCTFail("Expected validation error")
        } catch let error as EventStoreError {
            guard case .validation = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testUpsertCreatorRejectsDuplicateHandle() async throws {
        let store = InMemoryEventStore(creators: [SampleData.aurora])
        let clash = Creator(displayName: "Imposter", handle: SampleData.aurora.handle)
        do {
            try await store.upsertCreator(clash)
            XCTFail("Expected duplicateHandle")
        } catch let error as EventStoreError {
            XCTAssertEqual(error, .duplicateHandle(SampleData.aurora.handle))
        }
    }

    func testDeleteMissingEventThrows() async {
        let store = InMemoryEventStore()
        let id = UUID()
        do {
            try await store.deleteEvent(id: id)
            XCTFail("Expected eventNotFound")
        } catch let error as EventStoreError {
            XCTAssertEqual(error, .eventNotFound(id))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
