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

// These exercise the actual URLSession client: the save queue must survive an
// unavailable server and slow responses without letting an older rule win.
@MainActor
final class FamilyStoreDeliveryTests: XCTestCase {
    func testTransientFailureRetriesAutomaticallyWithoutReopening() async throws {
        let context = try DeliveryTestContext()
        let store = context.makeStore(retryBaseDelay: 0.01)
        defer { store.signOut(); context.cleanUp() }
        context.transport.respond { request, complete in
            if context.transport.requests.count == 1 {
                complete(.failure(URLError(.notConnectedToInternet)))
            } else {
                complete(.success(try! deliveryKidData(policy: deliveryRequestPolicy(request), revision: 2)))
            }
        }
        store.updatePolicy(for: "k1") { $0.masterAIOff = true }

        let saved = await eventually { store.kids[0].policyRevision == 2 && store.deliveryState(for: store.kids[0]) == .saved }

        XCTAssertTrue(saved)
        XCTAssertEqual(context.transport.requests.count, 2)
        XCTAssertEqual(try deliveryChangeID(XCTUnwrap(context.transport.requests.first)),
                       try deliveryChangeID(XCTUnwrap(context.transport.requests.last)))
    }

    func testPermanentFailureStopsAutomaticRetryAndCanBeRetriedManually() async throws {
        let context = try DeliveryTestContext()
        let store = context.makeStore(retryBaseDelay: 0.01)
        defer { store.signOut(); context.cleanUp() }
        context.transport.respond { request, complete in
            if context.transport.requests.count == 1 {
                complete(.failure(DeliveryHTTPFailure(status: 400)))
            } else {
                complete(.success(try! deliveryKidData(policy: deliveryRequestPolicy(request), revision: 2)))
            }
        }
        store.updatePolicy(for: "k1") { $0.masterAIOff = true }
        let needsAttention = await eventually { store.deliveryState(for: store.kids[0]) == .needsAttention }
        XCTAssertTrue(needsAttention)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(context.transport.requests.count, 1)

        store.retryPolicy(for: "k1")

        let saved = await eventually { store.kids[0].policyRevision == 2 && store.deliveryState(for: store.kids[0]) == .saved }
        XCTAssertTrue(saved)
        XCTAssertEqual(context.transport.requests.count, 2)
        XCTAssertEqual(try deliveryChangeID(XCTUnwrap(context.transport.requests.first)),
                       try deliveryChangeID(XCTUnwrap(context.transport.requests.last)))
    }

    func testFailedSaveRestoresQueueAndRetriesTheSameChangeID() async throws {
        let context = try DeliveryTestContext()
        let first = context.makeStore(retryBaseDelay: 3_600)
        var restored: FamilyStore?
        defer {
            first.signOut()
            restored?.signOut()
            context.cleanUp()
        }
        context.transport.respond { request, complete in
            if context.transport.requests.count == 1 {
                complete(.failure(URLError(.networkConnectionLost)))
            } else {
                complete(.success(try! deliveryKidData(policy: deliveryRequestPolicy(request), revision: 2)))
            }
        }

        first.updatePolicy(for: "k1") { $0.masterAIOff = true }
        let waiting = await eventually {
            if case .waitingToRetry = first.deliveryState(for: first.kids[0]) { return true }
            return false
        }
        XCTAssertTrue(waiting)
        let originalRequest = try XCTUnwrap(context.transport.requests.first)
        let originalChangeID = try deliveryChangeID(originalRequest)
        XCTAssertFalse(originalChangeID.isEmpty)

        // A new store represents reopening the app. The first store's long
        // retry delay keeps this test independent of timing and connectivity.
        restored = context.makeStore(retryBaseDelay: 3_600)
        let resumed = try XCTUnwrap(restored)
        let saved = await eventually {
            if case .saved = resumed.deliveryState(for: resumed.kids[0]) { return true }
            return false
        }
        XCTAssertTrue(saved)
        XCTAssertEqual(context.transport.requests.count, 2)
        XCTAssertEqual(try deliveryChangeID(XCTUnwrap(context.transport.requests.last)), originalChangeID)
        XCTAssertTrue(resumed.kids[0].policy.masterAIOff)
        XCTAssertEqual(resumed.kids[0].policyRevision, 2)
    }

