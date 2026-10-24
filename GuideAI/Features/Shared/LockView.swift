import SwiftUI

/// What a kid sees if they open the app: rules stay in force, controls need the parent.
struct LockView: View {
    @EnvironmentObject private var store: FamilyStore
    @State private var error: String?
    @State private var authenticating = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(GuideTheme.brand)
            VStack(spacing: 8) {
                Text("AI is guided on this phone")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("Your family's rules are on in Safari. Ask a parent if you need something changed.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Spacer()
            Button(action: unlock) {
                Label("Parent unlock", systemImage: "faceid")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .foregroundStyle(.white)
                    .background(GuideTheme.actionGradient, in: RoundedRectangle(cornerRadius: GuideTheme.compactCornerRadius, style: .continuous))
            }
            .disabled(authenticating)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(GuideTheme.pageBackground.ignoresSafeArea())
    }

    private func unlock() {
        authenticating = true
        Task {
            defer { authenticating = false }
            do {
                try await ParentAuthenticationService().authenticate(reason: "Unlock Guidance parent controls")
                error = nil
                store.isUnlocked = true
            } catch ParentAuthenticationError.unavailable {
                #if targetEnvironment(simulator)
                // Simulators often have no passcode or enrolled Face ID.
                store.isUnlocked = true
                #else
                self.error = ParentAuthenticationError.unavailable.localizedDescription
                #endif
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
