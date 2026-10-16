import Foundation

struct ParentalPolicy: Codable, Equatable {
    var mode: AIMode
    var blockExternalAI: Bool
    var dailyLimitMinutes: Int
    var customInstructions: String
    var requireAttemptFirst: Bool
    var allowFullAssignmentGeneration: Bool
    var updatedAt: Date

    static let `default` = ParentalPolicy(
        mode: .learning,
        blockExternalAI: true,
        dailyLimitMinutes: 45,
        customInstructions: "",
        requireAttemptFirst: true,
        allowFullAssignmentGeneration: false,
        updatedAt: Date()
    )

    var dailyLimitSeconds: Int { dailyLimitMinutes * 60 }
}
