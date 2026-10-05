import Foundation
#if canImport(UIKit)
import UIKit
import UserNotifications

/// Asks for notification permission, registers with APNs, and forwards the
/// device token to `PUT /me/device-token`. Silently no-ops when permission is
/// denied, in the simulator (no APNs), or while signed out — a token received
/// before sign-in is stashed and uploaded by ``syncNow()`` afterwards.
@MainActor
final class PushRegistration {
    static let shared = PushRegistration()
    private var pendingToken: String?

    private init() {}

    /// Prompts for permission (first launch only — iOS remembers the answer)
    /// and registers with APNs.
    func requestPermissionAndRegister() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, _ in
            guard granted else { return }
            Task { @MainActor in
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    /// Called by the app delegate when APNs hands back a device token.
    func didReceiveDeviceToken(_ data: Data) {
        pendingToken = data.map { String(format: "%02x", $0) }.joined()
        Task { await uploadPending() }
    }

    /// Call after bootstrap/sign-in: flush a stashed token, or kick off the
    /// permission prompt + APNs registration if we don't have one yet.
    func syncNow() {
        if pendingToken == nil {
            requestPermissionAndRegister()
        } else {
            Task { await uploadPending() }
        }
    }

    private func uploadPending() async {
        guard let token = pendingToken, let bearer = TokenHolder.shared.token else { return }
        var request = URLRequest(url: AppConfig.apiBaseURL.appendingPathComponent("me/device-token"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONEncoder().encode(["token": token])
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { return }
        pendingToken = nil
    }
}
#endif
