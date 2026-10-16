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
    @Published var shouldOpenAssistant = false

    init() {
        self.policyStore = LocalPolicyStore()
        self.familyControls = FamilyControlsManager()
        self.shieldManager = ShieldManager()
        self.usageTracker = UsageTracker()
        self.aiService = AIService()

        #if GUIDEAI_DEMO
        // Keep the recording build on a predictable, ready-to-show screen.
        let launchArguments = ProcessInfo.processInfo.arguments
        self.policyStore.resetToDefaults()
        self.onboardingComplete = true
        self.activeRole = launchArguments.contains("-childMode")
            || launchArguments.contains("-shieldRedirect")
            || launchArguments.contains("-shieldPreview")
            || launchArguments.contains("-answeredDemo") ? .child : .parent
        self.shouldOpenAssistant = launchArguments.contains("-shieldRedirect")
            || launchArguments.contains("-answeredDemo")
        AppGroupStore.sharedDefaults.set(true, forKey: AppGroupStore.Key.onboardingComplete)
        #else
        self.onboardingComplete = AppGroupStore.sharedDefaults.bool(forKey: AppGroupStore.Key.onboardingComplete)
        #if DEBUG
        self.activeRole = ProcessInfo.processInfo.arguments.contains("-parentMode") ? .parent : .child
        self.shouldOpenAssistant = ProcessInfo.processInfo.arguments.contains("-shieldRedirect")
        #else
        self.activeRole = .child
        #endif
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

    func consumePendingShieldRedirect() {
        let defaults = AppGroupStore.sharedDefaults
        guard defaults.bool(forKey: AppGroupStore.Key.openAssistantFromShield) else { return }
        defaults.removeObject(forKey: AppGroupStore.Key.openAssistantFromShield)
        activeRole = .child
        shouldOpenAssistant = true
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
