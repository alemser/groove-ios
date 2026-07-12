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
    var body: some View {
        TabView {
            NowPlayingView()
                .tabItem { Label("Now Playing", systemImage: "waveform") }

            PlaysView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

            LibraryView()
                .tabItem { Label("Library", systemImage: "square.stack") }

            ReviewView()
                .tabItem { Label("Review", systemImage: "checkmark.seal") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Brand.accent)
    }
}
