import Foundation

/// Records engagement (views & downloads) and reads back per-event stats.
///
/// Recording is public/anonymous (any viewer contributes), while reading is a
/// creator-only operation on the server. Like ``EventStore`` this is a protocol so
/// the in-memory implementation used in tests/previews can be swapped for the REST
/// implementation without touching the UI.
public protocol AnalyticsStore: Sendable {
    /// Records a single view of an event (called when its page is opened).
    func recordView(eventID: UUID) async throws
    /// Records `count` media downloads for an event.
    func recordDownloads(eventID: UUID, count: Int) async throws
    /// Stats for a single event.
    func stats(forEvent eventID: UUID) async throws -> EventStats
    /// Stats for every event owned by the authenticated creator.
    func creatorStats() async throws -> [EventStats]
}

/// In-memory implementation for previews and tests.
public actor InMemoryAnalyticsStore: AnalyticsStore {
    private var stats: [UUID: EventStats]

    public init(_ seed: [EventStats] = []) {
        self.stats = Dictionary(seed.map { ($0.eventID, $0) }, uniquingKeysWith: { a, _ in a })
    }

    public func recordView(eventID: UUID) async throws {
        stats[eventID, default: EventStats(eventID: eventID)].views += 1
    }

    public func recordDownloads(eventID: UUID, count: Int) async throws {
        guard count > 0 else { return }
        stats[eventID, default: EventStats(eventID: eventID)].downloads += count
    }

    public func stats(forEvent eventID: UUID) async throws -> EventStats {
        stats[eventID] ?? EventStats(eventID: eventID)
    }

    public func creatorStats() async throws -> [EventStats] {
        Array(stats.values)
    }
}
