import Vapor
import Fluent
import EncoreMomentCore

func routes(_ app: Application) throws {
    app.get { _ async in "EncoreMoment API is up" }
    app.get("health") { _ async in ["status": "ok"] }

    try app.register(collection: UploadController())
    try app.register(collection: AuthController())
    try app.register(collection: CreatorController())
    try app.register(collection: EventController())
    try app.register(collection: FanController())
    try app.register(collection: AnalyticsController())
    try app.register(collection: SocialController())
    try app.register(collection: ReportController())
    try app.register(collection: NotificationController())
}

struct CreatorController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let creators = routes.grouped("creators")
        // Optional auth on reads: lets signed-in viewers' blocks filter results.
        let readable = creators.grouped(UserToken.authenticator())
        readable.get(use: index)
        readable.get(":id", use: show)

        let protected = creators.grouped(UserToken.authenticator(), UserToken.guardMiddleware())
        protected.put(":id", use: update)
    }

    func index(req: Request) async throws -> [Creator] {
        var query = CreatorModel.query(on: req.db)
        let blocked = try await Moderation.blockedCreatorIDs(for: req)
        if !blocked.isEmpty {
            query = query.filter(\.$id !~ Array(blocked))
        }
        return try await query
            .sort(\.$displayName)
            .all()
            .map { $0.toDTO() }
    }

    func show(req: Request) async throws -> Creator {
        guard let id = req.parameters.get("id", as: UUID.self) else { throw Abort(.badRequest) }
        guard let model = try await CreatorModel.find(id, on: req.db) else { throw Abort(.notFound) }
        return model.toDTO()
    }

    /// Update a creator profile. Only the owning user may edit their own profile.
    func update(req: Request) async throws -> Creator {
        let token = try req.auth.require(UserToken.self)
        guard let id = req.parameters.get("id", as: UUID.self) else { throw Abort(.badRequest) }
        guard try id == token.requireCreatorID() else { throw Abort(.forbidden) }
        guard let existing = try await CreatorModel.find(id, on: req.db) else { throw Abort(.notFound) }

        let dto = try req.content.decode(Creator.self)
        guard Creator.isValidHandle(dto.handle) else {
            throw Abort(.unprocessableEntity, reason: "Handle must be 3–30 lowercase letters, digits or underscores.")
        }
        guard !dto.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Abort(.unprocessableEntity, reason: "Display name is required.")
        }
        if let taken = try await CreatorModel.query(on: req.db).filter(\.$handle == dto.handle).first(),
           taken.id != existing.id {
            throw Abort(.conflict, reason: "That handle is taken.")
        }
        existing.apply(dto)
        try await existing.save(on: req.db)
        return existing.toDTO()
    }
}

