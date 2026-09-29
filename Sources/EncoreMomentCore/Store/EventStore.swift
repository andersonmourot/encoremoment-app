import Foundation

/// Errors surfaced by an ``EventStore``.
public enum EventStoreError: Error, Equatable, Sendable {
    case eventNotFound(UUID)
    case creatorNotFound(UUID)
    case mediaNotFound(UUID)
    case duplicateHandle(String)
    case validation(String)
}

/// Abstraction over the backend that persists creators, events and media.
///
/// The app talks only to this protocol, so the in-memory implementation used today
/// can be swapped for a networked (REST/GraphQL) implementation later without
/// touching the UI layer.
public protocol EventStore: Sendable {
    // Creators
    func allCreators() async throws -> [Creator]
    func creator(id: UUID) async throws -> Creator?
    func upsertCreator(_ creator: Creator) async throws

    // Events
    /// All published events, intended for the public Discover feed.
    func publishedEvents() async throws -> [Event]
    /// Every event owned by a creator, including unpublished drafts.
    func events(forCreator creatorId: UUID) async throws -> [Event]
    func event(id: UUID) async throws -> Event?
    func createEvent(_ event: Event) async throws
    func updateEvent(_ event: Event) async throws
    func deleteEvent(id: UUID) async throws

    // Media
    func addMedia(_ item: MediaItem, toEvent eventId: UUID) async throws
    func removeMedia(id: UUID, fromEvent eventId: UUID) async throws
}
