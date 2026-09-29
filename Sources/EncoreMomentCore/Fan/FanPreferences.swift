import Foundation

/// A viewer's personal preferences: which events they've favorited, which
/// creators they follow, and which creators they've blocked.
///
/// Anonymous viewers store this locally (see ``FanPreferencesStore``); signed-in
/// accounts sync it to the server.
public struct FanPreferences: Codable, Sendable, Equatable {
    public var favoriteEventIDs: Set<UUID>
    public var followedCreatorIDs: Set<UUID>
    public var blockedCreatorIDs: Set<UUID>

    public init(
        favoriteEventIDs: Set<UUID> = [],
        followedCreatorIDs: Set<UUID> = [],
        blockedCreatorIDs: Set<UUID> = []
    ) {
        self.favoriteEventIDs = favoriteEventIDs
        self.followedCreatorIDs = followedCreatorIDs
        self.blockedCreatorIDs = blockedCreatorIDs
    }

    /// Tolerant decoding: `blockedCreatorIDs` was added later and older server
    /// responses (and older on-device files) don't include it.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        favoriteEventIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .favoriteEventIDs) ?? []
        followedCreatorIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .followedCreatorIDs) ?? []
        blockedCreatorIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .blockedCreatorIDs) ?? []
    }

    public func isFavorite(_ eventID: UUID) -> Bool { favoriteEventIDs.contains(eventID) }
    public func isFollowing(_ creatorID: UUID) -> Bool { followedCreatorIDs.contains(creatorID) }
    public func isBlocked(_ creatorID: UUID) -> Bool { blockedCreatorIDs.contains(creatorID) }

    public mutating func setFavorite(_ eventID: UUID, _ isFavorite: Bool) {
        if isFavorite { favoriteEventIDs.insert(eventID) } else { favoriteEventIDs.remove(eventID) }
    }

    public mutating func setFollowing(_ creatorID: UUID, _ isFollowing: Bool) {
        if isFollowing { followedCreatorIDs.insert(creatorID) } else { followedCreatorIDs.remove(creatorID) }
    }

    public mutating func setBlocked(_ creatorID: UUID, _ isBlocked: Bool) {
        if isBlocked { blockedCreatorIDs.insert(creatorID) } else { blockedCreatorIDs.remove(creatorID) }
    }
}
