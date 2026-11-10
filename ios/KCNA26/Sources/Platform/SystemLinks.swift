import UIKit

/// Opening system pages and URLs from non-view code (views use `@Environment(\.openURL)` for
/// links). Kotlin: `Settings.ACTION_APPLICATION_DETAILS_SETTINGS`,
/// `ACTION_APP_NOTIFICATION_SETTINGS`, `ACTION_LOCATION_SOURCE_SETTINGS` and `openUrl(context, …)`.
@MainActor
enum SystemLinks {
    /// The app's page in Settings (location permission, "Allow location"; iOS can't open the
    /// device-wide Location Services switch, so "Turn on location" lands here too).
    static func openAppSettings() {
        open(UIApplication.openSettingsURLString)
    }

    /// The app's notification settings (the notifications-off hint's "Turn on" once the system
    /// dialog can't show any more, ``NotificationAsk/TurnOn/openSettings``); the app's page if
    /// that URL is unavailable.
    static func openNotificationSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            UIApplication.shared.open(url)
        } else {
            openAppSettings()
        }
    }

    /// Opens `url` in the system (browser, Maps, …). Ignores a URL nothing can open.
    static func open(_ url: URL) {
        UIApplication.shared.open(url)
    }

    /// ``open(_:)`` for a string; nothing for text that isn't a URL.
    static func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        open(url)
    }

    /// The notifications-off hint's "Turn on" (Kotlin `NotificationsOffHint`):
    /// ``NotificationAsk/turnOn(_:)`` for the current status: the system dialog while it can
    /// still show (``AppGraph/requestNotificationsNow()``, which re-plans the reminders if
    /// granted), else the notification settings.
    static func turnOnNotifications(_ graph: AppGraph) async {
        let status: NotificationAsk.Authorization = await graph.notificationPermission.status()
        switch NotificationAsk.turnOn(status) {
        case .requestAuthorization:
            _ = await graph.requestNotificationsNow()
        case .openSettings:
            openNotificationSettings()
        }
    }
}
