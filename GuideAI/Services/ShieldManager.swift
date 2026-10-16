import FamilyControls
import Foundation
import ManagedSettings
import os

@MainActor
final class ShieldManager {
    private let logger = Logger(subsystem: AppConfig.bundleIdentifier, category: "Shield")
    #if !GUIDEAI_DEMO
    private let store = ManagedSettingsStore()
    #endif

    func apply(selection: FamilyActivitySelection) {
        #if GUIDEAI_DEMO
        logger.info("Video demo preview: skipped ManagedSettings shield application")
        return
        #else
        guard !selection.applicationTokens.isEmpty || !selection.webDomainTokens.isEmpty || !selection.categoryTokens.isEmpty else {
            clearRestrictions()
            logger.info("Cleared shields because the saved selection is empty")
            return
        }
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        if !selection.categoryTokens.isEmpty {
            store.shield.applicationCategories = .specific(selection.categoryTokens, except: Set())
            store.shield.webDomainCategories = .specific(selection.categoryTokens, except: Set())
        } else {
            store.shield.applicationCategories = nil
            store.shield.webDomainCategories = nil
        }
        logger.info("Applied shields: \(selection.applicationTokens.count) apps, \(selection.webDomainTokens.count) domains")
        #endif
    }

    func clearRestrictions() {
        #if GUIDEAI_DEMO
        logger.info("Video demo preview: no ManagedSettings shields to clear")
        #else
        store.shield.applications = nil
        store.shield.webDomains = nil
        store.shield.applicationCategories = nil
        store.shield.webDomainCategories = nil
        logger.info("Cleared ManagedSettings shields")
        #endif
    }

    func refreshFromSavedPolicy(
        policy: ParentalPolicy,
        selection: FamilyActivitySelection,
        isAuthorized: Bool
    ) {
        guard isAuthorized else {
            clearRestrictions()
            return
        }
        if policy.blockExternalAI {
            apply(selection: selection)
        } else {
            clearRestrictions()
        }
    }
}
