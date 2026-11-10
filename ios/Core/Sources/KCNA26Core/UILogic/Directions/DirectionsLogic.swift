import Foundation

/// A location fix: raw `lat`/`lng` plus local metres (`x` east, `y` north of the
/// wayfinding origin) and the horizontal accuracy radius in metres.
struct Fix: Sendable, Hashable {
    let lat: Double
    let lng: Double
    let x: Double
    let y: Double
    let accuracyM: Double
    let altitudeM: Double?

    init(_ lat: Double, _ lng: Double, _ x: Double, _ y: Double, _ accuracyM: Double, _ altitudeM: Double? = nil) {
        self.lat = lat
        self.lng = lng
        self.x = x
        self.y = y
        self.accuracyM = accuracyM
        self.altitudeM = altitudeM
    }

    init(lat: Double, lng: Double, x: Double, y: Double, accuracyM: Double, altitudeM: Double? = nil) {
        self.init(lat, lng, x, y, accuracyM, altitudeM)
    }

    var pos: PointXY { PointXY(x, y) }
}

/// Why there is no position yet (only used while ``Fix`` is nil).
enum LocStatus: String, Sendable, Hashable, CaseIterable {
    /// Asking / waiting for the first fix: "Finding you…".
    case searching = "SEARCHING"

    /// No fix after a while, or the location service failed: "No GPS fix yet".
    case noFix = "NO_FIX"

    /// Permission denied: "Location is off".
    case permissionDenied = "PERMISSION_DENIED"

    /// Device-wide location switched off: "Location is off".
    case deviceOff = "DEVICE_OFF"

    /// Kotlin's enum `name`.
    var name: String { rawValue }

    /// The screen's status rule (Kotlin DirectionsScreen `LiveDirections`): denied (and not
    /// granted) first, then device-wide location off (with the permission granted), then no fix
    /// yet, else searching. On iOS use ``LocationTracker/locStatus(_:deviceLocationOff:noFix:)``,
    /// which derives `permissionGranted` / `permissionDenied` from Core Location's authorization.
    static func of(permissionGranted: Bool, permissionDenied: Bool, deviceOff: Bool, noFix: Bool) -> LocStatus {
        if !permissionGranted && permissionDenied { return .permissionDenied }
        if permissionGranted && deviceOff { return .deviceOff }
        if noFix { return .noFix }
        return .searching
    }
}

/// What the readout under the map shows (port of the web's lvPaint text states, without its
/// compass-arrow sentences: the app's Directions screen is a live map).
///
/// - `headline`: "120 m north-east", "You’re about here", "Finding you…", ...
/// - `distance`: "120 m" when a distance is shown.
/// - `direction`: "north-east" when a distance is shown.
/// - `accuracy`: "±12 m" once there is a fix.
/// - `detail`: a sentence under the line: the floor reminder when `here`, what to do when
///   there is no fix yet, otherwise nil.
/// - `weakGps`: set when accuracy is above ``DirectionsText/WEAK_GPS_M``.
/// - `here`: within max(15 m, 0.6 × accuracy) of the room.
struct Readout: Sendable, Hashable {
    let headline: String
    let distance: String?
    let direction: String?
    let accuracy: String?
    let detail: String?
    let weakGps: String?
    let here: Bool

    /// The line under the map: "120 m north-east · ±12 m", "You’re about here · ±10 m" or "Finding you…".
    var line: String { [headline, accuracy].compactMap { $0 }.joined(separator: " · ") }

    /// There is a position (so a distance or "You’re about here").
    var hasFix: Bool { accuracy != nil }
}

/// UI strings. Wording follows the original web version where it has the same thing.
///
/// iOS: the two "… in Android Settings …" sentences say "… in Settings …" (the iOS app's
/// own settings / Location Services); every other string is verbatim.
enum DirectionsText {
    static let FINDING = "Finding you…"
    static let FINDING_SUB = "Hold on a moment."
    static let NO_FIX = "No GPS fix yet"
    static let NO_FIX_SUB = "Indoors this can take a minute. A window or doorway helps."
    static let LOCATION_OFF = "Location is off"
    /// Kotlin: "Allow location for this app in Android Settings to see distance and direction."
    static let LOCATION_OFF_SUB = "Allow location for this app in Settings to see distance and direction."
    /// Kotlin: "Turn on location in Android Settings to see distance and direction."
    static let DEVICE_OFF_SUB = "Turn on location in Settings to see distance and direction."
    static let ALLOW_LOCATION = "Allow location"
    static let TURN_ON_LOCATION = "Turn on location"
    static let HERE = "You’re about here"
    static let WEAK_GPS = "GPS is weak indoors: follow the steps."
    static let FALLBACK_NOTE = Router.NO_FIX_NOTE
    static let MAP_NOTE =
        "Map is north-up; the dashed line is the walking route. Room positions come from the venue floor plans (about ±15 m)."
    static let OFF_SITE = "Off-site event. The official listing has the address and registration details."
    static let NO_POSITION = "No map position for this room."
    static let OFFICIAL_LISTING = "Official listing ↗"
    static let MY_LOCATION = "My location (GPS)"
    static let ENTRANCES = "Entrances"
    static let ROOMS = "Rooms"

