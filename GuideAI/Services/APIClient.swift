import Foundation
import os

enum APIClientError: LocalizedError {
    case invalidURL
    case invalidResponse
    case server(message: String)
    case decoding
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The assistant service is not configured correctly."
        case .invalidResponse:
            return "Unexpected response from the assistant service."
        case .server(let message):
            return message
        case .decoding:
            return "Could not read the assistant response."
        case .network:
            return "Could not reach the assistant service. Check your connection."
        }
    }
}

struct ChatAPIRequest: Encodable {
    struct MessagePayload: Encodable {
        let role: String
        let content: String
    }

    struct PolicyPayload: Encodable {
        let mode: String
        let customInstructions: String
        let requireAttemptFirst: Bool
        let allowFullAssignmentGeneration: Bool
    }

    let conversation: [MessagePayload]
    let policy: PolicyPayload
}

struct ChatAPIResponse: Decodable {
    struct UsagePayload: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
    }

    let text: String
    let usage: UsagePayload?
}

final class APIClient {
    private let logger = Logger(subsystem: AppConfig.bundleIdentifier, category: "API")
    private let session: URLSession
    private let baseURL: URL

    init(baseURL: URL = AppConfig.apiBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func sendChat(messages: [ChatMessage], policy: ParentalPolicy) async throws -> ChatAPIResponse {
        let url = baseURL.appendingPathComponent("chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90

        let payload = ChatAPIRequest(
            conversation: messages.suffix(40).map { .init(role: $0.role.rawValue, content: $0.content) },
            policy: .init(
                mode: policy.mode.rawValue,
                customInstructions: policy.customInstructions,
                requireAttemptFirst: policy.requireAttemptFirst,
                allowFullAssignmentGeneration: policy.allowFullAssignmentGeneration
            )
        )
        request.httpBody = try JSONEncoder().encode(payload)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }

            if !(200..<300).contains(http.statusCode) {
                if let err = try? JSONDecoder().decode([String: String].self, from: data),
                   let message = err["error"] {
                    throw APIClientError.server(message: message)
                }
                throw APIClientError.server(message: "Assistant service error (\(http.statusCode)).")
            }

            do {
                return try JSONDecoder().decode(ChatAPIResponse.self, from: data)
            } catch {
                logger.error("Decode failed: \(error.localizedDescription)")
                throw APIClientError.decoding
            }
        } catch let error as APIClientError {
            throw error
        } catch {
            logger.error("Network error: \(error.localizedDescription)")
            throw APIClientError.network(error)
        }
    }

    func healthCheck() async -> Bool {
        let url = baseURL.appendingPathComponent("health")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }
}
