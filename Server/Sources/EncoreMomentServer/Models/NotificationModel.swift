import Fluent
import Foundation
import EncoreMomentCore

final class NotificationModel: Model, @unchecked Sendable {
    static let schema = "notifications"

    @ID(custom: "id", generatedBy: .user) var id: UUID?
    @Field(key: "user_id") var userId: UUID
    @Field(key: "kind") var kind: String
    @Field(key: "title") var title: String
    @Field(key: "body") var body: String
    @OptionalField(key: "event_id") var eventId: UUID?
    @OptionalField(key: "creator_id") var creatorId: UUID?
    @Field(key: "is_read") var isRead: Bool
    @Field(key: "created_at") var createdAt: Date

    init() {}

    init(
        userId: UUID,
        kind: AppNotificationKind,
        title: String,
        body: String,
        eventId: UUID? = nil,
        creatorId: UUID? = nil,
        isRead: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.userId = userId
        self.kind = kind.rawValue
        self.title = title
        self.body = body
        self.eventId = eventId
        self.creatorId = creatorId
        self.isRead = isRead
        self.createdAt = createdAt
    }

    func toDTO() -> AppNotification {
        AppNotification(
            id: id ?? UUID(),
            kind: AppNotificationKind(rawValue: kind) ?? .comment,
            title: title,
            body: body,
            eventID: eventId,
            creatorID: creatorId,
            isRead: isRead,
            createdAt: createdAt
        )
    }
}

struct CreateNotification: AsyncMigration {
    var name: String { "CreateNotification" }
    func prepare(on database: Database) async throws {
        try await database.schema(NotificationModel.schema)
            .field("id", .uuid, .identifier(auto: false))
            .field("user_id", .uuid, .required)
            .field("kind", .string, .required)
            .field("title", .string, .required)
            .field("body", .string, .required)
            .field("event_id", .uuid)
            .field("creator_id", .uuid)
            .field("is_read", .bool, .required)
            .field("created_at", .datetime, .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(NotificationModel.schema).delete()
    }
}