    func testRefreshKeepsAnUnsavedLocalPolicy() async throws {
        let context = try DeliveryTestContext()
        let store = context.makeStore(saveDebounce: .seconds(3_600))
        defer { store.signOut(); context.cleanUp() }
        context.transport.respond { request, complete in
            if request.url?.path == "/catalog" {
                complete(.success(try! deliveryJSON(catalog)))
            } else if request.url?.path.hasSuffix("/activity") == true {
                complete(.success(deliveryActivityData(revision: 1)))
            } else {
                complete(.success(try! deliveryFamilyData(kid: deliveryKidData())))
            }
        }
        store.updatePolicy(for: "k1") { $0.masterAIOff = true }

        await store.refresh()

        XCTAssertTrue(store.kids[0].policy.masterAIOff)
        if case .saving = store.deliveryState(for: store.kids[0]) {} else {
            XCTFail("Refreshing an older server snapshot must leave the local edit queued")
        }
        XCTAssertFalse(context.transport.requests.contains { $0.httpMethod == "PUT" })
    }

    func testNewEditWaitsForEarlierSaveAndSurvivesItsResponse() async throws {
        let context = try DeliveryTestContext()
        let store = context.makeStore()
        let firstSave = expectation(description: "first save started")
        let firstReply = DeliveryReplyBox()
        defer { store.signOut(); context.cleanUp() }
        context.transport.respond { request, complete in
            if context.transport.requests.count == 1 {
                firstReply.store(complete)
                firstSave.fulfill()
            } else {
                complete(.success(try! deliveryKidData(policy: deliveryRequestPolicy(request), revision: 3)))
            }
        }
        store.updatePolicy(for: "k1") { $0.masterAIOff = true }
        await fulfillment(of: [firstSave], timeout: 3)
        store.updatePolicy(for: "k1") { $0.categories["essay"] = .allow }
        XCTAssertEqual(context.transport.requests.count, 1, "A second save must not race the in-flight save")
        let firstRequest = try XCTUnwrap(context.transport.requests.first)
        firstReply.complete(.success(try deliveryKidData(policy: deliveryRequestPolicy(firstRequest), revision: 2)))

        let saved = await eventually {
            if case .saved = store.deliveryState(for: store.kids[0]) { return true }
            return false
        }
        XCTAssertTrue(saved)
        XCTAssertEqual(context.transport.requests.count, 2)
        XCTAssertTrue(store.kids[0].policy.masterAIOff)
        XCTAssertEqual(store.kids[0].policy.categories["essay"], .allow)
        let secondRequest = try XCTUnwrap(context.transport.requests.last)
        XCTAssertEqual(try deliveryRequestPolicy(secondRequest).categories["essay"], .allow)
        XCTAssertNotEqual(try deliveryChangeID(firstRequest), try deliveryChangeID(secondRequest))
    }

    func testSignOutIgnoresDelayedFamilyResponse() async throws {
        let context = try DeliveryTestContext()
        let store = context.makeStore()
        let familyStarted = expectation(description: "family refresh started")
        let delayed = DeliveryReplyBox()
        defer { store.signOut(); context.cleanUp() }
        context.transport.respond { request, complete in
            if request.url?.path == "/catalog" {
                complete(.success(try! deliveryJSON(catalog)))
            } else {
                delayed.store(complete)
                familyStarted.fulfill()
            }
        }
        let refresh = Task { await store.refresh() }
        await fulfillment(of: [familyStarted], timeout: 3)

        store.signOut()
        delayed.complete(.success(try deliveryFamilyData(kid: deliveryKidData())))
        await refresh.value

        XCTAssertNil(store.session)
        XCTAssertTrue(store.kids.isEmpty)
        XCTAssertTrue(store.activity.isEmpty)
    }

