import Vapor
import Fluent
import EncoreMomentCore

struct ReportController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let protected = routes.grouped(UserToken.authenticator(), UserToken.guardMiddleware())
        protected.get("reports", use: index)
        protected.post("reports", use: create)
        protected.delete("reports", ":id", use: delete)
    }

    func index(req: Request) async throws -> [Report] {
        let token = try req.auth.require(UserToken.self)
        _ = try token.requireCreatorID()
        return try await ReportModel.query(on: req.db)
            .sort(\.$createdAt, .descending)
            .all()
            .map { $0.toDTO() }
    }

    func create(req: Request) async throws -> HTTPStatus {
        let token = try req.auth.require(UserToken.self)
        let userId = try token.requireUserID()
        let body = try req.content.decode(ReportRequest.self)
        let details = body.details?.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = ReportRequest(
            targetType: body.targetType,
            targetID: body.targetID,
            eventID: body.eventID,
            reason: body.reason,
            details: details?.isEmpty == true ? nil : details
        )
        try await ReportModel(userId: userId, request: request).create(on: req.db)
        return .created
    }

    func delete(req: Request) async throws -> HTTPStatus {
        let token = try req.auth.require(UserToken.self)
        _ = try token.requireCreatorID()
        guard let id = req.parameters.get("id", as: UUID.self) else { throw Abort(.badRequest) }
        guard let report = try await ReportModel.find(id, on: req.db) else { throw Abort(.notFound) }
        try await report.delete(on: req.db)
        return .noContent
    }
}
