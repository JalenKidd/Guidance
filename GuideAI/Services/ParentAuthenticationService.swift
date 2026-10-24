import Foundation
import LocalAuthentication

enum ParentAuthenticationError: LocalizedError {
    case unavailable
    case failed
    case canceled

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Device authentication is not available. Enable a passcode and try again."
        case .failed:
            return "Authentication failed. Try again."
        case .canceled:
            return "Authentication was canceled."
        }
    }
}

struct ParentAuthenticationService {
    func authenticate(reason: String = "Unlock parent settings") async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var error: NSError?
        let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
            ? .deviceOwnerAuthentication
            : .deviceOwnerAuthenticationWithBiometrics

        guard context.canEvaluatePolicy(policy, error: &error) else {
            throw ParentAuthenticationError.unavailable
        }

        let success = try await context.evaluatePolicy(policy, localizedReason: reason)
        if !success {
            throw ParentAuthenticationError.failed
        }
    }
}
