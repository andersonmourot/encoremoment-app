import XCTest
@testable import EncoreMomentCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class MockTransport: HTTPTransport, @unchecked Sendable {
    typealias Handler = (URLRequest) throws -> (Int, Data)
    private let handler: Handler
    private(set) var requests: [URLRequest] = []
    init(_ handler: @escaping Handler) { self.handler = handler }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let (status, data) = try handler(request)
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

final class AuthClientTests: XCTestCase {
    private let baseURL = URL(string: "https://api.encoremoment.app")!

    private func session(_ creator: Creator, token: String = "tok") throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(AuthSession(token: token, creator: creator))
    }

    func testRegisterReturnsSession() async throws {
        let creator = Creator(displayName: "DJ", handle: "dj")
        let payload = try session(creator, token: "abc")
        let transport = MockTransport { _ in (200, payload) }
        let client = AuthClient(baseURL: baseURL, transport: transport)

        let result = try await client.register(email: "a@b.com", password: "password123", displayName: "DJ", handle: "dj")
        XCTAssertEqual(result.token, "abc")
        XCTAssertEqual(result.creator?.handle, "dj")

        let req = transport.requests.first!
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.url?.path, "/auth/register")
    }

    func testLoginSendsCredentials() async throws {
        let creator = Creator(displayName: "DJ", handle: "dj")
        let transport = MockTransport { _ in (200, try self.session(creator)) }
        let client = AuthClient(baseURL: baseURL, transport: transport)
        _ = try await client.login(email: "a@b.com", password: "secretpw1")

        let body = try JSONSerialization.jsonObject(with: transport.requests.first!.httpBody!) as! [String: String]
        XCTAssertEqual(body["email"], "a@b.com")
        XCTAssertEqual(body["password"], "secretpw1")
    }

    func testErrorReasonIsParsed() async {
        let body = Data(#"{"error":true,"reason":"That handle is taken."}"#.utf8)
        let transport = MockTransport { _ in (409, body) }
        let client = AuthClient(baseURL: baseURL, transport: transport)
        do {
            _ = try await client.register(email: "a@b.com", password: "password123", displayName: "X", handle: "dj")
            XCTFail("Expected error")
        } catch let error as AuthError {
            XCTAssertEqual(error.status, 409)
            XCTAssertEqual(error.reason, "That handle is taken.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMeAttachesBearerToken() async throws {
        let creator = Creator(displayName: "DJ", handle: "dj")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let transport = MockTransport { _ in (200, try encoder.encode(Account(email: "dj@b.com", creator: creator))) }
        let client = AuthClient(baseURL: baseURL, transport: transport)
        let account = try await client.me(token: "mytoken")
        XCTAssertEqual(account.creator?.handle, "dj")
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer mytoken")
    }

    func testCompleteProfileAttachesBearerToken() async throws {
        let creator = Creator(displayName: "DJ", handle: "dj")
        let transport = MockTransport { _ in (200, try self.session(creator, token: "newtoken")) }
        let client = AuthClient(baseURL: baseURL, transport: transport)

        let result = try await client.completeProfile(token: "oldtoken", displayName: "DJ", handle: "dj")
        XCTAssertEqual(result.token, "newtoken")
        XCTAssertEqual(result.creator?.handle, "dj")

        let req = transport.requests.first!
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.url?.path, "/auth/profile")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer oldtoken")
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: String]
        XCTAssertEqual(body["displayName"], "DJ")
        XCTAssertEqual(body["handle"], "dj")
    }

    func testDeleteAccountSendsDeleteWithBearer() async throws {
        let transport = MockTransport { _ in (204, Data()) }
        let client = AuthClient(baseURL: baseURL, transport: transport)
        try await client.deleteAccount(token: "tok123")
        let req = transport.requests.first!
        XCTAssertEqual(req.httpMethod, "DELETE")
        XCTAssertEqual(req.url?.path, "/auth/account")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer tok123")
    }

    func testDeleteAccountPropagatesErrorReason() async {
        let body = Data(#"{"error":true,"reason":"Not found."}"#.utf8)
        let transport = MockTransport { _ in (404, body) }
        let client = AuthClient(baseURL: baseURL, transport: transport)
        do {
            try await client.deleteAccount(token: "tok123")
            XCTFail("Expected error")
        } catch let error as AuthError {
            XCTAssertEqual(error.status, 404)
            XCTAssertEqual(error.reason, "Not found.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAuthenticatedTransportAttachesToken() async throws {
        let inner = MockTransport { _ in (200, Data("[]".utf8)) }
        let transport = AuthenticatedTransport(base: inner) { "thetoken" }
        _ = try await transport.send(URLRequest(url: baseURL))
        XCTAssertEqual(inner.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer thetoken")
    }

    func testAuthenticatedTransportSkipsWhenNoToken() async throws {
        let inner = MockTransport { _ in (200, Data("[]".utf8)) }
        let transport = AuthenticatedTransport(base: inner) { nil }
        _ = try await transport.send(URLRequest(url: baseURL))
        XCTAssertNil(inner.requests.first?.value(forHTTPHeaderField: "Authorization"))
    }
}
