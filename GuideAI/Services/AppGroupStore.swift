import Foundation

enum AppGroupStore {
    enum Key {
        static let parentalPolicy = "guideai.parentalPolicy"
        static let familyActivitySelection = "guideai.familyActivitySelection"
        static let dailyUsage = "guideai.dailyUsage"
        static let onboardingComplete = "guideai.onboardingComplete"
        static let conversationMessages = "guideai.conversationMessages"
        static let aiFreeScheduleEnabled = "guideai.aiFreeScheduleEnabled"
    }

    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: AppConfig.appGroupIdentifier) ?? .standard
    }
}
