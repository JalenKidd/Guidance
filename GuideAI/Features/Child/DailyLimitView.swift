import SwiftUI

struct DailyLimitView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hourglass.bottomhalf.filled")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Today's AI time has been used.")
                .font(GuideTheme.titleFont)
                .multilineTextAlignment(.center)
            Text("Your limit resets tomorrow.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .accessibilityElement(children: .combine)
    }
}
