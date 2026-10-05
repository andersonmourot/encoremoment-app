import Foundation

/// A page created by a creator that holds the photos and videos for one event.
/// Each event is independent and owns its own media collection.
public struct Event: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let creatorId: UUID
    public var title: String
    public var details: String?
    public var coverImageURL: URL?
    public var location: String?
    /// When the event itself took place.
    public var date: Date
    /// When the event page was created on the platform.
    public let createdAt: Date
    /// Whether the event is visible to viewers in Discover.
    public var isPublished: Bool
    /// Whether signed-in viewers can contribute their own media to this event.
    public var allowsCommunityUploads: Bool
    /// Whether only the owner and invited members can view this event.
    /// Invited collaborators can always upload regardless of
    /// `allowsCommunityUploads`.
    public var inviteOnly: Bool
    public var media: [MediaItem]
    /// Total event likes — populated by the API on feed reads so popular-first
    /// ordering and badges can be rendered without extra calls.
    public var likeCount: Int?

    public init(
        id: UUID = UUID(),
        creatorId: UUID,
        title: String,
        details: String? = nil,
        coverImageURL: URL? = nil,
        location: String? = nil,
        date: Date = Date(),
        createdAt: Date = Date(),
        isPublished: Bool = true,
        allowsCommunityUploads: Bool = false,
        inviteOnly: Bool = false,
        media: [MediaItem] = [],
        likeCount: Int? = nil
    ) {
        self.id = id
        self.creatorId = creatorId
        self.title = title
        self.details = details
        self.coverImageURL = coverImageURL
        self.location = location
        self.date = date
        self.createdAt = createdAt
        self.isPublished = isPublished
        self.allowsCommunityUploads = allowsCommunityUploads
        self.inviteOnly = inviteOnly
        self.media = media
        self.likeCount = likeCount
    }

    private enum CodingKeys: String, CodingKey {
        case id, creatorId, title, details, coverImageURL, location, date, createdAt
        case isPublished, allowsCommunityUploads, inviteOnly, media, likeCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        creatorId = try container.decode(UUID.self, forKey: .creatorId)
        title = try container.decode(String.self, forKey: .title)
        details = try container.decodeIfPresent(String.self, forKey: .details)
        coverImageURL = try container.decodeIfPresent(URL.self, forKey: .coverImageURL)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        date = try container.decode(Date.self, forKey: .date)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        isPublished = try container.decode(Bool.self, forKey: .isPublished)
        allowsCommunityUploads = try container.decodeIfPresent(Bool.self, forKey: .allowsCommunityUploads) ?? false
        inviteOnly = try container.decodeIfPresent(Bool.self, forKey: .inviteOnly) ?? false
        media = try container.decodeIfPresent([MediaItem].self, forKey: .media) ?? []
        likeCount = try container.decodeIfPresent(Int.self, forKey: .likeCount)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(creatorId, forKey: .creatorId)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(details, forKey: .details)
        try container.encodeIfPresent(coverImageURL, forKey: .coverImageURL)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encode(date, forKey: .date)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(isPublished, forKey: .isPublished)
        try container.encode(allowsCommunityUploads, forKey: .allowsCommunityUploads)
        try container.encode(inviteOnly, forKey: .inviteOnly)
        try container.encode(media, forKey: .media)
        try container.encodeIfPresent(likeCount, forKey: .likeCount)
    }

    public var photoCount: Int { media.lazy.filter { $0.kind == .photo }.count }
    public var videoCount: Int { media.lazy.filter { $0.kind == .video }.count }
    public var mediaCount: Int { media.count }
    /// Number of media items the creator allows fans to download.
    public var downloadableCount: Int { media.lazy.filter(\.isDownloadable).count }

    /// Cover image to display, falling back to the first media preview when no cover is set.
    public var displayCoverURL: URL? { coverImageURL ?? media.first?.previewURL }
}

public extension Event {
    /// Validates a title once trimmed: must be 1–100 characters.
    static func isValidTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return (1...100).contains(trimmed.count)
    }
}
