import Fluent
import Foundation
import EncoreMomentCore
import SQLKit

final class CreatorModel: Model, @unchecked Sendable {
    static let schema = "creators"

    @ID(custom: "id", generatedBy: .user) var id: UUID?
    @Field(key: "display_name") var displayName: String
    @Field(key: "handle") var handle: String
    @OptionalField(key: "bio") var bio: String?
    @OptionalField(key: "avatar_url") var avatarURL: String?
    @OptionalField(key: "accent_color_hex") var accentColorHex: String?
    @Field(key: "is_verified") var isVerified: Bool
    @Field(key: "joined_at") var joinedAt: Date

    init() {}

    init(from creator: Creator) {
        self.id = creator.id
        self.displayName = creator.displayName
        self.handle = creator.handle
        self.bio = creator.bio
        self.avatarURL = creator.avatarURL?.absoluteString
        self.accentColorHex = creator.accentColorHex
        self.isVerified = creator.isVerified
        self.joinedAt = creator.joinedAt
    }

    func apply(_ creator: Creator) {
        self.displayName = creator.displayName
        self.handle = creator.handle
        self.bio = creator.bio
        self.avatarURL = creator.avatarURL?.absoluteString
        self.accentColorHex = creator.accentColorHex
        self.isVerified = creator.isVerified
        self.joinedAt = creator.joinedAt
    }

    func toDTO() -> Creator {
        Creator(
            id: id ?? UUID(),
            displayName: displayName,
            handle: handle,
            bio: bio,
            avatarURL: avatarURL.flatMap(URL.init(string:)),
            accentColorHex: accentColorHex,
            isVerified: isVerified,
            joinedAt: joinedAt
        )
    }

    /// Case-insensitive handle lookup — handles may contain capitals, but two
    /// handles differing only in case are the same handle.
    static func findByHandle(_ handle: String, on db: Database) async throws -> CreatorModel? {
        try await CreatorModel.query(on: db).all()
            .first { $0.handle.lowercased() == handle.lowercased() }
    }
}

struct AddCreatorAccentColor: AsyncMigration {
    var name: String { "AddCreatorAccentColor" }
    func prepare(on database: Database) async throws {
        guard let sql = database as? any SQLDatabase else { return }
        try await sql.raw("""
        ALTER TABLE \(unsafeRaw: CreatorModel.schema)
        ADD COLUMN accent_color_hex TEXT
        """).run()
    }

    func revert(on database: Database) async throws {
        // SQLite cannot drop columns on older versions; keep the additive column.
    }
}

/// Handles are unique case-insensitively — the column-level UNIQUE constraint
/// is binary (case-sensitive), so enforce it with an expression index.
struct AddCreatorHandleCaseIndex: AsyncMigration {
    var name: String { "AddCreatorHandleCaseIndex" }
    func prepare(on database: Database) async throws {
        guard let sql = database as? any SQLDatabase else { return }
        try await sql.raw("""
        CREATE UNIQUE INDEX creators_handle_nocase
        ON \(unsafeRaw: CreatorModel.schema) (LOWER(handle))
        """).run()
    }

    func revert(on database: Database) async throws {
        guard let sql = database as? any SQLDatabase else { return }
        try await sql.raw("DROP INDEX IF EXISTS creators_handle_nocase").run()
    }
}

struct CreateCreator: AsyncMigration {
    var name: String { "CreateCreator" }
    func prepare(on database: Database) async throws {
        try await database.schema(CreatorModel.schema)
            .field("id", .uuid, .identifier(auto: false))
            .field("display_name", .string, .required)
            .field("handle", .string, .required)
            .unique(on: "handle")
            .field("bio", .string)
            .field("avatar_url", .string)
            .field("is_verified", .bool, .required)
            .field("joined_at", .datetime, .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(CreatorModel.schema).delete()
    }
}
