import Foundation

/// Pure, testable helpers for arranging events in the Discover feed.
public enum EventFeed {
    /// Case-insensitive search across an event's title, details and location.
    public static func search(_ events: [Event], query: String) -> [Event] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return events }
        return events.filter { event in
            let haystack = [event.title, event.details ?? "", event.location ?? ""]
                .joined(separator: " ")
            return haystack.range(of: trimmed, options: .caseInsensitive) != nil
        }
    }

    /// Most recent events first, by event date.
    public static func sortedByDate(_ events: [Event]) -> [Event] {
        events.sorted { $0.date > $1.date }
    }

    /// Events whose creator is in `creatorIDs` (e.g. the fan's followed creators).
    public static func events(_ events: [Event], byCreators creatorIDs: Set<UUID>) -> [Event] {
        events.filter { creatorIDs.contains($0.creatorId) }
    }

    /// Events whose id is in `eventIDs` (e.g. the fan's favorites), newest first.
    public static func events(_ events: [Event], withIDs eventIDs: Set<UUID>) -> [Event] {
        sortedByDate(events.filter { eventIDs.contains($0.id) })
    }

    /// Events grouped by the calendar day they took place, newest day first.
    public static func groupedByDay(_ events: [Event], calendar: Calendar = .current) -> [(day: Date, events: [Event])] {
        let groups = Dictionary(grouping: events) { calendar.startOfDay(for: $0.date) }
        return groups
            .map { (day: $0.key, events: sortedByDate($0.value)) }
            .sorted { $0.day > $1.day }
    }
}
