import Foundation
import Combine
import os

/// Source of truth for the parent console. The server owns the data; this keeps
/// a cached copy so the app opens instantly and still shows rules when offline.
@MainActor
final class FamilyStore: ObservableObject {
    @Published private(set) var session: FamilySession?
    @Published private(set) var kids: [Kid] = []
    /// Shown to kids as "Guardian: <name>" in the Safari extension.
    @Published private(set) var parentName: String?
    @Published private(set) var catalog: AICatalog?
    @Published private(set) var activity: [String: KidActivity] = [:]
    @Published var selectedKidID: String?
    @Published private(set) var isLoading = false
    @Published private var savingKids: Set<String> = []
    @Published private var queuedPolicies: [String: PendingPolicySave] = [:]
    @Published var errorMessage: String?
    @Published var isUnlocked = false

    private let logger = Logger(subsystem: AppConfig.bundleIdentifier, category: "FamilyStore")
    private let defaults: UserDefaults
    private let apiOverride: GuidanceAPI?
    private let saveDebounce: Duration
    private let retryBaseDelay: TimeInterval
    private var pendingSaves: [String: Task<Void, Never>] = [:]
    private var workerIDs: [String: UUID] = [:]
    private var sessionGeneration = UUID()

    private struct PendingPolicySave: Codable {
        let familyId: String
        let serverURL: String
        let policy: KidPolicy
        let changeId: String
        var attempts = 0
        var error: String?
        var retryable = true
    }

    private enum Key {
        static let session = "guidance.session"
        static let kids = "guidance.cachedKids"
        static let catalog = "guidance.cachedCatalog"
        static let selectedKid = "guidance.selectedKid"
        static let parentName = "guidance.parentName"
        static let alertsSeen = "guidance.alertsSeenAt"
        static let pendingPolicies = "guidance.pendingPolicies"
    }

    init(defaults: UserDefaults = .standard, api: GuidanceAPI? = nil,
         saveDebounce: Duration = .milliseconds(500), retryBaseDelay: TimeInterval = 2) {
        self.defaults = defaults
        self.apiOverride = api
        self.saveDebounce = saveDebounce
        self.retryBaseDelay = retryBaseDelay
        session = load(FamilySession.self, Key.session)
        kids = load([Kid].self, Key.kids) ?? []
        catalog = load(AICatalog.self, Key.catalog)
        parentName = defaults.string(forKey: Key.parentName)
        selectedKidID = defaults.string(forKey: Key.selectedKid) ?? kids.first?.id
        queuedPolicies = load([String: PendingPolicySave].self, Key.pendingPolicies) ?? [:]
        for index in kids.indices {
            if let pending = pendingPolicy(for: kids[index].id) { kids[index].policy = pending.policy }
        }
        resumePendingSaves()
    }

    var api: GuidanceAPI { apiOverride ?? GuidanceAPI() }
    var isSaving: Bool { !savingKids.isEmpty }

    private var serverURL: String { api.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }

    private func pendingPolicy(for kidID: String) -> PendingPolicySave? {
        guard let pending = queuedPolicies[kidID], pending.familyId == session?.familyId,
              pending.serverURL == serverURL else { return nil }
        return pending
    }

    /// Selection value meaning "edit every kid at once".
    static let allKidsID = "all"

    var isAllKids: Bool {
        selectedKidID == Self.allKidsID && kids.count > 1
    }

    /// The kid whose details are shown. With All kids selected this is the first kid,
    /// so screens that need one kid still have one.
    var selectedKid: Kid? {
        kids.first { $0.id == selectedKidID } ?? kids.first
    }

    /// The kids a rule change applies to.
    var targetKids: [Kid] {
        if isAllKids { return kids }
        return selectedKid.map { [$0] } ?? []
    }

    /// "Jalen" or "all kids", for labels.
    var targetName: String {
        isAllKids ? "all kids" : (selectedKid?.name ?? "your kid")
    }

