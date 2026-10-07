import Combine
import FamilyControls
import Foundation
import os

@MainActor
final class FamilyControlsManager: ObservableObject {
    private let logger = Logger(subsystem: AppConfig.bundleIdentifier, category: "FamilyControls")

    @Published private(set) var authorizationStatus: AuthorizationStatus
    @Published var activitySelection = FamilyActivitySelection()

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var isAuthorized: Bool {
        switch authorizationStatus {
        case .approved, .approvedWithDataAccess:
            return true
        default:
            return false
        }
    }

    init(defaults: UserDefaults = AppGroupStore.sharedDefaults) {
        self.defaults = defaults
        self.authorizationStatus = AuthorizationCenter.shared.authorizationStatus
        loadSelection()
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus
        if !isAuthorized {
            activitySelection = FamilyActivitySelection()
            clearPersistedSelection()
        }
    }

    func requestAuthorization() async throws {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            authorizationStatus = AuthorizationCenter.shared.authorizationStatus
            logger.info("Family Controls authorization succeeded: \(String(describing: self.authorizationStatus))")
        } catch {
            authorizationStatus = AuthorizationCenter.shared.authorizationStatus
            logger.error("Family Controls authorization failed: \(error.localizedDescription)")
            throw error
        }
    }

    func saveSelection() {
        guard isAuthorized else { return }
        if let data = try? encoder.encode(activitySelection) {
            defaults.set(data, forKey: AppGroupStore.Key.familyActivitySelection)
        }
    }

    func loadSelection() {
        guard let data = defaults.data(forKey: AppGroupStore.Key.familyActivitySelection),
              let selection = try? decoder.decode(FamilyActivitySelection.self, from: data) else {
            activitySelection = FamilyActivitySelection()
            return
        }
        activitySelection = selection
    }

    private func clearPersistedSelection() {
        defaults.removeObject(forKey: AppGroupStore.Key.familyActivitySelection)
    }

    var applicationTokenCount: Int { activitySelection.applicationTokens.count }
    var webDomainTokenCount: Int { activitySelection.webDomainTokens.count }
}
