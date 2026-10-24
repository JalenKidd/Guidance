import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: FamilyStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            #if DEBUG
            if let screen = DebugLaunch.value("-screen") {
                DebugScreen(name: screen)
            } else {
                main
            }
            #else
            main
            #endif
        }
        .tint(GuideTheme.brand)
        .task {
            #if DEBUG
            if DebugLaunch.has("-unlocked") { store.isUnlocked = true }
            #endif
            await store.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                // The kid may pick up the phone next; parent controls need Face ID again.
                store.isUnlocked = false
            case .active:
                Task { await store.refresh() }
            default:
                break
            }
        }
    }
}

extension RootView {
    @ViewBuilder
    private var main: some View {
        if store.session == nil {
            WelcomeView()
        } else if !store.isUnlocked {
            LockView()
        } else {
            ParentTabView()
        }
    }
}

private enum ParentTab: String, Hashable {
    case home
    case schedules
    case activity
    case setup
}

private struct ParentTabView: View {
    @EnvironmentObject private var store: FamilyStore
    @State private var tab: ParentTab = {
        #if DEBUG
        if let name = DebugLaunch.value("-tab"), let tab = ParentTab(rawValue: name) { return tab }
        #endif
        return .home
    }()

    var body: some View {
        TabView(selection: $tab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(ParentTab.home)

            SchedulesView()
                .tabItem { Label("Schedules", systemImage: "clock.fill") }
                .tag(ParentTab.schedules)

            ActivityView()
                .tabItem { Label("Activity", systemImage: "chart.bar.xaxis") }
                .tag(ParentTab.activity)
                .badge(store.attentionCount)

            SetupView()
                .tabItem { Label("Setup", systemImage: "iphone.gen3") }
                .tag(ParentTab.setup)
        }
        .environment(\.openActivity) { tab = .activity }
        // While the parent has the app open, check for new requests and alerts.
        .task {
            while !Task.isCancelled {
                await store.refreshAllActivity()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }
}
