import SwiftUI

struct AppRouter: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !env.onboardingComplete {
                OnboardingView()
            } else if env.activeRole == .parent {
                ParentRootTabView()
            } else {
                ChildRootTabView()
            }
        }
        .tint(GuideTheme.brand)
        .onAppear {
            env.familyControls.refreshAuthorizationStatus()
            env.usageTracker.rolloverIfNeeded()
            env.syncShieldsFromPolicy()
            env.consumePendingShieldRedirect()
        }
        .onChange(of: env.policyStore.policy) { _, _ in
            env.syncShieldsFromPolicy()
        }
        .onChange(of: env.familyControls.activitySelection) { _, _ in
            env.familyControls.saveSelection()
            env.syncShieldsFromPolicy()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                env.consumePendingShieldRedirect()
            }
        }
    }
}

private enum ParentTab: Hashable {
    case overview
    case activity
    case controls
}

private struct ParentRootTabView: View {
    @State private var selectedTab: ParentTab

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let initialTab: ParentTab = arguments.contains("-activityTab")
            ? .activity
            : arguments.contains("-controlsTab") ? .controls : .overview
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ParentDashboardView(
                onOpenActivity: { selectedTab = .activity },
                onOpenControls: { selectedTab = .controls }
            )
            .tabItem { Label("Overview", systemImage: "house.fill") }
            .tag(ParentTab.overview)

            WeeklyActivityView(audience: .parent)
                .tabItem { Label("Activity", systemImage: "chart.bar.xaxis") }
                .tag(ParentTab.activity)

            ParentControlsHubView()
                .tabItem { Label("Controls", systemImage: "slider.horizontal.3") }
                .tag(ParentTab.controls)
        }
    }
}

private enum ChildTab: Hashable {
    case home
    case learn
    case progress
}

private struct ChildRootTabView: View {
    @State private var selectedTab: ChildTab

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let initialTab: ChildTab = arguments.contains("-learnTab")
            ? .learn
            : arguments.contains("-progressTab") ? .progress : .home
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ChildHomeView(onOpenProgress: { selectedTab = .progress })
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(ChildTab.home)

            AssistantView(showsCloseButton: false)
                .tabItem { Label("Learn", systemImage: "bubble.left.and.text.bubble.right.fill") }
                .tag(ChildTab.learn)

            WeeklyActivityView(audience: .child)
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(ChildTab.progress)
        }
    }
}

enum ActivityAudience {
    case parent
    case child
}

enum ActivityMetric: String, CaseIterable, Identifiable {
    case minutes = "Minutes"
    case requests = "Requests"

    var id: String { rawValue }
}

struct WeeklyActivityPoint: Identifiable {
    let id: Int
    let day: String
    let minutes: Int
    let requests: Int

    func value(for metric: ActivityMetric) -> Int {
        metric == .minutes ? minutes : requests
    }
}

enum WeeklyActivityData {
    static var points: [WeeklyActivityPoint] {
        let minuteValues = [14, 22, 17, 28, 19, 31, 18]
        let requestValues = [4, 7, 5, 9, 6, 11, 8]
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"

        return (0..<7).map { index in
            let offset = index - 6
            let date = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
            return WeeklyActivityPoint(
                id: index,
                day: index == 6 ? "Today" : formatter.string(from: date),
                minutes: minuteValues[index],
                requests: requestValues[index]
            )
        }
    }
}

struct WeeklyTrendPreviewCard: View {
    let onOpen: () -> Void

    private let points = WeeklyActivityData.points

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("WEEKLY ACTIVITY")
                            .font(.caption2.weight(.heavy))
                            .kerning(0.8)
                            .foregroundStyle(.secondary)
                        Text("AI learning trends")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    Text("149 min")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(GuideTheme.brand)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }

                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(points) { point in
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(point.id == 6 ? GuideTheme.brand : GuideTheme.brand.opacity(0.22))
                            .frame(height: CGFloat(point.minutes) * 1.35)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 44, alignment: .bottom)

                HStack {
                    Label("8 guided requests today", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("View details")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GuideTheme.brand)
                }
            }
            .guideCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open weekly AI activity")
    }
}

struct WeeklyActivityView: View {
    let audience: ActivityAudience

