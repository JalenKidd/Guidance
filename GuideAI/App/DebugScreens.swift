#if DEBUG
import SwiftUI

/// Debug-only launch arguments for taking screenshots of every screen without tapping:
///   -unlocked             skip the Face ID lock
///   -tab <home|schedules|activity|setup>
///   -screen <name>        open one screen directly (see `DebugScreen`)
enum DebugLaunch {
    static let arguments = ProcessInfo.processInfo.arguments

    static func has(_ flag: String) -> Bool {
        arguments.contains(flag)
    }

    static func value(_ key: String) -> String? {
        guard let i = arguments.firstIndex(of: key), arguments.indices.contains(i + 1) else { return nil }
        return arguments[i + 1]
    }
}

struct DebugScreen: View {
    @EnvironmentObject private var store: FamilyStore
    let name: String

    var body: some View {
        switch name {
        case "welcome-signin", "welcome-new":
            WelcomeView(startsWithNewFamily: name == "welcome-new")
        case "lock":
            LockView()
        case "category":
            NavigationStack { CategoryDetailView(categoryID: DebugLaunch.value("-category") ?? "essay") }
        case "app":
            NavigationStack { AppDetailView(appID: DebugLaunch.value("-app") ?? "chatgpt") }
        case "homework":
            NavigationStack { GuidedRulesView() }
        case "safety":
            NavigationStack { SafetyAlertsView() }
        case "exceptions":
            NavigationStack { SiteOverridesView() }
        case "schedule-editor":
            ScheduleEditorView(schedule: .schoolNightsPreset)
        case "kid-profile":
            if let kid = store.kids.first {
                NavigationStack { KidProfileView(kidID: kid.id) }
            } else {
                ProgressView()
            }
        default:
            Text("Unknown debug screen: \(name)")
        }
    }
}
#endif
