import SwiftUI

struct RulesView: View {
    @EnvironmentObject private var store: FamilyStore

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: GuideTheme.sectionSpacing) {
                    TabHeader("Rules") {
                        if store.isSaving { ProgressView() }
                    }
                    KidSelectorBar()
                    if let kid = store.selectedKid, let catalog = store.catalog {
                        RulesContent(kid: kid, catalog: catalog)
                    } else if store.isLoading {
                        ProgressView().padding(.top, 60)
                    } else {
                        ErrorBanner(message: "Couldn't load the AI categories yet. Check the server address in Setup, then pull to refresh.")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(GuideTheme.pageBackground.ignoresSafeArea())
            .refreshable { await store.refresh() }
            .navigationTitle("Rules")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: CategoryRoute.self) { route in
                CategoryDetailView(categoryID: route.id)
            }
        }
    }
}

struct CategoryRoute: Hashable {
    let id: String
}

private struct RulesContent: View {
    @EnvironmentObject private var store: FamilyStore
    let kid: Kid
    let catalog: AICatalog

    var body: some View {
        let effective = PolicyResolver.effective(kid.policy, catalog: catalog)

        if store.parentName == nil {
            VStack(alignment: .leading, spacing: 8) {
                Label("What should \(store.isAllKids ? "your kids" : kid.name) call you?", systemImage: "person.crop.circle.badge.questionmark")
                    .font(.headline)
                Text("Shown as \"Guardian\" in the Guidance extension on \(store.isAllKids ? "their phones" : "\(kid.name)'s phone").")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                GuardianNameField()
                    .padding(10)
                    .background(GuideTheme.tertiaryFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .guideCard()
        }

        MasterSwitchCard(kid: kid, effective: effective)

        if !store.isAllKids && !effective.activeScheduleNames.isEmpty {
            activeScheduleBanner(effective)
        }

        ForEach(store.targetKids) { target in
            ForEach(target.policy.activeTemporaryAllows()) { allow in
                HStack(spacing: 10) {
                    Image(systemName: "clock.badge.checkmark.fill")
                        .foregroundStyle(GuideTheme.success)
                    Text("\(store.isAllKids ? "\(target.name): " : "")\(allow.domain) approved until \(allow.until.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("End") { store.endTemporaryAllow(allow, kidID: target.id) }
                        .font(.subheadline.weight(.semibold))
                }
                .guideCard(padding: 14)
            }
        }

        SectionLabel(title: "AI categories")
        ForEach(catalog.categories) { category in
            CategoryCard(kid: kid, category: category, effective: effective)
        }

        SectionLabel(title: "Chatbot rules")
        NavigationLink {
            GuidedRulesView()
        } label: {
            linkCard(
                symbol: "graduationcap.fill",
                title: "Homework rules for chatbots",
                detail: guidedSummary
            )
        }
        .buttonStyle(.plain)

        NavigationLink {
            SafetyAlertsView()
        } label: {
            linkCard(
                symbol: "bell.badge.fill",
                title: "Safety alerts",
                detail: safetySummary
            )
        }
        .buttonStyle(.plain)

        NavigationLink {
            SiteOverridesView()
        } label: {
            linkCard(
                symbol: "list.bullet.rectangle.fill",
                title: "Site exceptions",
                detail: exceptionCount == 0
                    ? "Always allow or block a specific site."
                    : "\(exceptionCount) site\(exceptionCount == 1 ? "" : "s") with their own rule"
            )
        }
        .buttonStyle(.plain)
    }

    private var exceptionCount: Int {
        Set(store.targetKids.flatMap { $0.policy.siteOverrides.keys }).count
    }

    private var safetySummary: String {
        "Always on for \(SafetyTopic.all.count) topics, like self-harm and vaping"
    }

    private var guidedSummary: String {
        let rules = kid.policy.guidedRules
        var parts: [String] = []
        if rules.blockHomeworkOffloading { parts.append("Stops homework offloading") }
        if rules.hideFinishedAnswers { parts.append("Hides finished answers") }
        if !rules.globalInstructions.isEmpty {
            parts.append("\(rules.globalInstructions.count) custom instruction\(rules.globalInstructions.count == 1 ? "" : "s")")
        }
        return parts.isEmpty ? "No rules on Guided chatbots" : parts.joined(separator: " · ")
    }

    private func activeScheduleBanner(_ effective: EffectiveRules) -> some View {
        let names = effective.activeScheduleNames.joined(separator: ", ")
        let schedule = kid.policy.schedules.first { effective.activeScheduleNames.contains($0.name) }
        return HStack(spacing: 10) {
            Image(systemName: "clock.badge.checkmark.fill")
                .foregroundStyle(GuideTheme.warmAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(names) is on now")
                    .font(.subheadline.weight(.semibold))
                if let schedule {
                    Text("Until \(TimeText.display(schedule.end)). Categories it changes are marked below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .guideCard(padding: 14)
    }

    private func linkCard(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(GuideTheme.brand)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .guideCard()
    }
}

private struct MasterSwitchCard: View {
    @EnvironmentObject private var store: FamilyStore
    let kid: Kid
    let effective: EffectiveRules

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.isAllKids ? "AI ON ALL \(store.kids.count) KIDS' PHONES" : "AI ON \(kid.name.uppercased())'S PHONE")
                        .font(.caption2.weight(.heavy))
                        .kerning(0.8)
                        .foregroundStyle(GuideTheme.heroSecondaryText)
                    Text(headline)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(GuideTheme.heroText)
                }
                Spacer()
                Image(systemName: effective.masterOff ? "powersleep" : "shield.lefthalf.filled")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(GuideTheme.brand)
            }

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(GuideTheme.heroSecondaryText)

            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: Binding(
                    get: { store.shared { $0.masterAIOff } ?? false },
                    set: { value in store.updatePolicies { $0.masterAIOff = value } }
                )) {
                    Text("Turn off all AI")
                        .font(.headline)
                        .foregroundStyle(GuideTheme.heroText)
                }
                .tint(GuideTheme.brand)
                if store.shared({ $0.masterAIOff }) == nil {
                    Text("Off for some kids. Switching it sets it for all.")
                        .font(.caption)
                        .foregroundStyle(GuideTheme.heroSecondaryText)
                }
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: GuideTheme.compactCornerRadius, style: .continuous))
        }
        .padding(GuideTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GuideTheme.heroGradient, in: RoundedRectangle(cornerRadius: GuideTheme.cornerRadius, style: .continuous))
    }

