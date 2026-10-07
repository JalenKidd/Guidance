import SwiftUI

@MainActor
@main
struct GuideAIApp: App {
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            AppRouter()
                .environmentObject(environment)
        }
    }
}
