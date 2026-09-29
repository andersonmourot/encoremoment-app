import Foundation
import EncoreMomentCore

struct NotificationService {
    private let baseURL: URL
    private let tokenProvider: () -> String?

    init(baseURL: URL = AppConfig.apiBaseURL, tokenProvider: @escaping () -> String? = { TokenHolder.shared.token }) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
    }

    func notifications() async throws -> [AppNotification] {
        var request = URLRequest(url: baseURL.appendingPathComponent("me/notifications"))
        request.httpMethod = "GET"
        guard let token = tokenProvider() else { throw NotificationError.notSignedIn }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NotificationError.failed
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([AppNotification].self, from: data)
    }

    func markRead(id: UUID) async throws -> AppNotification {
        var request = URLRequest(url: baseURL.appendingPathComponent("me/notifications/\(id.uuidString)/read"))
        request.httpMethod = "POST"
        guard let token = tokenProvider() else { throw NotificationError.notSignedIn }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NotificationError.failed
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AppNotification.self, from: data)
    }

    func markAllRead() async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("me/notifications/read-all"))
        request.httpMethod = "POST"
        guard let token = tokenProvider() else { throw NotificationError.notSignedIn }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NotificationError.failed
        }
    }
}

private enum NotificationError: LocalizedError {
    case notSignedIn
    case failed

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "Sign in to view notifications."
        case .failed: "Couldn't update notifications. Please try again."
        }
    }
}
