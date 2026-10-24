import Foundation

/// How a whole AI category behaves on the kid's phone.
enum CategoryState: String, Codable, CaseIterable, Identifiable {
    case allow
    case guided
    case block

    var id: String { rawValue }

    var label: String {
        switch self {
        case .allow: return "Allow"
        case .guided: return "Guided"
        case .block: return "Block"
        }
    }

    var symbol: String {
        switch self {
        case .allow: return "checkmark.circle.fill"
        case .guided: return "graduationcap.circle.fill"
        case .block: return "nosign"
        }
    }

    var strictness: Int {
        switch self {
        case .allow: return 0
        case .guided: return 1
        case .block: return 2
        }
    }
}

enum SiteOverride: String, Codable, CaseIterable, Identifiable {
    case allow
    /// Only takes effect on sites whose category supports Guided (chatbots).
    case guided
    case block

    var id: String { rawValue }

    var label: String {
        switch self {
        case .allow: return "Always allow"
        case .guided: return "Always guided"
        case .block: return "Always block"
        }
    }

    var categoryState: CategoryState {
        switch self {
        case .allow: return .allow
        case .guided: return .guided
        case .block: return .block
        }
    }

    init(_ state: CategoryState) {
        switch state {
        case .allow: self = .allow
        case .guided: self = .guided
        case .block: self = .block
        }
    }

    /// The choices that make sense for a site in a category (Guided only for chatbots).
    static func options(supportsGuided: Bool) -> [SiteOverride] {
        supportsGuided ? allCases : [.allow, .block]
    }
}

struct AISchedule: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var enabled: Bool
    /// 0 = Sunday … 6 = Saturday (JavaScript `Date.getDay()`), shared with the extension.
    var days: [Int]
    /// "HH:MM", 24-hour. `end` earlier than `start` means the window runs past midnight.
    var start: String
    var end: String
    var masterAIOff: Bool
    var categories: [String: CategoryState]

    static func new(name: String) -> AISchedule {
        AISchedule(
            id: UUID().uuidString,
            name: name,
            enabled: true,
            days: [0, 1, 2, 3, 4],
            start: "16:00",
            end: "21:00",
            masterAIOff: false,
            categories: [:]
        )
    }

    static let schoolNightsPreset = AISchedule(
        id: UUID().uuidString,
        name: "School nights",
        enabled: true,
        days: [0, 1, 2, 3, 4],
        start: "16:00",
        end: "21:00",
        masterAIOff: false,
        categories: ["essay": .block, "math": .block, "homework": .block, "humanizers": .block, "chatbots": .guided]
    )

    static let bedtimePreset = AISchedule(
        id: UUID().uuidString,
        name: "Bedtime",
        enabled: true,
        days: [0, 1, 2, 3, 4, 5, 6],
        start: "21:30",
        end: "07:00",
        masterAIOff: true,
        categories: [:]
    )
}

struct GuidedRules: Codable, Equatable {
    var blockHomeworkOffloading: Bool
    var requireAttemptFirst: Bool
    var hideFinishedAnswers: Bool
    var globalInstructions: [String]

    init(blockHomeworkOffloading: Bool, requireAttemptFirst: Bool, hideFinishedAnswers: Bool = true, globalInstructions: [String]) {
        self.blockHomeworkOffloading = blockHomeworkOffloading
        self.requireAttemptFirst = requireAttemptFirst
        self.hideFinishedAnswers = hideFinishedAnswers
        self.globalInstructions = globalInstructions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        blockHomeworkOffloading = try c.decodeIfPresent(Bool.self, forKey: .blockHomeworkOffloading) ?? true
        requireAttemptFirst = try c.decodeIfPresent(Bool.self, forKey: .requireAttemptFirst) ?? true
        hideFinishedAnswers = try c.decodeIfPresent(Bool.self, forKey: .hideFinishedAnswers) ?? true
        globalInstructions = try c.decodeIfPresent([String].self, forKey: .globalInstructions) ?? []
    }
}

/// A parent-approved "Ask a parent" request: the site works normally until `until`.
struct TemporaryAllow: Codable, Equatable, Identifiable {
    var domain: String
    var until: Date
    var requestId: String?

    var id: String { domain }
}

