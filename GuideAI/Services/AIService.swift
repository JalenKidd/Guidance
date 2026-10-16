import Foundation

@MainActor
final class AIService: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isLoading = false
    @Published var lastError: String?

    private let apiClient: APIClient
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(apiClient: APIClient = APIClient(), defaults: UserDefaults = AppGroupStore.sharedDefaults) {
        self.apiClient = apiClient
        self.defaults = defaults
        #if GUIDEAI_DEMO
        // Begin every recording session with a clean conversation. Responses
        // are generated locally below, so the demo never depends on Wi-Fi or a key.
        if ProcessInfo.processInfo.arguments.contains("-answeredDemo") {
            self.messages = [
                ChatMessage(role: .user, content: Self.demoEssayPrompt),
                ChatMessage(role: .assistant, content: Self.demoEssayResponse)
            ]
        } else {
            self.messages = []
        }
        #else
        loadMessages()
        #endif
    }

    func loadMessages() {
        guard let data = defaults.data(forKey: AppGroupStore.Key.conversationMessages),
              let decoded = try? decoder.decode([ChatMessage].self, from: data) else {
            messages = []
            return
        }
        messages = decoded
    }

    func persistMessages() {
        if let data = try? encoder.encode(messages) {
            defaults.set(data, forKey: AppGroupStore.Key.conversationMessages)
        }
    }

    func clearConversation() {
        messages = []
        persistMessages()
        lastError = nil
    }

    func send(userText: String, policy: ParentalPolicy, usageTracker: UsageTracker) async {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let limit = policy.dailyLimitSeconds
        guard !usageTracker.isLimitReached(limitSeconds: limit) else {
            lastError = "Today's AI time has been used."
            return
        }

        lastError = nil
        isLoading = true
        defer { isLoading = false }

        let userMessage = ChatMessage(role: .user, content: trimmed)
        messages.append(userMessage)
        persistMessages()
        usageTracker.recordRequest(limitSeconds: limit)

        await requestResponse(policy: policy, managesLoadingState: false)
    }

    func retryLastRequest(policy: ParentalPolicy, usageTracker: UsageTracker) async {
        let limit = policy.dailyLimitSeconds
        guard !isLoading,
              !usageTracker.isLimitReached(limitSeconds: limit),
              messages.last?.role == .user else { return }

        lastError = nil
        isLoading = true
        defer { isLoading = false }
        usageTracker.recordRequest(limitSeconds: limit)

        await requestResponse(policy: policy, managesLoadingState: false)
    }

    private func requestResponse(policy: ParentalPolicy, managesLoadingState: Bool = true) async {
        if managesLoadingState {
            lastError = nil
            isLoading = true
        }
        defer {
            if managesLoadingState { isLoading = false }
        }

        #if GUIDEAI_DEMO
        try? await Task.sleep(for: .milliseconds(650))
        let prompt = messages.last(where: { $0.role == .user })?.content ?? ""
        messages.append(ChatMessage(role: .assistant, content: demoResponse(for: prompt, policy: policy)))
        persistMessages()
        #else
        do {
            let response = try await apiClient.sendChat(messages: messages, policy: policy)
            messages.append(ChatMessage(role: .assistant, content: response.text))
            persistMessages()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "Something went wrong. Try again."
        }
        #endif
    }

    #if GUIDEAI_DEMO
    private func demoResponse(for prompt: String, policy: ParentalPolicy) -> String {
        let normalized = prompt.lowercased()

        if normalized.contains("essay") || normalized.contains("civil war") || normalized.contains("outline") {
            return Self.demoEssayResponse
        }

        if normalized.contains("quiz") || normalized.contains("test me") {
            return """
            Let’s do one question at a time.

            Question 1: Why did debates over slavery in western territories increase tension between the North and South?

            Answer in one or two sentences, and I’ll give you a hint or feedback before the next question.
            """
        }

        if normalized.contains("explain") || normalized.contains("understand") {
            return """
            Let’s break it into three parts: what happened, why it happened, and why it mattered.

            Start by telling me the specific idea or sentence that feels confusing. I’ll explain it with an example, then ask you to put it in your own words.
            """
        }

        return """
        I can help you work through that without replacing your thinking.

        First, tell me what you already know or what you have tried. Then I can offer a hint, a short explanation, or feedback on your approach.
        """
    }

    private static let demoEssayPrompt = "Help me outline a Civil War essay"

    private static let demoEssayResponse = """
    I can help you build a strong essay, but I won’t write a ready-to-submit assignment for you.

    Possible thesis:
    The Civil War became increasingly difficult to avoid because the expansion of slavery deepened political division, weakened compromise, and turned sectional conflict into a national crisis.

    Evidence plan:
    1. Expansion of slavery into western territories
    2. Breakdown of compromises and political parties
    3. Election of 1860 and secession

    Your turn: Which of those three causes do you think made conflict most unavoidable, and why?
    """
    #endif
}
