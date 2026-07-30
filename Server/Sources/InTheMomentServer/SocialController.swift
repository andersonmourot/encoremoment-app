import Vapor
import Fluent
import InTheMomentCore

/// Comments and likes on events. Reads are public (likes optionally use the
/// token to report the viewer's like state); writes require authentication.
/// Comments may be deleted by their author or the event's owning creator.
struct SocialController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let events = routes.grouped("events")

        // Public reads.
        events.get(":id", "comments", use: listComments)
        events.grouped(UserToken.authenticator()).get(":id", "comments", ":commentId", "likes", use: commentLikeSummary)
        events.grouped(UserToken.authenticator()).get(":id", "media", ":mediaId", "likes", use: mediaLikeSummary)
        // Optional auth: anonymous callers get likedByViewer == false.
        events.grouped(UserToken.authenticator()).get(":id", "likes", use: likeSummary)

        // Authenticated writes.
        let protected = events.grouped(UserToken.authenticator(), UserToken.guardMiddleware())
        protected.post(":id", "comments", use: addComment)
        protected.delete(":id", "comments", ":commentId", use: deleteComment)
        protected.post(":id", "comments", ":commentId", "like", use: likeComment)
        protected.delete(":id", "comments", ":commentId", "like", use: unlikeComment)
        protected.post(":id", "media", ":mediaId", "like", use: likeMedia)
        protected.delete(":id", "media", ":mediaId", "like", use: unlikeMedia)
        protected.post(":id", "like", use: like)
        protected.delete(":id", "like", use: unlike)
    }

    struct CommentBody: Content { let body: String }

    func listComments(req: Request) async throws -> [Comment] {
        let eventId = try id(req)
        let rows = try await CommentModel.query(on: req.db)
            .filter(\.$eventId == eventId)
            .sort(\.$createdAt, .ascending)
            .all()
        return rows.map { $0.toDTO() }
    }

    func addComment(req: Request) async throws -> Comment {
        let token = try req.auth.require(UserToken.self)
        let userId = try token.requireUserID()
        let eventId = try id(req)
        guard let event = try await EventModel.find(eventId, on: req.db) else { throw Abort(.notFound) }

        let text = try req.content.decode(CommentBody.self).body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Comment.isValidBody(text) else {
            throw Abort(.unprocessableEntity, reason: "Comment must be 1–2000 characters.")
        }

        let name = try await Self.authorName(for: userId, on: req.db)
        let model = CommentModel(eventId: eventId, userId: userId, authorName: name, body: text)
        try await model.create(on: req.db)
        if token.creatorId != event.creatorId {
            try await NotificationCenter.notifyCreator(
                creatorId: event.creatorId,
                kind: .comment,
                title: "New comment",
                body: "\(name) commented on \(event.title).",
                eventId: eventId,
                on: req.db
            )
        }
        return model.toDTO()
    }

    func deleteComment(req: Request) async throws -> HTTPStatus {
        let token = try req.auth.require(UserToken.self)
        let userId = try token.requireUserID()
        let eventId = try id(req)
        guard let commentId = req.parameters.get("commentId", as: UUID.self) else { throw Abort(.badRequest) }
        guard let comment = try await CommentModel.find(commentId, on: req.db), comment.eventId == eventId else {
            throw Abort(.notFound)
        }

        let isAuthor = comment.userId == userId
        let isEventOwner: Bool
        if let creatorId = token.creatorId, let event = try await EventModel.find(eventId, on: req.db) {
            isEventOwner = event.creatorId == creatorId
        } else {
            isEventOwner = false
        }
        guard isAuthor || isEventOwner else { throw Abort(.forbidden) }

        try await comment.delete(on: req.db)
        return .noContent
    }

    func likeSummary(req: Request) async throws -> LikeSummary {
        let eventId = try id(req)
        guard try await EventModel.find(eventId, on: req.db) != nil else { throw Abort(.notFound) }
        let viewerId = req.auth.get(UserToken.self)?.userId
        return try await Self.summary(eventId: eventId, viewerId: viewerId, on: req.db)
    }

    func like(req: Request) async throws -> LikeSummary {
        let token = try req.auth.require(UserToken.self)
        let userId = try token.requireUserID()
        let eventId = try id(req)
        guard let event = try await EventModel.find(eventId, on: req.db) else { throw Abort(.notFound) }

        let existing = try await EventLikeModel.query(on: req.db)
            .filter(\.$eventId == eventId)
            .filter(\.$userId == userId)
            .first()
        if existing == nil {
            try await EventLikeModel(eventId: eventId, userId: userId).create(on: req.db)
            if token.creatorId != event.creatorId {
                try await NotificationCenter.notifyCreator(
                    creatorId: event.creatorId,
                    kind: .like,
                    title: "New like",
                    body: "Someone liked \(event.title).",
                    eventId: eventId,
                    on: req.db
                )
            }
        }
        return try await Self.summary(eventId: eventId, viewerId: userId, on: req.db)
    }

    func unlike(req: Request) async throws -> LikeSummary {
        let token = try req.auth.require(UserToken.self)
        let userId = try token.requireUserID()
        let eventId = try id(req)
        try await EventLikeModel.query(on: req.db)
            .filter(\.$eventId == eventId)
            .filter(\.$userId == userId)
            .delete()
        return try await Self.summary(eventId: eventId, viewerId: userId, on: req.db)
    }

    func commentLikeSummary(req: Request) async throws -> LikeSummary {
        let commentId = try commentId(req)
        _ = try await requireComment(commentId, eventId: id(req), on: req.db)
        return try await Self.commentSummary(commentId: commentId, viewerId: req.auth.get(UserToken.self)?.userId, on: req.db)
    }

    func likeComment(req: Request) async throws -> LikeSummary {
        let userId = try req.auth.require(UserToken.self).requireUserID()
        let commentId = try commentId(req)
        _ = try await requireComment(commentId, eventId: id(req), on: req.db)
        let existing = try await CommentLikeModel.query(on: req.db)
            .filter(\.$commentId == commentId)
            .filter(\.$userId == userId)
            .first()
        if existing == nil {
            try await CommentLikeModel(commentId: commentId, userId: userId).create(on: req.db)
        }
        return try await Self.commentSummary(commentId: commentId, viewerId: userId, on: req.db)
    }

    func unlikeComment(req: Request) async throws -> LikeSummary {
        let userId = try req.auth.require(UserToken.self).requireUserID()
        let commentId = try commentId(req)
        try await CommentLikeModel.query(on: req.db)
            .filter(\.$commentId == commentId)
            .filter(\.$userId == userId)
            .delete()
        return try await Self.commentSummary(commentId: commentId, viewerId: userId, on: req.db)
    }

    func mediaLikeSummary(req: Request) async throws -> LikeSummary {
        let mediaId = try mediaId(req)
        _ = try await requireMedia(mediaId, eventId: id(req), on: req.db)
        return try await Self.mediaSummary(mediaId: mediaId, viewerId: req.auth.get(UserToken.self)?.userId, on: req.db)
    }

    func likeMedia(req: Request) async throws -> LikeSummary {
        let userId = try req.auth.require(UserToken.self).requireUserID()
        let mediaId = try mediaId(req)
        _ = try await requireMedia(mediaId, eventId: id(req), on: req.db)
        let existing = try await MediaLikeModel.query(on: req.db)
            .filter(\.$mediaId == mediaId)
            .filter(\.$userId == userId)
            .first()
        if existing == nil {
            try await MediaLikeModel(mediaId: mediaId, userId: userId).create(on: req.db)
        }
        return try await Self.mediaSummary(mediaId: mediaId, viewerId: userId, on: req.db)
    }

    func unlikeMedia(req: Request) async throws -> LikeSummary {
        let userId = try req.auth.require(UserToken.self).requireUserID()
        let mediaId = try mediaId(req)
        try await MediaLikeModel.query(on: req.db)
            .filter(\.$mediaId == mediaId)
            .filter(\.$userId == userId)
            .delete()
        return try await Self.mediaSummary(mediaId: mediaId, viewerId: userId, on: req.db)
    }

    // MARK: Helpers

    private func id(_ req: Request) throws -> UUID {
        guard let id = req.parameters.get("id", as: UUID.self) else { throw Abort(.badRequest) }
        return id
    }

    private func commentId(_ req: Request) throws -> UUID {
        guard let id = req.parameters.get("commentId", as: UUID.self) else { throw Abort(.badRequest) }
        return id
    }

    private func mediaId(_ req: Request) throws -> UUID {
        guard let id = req.parameters.get("mediaId", as: UUID.self) else { throw Abort(.badRequest) }
        return id
    }

    private func requireComment(_ commentId: UUID, eventId: UUID, on db: Database) async throws -> CommentModel {
        guard let comment = try await CommentModel.find(commentId, on: db), comment.eventId == eventId else {
            throw Abort(.notFound)
        }
        return comment
    }

    private func requireMedia(_ mediaId: UUID, eventId: UUID, on db: Database) async throws -> MediaModel {
        guard let media = try await MediaModel.query(on: db)
            .filter(\.$id == mediaId)
            .filter(\.$event.$id == eventId)
            .first() else {
            throw Abort(.notFound)
        }
        return media
    }

    private static func summary(eventId: UUID, viewerId: UUID?, on db: Database) async throws -> LikeSummary {
        let count = try await EventLikeModel.query(on: db).filter(\.$eventId == eventId).count()
        var liked = false
        if let viewerId {
            liked = try await EventLikeModel.query(on: db)
                .filter(\.$eventId == eventId)
                .filter(\.$userId == viewerId)
                .first() != nil
        }
        return LikeSummary(eventID: eventId, count: count, likedByViewer: liked)
    }

    private static func commentSummary(commentId: UUID, viewerId: UUID?, on db: Database) async throws -> LikeSummary {
        let count = try await CommentLikeModel.query(on: db).filter(\.$commentId == commentId).count()
        var liked = false
        if let viewerId {
            liked = try await CommentLikeModel.query(on: db)
                .filter(\.$commentId == commentId)
                .filter(\.$userId == viewerId)
                .first() != nil
        }
        return LikeSummary(eventID: commentId, count: count, likedByViewer: liked)
    }

    private static func mediaSummary(mediaId: UUID, viewerId: UUID?, on db: Database) async throws -> LikeSummary {
        let count = try await MediaLikeModel.query(on: db).filter(\.$mediaId == mediaId).count()
        var liked = false
        if let viewerId {
            liked = try await MediaLikeModel.query(on: db)
                .filter(\.$mediaId == mediaId)
                .filter(\.$userId == viewerId)
                .first() != nil
        }
        return LikeSummary(eventID: mediaId, count: count, likedByViewer: liked)
    }

    /// The display name to attribute a comment to: the profile display name when
    /// present, otherwise the local part of the account email.
    private static func authorName(for userId: UUID, on db: Database) async throws -> String {
        guard let user = try await UserModel.find(userId, on: db) else { throw Abort(.notFound) }
        if let creatorId = user.creatorId, let creator = try await CreatorModel.find(creatorId, on: db) {
            return creator.displayName
        }
        return String(user.email.prefix(while: { $0 != "@" }))
    }
}
