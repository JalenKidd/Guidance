import SwiftUI

struct AppRouter: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        Group {
            if !env.onboardingComplete {
                OnboardingView()
            } else if env.activeRole == .parent {
                ParentDashboardView()
            } else {
                ChildHomeView()
            }
        }
        .tint(GuideTheme.brand)
        .onAppear {
            env.familyControls.refreshAuthorizationStatus()
            env.usageTracker.rolloverIfNeeded()
            env.syncShieldsFromPolicy()
        }
        .onChange(of: env.policyStore.policy) { _, _ in
            env.syncShieldsFromPolicy()
        }
        .onChange(of: env.familyControls.activitySelection) { _, _ in
            env.familyControls.saveSelection()
            env.syncShieldsFromPolicy()
        }
    }
}