    func testDelayedApprovalSurvivesAConcurrentSaveThatAlreadyFinished() async throws {
        let context = try DeliveryTestContext()
        let store = context.makeStore()
        let decisionStarted = expectation(description: "approval started")
        let decisionReply = DeliveryReplyBox()
        let request = AccessRequest(id: "r1", domain: "quillbot.com", categoryId: "essay", kind: .site,
                                    reason: "Check a citation", minutes: 30, status: .pending,
                                    createdAt: Date(), until: nil)
        let allowance = TemporaryAllow(domain: request.domain, until: Date().addingTimeInterval(1_800), requestId: request.id)
        defer { store.signOut(); context.cleanUp() }
        context.transport.respond { outgoing, complete in
            if outgoing.httpMethod == "POST" {
                decisionReply.store(complete)
                decisionStarted.fulfill()
            } else if outgoing.httpMethod == "PUT" {
                let saves = context.transport.requests.filter { $0.httpMethod == "PUT" }.count
                complete(.success(try! deliveryKidData(policy: deliveryRequestPolicy(outgoing), revision: saves == 1 ? 3 : 4)))
            } else {
                complete(.success(deliveryActivityData(revision: 4)))
            }
        }
        let decision = Task { await store.decide(request, approve: true, minutes: 30, kidID: "k1") }
        await fulfillment(of: [decisionStarted], timeout: 3)

        // The server approved revision 2, but its response is delayed. A newer
        // rule edit finishes first, based on the old policy without that allow.
        store.updatePolicy(for: "k1") { $0.masterAIOff = true }
        let firstSaved = await eventually {
            store.kids[0].policyRevision == 3 && store.deliveryState(for: store.kids[0]) == .saved
        }
        XCTAssertTrue(firstSaved)
        XCTAssertTrue(store.kids[0].policy.temporaryAllows.isEmpty)
        var approvedPolicy = policy()
        approvedPolicy.temporaryAllows = [allowance]
        let result: [String: Any] = [
            "request": try JSONSerialization.jsonObject(with: deliveryJSON(request)),
            "kid": try JSONSerialization.jsonObject(with: deliveryKidData(policy: approvedPolicy, revision: 2)),
        ]
        decisionReply.complete(.success(try JSONSerialization.data(withJSONObject: result)))
        await decision.value

        let approvalSaved = await eventually {
            store.kids[0].policyRevision == 4 && store.deliveryState(for: store.kids[0]) == .saved
        }
        XCTAssertTrue(approvalSaved)
        XCTAssertTrue(store.kids[0].policy.masterAIOff)
        XCTAssertEqual(store.kids[0].policy.temporaryAllows.first?.requestId, request.id)
        XCTAssertEqual(context.transport.requests.filter { $0.httpMethod == "PUT" }.count, 2)
    }

    func testAppliedRequiresMatchingRevisionAndNoPendingEdit() async throws {
        let appliedAt = "2026-10-24T13:00:00.000Z"
        let context = try DeliveryTestContext(kid: deliveryKidData(revision: 3, appliedRevision: 2, appliedAt: appliedAt))
        let store = context.makeStore(saveDebounce: .seconds(3_600))
        defer { store.signOut(); context.cleanUp() }
        if case .saved = store.deliveryState(for: store.kids[0]) {} else {
            XCTFail("An older device receipt must not confirm the current rules")
        }
        context.transport.respond { _, complete in
            complete(.success(deliveryActivityData(revision: 3, appliedRevision: 3, appliedAt: appliedAt)))
        }

        await store.refreshActivity(for: "k1")

        if case .applied(let date) = store.deliveryState(for: store.kids[0]) {
            XCTAssertNotNil(date)
        } else {
            XCTFail("A matching activity receipt must advance Saved to Applied")
        }
        store.updatePolicy(for: "k1") { $0.masterAIOff = true }
        if case .saving = store.deliveryState(for: store.kids[0]) {} else {
            XCTFail("A local edit must immediately stop displaying the previous Applied receipt")
        }
    }

