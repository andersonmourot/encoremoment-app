import Foundation

/// What an invited member may do on an event.
public enum EventMemberRole: String, Codable, Sendable, CaseIterable, Identifiable {
    /// May view an invite-only event but cannot upload media.
    case viewer
    /// May view and upload media; their uploads appear in the official section.
    case collaborator

    public var id: String { rawValue }

    /// Whether the role may contribute media to the event.
    public var canUpload: Bool { self == .collaborator }

    public var displayName: String {
        switch self {
        case .viewer: "View only"
        case .collaborator: "Collaborator"
        }
    }
}

/// A person invited to an event by its owner. Members are keyed by creator id
/// (every account has a creator profile), matching follows/blocks.
public struct EventMember: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let eventID: UUID
    public let creatorID: UUID
    public var role: EventMemberRole
    /// Denormalized for display (looked up from the creator profile).
    public var displayName: String
    public var handle: String

    public init(
        id: UUID = UUID(),
        eventID: UUID,
        creatorID: UUID,
        role: EventMemberRole,
        displayName: String,
        handle: String
    ) {
        self.id = id
        self.eventID = eventID
        self.creatorID = creatorID
        self.role = role
        self.displayName = displayName
        self.handle = handle
    }
}

/// Response for `GET /events/{id}/membership` — the caller's own membership,
/// or `nil` when they are not a member.
public struct EventMembershipResponse: Codable, Sendable, Equatable {
    public let member: EventMember?

    public init(member: EventMember?) {
        self.member = member
    }
}

/// Body for `POST /events/{id}/members`.
public struct EventInviteRequest: Codable, Sendable, Equatable {
    public var handle: String
    public var role: EventMemberRole

    public init(handle: String, role: EventMemberRole) {
        self.handle = handle
        self.role = role
    }
}
