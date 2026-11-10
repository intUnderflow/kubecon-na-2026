import Foundation
import UserNotifications

/// The `UNUserNotificationCenter` delegate (set by ``AppDelegate`` before launch finishes, so the
/// tap that launches the app arrives too).
///
/// - Tap (the default action; Kotlin: the notification's content intent, MainActivity
///   `ACTION_OPEN_DIRECTIONS`): ``ReminderContent/directionsSessionId(_:)`` ->
///   ``AppGraph/notificationTapped(sessionId:)``; a window then routes it
///   (``AppGraph/routePendingDirections(to:)``: Schedule with the session's details -> Directions).
/// - A notification arriving while the app is in the foreground (`willPresent`): a reminder shows
///   only if the receiver's checks still pass at this moment (Kotlin ReminderReceiver,
///   ``AppGraph/reminderFiring(sessionId:minutesBefore:)``); anything else shows.
///
/// The methods are the async variants, nonisolated: the system may call them off the main
/// thread; only `Sendable` values (strings, the graph) cross to the main actor.
final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    private let graph: AppGraph

    init(graph: AppGraph) {
        self.graph = graph
        super.init()
    }

    /// Banner, Notification Center list and sound (Kotlin: a high-importance notification).
    static let presented: UNNotificationPresentationOptions = [.banner, .list, .sound]

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        guard let sessionId = ReminderContent.directionsSessionId(response.notification.request.content.userInfo) else { return }
        await graph.notificationTapped(sessionId: sessionId)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let request = notification.request
        guard let key = ReminderContent.keyOf(identifier: request.identifier, userInfo: request.content.userInfo) else {
            return NotificationCenterDelegate.presented
        }
        let firing: ReminderFiring = await graph.reminderFiring(sessionId: key.sessionId, minutesBefore: key.minutes)
        return firing.shows ? NotificationCenterDelegate.presented : []
    }
}
