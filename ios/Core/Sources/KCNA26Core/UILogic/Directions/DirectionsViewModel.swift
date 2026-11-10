import Foundation
import Observation

/// State of one Directions screen (Kotlin: an AndroidX `ViewModel`, activity-scoped and keyed
/// "dir-<sessionId>-<identityHashCode(repo)>", so the last fix, the heading and the route survive
/// recreation without flashing "Finding you…"). iOS: create one per pushed Directions screen and
/// keep it in the view's `@State` (it lives as long as the screen is in the navigation stack),
/// keyed by the data set too: the session, room, target, From options and routes come from the
/// `repo` and `router` it was built with, so when a live data update swaps
/// `AppGraph.repository` (and `router`), build a new one with the new pair (cache it under
/// `(sessionId, ObjectIdentifier(graph.repository))`, or put
/// `.id(ObjectIdentifier(graph.repository))` on the screen's content). Otherwise an open screen
/// keeps routing to the talk's old room until it is left and reopened.
///
/// Location and compass updates belong to the screen's lifecycle and are pushed in by the app
/// layer (CoreLocation; see ``LocationTracker`` and ``CompassSensor`` for the exact wiring):
///
/// - ``trackingStarted()`` / ``trackingStopped()`` around `startUpdatingLocation()` /
///   `stopUpdatingLocation()` (screen visible and authorized);
/// - ``onLocation(_:)`` with each `CLLocation` (Kotlin ``onLocation(_:_:_:_:)``);
/// - ``onLocationFailure()`` when Core Location reports `CLError.denied`;
/// - ``setDeviceLocationOff(_:)`` from `CLLocationManager.locationServicesEnabled()`;
/// - ``onHeading(trueHeading:magneticHeading:headingAccuracy:timeMs:)`` with each `CLHeading`
///   (Kotlin ``onAzimuth(_:_:_:_:)`` + ``onSensorAccuracy(_:_:)``).
///
/// The heading only drives the heading cone on the map's "me" dot. Everything is main-actor
/// state; reading ``plan`` re-routes only when its key changes (cheap, see ``RoutePlanner``).
@MainActor
@Observable
final class DirectionsViewModel {
    nonisolated static let NO_FIX_AFTER_MS: Int64 = 30_000
    nonisolated static let STALE_FIX_MS: Int64 = 60_000
    nonisolated static let CALIBRATE_AFTER_MS: Int64 = 1_500
    nonisolated static let HEADING_ALPHA = 0.5
    nonisolated static let VENUE_ALTITUDE_M = 1300.0
    /// wayfinding.json: "About 10 degrees east at Salt Lake City" (the web's DECL).
    nonisolated static let FALLBACK_DECLINATION = Geo.SLC_DECLINATION_DEG

    let sessionId: String
    let session: Session?
    let room: Room?

    /// The room's position, or nil for OFF / unknown rooms (no live directions then).
    let target: PointXY?

    let options: FromOptions

    @ObservationIgnored private let repo: Repository
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let clock: any AppClock
    @ObservationIgnored private let planner: RoutePlanner
    @ObservationIgnored private let declinationOf: (Double, Double, Double, Int64) throws -> Double
    @ObservationIgnored private let log: (String) -> Void
    @ObservationIgnored private let elapsedMs: () -> Int64
    @ObservationIgnored private let scheduler: any DirectionsScheduler

    /// The latest fix, or nil.
    private(set) var fix: Fix? = nil

    /// True once tracking ran ``NO_FIX_AFTER_MS`` without a fix (or failed): "No GPS fix yet".
    private(set) var noFix = false

    private(set) var deviceLocationOff = false

    /// Smoothed true heading of the top of the phone (degrees clockwise from north, turning the
    /// short way round), or nil until the compass wakes up: the map hides the cone until then.
    private(set) var heading: Double? = nil

    /// Show the figure-8 hint (magnetometer or rotation vector accuracy low/unreliable for a moment).
    private(set) var calibrate = false

    @ObservationIgnored private let smoother = HeadingSmoother(DirectionsViewModel.HEADING_ALPHA)
    @ObservationIgnored private let logThrottle = Throttle(1000)
    /// Degrees east; the venue's until the first fix, then the fix's.
    @ObservationIgnored private var declinationDeg: Double = DirectionsViewModel.FALLBACK_DECLINATION
    @ObservationIgnored private var magAccuracy: Int? = nil
    @ObservationIgnored private var rvAccuracy: Int? = nil
    @ObservationIgnored private var calibrateJob: DirectionsJob? = nil
    @ObservationIgnored private var noFixJob: DirectionsJob? = nil
    @ObservationIgnored private var fixAtMs: Int64 = 0
    /// The last plan and its ``RoutePlanner/planKey(_:_:)`` (Kotlin: `distinctUntilChanged` + `stateIn`).
    @ObservationIgnored private var planCache: (key: String, plan: RoutePlan?)? = nil

