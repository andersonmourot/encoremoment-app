import Foundation

/// Abstracts comments and likes on events. Reading is public; posting/deleting
/// comments and toggling likes require an authenticated transport in the API
/// implementation.
public protocol SocialStore: Sendable {
    /// Comments for an event, oldest first.
    func comments(forEvent eventID: UUID) async throws -> [Comment]
    /// Comments on one media item within an event, oldest first.
    func comments(forMedia mediaID: UUID, in eventID: UUID) async throws -> [Comment]
    /// Posts a comment as the authenticated user; returns the created comment.
    @discardableResult
    func addComment(eventID: UUID, body: String) async throws -> Comment
    /// Posts a comment on a specific media item inside an event.
    @discardableResult
    func addComment(mediaID: UUID, eventID: UUID, body: String) async throws -> Comment
    /// Media the signed-in viewer has liked (the profile "Liked" section).
    func likedMedia() async throws -> [MediaItem]
    /// Deletes a comment (author or the event's creator only).
    func deleteComment(id: UUID, eventID: UUID) async throws
    func commentLikeSummary(commentID: UUID, eventID: UUID) async throws -> LikeSummary
    @discardableResult
    func setCommentLike(commentID: UUID, eventID: UUID, _ liked: Bool) async throws -> LikeSummary
    func mediaLikeSummary(mediaID: UUID, eventID: UUID) async throws -> LikeSummary
    @discardableResult
    func setMediaLike(mediaID: UUID, eventID: UUID, _ liked: Bool) async throws -> LikeSummary
    /// The like count and the viewer's like state for an event.
    func likeSummary(forEvent eventID: UUID) async throws -> LikeSummary
    /// Event, media, and comment like summaries in a single call.
    func likeSummaries(forEvent eventID: UUID) async throws -> EventLikeSummaries
    /// Sets the viewer's like state; returns the updated summary.
    @discardableResult
    func setLike(eventID: UUID, _ liked: Bool) async throws -> LikeSummary
}

/// In-memory ``SocialStore`` for tests and previews. All comments are attributed
/// to a single configured viewer, whose likes drive `likedByViewer`.
public actor InMemorySocialStore: SocialStore {
    private var commentsByEvent: [UUID: [Comment]] = [:]
    private var likesByEvent: [UUID: Set<UUID>] = [:]
    private var likesByComment: [UUID: Set<UUID>] = [:]
    private var likesByMedia: [UUID: Set<UUID>] = [:]
    private let viewerID: UUID
    private let viewerName: String

    public init(viewerID: UUID = UUID(), viewerName: String = "You", comments: [Comment] = []) {
        self.viewerID = viewerID
        self.viewerName = viewerName
        for comment in comments {
            commentsByEvent[comment.eventID, default: []].append(comment)
        }
    }

    public func comments(forEvent eventID: UUID) async throws -> [Comment] {
        (commentsByEvent[eventID] ?? [])
            .filter { $0.mediaID == nil }
            .sorted { $0.createdAt < $1.createdAt }
    }

    public func comments(forMedia mediaID: UUID, in eventID: UUID) async throws -> [Comment] {
        (commentsByEvent[eventID] ?? [])
            .filter { $0.mediaID == mediaID }
            .sorted { $0.createdAt < $1.createdAt }
    }

    @discardableResult
    public func addComment(eventID: UUID, body: String) async throws -> Comment {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Comment.isValidBody(trimmed) else { throw SocialStoreError.invalidComment }
        let comment = Comment(
            eventID: eventID,
            authorID: viewerID,
            authorName: viewerName,
            body: trimmed
        )
        commentsByEvent[eventID, default: []].append(comment)
        return comment
    }

    @discardableResult
    public func addComment(mediaID: UUID, eventID: UUID, body: String) async throws -> Comment {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Comment.isValidBody(trimmed) else { throw SocialStoreError.invalidComment }
        let comment = Comment(
            eventID: eventID,
            mediaID: mediaID,
            authorID: viewerID,
            authorName: viewerName,
            body: trimmed
        )
        commentsByEvent[eventID, default: []].append(comment)
        return comment
    }

    /// The in-memory store doesn't hold media items — the API store serves
    /// this from `GET /me/liked-media`.
    public func likedMedia() async throws -> [MediaItem] { [] }

    public func deleteComment(id: UUID, eventID: UUID) async throws {
        commentsByEvent[eventID]?.removeAll { $0.id == id }
    }

    public func commentLikeSummary(commentID: UUID, eventID: UUID) async throws -> LikeSummary {
        let likes = likesByComment[commentID] ?? []
        return LikeSummary(eventID: commentID, count: likes.count, likedByViewer: likes.contains(viewerID))
    }

    @discardableResult
    public func setCommentLike(commentID: UUID, eventID: UUID, _ liked: Bool) async throws -> LikeSummary {
        if liked {
            likesByComment[commentID, default: []].insert(viewerID)
        } else {
            likesByComment[commentID]?.remove(viewerID)
        }
        return try await commentLikeSummary(commentID: commentID, eventID: eventID)
    }

    public func mediaLikeSummary(mediaID: UUID, eventID: UUID) async throws -> LikeSummary {
        let likes = likesByMedia[mediaID] ?? []
        return LikeSummary(eventID: mediaID, count: likes.count, likedByViewer: likes.contains(viewerID))
    }

    @discardableResult
    public func setMediaLike(mediaID: UUID, eventID: UUID, _ liked: Bool) async throws -> LikeSummary {
        if liked {
            likesByMedia[mediaID, default: []].insert(viewerID)
        } else {
            likesByMedia[mediaID]?.remove(viewerID)
        }
        return try await mediaLikeSummary(mediaID: mediaID, eventID: eventID)
    }

    public func likeSummary(forEvent eventID: UUID) async throws -> LikeSummary {
        let likes = likesByEvent[eventID] ?? []
        return LikeSummary(eventID: eventID, count: likes.count, likedByViewer: likes.contains(viewerID))
    }

    public func likeSummaries(forEvent eventID: UUID) async throws -> EventLikeSummaries {
        let media = likesByMedia.keys
            .map { LikeSummary(eventID: $0, count: (likesByMedia[$0] ?? []).count, likedByViewer: (likesByMedia[$0] ?? []).contains(viewerID)) }
        let comments = (commentsByEvent[eventID] ?? []).map { comment in
            let likes = likesByComment[comment.id] ?? []
            return LikeSummary(eventID: comment.id, count: likes.count, likedByViewer: likes.contains(viewerID))
        }
        return EventLikeSummaries(event: try await likeSummary(forEvent: eventID), media: media, comments: comments)
    }

    @discardableResult
    public func setLike(eventID: UUID, _ liked: Bool) async throws -> LikeSummary {
        if liked {
            likesByEvent[eventID, default: []].insert(viewerID)
        } else {
            likesByEvent[eventID]?.remove(viewerID)
        }
        return try await likeSummary(forEvent: eventID)
    }
}

public enum SocialStoreError: Error, Equatable, Sendable {
    case invalidComment
}
