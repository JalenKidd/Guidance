import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: FamilyStore

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: GuideTheme.sectionSpacing) {
                    TabHeader("Home") {
                        if store.isSaving { ProgressView() }
                    }
                    KidSelectorBar()
                    if let kid = store.selectedKid, let catalog = store.catalog {
                        HomeContent(kid: kid, catalog: catalog)
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
            .navigationTitle("Home")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: CategoryRoute.self) { route in
                CategoryDetailView(categoryID: route.id)
            }
            .navigationDestination(for: AppRoute.self) { route in
                AppDetailView(appID: route.id)
            }
        }
    }
}

struct CategoryRoute: Hashable {
    let id: String
}

struct AppRoute: Hashable {
    let id: String
}

private struct HomeContent: View {
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

        MasterSwitchCard(kid: kid, effective: effective, poweredDown: poweredDown(effective))
            .zIndex(1) // Keeps the shockwave ring above the rows below.

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

        let off = poweredDown(effective)
        ForEach(Array(catalog.categories.enumerated()), id: \.element.id) { index, category in
            CategoryRow(category: category, effective: effective, poweredDown: off, index: index)
        }

        SectionLabel(title: "Rules")
            .padding(.top, 8)
        NavigationLink {
            GuidedRulesView()
        } label: {
            linkCard(symbol: "graduationcap.fill", title: "Rules for LLMs (Chatbots)")
        }
        .buttonStyle(.plain)

        NavigationLink {
            SafetyAlertsView()
        } label: {
            linkCard(symbol: "bell.badge.fill", title: "Safety alerts")
        }
        .buttonStyle(.plain)

        NavigationLink {
            SiteOverridesView()
        } label: {
            linkCard(symbol: "list.bullet.rectangle.fill", title: "Site exceptions")
        }
        .buttonStyle(.plain)
    }

    /// Whether "Turn off all AI" is in effect for what's on screen.
    private func poweredDown(_ effective: EffectiveRules) -> Bool {
        store.isAllKids ? store.shared { $0.masterAIOff } == true : effective.masterOff
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
                    Text("Until \(TimeText.display(schedule.end))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .guideCard(padding: 14)
    }

    private func linkCard(symbol: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(GuideTheme.brand)
                .frame(width: 30)
            Text(title).font(.headline)
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
    /// AI is off: the card goes dark.
    let poweredDown: Bool
    /// Bumped when the parent flips the switch, to fire the shockwave.
    @State private var shockwave = 0

    private static let offGradient = LinearGradient(
        colors: [Color(white: 0.2), Color(white: 0.05)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: GuideTheme.cornerRadius, style: .continuous)

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.isAllKids ? "AI ON ALL \(store.kids.count) KIDS' PHONES" : "AI ON \(kid.name.uppercased())'S PHONE")
                        .font(.caption2.weight(.heavy))
                        .kerning(0.8)
                        .foregroundStyle(secondaryText)
                    Text(headline)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(primaryText)
                        .contentTransition(.opacity)
                }
                Spacer()
                // The half shield powers up into a full, glowing super shield.
                Image(systemName: poweredDown ? "bolt.shield.fill" : "shield.lefthalf.filled")
                    .font(.system(size: poweredDown ? 40 : 30, weight: .semibold))
                    .foregroundStyle(GuideTheme.brand)
                    .shadow(color: GuideTheme.brand.opacity(poweredDown ? 0.9 : 0), radius: poweredDown ? 14 : 0)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: poweredDown)
                    .symbolEffect(.pulse, options: .repeating, isActive: poweredDown)
                    .background {
                        ShockwaveRings(trigger: shockwave, color: GuideTheme.brand)
                    }
            }

            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(secondaryText)
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: Binding(
                    get: { store.shared { $0.masterAIOff } ?? false },
                    set: { value in
                        shockwave += 1
                        store.updatePolicies { $0.masterAIOff = value }
                    }
                )) {
                    Text("Turn off all AI")
                        .font(.headline)
                        .foregroundStyle(primaryText)
                }
                .tint(GuideTheme.brand)
                if store.shared({ $0.masterAIOff }) == nil {
                    Text("Off for some kids. Switching it sets it for all.")
                        .font(.caption)
                        .foregroundStyle(secondaryText)
                }
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: GuideTheme.compactCornerRadius, style: .continuous))
        }
        .padding(GuideTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // Cross-fade between the red card and the dark "powered down" card.
            ZStack {
                shape.fill(GuideTheme.heroGradient)
                shape.fill(Self.offGradient).opacity(poweredDown ? 1 : 0)
            }
        }
        .scaleEffect(poweredDown ? 0.98 : 1)
        .animation(.spring(response: 0.5, dampingFraction: 0.65), value: poweredDown)
    }

    private var primaryText: Color { poweredDown ? .white : GuideTheme.heroText }
    private var secondaryText: Color { poweredDown ? .white.opacity(0.7) : GuideTheme.heroSecondaryText }

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

    /// Only shown when a schedule is the reason AI is off, since the toggle wouldn't say so.
    private var detail: String? {
        guard !store.isAllKids, let schedule = effective.masterOffSchedule, !kid.policy.masterAIOff else { return nil }
        return "\(schedule) turned AI off until it ends."
    }
}

/// One category: its name and rule above a horizontal row of its apps.
private struct CategoryRow: View {
    @EnvironmentObject private var store: FamilyStore
    let category: AICategory
    let effective: EffectiveRules
    let poweredDown: Bool
    /// Position on the page, so rows shut off one after another from the top.
    let index: Int
    /// Bumped when the parent picks Block here, to fire a ring from the button.
    @State private var blockRing = 0

