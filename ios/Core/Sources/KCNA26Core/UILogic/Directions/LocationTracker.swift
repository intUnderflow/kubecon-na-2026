import Foundation

/// One Core Location update as the app layer reads it from a `CLLocation` (Core cannot import
/// CoreLocation). Pass only the newest location of `didUpdateLocations` (`locations.last`, Kotlin
/// `LocationResult.lastLocation`):
///
/// ```swift
/// LocationReading(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude,
///                 horizontalAccuracy: loc.horizontalAccuracy, altitude: loc.altitude,
///                 verticalAccuracy: loc.verticalAccuracy, ageSeconds: -loc.timestamp.timeIntervalSinceNow)
/// ```
///
/// `ageSeconds` is measured against the real time (`timeIntervalSinceNow`), never the app clock
/// (which may be a debug fake).
struct LocationReading: Sendable, Hashable {
    let latitude: Double
    let longitude: Double
    /// Metres; negative = the coordinate is invalid (`CLLocation.horizontalAccuracy`).
    let horizontalAccuracy: Double
    let altitude: Double
    /// Metres; negative = the altitude is invalid (`CLLocation.verticalAccuracy`).
    let verticalAccuracy: Double
    /// How old the reading is, in seconds (Core Location delivers its cached fix first).
    let ageSeconds: Double

    init(latitude: Double, longitude: Double, horizontalAccuracy: Double, altitude: Double, verticalAccuracy: Double, ageSeconds: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.altitude = altitude
        self.verticalAccuracy = verticalAccuracy
        self.ageSeconds = ageSeconds
    }

    /// Worth a fix: finite coordinates, a valid (≥ 0) horizontal accuracy, and not older than
    /// ``LocationTracker/MAX_AGE_MS`` (a reading "from the future" by clock skew counts as new).
    var isUsable: Bool {
        latitude.isFinite && longitude.isFinite && horizontalAccuracy >= 0
            && !(ageSeconds * 1000 > Double(LocationTracker.MAX_AGE_MS))
    }

    /// The accuracy radius for ``Fix/accuracyM`` (Kotlin: `loc.accuracy`, 0 without one).
    var accuracyM: Double { horizontalAccuracy >= 0 && horizontalAccuracy.isFinite ? horizontalAccuracy : 0.0 }

    /// The altitude, or nil when Core Location marks it invalid (Kotlin: `hasAltitude()`).
    var altitudeM: Double? { verticalAccuracy >= 0 && altitude.isFinite ? altitude : nil }
}

/// The pure parts of Kotlin's `LocationTracker` (fused location at high accuracy, every second,
/// only while the Directions screen is started), and how the iOS app layer replaces it with Core
/// Location.
///
/// ## iOS (app layer, CoreLocation)
///
/// - Info.plist: `NSLocationWhenInUseUsageDescription`. Ask with
///   `requestWhenInUseAuthorization()` the first time the screen opens while the status is
///   `.notDetermined` (Kotlin asks once on open); "Allow location" (``DirectionsText/ALLOW_LOCATION``)
///   opens the app's page in Settings (`UIApplication.openSettingsURLString`), and "Turn on
///   location" (``DirectionsText/TURN_ON_LOCATION``) can only open Settings too.
/// - `desiredAccuracy = kCLLocationAccuracyBest`, `distanceFilter = kCLDistanceFilterNone`,
///   `activityType = .fitness`, `pausesLocationUpdatesAutomatically = false` (Android: high
///   accuracy every ``INTERVAL_MS``; Core Location delivers about once a second when moving).
/// - Start (`startUpdatingLocation()`, then ``DirectionsViewModel/trackingStarted()``) when the
///   screen appears with the scene active and the status authorized, and on authorization
///   becoming authorized; stop (`stopUpdatingLocation()`, then
///   ``DirectionsViewModel/trackingStopped()``) when it disappears or the scene leaves `.active`.
///   Never call one twice in a row (Kotlin's `started` flag).
/// - `didUpdateLocations`: ``DirectionsViewModel/onLocation(_:)`` with a ``LocationReading`` of
///   `locations.last`, then `setDeviceLocationOff(false)`.
/// - `didFailWithError`: `CLError.denied` → ``DirectionsViewModel/onLocationFailure()`` (and stop);
///   `CLError.locationUnknown` is transient (Core Location keeps trying; the "No GPS fix yet"
///   timer covers it).
/// - Device-wide switch: `CLLocationManager.locationServicesEnabled()` (call it off the main
///   thread) → ``DirectionsViewModel/setDeviceLocationOff(_:)`` with its negation, on appear and
///   on every return to `.active` (Kotlin: on resume) and on authorization changes.
/// - The readout's status: ``locStatus(_:deviceLocationOff:noFix:)``.
enum LocationTracker {
    /// The debug log tag (Kotlin "KcnaLocation").
    static let TAG = "KcnaLocation"

    /// Android's update interval (and minimum interval), ms.
    static let INTERVAL_MS: Int64 = 1000

    /// Android's maximum delivery delay, ms.
    static let MAX_DELAY_MS: Int64 = 2000

    /// iOS: the oldest reading accepted, ms (the same as ``DirectionsViewModel/STALE_FIX_MS``: an
    /// older cached position is never shown).
    static let MAX_AGE_MS: Int64 = DirectionsViewModel.STALE_FIX_MS

    /// Core Location's authorization (`CLAuthorizationStatus`) as Core sees it.
    enum Authorization: Sendable, Hashable {
        /// `.notDetermined`: not asked yet.
        case notDetermined
        /// `.restricted` (parental controls, MDM) or `.denied` (the user said no, or location
        /// services are off device-wide).
        case denied
        /// `.authorizedWhenInUse` / `.authorizedAlways`.
        case authorized
    }

    /// Kotlin `hasLocationPermission`: fine or approximate location is granted (start tracking).
    static func hasLocationPermission(_ a: Authorization) -> Bool { a == .authorized }

    /// The readout's ``LocStatus`` on iOS: Kotlin's screen rule (``LocStatus/of(permissionGranted:permissionDenied:deviceOff:noFix:)``)
    /// with Core Location's quirk that the status reads `.denied` while location services are
    /// off device-wide: then the problem is the switch (``LocStatus/deviceOff``, "Turn on
    /// location"), not this app's permission. `deviceLocationOff` is
    /// ``DirectionsViewModel/deviceLocationOff``.
    static func locStatus(_ a: Authorization, deviceLocationOff: Bool, noFix: Bool) -> LocStatus {
        let servicesOff = deviceLocationOff
        return LocStatus.of(
            permissionGranted: a == .authorized || servicesOff,
            permissionDenied: a == .denied && !servicesOff,
            deviceOff: servicesOff,
            noFix: noFix
        )
    }
}
