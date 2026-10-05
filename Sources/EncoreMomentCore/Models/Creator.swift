import Foundation

/// An artist or event company that publishes events and uploads media.
public struct Creator: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    /// Human-readable name shown on the profile, e.g. "Aurora Live".
    public var displayName: String
    /// Unique, URL-safe handle (without the leading `@`), e.g. "AuroraLive".
    public var handle: String
    public var bio: String?
    public var avatarURL: URL?
    /// Hex color used to personalize this creator/account's app accents.
    public var accentColorHex: String?
    public var isVerified: Bool
    public let joinedAt: Date
    /// Follower count — populated by the API on creator listings.
    public var followerCount: Int?

    public init(
        id: UUID = UUID(),
        displayName: String,
        handle: String,
        bio: String? = nil,
        avatarURL: URL? = nil,
        accentColorHex: String? = nil,
        isVerified: Bool = false,
        joinedAt: Date = Date(),
        followerCount: Int? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.handle = handle
        self.bio = bio
        self.avatarURL = avatarURL
        self.accentColorHex = accentColorHex
        self.isVerified = isVerified
        self.joinedAt = joinedAt
        self.followerCount = followerCount
    }

    /// The handle rendered with a leading `@` for display.
    public var displayHandle: String { "@" + handle }
}

public extension Creator {
    /// Validates a handle: 3–30 chars, ASCII letters, digits and underscores only.
    /// Matching against other handles is always case-insensitive.
    static func isValidHandle(_ handle: String) -> Bool {
        guard (3...30).contains(handle.count) else { return false }
        return handle.allSatisfy { $0.isASCIILetter || $0.isASCIIDigit || $0 == "_" }
    }
}

private extension Character {
    var isASCIILetter: Bool { (self >= "a" && self <= "z") || (self >= "A" && self <= "Z") }
    var isASCIIDigit: Bool { self >= "0" && self <= "9" }
}
