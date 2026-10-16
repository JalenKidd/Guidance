import SwiftUI

struct ChildHomeView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var showAssistant = false
    @State private var showDemoShieldPreview = false
    @State private var showModeDetails = false
    @State private var authError: String?
    private let onOpenProgress: () -> Void

    init(onOpenProgress: @escaping () -> Void = {}) {
        self.onOpenProgress = onOpenProgress
    }

    private var policy: ParentalPolicy { env.policyStore.policy }

    var body: some View {
        NavigationStack {
            ZStack {
                GuideTheme.pageBackground
                    .ignoresSafeArea()

                Group {
                    if env.usageTracker.isLimitReached(limitSeconds: policy.dailyLimitSeconds) {
                        DailyLimitView()
                    } else {
                        mainContent
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showAssistant) {
                AssistantView()
            }
            .sheet(isPresented: $showModeDetails) {
                ChildModeDetailsView()
            }
            .fullScreenCover(isPresented: $showDemoShieldPreview) {
                DemoShieldPreviewView {
                    showDemoShieldPreview = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        showAssistant = true
                    }
                }
            }
            .onAppear {
                #if GUIDEAI_DEMO
                if ProcessInfo.processInfo.arguments.contains("-shieldPreview") {
                    showDemoShieldPreview = true
                }
                #endif
                presentPendingAssistantIfNeeded()
            }
            .onChange(of: env.shouldOpenAssistant) { _, _ in
                presentPendingAssistantIfNeeded()
            }
        }
    }

    private var mainContent: some View {
        ScrollView {
            LazyVStack(spacing: GuideTheme.sectionSpacing) {
                childHeader
                welcomeCard
                askGuideAIButton
                if AppConfig.isVideoDemo {
                    demoShieldButton
                }
                usageCard
                WeeklyTrendPreviewCard(onOpen: onOpenProgress)
                protectionCard

                if let authError {
                    Label(authError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
    }

    private var childHeader: some View {
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
                Text("Your learning space")
                    .font(.title2.bold())
            }

            Spacer()

            ParentModeButton(authError: $authError)
                .frame(width: 44, height: 44)
                .background(GuideTheme.cardBackground, in: Circle())
                .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private var welcomeCard: some View {
        Button {
            showModeDetails = true
        } label: {
            HStack(spacing: 15) {
                ZStack {
                    Circle()
                        .fill(GuideTheme.brand.opacity(0.12))
                        .frame(width: 58, height: 58)
                    Image(systemName: modeIcon)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(GuideTheme.brand)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("CURRENT MODE")
                        .font(.system(size: 10, weight: .heavy))
                        .kerning(0.8)
                        .foregroundStyle(.secondary)
                    Text(policy.mode.displayName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(modeMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .guideCard()
        }
        .buttonStyle(.plain)
    }

    private var askGuideAIButton: some View {
        Button {
            showAssistant = true
        } label: {
            HStack(spacing: 15) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.17))
                        .frame(width: 52, height: 52)
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.title3)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Ask \(AppConfig.productDisplayName)")
                        .font(.title3.weight(.bold))
                    Text("Start a guided conversation")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.80))
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.headline.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(GuideTheme.actionGradient)
                    .shadow(color: GuideTheme.brand.opacity(0.20), radius: 16, y: 8)
            }
        }
        .buttonStyle(.plain)
    }

    private var usageCard: some View {
        let usage = env.usageTracker.dailyUsage
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Today's usage", systemImage: "clock.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(usage.minutesUsed) of \(policy.dailyLimitMinutes) min")
                    .font(.subheadline.weight(.bold))
            }

            ProgressView(
                value: Double(min(usage.secondsUsed, policy.dailyLimitSeconds)),
                total: Double(max(policy.dailyLimitSeconds, 1))
            )
            .tint(GuideTheme.brand)

            Text("Your daily limit refreshes tomorrow.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .guideCard()
    }

    private var demoShieldButton: some View {
        Button {
            showDemoShieldPreview = true
        } label: {
            HStack(spacing: 13) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Open ChatGPT")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Restricted by your parent • Guided help available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .guideCard()
        }
        .buttonStyle(.plain)
    }

    private var protectionCard: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(protectionColor.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: policy.blockExternalAI ? "lock.shield.fill" : "lock.open.fill")
                    .foregroundStyle(protectionColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(policy.blockExternalAI ? "Outside AI is protected" : "Outside AI is available")
                    .font(.subheadline.weight(.semibold))
                Text(policy.blockExternalAI ? "Use \(AppConfig.productDisplayName) for parent-approved help." : "Your parent currently allows external AI access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .guideCard()
    }

    private var modeIcon: String {
        switch policy.mode {
        case .learning: return "book.closed.fill"
        case .standard: return "sparkles"
        case .restricted: return "hand.raised.fill"
        }
    }

    private var modeMessage: String {
        switch policy.mode {
        case .learning: return "Hints and questions help you understand."
        case .standard: return "Helpful answers with built-in safety rules."
        case .restricted: return "Definitions, hints, and feedback only."
        }
    }

    private var protectionColor: Color {
        policy.blockExternalAI ? GuideTheme.success : .orange
    }

    private func presentPendingAssistantIfNeeded() {
        guard env.shouldOpenAssistant else { return }
        env.shouldOpenAssistant = false
        showAssistant = true
    }
}

private struct ChildModeDetailsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    private var policy: ParentalPolicy { env.policyStore.policy }

    var body: some View {
        NavigationStack {
            ZStack {
                GuideTheme.pageBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        ZStack {
                            Circle()
                                .fill(GuideTheme.brandSoft)
                                .frame(width: 88, height: 88)
                            Image(systemName: modeIcon)
                                .font(.system(size: 34, weight: .semibold))
                                .foregroundStyle(GuideTheme.brand)
                        }

                        VStack(spacing: 7) {
                            Text(policy.mode.displayName)
                                .font(.title2.bold())
                            Text(policy.mode.summary)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            modeRule("Hints and explanations are always available", icon: "lightbulb.fill")
                            modeRule("Guidance asks questions that keep you thinking", icon: "questionmark.bubble.fill")
                            modeRule("Ready-to-submit assignments stay off", icon: "doc.badge.ellipsis")
                        }
                        .guideCard()

                        Label("A parent can switch modes from the Controls tab.", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("How your mode works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func modeRule(_ text: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(GuideTheme.brand)
                .frame(width: 26)
            Text(text)
                .font(.subheadline)
            Spacer()
        }
    }

    private var modeIcon: String {
        switch policy.mode {
        case .learning: return "book.closed.fill"
        case .standard: return "sparkles"
        case .restricted: return "hand.raised.fill"
        }
    }
}

struct ParentModeButton: View {
    @EnvironmentObject private var env: AppEnvironment
    @Binding var authError: String?

    var body: some View {
        Button {
            Task {
                do {
                    try await env.parentAuth.authenticate()
                    env.activeRole = .parent
                    authError = nil
                } catch {
                    authError = (error as? LocalizedError)?.errorDescription
                }
            }
        } label: {
            Label("Parent Settings", systemImage: "lock.fill")
                .labelStyle(.iconOnly)
        }
        .accessibilityLabel("Parent Settings")
    }
}