    private var headline: String {
        if store.isAllKids {
            switch store.shared({ $0.masterAIOff }) {
            case true?: return "All AI is off"
            case nil: return "AI is off for some kids"
            case false?: return "Editing all kids"
            }
        }
        if effective.masterOff { return "All AI is off" }
        let blocked = effective.states.values.filter { $0 == .block }.count
        return blocked == 0 ? "AI is on" : "\(blocked) categor\(blocked == 1 ? "y" : "ies") blocked"
    }

    private var detail: String {
        if store.isAllKids {
            return "Changes on this screen apply to every kid. Pick one kid above to change just their rules."
        }
        if let schedule = effective.masterOffSchedule, !kid.policy.masterAIOff {
            return "The \(schedule) schedule turned AI off. Every AI site in the catalog is blocked until it ends."
        }
        if effective.masterOff {
            return "Every AI site in the catalog is blocked, including ones you normally allow."
        }
        return "Choose what's allowed below. Guided chatbots check each prompt against your homework rules."
    }
}

private struct CategoryCard: View {
    @EnvironmentObject private var store: FamilyStore
    let kid: Kid
    let category: AICategory
    let effective: EffectiveRules

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: CategoryRoute(id: category.id)) {
                HStack(spacing: 12) {
                    Image(systemName: category.icon)
                        .font(.title3)
                        .foregroundStyle(GuideTheme.brand)
                        .frame(width: 34, height: 34)
                        .background(GuideTheme.brandSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            CategoryStatePicker(
                supportsGuided: category.supportsGuided,
                state: Binding(
                    get: { store.shared { $0.categories[category.id] ?? category.defaultState } },
                    set: { value in
                        guard let value else { return }
                        store.updatePolicies { $0.categories[category.id] = value }
                    }
                )
            )
            if store.shared({ $0.categories[category.id] ?? category.defaultState }) == nil {
                MixedCaption()
            }
        }
        .guideCard()
        .opacity(!store.isAllKids && effective.masterOff ? 0.55 : 1)
    }

    private var subtitle: String {
        let sites = "\(category.domains.count) sites"
        if store.isAllKids { return sites }
        if effective.masterOff { return "\(sites) · Off with all AI" }
        if let schedule = effective.scheduledBy[category.id], let state = effective.states[category.id] {
            return "\(sites) · \(state.label) now (\(schedule))"
        }
        return sites
    }
}