    var body: some View {
        let apps = category.apps
        let customized = customizedApps(apps)
        let shared = store.shared { $0.categories[category.id] ?? category.defaultState }
        let blocked = customized.isEmpty && shared == .block
        let locked = poweredDown || blocked

        VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: CategoryRoute(id: category.id)) {
                HStack(spacing: 6) {
                    Text(category.name)
                        .font(.title3.weight(.bold))
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // With "Turn off all AI" on, every row reads Block and can't be changed.
            CategoryRuleBar(
                supportsGuided: category.supportsGuided,
                selected: poweredDown ? .block : (customized.isEmpty ? shared : nil),
                isCustom: !poweredDown && !customized.isEmpty,
                blockRing: blockRing
            ) { state in
                if state == .block && !blocked { blockRing += 1 }
                // Picking a rule for the whole category also clears the apps' own rules.
                let domains = customized.flatMap(\.domains)
                store.updatePolicies { policy in
                    policy.categories[category.id] = state
                    for domain in domains { policy.siteOverrides[domain] = nil }
                }
            }
            .disabled(poweredDown)
            if shared == nil && customized.isEmpty && !poweredDown { MixedCaption() }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(Array(apps.enumerated()), id: \.element.id) { position, app in
                        NavigationLink(value: AppRoute(id: app.id)) {
                            // Locks pop on left to right; with "Turn off all AI" they wait for this row's turn.
                            AppTile(app: app, override: override(for: app), locked: locked,
                                    delay: (poweredDown ? delay + 0.15 : 0.1) + Double(position) * 0.05)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, -16)
        }
        .padding(.top, 6)
        .saturation(locked ? 0 : 1)
        .opacity(locked ? 0.5 : 1)
        .scaleEffect(locked ? 0.96 : 1, anchor: .leading)
        // "Turn off all AI" sweeps down the page; Block on this row animates right away.
        .animation(.spring(response: 0.45, dampingFraction: 0.7).delay(delay), value: poweredDown)
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: blocked)
        .zIndex(blockRing > 0 ? 1 : 0)
    }

    private var delay: Double { 0.15 + Double(index) * 0.08 }

    /// Apps any target kid has given their own rule.
    private func customizedApps(_ apps: [AIApp]) -> [AIApp] {
        apps.filter { app in
            store.targetKids.contains { kid in app.domains.contains { kid.policy.siteOverrides[$0] != nil } }
        }
    }

    /// The app's own rule. Outer nil: kids differ.
    private func override(for app: AIApp) -> SiteOverride?? {
        store.shared { policy in app.domains.lazy.compactMap { policy.siteOverrides[$0] }.first }
    }

    private var status: String? {
        if store.isAllKids { return nil }
        if effective.masterOff { return "Off with all AI" }
        if let schedule = effective.scheduledBy[category.id], let state = effective.states[category.id] {
            return "\(state.label) now · \(schedule)"
        }
        return nil
    }
}

/// Allow · Guided · Block, plus Custom when some apps in the category have their own rule.
/// Custom only shows what's set; pick an app to change its rule.
private struct CategoryRuleBar: View {
    let supportsGuided: Bool
    /// nil when Custom or when kids differ.
    let selected: CategoryState?
    let isCustom: Bool
    var blockRing = 0
    let choose: (CategoryState) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(supportsGuided ? CategoryState.allCases : [.allow, .block]) { state in
                segment(state.label, isOn: selected == state) { choose(state) }
                    .background {
                        if state == .block {
                            ShockwaveRings(trigger: blockRing, color: GuideTheme.brand, spread: 4)
                        }
                    }
            }
            if isCustom {
                segment("Custom", isOn: true, action: nil)
            }
        }
        .padding(3)
        .background(GuideTheme.tertiaryFill, in: Capsule())
    }

    private func segment(_ title: String, isOn: Bool, action: (() -> Void)?) -> some View {
        Button {
            action?()
        } label: {
            Text(title)
                .font(.subheadline.weight(isOn ? .semibold : .regular))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(isOn ? Color(uiColor: .systemGray3) : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct AppTile: View {
    let app: AIApp
    /// Outer nil: kids differ. Inner nil: follows the category.
    let override: SiteOverride??
    /// "Turn off all AI" is on: a lock pops onto the icon.
    var locked = false
    var delay: Double = 0

    var body: some View {
        VStack(spacing: 6) {
            AppIconView(app: app, size: 72)
                .overlay {
                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.65), in: Circle())
                            .transition(.scale(scale: 0.2).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.55).delay(delay), value: locked)
                .overlay(alignment: .topTrailing) {
                    if let badge {
                        Image(systemName: badge)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(GuideTheme.brand, in: Circle())
                            .offset(x: 6, y: -6)
                    }
                }
            Text(app.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 80)
        }
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(app.name + (accessibilityRule.map { ", \($0)" } ?? ""))
    }

    private var badge: String? {
        guard let override else { return "questionmark" }
        return override?.categoryState.symbol
    }

    private var accessibilityRule: String? {
        guard let override else { return "different for each kid" }
        return override?.label
    }
}

/// Two rings that burst out from the master switch icon when it's flipped.
private struct ShockwaveRings: View {
    let trigger: Int
    let color: Color
    /// How many times its own size each ring grows.
    var spread: CGFloat = 16
    @State private var progress: [CGFloat] = [1, 1]

    var body: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                Circle()
                    .stroke(color, lineWidth: 8 * (1 - progress[i]) + 1)
                    .frame(width: 44, height: 44)
                    .scaleEffect(1 + progress[i] * spread)
                    .opacity(Double(1 - progress[i]) * 0.8)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in
            for i in progress.indices {
                progress[i] = 0
                withAnimation(.easeOut(duration: 0.9).delay(Double(i) * 0.15)) { progress[i] = 1 }
            }
        }
    }
}