struct EventController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let events = routes.grouped("events")
        // Optional auth on reads: lets signed-in viewers' blocks filter results.
        let readable = events.grouped(UserToken.authenticator())
        readable.get(use: index)
        readable.get(":id", use: show)

        let protected = events.grouped(UserToken.authenticator(), UserToken.guardMiddleware())
        protected.post(use: create)
        protected.put(":id", use: update)
        protected.delete(":id", use: delete)
        protected.post(":id", "uploads", use: uploadMedia)
        protected.post(":id", "media", use: addMedia)
        protected.delete(":id", "media", ":mediaId", use: removeMedia)
        protected.get(":id", "members", use: listMembers)
        protected.post(":id", "members", use: inviteMember)
        protected.delete(":id", "members", ":creatorId", use: removeMember)
        protected.get(":id", "membership", use: myMembership)
    }

    func index(req: Request) async throws -> [Event] {
        var query = EventModel.query(on: req.db).with(\.$media)
        if let published = req.query[Bool.self, at: "published"], published {
            query = query.filter(\.$isPublished == true)
        }
        if let creator = req.query[UUID.self, at: "creator"] {
            query = query.filter(\.$creatorId == creator)
        }
        let blocked = try await Moderation.blockedCreatorIDs(for: req)
        if !blocked.isEmpty {
            query = query.filter(\.$creatorId !~ Array(blocked))
        }
        var events = try await query.sort(\.$date, .descending).all()
        // Invite-only events are visible to their owner and invited members.
        if events.contains(where: \.inviteOnly) {
            let creatorId = req.auth.get(UserToken.self)?.creatorId
            var memberEventIds = Set<UUID>()
            if let creatorId {
                memberEventIds = try await EventAccess.memberEventIDs(for: creatorId, on: req.db)
            }
            events = events.filter {
                !$0.inviteOnly || $0.creatorId == creatorId || memberEventIds.contains($0.id ?? UUID())
            }
        }
        return events.map { $0.toDTO() }
    }

    func show(req: Request) async throws -> Event {
        let model = try await loadEvent(req)
        guard try await EventAccess.canView(model, on: req) else {
            throw Abort(.forbidden, reason: "This event is invite-only.")
        }
        var dto = model.toDTO()
        let blockedUsers = try await Moderation.blockedUserIDs(for: req)
        if !blockedUsers.isEmpty {
            dto.media = dto.media.filter {
                guard let uploaderID = $0.uploaderID else { return true }
                return !blockedUsers.contains(uploaderID)
            }
        }
        return dto
    }

    func create(req: Request) async throws -> Event {
        let token = try req.auth.require(UserToken.self)
        let dto = try req.content.decode(Event.self)
        guard Event.isValidTitle(dto.title) else {
            throw Abort(.unprocessableEntity, reason: "Event title must be 1–100 characters.")
        }
        // Ownership: the event is always attributed to the authenticated creator.
        let creatorId = try token.requireCreatorID()
        let model = EventModel(from: dto)
        model.creatorId = creatorId
        return try await req.db.transaction { db in
            try await model.create(on: db)
            for item in dto.media {
                let media = MediaModel(from: item)
                media.$event.id = dto.id
                try await media.create(on: db)
            }
            return try await Self.reload(dto.id, on: db).toDTO()
        }
    }

    func update(req: Request) async throws -> Event {
        let token = try req.auth.require(UserToken.self)
        guard let id = req.parameters.get("id", as: UUID.self) else { throw Abort(.badRequest) }
        let dto = try req.content.decode(Event.self)
        guard Event.isValidTitle(dto.title) else {
            throw Abort(.unprocessableEntity, reason: "Event title must be 1–100 characters.")
        }
        let model = try await Self.requireOwnedEvent(id, token: token, on: req.db)
        return try await req.db.transaction { db in
            model.applyFields(dto)
            model.creatorId = try token.requireCreatorID()
            try await model.save(on: db)
            try await MediaModel.query(on: db).filter(\.$event.$id == id).delete()
            for item in dto.media {
                let media = MediaModel(from: item)
                media.$event.id = id
                try await media.create(on: db)
            }
            return try await Self.reload(id, on: db).toDTO()
        }
    }

    func delete(req: Request) async throws -> HTTPStatus {
        let token = try req.auth.require(UserToken.self)
        guard let id = req.parameters.get("id", as: UUID.self) else { throw Abort(.badRequest) }
        let model = try await Self.requireOwnedEvent(id, token: token, on: req.db)
        try await model.delete(on: req.db)
        return .noContent
    }

    func addMedia(req: Request) async throws -> MediaItem {
        let token = try req.auth.require(UserToken.self)
        guard let eventId = req.parameters.get("id", as: UUID.self) else { throw Abort(.badRequest) }
        let event = try await Self.requireMediaUploadAllowed(eventId, token: token, on: req.db)
        var dto = try req.content.decode(MediaItem.self)
        dto.sortOrder = try await Self.nextSortOrder(eventId, on: req.db)
        let uploaderID = try token.requireUserID()
        dto.uploaderID = uploaderID
        dto.uploaderName = try await Self.displayName(for: uploaderID, on: req.db)
        dto.isOfficial = try await EventAccess.isOfficialUploader(event, token: token, on: req.db)
        let media = MediaModel(from: dto)
        media.$event.id = eventId
        try await media.create(on: req.db)
        try await Self.notifyCommunityUploadIfNeeded(eventId, token: token, on: req.db)
        return media.toDTO()
    }

    func uploadMedia(req: Request) async throws -> MediaItem {
        let token = try req.auth.require(UserToken.self)
        guard let eventId = req.parameters.get("id", as: UUID.self) else { throw Abort(.badRequest) }
        let event = try await Self.requireMediaUploadAllowed(eventId, token: token, on: req.db)

        let body = try req.content.decode(MediaUploadRequest.self)
        let mediaURL = try await UploadStorage.save(
            body.file,
            fallbackExtension: body.kind == .video ? "mp4" : "jpg",
            req: req
        )
        let thumbnailURL: URL?
        if let thumbnail = body.thumbnail {
            thumbnailURL = try await UploadStorage.save(thumbnail, fallbackExtension: "jpg", req: req)
        } else {
            thumbnailURL = nil
        }
        let uploaderID = try token.requireUserID()
        let dto = MediaItem(
            eventId: eventId,
            kind: body.kind,
            url: mediaURL,
            thumbnailURL: thumbnailURL ?? (body.kind == .photo ? mediaURL : nil),
            uploaderID: uploaderID,
            uploaderName: try await Self.displayName(for: uploaderID, on: req.db),
            isOfficial: try await EventAccess.isOfficialUploader(event, token: token, on: req.db),
            sortOrder: try await Self.nextSortOrder(eventId, on: req.db)
        )
        let media = MediaModel(from: dto)
        media.$event.id = eventId
        try await media.create(on: req.db)
        try await Self.notifyCommunityUploadIfNeeded(eventId, token: token, on: req.db)
        return media.toDTO()
    }

    func removeMedia(req: Request) async throws -> HTTPStatus {
        let token = try req.auth.require(UserToken.self)
        guard let eventId = req.parameters.get("id", as: UUID.self),
              let mediaId = req.parameters.get("mediaId", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        guard let media = try await MediaModel.query(on: req.db)
            .filter(\.$id == mediaId)
            .filter(\.$event.$id == eventId)
            .first() else {
            throw Abort(.notFound)
        }
        let event = try await Self.requireExistingEvent(eventId, on: req.db)
        let userId = try token.requireUserID()
        guard token.creatorId == event.creatorId || media.uploaderId == userId else {
            throw Abort(.forbidden, reason: "You can only delete media you added.")
        }
        try await media.delete(on: req.db)
        return .noContent
    }

    // MARK: Members (invited viewers & collaborators)

    /// Full member list — owner only.
    func listMembers(req: Request) async throws -> [EventMember] {
        let token = try req.auth.require(UserToken.self)
        let event = try await Self.requireExistingEvent(try eventIdParam(req), on: req.db)
        guard token.creatorId == event.creatorId else { throw Abort(.forbidden) }
        return try await Self.memberDTOs(eventId: try event.requireID(), on: req.db)
    }

    /// The caller's own membership — used by the app to decide whether the
    /// viewer may upload. `member` is nil for non-members (including the owner,
    /// who already has full access).
    func myMembership(req: Request) async throws -> EventMembershipResponse {
        let token = try req.auth.require(UserToken.self)
        let event = try await Self.requireExistingEvent(try eventIdParam(req), on: req.db)
        guard let creatorId = token.creatorId else { return EventMembershipResponse(member: nil) }
        guard let row = try await EventMemberModel.query(on: req.db)
            .filter(\.$eventId == event.requireID())
            .filter(\.$creatorId == creatorId)
            .first() else {
            return EventMembershipResponse(member: nil)
        }
        guard let creator = try await CreatorModel.find(row.creatorId, on: req.db) else {
            return EventMembershipResponse(member: nil)
        }
        return EventMembershipResponse(member: Self.memberDTO(row, creator: creator))
    }

    /// Invites a creator by handle as a viewer or collaborator (owner only).
    /// Re-inviting an existing member updates their role.
    func inviteMember(req: Request) async throws -> [EventMember] {
        let token = try req.auth.require(UserToken.self)
        let event = try await Self.requireOwnedEvent(try eventIdParam(req), token: token, on: req.db)
        let invite = try req.content.decode(EventInviteRequest.self)
        let handle = invite.handle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .lowercased()
        guard let creator = try await CreatorModel.query(on: req.db)
            .filter(\.$handle == handle).first() else {
            throw Abort(.notFound, reason: "No creator found with handle \"\(handle)\".")
        }
        guard creator.id != event.creatorId else {
            throw Abort(.badRequest, reason: "The event's owner can't be invited.")
        }
        let eventId = try event.requireID()
        let creatorId = try creator.requireID()
        if let existing = try await EventMemberModel.query(on: req.db)
            .filter(\.$eventId == eventId).filter(\.$creatorId == creatorId).first() {
            existing.role = invite.role.rawValue
            try await existing.save(on: req.db)
        } else {
            try await EventMemberModel(eventId: eventId, creatorId: creatorId, role: invite.role)
                .create(on: req.db)
            let ownerName = try await Self.creatorName(for: event.creatorId, on: req.db)
            let action = invite.role == .collaborator ? "collaborate on" : "view"
            try await NotificationCenter.notifyCreator(
                creatorId: creatorId,
                kind: .invite,
                title: "Event invite",
                body: "\(ownerName) invited you to \(action) \(event.title).",
                eventId: eventId,
                on: req.db
            )
        }
        return try await Self.memberDTOs(eventId: eventId, on: req.db)
    }

    /// Removes an invited member — the owner, or the member removing themselves.
    func removeMember(req: Request) async throws -> [EventMember] {
        let token = try req.auth.require(UserToken.self)
        let event = try await Self.requireExistingEvent(try eventIdParam(req), on: req.db)
        guard let creatorId = req.parameters.get("creatorId", as: UUID.self) else { throw Abort(.badRequest) }
        guard token.creatorId == event.creatorId || token.creatorId == creatorId else {
            throw Abort(.forbidden)
        }
        try await EventMemberModel.query(on: req.db)
            .filter(\.$eventId == event.requireID()).filter(\.$creatorId == creatorId).delete()
        return try await Self.memberDTOs(eventId: try event.requireID(), on: req.db)
    }

    // MARK: Helpers

    private func eventIdParam(_ req: Request) throws -> UUID {
        guard let id = req.parameters.get("id", as: UUID.self) else { throw Abort(.badRequest) }
        return id
    }

    private static func memberDTO(_ row: EventMemberModel, creator: CreatorModel) -> EventMember {
        EventMember(
            id: (try? row.requireID()) ?? UUID(),
            eventID: row.eventId,
            creatorID: row.creatorId,
            role: row.memberRole,
            displayName: creator.displayName,
            handle: creator.handle
        )
    }

    private static func memberDTOs(eventId: UUID, on db: Database) async throws -> [EventMember] {
        let rows = try await EventMemberModel.query(on: db).filter(\.$eventId == eventId).all()
        var result: [EventMember] = []
        for row in rows {
            if let creator = try await CreatorModel.find(row.creatorId, on: db) {
                result.append(memberDTO(row, creator: creator))
            }
        }
        return result.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private static func creatorName(for creatorId: UUID, on db: Database) async throws -> String {
        try await CreatorModel.find(creatorId, on: db)?.displayName ?? "Someone"
    }

    private func loadEvent(_ req: Request) async throws -> EventModel {
        guard let id = req.parameters.get("id", as: UUID.self) else { throw Abort(.badRequest) }
        return try await Self.reload(id, on: req.db)
    }

    /// Loads an event and asserts the token's creator owns it.
    private static func requireOwnedEvent(_ id: UUID, token: UserToken, on db: Database) async throws -> EventModel {
        let creatorId = try token.requireCreatorID()
        let model = try await requireExistingEvent(id, on: db)
        guard model.creatorId == creatorId else { throw Abort(.forbidden) }
        return model
    }

    private static func requireExistingEvent(_ id: UUID, on db: Database) async throws -> EventModel {
        guard let model = try await EventModel.find(id, on: db) else { throw Abort(.notFound) }
        return model
    }

    /// Loads the event and asserts the token's user may add media to it
    /// (owner, invited collaborator, or anyone when community uploads are on).
    private static func requireMediaUploadAllowed(_ id: UUID, token: UserToken, on db: Database) async throws -> EventModel {
        _ = try token.requireUserID()
        guard let model = try await EventModel.find(id, on: db) else { throw Abort(.notFound) }
        guard try await EventAccess.canUpload(model, token: token, on: db) else {
            throw Abort(.forbidden, reason: "You don't have permission to add media to this event.")
        }
        return model
    }

    private static func nextSortOrder(_ eventId: UUID, on db: Database) async throws -> Int {
        let count = try await MediaModel.query(on: db)
            .filter(\.$event.$id == eventId)
            .count()
        return count
    }

    private static func displayName(for userId: UUID, on db: Database) async throws -> String {
        guard let user = try await UserModel.find(userId, on: db) else { throw Abort(.notFound) }
        if let creatorId = user.creatorId, let creator = try await CreatorModel.find(creatorId, on: db) {
            return creator.displayName
        }
        return String(user.email.prefix(while: { $0 != "@" }))
    }

    private static func notifyCommunityUploadIfNeeded(_ eventId: UUID, token: UserToken, on db: Database) async throws {
        guard let event = try await EventModel.find(eventId, on: db),
              token.creatorId != event.creatorId else { return }
        let name = try await NotificationCenter.actorName(for: token.requireUserID(), on: db)
        try await NotificationCenter.notifyCreator(
            creatorId: event.creatorId,
            kind: .mediaUpload,
            title: "New media added",
            body: "\(name) added media to \(event.title).",
            eventId: eventId,
            on: db
        )
    }

    private static func reload(_ id: UUID, on db: Database) async throws -> EventModel {
        guard let model = try await EventModel.query(on: db)
            .filter(\.$id == id)
            .with(\.$media)
            .first() else {
            throw Abort(.notFound)
        }
        return model
    }

}

private struct MediaUploadRequest: Content {
    let kind: MediaKind
    let file: File
    let thumbnail: File?
}
