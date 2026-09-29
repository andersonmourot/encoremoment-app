import Foundation

/// An ``EventStore`` that persists ``StoreState`` to a JSON file on disk, so
/// creators' events and uploads survive app restarts.
///
/// All access goes through an actor; every mutation writes the whole state back
/// to disk atomically. Suitable for on-device local storage; swap for a networked
/// store when a real backend exists.
public actor FileEventStore: EventStore {
    private let fileURL: URL
    private var state: StoreState

    /// Loads existing state from `fileURL`. If the file is missing, starts from
    /// `seed` (e.g. ``SampleData``) and writes it so first launch is populated.
    public init(fileURL: URL, seed: StoreState = StoreState()) throws {
        self.fileURL = fileURL
        if let loaded = try Self.load(from: fileURL) {
            self.state = loaded
        } else {
            self.state = seed
            try Self.persist(seed, to: fileURL)
        }
    }

    // MARK: Creators

    public func allCreators() async throws -> [Creator] { state.allCreators() }
    public func creator(id: UUID) async throws -> Creator? { state.creator(id: id) }
    public func upsertCreator(_ creator: Creator) async throws {
        try mutate { try $0.upsertCreator(creator) }
    }

    // MARK: Events

    public func publishedEvents() async throws -> [Event] { state.publishedEvents() }
    public func events(forCreator creatorId: UUID) async throws -> [Event] { state.events(forCreator: creatorId) }
    public func event(id: UUID) async throws -> Event? { state.event(id: id) }
    public func createEvent(_ event: Event) async throws { try mutate { try $0.createEvent(event) } }
    public func updateEvent(_ event: Event) async throws { try mutate { try $0.updateEvent(event) } }
    public func deleteEvent(id: UUID) async throws { try mutate { try $0.deleteEvent(id: id) } }

    // MARK: Media

    public func addMedia(_ item: MediaItem, toEvent eventId: UUID) async throws {
        try mutate { try $0.addMedia(item, toEvent: eventId) }
    }
    public func removeMedia(id: UUID, fromEvent eventId: UUID) async throws {
        try mutate { try $0.removeMedia(id: id, fromEvent: eventId) }
    }

    // MARK: Persistence

    /// Applies `change` to a copy of the state and only commits + persists if it succeeds,
    /// so a failed/validating mutation never leaves partial state on disk.
    private func mutate(_ change: (inout StoreState) throws -> Void) throws {
        var copy = state
        try change(&copy)
        try Self.persist(copy, to: fileURL)
        state = copy
    }

    private static func load(from url: URL) throws -> StoreState? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(StoreState.self, from: data)
    }

    private static func persist(_ state: StoreState, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }
}
