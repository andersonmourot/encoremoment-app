import Fluent
import Foundation
import InTheMomentCore
import SQLKit

final class MediaModel: Model, @unchecked Sendable {
    static let schema = "media"

    @ID(custom: "id", generatedBy: .user) var id: UUID?
    @Parent(key: "event_id") var event: EventModel
    @Field(key: "kind") var kind: String
    @Field(key: "url") var url: String
    @OptionalField(key: "thumbnail_url") var thumbnailURL: String?
    @OptionalField(key: "caption") var caption: String?
    @OptionalField(key: "uploader_id") var uploaderId: UUID?
    @OptionalField(key: "uploader_name") var uploaderName: String?
    @OptionalField(key: "width") var width: Int?
    @OptionalField(key: "height") var height: Int?
    @OptionalField(key: "duration_seconds") var durationSeconds: Double?
    @Field(key: "is_downloadable") var isDownloadable: Bool
    @Field(key: "sort_order") var sortOrder: Int
    @Field(key: "created_at") var createdAt: Date

    init() {}

    init(from item: MediaItem) {
        self.id = item.id
        self.$event.id = item.eventId
        self.kind = item.kind.rawValue
        self.url = item.url.absoluteString
        self.thumbnailURL = item.thumbnailURL?.absoluteString
        self.caption = item.caption
        self.uploaderId = item.uploaderID
        self.uploaderName = item.uploaderName
        self.width = item.width
        self.height = item.height
        self.durationSeconds = item.durationSeconds
        self.isDownloadable = item.isDownloadable
        self.sortOrder = item.sortOrder
        self.createdAt = item.createdAt
    }

    func toDTO() -> MediaItem {
        MediaItem(
            id: id ?? UUID(),
            eventId: $event.id,
            kind: MediaKind(rawValue: kind) ?? .photo,
            url: URL(string: url) ?? URL(string: "about:blank")!,
            thumbnailURL: thumbnailURL.flatMap(URL.init(string:)),
            caption: caption,
            uploaderID: uploaderId,
            uploaderName: uploaderName,
            width: width,
            height: height,
            durationSeconds: durationSeconds,
            isDownloadable: isDownloadable,
            sortOrder: sortOrder,
            createdAt: createdAt
        )
    }
}

struct AddMediaSortOrder: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? any SQLDatabase else { return }
        try await sql.raw("""
        ALTER TABLE \(unsafeRaw: MediaModel.schema)
        ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0
        """).run()
    }

    func revert(on database: Database) async throws {
        // SQLite cannot drop columns on older versions; keep the additive column.
    }
}

struct AddMediaUploader: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? any SQLDatabase else { return }
        try await sql.raw("ALTER TABLE \(unsafeRaw: MediaModel.schema) ADD COLUMN uploader_id UUID").run()
        try await sql.raw("ALTER TABLE \(unsafeRaw: MediaModel.schema) ADD COLUMN uploader_name TEXT").run()
    }

    func revert(on database: Database) async throws {
        // SQLite cannot drop columns on older versions; keep additive columns.
    }
}

struct CreateMedia: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(MediaModel.schema)
            .field("id", .uuid, .identifier(auto: false))
            .field("event_id", .uuid, .required, .references(EventModel.schema, "id", onDelete: .cascade))
            .field("kind", .string, .required)
            .field("url", .string, .required)
            .field("thumbnail_url", .string)
            .field("caption", .string)
            .field("width", .int)
            .field("height", .int)
            .field("duration_seconds", .double)
            .field("is_downloadable", .bool, .required)
            .field("created_at", .datetime, .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(MediaModel.schema).delete()
    }
}
