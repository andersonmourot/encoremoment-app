import Fluent
import Foundation
import SQLKit
import Vapor

/// An authenticated account. New accounts own a ``CreatorModel`` profile; the
/// relationship stays optional so older accounts without a profile can still log in.
final class UserModel: Model, @unchecked Sendable {
    static let schema = "users"

    @ID(custom: "id", generatedBy: .user) var id: UUID?
    @Field(key: "email") var email: String
    @Field(key: "password_hash") var passwordHash: String
    @OptionalField(key: "creator_id") var creatorId: UUID?
    @Field(key: "created_at") var createdAt: Date

    init() {}

    init(id: UUID = UUID(), email: String, passwordHash: String, creatorId: UUID? = nil, createdAt: Date = Date()) {
        self.id = id
        self.email = email
        self.passwordHash = passwordHash
        self.creatorId = creatorId
        self.createdAt = createdAt
    }
}

struct CreateUser: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(UserModel.schema)
            .field("id", .uuid, .identifier(auto: false))
            .field("email", .string, .required)
            .unique(on: "email")
            .field("password_hash", .string, .required)
            .field("creator_id", .uuid, .required, .references(CreatorModel.schema, "id", onDelete: .cascade))
            .field("created_at", .datetime, .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(UserModel.schema).delete()
    }
}

/// Makes `users.creator_id` nullable so legacy accounts without a profile can exist.
/// SQLite can't alter a column's nullability in place, so we rebuild the table,
/// preserving existing rows. The replacement table is built with Fluent's schema
/// builder so column storage types match exactly, then swapped in by rename.
struct MakeUserCreatorOptional: AsyncMigration {
    private static let tempSchema = "users_optional_creator"

    func prepare(on database: Database) async throws {
        guard let sql = database as? any SQLDatabase else { return }

        try await database.schema(Self.tempSchema)
            .field("id", .uuid, .identifier(auto: false))
            .field("email", .string, .required)
            .unique(on: "email")
            .field("password_hash", .string, .required)
            .field("creator_id", .uuid, .references(CreatorModel.schema, "id", onDelete: .cascade))
            .field("created_at", .datetime, .required)
            .create()

        try await sql.raw("""
        INSERT INTO \(unsafeRaw: Self.tempSchema) (id, email, password_hash, creator_id, created_at)
        SELECT id, email, password_hash, creator_id, created_at FROM \(unsafeRaw: UserModel.schema)
        """).run()

        try await database.schema(UserModel.schema).delete()
        try await sql.raw("ALTER TABLE \(unsafeRaw: Self.tempSchema) RENAME TO \(unsafeRaw: UserModel.schema)").run()
    }

    func revert(on database: Database) async throws {
        // Non-reversible nullability change; leave the (more permissive) schema in place.
    }
}
