import SwiftUI

struct RootView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Group {
            if settings.isConfigured {
                MainTabView()
            } else {
                ConnectView()
            }
        }
        .animation(.default, value: settings.isConfigured)
    }
}

struct MainTabView: View {
    /// Restore the tab the user was last on.
    @AppStorage("selectedTab") private var selectedTab = 0
    @Environment(AppSettings.self) private var settings
    @Environment(AttentionCenter.self) private var attention
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selectedTab) {
            NowPlayingView()
                .tabItem { Label("Now Playing", systemImage: "waveform") }
                .tag(0)

            PlaysView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(1)

            LibraryView()
                .tabItem { Label("Library", systemImage: "square.stack") }
                .tag(2)

            ReviewView()
                .tabItem { Label("Review", systemImage: "checkmark.seal") }
                .badge(attention.count)
                .tag(3)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(4)
        }
        .tint(Brand.accent)
        .task { attention.start(settings) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await attention.refresh() } }
        }
    }
}
