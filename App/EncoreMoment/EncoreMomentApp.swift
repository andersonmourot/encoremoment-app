import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
private final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushRegistration.shared.didReceiveDeviceToken(deviceToken)
        }
    }
}
#endif

@main
struct EncoreMomentApp: App {
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @StateObject private var model = AppModel()
    @StateObject private var auth = AuthService()
    @StateObject private var settings = AppSettings()
    @State private var didRestoreSession = false

    var body: some Scene {
        WindowGroup {
            AuthGateView(didRestoreSession: didRestoreSession)
                .environmentObject(model)
                .environmentObject(auth)
                .environmentObject(settings)
                .task {
                    guard !didRestoreSession else { return }
                    let account = await auth.restore()
                    await model.bootstrap(account: account)
                    didRestoreSession = true
                }
                .tint(model.accentColor)
                .preferredColorScheme(settings.theme.colorScheme)
                .onOpenURL { url in
                    Task { await model.handle(url: url) }
                }
                .sheet(item: $model.deepLinkedEvent) { event in
                    NavigationStack {
                        EventDetailView(event: event)
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) {
                                    Button("Done") { model.deepLinkedEvent = nil }
                                }
                            }
                    }
                }
        }
    }
}

private struct AuthGateView: View {
    let didRestoreSession: Bool
    @EnvironmentObject private var auth: AuthService

    var body: some View {
        Group {
            if !didRestoreSession {
                VStack(spacing: 14) {
                    ProgressView()
                    Text("Loading EncoreMoment...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if auth.isAuthenticated {
                RootTabView()
            } else {
                RequiredAuthView()
            }
        }
    }
}

private struct RequiredAuthView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "sparkles")
                    .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(Color.appAccent)
                    .padding(.top, 28)
                VStack(spacing: 6) {
                    Text("Welcome to EncoreMoment")
                        .font(.title2.bold())
                    Text("Create an account or sign in to browse events, save media, follow creators, and share your moments.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                AuthView(allowsCancel: false)
                    .frame(minHeight: 500)
            }
        }
    }
}
