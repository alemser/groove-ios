import SwiftUI
import UserNotifications

@main
struct GrooveApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings = AppSettings()
    @State private var attention = AttentionCenter()
    @State private var nowPlaying = NowPlayingModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(attention)
                .environment(appDelegate.navigation)
                .environment(nowPlaying)
                .tint(Brand.accent)
                .preferredColorScheme(.dark)
        }
    }
}

/// Owns `NavigationState` so a notification tap can route it: the delegate is
/// set at launch, before a tap that cold-starts the app is delivered.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let navigation = NavigationState()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    @MainActor
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        if let destination = NotificationDestination(userInfo: response.notification.request.content.userInfo) {
            navigation.open(destination)
        }
    }
}
