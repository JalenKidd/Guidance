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
        loadMessages()
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

        do {
            let response = try await apiClient.sendChat(messages: messages, policy: policy)
            messages.append(ChatMessage(role: .assistant, content: response.text))
            persistMessages()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "Something went wrong. Try again."
        }
    }
}