    @State private var metric: ActivityMetric = .minutes
    @State private var selectedDayID = 6

    private let points = WeeklyActivityData.points

    private var selectedPoint: WeeklyActivityPoint {
        points.first(where: { $0.id == selectedDayID }) ?? points[6]
    }

    private var totalMinutes: Int { points.reduce(0) { $0 + $1.minutes } }
    private var totalRequests: Int { points.reduce(0) { $0 + $1.requests } }

    var body: some View {
        NavigationStack {
            ZStack {
                GuideTheme.pageBackground.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: GuideTheme.sectionSpacing) {
                        activityHeader
                        summaryCards
                        chartCard
                        insightCard
                        privacyCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var activityHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(GuideTheme.brandSoft)
                    .frame(width: 48, height: 48)
                Image(systemName: audience == .parent ? "chart.bar.fill" : "chart.line.uptrend.xyaxis")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(GuideTheme.brand)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(AppConfig.productDisplayName.uppercased())
                    .font(.caption2.weight(.heavy))
                    .kerning(1.2)
                    .foregroundStyle(GuideTheme.brand)
                Text(audience == .parent ? "AI activity" : "Your progress")
                    .font(.title2.bold())
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var summaryCards: some View {
        HStack(spacing: 12) {
            summaryMetric(value: "\(totalMinutes)m", label: "This week", icon: "clock.fill", tint: GuideTheme.brand)
            summaryMetric(value: "\(totalRequests)", label: "Guided requests", icon: "bubble.left.fill", tint: .orange)
        }
    }

    private func summaryMetric(value: String, label: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .guideCard()
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Last 7 days")
                        .font(.headline)
                    Text("Tap a day to inspect activity")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(selectedPoint.value(for: metric)) \(metric == .minutes ? "min" : "requests")")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(GuideTheme.brand)
            }

            Picker("Activity metric", selection: $metric) {
                ForEach(ActivityMetric.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(points) { point in
                    activityBar(point)
                }
            }
            .frame(height: 190, alignment: .bottom)
        }
        .guideCard()
    }

    private func activityBar(_ point: WeeklyActivityPoint) -> some View {
        let maxValue = max(points.map { $0.value(for: metric) }.max() ?? 1, 1)
        let value = point.value(for: metric)
        let isSelected = point.id == selectedDayID
        let height = max(14, CGFloat(value) / CGFloat(maxValue) * 128)

        return Button {
            withAnimation(.snappy(duration: 0.25)) {
                selectedDayID = point.id
            }
        } label: {
            VStack(spacing: 7) {
                Text(isSelected ? "\(value)" : " ")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(GuideTheme.brand)
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? GuideTheme.brand : GuideTheme.brand.opacity(0.20))
                    .frame(height: height)
                Text(point.day)
                    .font(.system(size: 9, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? GuideTheme.brand : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(point.day), \(value) \(metric.rawValue.lowercased())")
    }

    private var insightCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(audience == .parent ? "Weekly insights" : "Learning streak")
                .font(.headline)

            insightRow(
                icon: "book.closed.fill",
                tint: GuideTheme.brand,
                title: "Learning Mode",
                detail: audience == .parent ? "Used for 82% of guided sessions" : "Your most-used learning setting"
            )
            Divider()
            insightRow(
                icon: "arrow.triangle.turn.up.right.diamond.fill",
                tint: .orange,
                title: "3 protected redirects",
                detail: audience == .parent ? "Students chose guided help instead" : "You chose guided help instead"
            )
            Divider()
            insightRow(
                icon: "flame.fill",
                tint: .pink,
                title: "5-day learning streak",
                detail: "Up two days from last week"
            )
        }
        .guideCard()
    }

    private func insightRow(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var privacyCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(GuideTheme.success)
            VStack(alignment: .leading, spacing: 4) {
                Text("Privacy by design")
                    .font(.subheadline.weight(.semibold))
                Text(audience == .parent
                    ? "See time, requests, and trends without reading the child's conversations."
                    : "Your parent sees activity totals, not the text of your conversations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .guideCard()
    }
}

private struct ParentControlsHubView: View {
    @EnvironmentObject private var env: AppEnvironment
    @AppStorage("guidance.appearance") private var appearance = GuidanceAppearance.system.rawValue
    @State private var showPicker = false
    @State private var showSettings = false

    private var policy: ParentalPolicy { env.policyStore.policy }

    var body: some View {
        NavigationStack {
            ZStack {
                GuideTheme.pageBackground.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: GuideTheme.sectionSpacing) {
                        controlsHeader
                        modeCard
                        protectionCard
                        dailyLimitCard
                        appearanceCard
                        learningRulesButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showPicker) { AISelectionView() }
            .sheet(isPresented: $showSettings) { ParentSettingsView() }
        }
    }

    private var controlsHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(GuideTheme.brandSoft)
                    .frame(width: 48, height: 48)
                Image(systemName: "slider.horizontal.3")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(GuideTheme.brand)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(AppConfig.productDisplayName.uppercased())
                    .font(.caption2.weight(.heavy))
                    .kerning(1.2)
                    .foregroundStyle(GuideTheme.brand)
                Text("Parent controls")
                    .font(.title2.bold())
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("AI assistance mode")
                    .font(.headline)
                Text("Changes apply immediately to guided help.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(AIMode.allCases) { mode in
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        env.updatePolicy { $0.mode = mode }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: modeIcon(mode))
                            .foregroundStyle(policy.mode == mode ? .white : GuideTheme.brand)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.displayName)
                                .font(.subheadline.weight(.semibold))
                            Text(mode.summary)
                                .font(.caption2)
                                .foregroundStyle(policy.mode == mode ? Color.white.opacity(0.82) : Color.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Image(systemName: policy.mode == mode ? "checkmark.circle.fill" : "circle")
                    }
                    .foregroundStyle(policy.mode == mode ? Color.white : Color.primary)
                    .padding(13)
                    .background(
                        policy.mode == mode ? AnyShapeStyle(GuideTheme.actionGradient) : AnyShapeStyle(GuideTheme.tertiaryFill),
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .guideCard()
    }

    private var protectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: Binding(
                get: { policy.blockExternalAI },
                set: { value in env.updatePolicy { $0.blockExternalAI = value } }
            )) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Restrict selected AI tools")
                        .font(.headline)
                    Text("\(env.familyControls.selectionSummary) currently selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(GuideTheme.brand)

            Button {
                showPicker = true
            } label: {
                Label("Choose apps and websites", systemImage: "plus.app.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.borderedProminent)
        }
        .guideCard()
    }

    private var dailyLimitCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Daily AI limit")
                        .font(.headline)
                    Text("Guided-assistant time per day")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(policy.dailyLimitMinutes) min")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(GuideTheme.brand)
            }

            HStack(spacing: 14) {
                limitButton(symbol: "minus", delta: -5)
                ProgressView(value: Double(policy.dailyLimitMinutes), total: 180)
                    .tint(GuideTheme.brand)
                limitButton(symbol: "plus", delta: 5)
            }
        }
        .guideCard()
    }

    private func limitButton(symbol: String, delta: Int) -> some View {
        Button {
            env.updatePolicy {
                $0.dailyLimitMinutes = min(180, max(5, $0.dailyLimitMinutes + delta))
            }
        } label: {
            Image(systemName: symbol)
                .font(.headline)
                .frame(width: 38, height: 38)
                .background(GuideTheme.tertiaryFill, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(delta > 0 ? "Increase daily limit" : "Decrease daily limit")
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Appearance", systemImage: "circle.lefthalf.filled")
                .font(.headline)
            Picker("Appearance", selection: $appearance) {
                ForEach(GuidanceAppearance.allCases) { option in
                    Text(option.label).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)
            Text("System follows the iPhone's Light or Dark appearance.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .guideCard()
    }

    private var learningRulesButton: some View {
        Button {
            showSettings = true
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "checklist")
                    .foregroundStyle(GuideTheme.brand)
                    .frame(width: 36, height: 36)
                    .background(GuideTheme.brand.opacity(0.10), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("Learning rules & custom instructions")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Attempt-first and assignment settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .guideCard()
        }
        .buttonStyle(.plain)
    }

    private func modeIcon(_ mode: AIMode) -> String {
        switch mode {
        case .learning: return "book.closed.fill"
        case .standard: return "sparkles"
        case .restricted: return "hand.raised.fill"
        }
    }
}
