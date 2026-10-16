import Combine
import FamilyControls
import Foundation
import os

@MainActor
final class FamilyControlsManager: ObservableObject {
    private let logger = Logger(subsystem: AppConfig.bundleIdentifier, category: "FamilyControls")

    @Published private(set) var authorizationStatus: AuthorizationStatus
    @Published var activitySelection = FamilyActivitySelection()
    #if GUIDEAI_DEMO
    @Published private(set) var demoSelectedToolIDs: Set<String>
    #endif

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var isAuthorized: Bool {
        #if GUIDEAI_DEMO
        return true
        #else
        switch authorizationStatus {
        case .approved, .approvedWithDataAccess:
            return true
        default:
            return false
        }
        #endif
    }

    init(defaults: UserDefaults = AppGroupStore.sharedDefaults) {
        self.defaults = defaults
        #if GUIDEAI_DEMO
        let savedTools = defaults.stringArray(forKey: AppGroupStore.Key.demoSelectedTools)
        self.demoSelectedToolIDs = Set(savedTools ?? ["chatgpt", "gemini", "claude"])
        self.authorizationStatus = .approved
        #else
        self.authorizationStatus = AuthorizationCenter.shared.authorizationStatus
        #endif
        loadSelection()
    }

    func refreshAuthorizationStatus() {
        #if GUIDEAI_DEMO
        authorizationStatus = .approved
        #else
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus
        if !isAuthorized {
            activitySelection = FamilyActivitySelection()
            clearPersistedSelection()
        }
        #endif
    }

    func requestAuthorization() async throws {
        #if GUIDEAI_DEMO
        authorizationStatus = .approved
        return
        #else
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            authorizationStatus = AuthorizationCenter.shared.authorizationStatus
            logger.info("Family Controls authorization succeeded: \(String(describing: self.authorizationStatus))")
        } catch {
            authorizationStatus = AuthorizationCenter.shared.authorizationStatus
            logger.error("Family Controls authorization failed: \(error.localizedDescription)")
            throw error
        }
        #endif
    }

    func saveSelection() {
        guard isAuthorized else { return }
        #if GUIDEAI_DEMO
        defaults.set(Array(demoSelectedToolIDs).sorted(), forKey: AppGroupStore.Key.demoSelectedTools)
        #else
        if let data = try? encoder.encode(activitySelection) {
            defaults.set(data, forKey: AppGroupStore.Key.familyActivitySelection)
        }
        #endif
    }

    func loadSelection() {
        #if GUIDEAI_DEMO
        activitySelection = FamilyActivitySelection()
        return
        #else
        guard let data = defaults.data(forKey: AppGroupStore.Key.familyActivitySelection),
              let selection = try? decoder.decode(FamilyActivitySelection.self, from: data) else {
            activitySelection = FamilyActivitySelection()
            return
        }
        activitySelection = selection
        #endif
    }

    private func clearPersistedSelection() {
        defaults.removeObject(forKey: AppGroupStore.Key.familyActivitySelection)
    }

    var applicationTokenCount: Int {
        #if GUIDEAI_DEMO
        return ["chatgpt", "gemini"].filter { demoSelectedToolIDs.contains($0) }.count
        #else
        return activitySelection.applicationTokens.count
        #endif
    }

    var webDomainTokenCount: Int {
        #if GUIDEAI_DEMO
        return demoSelectedToolIDs.contains("claude") ? 1 : 0
        #else
        return activitySelection.webDomainTokens.count
        #endif
    }

    var categoryTokenCount: Int {
        #if GUIDEAI_DEMO
        return 0
        #else
        return activitySelection.categoryTokens.count
        #endif
    }
    var selectedTokenCount: Int { applicationTokenCount + webDomainTokenCount + categoryTokenCount }
    var hasSelection: Bool { selectedTokenCount > 0 }

    var selectionSummary: String {
        var parts: [String] = []
        if applicationTokenCount > 0 {
            parts.append("\(applicationTokenCount) app\(applicationTokenCount == 1 ? "" : "s")")
        }
        if webDomainTokenCount > 0 {
            parts.append("\(webDomainTokenCount) website\(webDomainTokenCount == 1 ? "" : "s")")
        }
        if categoryTokenCount > 0 {
            parts.append("\(categoryTokenCount) categor\(categoryTokenCount == 1 ? "y" : "ies")")
        }
        return parts.isEmpty ? "No tools selected" : parts.joined(separator: " • ")
    }

    #if GUIDEAI_DEMO
    func updateDemoSelection(_ toolIDs: Set<String>) {
        demoSelectedToolIDs = toolIDs
        saveSelection()
    }
    #endif
}
