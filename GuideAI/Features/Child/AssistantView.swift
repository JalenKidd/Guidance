import SwiftUI

struct AssistantView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var input = ""
    @FocusState private var focused: Bool
    private let showsCloseButton: Bool

    init(showsCloseButton: Bool = true) {
        self.showsCloseButton = showsCloseButton
    }

    private var policy: ParentalPolicy { env.policyStore.policy }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if env.usageTracker.isLimitReached(limitSeconds: policy.dailyLimitSeconds) {
                    DailyLimitView()
                } else {
                    messageList
                    inputBar
                }
            }
            .navigationTitle(AppConfig.productDisplayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsCloseButton {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") { dismiss() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Clear conversation", role: .destructive) {
                            env.aiService.clearConversation()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                HStack {
                    Text(policy.mode.shortName)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                    Text("\(env.usageTracker.remainingSeconds(limitSeconds: policy.dailyLimitSeconds) / 60) min left")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
        }
        .onAppear { startTrackingIfNeeded() }
        .onDisappear { env.usageTracker.pauseTracking() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                startTrackingIfNeeded()
            } else {
                env.usageTracker.pauseTracking()
            }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if env.aiService.messages.filter({ $0.role != .system }).isEmpty && !env.aiService.isLoading {
                        assistantWelcome
                    }
                    ForEach(env.aiService.messages.filter { $0.role != .system }) { message in
                        ChatBubbleView(message: message)
                            .id(message.id)
                    }
                    if env.aiService.isLoading {
                        ProgressView("Thinking…")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    if let error = env.aiService.lastError {
                        VStack(spacing: 8) {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                            Button("Retry") {
                                Task {
                                    await env.aiService.retryLastRequest(
                                        policy: policy,
                                        usageTracker: env.usageTracker
                                    )
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                    }
                }
                .padding()
            }
            .onChange(of: env.aiService.messages.count) { _, _ in
                if let id = env.aiService.messages.last?.id {
                    withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
        }
    }

    private var assistantWelcome: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(GuideTheme.brand.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "book.pages.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(GuideTheme.brand)
            }

            VStack(spacing: 7) {
                Text("Learning Mode is on")
                    .font(.title3.weight(.bold))
                Text("I’ll help you understand, plan, and improve your work without replacing your thinking.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 9) {
                promptSuggestion("Help me outline a Civil War essay", icon: "list.bullet.rectangle")
                promptSuggestion("Quiz me on a topic", icon: "questionmark.bubble")
                promptSuggestion("Explain a hard concept", icon: "lightbulb.fill")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }

    private func promptSuggestion(_ prompt: String, icon: String) -> some View {
        Button {
            input = prompt
            focused = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(GuideTheme.brand)
                    .frame(width: 22)
                Text(prompt)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.left")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(13)
            .background(GuideTheme.cardBackground, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask for guided help…", text: $input, axis: .vertical)
                .lineLimit(1...4)
                .focused($focused)
                .disabled(env.aiService.isLoading)
            Button {
                let text = input
                input = ""
                Task {
                    await env.aiService.send(userText: text, policy: policy, usageTracker: env.usageTracker)
                }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || env.aiService.isLoading)
            .accessibilityLabel("Send")
        }
        .padding()
        .background(.bar)
    }

    private func startTrackingIfNeeded() {
        env.usageTracker.startTracking(limitSeconds: policy.dailyLimitSeconds)
    }
}
