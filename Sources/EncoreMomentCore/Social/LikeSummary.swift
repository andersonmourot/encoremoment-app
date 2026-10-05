import Foundation

/// The like state of an event: how many users liked it and whether the current
/// viewer is one of them (`false` for anonymous viewers).
public struct LikeSummary: Codable, Sendable, Equatable, Identifiable {
    public let eventID: UUID
    public var count: Int
    public var likedByViewer: Bool
    /// Number of comments on the target (only populated for media summaries).
    public var commentCount: Int
    public var id: UUID { eventID }

    public init(eventID: UUID, count: Int = 0, likedByViewer: Bool = false, commentCount: Int = 0) {
        self.eventID = eventID
        self.count = count
        self.likedByViewer = likedByViewer
        self.commentCount = commentCount
    }

    private enum CodingKeys: String, CodingKey {
        case eventID, count, likedByViewer, commentCount
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        eventID = try c.decode(UUID.self, forKey: .eventID)
        count = try c.decode(Int.self, forKey: .count)
        likedByViewer = try c.decode(Bool.self, forKey: .likedByViewer)
        commentCount = try c.decodeIfPresent(Int.self, forKey: .commentCount) ?? 0
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
