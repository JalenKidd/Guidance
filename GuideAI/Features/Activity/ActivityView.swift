import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var store: FamilyStore

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: GuideTheme.sectionSpacing) {
                    if let error = store.errorMessage {
                        ErrorBanner(message: error) { store.errorMessage = nil }
                    }
                    KidSelectorBar()
                    if !store.targetKids.isEmpty {
                        content(store.targetKids)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(GuideTheme.pageBackground.ignoresSafeArea())
            .refreshable { await refresh() }
            .task(id: store.selectedKidID) { await refresh() }
            .onDisappear {
                for kid in store.targetKids { store.markAlertsSeen(for: kid.id) }
            }
            .navigationTitle("Activity")
        }
    }

    private func refresh() async {
        for kid in store.targetKids { await store.refreshActivity(for: kid.id) }
    }

    /// One kid, or several merged (All kids). With several, rows are labeled with the kid's name.
    @ViewBuilder
    private func content(_ kids: [Kid]) -> some View {
        let labeled = kids.count > 1
        let loaded = kids.compactMap { store.activity[$0.id] }
        let pending = kids.flatMap { kid in (store.activity[kid.id]?.pendingRequests ?? []).map { (kid, $0) } }
        let approvals = kids.flatMap { kid in kid.policy.activeTemporaryAllows().map { (kid, $0) } }
        let unseen = Set(kids.flatMap { store.unseenAlerts(for: $0.id).map(\.id) })
        let alerts = kids
            .flatMap { kid in (store.activity[kid.id]?.safetyAlerts ?? []).map { (kid, $0) } }
            .sorted { $0.1.at > $1.1.at }
        let recent = kids
            .flatMap { kid in (store.activity[kid.id]?.events ?? []).filter { $0.type != .safetyAlert }.map { (kid, $0) } }
            .sorted { $0.1.at > $1.1.at }
            .prefix(100)

        if !pending.isEmpty {
            SectionLabel(title: labeled ? "Your kids are asking" : "\(kids[0].name) is asking")
            ForEach(pending, id: \.1.id) { kid, request in
                RequestCard(kid: kid, request: request, showsName: labeled)
            }
        }

        if !approvals.isEmpty {
            SectionLabel(title: "Approved for now")
            VStack(spacing: 0) {
                ForEach(approvals.indices, id: \.self) { index in
                    let (kid, allow) = approvals[index]
                    HStack {
                        Image(systemName: "clock.badge.checkmark.fill")
                            .foregroundStyle(GuideTheme.success)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(labeled ? "\(kid.name): \(allow.domain)" : allow.domain).font(.subheadline.weight(.semibold))
                            Text("Until \(allow.until.formatted(date: .omitted, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("End now") { store.endTemporaryAllow(allow, kidID: kid.id) }
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(12)
                }
            }
            .guideCard(padding: 4)
        }

        if !alerts.isEmpty {
            SectionLabel(title: "Safety alerts")
            VStack(spacing: 0) {
                ForEach(alerts, id: \.1.id) { kid, alert in
                    SafetyAlertRow(alert: alert, isNew: unseen.contains(alert.id), kidName: labeled ? kid.name : nil)
                    if alert.id != alerts.last?.1.id { Divider().padding(.leading, 46) }
                }
            }
            .guideCard(padding: 6)
            Text("Guidance doesn't block these questions. Curiosity is normal, and these alerts are a prompt for a conversation.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }

        ForEach(kids) { kid in
            ProtectionCard(kid: kid, activity: store.activity[kid.id], showsName: labeled)
        }

        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            metric("Sites blocked", total(loaded, .blocked), "nosign")
            metric("Prompts stopped", total(loaded, .guidedBlock), "hand.raised.fill")
            metric("Answers hidden", total(loaded, .answerHidden), "eye.slash.fill")
            metric("Guided prompts", total(loaded, .guidedAllow), "graduationcap.fill")
        }

        SectionLabel(title: "Recent")
        if !recent.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(recent), id: \.1.id) { kid, event in
                    EventRow(event: event, catalog: store.catalog, kidName: labeled ? kid.name : nil)
                    if event.id != recent.last?.1.id { Divider().padding(.leading, 46) }
                }
            }
            .guideCard(padding: 6)
        } else {
            Text(loaded.isEmpty ? "Loading…" : "Nothing yet. Blocked sites and checked prompts show up here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .guideCard()
        }

        Text("Guidance shows what was blocked or checked, not full conversations. Safety alerts include the message that triggered them.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    private func total(_ activities: [KidActivity], _ kind: ActivityEvent.Kind) -> Int? {
        activities.isEmpty ? nil : activities.reduce(0) { $0 + $1.count(kind) }
    }

    private func metric(_ title: String, _ value: Int?, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(GuideTheme.brand)
            Text(value.map(String.init) ?? "–")
                .font(GuideTheme.metricFont)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .guideCard(padding: 14)
    }
}

private struct RequestCard: View {
    @EnvironmentObject private var store: FamilyStore
    let kid: Kid
    let request: AccessRequest
    var showsName = false
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "hand.wave.fill")
                    .font(.title3)
                    .foregroundStyle(GuideTheme.warmAccent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text("For \(request.minutes) min · \(request.createdAt.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("“\(request.reason)”")
                .font(.body)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GuideTheme.brandSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 10) {
                Menu {
                    ForEach([15, 30, 60, 120], id: \.self) { minutes in
                        Button("\(minutes < 60 ? "\(minutes) minutes" : "\(minutes / 60) hour\(minutes == 60 ? "" : "s")")") {
                            decide(approve: true, minutes: minutes)
                        }
                    }
                } label: {
                    Text("Approve")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .foregroundStyle(.white)
                        .background(GuideTheme.success, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } primaryAction: {
                    decide(approve: true, minutes: request.minutes)
                }

                Button {
                    decide(approve: false, minutes: nil)
                } label: {
                    Text("Not now")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(GuideTheme.tertiaryFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .disabled(working)

            Text("Tap Approve for \(request.minutes) min, or hold it to pick a different length.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .guideCard()
    }

    private var title: String {
        let who = showsName ? kid.name : "Wants"
        switch request.kind {
        case .site: return showsName ? "\(who) wants to use \(request.domain)" : "Wants to use \(request.domain)"
        case .guided: return showsName ? "\(who) wants \(request.domain) without homework checks" : "Wants \(request.domain) without homework checks"
        }
    }

    private func decide(approve: Bool, minutes: Int?) {
        working = true
        Task {
            await store.decide(request, approve: approve, minutes: minutes, kidID: kid.id)
            working = false
        }
    }
}

private struct SafetyAlertRow: View {
    let alert: ActivityEvent
    let isNew: Bool
    var kidName: String?

    var body: some View {
        let topic = SafetyTopic.named(alert.topic)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: topic?.symbol ?? "exclamationmark.triangle.fill")
                .foregroundStyle(alert.isUrgent ? Color.red : GuideTheme.warmAccent)
                .frame(width: 28, height: 28)
                .background((alert.isUrgent ? Color.red : GuideTheme.warmAccent).opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text((kidName.map { "\($0): " } ?? "") + (topic?.name ?? "Safety topic"))
                        .font(.subheadline.weight(.semibold))
                    if alert.isUrgent {
                        Text("URGENT")
                            .font(.caption2.weight(.heavy))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    if isNew {
                        Circle().fill(GuideTheme.brand).frame(width: 8, height: 8)
                            .accessibilityLabel("New")
                    }
                }
                if let excerpt = alert.excerpt {
                    Text("“\(excerpt)”")
                        .font(.subheadline)
                }
                Text("\(alert.domain ?? "AI chatbot") · \(alert.at.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if alert.isUrgent {
                    Text("If you think your kid is in danger, call or text 988 (Suicide & Crisis Lifeline) for advice on what to do next, or 911 in an emergency.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
    }
}

private struct ProtectionCard: View {
    let kid: Kid
    let activity: KidActivity?
    var showsName = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .guideCard()
    }

    private var paired: Bool { activity?.paired ?? kid.paired }
    private var lastSeen: Date? { activity?.lastHeartbeat ?? kid.lastHeartbeat }
    private var stale: Bool {
        guard let lastSeen else { return true }
        return Date().timeIntervalSince(lastSeen) > 24 * 60 * 60
    }

    private var symbol: String {
        !paired ? "link.badge.plus" : stale ? "exclamationmark.shield.fill" : "checkmark.shield.fill"
    }

    private var color: Color {
        !paired ? .secondary : stale ? .orange : GuideTheme.success
    }

    private var title: String {
        if !paired { return showsName ? "\(kid.name): extension not paired" : "Safari extension not paired" }
        if stale { return "Haven't heard from \(kid.name)'s Safari lately" }
        return showsName ? "\(kid.name): protection on" : "Protection on"
    }

    private var detail: String {
        if !paired { return "Finish the steps in Setup on \(kid.name)'s phone." }
        let seen = "Last check-in \(TimeText.relative(lastSeen))."
        return stale ? "\(seen) The extension may be turned off in Settings → Apps → Safari → Extensions." : seen
    }
}

private struct EventRow: View {
    let event: ActivityEvent
    let catalog: AICatalog?
    var kidName: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text((kidName.map { "\($0): " } ?? "") + title).font(.subheadline.weight(.semibold))
                if let reason = event.reason {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                }
                Text(event.at.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(10)
    }

    private var site: String { event.domain ?? "a site" }
    private var categoryName: String? { catalog?.category(id: event.categoryId)?.name }

    private var title: String {
        switch event.type {
        case .blocked: return "Blocked \(site)" + (categoryName.map { " · \($0)" } ?? "")
        case .guidedBlock: return "Stopped a homework prompt on \(site)"
        case .guidedAllow: return "Guided prompt on \(site)"
        case .answerHidden: return "Hid a finished answer on \(site)"
        case .safetyAlert: return "Safety alert on \(site)"
        }
    }

    private var symbol: String {
        switch event.type {
        case .blocked: return "nosign"
        case .guidedBlock: return "hand.raised.fill"
        case .guidedAllow: return "graduationcap.fill"
        case .answerHidden: return "eye.slash.fill"
        case .safetyAlert: return "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch event.type {
        case .blocked: return GuideTheme.brand
        case .guidedBlock, .answerHidden: return GuideTheme.warmAccent
        case .guidedAllow: return GuideTheme.success
        case .safetyAlert: return .red
        }
    }
}
