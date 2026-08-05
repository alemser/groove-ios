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
    @Environment(AppSettings.self) private var settings
    @Environment(AttentionCenter.self) private var attention
    @Environment(NavigationState.self) private var navigation
    @Environment(NowPlayingModel.self) private var nowPlaying
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var navigation = navigation
        // `TabView` owns a native UITabBar that doesn't shrink for a SwiftUI
        // safeAreaInset the way a ScrollView would, so the mini-bar is placed
        // with a plain bottom-aligned overlay instead — offset by the
        // standard 49pt tab bar content height (stable across iPhone form
        // factors pre-iOS 18's dedicated `tabViewBottomAccessory`).
        ZStack(alignment: .bottom) {
            TabView(selection: $navigation.selectedTab) {
                HomeView()
                    .tabItem { Label("Home", systemImage: "house") }
                    .tag(NavigationState.Tab.home)

                LibraryView()
                    .tabItem { Label("Library", systemImage: "square.stack") }
                    .badge(attention.count)
                    .tag(NavigationState.Tab.library)

                RigView()
                    .tabItem { Label("Rig", systemImage: "hifispeaker.and.homepod") }
                    .badge(attention.rigAttentionCount)
                    .tag(NavigationState.Tab.rig)

                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(NavigationState.Tab.settings)
            }
            .tint(Brand.accent)

            if !navigation.isNowPlayingSheetPresented, nowPlaying.status?.playback.active == true {
                NowPlayingMiniBar()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 57)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: nowPlaying.status?.playback.active)
        .sheet(isPresented: $navigation.isNowPlayingSheetPresented) {
            NowPlayingView()
        }
        .task { attention.start(settings) }
        .task { nowPlaying.start(settings) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await attention.refresh() }
                nowPlaying.start(settings)
            } else {
                nowPlaying.stop()
            }
        }
    }
}
