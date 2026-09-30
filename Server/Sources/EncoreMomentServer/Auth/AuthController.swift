import Vapor
import Fluent
import JWT
import EncoreMomentCore

struct RegisterRequest: Content {
    let email: String
    let password: String
    let displayName: String
    let handle: String
}

struct LoginRequest: Content {
    let email: String
    let password: String
}

struct ProfileRequest: Content {
    let displayName: String
    let handle: String
}

/// Returned on register/login. `creator` is nil only for older accounts without a profile.
struct AuthResponse: Content {
    let token: String
    let userId: UUID
    let creator: Creator?
}

/// Returned by `/auth/me` — the signed-in account, with its creator profile if any.
struct AccountResponse: Content {
    let id: UUID
    let email: String
    let creator: Creator?
}

struct AuthController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let auth = routes.grouped("auth")
        auth.post("register", use: register)
        auth.post("login", use: login)

        let protected = auth.grouped(UserToken.authenticator(), UserToken.guardMiddleware())
        protected.get("me", use: me)
        protected.post("profile", use: completeProfile)
        protected.post("avatar", use: uploadAvatar)
        protected.delete("account", use: deleteAccount)
    }

    func register(req: Request) async throws -> AuthResponse {
        let body = try req.content.decode(RegisterRequest.self)
        let email = body.email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        guard email.contains("@"), email.count >= 3 else {
            throw Abort(.unprocessableEntity, reason: "A valid email is required.")
        }
        guard body.password.count >= 8 else {
            throw Abort(.unprocessableEntity, reason: "Password must be at least 8 characters.")
        }
        guard Creator.isValidHandle(body.handle) else {
            throw Abort(.unprocessableEntity, reason: "Handle must be 3–30 lowercase letters, digits or underscores.")
        }
        guard try await UserModel.query(on: req.db).filter(\.$email == email).first() == nil else {
            throw Abort(.conflict, reason: "An account with that email already exists.")
        }
        guard try await CreatorModel.query(on: req.db).filter(\.$handle == body.handle).first() == nil else {
            throw Abort(.conflict, reason: "That handle is taken.")
        }

        let creator = Creator(displayName: body.displayName, handle: body.handle)
        let creatorModel = CreatorModel(from: creator)
        let hash = try await req.password.async.hash(body.password)
        let user = UserModel(email: email, passwordHash: hash, creatorId: creator.id)

        try await req.db.transaction { db in
            try await creatorModel.create(on: db)
            try await user.create(on: db)
        }

        return try await makeResponse(for: user, creator: creator, req: req)
    }

    func login(req: Request) async throws -> AuthResponse {
        let body = try req.content.decode(LoginRequest.self)
        let email = body.email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        guard let user = try await UserModel.query(on: req.db).filter(\.$email == email).first() else {
            throw Abort(.unauthorized, reason: "Invalid email or password.")
        }
        guard try await req.password.async.verify(body.password, created: user.passwordHash) else {
            throw Abort(.unauthorized, reason: "Invalid email or password.")
        }

        let creator = try await Self.creator(for: user, on: req.db)
        return try await makeResponse(for: user, creator: creator, req: req)
    }

    func me(req: Request) async throws -> AccountResponse {
        let token = try req.auth.require(UserToken.self)
        let userId = try token.requireUserID()
        guard let user = try await UserModel.find(userId, on: req.db) else { throw Abort(.notFound) }
        let creator = try await Self.creator(for: user, on: req.db)
        return AccountResponse(id: userId, email: user.email, creator: creator)
    }

    func completeProfile(req: Request) async throws -> AuthResponse {
        let token = try req.auth.require(UserToken.self)
        let userId = try token.requireUserID()
        let body = try req.content.decode(ProfileRequest.self)
        guard let user = try await UserModel.find(userId, on: req.db) else { throw Abort(.notFound) }

        if let existing = try await Self.creator(for: user, on: req.db) {
            return try await makeResponse(for: user, creator: existing, req: req)
        }
        guard Creator.isValidHandle(body.handle) else {
            throw Abort(.unprocessableEntity, reason: "Handle must be 3–30 lowercase letters, digits or underscores.")
        }
        guard !body.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Abort(.unprocessableEntity, reason: "Display name is required.")
        }
        guard try await CreatorModel.query(on: req.db).filter(\.$handle == body.handle).first() == nil else {
            throw Abort(.conflict, reason: "That handle is taken.")
        }

        let creator = Creator(displayName: body.displayName, handle: body.handle)
        let creatorModel = CreatorModel(from: creator)
        user.creatorId = creator.id
        try await req.db.transaction { db in
            try await creatorModel.create(on: db)
            try await user.save(on: db)
        }
        return try await makeResponse(for: user, creator: creator, req: req)
    }

    func uploadAvatar(req: Request) async throws -> Creator {
        let token = try req.auth.require(UserToken.self)
        let creatorId = try token.requireCreatorID()
        guard let creator = try await CreatorModel.find(creatorId, on: req.db) else {
            throw Abort(.notFound)
        }
        let body = try req.content.decode(AvatarUploadRequest.self)
        let avatarURL = try await UploadStorage.save(body.file, fallbackExtension: "jpg", req: req)
        creator.avatarURL = avatarURL.absoluteString
        try await creator.save(on: req.db)
        return creator.toDTO()
    }

    /// Permanently deletes the account, its creator profile, and everything
    /// attached to either (events, media, social rows, fan preferences).
    func deleteAccount(req: Request) async throws -> HTTPStatus {
        let token = try req.auth.require(UserToken.self)
        let userId = try token.requireUserID()
        guard let user = try await UserModel.find(userId, on: req.db) else {
            throw Abort(.notFound)
        }
        let creatorId = user.creatorId

        // Content owned via the creator profile.
        let eventIds: [UUID] = creatorId == nil ? [] : try await EventModel.query(on: req.db)
            .filter(\.$creatorId == creatorId!)
            .all()
            .compactMap(\.id)
        let eventMedia: [MediaModel] = eventIds.isEmpty ? [] : try await MediaModel.query(on: req.db)
            .filter(\.$event.$id ~~ eventIds)
            .all()
        // Media this user uploaded to other creators' events.
        let uploadedMedia = try await MediaModel.query(on: req.db)
            .filter(\.$uploaderId == userId)
            .all()
        let allMedia = eventMedia + uploadedMedia
        let allMediaIds = Set(allMedia.compactMap(\.id))

        // Comments authored by the user plus any left on their events.
        let authoredCommentIds = try await CommentModel.query(on: req.db)
            .filter(\.$userId == userId)
            .all()
            .compactMap(\.id)
        let eventCommentIds: [UUID] = eventIds.isEmpty ? [] : try await CommentModel.query(on: req.db)
            .filter(\.$eventId ~~ eventIds)
            .all()
            .compactMap(\.id)
        let allCommentIds = authoredCommentIds + eventCommentIds

        let avatarURL: String? = creatorId == nil ? nil
            : try await CreatorModel.find(creatorId!, on: req.db)?.avatarURL

        try await req.db.transaction { db in
            try await CommentLikeModel.query(on: db).filter(\.$userId == userId).delete()
            if !allCommentIds.isEmpty {
                try await CommentLikeModel.query(on: db).filter(\.$commentId ~~ allCommentIds).delete()
            }
            try await CommentModel.query(on: db).filter(\.$userId == userId).delete()
            try await EventLikeModel.query(on: db).filter(\.$userId == userId).delete()
            try await MediaLikeModel.query(on: db).filter(\.$userId == userId).delete()
            try await FavoriteModel.query(on: db).filter(\.$userId == userId).delete()
            try await FollowModel.query(on: db).filter(\.$userId == userId).delete()
            try await BlockModel.query(on: db).filter(\.$userId == userId).delete()
            try await ReportModel.query(on: db).filter(\.$userId == userId).delete()
            try await NotificationModel.query(on: db).filter(\.$userId == userId).delete()
            try await MediaModel.query(on: db).filter(\.$uploaderId == userId).delete()
            if let creatorId {
                // Their memberships on other people's events.
                try await EventMemberModel.query(on: db).filter(\.$creatorId == creatorId).delete()
            }

            if !eventIds.isEmpty {
                try await CommentModel.query(on: db).filter(\.$eventId ~~ eventIds).delete()
                try await EventLikeModel.query(on: db).filter(\.$eventId ~~ eventIds).delete()
                try await FavoriteModel.query(on: db).filter(\.$eventId ~~ eventIds).delete()
                try await EventStatsModel.query(on: db).filter(\.$id ~~ eventIds).delete()
                try await MediaModel.query(on: db).filter(\.$event.$id ~~ eventIds).delete()
                try await EventMemberModel.query(on: db).filter(\.$eventId ~~ eventIds).delete()
            }
            if !allMediaIds.isEmpty {
                try await MediaLikeModel.query(on: db).filter(\.$mediaId ~~ Array(allMediaIds)).delete()
            }
            let reportTargetIds = eventIds + allMediaIds + allCommentIds + (creatorId.map { [$0] } ?? [])
            if !reportTargetIds.isEmpty {
                try await ReportModel.query(on: db).filter(\.$targetId ~~ reportTargetIds).delete()
            }
            if let creatorId {
                try await EventModel.query(on: db).filter(\.$creatorId == creatorId).delete()
                try await FollowModel.query(on: db).filter(\.$creatorId == creatorId).delete()
                try await BlockModel.query(on: db).filter(\.$creatorId == creatorId).delete()
                if let creator = try await CreatorModel.find(creatorId, on: db) {
                    try await creator.delete(on: db)
                }
            }
            try await user.delete(on: db)
        }

        // Uploaded files are best-effort cleanup after the rows are gone.
        var fileURLs = allMedia.map(\.url) + allMedia.compactMap(\.thumbnailURL)
        if let avatarURL { fileURLs.append(avatarURL) }
        for raw in fileURLs {
            if let url = URL(string: raw) {
                await UploadStorage.delete(publicURL: url, req: req)
            }
        }
        return .noContent
    }

    /// Resolves the user's creator profile, if they have one.
    private static func creator(for user: UserModel, on db: Database) async throws -> Creator? {
        guard let creatorId = user.creatorId else { return nil }
        return try await CreatorModel.find(creatorId, on: db)?.toDTO()
    }

    private func makeResponse(for user: UserModel, creator: Creator?, req: Request) async throws -> AuthResponse {
        let userId = try user.requireID()
        let payload = UserToken(userId: userId, creatorId: creator?.id)
        let token = try await req.jwt.sign(payload)
        return AuthResponse(token: token, userId: userId, creator: creator)
    }
}

private struct AvatarUploadRequest: Content {
    let file: File
}
