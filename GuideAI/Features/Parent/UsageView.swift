import SwiftUI

struct UsageView: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        let policy = env.policyStore.policy
        let usage = env.usageTracker.dailyUsage
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(GuideTheme.brand.opacity(0.12))
                            .frame(width: 38, height: 38)
                        Image(systemName: "chart.bar.fill")
                            .foregroundStyle(GuideTheme.brand)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Today's GuideAI usage")
                            .font(.subheadline.weight(.semibold))
                        Text("\(usage.requestCount) approved request\(usage.requestCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text("\(usage.minutesUsed) / \(policy.dailyLimitMinutes)m")
                    .font(.subheadline.weight(.bold))
            }

            ProgressView(
                value: Double(min(usage.secondsUsed, policy.dailyLimitSeconds)),
                total: Double(max(policy.dailyLimitSeconds, 1))
            )
            .tint(GuideTheme.brand)
        }
        .guideCard()
    }
}
