import Foundation

/// An in-memory ``EventStore`` used for development, previews and tests.
///
/// Backed by an actor wrapping ``StoreState`` so concurrent access from the UI is safe.
/// Seed it with ``SampleData`` for a populated experience, or start empty.
public actor InMemoryEventStore: EventStore {
    private var state: StoreState

    public init(creators: [Creator] = [], events: [Event] = []) {
        self.state = StoreState(creators: creators, events: events)
    }

    public init(state: StoreState) {
        self.state = state
    }

    // MARK: Creators

    public func allCreators() async throws -> [Creator] { state.allCreators() }
    public func creator(id: UUID) async throws -> Creator? { state.creator(id: id) }
    public func upsertCreator(_ creator: Creator) async throws { try state.upsertCreator(creator) }

    // MARK: Events

    public func publishedEvents() async throws -> [Event] { state.publishedEvents() }
    public func events(forCreator creatorId: UUID) async throws -> [Event] { state.events(forCreator: creatorId) }
    public func event(id: UUID) async throws -> Event? { state.event(id: id) }
    public func createEvent(_ event: Event) async throws { try state.createEvent(event) }
    public func updateEvent(_ event: Event) async throws { try state.updateEvent(event) }
    public func deleteEvent(id: UUID) async throws { try state.deleteEvent(id: id) }

    // MARK: Media

    public func addMedia(_ item: MediaItem, toEvent eventId: UUID) async throws {
        try state.addMedia(item, toEvent: eventId)
    }
    public func removeMedia(id: UUID, fromEvent eventId: UUID) async throws {
        try state.removeMedia(id: id, fromEvent: eventId)
    }
}
