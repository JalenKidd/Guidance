import Foundation
import os

enum GuidanceAPIError: LocalizedError {
    case server(status: Int, message: String)
    case unreachable
    case decoding

    var errorDescription: String? {
        switch self {
        case .server(_, let message):
            return message
        case .unreachable:
            return "Can't reach the Guidance server. Check that it's running and the address in Setup is right."
        case .decoding:
            return "The Guidance server sent something unexpected."
        }
    }

    var isUnauthorized: Bool {
        if case .server(let status, _) = self { return status == 401 }
        return false
    }
}

/// Parent-side client for the Guidance backend (`Backend/functions/src/app.ts`).
struct GuidanceAPI {
    private static let logger = Logger(subsystem: AppConfig.bundleIdentifier, category: "API")

    var baseURL: URL = AppConfig.apiBaseURL
    var session: URLSession = .shared

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = fractional.date(from: string) ?? plain.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date \(string)")
        }
        return decoder
    }()

    private struct ErrorBody: Decodable { let error: String }
    private struct Empty: Decodable {}

    private func send<Response: Decodable>(
        _ method: String,
        _ path: String,
        token: String? = nil,
        body: Data? = nil
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            Self.logger.error("\(method) \(path) failed: \(error.localizedDescription)")
            throw GuidanceAPIError.unreachable
        }
        guard let http = response as? HTTPURLResponse else { throw GuidanceAPIError.unreachable }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
                ?? "Guidance server error (\(http.statusCode))."
            throw GuidanceAPIError.server(status: http.statusCode, message: message)
        }
        if Response.self == Empty.self || data.isEmpty, let empty = Empty() as? Response { return empty }
        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
            Self.logger.error("Decoding \(path) failed: \(error.localizedDescription)")
            throw GuidanceAPIError.decoding
        }
    }

    private func json(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    // MARK: - Endpoints

    struct FamilyResponse: Decodable {
        let familyId: String
        let parentName: String?
        let kids: [Kid]
    }

    func health() async -> Bool {
        struct Health: Decodable { let ok: Bool }
        return ((try? await send("GET", "health") as Health)?.ok) ?? false
    }

    func catalog() async throws -> AICatalog {
        try await send("GET", "catalog")
    }

    struct SignInResponse: Decodable {
        let familyId: String
        let parentToken: String
        let parentName: String?

        var session: FamilySession { FamilySession(familyId: familyId, parentToken: parentToken) }
    }

    func signIn(email: String, password: String) async throws -> SignInResponse {
        try await send("POST", "auth/sign-in", body: json(["email": email, "password": password]))
    }

    func renameKid(_ kidID: String, to name: String, session: FamilySession) async throws -> Kid {
        try await send("PUT", "families/\(session.familyId)/kids/\(kidID)", token: session.parentToken, body: json(["name": name]))
    }

    func createFamily(parentName: String) async throws -> FamilySession {
        try await send("POST", "families", body: json(["parentName": parentName]))
    }

    func setParentName(_ name: String, session: FamilySession) async throws -> FamilyResponse {
        try await send("PUT", "families/\(session.familyId)", token: session.parentToken, body: json(["parentName": name]))
    }

    func family(_ session: FamilySession) async throws -> FamilyResponse {
        try await send("GET", "families/\(session.familyId)", token: session.parentToken)
    }

    func addKid(named name: String, session: FamilySession) async throws -> Kid {
        try await send("POST", "families/\(session.familyId)/kids", token: session.parentToken, body: json(["name": name]))
    }

    func removeKid(_ kidID: String, session: FamilySession) async throws {
        let _: Empty = try await send("DELETE", "families/\(session.familyId)/kids/\(kidID)", token: session.parentToken)
    }

    func savePolicy(_ policy: KidPolicy, kidID: String, session: FamilySession, changeId: String) async throws -> Kid {
        // Keep the policy body compatible with older servers, which ignore unknown keys.
        struct Update: Encodable {
            let policy: KidPolicy
            let changeId: String
            enum CodingKeys: String, CodingKey { case changeId }

            func encode(to encoder: Encoder) throws {
                try policy.encode(to: encoder)
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(changeId, forKey: .changeId)
            }
        }
        return try await send("PUT", "families/\(session.familyId)/kids/\(kidID)/policy", token: session.parentToken,
                              body: json(Update(policy: policy, changeId: changeId)))
    }

    func activity(kidID: String, session: FamilySession) async throws -> KidActivity {
        try await send("GET", "families/\(session.familyId)/kids/\(kidID)/activity", token: session.parentToken)
    }

    struct RequestDecisionResponse: Decodable {
        let request: AccessRequest
        let kid: Kid
    }

    func decideRequest(_ requestID: String, approve: Bool, minutes: Int?, kidID: String, session: FamilySession) async throws -> RequestDecisionResponse {
        struct Decision: Encodable { let approve: Bool; let minutes: Int? }
        return try await send(
            "POST",
            "families/\(session.familyId)/kids/\(kidID)/requests/\(requestID)",
            token: session.parentToken,
            body: json(Decision(approve: approve, minutes: minutes))
        )
    }

    func suggestSite(domain: String, categoryID: String?, note: String?, session: FamilySession) async throws {
        struct Suggestion: Encodable { let domain: String; let categoryId: String?; let note: String? }
        let _: Empty = try await send(
            "POST",
            "families/\(session.familyId)/suggestions",
            token: session.parentToken,
            body: json(Suggestion(domain: domain, categoryId: categoryID, note: note))
        )
    }
}
