import Foundation

/// An in-memory ``EventStore`` used for development, previews and tests.
///
/// Backed by an actor wrapping ``StoreState`` so concurrent access from the UI is safe.
/// Seed it with ``SampleData`` for a populated experience, or start empty.
public actor InMemoryEventStore: EventStore {
    private var state: StoreState
    /// The creator profile acting as the local viewer — used to answer
    /// `myMembership` in tests and previews (the real answer lives server-side).
    public var viewerCreatorID: UUID?

    public init(creators: [Creator] = [], events: [Event] = [], members: [EventMember] = [], viewerCreatorID: UUID? = nil) {
        self.state = StoreState(creators: creators, events: events, members: members)
        self.viewerCreatorID = viewerCreatorID
    }

    public init(state: StoreState, viewerCreatorID: UUID? = nil) {
        self.state = state
        self.viewerCreatorID = viewerCreatorID
    }

    // MARK: Creators

    public func allCreators() async throws -> [Creator] { state.allCreators() }
    public func topCreators(limit: Int) async throws -> [Creator] { state.topCreators(limit: limit) }
    public func creator(id: UUID) async throws -> Creator? { state.creator(id: id) }
    public func upsertCreator(_ creator: Creator) async throws { try state.upsertCreator(creator) }

    // MARK: Events

    public func publishedEvents() async throws -> [Event] { state.publishedEvents() }
    public func publishedEventsPage(limit: Int, offset: Int, followingOnly: Bool, popular: Bool) async throws -> [Event] {
        state.publishedEventsPage(limit: limit, offset: offset, followingOnly: followingOnly, popular: popular)
    }
    public func mediaFeed(followingOnly: Bool, limit: Int, offset: Int) async throws -> [MediaFeedItem] {
        state.mediaFeed(followingOnly: followingOnly, limit: limit, offset: offset)
    }
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

    // MARK: Members

    public func members(of eventID: UUID) async throws -> [EventMember] { state.members(of: eventID) }

    public func myMembership(in eventID: UUID) async throws -> EventMemberRole? {
        guard let viewerCreatorID else { return nil }
        return state.memberRole(creatorID: viewerCreatorID, in: eventID)
    }

    @discardableResult
    public func inviteMember(handle: String, role: EventMemberRole, to eventID: UUID) async throws -> [EventMember] {
        try state.inviteMember(handle: handle, role: role, to: eventID)
    }

    @discardableResult
    public func removeMember(creatorID: UUID, from eventID: UUID) async throws -> [EventMember] {
        try state.removeMember(creatorID: creatorID, from: eventID)
    }

    // MARK: Invite links

    public func createInviteLink(role: EventMemberRole, for eventID: UUID) async throws -> EventInviteLink {
        try state.createInviteLink(role: role, for: eventID)
    }

    public func inviteLinkPreview(code: String) async throws -> InviteLinkPreview {
        try state.inviteLinkPreview(code: code)
    }

    public func redeemInviteLink(code: String) async throws -> Event {
        guard let viewerCreatorID else {
            throw EventStoreError.validation("Sign in to redeem an invite link.")
        }
        return try state.redeemInviteLink(code: code, as: viewerCreatorID)
    }
}
