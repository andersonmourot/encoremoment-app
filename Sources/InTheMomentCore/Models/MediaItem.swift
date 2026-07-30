import Foundation

/// The type of media stored in an event.
public enum MediaKind: String, Codable, Sendable, CaseIterable {
    case photo
    case video
}

/// A single photo or video belonging to an event.
public struct MediaItem: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let eventId: UUID
    public var kind: MediaKind
    /// Full-resolution asset URL used for viewing and downloading.
    public var url: URL
    /// Optional smaller image used in grids and lists. For videos this is a poster frame.
    public var thumbnailURL: URL?
    public var caption: String?
    public var uploaderID: UUID?
    public var uploaderName: String?
    public var width: Int?
    public var height: Int?
    /// Duration in seconds; only meaningful for `.video`.
    public var durationSeconds: Double?
    /// Whether viewers are allowed to download this item to their device.
    public var isDownloadable: Bool
    /// Display order within the event gallery.
    public var sortOrder: Int
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        eventId: UUID,
        kind: MediaKind,
        url: URL,
        thumbnailURL: URL? = nil,
        caption: String? = nil,
        uploaderID: UUID? = nil,
        uploaderName: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        durationSeconds: Double? = nil,
        isDownloadable: Bool = true,
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.eventId = eventId
        self.kind = kind
        self.url = url
        self.thumbnailURL = thumbnailURL
        self.caption = caption
        self.uploaderID = uploaderID
        self.uploaderName = uploaderName
        self.width = width
        self.height = height
        self.durationSeconds = durationSeconds
        self.isDownloadable = isDownloadable
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, eventId, kind, url, thumbnailURL, caption, uploaderID, uploaderName, width, height
        case durationSeconds, isDownloadable, sortOrder, createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        eventId = try container.decode(UUID.self, forKey: .eventId)
        kind = try container.decode(MediaKind.self, forKey: .kind)
        url = try container.decode(URL.self, forKey: .url)
        thumbnailURL = try container.decodeIfPresent(URL.self, forKey: .thumbnailURL)
        caption = try container.decodeIfPresent(String.self, forKey: .caption)
        uploaderID = try container.decodeIfPresent(UUID.self, forKey: .uploaderID)
        uploaderName = try container.decodeIfPresent(String.self, forKey: .uploaderName)
        width = try container.decodeIfPresent(Int.self, forKey: .width)
        height = try container.decodeIfPresent(Int.self, forKey: .height)
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds)
        isDownloadable = try container.decodeIfPresent(Bool.self, forKey: .isDownloadable) ?? true
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(eventId, forKey: .eventId)
        try container.encode(kind, forKey: .kind)
        try container.encode(url, forKey: .url)
        try container.encodeIfPresent(thumbnailURL, forKey: .thumbnailURL)
        try container.encodeIfPresent(caption, forKey: .caption)
        try container.encodeIfPresent(uploaderID, forKey: .uploaderID)
        try container.encodeIfPresent(uploaderName, forKey: .uploaderName)
        try container.encodeIfPresent(width, forKey: .width)
        try container.encodeIfPresent(height, forKey: .height)
        try container.encodeIfPresent(durationSeconds, forKey: .durationSeconds)
        try container.encode(isDownloadable, forKey: .isDownloadable)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encode(createdAt, forKey: .createdAt)
    }

    /// The image URL preferred for display: the thumbnail when present, otherwise the full asset.
    public var previewURL: URL { thumbnailURL ?? url }

    /// `durationSeconds` formatted as `m:ss`, or `nil` when not a timed asset.
    public var formattedDuration: String? {
        guard kind == .video, let seconds = durationSeconds, seconds > 0 else { return nil }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
