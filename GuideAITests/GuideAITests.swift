import XCTest
@testable import GuideAI

private let catalog = AICatalog(version: 1, categories: [
    AICategory(id: "chatbots", name: "Chatbots", description: "", icon: "", supportsGuided: true, defaultState: .guided, domains: ["chatgpt.com"]),
    AICategory(id: "essay", name: "Essay", description: "", icon: "", supportsGuided: false, defaultState: .block, domains: ["quillbot.com"]),
    AICategory(id: "math", name: "Math", description: "", icon: "", supportsGuided: false, defaultState: .block, domains: ["mathway.com"]),
])

private func policy(schedules: [AISchedule] = [], masterOff: Bool = false) -> KidPolicy {
    KidPolicy(
        masterAIOff: masterOff,
        categories: ["chatbots": .guided, "essay": .block, "math": .allow],
        siteOverrides: [:],
        schedules: schedules,
        guidedRules: GuidedRules(blockHomeworkOffloading: true, requireAttemptFirst: true, globalInstructions: [])
    )
}

/// 2026-10-21 is a Wednesday (JS weekday 3).
private func date(_ hhmm: String, day: Int = 21) -> Date {
    let minutes = PolicyResolver.minutes(hhmm)
    return Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: minutes / 60, minute: minutes % 60))!
}

final class PolicyResolverTests: XCTestCase {
    func testWeekdayMatchesJavaScript() {
        XCTAssertEqual(PolicyResolver.jsWeekday(date("12:00")), 3)
    }

    func testCategorySettingsApplyWithoutSchedules() {
        let rules = PolicyResolver.effective(policy(), catalog: catalog, at: date("12:00"))
        XCTAssertFalse(rules.masterOff)
        XCTAssertEqual(rules.states["essay"], .block)
        XCTAssertEqual(rules.states["math"], .allow)
    }

    func testScheduleOverridesInsideWindowOnly() {
        var schoolNights = AISchedule.schoolNightsPreset
        schoolNights.categories = ["math": .block]
        let p = policy(schedules: [schoolNights])
        XCTAssertEqual(PolicyResolver.effective(p, catalog: catalog, at: date("15:59")).states["math"], .allow)
        let inside = PolicyResolver.effective(p, catalog: catalog, at: date("16:00"))
        XCTAssertEqual(inside.states["math"], .block)
        XCTAssertEqual(inside.scheduledBy["math"], "School nights")
        // Friday isn't a school night.
        XCTAssertEqual(PolicyResolver.effective(p, catalog: catalog, at: date("17:00", day: 23)).states["math"], .allow)
    }

    func testOvernightBedtimeTurnsAIOff() {
        let p = policy(schedules: [AISchedule.bedtimePreset])
        XCTAssertFalse(PolicyResolver.effective(p, catalog: catalog, at: date("21:00")).masterOff)
        let late = PolicyResolver.effective(p, catalog: catalog, at: date("23:30"))
        XCTAssertTrue(late.masterOff)
        XCTAssertEqual(late.masterOffSchedule, "Bedtime")
        XCTAssertTrue(PolicyResolver.effective(p, catalog: catalog, at: date("06:59", day: 22)).masterOff)
        XCTAssertFalse(PolicyResolver.effective(p, catalog: catalog, at: date("07:00", day: 22)).masterOff)
    }

    func testStrictestOverlappingScheduleWins() {
        var loose = AISchedule.new(name: "Study hall")
        loose.categories = ["math": .allow]
        var strict = AISchedule.new(name: "Test week")
        strict.categories = ["math": .block]
        let rules = PolicyResolver.effective(policy(schedules: [loose, strict]), catalog: catalog, at: date("17:00"))
        XCTAssertEqual(rules.states["math"], .block)
        XCTAssertEqual(rules.scheduledBy["math"], "Test week")
    }
}

final class ModelCodingTests: XCTestCase {
    func testDecodesServerKid() throws {
        let json = """
        {"id":"k1","name":"Maya","pairingCode":"ABC234","paired":true,"lastHeartbeat":"2026-10-21T18:04:05.123Z",
         "policy":{"masterAIOff":false,"categories":{"essay":"block","chatbots":"guided"},"siteOverrides":{"claude.ai":"allow"},
         "schedules":[],"guidedRules":{"blockHomeworkOffloading":true,"requireAttemptFirst":false,"globalInstructions":["Be kind"]}}}
        """
        let kid = try GuidanceAPI.decoder.decode(Kid.self, from: Data(json.utf8))
        XCTAssertEqual(kid.policy.categories["essay"], .block)
        XCTAssertEqual(kid.policy.siteOverrides["claude.ai"], .allow)
        XCTAssertNotNil(kid.lastHeartbeat)
    }

    func testOlderSavedPolicyGetsDefaultsForNewFields() throws {
        let json = #"{"masterAIOff":false,"categories":{},"siteOverrides":{},"schedules":[],"guidedRules":{"blockHomeworkOffloading":true,"requireAttemptFirst":true,"globalInstructions":[]}}"#
        let policy = try GuidanceAPI.decoder.decode(KidPolicy.self, from: Data(json.utf8))
        XCTAssertTrue(policy.guidedRules.hideFinishedAnswers)
        XCTAssertEqual(policy.temporaryAllows, [])
    }

    func testDecodesActivityWithRequestsAndAlerts() throws {
        let json = """
        {"lastHeartbeat":null,"paired":true,"counts":{"safety_alert":1},
         "events":[{"id":"e1","type":"safety_alert","domain":"chatgpt.com","topic":"self_harm","severity":"urgent","excerpt":"i feel awful","at":"2026-10-21T18:04:05.123Z"}],
         "requests":[{"id":"r1","domain":"quillbot.com","kind":"site","reason":"citations","minutes":30,"status":"pending","createdAt":"2026-10-21T18:00:00.000Z"}]}
        """
        let activity = try GuidanceAPI.decoder.decode(KidActivity.self, from: Data(json.utf8))
        XCTAssertEqual(activity.safetyAlerts.first?.isUrgent, true)
        XCTAssertEqual(activity.pendingRequests.first?.reason, "citations")
    }

    func testOnlyUnexpiredApprovalsAreActive() {
        var p = policy()
        p.temporaryAllows = [
            TemporaryAllow(domain: "quillbot.com", until: date("12:30")),
            TemporaryAllow(domain: "mathway.com", until: date("11:00")),
        ]
        XCTAssertEqual(p.activeTemporaryAllows(at: date("12:00")).map(\.domain), ["quillbot.com"])
    }

    func testDomainInputNormalizes() {
        XCTAssertEqual(DomainInput.normalize("https://www.Claude.ai/new"), "claude.ai")
        XCTAssertEqual(DomainInput.normalize(" quillbot.com "), "quillbot.com")
        XCTAssertNil(DomainInput.normalize("not a site"))
    }
}
