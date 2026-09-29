import Foundation

/// Builds and parses links to content inside EncoreMoment.
///
/// Two URL shapes are supported for every destination:
/// - a custom scheme for in-app deep links (`encoremoment://event/<id>`)
/// - an `https://` universal link for sharing publicly (`https://encoremoment.app/event/<id>`)
public enum DeepLink: Equatable, Sendable {
    case event(UUID)
    case creator(UUID)

    public static let scheme = "encoremoment"
    public static let webHost = "encoremoment.app"

    /// The `encoremoment://…` URL for opening this destination inside the app.
    public var appURL: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .event(let id):
            components.host = "event"
            components.path = "/\(id.uuidString)"
        case .creator(let id):
            components.host = "creator"
            components.path = "/\(id.uuidString)"
        }
        return components.url!
    }

    /// The shareable `https://encoremoment.app/…` universal link.
    public var webURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.webHost
        switch self {
        case .event(let id): components.path = "/event/\(id.uuidString)"
        case .creator(let id): components.path = "/creator/\(id.uuidString)"
        }
        return components.url!
    }

    /// Parses either URL shape back into a ``DeepLink``, or `nil` if unrecognized.
    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        let kind: String
        let idString: String
        let trimmedPath = components.path.split(separator: "/").map(String.init)

        switch components.scheme {
        case Self.scheme:
            // encoremoment://event/<id>  -> host = "event", path = "/<id>"
            guard let host = components.host, let id = trimmedPath.first else { return nil }
            kind = host
            idString = id
        case "https", "http":
            // https://encoremoment.app/event/<id> -> path = ["event", "<id>"]
            guard components.host == Self.webHost, trimmedPath.count == 2 else { return nil }
            kind = trimmedPath[0]
            idString = trimmedPath[1]
        default:
            return nil
        }

        guard let uuid = UUID(uuidString: idString) else { return nil }
        switch kind {
        case "event": self = .event(uuid)
        case "creator": self = .creator(uuid)
        default: return nil
        }
    }
}
