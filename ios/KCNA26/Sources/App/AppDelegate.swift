import UIKit
import UserNotifications

/// The UIKit application delegate (`@UIApplicationDelegateAdaptor` in ``KCNA26App``).
///
/// - `didFinishLaunchingWithOptions`: sets the `UNUserNotificationCenter` delegate
///   (``NotificationCenterDelegate``). It must be set before launch finishes, or the tap that
///   launched the app (a reminder: Kotlin MainActivity's `ACTION_OPEN_DIRECTIONS` intent) is
///   never delivered.
/// - `applicationWillTerminate`: ``AppGraph/onBackground()`` (Core's
///   `willTerminateNotification` rule: the crash guard must see every healthy exit).
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// `UNUserNotificationCenter.delegate` is weak: keep it here.
    private var notificationDelegate: NotificationCenterDelegate?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let delegate = NotificationCenterDelegate(graph: AppGraph.shared)
        notificationDelegate = delegate
        UNUserNotificationCenter.current().delegate = delegate
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        AppGraph.shared.onBackground()
    }
}
