import Foundation

public enum AppNotificationKind: String, Codable, Sendable, CaseIterable {
    case comment
    case like
    case follow
    case mediaUpload
}

public struct AppNotification: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let kind: AppNotificationKind
    public let title: String
    public let body: String
    public let eventID: UUID?
    public let creatorID: UUID?
    public var isRead: Bool
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: AppNotificationKind,
        title: String,
        body: String,
        eventID: UUID? = nil,
        creatorID: UUID? = nil,
        isRead: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.eventID = eventID
        self.creatorID = creatorID
        self.isRead = isRead
        self.createdAt = createdAt
    }
}
