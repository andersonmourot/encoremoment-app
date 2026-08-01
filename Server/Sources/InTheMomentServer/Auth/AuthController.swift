import Vapor
import Fluent
import JWT
import InTheMomentCore

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
