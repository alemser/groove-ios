import SwiftUI

@main
struct GrooveApp: App {
    @State private var settings = AppSettings()
    @State private var attention = AttentionCenter()
    @State private var navigation = NavigationState()
    @State private var nowPlaying = NowPlayingModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(attention)
                .environment(navigation)
                .environment(nowPlaying)
                .tint(Brand.accent)
                .preferredColorScheme(.dark)
        }
    }
}
