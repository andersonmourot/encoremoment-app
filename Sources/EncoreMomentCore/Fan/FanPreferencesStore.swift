import Foundation

/// Persists a fan's ``FanPreferences``. Mutations return the updated value so the
/// UI can refresh from a single source of truth.
public protocol FanPreferencesStore: Sendable {
    func preferences() async throws -> FanPreferences
    @discardableResult func setFavorite(eventID: UUID, _ isFavorite: Bool) async throws -> FanPreferences
    @discardableResult func setFollowing(creatorID: UUID, _ isFollowing: Bool) async throws -> FanPreferences
    /// Union-merges the given preferences into the store (used to push on-device
    /// favorites/follows up to a freshly signed-in account). Returns the result.
    @discardableResult func merge(_ other: FanPreferences) async throws -> FanPreferences
}

public extension FanPreferencesStore {
    @discardableResult
    func merge(_ other: FanPreferences) async throws -> FanPreferences {
        for eventID in other.favoriteEventIDs { try await setFavorite(eventID: eventID, true) }
        for creatorID in other.followedCreatorIDs { try await setFollowing(creatorID: creatorID, true) }
        return try await preferences()
    }
}

/// In-memory implementation for previews and tests.
public actor InMemoryFanPreferencesStore: FanPreferencesStore {
    private var prefs: FanPreferences

    public init(_ prefs: FanPreferences = FanPreferences()) {
        self.prefs = prefs
    }

    public func preferences() async throws -> FanPreferences { prefs }

    @discardableResult
    public func setFavorite(eventID: UUID, _ isFavorite: Bool) async throws -> FanPreferences {
        prefs.setFavorite(eventID, isFavorite)
        return prefs
    }

    @discardableResult
    public func setFollowing(creatorID: UUID, _ isFollowing: Bool) async throws -> FanPreferences {
        prefs.setFollowing(creatorID, isFollowing)
        return prefs
    }
}

/// Persists ``FanPreferences`` to a JSON file on disk (the on-device default).
public actor FileFanPreferencesStore: FanPreferencesStore {
    private let fileURL: URL
    private var prefs: FanPreferences

    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        self.prefs = (try? Self.load(from: fileURL)) ?? FanPreferences()
    }

    public func preferences() async throws -> FanPreferences { prefs }

    @discardableResult
    public func setFavorite(eventID: UUID, _ isFavorite: Bool) async throws -> FanPreferences {
        prefs.setFavorite(eventID, isFavorite)
        try persist()
        return prefs
    }

    @discardableResult
    public func setFollowing(creatorID: UUID, _ isFollowing: Bool) async throws -> FanPreferences {
        prefs.setFollowing(creatorID, isFollowing)
        try persist()
        return prefs
    }

    private func persist() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(prefs).write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) throws -> FanPreferences? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(FanPreferences.self, from: Data(contentsOf: url))
    }
}
