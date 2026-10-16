import SwiftUI

struct ParentDashboardView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var showPicker = false
    @State private var showModeConfig = false
    private let onOpenActivity: () -> Void
    private let onOpenControls: () -> Void

    init(
        onOpenActivity: @escaping () -> Void = {},
        onOpenControls: @escaping () -> Void = {}
    ) {
        self.onOpenActivity = onOpenActivity
        self.onOpenControls = onOpenControls
    }

    private var policy: ParentalPolicy { env.policyStore.policy }

    var body: some View {
        NavigationStack {
            ZStack {
                GuideTheme.pageBackground
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: GuideTheme.sectionSpacing) {
                        dashboardHeader
                        if AppConfig.isVideoDemo {
                            demoBuildBanner
                        }
                        protectionHero
                        dailySnapshot
                        UsageView()
                        WeeklyTrendPreviewCard(onOpen: onOpenActivity)
                        quickControls
                        ControlsStatusView()
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
                Text(AppConfig.productDisplayName.uppercased())
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

    private var demoBuildBanner: some View {
        HStack(spacing: 11) {
            Image(systemName: "person.2.fill")
                .foregroundStyle(GuideTheme.brand)

            VStack(alignment: .leading, spacing: 2) {
                Text("PROTECTION ACTIVE")
                    .font(.caption2.weight(.heavy))
                    .kerning(0.8)
                    .foregroundStyle(GuideTheme.brand)
                Text("\(selectedCount) tools selected • \(policy.dailyLimitMinutes)-minute daily limit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(GuideTheme.success)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GuideTheme.cardBackground, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var selectedCount: Int {
        env.familyControls.selectedTokenCount
    }

    private var protectionTitle: String {
        guard env.familyControls.isAuthorized else { return "Finish protection setup" }
        if policy.blockExternalAI && selectedCount > 0 { return "Learning-first protection" }
        if policy.blockExternalAI { return "Choose AI tools to restrict" }
        return "External AI is allowed"
    }

    private var protectionMessage: String {
        guard env.familyControls.isAuthorized else {
            return "Authorize Screen Time controls to manage outside AI access."
        }
        if policy.blockExternalAI && selectedCount > 0 {
            return "\(env.familyControls.selectionSummary) restricted. Blocked attempts can open \(AppConfig.productDisplayName) for guided learning."
        }
        if policy.blockExternalAI {
            return "Select the AI apps and websites you want \(AppConfig.productDisplayName) to block."
        }
        return "Turn blocking on from Limits & Settings whenever you are ready."
    }

    private var protectionHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Button {
                    showModeConfig = true
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "book.closed.fill")
                        Text(policy.mode.displayName)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(GuideTheme.heroText.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Double tap to change AI mode")

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
                    .foregroundStyle(GuideTheme.heroSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                showPicker = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.app.fill")
                    Text(selectedCount == 0 ? "Choose restricted AI tools" : "Manage restricted tools")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(GuideTheme.brand)
                .padding(.horizontal, 15)
                .frame(height: 48)
                .background(GuideTheme.cardBackground, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(GuideTheme.heroText)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(GuideTheme.heroGradient)
                .shadow(color: GuideTheme.brand.opacity(0.14), radius: 18, y: 9)
        }
    }

    private var dailySnapshot: some View {
        HStack(spacing: 0) {
            Button {
                showModeConfig = true
            } label: {
                snapshotMetric(
                    icon: "book.closed.fill",
                    tint: GuideTheme.brand,
                    value: policy.mode.shortName,
                    label: "Tap to change"
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            snapshotDivider

            Button(action: onOpenActivity) {
                snapshotMetric(
                    icon: "clock.fill",
                    tint: .orange,
                    value: "\(env.usageTracker.dailyUsage.minutesUsed)m",
                    label: "View activity"
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            snapshotDivider

            Button {
                showPicker = true
            } label: {
                snapshotMetric(
                    icon: "lock.shield.fill",
                    tint: GuideTheme.success,
                    value: "\(selectedCount)",
                    label: "Manage tools"
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
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
                    subtitle: "Adjust how \(AppConfig.productDisplayName) responds"
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
                    onOpenControls()
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

