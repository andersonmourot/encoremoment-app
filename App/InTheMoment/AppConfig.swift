import Foundation

/// App-wide configuration values.
enum AppConfig {
    /// Base URL of the shared InTheMoment backend. Override at runtime with the
    /// `ITM_API_BASE_URL` environment variable (handy for pointing at a local server).
    static var apiBaseURL: URL {
        if let override = ProcessInfo.processInfo.environment["ITM_API_BASE_URL"],
           let url = URL(string: override) {
            return url
        }
        return URL(string: "https://inthemoment-api.fly.dev")!
    }

    static var usesLocalAPI: Bool {
        guard let host = apiBaseURL.host else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "0.0.0.0"
    }
}
