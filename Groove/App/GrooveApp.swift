import SwiftUI

@main
struct GrooveApp: App {
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .tint(Brand.accent)
                .preferredColorScheme(.dark)
        }
    }
}
