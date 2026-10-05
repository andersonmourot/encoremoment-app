import Foundation

/// The serializable data behind a store: all creators and events keyed by id.
///
/// Holds the shared, validated query/mutation logic so concrete stores
/// (``InMemoryEventStore``, ``FileEventStore``) only handle concurrency and
/// persistence, not business rules.
public struct StoreState: Codable, Sendable, Equatable {
    public var creators: [UUID: Creator]
    public var events: [UUID: Event]
    public var members: [EventMember]
    public var inviteLinks: [EventInviteLink]

    public init(creators: [Creator] = [], events: [Event] = [], members: [EventMember] = [], inviteLinks: [EventInviteLink] = []) {
        self.creators = Dictionary(uniqueKeysWithValues: creators.map { ($0.id, $0) })
        self.events = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
        self.members = members
        self.inviteLinks = inviteLinks
    }

    private enum CodingKeys: String, CodingKey {
        case creators, events, members, inviteLinks
    }

    /// Backward-compatible decode: files written before members/invite links
    /// existed have neither key.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        creators = try container.decode([UUID: Creator].self, forKey: .creators)
        events = try container.decode([UUID: Event].self, forKey: .events)
        members = try container.decodeIfPresent([EventMember].self, forKey: .members) ?? []
        inviteLinks = try container.decodeIfPresent([EventInviteLink].self, forKey: .inviteLinks) ?? []
    }

    // MARK: Queries

    public func allCreators() -> [Creator] {
        creators.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    public func creator(id: UUID) -> Creator? { creators[id] }

    public func publishedEvents() -> [Event] {
        events.values.filter { $0.isPublished }.sorted { $0.date > $1.date }
    }

    public func topCreators(limit: Int) -> [Creator] {
        Array(
            allCreators()
                .sorted { ($0.followerCount ?? 0) > ($1.followerCount ?? 0) }
                .prefix(limit)
        )
    }

    /// Local stores have no follow graph, so `followingOnly` yields nothing.
    public func publishedEventsPage(limit: Int, offset: Int, followingOnly: Bool, popular: Bool) -> [Event] {
        var all = publishedEvents()
        guard !followingOnly else { return [] }
        if popular { all.sort { ($0.likeCount ?? 0) > ($1.likeCount ?? 0) } }
        guard offset < all.count else { return [] }
        return Array(all.dropFirst(offset).prefix(limit))
    }

    /// Cross-event media feed for the Moments rail. Local stores have no like
    /// data, so ordering is recency-only and counts are zero.
    public func mediaFeed(followingOnly: Bool, limit: Int, offset: Int) -> [MediaFeedItem] {
        guard !followingOnly else { return [] }
        let items = publishedEvents().flatMap { event -> [MediaFeedItem] in
            let creatorName = creators[event.creatorId]?.displayName ?? ""
            return event.media.map {
                MediaFeedItem(
                    media: $0, eventID: event.id, eventTitle: event.title,
                    creatorID: event.creatorId, creatorName: creatorName,
                    likeCount: 0, likedByViewer: false
                )
            }
        }
        .sorted { $0.media.createdAt > $1.media.createdAt }
        guard offset < items.count else { return [] }
        return Array(items.dropFirst(offset).prefix(limit))
    }

    public func events(forCreator creatorId: UUID) -> [Event] {
        events.values.filter { $0.creatorId == creatorId }.sorted { $0.date > $1.date }
    }

    public func event(id: UUID) -> Event? { events[id] }

    // MARK: Mutations

    public mutating func upsertCreator(_ creator: Creator) throws {
        guard Creator.isValidHandle(creator.handle) else {
            throw EventStoreError.validation("Invalid handle: \(creator.handle)")
        }
        if creators.values.contains(where: { $0.handle.lowercased() == creator.handle.lowercased() && $0.id != creator.id }) {
            throw EventStoreError.duplicateHandle(creator.handle)
        }
        creators[creator.id] = creator
    }

    public mutating func createEvent(_ event: Event) throws {
        guard Event.isValidTitle(event.title) else {
            throw EventStoreError.validation("Event title must be 1–100 characters.")
        }
        guard creators[event.creatorId] != nil else {
            throw EventStoreError.creatorNotFound(event.creatorId)
        }
        events[event.id] = event
    }

    public mutating func updateEvent(_ event: Event) throws {
        guard events[event.id] != nil else {
            throw EventStoreError.eventNotFound(event.id)
        }
        guard Event.isValidTitle(event.title) else {
            throw EventStoreError.validation("Event title must be 1–100 characters.")
        }
        events[event.id] = event
    }

    public mutating func deleteEvent(id: UUID) throws {
        guard events.removeValue(forKey: id) != nil else {
            throw EventStoreError.eventNotFound(id)
        }
        members.removeAll { $0.eventID == id }
        inviteLinks.removeAll { $0.eventID == id }
    }

    public mutating func addMedia(_ item: MediaItem, toEvent eventId: UUID) throws {
        guard var event = events[eventId] else {
            throw EventStoreError.eventNotFound(eventId)
        }
        guard item.eventId == eventId else {
            throw EventStoreError.validation("Media item's eventId does not match the target event.")
        }
        var item = item
        item.sortOrder = event.media.count
        event.media.append(item)
        events[eventId] = event
    }

    public mutating func removeMedia(id: UUID, fromEvent eventId: UUID) throws {
        guard var event = events[eventId] else {
            throw EventStoreError.eventNotFound(eventId)
        }
        guard event.media.contains(where: { $0.id == id }) else {
            throw EventStoreError.mediaNotFound(id)
        }
        event.media.removeAll { $0.id == id }
        events[eventId] = event
    }

    // MARK: Members

    public func members(of eventID: UUID) -> [EventMember] {
        members.filter { $0.eventID == eventID }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    public func memberRole(creatorID: UUID, in eventID: UUID) -> EventMemberRole? {
        members.first { $0.eventID == eventID && $0.creatorID == creatorID }?.role
    }

    /// Invites (or re-roles) the creator identified by `handle`.
    @discardableResult
    public mutating func inviteMember(handle: String, role: EventMemberRole, to eventID: UUID) throws -> [EventMember] {
        guard events[eventID] != nil else { throw EventStoreError.eventNotFound(eventID) }
        guard let creator = creators.values.first(where: { $0.handle.lowercased() == handle.lowercased() }) else {
            throw EventStoreError.validation("No creator found with handle \"\(handle)\".")
        }
        guard creator.id != events[eventID]?.creatorId else {
            throw EventStoreError.validation("You can't invite the event's owner.")
        }
        if let index = members.firstIndex(where: { $0.eventID == eventID && $0.creatorID == creator.id }) {
            members[index].role = role
        } else {
            members.append(EventMember(
                eventID: eventID, creatorID: creator.id, role: role,
                displayName: creator.displayName, handle: creator.handle
            ))
        }
        return members(of: eventID)
    }

    @discardableResult
    public mutating func removeMember(creatorID: UUID, from eventID: UUID) throws -> [EventMember] {
        members.removeAll { $0.eventID == eventID && $0.creatorID == creatorID }
        return members(of: eventID)
    }

    // MARK: Invite links

    @discardableResult
    public mutating func createInviteLink(role: EventMemberRole, for eventID: UUID) throws -> EventInviteLink {
        guard events[eventID] != nil else { throw EventStoreError.eventNotFound(eventID) }
        let link = EventInviteLink(code: Self.newInviteCode(), eventID: eventID, role: role)
        inviteLinks.append(link)
        return link
    }

    public func inviteLinkPreview(code: String) throws -> InviteLinkPreview {
        guard let link = inviteLinks.first(where: { $0.code == code }),
              let event = events[link.eventID] else {
            throw EventStoreError.eventNotFound(UUID())
        }
        return InviteLinkPreview(eventID: event.id, eventTitle: event.title, role: link.role)
    }

    /// Redeems a link as `creatorID` — joins the event (or re-roles an existing
    /// membership) and returns the event.
    @discardableResult
    public mutating func redeemInviteLink(code: String, as creatorID: UUID) throws -> Event {
        guard let link = inviteLinks.first(where: { $0.code == code }) else {
            throw EventStoreError.validation("Invite link is invalid or expired.")
        }
        guard let event = events[link.eventID] else { throw EventStoreError.eventNotFound(link.eventID) }
        guard let creator = creators[creatorID] else { throw EventStoreError.creatorNotFound(creatorID) }
        guard creator.id != event.creatorId else {
            throw EventStoreError.validation("You already own this event.")
        }
        if let index = members.firstIndex(where: { $0.eventID == link.eventID && $0.creatorID == creatorID }) {
            members[index].role = link.role
        } else {
            members.append(EventMember(
                eventID: link.eventID, creatorID: creatorID, role: link.role,
                displayName: creator.displayName, handle: creator.handle
            ))
        }
        return event
    }

    private static func newInviteCode() -> String {
        let bytes = (0..<16).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
