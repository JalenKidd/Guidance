import Foundation

enum AppConfig {
    /// Display name shown in UI; change here for rebranding.
    static let productDisplayName = "Guidance"

    static let bundleIdentifier = "com.cac.guideai"

    static let serverURLKey = "guidance.serverURL"

    /// Guidance server (no trailing slash). Priority: scheme env `GUIDEAI_API_BASE_URL`,
    /// then the address saved in Setup, then localhost (works in the Simulator).
    static var apiBaseURL: URL {
        if let env = ProcessInfo.processInfo.environment["GUIDEAI_API_BASE_URL"],
           let url = URL(string: env), !env.isEmpty {
            return url
        }
        if let stored = UserDefaults.standard.string(forKey: serverURLKey),
           let url = URL(string: stored), !stored.isEmpty {
            return url
        }
        return URL(string: "http://127.0.0.1:8080")!
    }
}
