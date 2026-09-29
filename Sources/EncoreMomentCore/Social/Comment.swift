import Foundation

/// A text comment posted by an authenticated user on an event. `authorName` is
/// denormalized at creation time so it can be displayed without a second lookup.
public struct Comment: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let eventID: UUID
    /// The account id of the comment's author.
    public let authorID: UUID
    public let authorName: String
    public var body: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        eventID: UUID,
        authorID: UUID,
        authorName: String,
        body: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.eventID = eventID
        self.authorID = authorID
        self.authorName = authorName
        self.body = body
        self.createdAt = createdAt
    }
}

public extension Comment {
    /// Validates comment text once trimmed: must be 1–2000 characters.
    static func isValidBody(_ body: String) -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return (1...2000).contains(trimmed.count)
    }
}
