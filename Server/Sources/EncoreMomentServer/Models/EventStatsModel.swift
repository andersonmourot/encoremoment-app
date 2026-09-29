import Fluent
import Foundation
import EncoreMomentCore

/// Per-event engagement counters. The row's `id` is the event's id (one row per
/// event), created lazily the first time a view or download is recorded.
final class EventStatsModel: Model, @unchecked Sendable {
    static let schema = "event_stats"

    @ID(custom: "id", generatedBy: .user) var id: UUID?
    @Field(key: "view_count") var viewCount: Int
    @Field(key: "download_count") var downloadCount: Int

    init() {}

    init(eventId: UUID, viewCount: Int = 0, downloadCount: Int = 0) {
        self.id = eventId
        self.viewCount = viewCount
        self.downloadCount = downloadCount
    }

    func toDTO() -> EventStats {
        EventStats(eventID: id ?? UUID(), views: viewCount, downloads: downloadCount)
    }
}

struct CreateEventStats: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(EventStatsModel.schema)
            .field("id", .uuid, .identifier(auto: false),
                   .references(EventModel.schema, "id", onDelete: .cascade))
            .field("view_count", .int, .required)
            .field("download_count", .int, .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(EventStatsModel.schema).delete()
    }
}
