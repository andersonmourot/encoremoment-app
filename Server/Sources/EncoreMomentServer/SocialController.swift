import Vapor
import Fluent
import EncoreMomentCore

/// Comments and likes on events. Reads are public (likes optionally use the
/// token to report the viewer's like state); writes require authentication.
/// Comments may be deleted by their author or the event's owning creator.
struct SocialController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let events = routes.grouped("events")

        // Public reads.
        events.grouped(UserToken.authenticator()).get(":id", "comments", use: listComments)
        events.grouped(UserToken.authenticator()).get(":id", "comments", ":commentId", "likes", use: commentLikeSummary)
        events.grouped(UserToken.authenticator()).get(":id", "media", ":mediaId", "likes", use: mediaLikeSummary)
        events.grouped(UserToken.authenticator()).get(":id", "media", ":mediaId", "comments", use: listMediaComments)
        // Cross-event media feed (the Moments rail).
        routes.grouped(UserToken.authenticator()).grouped("media").get("feed", use: mediaFeed)
        // Optional auth: anonymous callers get likedByViewer == false.
        events.grouped(UserToken.authenticator()).get(":id", "likes", use: likeSummary)
        // Batch: every like summary on the event in one request.
        events.grouped(UserToken.authenticator()).get(":id", "likes", "all", use: likeSummaries)

        // Authenticated writes.
        let protected = events.grouped(UserToken.authenticator(), UserToken.guardMiddleware())
        protected.post(":id", "comments", use: addComment)
        protected.delete(":id", "comments", ":commentId", use: deleteComment)
        protected.post(":id", "comments", ":commentId", "like", use: likeComment)
        protected.delete(":id", "comments", ":commentId", "like", use: unlikeComment)
        protected.post(":id", "media", ":mediaId", "comments", use: addMediaComment)
        protected.post(":id", "media", ":mediaId", "like", use: likeMedia)
        protected.delete(":id", "media", ":mediaId", "like", use: unlikeMedia)
        protected.post(":id", "like", use: like)
        protected.delete(":id", "like", use: unlike)
    }

    struct CommentBody: Content { let body: String }

    func listComments(req: Request) async throws -> [Comment] {
        let eventId = try id(req)
        _ = try await requireViewableEvent(eventId, req)
        var query = CommentModel.query(on: req.db)
            .filter(\.$eventId == eventId)
        let blockedUsers = try await Moderation.blockedUserIDs(for: req)
        if !blockedUsers.isEmpty {
            query = query.filter(\.$userId !~ Array(blockedUsers))
        }
        // Only event-level comments — media comments come from the
        // per-media endpoint.
        return try await query
            .sort(\.$createdAt, .ascending)
            .all()
            .filter { $0.mediaId == nil }
            .map { $0.toDTO() }
    }

    /// Comments on one media item, oldest first.
    func listMediaComments(req: Request) async throws -> [Comment] {
        let eventId = try id(req)
        let mediaId = try mediaId(req)
        _ = try await requireViewableEvent(eventId, req)
        _ = try await requireMedia(mediaId, eventId: eventId, on: req.db)
        let blockedUsers = try await Moderation.blockedUserIDs(for: req)
        return try await CommentModel.query(on: req.db)
            .filter(\.$eventId == eventId)
            .sort(\.$createdAt, .ascending)
            .all()
            .filter { $0.mediaId == mediaId && !blockedUsers.contains($0.userId) }
            .map { $0.toDTO() }
    }

    func addMediaComment(req: Request) async throws -> Comment {
        let token = try req.auth.require(UserToken.self)
        let userId = try token.requireUserID()
        let eventId = try id(req)
        let mediaId = try mediaId(req)
        let event = try await requireViewableEvent(eventId, req)
        _ = try await requireMedia(mediaId, eventId: eventId, on: req.db)

        let text = try req.content.decode(CommentBody.self).body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Comment.isValidBody(text) else {
            throw Abort(.unprocessableEntity, reason: "Comment must be 1–2000 characters.")
        }

        let name = try await Self.authorName(for: userId, on: req.db)
        let model = CommentModel(eventId: eventId, mediaId: mediaId, userId: userId, authorName: name, body: text)
        try await model.create(on: req.db)
        if token.creatorId != event.creatorId {
            try await NotificationCenter.notifyCreator(
                creatorId: event.creatorId,
                kind: .comment,
                title: "New comment",
                body: "\(name) commented on a photo in \(event.title).",
                eventId: eventId,
                on: req.db
            )
        }
        return model.toDTO()
    }

    func addComment(req: Request) async throws -> Comment {
        let token = try req.auth.require(UserToken.self)
        let userId = try token.requireUserID()
        let eventId = try id(req)
        let event = try await requireViewableEvent(eventId, req)

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
        _ = try await requireViewableEvent(eventId, req)
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
        _ = try await requireViewableEvent(eventId, req)
        let viewerId = req.auth.get(UserToken.self)?.userId
        return try await Self.summary(eventId: eventId, viewerId: viewerId, on: req.db)
    }

    /// One request for the event like summary plus every media and comment
    /// like summary — replaces the per-item fan-out on the event page.
    func likeSummaries(req: Request) async throws -> EventLikeSummaries {
        let eventId = try id(req)
        _ = try await requireViewableEvent(eventId, req)
        let viewerId = req.auth.get(UserToken.self)?.userId

        let eventSummary = try await Self.summary(eventId: eventId, viewerId: viewerId, on: req.db)

        let mediaIDs = try await MediaModel.query(on: req.db)
            .filter(\.$event.$id == eventId).all().compactMap(\.id)
        let commentIDs = try await CommentModel.query(on: req.db)
            .filter(\.$eventId == eventId).all().compactMap(\.id)

        let mediaLikes = mediaIDs.isEmpty ? [] : try await MediaLikeModel.query(on: req.db)
            .filter(\.$mediaId ~~ mediaIDs).all()
        let commentLikes = commentIDs.isEmpty ? [] : try await CommentLikeModel.query(on: req.db)
            .filter(\.$commentId ~~ commentIDs).all()

        let mediaByID = Dictionary(grouping: mediaLikes, by: \.mediaId)
        let commentByID = Dictionary(grouping: commentLikes, by: \.commentId)

        return EventLikeSummaries(
            event: eventSummary,
            media: mediaIDs.map { id in
                let likes = mediaByID[id] ?? []
                return LikeSummary(eventID: id, count: likes.count,
                                   likedByViewer: viewerId.map { v in likes.contains { $0.userId == v } } ?? false)
            },
            comments: commentIDs.map { id in
                let likes = commentByID[id] ?? []
                return LikeSummary(eventID: id, count: likes.count,
                                   likedByViewer: viewerId.map { v in likes.contains { $0.userId == v } } ?? false)
            }
        )
    }

    func like(req: Request) async throws -> LikeSummary {
        let token = try req.auth.require(UserToken.self)
        let userId = try token.requireUserID()
        let eventId = try id(req)
        let event = try await requireViewableEvent(eventId, req)

        let existing = try await EventLikeModel.query(on: req.db)
            .filter(\.$eventId == eventId)
            .filter(\.$userId == userId)
            .first()
        if existing == nil {
            try await EventLikeModel(eventId: eventId, userId: userId).create(on: req.db)
            if token.creatorId != event.creatorId {
                let name = try await NotificationCenter.actorName(for: userId, on: req.db)
                try await NotificationCenter.notifyCreator(
                    creatorId: event.creatorId,
                    kind: .like,
                    title: "New like",
                    body: "\(name) liked \(event.title).",
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
        _ = try await requireViewableEvent(eventId, req)
        try await EventLikeModel.query(on: req.db)
            .filter(\.$eventId == eventId)
            .filter(\.$userId == userId)
            .delete()
        return try await Self.summary(eventId: eventId, viewerId: userId, on: req.db)
    }

    func commentLikeSummary(req: Request) async throws -> LikeSummary {
        let commentId = try commentId(req)
        _ = try await requireViewableEvent(id(req), req)
        _ = try await requireComment(commentId, eventId: id(req), on: req.db)
        return try await Self.commentSummary(commentId: commentId, viewerId: req.auth.get(UserToken.self)?.userId, on: req.db)
    }

    func likeComment(req: Request) async throws -> LikeSummary {
        let userId = try req.auth.require(UserToken.self).requireUserID()
        let commentId = try commentId(req)
        _ = try await requireViewableEvent(id(req), req)
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
        _ = try await requireViewableEvent(id(req), req)
        try await CommentLikeModel.query(on: req.db)
            .filter(\.$commentId == commentId)
            .filter(\.$userId == userId)
            .delete()
        return try await Self.commentSummary(commentId: commentId, viewerId: userId, on: req.db)
    }

    func mediaLikeSummary(req: Request) async throws -> LikeSummary {
        let mediaId = try mediaId(req)
        _ = try await requireViewableEvent(id(req), req)
        _ = try await requireMedia(mediaId, eventId: id(req), on: req.db)
        return try await Self.mediaSummary(mediaId: mediaId, viewerId: req.auth.get(UserToken.self)?.userId, on: req.db)
    }

    func likeMedia(req: Request) async throws -> LikeSummary {
        let userId = try req.auth.require(UserToken.self).requireUserID()
        let mediaId = try mediaId(req)
        _ = try await requireViewableEvent(id(req), req)
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
        _ = try await requireViewableEvent(id(req), req)
        try await MediaLikeModel.query(on: req.db)
            .filter(\.$mediaId == mediaId)
            .filter(\.$userId == userId)
            .delete()
        return try await Self.mediaSummary(mediaId: mediaId, viewerId: userId, on: req.db)
    }

    /// `GET /media/feed?following=&limit=&offset=` — media across published,
    /// viewable events ordered by likes then recency. `following=true`
    /// restricts to creators the signed-in viewer follows.
    func mediaFeed(req: Request) async throws -> [MediaFeedItem] {
        let followingOnly = (try? req.query.get(Bool.self, at: "following")) ?? false
        let limit = max(1, min((try? req.query.get(Int.self, at: "limit")) ?? 50, 100))
        let offset = max(0, (try? req.query.get(Int.self, at: "offset")) ?? 0)

        let blocked = try await Moderation.blockedCreatorIDs(for: req)
        var allowedCreatorIds: Set<UUID>? = nil
        if followingOnly {
            guard let uid = req.auth.get(UserToken.self)?.userId else {
                return []  // anonymous viewers follow nobody
            }
            allowedCreatorIds = Set(try await FollowModel.query(on: req.db)
                .filter(\.$userId == uid).all().map(\.creatorId))
        }

        // Events the viewer may see: published, not invite-only (or a member/
        // owner of it), not blocked, optionally limited to followed creators.
        var eventRows = try await EventModel.query(on: req.db)
            .filter(\.$isPublished == true)
            .all()
        let viewerCreatorId = req.auth.get(UserToken.self)?.creatorId
        var memberEventIds = Set<UUID>()
        if let viewerCreatorId {
            memberEventIds = (try? await EventAccess.memberEventIDs(for: viewerCreatorId, on: req.db)) ?? []
        }
        eventRows = eventRows.filter { event in
            guard let id = event.id else { return false }
            if blocked.contains(event.creatorId) { return false }
            if let allowed = allowedCreatorIds, !allowed.contains(event.creatorId) { return false }
            if event.inviteOnly {
                return event.creatorId == viewerCreatorId || memberEventIds.contains(id)
            }
            return true
        }
        let eventById = Dictionary(uniqueKeysWithValues: eventRows.compactMap { event in
            event.id.map { ($0, event) }
        })

        var mediaRows = try await MediaModel.query(on: req.db)
            .filter(\.$event.$id ~~ Array(eventById.keys))
            .all()
        // Like counts + the viewer's own like state for these items.
        let mediaIds = mediaRows.compactMap(\.id)
        let likes = mediaIds.isEmpty ? [] : try await MediaLikeModel.query(on: req.db)
            .filter(\.$mediaId ~~ mediaIds).all()
        let countByMedia = Dictionary(grouping: likes, by: \.mediaId).mapValues(\.count)
        let viewerLiked: Set<UUID> = {
            guard let uid = req.auth.get(UserToken.self)?.userId else { return [] }
            return Set(likes.filter { $0.userId == uid }.map(\.mediaId))
        }()

        mediaRows.sort {
            let lc = countByMedia[$0.id ?? UUID()] ?? 0
            let rc = countByMedia[$1.id ?? UUID()] ?? 0
            if lc != rc { return lc > rc }
            return $0.createdAt > $1.createdAt
        }
        guard offset < mediaRows.count else { return [] }
        let page = mediaRows.dropFirst(offset).prefix(limit)

        let creatorNames = Dictionary(uniqueKeysWithValues: try await CreatorModel.query(on: req.db)
            .filter(\.$id ~~ Array(Set(eventRows.map(\.creatorId))))
            .all().compactMap { creator in creator.id.map { ($0, creator.displayName) } })

        // Comment counts for the page's media items.
        let pageIds = page.compactMap(\.id)
        let comments = pageIds.isEmpty ? [] : try await CommentModel.query(on: req.db)
            .filter(\.$mediaId ~~ pageIds).all()
        let commentCountByMedia = Dictionary(grouping: comments, by: \.mediaId).mapValues(\.count)

        return page.compactMap { media in
            guard let mid = media.id, let event = eventById[media.$event.id] else { return nil }
            return MediaFeedItem(
                media: media.toDTO(),
                eventID: media.$event.id,
                eventTitle: event.title,
                creatorID: event.creatorId,
                creatorName: creatorNames[event.creatorId] ?? "",
                likeCount: countByMedia[mid] ?? 0,
                likedByViewer: viewerLiked.contains(mid),
                commentCount: commentCountByMedia[mid] ?? 0
            )
        }
    }

    // MARK: Helpers

    private func id(_ req: Request) throws -> UUID {
        guard let id = req.parameters.get("id", as: UUID.self) else { throw Abort(.badRequest) }
        return id
    }

    /// Loads the event and asserts the caller may view it (invite-only events
    /// are limited to the owner and invited members).
    private func requireViewableEvent(_ eventId: UUID, _ req: Request) async throws -> EventModel {
        guard let event = try await EventModel.find(eventId, on: req.db) else { throw Abort(.notFound) }
        guard try await EventAccess.canView(event, on: req) else {
            throw Abort(.forbidden, reason: "This event is invite-only.")
        }
        return event
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
