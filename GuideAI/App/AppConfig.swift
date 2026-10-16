import Foundation

enum AppConfig {
    /// Display name shown in UI; change here for rebranding.
    static let productDisplayName = "Guidance"

    static let bundleIdentifier = "com.cac.guideai"
    static let appGroupIdentifier = "group.com.cac.guideai.shared"

    #if GUIDEAI_DEMO
    static let isVideoDemo = true
    #else
    static let isVideoDemo = false
    #endif

    /// Backend base URL (no trailing slash). Override in Debug via scheme environment `GUIDEAI_API_BASE_URL`.
    static var apiBaseURL: URL {
        if let env = ProcessInfo.processInfo.environment["GUIDEAI_API_BASE_URL"],
           let url = URL(string: env), !env.isEmpty {
            return url
        }
        if let stored = UserDefaults.standard.string(forKey: "guideai.apiBaseURL"),
           let url = URL(string: stored), !stored.isEmpty {
            return url
        }
        #if DEBUG
        return URL(string: "http://127.0.0.1:8080")!
        #else
        return URL(string: "https://your-guideai-backend.example.com")!
        #endif
    }
}
