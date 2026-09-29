import Foundation

/// Thread-safe holder for the current auth token, backed by the Keychain.
///
/// Shared so ``AuthenticatedTransport`` (used deep inside `APIEventStore`) can
/// read the latest token from any thread without being rebuilt on sign-in/out.
final class TokenHolder: @unchecked Sendable {
    static let shared = TokenHolder()

    private static let key = "com.encoremoment.authToken"
    private let lock = NSLock()
    private var cached: String?

    private init() {
        cached = Keychain.get(Self.key)
    }

    var token: String? {
        lock.lock(); defer { lock.unlock() }
        return cached
    }

    func set(_ value: String?) {
        lock.lock(); defer { lock.unlock() }
        cached = value
        if let value {
            Keychain.set(value, for: Self.key)
        } else {
            Keychain.delete(Self.key)
        }
    }
}
