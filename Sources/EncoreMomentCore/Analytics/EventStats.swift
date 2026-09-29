import Foundation

/// Aggregate engagement counters for a single event, shown to its creator.
///
/// A plain `Codable` value type so it serves as both the API response body and
/// the app-side model (mirrors how ``Event`` and ``FanPreferences`` are shared).
public struct EventStats: Codable, Sendable, Equatable, Identifiable {
    public let eventID: UUID
    /// Number of times the event page has been opened.
    public var views: Int
    /// Number of media items saved from the event (sum across all fans).
    public var downloads: Int

    public var id: UUID { eventID }

    public init(eventID: UUID, views: Int = 0, downloads: Int = 0) {
        self.eventID = eventID
        self.views = views
        self.downloads = downloads
    }
}
