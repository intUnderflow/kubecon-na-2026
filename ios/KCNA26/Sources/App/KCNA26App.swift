import SwiftUI

/// The app (Kotlin `KcnaApp` + `MainActivity`): one ``AppGraph`` per process, started as early as
/// possible, and the App-level scene phase (the aggregate of all windows) driving its
/// foreground/background reactions.
///
/// - `init`: installs Core Location's observed declination for the compass
///   (``DirectionsLocationService/installDeclinationSource()``), then
///   ``AppGraph/start(arguments:)``: the data loads off the main thread, the debug `-fakeNow`
///   argument applies, the reminders are planned and re-planned on every relevant change.
/// - scenePhase `.active` (also right after launch: `initial: true`) -> ``AppGraph/onForeground()``
///   (data check if due, reminders, the notification ask in context); every other phase
///   (`.inactive`, `.background`) -> ``AppGraph/onBackground()`` (the data crash guard needs
///   it on every exit from `.active`). `applicationWillTerminate` does the same (``AppDelegate``).
/// - ``AppDelegate`` sets the `UNUserNotificationCenter` delegate in
///   `didFinishLaunchingWithOptions`, so a reminder tap that launches the app is delivered.
/// - Each window shows ``RootView`` with the graph in the environment (`@Environment(AppGraph.self)`),
///   the theme (`.kcnaTheme()`, the page background) and the window width class
///   (`.readsWindowWidth()`).
@main
struct KCNA26App: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    private let graph: AppGraph

    init() {
        DirectionsLocationService.installDeclinationSource()
        let graph = AppGraph.shared
        graph.start(arguments: ProcessInfo.processInfo.arguments)
        self.graph = graph
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(graph)
                .kcnaTheme()
                .kcnaPageBackground()
                .readsWindowWidth()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                graph.onForeground()
            } else {
                graph.onBackground()
            }
        }
    }
}
