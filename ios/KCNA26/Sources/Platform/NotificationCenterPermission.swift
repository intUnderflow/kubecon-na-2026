import Foundation
import UserNotifications

/// Core's ``NotificationPermission`` over `UNUserNotificationCenter` (Kotlin: the
/// POST_NOTIFICATIONS runtime permission). ``AppGraph`` asks in context
/// (``NotificationAsk``); the notifications-off hint reads ``status()``.
struct NotificationCenterPermission: NotificationPermission {
    func status() async -> NotificationAsk.Authorization {
        let settings: UNNotificationSettings = await UNUserNotificationCenter.current().notificationSettings()
        return NotificationCenterPermission.authorization(settings.authorizationStatus)
    }

    /// The system dialog (shown only while the status is `.notDetermined`); true when granted.
    func request() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    /// `UNAuthorizationStatus` as Core sees it (an unknown future status counts as authorized).
    static func authorization(_ status: UNAuthorizationStatus) -> NotificationAsk.Authorization {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        @unknown default: return .authorized
        }
    }
}