struct KidPolicy: Codable, Equatable {
    var masterAIOff: Bool
    var categories: [String: CategoryState]
    var siteOverrides: [String: SiteOverride]
    var schedules: [AISchedule]
    var guidedRules: GuidedRules
    var temporaryAllows: [TemporaryAllow]
    /// Extra Guided instructions for one catalog app, keyed by app id.
    var appInstructions: [String: [String]]

    init(
        masterAIOff: Bool,
        categories: [String: CategoryState],
        siteOverrides: [String: SiteOverride],
        schedules: [AISchedule],
        guidedRules: GuidedRules,
        temporaryAllows: [TemporaryAllow] = [],
        appInstructions: [String: [String]] = [:]
    ) {
        self.masterAIOff = masterAIOff
        self.categories = categories
        self.siteOverrides = siteOverrides
        self.schedules = schedules
        self.guidedRules = guidedRules
        self.temporaryAllows = temporaryAllows
        self.appInstructions = appInstructions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        masterAIOff = try c.decodeIfPresent(Bool.self, forKey: .masterAIOff) ?? false
        categories = try c.decodeIfPresent([String: CategoryState].self, forKey: .categories) ?? [:]
        siteOverrides = try c.decodeIfPresent([String: SiteOverride].self, forKey: .siteOverrides) ?? [:]
        schedules = try c.decodeIfPresent([AISchedule].self, forKey: .schedules) ?? []
        guidedRules = try c.decodeIfPresent(GuidedRules.self, forKey: .guidedRules)
            ?? GuidedRules(blockHomeworkOffloading: true, requireAttemptFirst: true, globalInstructions: [])
        temporaryAllows = try c.decodeIfPresent([TemporaryAllow].self, forKey: .temporaryAllows) ?? []
        appInstructions = try c.decodeIfPresent([String: [String]].self, forKey: .appInstructions) ?? [:]
    }

    func activeTemporaryAllows(at date: Date = Date()) -> [TemporaryAllow] {
        temporaryAllows.filter { $0.until > date }
    }
}

/// Topics a parent always hears about when their kid asks an AI about them.
/// Mirrors `Backend/functions/src/safety.ts`. These never block anything.
struct SafetyTopic: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let urgent: Bool

    static let all: [SafetyTopic] = [
        SafetyTopic(id: "self_harm", name: "Self-harm or suicide", symbol: "heart.text.square.fill", urgent: true),
        SafetyTopic(id: "nicotine", name: "Vaping or smoking", symbol: "smoke.fill", urgent: false),
        SafetyTopic(id: "drugs_alcohol", name: "Drugs or alcohol", symbol: "pills.fill", urgent: false),
        SafetyTopic(id: "sexual", name: "Sexual content", symbol: "eye.slash.fill", urgent: false),
        SafetyTopic(id: "weapons_violence", name: "Weapons or violence", symbol: "exclamationmark.octagon.fill", urgent: false),
        SafetyTopic(id: "eating_disorders", name: "Eating disorders", symbol: "fork.knife", urgent: false),
        SafetyTopic(id: "dangerous_challenges", name: "Dangerous challenges", symbol: "flame.fill", urgent: false),
        SafetyTopic(id: "bypass_controls", name: "Getting around parental controls", symbol: "lock.open.fill", urgent: false),
    ]

    static func named(_ id: String?) -> SafetyTopic? {
        all.first { $0.id == id }
    }
}

struct Kid: Codable, Equatable, Identifiable {
    let id: String
    var name: String
    var pairingCode: String
    var paired: Bool
    var lastHeartbeat: Date?
    var policy: KidPolicy
    /// A download or heartbeat is not an acknowledgement that Safari installed these rules.
    var policyRevision: Int? = nil
    var appliedPolicyRevision: Int? = nil
    var policyAppliedAt: Date? = nil
}

enum PolicyDeliveryState: Equatable {
    case saving
    case waitingToRetry
    case needsAttention
    case saved
    case applied(Date?)
}

