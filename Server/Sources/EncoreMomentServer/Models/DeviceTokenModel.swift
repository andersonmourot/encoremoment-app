import Fluent
import Foundation

/// A device's APNs push token, owned by one user account. Users can have
/// several rows (iPhone + iPad); replaced when the device token rotates.
final class DeviceTokenModel: Model, @unchecked Sendable {
    static let schema = "device_tokens"

    @ID(custom: "id", generatedBy: .user) var id: UUID?
    @Field(key: "user_id") var userId: UUID
    @Field(key: "token") var token: String
    @Field(key: "created_at") var createdAt: Date

    init() {}

    init(id: UUID = UUID(), userId: UUID, token: String) {
        self.id = id
        self.userId = userId
        self.token = token
        self.createdAt = Date()
    }
}

struct CreateDeviceToken: AsyncMigration {
    var name: String { "CreateDeviceToken" }
    func prepare(on database: Database) async throws {
        try await database.schema(DeviceTokenModel.schema)
            .field("id", .uuid, .identifier(auto: false))
            .field("user_id", .uuid, .required, .references(UserModel.schema, "id", onDelete: .cascade))
            .field("token", .string, .required)
            .field("created_at", .datetime, .required)
            .unique(on: "user_id", "token")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(DeviceTokenModel.schema).delete()
    }
}
