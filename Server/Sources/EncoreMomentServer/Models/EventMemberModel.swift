import Fluent
import Foundation
import EncoreMomentCore

/// A person invited to an event by its owner — as a viewer (can see invite-only
/// events) or a collaborator (can also upload, landing in the official section).
/// Members are keyed by creator id, matching follows and blocks.
final class EventMemberModel: Model, @unchecked Sendable {
    static let schema = "event_members"

    @ID(custom: "id", generatedBy: .user) var id: UUID?
    @Field(key: "event_id") var eventId: UUID
    @Field(key: "creator_id") var creatorId: UUID
    @Field(key: "role") var role: String

    init() {}

    init(id: UUID = UUID(), eventId: UUID, creatorId: UUID, role: EventMemberRole) {
        self.id = id
        self.eventId = eventId
        self.creatorId = creatorId
        self.role = role.rawValue
    }

    var memberRole: EventMemberRole { EventMemberRole(rawValue: role) ?? .viewer }
}

struct CreateEventMember: AsyncMigration {
    var name: String { "CreateEventMember" }
    func prepare(on database: Database) async throws {
        try await database.schema(EventMemberModel.schema)
            .field("id", .uuid, .identifier(auto: false))
            .field("event_id", .uuid, .required, .references(EventModel.schema, "id", onDelete: .cascade))
            .field("creator_id", .uuid, .required, .references(CreatorModel.schema, "id", onDelete: .cascade))
            .field("role", .string, .required)
            .unique(on: "event_id", "creator_id")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(EventMemberModel.schema).delete()
    }
}
