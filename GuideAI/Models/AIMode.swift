import Foundation

enum AIMode: String, Codable, CaseIterable, Identifiable {
    case learning
    case standard
    case restricted

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .learning: return "Learning Mode"
        case .standard: return "Standard Mode"
        case .restricted: return "Restricted Mode"
        }
    }

    var shortName: String {
        switch self {
        case .learning: return "Learning"
        case .standard: return "Standard"
        case .restricted: return "Restricted"
        }
    }

    var summary: String {
        switch self {
        case .learning:
            return "Guides understanding with hints and questions instead of doing the work for the student."
        case .standard:
            return "Helpful, direct answers while following safety rules and your custom instructions."
        case .restricted:
            return "Definitions, hints, and feedback only—no complete assignments or essays."
        }
    }
}
