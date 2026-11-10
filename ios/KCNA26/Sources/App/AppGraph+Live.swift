import Foundation

extension AppGraph {
    /// The process's graph (Kotlin: the `KcnaApp` Application object), with the real platform
    /// services: Application Support, `UserDefaults` suites, the bundle's data, URLSession
    /// fetchers, and the `UNUserNotificationCenter` reminders and permission of `Platform/`.
    /// Created on first use, on the main actor (``KCNA26App``'s `init`).
    static let shared: AppGraph = makeShared()

    private static func makeShared() -> AppGraph {
        #if DEBUG
        if let graph = ScreenshotMode.makeGraph() { return graph }  // -screenshotScene <name> (ScreenshotMode.swift)
        #endif
        return AppGraph.live(
            reminders: NotificationCenterReminders(),
            notificationPermission: NotificationCenterPermission()
        )
    }
}
