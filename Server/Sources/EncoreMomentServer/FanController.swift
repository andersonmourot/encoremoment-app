import Vapor
import Fluent
import EncoreMomentCore

/// Per-account fan preferences (favorites & follows), so they sync across devices.
/// All routes require authentication and act on the token's user.
struct FanController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let me = routes.grouped("me")
            .grouped(UserToken.authenticator(), UserToken.guardMiddleware())

        me.get("preferences", use: preferences)
        me.put("preferences", use: merge)
        me.post("favorites", ":eventId", use: addFavorite)
        me.delete("favorites", ":eventId", use: removeFavorite)
        me.post("follows", ":creatorId", use: addFollow)
        me.delete("follows", ":creatorId", use: removeFollow)
        me.post("blocks", ":creatorId", use: block)
        me.delete("blocks", ":creatorId", use: unblock)
        me.get("blocks", use: listBlocks)
    }

    func preferences(req: Request) async throws -> FanPreferences {
        try await Self.load(for: try userId(req), on: req.db)
    }

    /// Union-merges the posted preferences into the account (used to push local
    /// favorites/follows up on first sign-in). Returns the merged result.
    func merge(req: Request) async throws -> FanPreferences {
        let uid = try userId(req)
        let incoming = try req.content.decode(FanPreferences.self)
        let current = try await Self.load(for: uid, on: req.db)

        for eventId in incoming.favoriteEventIDs.subtracting(current.favoriteEventIDs) {
            try? await FavoriteModel(userId: uid, eventId: eventId).create(on: req.db)
        }
        for creatorId in incoming.followedCreatorIDs.subtracting(current.followedCreatorIDs) {
            try? await FollowModel(userId: uid, creatorId: creatorId).create(on: req.db)
        }
        return try await Self.load(for: uid, on: req.db)
    }

    func addFavorite(req: Request) async throws -> FanPreferences {
        let uid = try userId(req)
        let eventId = try param(req, "eventId")
        let exists = try await FavoriteModel.query(on: req.db)
            .filter(\.$userId == uid).filter(\.$eventId == eventId).first() != nil
        if !exists { try await FavoriteModel(userId: uid, eventId: eventId).create(on: req.db) }
        return try await Self.load(for: uid, on: req.db)
    }

    func removeFavorite(req: Request) async throws -> FanPreferences {
        let uid = try userId(req)
        let eventId = try param(req, "eventId")
        try await FavoriteModel.query(on: req.db)
            .filter(\.$userId == uid).filter(\.$eventId == eventId).delete()
        return try await Self.load(for: uid, on: req.db)
    }

    func addFollow(req: Request) async throws -> FanPreferences {
        let uid = try userId(req)
        let creatorId = try param(req, "creatorId")
        let exists = try await FollowModel.query(on: req.db)
            .filter(\.$userId == uid).filter(\.$creatorId == creatorId).first() != nil
        if !exists {
            try await FollowModel(userId: uid, creatorId: creatorId).create(on: req.db)
            if let followedUser = try await UserModel.query(on: req.db).filter(\.$creatorId == creatorId).first(),
               followedUser.id != uid {
                let name = try await NotificationCenter.actorName(for: uid, on: req.db)
                try await NotificationCenter.notifyCreator(
                    creatorId: creatorId,
                    kind: .follow,
                    title: "New follower",
                    body: "\(name) followed your creator profile.",
                    on: req.db
                )
            }
        }
        return try await Self.load(for: uid, on: req.db)
    }

    func removeFollow(req: Request) async throws -> FanPreferences {
        let uid = try userId(req)
        let creatorId = try param(req, "creatorId")
        try await FollowModel.query(on: req.db)
            .filter(\.$userId == uid).filter(\.$creatorId == creatorId).delete()
        return try await Self.load(for: uid, on: req.db)
    }

    /// Blocks a creator: removes any follow, hides their content from the
    /// caller's feeds, and files a report so the developer is notified.
    func block(req: Request) async throws -> FanPreferences {
        let uid = try userId(req)
        let creatorId = try param(req, "creatorId")
        guard let blocked = try await CreatorModel.find(creatorId, on: req.db) else {
            throw Abort(.notFound, reason: "Creator not found.")
        }
        if let blockedUser = try await UserModel.query(on: req.db).filter(\.$creatorId == creatorId).first(),
           blockedUser.id == uid {
            throw Abort(.badRequest, reason: "You cannot block yourself.")
        }
        let exists = try await BlockModel.query(on: req.db)
            .filter(\.$userId == uid).filter(\.$creatorId == creatorId).first() != nil
        if !exists {
            try await BlockModel(userId: uid, creatorId: creatorId).create(on: req.db)
            // A block also stops following and drops the favorite flags on the
            // blocked creator's events.
            try await FollowModel.query(on: req.db)
                .filter(\.$userId == uid).filter(\.$creatorId == creatorId).delete()
            let blockedEventIds = try await EventModel.query(on: req.db)
                .filter(\.$creatorId == creatorId).all().map(\.id!)
            if !blockedEventIds.isEmpty {
                try await FavoriteModel.query(on: req.db)
                    .filter(\.$userId == uid).filter(\.$eventId ~~ blockedEventIds).delete()
            }
            // Blocking notifies the developer: file a report for review.
            try await ReportModel(
                userId: uid,
                request: ReportRequest(
                    targetType: .creator,
                    targetID: creatorId,
                    eventID: nil,
                    reason: .other,
                    details: "This creator was blocked by a user and is reported for review."
                )
            ).create(on: req.db)
        }
        return try await Self.load(for: uid, on: req.db)
    }

    func unblock(req: Request) async throws -> FanPreferences {
        let uid = try userId(req)
        let creatorId = try param(req, "creatorId")
        try await BlockModel.query(on: req.db)
            .filter(\.$userId == uid).filter(\.$creatorId == creatorId).delete()
        return try await Self.load(for: uid, on: req.db)
    }

    /// The profiles the caller has blocked — needed because `/creators` filters
    /// them out, but Settings still has to list them for unblocking.
    func listBlocks(req: Request) async throws -> [Creator] {
        let uid = try userId(req)
        let creatorIds = try await BlockModel.query(on: req.db)
            .filter(\.$userId == uid).all().map(\.creatorId)
        if creatorIds.isEmpty { return [] }
        return try await CreatorModel.query(on: req.db)
            .filter(\.$id ~~ creatorIds)
            .sort(\.$displayName)
            .all()
            .map { $0.toDTO() }
    }

    // MARK: Helpers

    private func userId(_ req: Request) throws -> UUID {
        try req.auth.require(UserToken.self).requireUserID()
    }

    private func param(_ req: Request, _ name: String) throws -> UUID {
        guard let id = req.parameters.get(name, as: UUID.self) else { throw Abort(.badRequest) }
        return id
    }

    private static func load(for userId: UUID, on db: Database) async throws -> FanPreferences {
        let favorites = try await FavoriteModel.query(on: db).filter(\.$userId == userId).all()
        let follows = try await FollowModel.query(on: db).filter(\.$userId == userId).all()
        let blocks = try await BlockModel.query(on: db).filter(\.$userId == userId).all()
        return FanPreferences(
            favoriteEventIDs: Set(favorites.map(\.eventId)),
            followedCreatorIDs: Set(follows.map(\.creatorId)),
            blockedCreatorIDs: Set(blocks.map(\.creatorId))
        )
    }
}