    /// The value when every target kid has the same one, otherwise nil (shown as "Mixed").
    func shared<T: Equatable>(_ value: (KidPolicy) -> T) -> T? {
        let values = targetKids.map { value($0.policy) }
        guard let first = values.first, values.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    // MARK: - Loading

    func refresh() async {
        let generation = sessionGeneration
        let activeSession = session
        let requestAPI = api
        let origin = serverURL
        resumePendingSaves()
        isLoading = true
        defer { if generation == sessionGeneration { isLoading = false } }
        do {
            let fresh = try await requestAPI.catalog()
            guard generation == sessionGeneration, session == activeSession, origin == serverURL else { return }
            catalog = fresh
            save(fresh, Key.catalog)

            guard let activeSession else { return }
            let family = try await requestAPI.family(activeSession)
            guard generation == sessionGeneration, session == activeSession, origin == serverURL else { return }
            apply(kids: family.kids)
            applyParentName(family.parentName)
            if let kid = selectedKid {
                await refreshActivity(for: kid.id)
            }
            errorMessage = nil
        } catch let error as GuidanceAPIError where error.isUnauthorized {
            guard generation == sessionGeneration, origin == serverURL else { return }
            errorMessage = "This family was removed from the server. Set up Guidance again in Setup."
        } catch {
            guard generation == sessionGeneration, origin == serverURL else { return }
            errorMessage = error.localizedDescription
        }
    }

    func refreshActivity(for kidID: String) async {
        guard let session else { return }
        let generation = sessionGeneration
        let requestAPI = api
        let origin = serverURL
        do {
            let fresh = try await requestAPI.activity(kidID: kidID, session: session)
            guard generation == sessionGeneration, self.session == session, origin == serverURL else { return }
            activity[kidID] = fresh
            if let index = kids.firstIndex(where: { $0.id == kidID }),
               fresh.policyRevision != nil, fresh.policyRevision == kids[index].policyRevision {
                kids[index].appliedPolicyRevision = fresh.appliedPolicyRevision
                kids[index].policyAppliedAt = fresh.policyAppliedAt
                save(kids, Key.kids)
            }
        } catch {
            logger.error("Activity refresh failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Requests and alerts

    /// Pending "Ask a parent" requests plus safety alerts the parent hasn't looked at, across all kids.
    var attentionCount: Int {
        kids.reduce(0) { total, kid in
            guard let activity = activity[kid.id] else { return total }
            return total + activity.pendingRequests.count + unseenAlerts(for: kid.id).count
        }
    }

    func unseenAlerts(for kidID: String) -> [ActivityEvent] {
        let seen = (defaults.dictionary(forKey: Key.alertsSeen)?[kidID] as? Double).map(Date.init(timeIntervalSince1970:)) ?? .distantPast
        return activity[kidID]?.safetyAlerts.filter { $0.at > seen } ?? []
    }

    func markAlertsSeen(for kidID: String) {
        guard !unseenAlerts(for: kidID).isEmpty else { return }
        var seen = defaults.dictionary(forKey: Key.alertsSeen) ?? [:]
        seen[kidID] = Date().timeIntervalSince1970
        defaults.set(seen, forKey: Key.alertsSeen)
        objectWillChange.send()
    }

    /// Refresh activity for every kid, so requests and alerts show up while the app is open.
    func refreshAllActivity() async {
        guard let session else { return }
        let generation = sessionGeneration
        let requestAPI = api
        let origin = serverURL
        resumePendingSaves()
        for kid in kids {
            await refreshActivity(for: kid.id)
            guard generation == sessionGeneration, origin == serverURL else { return }
        }
        // An approval or a second parent can change the server's policy while this app is open.
        if kids.contains(where: { (activity[$0.id]?.policyRevision ?? 0) > ($0.policyRevision ?? 0) }) {
            if let family = try? await requestAPI.family(session), generation == sessionGeneration,
               self.session == session, origin == serverURL {
                apply(kids: family.kids)
            }
        }
    }

    func decide(_ request: AccessRequest, approve: Bool, minutes: Int? = nil, kidID: String) async {
        guard let session else { return }
        let generation = sessionGeneration
        let requestAPI = api
        let origin = serverURL
        // An old queued full-policy save must not remove a newly approved exception.
        while pendingPolicy(for: kidID) != nil {
            if pendingPolicy(for: kidID)?.error != nil {
                errorMessage = "Save the waiting rule changes before answering this request."
                return
            }
            scheduleSave(for: kidID, after: .zero)
            await pendingSaves[kidID]?.value
            guard generation == sessionGeneration, origin == serverURL else { return }
        }
        do {
            let result = try await requestAPI.decideRequest(request.id, approve: approve, minutes: minutes, kidID: kidID, session: session)
            guard generation == sessionGeneration, self.session == session, origin == serverURL else { return }
            if let index = kids.firstIndex(where: { $0.id == kidID }) {
                kids[index] = merging(result.kid)
                save(kids, Key.kids)
            }
            if approve,
               let allowance = result.kid.policy.temporaryAllows.first(where: { $0.requestId == request.id }) {
                updatePolicy(for: kidID) { policy in
                    policy.temporaryAllows.removeAll { $0.domain == allowance.domain }
                    policy.temporaryAllows.append(allowance)
                }
            }
            await refreshActivity(for: kidID)
            errorMessage = nil
        } catch {
            guard generation == sessionGeneration, origin == serverURL else { return }
            errorMessage = error.localizedDescription
            await refreshActivity(for: kidID)
        }
    }

    /// Cancel an approval early.
    func endTemporaryAllow(_ allow: TemporaryAllow, kidID: String) {
        updatePolicy(for: kidID) { policy in
            policy.temporaryAllows.removeAll { $0.domain == allow.domain }
        }
    }

    // MARK: - Family setup

    func createFamily(parentName: String, firstKidName: String) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            let newSession = try await api.createFamily(parentName: parentName)
            stopSaveWorkers()
            applyParentName(parentName)
            session = newSession
            save(newSession, Key.session)
            if catalog == nil {
                let fresh = try await api.catalog()
                catalog = fresh
                save(fresh, Key.catalog)
            }
            let kid = try await api.addKid(named: firstKidName, session: newSession)
            apply(kids: [kid])
            select(kid.id)
            isUnlocked = true
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func addKid(named name: String) async {
        guard let session else { return }
        do {
            let kid = try await api.addKid(named: name, session: session)
            apply(kids: kids + [kid])
            select(kid.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeKid(_ kidID: String) async {
        guard let session else { return }
        do {
            try await api.removeKid(kidID, session: session)
            pendingSaves.removeValue(forKey: kidID)?.cancel()
            workerIDs.removeValue(forKey: kidID)
            savingKids.remove(kidID)
            queuedPolicies.removeValue(forKey: kidID)
            save(queuedPolicies, Key.pendingPolicies)
            apply(kids: kids.filter { $0.id != kidID })
            if selectedKidID == kidID { select(kids.first?.id) }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func setParentName(_ name: String) async -> Bool {
        guard let session else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed != parentName else { return true }
        do {
            let family = try await api.setParentName(String(trimmed.prefix(40)), session: session)
            applyParentName(family.parentName)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func applyParentName(_ name: String?) {
        parentName = name
        defaults.set(name, forKey: Key.parentName)
    }

    /// Demo sign-in with one of the accounts in `Backend/functions/src/accounts.ts`.
    func signIn(email: String, password: String) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await api.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            stopSaveWorkers()
            session = result.session
            save(result.session, Key.session)
            applyParentName(result.parentName)
            kids = []
            activity = [:]
            select(nil)
            isUnlocked = true
            errorMessage = nil
            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func renameKid(_ kidID: String, to name: String) async {
        guard let session else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = kids.firstIndex(where: { $0.id == kidID }), kids[index].name != trimmed else { return }
        do {
            let renamed = try await api.renameKid(kidID, to: String(trimmed.prefix(40)), session: session)
            if let i = kids.firstIndex(where: { $0.id == kidID }) {
                kids[i].name = renamed.name
                save(kids, Key.kids)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Forget this family on this device. The server copy stays.
    func signOut() {
        stopSaveWorkers()
        session = nil
        applyParentName(nil)
        kids = []
        activity = [:]
        selectedKidID = nil
        isUnlocked = false
        // Keep queued changes scoped to this family and server; signing back in can resume them.
        for key in [Key.session, Key.kids, Key.selectedKid] { defaults.removeObject(forKey: key) }
    }

    func select(_ kidID: String?) {
        selectedKidID = kidID
        defaults.set(kidID, forKey: Key.selectedKid)
    }

    // MARK: - Rules

    /// Change the rules of every target kid: the selected kid, or all kids.
    func updatePolicies(_ change: (inout KidPolicy) -> Void) {
        for kid in targetKids {
            updatePolicy(for: kid.id, change)
        }
    }

    /// Queue the latest edit durably before attempting a network save.
    func updatePolicy(for kidID: String, _ change: (inout KidPolicy) -> Void) {
        guard let session, let index = kids.firstIndex(where: { $0.id == kidID }) else { return }
        var policy = kids[index].policy
        change(&policy)
        guard policy != kids[index].policy else { return }
        queuedPolicies[kidID] = PendingPolicySave(familyId: session.familyId, serverURL: serverURL,
                                                  policy: policy, changeId: UUID().uuidString)
        // Write the queue first so a restart between writes cannot lose the edit.
        save(queuedPolicies, Key.pendingPolicies)
        kids[index].policy = policy
        save(kids, Key.kids)
        scheduleSave(for: kidID, after: saveDebounce)
    }

    func deliveryState(for kid: Kid) -> PolicyDeliveryState {
        if let pending = pendingPolicy(for: kid.id) {
            if savingKids.contains(kid.id) || pending.error == nil { return .saving }
            return pending.retryable ? .waitingToRetry : .needsAttention
        }
        // Activity polling can confirm delivery without requiring a pull-to-refresh.
        let latest = activity[kid.id]
        if let revision = kid.policyRevision {
            if latest?.policyRevision == revision {
                if latest?.appliedPolicyRevision == revision { return .applied(latest?.policyAppliedAt) }
                return .saved
            }
            if (latest?.policyRevision ?? 0) > revision { return .saved }
            if kid.appliedPolicyRevision == revision { return .applied(kid.policyAppliedAt) }
        }
        return .saved
    }

    func retryPolicy(for kidID: String) {
        guard var pending = pendingPolicy(for: kidID), !savingKids.contains(kidID) else { return }
        pending.error = nil
        pending.attempts = 0
        pending.retryable = true
        queuedPolicies[kidID] = pending
        save(queuedPolicies, Key.pendingPolicies)
        pendingSaves.removeValue(forKey: kidID)?.cancel()
        workerIDs.removeValue(forKey: kidID)
        scheduleSave(for: kidID, after: .zero)
    }

    private func resumePendingSaves() {
        for kid in kids {
            guard let pending = pendingPolicy(for: kid.id), pending.retryable else { continue }
            scheduleSave(for: kid.id, after: saveDebounce)
        }
    }

    /// One worker per kid: new edits replace the queued snapshot, never cancel a PUT in flight.
    private func scheduleSave(for kidID: String, after delay: Duration) {
        guard pendingSaves[kidID] == nil, pendingPolicy(for: kidID) != nil else { return }
        let workerID = UUID()
        let generation = sessionGeneration
        workerIDs[kidID] = workerID
        pendingSaves[kidID] = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch {
                self?.finishSaveWorker(for: kidID, workerID: workerID)
                return
            }
            guard !Task.isCancelled else {
                self?.finishSaveWorker(for: kidID, workerID: workerID)
                return
            }
            await self?.pushPolicy(for: kidID, workerID: workerID, generation: generation)
        }
    }

    private func pushPolicy(for kidID: String, workerID: UUID, generation: UUID) async {
        var nextDelay: Duration?
        defer { finishSaveWorker(for: kidID, workerID: workerID, nextDelay: nextDelay) }
        guard generation == sessionGeneration, workerIDs[kidID] == workerID,
              let session, let pending = pendingPolicy(for: kidID) else { return }
        let requestAPI = api
        let origin = serverURL
        savingKids.insert(kidID)
        do {
            let saved = try await requestAPI.savePolicy(pending.policy, kidID: kidID, session: session, changeId: pending.changeId)
            guard generation == sessionGeneration, self.session == session,
                  workerIDs[kidID] == workerID, origin == serverURL else { return }
            nextDelay = saveDebounce
            if pendingPolicy(for: kidID)?.changeId == pending.changeId {
                queuedPolicies.removeValue(forKey: kidID)
            }
            if let index = kids.firstIndex(where: { $0.id == kidID }) {
                kids[index] = merging(saved)
                save(kids, Key.kids)
            }
            // Cache the accepted revision before clearing the durable queue. If the
            // app stops between writes, replaying the same changeId is harmless.
            save(queuedPolicies, Key.pendingPolicies)
        } catch {
            guard generation == sessionGeneration, self.session == session,
                  workerIDs[kidID] == workerID, origin == serverURL else { return }
            nextDelay = saveDebounce
            if var latest = pendingPolicy(for: kidID), latest.changeId == pending.changeId {
                latest.attempts += 1
                latest.error = error.localizedDescription
                if case GuidanceAPIError.server(let status, _) = error {
                    latest.retryable = status >= 500 || status == 408 || status == 429
                } else {
                    latest.retryable = true
                }
                queuedPolicies[kidID] = latest
                save(queuedPolicies, Key.pendingPolicies)
                nextDelay = .seconds(min(30, retryBaseDelay * pow(2, Double(min(latest.attempts - 1, 5)))))
            }
        }
    }

    private func finishSaveWorker(for kidID: String, workerID: UUID, nextDelay: Duration? = nil) {
        guard workerIDs[kidID] == workerID else { return }
        savingKids.remove(kidID)
        pendingSaves.removeValue(forKey: kidID)
        workerIDs.removeValue(forKey: kidID)
        if let nextDelay, let pending = pendingPolicy(for: kidID), pending.retryable {
            scheduleSave(for: kidID, after: nextDelay)
        }
    }

    private func stopSaveWorkers() {
        sessionGeneration = UUID()
        for task in pendingSaves.values { task.cancel() }
        pendingSaves.removeAll()
        workerIDs.removeAll()
        savingKids.removeAll()
        isLoading = false
    }

    func suggestSite(domain: String, categoryID: String?, note: String?) async -> Bool {
        guard let session else { return false }
        do {
            try await api.suggestSite(domain: domain, categoryID: categoryID, note: note, session: session)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Cache

    private func apply(kids newKids: [Kid]) {
        kids = newKids.map(merging)
        save(kids, Key.kids)
        resumePendingSaves()
        let keepsAll = selectedKidID == Self.allKidsID && newKids.count > 1
        if !keepsAll && (selectedKidID == nil || !newKids.contains(where: { $0.id == selectedKidID })) {
            select(newKids.first?.id)
        }
    }

    /// Preserve local edits and newer save responses when a stale refresh finishes later.
    private func merging(_ serverKid: Kid) -> Kid {
        var merged = serverKid
        if let local = kids.first(where: { $0.id == serverKid.id }),
           (local.policyRevision ?? 0) > (serverKid.policyRevision ?? 0) {
            merged = local
        }
        if let pending = pendingPolicy(for: serverKid.id) { merged.policy = pending.policy }
        return merged
    }

    private func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? GuidanceAPI.decoder.decode(T.self, from: data)
    }

    private func save(_ value: some Encodable, _ key: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(value) { defaults.set(data, forKey: key) }
    }
}
