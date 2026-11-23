import UserNotifications

/// Where tapping a local notification takes the person.
enum NotificationDestination: String {
    /// The Library tab, with the "Needs Association" review open.
    case associations
    /// The Rig tab, on Stylus Tracking.
    case stylus

    private static let userInfoKey = "destination"

    init?(userInfo: [AnyHashable: Any]) {
        guard let raw = userInfo[Self.userInfoKey] as? String else { return nil }
        self.init(rawValue: raw)
    }

    fileprivate var userInfo: [AnyHashable: Any] { [Self.userInfoKey: rawValue] }
}

/// Posts the app's local notifications, when the user allows them.
enum Notifier {
    /// Asks the first time; once the person answered, does nothing.
    static func requestPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// A notification with the same `id` replaces the one before it.
    static func post(id: String, title: String, body: String, destination: NotificationDestination) async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = destination.userInfo
        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        try? await center.add(request)
    }
}
