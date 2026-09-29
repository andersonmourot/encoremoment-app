import Vapor
import Fluent
import EncoreMomentCore

/// Event engagement analytics. Recording views/downloads is public (any viewer
/// contributes); reading stats is restricted to the creator who owns the event.
struct AnalyticsController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let events = routes.grouped("events")
        // Public increment endpoints.
        events.post(":id", "view", use: recordView)
        events.post(":id", "download", use: recordDownload)

        // Creator-only reads.
        let protected = events.grouped(UserToken.authenticator(), UserToken.guardMiddleware())
        protected.get(":id", "stats", use: stats)

        let me = routes.grouped("me").grouped(UserToken.authenticator(), UserToken.guardMiddleware())
        me.get("stats", use: creatorStats)
    }

    func recordView(req: Request) async throws -> HTTPStatus {
        let id = try eventId(req)
        let row = try await Self.loadOrCreate(id, on: req.db)
        row.viewCount += 1
        try await row.save(on: req.db)
        return .noContent
    }

    func recordDownload(req: Request) async throws -> HTTPStatus {
        let id = try eventId(req)
        let count = max(1, req.query[Int.self, at: "count"] ?? 1)
        let row = try await Self.loadOrCreate(id, on: req.db)
        row.downloadCount += count
        try await row.save(on: req.db)
        return .noContent
    }

    /// Stats for one event; only its owning creator may read them.
    func stats(req: Request) async throws -> EventStats {
        let token = try req.auth.require(UserToken.self)
        let id = try eventId(req)
        guard let event = try await EventModel.find(id, on: req.db) else { throw Abort(.notFound) }
        guard try event.creatorId == token.requireCreatorID() else { throw Abort(.forbidden) }
        let row = try await EventStatsModel.find(id, on: req.db)
        return row?.toDTO() ?? EventStats(eventID: id)
    }

    /// Stats for every event the authenticated creator owns (zero for events
    /// with no recorded engagement yet).
    func creatorStats(req: Request) async throws -> [EventStats] {
        let token = try req.auth.require(UserToken.self)
        let creatorId = try token.requireCreatorID()
        let events = try await EventModel.query(on: req.db)
            .filter(\.$creatorId == creatorId)
            .all()
        let ids = events.compactMap { $0.id }
        guard !ids.isEmpty else { return [] }
        let rows = try await EventStatsModel.query(on: req.db)
            .filter(\.$id ~~ ids)
            .all()
        var byId: [UUID: EventStats] = [:]
        for row in rows where row.id != nil { byId[row.id!] = row.toDTO() }
        return ids.map { byId[$0] ?? EventStats(eventID: $0) }
    }

    // MARK: Helpers

    private func eventId(_ req: Request) throws -> UUID {
        guard let id = req.parameters.get("id", as: UUID.self) else { throw Abort(.badRequest) }
        return id
    }

    /// Loads the stats row for an event, creating a zeroed one if absent.
    /// Throws `.notFound` for an unknown event (the row's id is an FK to events).
    private static func loadOrCreate(_ id: UUID, on db: Database) async throws -> EventStatsModel {
        if let existing = try await EventStatsModel.find(id, on: db) { return existing }
        guard try await EventModel.find(id, on: db) != nil else { throw Abort(.notFound) }
        let row = EventStatsModel(eventId: id)
        try await row.create(on: db)
        return row
    }
}