    /// - Parameters:
    ///   - declinationOf: (lat, lng, altitudeM, epochMillis) -> degrees east (Kotlin
    ///     `Geo::declinationDeg`, `GeomagneticField`); a throw or a non-finite answer keeps the last value.
    ///   - log: the KcnaCompass debug log (Kotlin `Log.d`); the app passes an `os.Logger`.
    ///   - elapsedMs: monotonic time for fix staleness only (never shown, so not the app clock;
    ///     Kotlin `SystemClock.elapsedRealtime`).
    ///   - scheduler: runs the "no fix yet" and calibration-hint delays.
    init(
        repo: Repository,
        router: Router,
        settings: SettingsStore,
        clock: any AppClock,
        sessionId: String,
        declinationOf: @escaping (Double, Double, Double, Int64) throws -> Double = { Geo.declinationDeg($0, $1, $2, $3) },
        log: @escaping (String) -> Void = { _ in },
        elapsedMs: @escaping () -> Int64 = DirectionsViewModel.elapsedRealtimeMs,
        scheduler: (any DirectionsScheduler)? = nil
    ) {
        self.repo = repo
        self.settings = settings
        self.clock = clock
        self.sessionId = sessionId
        self.declinationOf = declinationOf
        self.log = log
        self.elapsedMs = elapsedMs
        self.scheduler = scheduler ?? TaskDirectionsScheduler()
        let session = repo.session(sessionId)
        let room = session.flatMap { repo.roomOf($0) }
        self.session = session
        self.room = room
        target = room.flatMap { $0.hasPosition && $0.level != nil ? $0.pos : nil }
        let options = FromOptions.from(router, repo.wayfinding)
        self.options = options
        planner = RoutePlanner(router, options)
        let o = repo.wayfinding.origin
        declinationDeg = safeDeclination(o.lat0, o.lon0, DirectionsViewModel.VENUE_ALTITUDE_M)
    }

    /// The route on screen; re-planned when From changes, or (My location) when the start point
    /// changes. Nil for OFF / unknown rooms. Reading it in a view also tracks
    /// `settings.directionsFrom` and ``fix``.
    var plan: RoutePlan? {
        guard let code = room?.code, target != nil else { return nil }
        let from = settings.directionsFrom
        let f = fix
        let key = planner.planKey(from, f)
        if let c = planCache, kotlinEquals(c.key, key) { return c.plan }
        let p = planner.plan(from, code, f)
        planCache = (key, p)
        return p
    }

    var directionsFrom: String { settings.directionsFrom }

    /// Current declination in degrees east (for tests and logs).
    var declination: Double { declinationDeg }

    func setFrom(_ key: String) {
        if options.contains(key) { settings.setDirectionsFrom(key) }
    }

    /// A new location fix (Kotlin: fused location). Non-finite coordinates are ignored; a
    /// non-finite accuracy counts as 0.
    func onLocation(_ lat: Double, _ lng: Double, _ accuracyM: Double, _ altitudeM: Double?) {
        if !lat.isFinite || !lng.isFinite { return }
        let p = Geo.toLocal(lat, lng, repo.wayfinding.origin)
        declinationDeg = safeDeclination(lat, lng, altitudeM ?? DirectionsViewModel.VENUE_ALTITUDE_M)
        fixAtMs = elapsedMs()
        noFixJob?.cancel()
        setNoFix(false)
        fix = Fix(lat, lng, p.x, p.y, accuracyM.isFinite ? accuracyM.coerceAtLeast(0.0) : 0.0, altitudeM)
    }

    /// iOS: one Core Location update (``LocationReading`` from a `CLLocation`). Readings Core
    /// Location marks invalid (negative `horizontalAccuracy`) or older than
    /// ``LocationTracker/MAX_AGE_MS`` (the cached fix it delivers first) are ignored; an invalid
    /// altitude (negative `verticalAccuracy`) is passed as unknown.
    func onLocation(_ reading: LocationReading) {
        guard reading.isUsable else { return }
        onLocation(reading.latitude, reading.longitude, reading.accuracyM, reading.altitudeM)
    }

    /// A new magnetic azimuth from the rotation vector (already remapped for the display):
    /// Kotlin's entry point, kept for parity. iOS feeds Core Location headings through
    /// ``onHeading(trueHeading:magneticHeading:headingAccuracy:timeMs:)`` instead.
    func onAzimuth(_ magneticDeg: Double, _ displayId: Int, _ rotation: Int, _ timeMs: Int64) {
        if !magneticDeg.isFinite { return }
        let trueDeg = Geo.trueHeading(magneticDeg, declinationDeg)
        heading = smoother.update(trueDeg)
        if logThrottle.ready(timeMs) {
            // Kotlin: String.format(Locale.ROOT, "display=%d rotation=%d (%d°) rawAzimuth=%.1f declination=%.1f trueHeading=%.1f", …)
            let raw = CompassSensor.javaFixed1(magneticDeg)
            let decl = CompassSensor.javaFixed1(declinationDeg)
            let tru = CompassSensor.javaFixed1(trueDeg)
            let rot = CompassMath.rotationDegrees(rotation)
            log("display=\(displayId) rotation=\(rotation) (\(rot)°) rawAzimuth=\(raw) declination=\(decl) trueHeading=\(tru)")
        }
    }

