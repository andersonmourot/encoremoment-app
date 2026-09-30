import Vapor
import Fluent
import Foundation
import EncoreMomentCore

/// Per-event access control for invite-only events and invited collaborators.
enum EventAccess {
    /// Whether the (optionally authenticated) viewer may see this event.
    /// Invite-only events are visible to the owner and invited members only.
    static func canView(_ event: EventModel, on req: Request) async throws -> Bool {
        guard event.inviteOnly else { return true }
        guard let creatorId = req.auth.get(UserToken.self)?.creatorId else { return false }
        if creatorId == event.creatorId { return true }
        return try await EventMemberModel.query(on: req.db)
            .filter(\.$eventId == event.requireID())
            .filter(\.$creatorId == creatorId)
            .first() != nil
    }

    /// Whether the viewer may contribute media: the owner, an invited
    /// collaborator, or anyone signed in when community uploads are enabled.
    static func canUpload(_ event: EventModel, token: UserToken, on db: Database) async throws -> Bool {
        if token.creatorId == event.creatorId { return true }
        if event.allowsCommunityUploads { return true }
        return try await isCollaborator(event, creatorId: token.creatorId, on: db)
    }

    /// Whether media from this uploader lands in the official section
    /// (event owner or invited collaborator).
    static func isOfficialUploader(_ event: EventModel, token: UserToken, on db: Database) async throws -> Bool {
        if token.creatorId == event.creatorId { return true }
        return try await isCollaborator(event, creatorId: token.creatorId, on: db)
    }

    /// Event ids the creator is an invited member of (for feed filtering).
    static func memberEventIDs(for creatorId: UUID, on db: Database) async throws -> Set<UUID> {
        let rows = try await EventMemberModel.query(on: db).filter(\.$creatorId == creatorId).all()
        return Set(rows.map(\.eventId))
    }

    private static func isCollaborator(_ event: EventModel, creatorId: UUID?, on db: Database) async throws -> Bool {
        guard let creatorId else { return false }
        let member = try await EventMemberModel.query(on: db)
            .filter(\.$eventId == event.requireID())
            .filter(\.$creatorId == creatorId)
            .first()
        return member?.memberRole == .collaborator
    }
}
