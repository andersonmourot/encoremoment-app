import Foundation

/// The like state of an event: how many users liked it and whether the current
/// viewer is one of them (`false` for anonymous viewers).
public struct LikeSummary: Codable, Sendable, Equatable, Identifiable {
    public let eventID: UUID
    public var count: Int
    public var likedByViewer: Bool
    public var id: UUID { eventID }

    public init(eventID: UUID, count: Int = 0, likedByViewer: Bool = false) {
        self.eventID = eventID
        self.count = count
        self.likedByViewer = likedByViewer
    }
}
