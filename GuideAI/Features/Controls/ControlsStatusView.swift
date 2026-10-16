import SwiftUI

struct ControlsStatusView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 13) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: env.familyControls.isAuthorized ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .font(.headline)
                        .foregroundStyle(statusColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Protection status")
                        .font(.subheadline.weight(.semibold))
                    Text(statusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(env.familyControls.isAuthorized ? "ACTIVE" : "ACTION")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(statusColor.opacity(0.10), in: Capsule())
            }

            if !env.familyControls.isAuthorized {
                Button("Authorize Screen Time") {
                    Task {
                        do {
                            try await env.familyControls.requestAuthorization()
                            env.syncShieldsFromPolicy()
                            errorMessage = nil
                        } catch {
                            errorMessage = "Authorization failed. Try again on a physical device."
                        }
                    }
                }
                .buttonStyle(.borderedProminent)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .guideCard()
    }

    private var statusColor: Color {
        env.familyControls.isAuthorized ? GuideTheme.success : .orange
    }

    private var statusDescription: String {
        return env.familyControls.isAuthorized
            ? "\(env.familyControls.selectedTokenCount) selected tools • \(env.policyStore.policy.mode.displayName)"
            : "Authorization required"
    }
}
