import Foundation

extension AppGraph {
    /// The process's graph (Kotlin: the `KcnaApp` Application object), with the real platform
    /// services: Application Support, `UserDefaults` suites, the bundle's data, URLSession
    /// fetchers, and the `UNUserNotificationCenter` reminders and permission of `Platform/`.
    /// Created on first use, on the main actor (``KCNA26App``'s `init`).
    static let shared: AppGraph = AppGraph.live(
        reminders: NotificationCenterReminders(),
        notificationPermission: NotificationCenterPermission()
    )
}
