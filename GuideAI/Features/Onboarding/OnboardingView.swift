import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var page = 0
    @State private var authError: String?
    @State private var isRequestingAuth = false

    private let pages: [(title: String, body: String, symbol: String)] = [
        (
            "AI isn't going away.",
            "\(AppConfig.productDisplayName) helps families choose how AI fits into learning—not whether it exists at all.",
            "sparkles"
        ),
        (
            "Block uncontrolled AI.",
            "Restrict the external AI apps and websites you select using Apple's Screen Time controls.",
            "hand.raised.fill"
        ),
        (
            "Keep approved AI useful.",
            "Your child can still use \(AppConfig.productDisplayName) under Learning, Standard, or Restricted rules you set.",
            "book.fill"
        ),
        (
            "Enable Controls.",
            "This beta uses on-device authorization on your iPhone for the demonstration—not full Family Sharing enrollment.",
            "lock.shield.fill"
        )
    ]

    var body: some View {
        VStack(spacing: GuideTheme.sectionSpacing) {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                    VStack(spacing: 24) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 56))
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        Text(item.title)
                            .font(GuideTheme.titleFont)
                            .multilineTextAlignment(.center)
                        Text(item.body)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .tag(index)
                    .padding()
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            if page == pages.count - 1 {
                VStack(spacing: 12) {
                    if let authError {
                        Text(authError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                    Button {
                        Task { await enableControls() }
                    } label: {
                        if isRequestingAuth {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Enable Parental Controls")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRequestingAuth)

                    Button("Continue without authorization") {
                        env.completeOnboarding()
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            } else {
                Button("Next") { withAnimation { page += 1 } }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
            }
        }
        .padding(.bottom)
    }

    private func enableControls() async {
        isRequestingAuth = true
        authError = nil
        defer { isRequestingAuth = false }
        do {
            try await env.familyControls.requestAuthorization()
            env.syncShieldsFromPolicy()
            env.completeOnboarding()
        } catch {
            authError = "Authorization was not granted. You can try again in Settings or continue to explore the app."
        }
    }
}
