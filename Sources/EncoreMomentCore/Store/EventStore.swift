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
    /// Most-followed creators, used as the Search tab's default suggestions.
    func topCreators(limit: Int) async throws -> [Creator]
    func creator(id: UUID) async throws -> Creator?
    func upsertCreator(_ creator: Creator) async throws

    // Events
    /// All published events, intended for the public Discover feed.
    func publishedEvents() async throws -> [Event]
    /// A page of published events for the Discover feed. `offset` is the number
    /// of already-loaded events; fewer than `limit` results means no more pages.
    /// `followingOnly` restricts to creators the viewer follows; `popular`
    /// orders by like count (most liked first) instead of date.
    func publishedEventsPage(
        limit: Int,
        offset: Int,
        followingOnly: Bool,
        popular: Bool
    ) async throws -> [Event]
    /// Cross-event media feed (the "Moments" rail) — most-liked first.
    func mediaFeed(followingOnly: Bool, limit: Int, offset: Int) async throws -> [MediaFeedItem]
    /// Every event owned by a creator, including unpublished drafts.
    func events(forCreator creatorId: UUID) async throws -> [Event]
    func event(id: UUID) async throws -> Event?
    func createEvent(_ event: Event) async throws
    func updateEvent(_ event: Event) async throws
    func deleteEvent(id: UUID) async throws

    // Media
    func addMedia(_ item: MediaItem, toEvent eventId: UUID) async throws
    func removeMedia(id: UUID, fromEvent eventId: UUID) async throws

    // Members (invited viewers & collaborators)
    /// Everyone invited to the event (owner-only on the server).
    func members(of eventID: UUID) async throws -> [EventMember]
    /// The signed-in viewer's own membership, or `nil` when not a member.
    func myMembership(in eventID: UUID) async throws -> EventMemberRole?
    /// Invites a creator by handle; returns the updated member list.
    @discardableResult
    func inviteMember(handle: String, role: EventMemberRole, to eventID: UUID) async throws -> [EventMember]
    /// Removes an invited member; returns the updated member list.
    @discardableResult
    func removeMember(creatorID: UUID, from eventID: UUID) async throws -> [EventMember]

    // Invite links
    /// Creates a shareable invite link for an event (owner only).
    func createInviteLink(role: EventMemberRole, for eventID: UUID) async throws -> EventInviteLink
    /// Public preview of an invite link (event title + role) before redeeming.
    func inviteLinkPreview(code: String) async throws -> InviteLinkPreview
    /// Redeems an invite link as the signed-in user; returns the joined event.
    func redeemInviteLink(code: String) async throws -> Event
}
