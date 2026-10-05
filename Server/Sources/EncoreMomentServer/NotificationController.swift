import Vapor
import Fluent
import EncoreMomentCore

struct NotificationController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let me = routes.grouped("me")
            .grouped(UserToken.authenticator(), UserToken.guardMiddleware())
        me.get("notifications", use: index)
        me.post("notifications", ":id", "read", use: markRead)
        me.post("notifications", "read-all", use: markAllRead)
    }

    func index(req: Request) async throws -> [AppNotification] {
        let userId = try req.auth.require(UserToken.self).requireUserID()
        return try await NotificationModel.query(on: req.db)
            .filter(\.$userId == userId)
            .sort(\.$createdAt, .descending)
            .limit(100)
            .all()
            .map { $0.toDTO() }
    }

    func markRead(req: Request) async throws -> AppNotification {
        let userId = try req.auth.require(UserToken.self).requireUserID()
        guard let id = req.parameters.get("id", as: UUID.self),
              let notification = try await NotificationModel.find(id, on: req.db),
              notification.userId == userId else {
            throw Abort(.notFound)
        }
        notification.isRead = true
        try await notification.save(on: req.db)
        return notification.toDTO()
    }

    func markAllRead(req: Request) async throws -> HTTPStatus {
        let userId = try req.auth.require(UserToken.self).requireUserID()
        let rows = try await NotificationModel.query(on: req.db)
            .filter(\.$userId == userId)
            .filter(\.$isRead == false)
            .all()
        for row in rows {
            row.isRead = true
            try await row.save(on: req.db)
        }
        return .noContent
    }
}

enum NotificationCenter {
    static func notifyCreator(
        creatorId: UUID,
        kind: AppNotificationKind,
        title: String,
        body: String,
        eventId: UUID? = nil,
        on db: Database
    ) async throws {
        guard let user = try await UserModel.query(on: db).filter(\.$creatorId == creatorId).first(),
              let userId = user.id else {
            return
        }
        try await NotificationModel(
            userId: userId,
            kind: kind,
            title: title,
            body: body,
            eventId: eventId,
            creatorId: creatorId
        ).create(on: db)
        // Best-effort push; no-ops when APNs isn't configured.
        await PushService.send(userId: userId, title: title, body: body, on: db, logger: db.logger)
    }

    /// Display name for the user who triggered a notification — their creator
    /// profile name when present, otherwise the local part of their email.
    static func actorName(for userId: UUID, on db: Database) async throws -> String {
        guard let user = try await UserModel.find(userId, on: db) else { return "Someone" }
        if let creatorId = user.creatorId,
           let creator = try await CreatorModel.find(creatorId, on: db) {
            return creator.displayName
        }
        return String(user.email.prefix(while: { $0 != "@" }))
    }
}
