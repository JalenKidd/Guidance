import Foundation

enum AppGroupStore {
    enum Key {
        static let parentalPolicy = "guideai.parentalPolicy"
        static let familyActivitySelection = "guideai.familyActivitySelection"
        static let dailyUsage = "guideai.dailyUsage"
        static let onboardingComplete = "guideai.onboardingComplete"
        static let conversationMessages = "guideai.conversationMessages"
        static let aiFreeScheduleEnabled = "guideai.aiFreeScheduleEnabled"
        static let openAssistantFromShield = "guideai.openAssistantFromShield"
        static let demoSelectedTools = "guidance.selectedTools"
    }

    static var sharedDefaults: UserDefaults {
        #if GUIDEAI_DEMO
        // The installable video-demo target has no App Group entitlement so it
        // can be signed by a free Personal Team.
        return .standard
        #else
        UserDefaults(suiteName: AppConfig.appGroupIdentifier) ?? .standard
        #endif
    }
}
