import Foundation

/// Deterministic seed data used by SwiftUI previews, the simulator and tests.
public enum SampleData {
    public static let aurora = Creator(
        id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
        displayName: "Aurora Live",
        handle: "auroralive",
        bio: "Concert & festival photography collective.",
        isVerified: true
    )

    public static let cityEvents = Creator(
        id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!,
        displayName: "City Events Co.",
        handle: "cityevents",
        bio: "We document the city's nightlife, one event at a time."
    )

    public static var creators: [Creator] { [aurora, cityEvents] }

    private static func photo(_ event: UUID, _ n: Int, caption: String? = nil) -> MediaItem {
        MediaItem(
            eventId: event,
            kind: .photo,
            url: URL(string: "https://picsum.photos/seed/em-\(n)/1200/800")!,
            thumbnailURL: URL(string: "https://picsum.photos/seed/em-\(n)/400/400")!,
            caption: caption,
            width: 1200,
            height: 800
        )
    }

    private static func video(_ event: UUID, _ n: Int, seconds: Double) -> MediaItem {
        MediaItem(
            eventId: event,
            kind: .video,
            url: URL(string: "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4")!,
            thumbnailURL: URL(string: "https://picsum.photos/seed/em-vid-\(n)/400/400")!,
            durationSeconds: seconds
        )
    }

    public static var events: [Event] {
        let summerFest = UUID(uuidString: "00000000-0000-0000-0000-0000000000E1")!
        let rooftop = UUID(uuidString: "00000000-0000-0000-0000-0000000000E2")!
        let warehouse = UUID(uuidString: "00000000-0000-0000-0000-0000000000E3")!

        return [
            Event(
                id: summerFest,
                creatorId: aurora.id,
                title: "Summer Fest 2026",
                details: "Main stage highlights and crowd moments.",
                location: "Riverside Park",
                date: date(daysAgo: 2),
                media: [
                    photo(summerFest, 1, caption: "Opening act"),
                    photo(summerFest, 2),
                    photo(summerFest, 3, caption: "Golden hour"),
                    video(summerFest, 1, seconds: 42)
                ]
            ),
            Event(
                id: rooftop,
                creatorId: aurora.id,
                title: "Rooftop Sessions",
                details: "An intimate sunset set above the city.",
                location: "The Heights",
                date: date(daysAgo: 9),
                media: [
                    photo(rooftop, 4),
                    photo(rooftop, 5, caption: "Skyline"),
                    video(rooftop, 2, seconds: 18)
                ]
            ),
            Event(
                id: warehouse,
                creatorId: cityEvents.id,
                title: "Warehouse Night",
                details: "Late-night underground showcase.",
                location: "Block 9",
                date: date(daysAgo: 5),
                media: [
                    photo(warehouse, 6),
                    photo(warehouse, 7, caption: "Lights")
                ]
            )
        ]
    }

    private static func date(daysAgo: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
    }

    /// State pre-populated with the sample creators and events.
    public static func makeState() -> StoreState {
        StoreState(creators: creators, events: events)
    }

    /// A store pre-populated with the sample creators and events.
    public static func makeStore() -> InMemoryEventStore {
        InMemoryEventStore(creators: creators, events: events)
    }
}
