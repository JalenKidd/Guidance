import SwiftUI

struct ParentDashboardView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var showPicker = false
    @State private var showModeConfig = false
    @State private var showSettings = false

    private var policy: ParentalPolicy { env.policyStore.policy }

    var body: some View {
        NavigationStack {
            ZStack {
                GuideTheme.pageBackground
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: GuideTheme.sectionSpacing) {
                        dashboardHeader
                        protectionHero
                        dailySnapshot
                        UsageView()
                        quickControls
                        ControlsStatusView()
                        #if DEBUG
                        DemoToolsSection()
                        #endif
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showPicker) {
                AISelectionView()
            }
            .sheet(isPresented: $showModeConfig) {
                ModeConfigurationView()
            }
            .sheet(isPresented: $showSettings) {
                ParentSettingsView()
            }
        }
    }

    private var dashboardHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(GuideTheme.brand)
                    .frame(width: 48, height: 48)
                Image(systemName: "shield.lefthalf.filled")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("GUIDEAI")
                    .font(.caption2.weight(.heavy))
                    .kerning(1.2)
                    .foregroundStyle(GuideTheme.brand)
                Text("Parent overview")
                    .font(.title2.bold())
            }

            Spacer()

            Button {
                withAnimation(.snappy(duration: 0.3)) {
                    env.activeRole = .child
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "person.crop.circle.fill")
                    Text("Child")
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .background(GuideTheme.cardBackground, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private var selectedCount: Int {
        env.familyControls.applicationTokenCount + env.familyControls.webDomainTokenCount
    }

    private var protectionTitle: String {
        guard env.familyControls.isAuthorized else { return "Finish protection setup" }
        if policy.blockExternalAI && selectedCount > 0 { return "Protection is active" }
        if policy.blockExternalAI { return "Choose AI apps to protect" }
        return "External AI is allowed"
    }

    private var protectionMessage: String {
        guard env.familyControls.isAuthorized else {
            return "Authorize Screen Time controls to manage outside AI access."
        }
        if policy.blockExternalAI && selectedCount > 0 {
            return "Selected AI apps and websites are blocked. GuideAI remains available for approved learning."
        }
        if policy.blockExternalAI {
            return "Select the AI apps and websites you want GuideAI to block."
        }
        return "Turn blocking on from Limits & Settings whenever you are ready."
    }

    private var protectionHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(
                    env.familyControls.isAuthorized ? "Screen Time ready" : "Setup needed",
                    systemImage: env.familyControls.isAuthorized ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                )
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.16), in: Capsule())

                Spacer()

                Image(systemName: "shield.checkered")
                    .font(.system(size: 32, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(protectionTitle)
                    .font(.system(.title, design: .rounded).weight(.bold))
                Text(protectionMessage)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                showPicker = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.app.fill")
                    Text(selectedCount == 0 ? "Choose apps & websites" : "Manage protected apps")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(GuideTheme.brandDeep)
                .padding(.horizontal, 15)
                .frame(height: 48)
                .background(.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(GuideTheme.heroGradient)
                .shadow(color: GuideTheme.brand.opacity(0.22), radius: 18, y: 9)
        }
    }

    private var dailySnapshot: some View {
        HStack(spacing: 0) {
            snapshotMetric(
                icon: "book.closed.fill",
                tint: GuideTheme.brand,
                value: policy.mode.shortName,
                label: "AI mode"
            )

            snapshotDivider

            snapshotMetric(
                icon: "clock.fill",
                tint: .orange,
                value: "\(env.usageTracker.dailyUsage.minutesUsed)m",
                label: "Used today"
            )

            snapshotDivider

            snapshotMetric(
                icon: "lock.shield.fill",
                tint: GuideTheme.success,
                value: "\(selectedCount)",
                label: "Protected"
            )
        }
        .guideCard(padding: 14)
    }

    private var snapshotDivider: some View {
        Divider()
            .frame(height: 48)
            .padding(.horizontal, 6)
    }

    private func snapshotMetric(icon: String, tint: Color, value: String, label: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
            Text(value)
                .font(.headline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var quickControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("QUICK CONTROLS")

            VStack(spacing: 0) {
                dashboardAction(
                    icon: "sparkles",
                    tint: GuideTheme.brand,
                    title: policy.mode.displayName,
                    subtitle: "Adjust how GuideAI responds"
                ) {
                    showModeConfig = true
                }

                Divider()
                    .padding(.leading, 66)

                dashboardAction(
                    icon: "slider.horizontal.3",
                    tint: .orange,
                    title: "Limits & settings",
                    subtitle: "\(policy.dailyLimitMinutes) minute daily limit"
                ) {
                    showSettings = true
                }
            }
            .guideCard(padding: 0)
        }
    }

    private func dashboardAction(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tint.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.headline)
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.heavy))
            .kerning(0.9)
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
    }
}

#if DEBUG
struct DemoToolsSection: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var backendOK: Bool?
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Divider()
                Text("Auth: \(String(describing: env.familyControls.authorizationStatus))")
                    .font(.caption.monospaced())
                Text("Tokens — apps: \(env.familyControls.applicationTokenCount), web: \(env.familyControls.webDomainTokenCount)")
                    .font(.caption.monospaced())
                HStack {
                    Button("Reapply Shields") { env.syncShieldsFromPolicy() }
                    Button("Clear Shields") { env.shieldManager.clearRestrictions() }
                }
                .buttonStyle(.bordered)
                Button("Test Backend") {
                    Task { backendOK = await APIClient().healthCheck() }
                }
                if let backendOK {
                    Text(backendOK ? "Backend reachable" : "Backend unreachable")
                        .font(.caption)
                }
                Button("Reset Onboarding") { env.resetOnboarding() }
                Button("Reset Demo Data", role: .destructive) { env.resetDemoData() }
            }
            .padding(.top, 8)
        } label: {
            Label("Demo controls", systemImage: "hammer.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .guideCard()
    }
}
#endif
