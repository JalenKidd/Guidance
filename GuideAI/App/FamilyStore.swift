import Foundation
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
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?
    @Published var isUnlocked = false

    private let logger = Logger(subsystem: AppConfig.bundleIdentifier, category: "FamilyStore")
    private let defaults: UserDefaults
    private var pendingSaves: [String: Task<Void, Never>] = [:]

    private enum Key {
        static let session = "guidance.session"
        static let kids = "guidance.cachedKids"
        static let catalog = "guidance.cachedCatalog"
        static let selectedKid = "guidance.selectedKid"
        static let parentName = "guidance.parentName"
        static let alertsSeen = "guidance.alertsSeenAt"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        session = load(FamilySession.self, Key.session)
        kids = load([Kid].self, Key.kids) ?? []
        catalog = load(AICatalog.self, Key.catalog)
        parentName = defaults.string(forKey: Key.parentName)
        selectedKidID = defaults.string(forKey: Key.selectedKid) ?? kids.first?.id
    }

    var api: GuidanceAPI { GuidanceAPI() }

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
        isLoading = true
        defer { isLoading = false }
        do {
            let fresh = try await api.catalog()
            catalog = fresh
            save(fresh, Key.catalog)

            guard let session else { return }
            let family = try await api.family(session)
            apply(kids: family.kids)
            applyParentName(family.parentName)
            if let kid = selectedKid {
                await refreshActivity(for: kid.id)
            }
            errorMessage = nil
        } catch let error as GuidanceAPIError where error.isUnauthorized {
            errorMessage = "This family was removed from the server. Set up Guidance again in Setup."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshActivity(for kidID: String) async {
        guard let session else { return }
        do {
            activity[kidID] = try await api.activity(kidID: kidID, session: session)
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
        for kid in kids {
            await refreshActivity(for: kid.id)
        }
    }

    func decide(_ request: AccessRequest, approve: Bool, minutes: Int? = nil, kidID: String) async {
        guard let session else { return }
        do {
            let result = try await api.decideRequest(request.id, approve: approve, minutes: minutes, kidID: kidID, session: session)
            if let index = kids.firstIndex(where: { $0.id == kidID }) {
                kids[index] = result.kid
                save(kids, Key.kids)
            }
            await refreshActivity(for: kidID)
            errorMessage = nil
        } catch {
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
        session = nil
        applyParentName(nil)
        kids = []
        activity = [:]
        selectedKidID = nil
        isUnlocked = false
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

    /// Change a kid's rules. The UI updates immediately; the save is debounced so
    /// flicking through category settings sends one request.
    func updatePolicy(for kidID: String, _ change: (inout KidPolicy) -> Void) {
        guard let index = kids.firstIndex(where: { $0.id == kidID }) else { return }
        var policy = kids[index].policy
        change(&policy)
        guard policy != kids[index].policy else { return }
        kids[index].policy = policy
        save(kids, Key.kids)

        pendingSaves[kidID]?.cancel()
        pendingSaves[kidID] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await self?.pushPolicy(for: kidID)
        }
    }

    private func pushPolicy(for kidID: String) async {
        guard let session, let kid = kids.first(where: { $0.id == kidID }) else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let saved = try await api.savePolicy(kid.policy, kidID: kidID, session: session)
            // Only take the server copy if nothing changed locally while saving.
            if let index = kids.firstIndex(where: { $0.id == kidID }), kids[index].policy == kid.policy {
                kids[index] = saved
                save(kids, Key.kids)
            }
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't save rules: \(error.localizedDescription)"
        }
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
        kids = newKids
        save(newKids, Key.kids)
        let keepsAll = selectedKidID == Self.allKidsID && newKids.count > 1
        if !keepsAll && (selectedKidID == nil || !newKids.contains(where: { $0.id == selectedKidID })) {
            select(newKids.first?.id)
        }
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