    private func eventually(_ predicate: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return predicate()
    }
}

private typealias DeliveryCompletion = (Result<Data, Error>) -> Void

private struct DeliveryHTTPFailure: Error { let status: Int }

private final class DeliveryReplyBox {
    private let lock = NSLock()
    private var reply: DeliveryCompletion?

    func store(_ reply: @escaping DeliveryCompletion) {
        lock.lock()
        self.reply = reply
        lock.unlock()
    }

    func complete(_ result: Result<Data, Error>) {
        lock.lock()
        let reply = self.reply
        self.reply = nil
        lock.unlock()
        reply?(result)
    }
}

private final class DeliveryTestTransport {
    let baseURL = URL(string: "https://guidance-delivery-\(UUID().uuidString.lowercased()).invalid")!
    let session: URLSession
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private var handler: ((URLRequest, @escaping DeliveryCompletion) -> Void)?

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DeliveryURLProtocol.self]
        session = URLSession(configuration: configuration)
        DeliveryURLProtocol.register(host: baseURL.host!) { [weak self] request, complete in
            guard let self else { complete(.failure(URLError(.cancelled))); return }
            lock.lock()
            recorded.append(request)
            let currentHandler = handler
            lock.unlock()
            guard let currentHandler else { complete(.failure(URLError(.badServerResponse))); return }
            currentHandler(request, complete)
        }
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func respond(_ handler: @escaping (URLRequest, @escaping DeliveryCompletion) -> Void) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func cleanUp() {
        session.invalidateAndCancel()
        DeliveryURLProtocol.unregister(host: baseURL.host!)
        lock.lock()
        handler = nil
        lock.unlock()
    }
}

private final class DeliveryURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var handlers: [String: (URLRequest, @escaping DeliveryCompletion) -> Void] = [:]

    static func register(host: String, handler: @escaping (URLRequest, @escaping DeliveryCompletion) -> Void) {
        lock.lock()
        handlers[host] = handler
        lock.unlock()
    }

    static func unregister(host: String) {
        lock.lock()
        handlers.removeValue(forKey: host)
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.hasPrefix("guidance-delivery-") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handlers[request.url?.host ?? ""]
        Self.lock.unlock()
        guard let handler else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        // URLSession can expose the body as a stream to a custom protocol.
        // Copy it into Data so tests inspect the exact API payload reliably.
        var captured = request
        if captured.httpBody == nil, let stream = captured.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var body = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4_096)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let count = stream.read(buffer, maxLength: 4_096)
                if count <= 0 { break }
                body.append(buffer, count: count)
            }
            captured.httpBody = body
        }
        handler(captured) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let data):
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                               headerFields: ["Content-Type": "application/json"])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            case .failure(let error):
                if let failure = error as? DeliveryHTTPFailure {
                    let response = HTTPURLResponse(url: request.url!, statusCode: failure.status,
                                                   httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                    client?.urlProtocol(self, didLoad: Data(#"{"error":"Invalid rules"}"#.utf8))
                    client?.urlProtocolDidFinishLoading(self)
                } else {
                    client?.urlProtocol(self, didFailWithError: error)
                }
            }
        }
    }

    override func stopLoading() {}
}

@MainActor
private final class DeliveryTestContext {
    let suite = "guidance-delivery-tests-\(UUID().uuidString)"
    let defaults: UserDefaults
    let transport = DeliveryTestTransport()

    init(kid: Data? = nil) throws {
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(try deliveryJSON(FamilySession(familyId: "f1", parentToken: "parent-token")), forKey: "guidance.session")
        let savedKid = try GuidanceAPI.decoder.decode(Kid.self, from: kid ?? deliveryKidData())
        defaults.set(try deliveryJSON([savedKid]), forKey: "guidance.cachedKids")
        defaults.set("k1", forKey: "guidance.selectedKid")
    }

