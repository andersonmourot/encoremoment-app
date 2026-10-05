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

/// One-shot like state for everything on an event page — returned by
/// `GET /events/{id}/likes/all` so the client doesn't fan out one request
/// per media item and per comment.
public struct EventLikeSummaries: Codable, Sendable, Equatable {
    /// Likes on the event itself.
    public var event: LikeSummary
    /// Per-media summaries (`eventID` on each carries the media id).
    public var media: [LikeSummary]
    /// Per-comment summaries (`eventID` on each carries the comment id).
    public var comments: [LikeSummary]

    public init(event: LikeSummary, media: [LikeSummary] = [], comments: [LikeSummary] = []) {
        self.event = event
        self.media = media
        self.comments = comments
    }

    public var mediaByID: [UUID: LikeSummary] {
        Dictionary(uniqueKeysWithValues: media.map { ($0.eventID, $0) })
    }

    public var commentsByID: [UUID: LikeSummary] {
        Dictionary(uniqueKeysWithValues: comments.map { ($0.eventID, $0) })
    }
}
