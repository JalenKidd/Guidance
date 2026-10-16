import FamilyControls
import SwiftUI

struct AuthorizationView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Screen Time Authorization")
                .font(GuideTheme.titleFont)
            Text(statusText)
                .foregroundStyle(.secondary)
            Button("Request Authorization") {
                Task {
                    do {
                        try await env.familyControls.requestAuthorization()
                        env.syncShieldsFromPolicy()
                        message = nil
                    } catch {
                        message = "Authorization failed. Try again on a physical device with Screen Time available."
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            if let message {
                Text(message).font(.footnote).foregroundStyle(.orange)
            }
        }
        .guideCard()
    }

    private var statusText: String {
        switch env.familyControls.authorizationStatus {
        case .approved, .approvedWithDataAccess:
            return "Authorized — Family Controls are active on this device."
        case .denied:
            return "Denied — open Settings to allow Screen Time access for \(AppConfig.productDisplayName)."
        case .notDetermined:
            return "Not determined — tap below to authorize."
        @unknown default:
            return "Unknown authorization state."
        }
    }
}
