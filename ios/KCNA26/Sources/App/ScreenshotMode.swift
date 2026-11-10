#if DEBUG
import Foundation

/// Debug builds only: the screenshot scenes (Core ``ScreenshotScene``), chosen with the launch
/// argument `-screenshotScene <name>` (`ios/scripts/screenshots.sh`). Without the argument
/// every hook here does nothing and the app runs as usual; release builds don't contain it.
///
/// The hooks, each a line or two inside `#if DEBUG` in an existing file (ScheduleScreen.swift also
/// has a debug-only extension at its end, which can reach the screen's private state):
/// - ``makeGraph()`` (AppGraph+Live.swift, `AppGraph.shared`): the graph with the scene's
///   stand-ins (``ScreenshotScene/services(_:)``: offline data and descriptions, notifications
///   that read as allowed so neither the system dialog nor the "notifications are off" hint
///   shows, no reminder notifications) and the scene's state in its stores (speaker with the
///   first run answered, RSVPs, reminder time, From, fake time), before `start(arguments:)`.
/// - ``takeNavSaved()`` (RootView.swift, the window's ``NavModel``): the scene's screens and
///   open session instead of the restored ones, for the first window.
/// - ``takeScheduleSeed()`` (ScheduleScreen.swift): the Schedule's saved state (day, expanded
///   groups, open co-located cards; search cleared, RSVP filter off) and where its list starts,
///   once.
/// - ``directionsStarted(_:)`` (DirectionsLocationService.swift, when Directions starts
///   tracking): the scene's fix and heading go straight to the view model, in place of Core
///   Location (the simulator has no compass, its fixes read ±5 m rather than the Android shot's
///   ±12 m, and no location permission dialog can show; the script still grants location and
///   sets the simulator's position to the same place).
@MainActor
enum ScreenshotMode {
    /// The scene the launch arguments name; nil for a normal run.
    static let scene: ScreenshotScene? = ScreenshotScene.from(arguments: ProcessInfo.processInfo.arguments)

    private static var navApplied = false
    private static var scheduleApplied = false

    /// The process's graph for a screenshot scene (nil: a normal run, build the real one).
    static func makeGraph() -> AppGraph? {
        guard let scene else { return nil }
        let services = ScreenshotScene.services(
            .live(reminders: ScreenshotReminders(), notificationPermission: ScreenshotNotificationPermission())
        )
        let graph = AppGraph(services)
        scene.apply(settings: graph.settings, going: graph.going, clock: graph.fakeableClock)
        services.log("screenshot scene \(scene.name): now=\(graph.clock.now())")
        return graph
    }

    /// The first window's navigation (in place of the restored one), once per process; nil: keep
    /// the restored one.
    static func takeNavSaved() -> NavModel.Saved? {
        guard let scene, !navApplied else { return nil }
        navApplied = true
        return scene.navSaved
    }

    /// The Schedule screen's seed, once per process (nil: keep the saved state).
    static func takeScheduleSeed() -> ScreenshotScene.ScheduleSeed? {
        guard let scene, !scheduleApplied else { return nil }
        scheduleApplied = true
        return scene.scheduleSeed
    }

    /// Directions started tracking for `vm`: feed it the scene's fix and heading. True when the
    /// scene has a fix: then the service neither asks for location permission nor starts Core
    /// Location or the compass (their readings would replace the scene's).
    static func directionsStarted(_ vm: DirectionsViewModel) -> Bool {
        guard let scene, let fix = scene.location else { return false }
        vm.onLocation(fix.latitude, fix.longitude, fix.accuracyM, nil)
        if let heading = scene.heading {
            vm.onHeading(
                trueHeading: heading,
                magneticHeading: Geo.norm360(heading - Geo.SLC_DECLINATION_DEG),
                headingAccuracy: 10,
                timeMs: Date().epochMillis
            )
        }
        return true
    }
}
#endif
