import Vapor
import Fluent
import FluentSQLiteDriver
import JWT
import SQLKit

public func configure(_ app: Application) async throws {
    // JWT signing key (set JWT_SECRET in production).
    let secret = Environment.get("JWT_SECRET") ?? "dev-secret-change-me-in-production"
    await app.jwt.keys.add(hmac: .init(from: Array(secret.utf8)), digestAlgorithm: .sha256)

    // JSON coders that match the iOS app's APIEventStore contract (ISO-8601 dates).
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    ContentConfiguration.global.use(encoder: encoder, for: .json)
    ContentConfiguration.global.use(decoder: decoder, for: .json)

    // Media/avatar uploads need to accept normal phone photos and short videos.
    app.routes.defaultMaxBodySize = "100mb"

    // SQLite on a configurable path (a Fly volume in production).
    let dbPath = Environment.get("DATABASE_PATH") ?? "db.sqlite"
    app.databases.use(.sqlite(.file(dbPath)), as: .sqlite)

    let uploadsPath = Environment.get("UPLOADS_PATH") ?? defaultUploadsPath(dbPath: dbPath, workingDirectory: app.directory.workingDirectory)
    try FileManager.default.createDirectory(
        at: URL(fileURLWithPath: uploadsPath, isDirectory: true),
        withIntermediateDirectories: true
    )
    app.storage[UploadsConfigurationKey.self] = UploadsConfiguration(
        directory: uploadsPath,
        r2: R2Configuration.fromEnvironment()
    )

    app.migrations.add(CreateCreator())
    app.migrations.add(AddCreatorAccentColor())
    app.migrations.add(AddCreatorHandleCaseIndex())
    app.migrations.add(CreateEvent())
    app.migrations.add(AddEventCommunityUploads())
    app.migrations.add(CreateMedia())
    app.migrations.add(AddMediaSortOrder())
    app.migrations.add(AddMediaUploader())
    app.migrations.add(CreateUser())
    app.migrations.add(MakeUserCreatorOptional())
    app.migrations.add(CreateFavorite())
    app.migrations.add(CreateFollow())
    app.migrations.add(CreateBlock())
    app.migrations.add(CreateEventStats())
    app.migrations.add(CreateComment())
    app.migrations.add(CreateEventLike())
    app.migrations.add(CreateCommentLike())
    app.migrations.add(CreateMediaLike())
    app.migrations.add(CreateReport())
    app.migrations.add(CreateNotification())
    app.migrations.add(AddEventInviteOnly())
    app.migrations.add(AddMediaOfficial())
    app.migrations.add(CreateEventMember())
    app.migrations.add(CreateEventInviteLink())
    app.migrations.add(CreateDeviceToken())
    app.migrations.add(AddCommentMediaId())

    // The InTheMomentServer -> EncoreMomentServer module rename changed the
    // qualified names Fluent recorded in _fluent_migrations, so an existing
    // database would look unmigrated and every prepare would fail. Migrations
    // now declare stable names; rewrite old records to match. No-ops on a
    // fresh database (the table doesn't exist yet) and on already-fixed ones.
    if let sql = app.db(.sqlite) as? any SQLDatabase {
        try? await sql.raw("""
        UPDATE _fluent_migrations SET name = REPLACE(name, 'InTheMomentServer.', '')
        WHERE name LIKE 'InTheMomentServer.%'
        """).run()
        try? await sql.raw("""
        UPDATE _fluent_migrations SET name = REPLACE(name, 'EncoreMomentServer.', '')
        WHERE name LIKE 'EncoreMomentServer.%'
        """).run()
    }
    PushService.configure(app: app)

    try await app.autoMigrate()

    // Re-home any media that landed on the local uploads volume while R2 was
    // misconfigured. No-ops when R2 isn't configured or nothing is local.
    await UploadStorage.migrateLocalUploadsToR2(app: app)

    // Drop creator profiles whose owning account no longer exists — keeps
    // them out of Search suggestions after partial deletes.
    await purgeOrphanCreators(app: app)

    try await seedIfEmpty(app)

    try routes(app)
}

/// Deletes creator profiles that no user account references and that own no
/// events — leftovers from partial deletes. Seed/demo creators own events, so
/// they're never touched.
private func purgeOrphanCreators(app: Application) async {
    do {
        let linkedIDs = Set(try await UserModel.query(on: app.db).all().compactMap(\.creatorId))
        let ownedEventCreators = Set(try await EventModel.query(on: app.db).all().map(\.creatorId))
        let orphans = try await CreatorModel.query(on: app.db).all().filter { model in
            guard let id = model.id else { return false }
            return !linkedIDs.contains(id) && !ownedEventCreators.contains(id)
        }
        for orphan in orphans {
            if let id = orphan.id {
                try await FollowModel.query(on: app.db).filter(\.$creatorId == id).delete()
                try await EventMemberModel.query(on: app.db).filter(\.$creatorId == id).delete()
            }
            try await orphan.delete(on: app.db)
        }
        if !orphans.isEmpty {
            app.logger.info("Purged \(orphans.count) orphan creator profile(s).")
        }
    } catch {
        app.logger.warning("Orphan-creator sweep failed: \(error)")
    }
}

private func defaultUploadsPath(dbPath: String, workingDirectory: String) -> String {
    if dbPath.contains("/") {
        return URL(fileURLWithPath: dbPath)
            .deletingLastPathComponent()
            .appendingPathComponent("uploads", isDirectory: true)
            .path
    }
    return URL(fileURLWithPath: workingDirectory, isDirectory: true)
        .appendingPathComponent("uploads", isDirectory: true)
        .path
}
