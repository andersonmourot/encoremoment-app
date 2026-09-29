import Fluent
import Foundation
import EncoreMomentCore
import SQLKit

final class EventModel: Model, @unchecked Sendable {
    static let schema = "events"

    @ID(custom: "id", generatedBy: .user) var id: UUID?
    @Field(key: "creator_id") var creatorId: UUID
    @Field(key: "title") var title: String
    @OptionalField(key: "details") var details: String?
    @OptionalField(key: "cover_image_url") var coverImageURL: String?
    @OptionalField(key: "location") var location: String?
    @Field(key: "date") var date: Date
    @Field(key: "created_at") var createdAt: Date
    @Field(key: "is_published") var isPublished: Bool
    @Field(key: "allows_community_uploads") var allowsCommunityUploads: Bool
    @Children(for: \.$event) var media: [MediaModel]

    init() {}

    init(from event: Event) {
        self.id = event.id
        self.creatorId = event.creatorId
        self.title = event.title
        self.details = event.details
        self.coverImageURL = event.coverImageURL?.absoluteString
        self.location = event.location
        self.date = event.date
        self.createdAt = event.createdAt
        self.isPublished = event.isPublished
        self.allowsCommunityUploads = event.allowsCommunityUploads
    }

    func applyFields(_ event: Event) {
        self.creatorId = event.creatorId
        self.title = event.title
        self.details = event.details
        self.coverImageURL = event.coverImageURL?.absoluteString
        self.location = event.location
        self.date = event.date
        self.isPublished = event.isPublished
        self.allowsCommunityUploads = event.allowsCommunityUploads
    }

    /// Maps to the Core DTO. `media` must be eager-loaded by the caller.
    func toDTO() -> Event {
        Event(
            id: id ?? UUID(),
            creatorId: creatorId,
            title: title,
            details: details,
            coverImageURL: coverImageURL.flatMap(URL.init(string:)),
            location: location,
            date: date,
            createdAt: createdAt,
            isPublished: isPublished,
            allowsCommunityUploads: allowsCommunityUploads,
            media: ($media.value ?? [])
                .map { $0.toDTO() }
                .sorted {
                    if $0.sortOrder == $1.sortOrder { return $0.createdAt < $1.createdAt }
                    return $0.sortOrder < $1.sortOrder
                }
        )
    }
}

struct AddEventCommunityUploads: AsyncMigration {
    var name: String { "AddEventCommunityUploads" }
    func prepare(on database: Database) async throws {
        guard let sql = database as? any SQLDatabase else { return }
        try await sql.raw("""
        ALTER TABLE \(unsafeRaw: EventModel.schema)
        ADD COLUMN allows_community_uploads BOOLEAN NOT NULL DEFAULT false
        """).run()
    }

    func revert(on database: Database) async throws {
        // SQLite cannot drop columns on older versions; keep the additive column.
    }
}

struct CreateEvent: AsyncMigration {
    var name: String { "CreateEvent" }
    func prepare(on database: Database) async throws {
        try await database.schema(EventModel.schema)
            .field("id", .uuid, .identifier(auto: false))
            .field("creator_id", .uuid, .required, .references(CreatorModel.schema, "id", onDelete: .cascade))
            .field("title", .string, .required)
            .field("details", .string)
            .field("cover_image_url", .string)
            .field("location", .string)
            .field("date", .datetime, .required)
            .field("created_at", .datetime, .required)
            .field("is_published", .bool, .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(EventModel.schema).delete()
    }
}
