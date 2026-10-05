import Vapor
import Fluent
import JWTKit
import AsyncHTTPClient

/// Sends APNs push notifications for in-app notifications.
///
/// Entirely env-gated: unless `APNS_KEY_ID`, `APNS_TEAM_ID`,
/// `APNS_PRIVATE_KEY` (the .p8 PEM), and `APNS_BUNDLE_ID` are all set,
/// `configure` leaves the service disabled and sends are no-ops.
/// `APNS_SANDBOX=true` targets the sandbox environment.
enum PushService {
    private struct Configuration: Sendable {
        let keyID: String
        let teamID: String
        let privateKeyPEM: String
        let bundleID: String
        let useSandbox: Bool
    }

    private final class State: @unchecked Sendable {
        var config: Configuration?
    }

    private static let state = State()
    private static let keys = JWTKeyCollection()

    static func configure(app: Application) {
        guard let keyID = Environment.get("APNS_KEY_ID"),
              let teamID = Environment.get("APNS_TEAM_ID"),
              var pem = Environment.get("APNS_PRIVATE_KEY"),
              let bundleID = Environment.get("APNS_BUNDLE_ID") else {
            app.logger.info("Push notifications disabled (APNS_* env vars not set).")
            return
        }
        // PEMs passed through env vars often carry literal \n sequences.
        pem = pem.replacingOccurrences(of: "\\n", with: "\n")
        state.config = Configuration(
            keyID: keyID,
            teamID: teamID,
            privateKeyPEM: pem,
            bundleID: bundleID,
            useSandbox: Environment.get("APNS_SANDBOX") == "true"
        )
        app.logger.info("Push notifications enabled (bundle \(bundleID)).")
    }

    /// Sends a push to every registered device of the user. Best-effort:
    /// logs and swallows failures so a push outage can't break requests.
    static func send(userId: UUID, title: String, body: String, on db: Database, logger: Logger) async {
        guard let config = state.config else { return }
        do {
            let tokens = try await DeviceTokenModel.query(on: db)
                .filter(\.$userId == userId).all()
            guard !tokens.isEmpty else { return }
            let jwt = try await apnsJWT(config: config)
            let host = config.useSandbox ? "api.sandbox.push.apple.com" : "api.push.apple.com"

            let payload = try JSONEncoder().encode(APNsPayload(aps: .init(alert: .init(title: title, body: body))))
            var clientConfig = HTTPClient.Configuration()
            clientConfig.httpVersion = .automatic
            let client = HTTPClient(configuration: clientConfig)
            defer { try? client.syncShutdown() }
            for token in tokens {
                var request = HTTPClientRequest(url: "https://\(host)/3/device/\(token.token)")
                request.method = .POST
                request.headers.add(name: "authorization", value: "bearer \(jwt)")
                request.headers.add(name: "apns-topic", value: config.bundleID)
                request.headers.add(name: "apns-push-type", value: "alert")
                request.headers.add(name: "content-type", value: "application/json")
                request.body = .bytes(payload)
                let response = try await client.execute(request, timeout: .seconds(10))
                if response.status.code != 200 {
                    logger.warning("APNs push to …\(token.token.suffix(8)) failed: \(response.status.code)")
                }
            }
        } catch {
            logger.warning("APNs push failed: \(error.localizedDescription)")
        }
    }

    private struct APNsPayload: Encodable {
        struct APS: Encodable {
            struct Alert: Encodable { let title: String; let body: String }
            let alert: Alert
            let sound = "default"
        }
        let aps: APS
    }

    private struct APNsClaims: JWTPayload {
        var iss: String
        var iat: Date
        func verify(using algorithm: some JWTAlgorithm) async throws {}
    }

    private static func apnsJWT(config: Configuration) async throws -> String {
        let key = try ECDSA.PrivateKey<P256>(pem: config.privateKeyPEM)
        await keys.add(ecdsa: key, kid: JWKIdentifier(string: config.keyID))
        return try await keys.sign(
            APNsClaims(iss: config.teamID, iat: Date()),
            kid: JWKIdentifier(string: config.keyID)
        )
    }
}