struct AICategory: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let supportsGuided: Bool
    let defaultState: CategoryState
    let domains: [String]
    /// nil from servers that predate app info.
    var catalogApps: [AIApp]? = nil

    enum CodingKeys: String, CodingKey {
        case id, name, description, icon, supportsGuided, defaultState, domains
        case catalogApps = "apps"
    }

    /// Every site as an app: catalog apps first, then any domain no app covers, named by its domain.
    var apps: [AIApp] {
        let known = catalogApps ?? []
        let covered = Set(known.flatMap(\.domains))
        return known + domains.filter { !covered.contains($0) }.map {
            AIApp(id: $0, name: $0, domains: [$0], audience: "", quirks: [])
        }
    }
}

/// One AI product inside a category, like ChatGPT (chatgpt.com + chat.openai.com).
struct AIApp: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let name: String
    let domains: [String]
    /// Who it's for, including its minimum age when known.
    let audience: String
    let quirks: [String]

    var primaryDomain: String { domains[0] }
}

struct AICatalog: Codable, Equatable {
    let version: Int
    let categories: [AICategory]

    func category(id: String?) -> AICategory? {
        categories.first { $0.id == id }
    }

    func app(id: String) -> (app: AIApp, category: AICategory)? {
        for category in categories {
            if let app = category.apps.first(where: { $0.id == id }) { return (app, category) }
        }
        return nil
    }

    func category(forDomain host: String) -> AICategory? {
        categories.first { category in
            category.domains.contains { host == $0 || host.hasSuffix("." + $0) }
        }
    }
}

struct ActivityEvent: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case blocked
        case guidedBlock = "guided_block"
        case guidedAllow = "guided_allow"
        case answerHidden = "answer_hidden"
        case safetyAlert = "safety_alert"
    }

    let id: String
    let type: Kind
    let domain: String?
    let categoryId: String?
    let reason: String?
    /// Safety alerts only.
    let topic: String?
    let severity: String?
    let excerpt: String?
    let at: Date

    var isUrgent: Bool { severity == "urgent" }
}

struct AccessRequest: Codable, Equatable, Identifiable {
    enum Status: String, Codable {
        case pending
        case approved
        case denied
    }

    enum Kind: String, Codable {
        /// Open a blocked site.
        case site
        /// Use a Guided chatbot without homework checks.
        case guided
    }

    let id: String
    let domain: String
    let categoryId: String?
    let kind: Kind
    let reason: String
    let minutes: Int
    let status: Status
    let createdAt: Date
    let until: Date?
}

struct KidActivity: Codable, Equatable {
    let lastHeartbeat: Date?
    let paired: Bool
    let counts: [String: Int]
    let events: [ActivityEvent]
    let requests: [AccessRequest]
    let policyRevision: Int?
    let appliedPolicyRevision: Int?
    let policyAppliedAt: Date?

    func count(_ kind: ActivityEvent.Kind) -> Int { counts[kind.rawValue] ?? 0 }

    var pendingRequests: [AccessRequest] { requests.filter { $0.status == .pending } }
    var safetyAlerts: [ActivityEvent] { events.filter { $0.type == .safetyAlert } }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastHeartbeat = try c.decodeIfPresent(Date.self, forKey: .lastHeartbeat)
        paired = try c.decode(Bool.self, forKey: .paired)
        counts = try c.decode([String: Int].self, forKey: .counts)
        events = try c.decode([ActivityEvent].self, forKey: .events)
        requests = try c.decodeIfPresent([AccessRequest].self, forKey: .requests) ?? []
        policyRevision = try c.decodeIfPresent(Int.self, forKey: .policyRevision)
        appliedPolicyRevision = try c.decodeIfPresent(Int.self, forKey: .appliedPolicyRevision)
        policyAppliedAt = try c.decodeIfPresent(Date.self, forKey: .policyAppliedAt)
    }
}

struct FamilySession: Codable, Equatable {
    let familyId: String
    let parentToken: String
}

/// Normalizes what a parent types ("https://www.Claude.ai/new") into a bare domain ("claude.ai").
enum DomainInput {
    static func normalize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let url = URL(string: s.contains("://") ? s : "https://\(s)"), let host = url.host {
            s = host
        }
        if s.hasPrefix("www.") { s.removeFirst(4) }
        let pattern = #"^(?!-)[a-z0-9-]+(\.[a-z0-9-]+)+$"#
        return s.range(of: pattern, options: .regularExpression) != nil ? s : nil
    }
}
