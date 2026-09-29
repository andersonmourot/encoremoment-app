import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The result of a successful authentication: a bearer token plus the signed-in
/// profile. Older accounts may not have a creator profile.
public struct AuthSession: Codable, Sendable, Equatable {
    public let token: String
    public let creator: Creator?
    /// The signed-in user's account id (nil for older server responses).
    public let userId: UUID?

    public init(token: String, creator: Creator?, userId: UUID? = nil) {
        self.token = token
        self.creator = creator
        self.userId = userId
    }
}

/// The signed-in account, as returned by `/auth/me`.
public struct Account: Codable, Sendable, Equatable {
    /// The user's account id (nil for older server responses).
    public let id: UUID?
    public let email: String
    public let creator: Creator?

    public init(id: UUID? = nil, email: String, creator: Creator?) {
        self.id = id
        self.email = email
        self.creator = creator
    }
}

/// Talks to the backend's `/auth` endpoints. Pairs with ``APIEventStore`` (same
/// `baseURL` / `HTTPTransport`) and is fully testable via a mock transport.
public actor AuthClient {
    private let baseURL: URL
    private let transport: HTTPTransport
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(baseURL: URL, transport: HTTPTransport = URLSessionTransport()) {
        self.baseURL = baseURL
        self.transport = transport
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    private struct RegisterBody: Encodable {
        let email: String
        let password: String
        let displayName: String
        let handle: String
    }

    private struct LoginBody: Encodable {
        let email: String
        let password: String
    }

    private struct ProfileBody: Encodable {
        let displayName: String
        let handle: String
    }

    public func register(email: String, password: String, displayName: String, handle: String) async throws -> AuthSession {
        try await post("auth/register", body: RegisterBody(email: email, password: password, displayName: displayName, handle: handle))
    }

    public func login(email: String, password: String) async throws -> AuthSession {
        try await post("auth/login", body: LoginBody(email: email, password: password))
    }

    public func completeProfile(token: String, displayName: String, handle: String) async throws -> AuthSession {
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/profile"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(ProfileBody(displayName: displayName, handle: handle))
        let (data, http) = try await transport.send(request)
        try validate(http, data: data)
        return try decoder.decode(AuthSession.self, from: data)
    }

    public func me(token: String) async throws -> Account {
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/me"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, http) = try await transport.send(request)
        try validate(http, data: data)
        return try decoder.decode(Account.self, from: data)
    }

    private func post<Body: Encodable>(_ path: String, body: Body) async throws -> AuthSession {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        let (data, http) = try await transport.send(request)
        try validate(http, data: data)
        return try decoder.decode(AuthSession.self, from: data)
    }

    private func validate(_ response: HTTPURLResponse, data: Data) throws {
        guard (200..<300).contains(response.statusCode) else {
            let reason = (try? decoder.decode(ServerError.self, from: data))?.reason
            throw AuthError(status: response.statusCode, reason: reason)
        }
    }
}

/// Vapor's standard error envelope (`{"error": true, "reason": "..."}`).
private struct ServerError: Decodable {
    let reason: String?
}

public struct AuthError: Error, Equatable, Sendable {
    public let status: Int
    public let reason: String?

    public var message: String {
        reason ?? "Request failed (\(status))."
    }
}
