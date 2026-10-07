import Combine
import FamilyControls
import SwiftUI

@MainActor
final class AppEnvironment: ObservableObject {
    let policyStore: LocalPolicyStore
    private var cancellables = Set<AnyCancellable>()
    let familyControls: FamilyControlsManager
    let shieldManager: ShieldManager
    let usageTracker: UsageTracker
    let aiService: AIService
    let parentAuth = ParentAuthenticationService()

    @Published var onboardingComplete: Bool
    @Published var activeRole: UserRole

    init() {
        self.policyStore = LocalPolicyStore()
        self.familyControls = FamilyControlsManager()
        self.shieldManager = ShieldManager()
        self.usageTracker = UsageTracker()
        self.aiService = AIService()
        self.onboardingComplete = AppGroupStore.sharedDefaults.bool(forKey: AppGroupStore.Key.onboardingComplete)
        #if DEBUG
        self.activeRole = ProcessInfo.processInfo.arguments.contains("-parentMode") ? .parent : .child
        #else
        self.activeRole = .child
        #endif

        policyStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        familyControls.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        usageTracker.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        aiService.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func completeOnboarding() {
        onboardingComplete = true
        AppGroupStore.sharedDefaults.set(true, forKey: AppGroupStore.Key.onboardingComplete)
        // First-time setup: land in Parent Mode so controls can be configured before Child Mode.
        activeRole = .parent
    }

    func resetOnboarding() {
        onboardingComplete = false
        AppGroupStore.sharedDefaults.set(false, forKey: AppGroupStore.Key.onboardingComplete)
    }

    func syncShieldsFromPolicy() {
        familyControls.refreshAuthorizationStatus()
        shieldManager.refreshFromSavedPolicy(
            policy: policyStore.policy,
            selection: familyControls.activitySelection,
            isAuthorized: familyControls.isAuthorized
        )
    }

    func updatePolicy(_ mutate: (inout ParentalPolicy) -> Void) {
        var policy = policyStore.policy
        mutate(&policy)
        policyStore.save(policy)
        syncShieldsFromPolicy()
    }

    func resetDemoData() {
        policyStore.resetToDefaults()
        usageTracker.resetToday()
        aiService.clearConversation()
        familyControls.activitySelection = FamilyActivitySelection()
        familyControls.saveSelection()
        shieldManager.clearRestrictions()
    }
}
