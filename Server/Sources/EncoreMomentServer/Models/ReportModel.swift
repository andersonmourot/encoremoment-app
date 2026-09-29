import Fluent
import Foundation
import EncoreMomentCore

final class ReportModel: Model, @unchecked Sendable {
    static let schema = "reports"

    @ID(custom: "id", generatedBy: .user) var id: UUID?
    @Field(key: "user_id") var userId: UUID
    @Field(key: "target_type") var targetType: String
    @Field(key: "target_id") var targetId: UUID
    @OptionalField(key: "event_id") var eventId: UUID?
    @Field(key: "reason") var reason: String
    @OptionalField(key: "details") var details: String?
    @Field(key: "created_at") var createdAt: Date

    init() {}

    init(userId: UUID, request: ReportRequest, createdAt: Date = Date()) {
        self.id = UUID()
        self.userId = userId
        self.targetType = request.targetType.rawValue
        self.targetId = request.targetID
        self.eventId = request.eventID
        self.reason = request.reason.rawValue
        self.details = request.details
        self.createdAt = createdAt
    }

    func toDTO() -> Report {
        Report(
            id: id ?? UUID(),
            reporterID: userId,
            targetType: ReportTargetType(rawValue: targetType) ?? .event,
            targetID: targetId,
            eventID: eventId,
            reason: ReportReason(rawValue: reason) ?? .other,
            details: details,
            createdAt: createdAt
        )
    }
}

struct CreateReport: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(ReportModel.schema)
            .field("id", .uuid, .identifier(auto: false))
            .field("user_id", .uuid, .required)
            .field("target_type", .string, .required)
            .field("target_id", .uuid, .required)
            .field("event_id", .uuid)
            .field("reason", .string, .required)
            .field("details", .string)
            .field("created_at", .datetime, .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(ReportModel.schema).delete()
    }
}
