import Vapor
import Fluent
import Foundation

/// Helpers for enforcing per-user blocks on public read routes. Public routes
/// add `UserToken.authenticator()` (without the guard) so an optional token can
/// drive filtering for signed-in viewers.
enum Moderation {
    /// Creator ids the (optionally authenticated) viewer has blocked.
    static func blockedCreatorIDs(for req: Request) async throws -> Set<UUID> {
        guard let userId = req.auth.get(UserToken.self)?.userId else { return [] }
        return try await blockedCreatorIDs(for: userId, on: req.db)
    }

    static func blockedCreatorIDs(for userId: UUID, on db: Database) async throws -> Set<UUID> {
        let rows = try await BlockModel.query(on: db).filter(\.$userId == userId).all()
        return Set(rows.map(\.creatorId))
    }

    /// User ids whose creators the viewer has blocked — used to hide comments
    /// and community uploads authored by blocked users.
    static func blockedUserIDs(for req: Request) async throws -> Set<UUID> {
        let creatorIds = try await blockedCreatorIDs(for: req)
        if creatorIds.isEmpty { return [] }
        return Set(
            try await UserModel.query(on: req.db)
                .filter(\.$creatorId ~~ Array(creatorIds))
                .all()
                .compactMap(\.id)
        )
    }
}