    /// Header of the From menu's single list once there's a fix (not in the web, which has no fix-sorted list).
    static let NEAREST = "Nearest first"

    /// Accessibility labels of the From menu's kind icons.
    static let ENTRANCE = "Entrance"
    static let ROOM = "Room"
    static let FROM = "From"
    static let TITLE = "Directions"
    static let UNKNOWN_SESSION = "Unknown session"
    static let CALIBRATE_TITLE = "Compass needs calibrating."
    static let CALIBRATE_BODY = "Move the phone in a figure 8 a few times, away from metal."

    /// Accessibility label of the map's re-fit button (not in the web, which has no zoom).
    static let REFIT = "Fit the route on the map"

    /// Accuracy above this many metres counts as weak indoor GPS.
    static let WEAK_GPS_M = 50.0

    static func hereDetail(_ level: Int) -> String { "The room is on Level \(level); the steps below get you to the right floor." }

    /// The map's accessibility label (web mapSVG aria-label).
    static func mapDescription(_ venueCode: String?, _ level: Int) -> String {
        "Map: destination on \(venueCode == "HY" ? "Hyatt" : "Salt Palace") level \(level)"
    }
}

/// Pure helpers behind the Directions screen.
enum DirectionsLogic {
    /// Fallback start when "My location" has no fix yet, or the stored From is invalid (web: 'E200S').
    static let DEFAULT_ENTRANCE = Router.DEFAULT_ENTRANCE

    /// Port of lvPaint's text selection.
    static func readout(_ target: PointXY, _ level: Int, _ fix: Fix?, _ status: LocStatus) -> Readout {
        guard let fix else {
            let h: String
            let d: String
            switch status {
            case .permissionDenied: (h, d) = (DirectionsText.LOCATION_OFF, DirectionsText.LOCATION_OFF_SUB)
            case .deviceOff: (h, d) = (DirectionsText.LOCATION_OFF, DirectionsText.DEVICE_OFF_SUB)
            case .noFix: (h, d) = (DirectionsText.NO_FIX, DirectionsText.NO_FIX_SUB)
            case .searching: (h, d) = (DirectionsText.FINDING, DirectionsText.FINDING_SUB)
            }
            return Readout(headline: h, distance: nil, direction: nil, accuracy: nil, detail: d, weakGps: nil, here: false)
        }
        let dist = Geo.distance(fix.pos, target)
        let bearing = Geo.bearing(fix.pos, target)
        let here = Geo.isAboutHere(dist, fix.accuracyM)
        return Readout(
            headline: here ? DirectionsText.HERE : Geo.distanceLabel(dist, bearing),
            distance: here ? nil : "\(Geo.r10(dist)) m",
            direction: here ? nil : Geo.dir8(bearing),
            accuracy: accuracyText(fix.accuracyM),
            detail: here ? DirectionsText.hereDetail(level) : nil,
            weakGps: fix.accuracyM > DirectionsText.WEAK_GPS_M ? DirectionsText.WEAK_GPS : nil,
            here: here
        )
    }

    /// "±12 m" (web: Math.round(p.acc)). NaN gives "±0 m" (Kotlin's roundToInt throws).
    static func accuracyText(_ accuracyM: Double) -> String { "±\(accuracyM.coerceAtLeast(0.0).kotlinRoundToInt()) m" }
}

/// One entry of the From picker.
/// - `pos`: where it is in local metres (an entrance's node, a room's x/y); nil for "My location".
/// - `level`: its floor (the entrance node's level, the room's level); nil for "My location".
struct FromOption: Sendable, Hashable {
    let key: String
    let label: String
    let kind: FromKind
    let pos: PointXY?
    let level: Int?

    init(_ key: String, _ label: String, _ kind: FromKind, _ pos: PointXY? = nil, _ level: Int? = nil) {
        self.key = key
        self.label = label
        self.kind = kind
        self.pos = pos
        self.level = level
    }

    init(key: String, label: String, kind: FromKind, pos: PointXY? = nil, level: Int? = nil) {
        self.init(key, label, kind, pos, level)
    }
}

