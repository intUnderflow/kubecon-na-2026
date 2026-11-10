import Foundation
import UserNotifications

/// Core's ``ReminderScheduling`` over `UNUserNotificationCenter` (Kotlin AlarmManager +
/// ReminderNotifier): ``ReminderScheduler`` (owned by ``AppGraph``) decides what to schedule;
/// this only talks to the notification center.
///
/// - A request per ``ReminderRequest``: identifier = the reminder key ("1249844/10"), a
///   time-interval trigger (an absolute moment, also across time-zone changes), the content of
///   ``ReminderContent`` (title, body, thread "talk:<id>", target "directions:<id>", the
///   string `userInfo` the tap and `willPresent` read back), default sound, interruption level
///   `.active` (Kotlin's high-importance channel).
/// - Pending requests survive reboots and app updates (no boot receiver on iOS); iOS keeps at
///   most 64 per app, so the scheduler only adds the soonest 60.
struct NotificationCenterReminders: ReminderScheduling {
    private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }

    func pendingIdentifiers() async -> [String] {
        let requests: [UNNotificationRequest] = await center.pendingNotificationRequests()
        return requests.map(\.identifier)
    }

    func add(_ r: ReminderRequest) async throws {
        let c = UNMutableNotificationContent()
        c.title = r.content.title
        c.body = r.content.body
        c.threadIdentifier = r.content.threadIdentifier
        c.targetContentIdentifier = r.content.targetContentIdentifier
        c.userInfo = r.content.userInfo
        c.sound = .default
        c.interruptionLevel = .active
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: r.timeInterval(from: Date()), repeats: false)
        try await center.add(UNNotificationRequest(identifier: r.identifier, content: c, trigger: trigger))
    }

    func removePending(_ ids: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func delivered() async -> [DeliveredReminder] {
        let notifications: [UNNotification] = await center.deliveredNotifications()
        return notifications.map {
            DeliveredReminder(identifier: $0.request.identifier, userInfo: $0.request.content.userInfo, date: $0.date)
        }
    }

    func removeDelivered(_ ids: [String]) async {
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }
}