    /// iOS: one `CLHeading` (`trueHeading`, `magneticHeading`, `headingAccuracy` in degrees;
    /// `timeMs` = its `timestamp` in ms, only for the log throttle). Updates the calibration hint
    /// from the accuracy (``CompassSensor/accuracyStatus(headingAccuracy:)``, in the rotation
    /// vector's place), then smooths the TRUE heading: `trueHeading` as Core Location gives it
    /// (its declination already applied), or `magneticHeading` + ``declination`` when it has no
    /// true heading (−1). An invalid reading (negative accuracy) leaves the heading as it was.
    func onHeading(trueHeading: Double, magneticHeading: Double, headingAccuracy: Double, timeMs: Int64) {
        onSensorAccuracy(CompassSensor.TYPE_ROTATION_VECTOR, CompassSensor.accuracyStatus(headingAccuracy: headingAccuracy))
        guard let t = Geo.compassTrueHeading(
            trueHeading: trueHeading, magneticHeading: magneticHeading,
            headingAccuracy: headingAccuracy, declinationDeg: declinationDeg
        ) else { return }
        heading = smoother.update(t)
        if logThrottle.ready(timeMs) {
            let tru = CompassSensor.javaFixed1(trueHeading)
            let mag = CompassSensor.javaFixed1(magneticHeading)
            let acc = CompassSensor.javaFixed1(headingAccuracy)
            let decl = CompassSensor.javaFixed1(declinationDeg)
            log("trueHeading=\(tru) magneticHeading=\(mag) accuracy=\(acc) declination=\(decl) usedHeading=\(CompassSensor.javaFixed1(t))")
        }
    }

    /// Accuracy of TYPE_MAGNETIC_FIELD or TYPE_ROTATION_VECTOR changed (``CompassSensor`` type
    /// constants, ``Calibration`` statuses). Other sensor types are ignored.
    func onSensorAccuracy(_ sensorType: Int, _ accuracy: Int) {
        switch sensorType {
        case CompassSensor.TYPE_MAGNETIC_FIELD: magAccuracy = accuracy
        case CompassSensor.TYPE_ROTATION_VECTOR: rvAccuracy = accuracy
        default: return
        }
        if !Calibration.needsHint(magAccuracy, rvAccuracy) {
            calibrateJob?.cancel()
            calibrateJob = nil
            setCalibrate(false)
        } else if !calibrate && calibrateJob?.isActive != true {
            // Sensors often report "unreliable" for a moment right after registering: wait a little.
            calibrateJob = scheduler.launch(after: DirectionsViewModel.CALIBRATE_AFTER_MS) { [weak self] in
                self?.setCalibrate(true)
            }
        }
    }

    /// Location updates started (screen visible, permission granted). A fix kept from more than
    /// ``STALE_FIX_MS`` ago is dropped, so returning to the screen later never shows an old
    /// position (a quick round trip keeps it).
    func trackingStarted() {
        noFixJob?.cancel()
        if fix != nil && elapsedMs() &- fixAtMs > DirectionsViewModel.STALE_FIX_MS { fix = nil }
        if fix != nil { return }
        noFixJob = scheduler.launch(after: DirectionsViewModel.NO_FIX_AFTER_MS) { [weak self] in
            guard let self else { return }
            if self.fix == nil { self.setNoFix(true) }
        }
    }

    func trackingStopped() {
        noFixJob?.cancel()
        noFixJob = nil
    }

    /// The location service failed or the permission vanished: show "No GPS fix yet" rather than waiting.
    func onLocationFailure() {
        if fix == nil { setNoFix(true) }
    }

    func setDeviceLocationOff(_ off: Bool) {
        if deviceLocationOff != off { deviceLocationOff = off }
    }

    // Kotlin's MutableStateFlow ignores a value equal to the current one; @Observable would not.
    private func setNoFix(_ v: Bool) {
        if noFix != v { noFix = v }
    }

    private func setCalibrate(_ v: Bool) {
        if calibrate != v { calibrate = v }
    }

    /// Declination at a point, or the last good value if the model can't answer.
    private func safeDeclination(_ lat: Double, _ lng: Double, _ altitudeM: Double) -> Double {
        let d = try? declinationOf(lat, lng, altitudeM, clock.now().epochMillis)
        if let d, d.isFinite { return d }
        return declinationDeg
    }

    /// Milliseconds of `ContinuousClock`: monotonic and counting while the device sleeps, like
    /// Android's `SystemClock.elapsedRealtime()`.
    nonisolated static func elapsedRealtimeMs() -> Int64 {
        let c = elapsedOrigin.duration(to: ContinuousClock.now).components
        return c.seconds &* 1000 &+ c.attoseconds / 1_000_000_000_000_000
    }

    private nonisolated static let elapsedOrigin = ContinuousClock.now
}