/// The From picker's options (web wayHTML): "My location (GPS)", then the entrances in file order,
/// then the rooms sorted by name, as the engine lists them (``Router/startEntrances``,
/// ``Router/startRooms``: so not OFF, REG or COAT). The open menu shows them through
/// ``menu(_:)``: nearest first once there is a fix, grouped like this otherwise.
///
/// Equality compares `entrances` and `rooms` (Kotlin: the data class's constructor properties).
struct FromOptions: Sendable, Hashable {
    let entrances: [FromOption]
    let rooms: [FromOption]

    /// "My location (GPS)".
    let live: FromOption = FromOption(SettingsStore.FROM_LIVE, DirectionsText.MY_LOCATION, .live)

    /// Kotlin `associateBy { it.key }` (last wins); a lookup only.
    private let byKey: [String: FromOption]

    init(entrances: [FromOption], rooms: [FromOption]) {
        self.entrances = entrances
        self.rooms = rooms
        var m: [String: FromOption] = [:]
        for o in [live] + entrances + rooms { m[o.key] = o }
        byKey = m
    }

    static func == (a: FromOptions, b: FromOptions) -> Bool { a.entrances == b.entrances && a.rooms == b.rooms }

    func hash(into hasher: inout Hasher) {
        hasher.combine(entrances)
        hasher.combine(rooms)
    }

    /// Kotlin `byKey[key]`: exact (UTF-16) key match.
    private func option(_ key: String) -> FromOption? {
        guard let o = byKey[key], kotlinEquals(o.key, key) else { return nil }
        return o
    }

    func contains(_ key: String) -> Bool { option(key) != nil }
    func label(_ key: String) -> String { option(key)?.label ?? key }

    /// The stored From value, or the 200 South entrance when it is no longer valid (web: fk='E200S').
    func validate(_ key: String) -> String { contains(key) ? key : DirectionsLogic.DEFAULT_ENTRANCE }

    /// The open menu, sorted from `at` (local metres) or grouped when there's no fix; see ``FromMenu``.
    func menu(_ at: PointXY?) -> FromMenu { FromMenu.of(self, at) }

    /// The engine's start options, with positions and levels from `wayfinding`'s nodes and the rooms.
    static func from(_ router: Router, _ wayfinding: Wayfinding) -> FromOptions {
        FromOptions(
            entrances: router.startEntrances.map { e in
                let node = wayfinding.nodes[e.node]
                return FromOption(e.key, e.name, .entrance, node?.pos, node?.level)
            },
            rooms: router.startRooms.map { FromOption($0.code, $0.name, .room, $0.pos, $0.level) }
        )
    }
}

/// The route shown on screen.
/// - `from`: the validated From choice.
/// - `startKey`: for "My location": which start the live position resolved to (web LV.key).
/// - `showFallbackNote`: "Until GPS finds you, the steps start at the 200 South entrance."
struct RoutePlan: Sendable, Hashable {
    let from: String
    let route: Route?
    let summary: String
    let showFallbackNote: Bool
    let startKey: String?
}

/// Port of the route choice in the web's wayHTML/route and the re-route rule in lvPaint.
/// Immutable and `Sendable`.
final class RoutePlanner: Sendable {
    private let router: Router
    private let options: FromOptions

    init(_ router: Router, _ options: FromOptions) {
        self.router = router
        self.options = options
    }

    func routeFrom(_ from: String, _ fix: Fix?) -> RouteFrom {
        router.resolveFrom(options.validate(from), fix.map { RouteFrom.MyLocation($0.x, $0.y, $0.accuracyM) })
    }

    /// When this key changes the route must be recomputed. For "My location" it follows the start
    /// point the live position resolves to (so the steps don't churn on every fix); otherwise it is
    /// just the From choice.
    func planKey(_ fromSetting: String, _ fix: Fix?) -> String {
        let from = options.validate(fromSetting)
        if !kotlinEquals(from, SettingsStore.FROM_LIVE) { return from }
        return "\(SettingsStore.FROM_LIVE):" + (fix.map { router.myLocationStart($0.x, $0.y).key } ?? "none")
    }

    func plan(_ fromSetting: String, _ roomCode: String, _ fix: Fix?) -> RoutePlan {
        let from = options.validate(fromSetting)
        let route = router.route(routeFrom(from, fix), roomCode)
        let live = kotlinEquals(from, SettingsStore.FROM_LIVE)
        return RoutePlan(
            from: from,
            route: route,
            summary: route.map { router.summary($0) } ?? "",
            showFallbackNote: live && route != nil && !(route?.live ?? false),
            startKey: live ? route?.start?.key : nil
        )
    }
}
