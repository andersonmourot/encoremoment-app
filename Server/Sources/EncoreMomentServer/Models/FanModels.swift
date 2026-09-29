import Fluent
import Foundation

/// A fan's favorited event (per account).
final class FavoriteModel: Model, @unchecked Sendable {
    static let schema = "favorites"

    @ID(custom: "id", generatedBy: .user) var id: UUID?
    @Field(key: "user_id") var userId: UUID
    @Field(key: "event_id") var eventId: UUID

    init() {}

    init(id: UUID = UUID(), userId: UUID, eventId: UUID) {
        self.id = id
        self.userId = userId
        self.eventId = eventId
    }
}

/// A creator a fan follows (per account).
final class FollowModel: Model, @unchecked Sendable {
    static let schema = "follows"

    @ID(custom: "id", generatedBy: .user) var id: UUID?
    @Field(key: "user_id") var userId: UUID
    @Field(key: "creator_id") var creatorId: UUID

    init() {}

    init(id: UUID = UUID(), userId: UUID, creatorId: UUID) {
        self.id = id
        self.userId = userId
        self.creatorId = creatorId
    }
}

/// A creator a fan has blocked (per account). Blocked creators are filtered out
/// of the blocker's event/creator feeds, and their comments/uploads are hidden.
final class BlockModel: Model, @unchecked Sendable {
    static let schema = "blocks"

    @ID(custom: "id", generatedBy: .user) var id: UUID?
    @Field(key: "user_id") var userId: UUID
    @Field(key: "creator_id") var creatorId: UUID

    init() {}

    init(id: UUID = UUID(), userId: UUID, creatorId: UUID) {
        self.id = id
        self.userId = userId
        self.creatorId = creatorId
    }
}

struct CreateFavorite: AsyncMigration {
    var name: String { "CreateFavorite" }
    func prepare(on database: Database) async throws {
        try await database.schema(FavoriteModel.schema)
            .field("id", .uuid, .identifier(auto: false))
            .field("user_id", .uuid, .required, .references(UserModel.schema, "id", onDelete: .cascade))
            .field("event_id", .uuid, .required, .references(EventModel.schema, "id", onDelete: .cascade))
            .unique(on: "user_id", "event_id")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(FavoriteModel.schema).delete()
    }
}

struct CreateFollow: AsyncMigration {
    var name: String { "CreateFollow" }
    func prepare(on database: Database) async throws {
        try await database.schema(FollowModel.schema)
            .field("id", .uuid, .identifier(auto: false))
            .field("user_id", .uuid, .required, .references(UserModel.schema, "id", onDelete: .cascade))
            .field("creator_id", .uuid, .required, .references(CreatorModel.schema, "id", onDelete: .cascade))
            .unique(on: "user_id", "creator_id")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(FollowModel.schema).delete()
    }
}

struct CreateBlock: AsyncMigration {
    var name: String { "CreateBlock" }
    func prepare(on database: Database) async throws {
        try await database.schema(BlockModel.schema)
            .field("id", .uuid, .identifier(auto: false))
            .field("user_id", .uuid, .required, .references(UserModel.schema, "id", onDelete: .cascade))
            .field("creator_id", .uuid, .required, .references(CreatorModel.schema, "id", onDelete: .cascade))
            .unique(on: "user_id", "creator_id")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(BlockModel.schema).delete()
    }
}
