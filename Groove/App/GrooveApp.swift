import SwiftUI

@main
struct GrooveApp: App {
    @State private var settings = AppSettings()
    @State private var attention = AttentionCenter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(attention)
                .tint(Brand.accent)
                .preferredColorScheme(.dark)
        }
    }
}
