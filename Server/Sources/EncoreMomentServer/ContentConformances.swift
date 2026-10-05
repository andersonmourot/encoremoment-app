import Vapor
import EncoreMomentCore

// The Core DTOs are Codable & Sendable, so they can serve directly as Vapor
// request/response bodies. This keeps the API's JSON identical to what the iOS
// app's APIEventStore expects.
extension Creator: Content {}
extension Event: Content {}
extension MediaItem: Content {}
extension FanPreferences: Content {}
extension EventStats: Content {}
extension Comment: Content {}
extension LikeSummary: Content {}
extension ReportRequest: Content {}
extension Report: Content {}
extension AppNotification: Content {}
extension EventMember: Content {}
extension EventMembershipResponse: Content {}
extension EventInviteRequest: Content {}
extension EventLikeSummaries: Content {}
extension EventInviteLink: Content {}
extension InviteLinkCreateRequest: Content {}
extension InviteLinkPreview: Content {}
