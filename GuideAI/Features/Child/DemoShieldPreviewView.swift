import SwiftUI

struct DemoShieldPreviewView: View {
    let onGuidedHelp: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            GuideTheme.pageBackground
                .ignoresSafeArea()

            VStack(spacing: 24) {
                HStack {
                    Label("GUIDANCE PROTECTION", systemImage: "shield.lefthalf.filled")
                        .font(.caption2.weight(.heavy))
                        .kerning(0.8)
                        .foregroundStyle(GuideTheme.brand)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(GuideTheme.brand.opacity(0.10), in: Capsule())
                    Spacer()
                    Button("Close") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                }

                Spacer()

                ZStack {
                    Circle()
                        .fill(GuideTheme.brand.opacity(0.12))
                        .frame(width: 104, height: 104)
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 46, weight: .semibold))
                        .foregroundStyle(GuideTheme.brand)
                }

                VStack(spacing: 10) {
                    Text("This AI tool is paused")
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .multilineTextAlignment(.center)
                    Text("Your parent chose \(AppConfig.productDisplayName) for learning-focused help. You can still get explanations, hints, and feedback without a ready-to-submit answer.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: onGuidedHelp) {
                    HStack {
                        Image(systemName: "book.pages.fill")
                        Text("Get Guided Help")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 56)
                    .background(GuideTheme.actionGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)

                Text("Ask your parent to change this restriction, or continue with guided help.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Spacer()
            }
            .padding(24)
        }
    }
}
