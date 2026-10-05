import Fluent
import Foundation
import EncoreMomentCore

/// A shareable invite link for an event. Anyone signed in who redeems the code
/// joins the event with the link's role.
final class EventInviteLinkModel: Model, @unchecked Sendable {
    static let schema = "event_invite_links"

    @ID(custom: "id", generatedBy: .user) var id: UUID?
    @Field(key: "code") var code: String
    @Field(key: "event_id") var eventId: UUID
    @Field(key: "role") var role: String
    @Field(key: "created_by") var createdBy: UUID
    @Field(key: "created_at") var createdAt: Date

    init() {}

    init(eventId: UUID, role: EventMemberRole, createdBy: UUID) {
        self.id = UUID()
        self.code = Self.newCode()
        self.eventId = eventId
        self.role = role.rawValue
        self.createdBy = createdBy
        self.createdAt = Date()
    }

    var memberRole: EventMemberRole { EventMemberRole(rawValue: role) ?? .viewer }

    func toDTO() -> EventInviteLink {
        EventInviteLink(
            code: code,
            eventID: eventId,
            role: memberRole,
            createdAt: createdAt
        )
    }

    private static func newCode() -> String {
        Data((0..<16).map { _ in UInt8.random(in: 0...255) })
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

struct CreateEventInviteLink: AsyncMigration {
    var name: String { "CreateEventInviteLink" }
    func prepare(on database: Database) async throws {
        try await database.schema(EventInviteLinkModel.schema)
            .field("id", .uuid, .identifier(auto: false))
            .field("code", .string, .required)
            .field("event_id", .uuid, .required, .references(EventModel.schema, "id", onDelete: .cascade))
            .field("role", .string, .required)
            .field("created_by", .uuid, .required)
            .field("created_at", .datetime, .required)
            .unique(on: "code")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(EventInviteLinkModel.schema).delete()
    }
}
