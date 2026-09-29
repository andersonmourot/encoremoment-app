import Fluent
import Foundation
import EncoreMomentCore

/// A text comment on an event. `author_name` is denormalized at creation time so
/// the comment can be rendered without joining the users/creators tables.
final class CommentModel: Model, @unchecked Sendable {
    static let schema = "comments"

    @ID(custom: "id", generatedBy: .user) var id: UUID?
    @Field(key: "event_id") var eventId: UUID
    @Field(key: "user_id") var userId: UUID
    @Field(key: "author_name") var authorName: String
    @Field(key: "body") var body: String
    @Field(key: "created_at") var createdAt: Date

    init() {}

    init(id: UUID = UUID(), eventId: UUID, userId: UUID, authorName: String, body: String, createdAt: Date = Date()) {
        self.id = id
        self.eventId = eventId
        self.userId = userId
        self.authorName = authorName
        self.body = body
        self.createdAt = createdAt
    }

    func toDTO() -> Comment {
        Comment(id: id ?? UUID(), eventID: eventId, authorID: userId, authorName: authorName, body: body, createdAt: createdAt)
    }
}

struct CreateComment: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(CommentModel.schema)
            .field("id", .uuid, .identifier(auto: false))
            .field("event_id", .uuid, .required, .references(EventModel.schema, "id", onDelete: .cascade))
            .field("user_id", .uuid, .required, .references(UserModel.schema, "id", onDelete: .cascade))
            .field("author_name", .string, .required)
            .field("body", .string, .required)
            .field("created_at", .datetime, .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(CommentModel.schema).delete()
    }
}

/// One row per (user, event) like. The unique constraint makes liking idempotent.
final class EventLikeModel: Model, @unchecked Sendable {
    static let schema = "event_likes"

    @ID(custom: "id", generatedBy: .user) var id: UUID?
    @Field(key: "event_id") var eventId: UUID
    @Field(key: "user_id") var userId: UUID

    init() {}

    init(id: UUID = UUID(), eventId: UUID, userId: UUID) {
        self.id = id
        self.eventId = eventId
        self.userId = userId
    }
}

struct CreateEventLike: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(EventLikeModel.schema)
            .field("id", .uuid, .identifier(auto: false))
            .field("event_id", .uuid, .required, .references(EventModel.schema, "id", onDelete: .cascade))
            .field("user_id", .uuid, .required, .references(UserModel.schema, "id", onDelete: .cascade))
            .unique(on: "event_id", "user_id")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(EventLikeModel.schema).delete()
    }
}

final class CommentLikeModel: Model, @unchecked Sendable {
    static let schema = "comment_likes"

    @ID(custom: "id", generatedBy: .user) var id: UUID?
    @Field(key: "comment_id") var commentId: UUID
    @Field(key: "user_id") var userId: UUID

    init() {}

    init(id: UUID = UUID(), commentId: UUID, userId: UUID) {
        self.id = id
        self.commentId = commentId
        self.userId = userId
    }
}

struct CreateCommentLike: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(CommentLikeModel.schema)
            .field("id", .uuid, .identifier(auto: false))
            .field("comment_id", .uuid, .required, .references(CommentModel.schema, "id", onDelete: .cascade))
            .field("user_id", .uuid, .required, .references(UserModel.schema, "id", onDelete: .cascade))
            .unique(on: "comment_id", "user_id")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(CommentLikeModel.schema).delete()
    }
}

final class MediaLikeModel: Model, @unchecked Sendable {
    static let schema = "media_likes"

    @ID(custom: "id", generatedBy: .user) var id: UUID?
    @Field(key: "media_id") var mediaId: UUID
    @Field(key: "user_id") var userId: UUID

    init() {}

    init(id: UUID = UUID(), mediaId: UUID, userId: UUID) {
        self.id = id
        self.mediaId = mediaId
        self.userId = userId
    }
}

struct CreateMediaLike: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(MediaLikeModel.schema)
            .field("id", .uuid, .identifier(auto: false))
            .field("media_id", .uuid, .required, .references(MediaModel.schema, "id", onDelete: .cascade))
            .field("user_id", .uuid, .required, .references(UserModel.schema, "id", onDelete: .cascade))
            .unique(on: "media_id", "user_id")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(MediaLikeModel.schema).delete()
    }
}