    func makeStore(saveDebounce: Duration = .zero, retryBaseDelay: TimeInterval = 2) -> FamilyStore {
        FamilyStore(defaults: defaults, api: GuidanceAPI(baseURL: transport.baseURL, session: transport.session),
                    saveDebounce: saveDebounce, retryBaseDelay: retryBaseDelay)
    }

    func cleanUp() {
        transport.cleanUp()
        defaults.removePersistentDomain(forName: suite)
    }
}

private func deliveryJSON(_ value: some Encodable) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(value)
}

private func deliveryKidData(policy savedPolicy: KidPolicy = policy(), revision: Int? = 1,
                             appliedRevision: Int? = nil, appliedAt: String? = nil) throws -> Data {
    var object: [String: Any] = [
        "id": "k1", "name": "Maya", "pairingCode": "ABC234", "paired": true,
        "policy": try JSONSerialization.jsonObject(with: deliveryJSON(savedPolicy)),
    ]
    object["policyRevision"] = revision
    object["appliedPolicyRevision"] = appliedRevision
    object["policyAppliedAt"] = appliedAt
    return try JSONSerialization.data(withJSONObject: object)
}

private func deliveryFamilyData(kid: Data) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["familyId": "f1", "parentName": "Parent",
                                               "kids": [JSONSerialization.jsonObject(with: kid)]])
}

private func deliveryActivityData(revision: Int, appliedRevision: Int? = nil, appliedAt: String? = nil) -> Data {
    var object: [String: Any] = ["paired": true, "counts": [String: Int](), "events": [Any](),
                               "requests": [Any](), "policyRevision": revision]
    object["appliedPolicyRevision"] = appliedRevision
    object["policyAppliedAt"] = appliedAt
    return try! JSONSerialization.data(withJSONObject: object)
}

private func deliveryRequestPolicy(_ request: URLRequest) throws -> KidPolicy {
    try GuidanceAPI.decoder.decode(KidPolicy.self, from: XCTUnwrap(request.httpBody))
}

private func deliveryChangeID(_ request: URLRequest) throws -> String {
    let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
    return try XCTUnwrap(body?["changeId"] as? String)
}

final class CatalogAppTests: XCTestCase {
    func testAppsDecodeAndLeftoverDomainsBecomeTiles() throws {
        let json = """
        {"id":"chatbots","name":"Chatbots","description":"","icon":"","supportsGuided":true,"defaultState":"guided",
         "domains":["chatgpt.com","chat.openai.com","pi.ai"],
         "apps":[{"id":"chatgpt","name":"ChatGPT","domains":["chatgpt.com","chat.openai.com"],"audience":"13+","quirks":["Memory"]}]}
        """
        let category = try JSONDecoder().decode(AICategory.self, from: Data(json.utf8))
        XCTAssertEqual(category.apps.map(\.id), ["chatgpt", "pi.ai"])
        XCTAssertEqual(category.apps[0].primaryDomain, "chatgpt.com")
    }

    func testOlderCatalogWithoutAppsShowsEveryDomain() {
        XCTAssertEqual(catalog.categories[0].apps.map(\.name), ["chatgpt.com"])
    }

    func testPolicyDecodesGuidedOverridesAndAppInstructions() throws {
        let json = #"{"siteOverrides":{"claude.ai":"guided"},"appInstructions":{"chatgpt":["Only coding"]}}"#
        let policy = try JSONDecoder().decode(KidPolicy.self, from: Data(json.utf8))
        XCTAssertEqual(policy.siteOverrides["claude.ai"], .guided)
        XCTAssertEqual(policy.appInstructions["chatgpt"], ["Only coding"])
        XCTAssertEqual(try JSONDecoder().decode(KidPolicy.self, from: Data("{}".utf8)).appInstructions, [:])
    }
}
