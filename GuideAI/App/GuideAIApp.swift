import SwiftUI

enum GuidanceAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

@MainActor
@main
struct GuideAIApp: App {
    @StateObject private var store = FamilyStore()
    @AppStorage("guidance.appearance") private var appearance = GuidanceAppearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(preferredColorScheme)
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch GuidanceAppearance(rawValue: appearance) ?? .system {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
