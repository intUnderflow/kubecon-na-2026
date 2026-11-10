import Foundation

/// What a From option is; the nearest-first menu shows it as a small icon. Ordered like the
/// Kotlin enum (LIVE < ENTRANCE < ROOM), which the menu's tie-break uses.
enum FromKind: Int, Sendable, Hashable, CaseIterable, Comparable {
    case live, entrance, room

    /// Kotlin's enum `name`: "LIVE", "ENTRANCE", "ROOM".
    var name: String {
        switch self {
        case .live: "LIVE"
        case .entrance: "ENTRANCE"
        case .room: "ROOM"
        }
    }

    /// Kotlin's enum `ordinal`.
    var ordinal: Int { rawValue }

    static func < (a: FromKind, b: FromKind) -> Bool { a.rawValue < b.rawValue }
}

/// One row of the open From menu.
/// - `distanceM`: straight-line horizontal metres from the point the menu was sorted from,
///   or nil when the menu has no fix (grouped layout) or the option has no position.
struct FromMenuItem: Sendable, Hashable {
    let option: FromOption
    let distanceM: Double?

    init(_ option: FromOption, _ distanceM: Double? = nil) {
        self.option = option
        self.distanceM = distanceM
    }

    var key: String { option.key }

    /// "40 m", "1.2 km"; nil without a distance.
    var distance: String? { distanceM.map { FromMenu.distanceLabel($0) } }

    /// "L2"; nil when the level isn't known.
    var level: String? { FromMenu.levelLabel(option.level) }
}

/// A titled group of the open From menu.
struct FromMenuSection: Sendable, Hashable {
    let title: String
    let items: [FromMenuItem]

    init(_ title: String, _ items: [FromMenuItem]) {
        self.title = title
        self.items = items
    }
}

/// What the open From menu lists after "My location (GPS)" (`live`, always first).
///
/// - With a fix (`byDistance`): one section, the entrances and rooms together, nearest first by
///   straight-line horizontal distance from the fix. Distances compare as they are shown
///   (``shownMetres(_:)``: "40 m", "1.2 km"), so options showing the same distance are ordered by
///   level (lowest first), then name; an entrance comes before a room at the same spot (the Hyatt
///   lobby is both), then key.
/// - Without a fix: the grouped layout, "Entrances" in file order then "Rooms" by name, with no
///   distances.
///
/// Rooms without a usable position (OFF) are left out of both layouts; the engine's
/// ``Router/startRooms`` already excludes them. Build it once when the menu opens and keep it
/// while the menu is open (SwiftUI: `@State`, set from the fix when the menu opens), so new
/// fixes never move items under the user's finger.
struct FromMenu: Sendable, Hashable {
    let live: FromOption
    let sections: [FromMenuSection]
    let byDistance: Bool

    init(_ live: FromOption, _ sections: [FromMenuSection], byDistance: Bool) {
        self.live = live
        self.sections = sections
        self.byDistance = byDistance
    }

    /// Every row after `live`, in menu order.
    var items: [FromMenuItem] { sections.flatMap(\.items) }

    /// The menu for `options` sorted from `at` (local metres); nil or non-finite means no fix.
    static func of(_ options: FromOptions, _ at: PointXY?) -> FromMenu {
        let rooms = options.rooms.filter { isUsable($0.pos) }
        guard let at, isUsable(at) else {
            return FromMenu(
                options.live,
                [
                    FromMenuSection(DirectionsText.ENTRANCES, options.entrances.map { FromMenuItem($0) }),
                    FromMenuSection(DirectionsText.ROOMS, rooms.map { FromMenuItem($0) }),
                ],
                byDistance: false
            )
        }
        let nearest = (options.entrances + rooms)
            .map { o -> FromMenuItem in
                let d: Double? = o.pos.flatMap { p in isUsable(p) ? Geo.distance(at, p) : nil }
                return FromMenuItem(o, d)
            }
            .stableSorted(with: NEAREST_FIRST)
        return FromMenu(options.live, [FromMenuSection(DirectionsText.NEAREST, nearest)], byDistance: true)
    }

    /// Nearest first: shown distance, then level (lowest first), then name (case-insensitive),
    /// then entrances before rooms, then key. Options without a distance or a level go last.
    static let NEAREST_FIRST: KComparator<FromMenuItem> =
        KComparator<FromMenuItem>.by { $0.distanceM.map { shownMetres($0) } ?? Int64.max }
            .thenBy { $0.option.level ?? Int(Int32.max) }
            .thenBy(.caseInsensitiveOrder) { $0.option.label }
            .thenBy { $0.option.kind }
            .thenBy { $0.option.key }

    /// A distance as the menu shows it, in metres: the readout's ``Geo/r10(_:)`` (nearest 10 m, at
    /// least 10) below 1 km, else to the nearest 100 m (one decimal of a km).
    static func shownMetres(_ m: Double) -> Int64 {
        let r = Int64(Geo.r10(m))
        return r < 1000 ? r : Geo.jsRound(m / 100.0) &* 100 // Kotlin's Long multiplication wraps
    }

    /// "10 m", "40 m", "990 m", then "1.0 km", "1.2 km", "12.3 km" (always a dot, any locale).
    static func distanceLabel(_ m: Double) -> String {
        let s = shownMetres(m)
        return s < 1000 ? "\(s) m" : "\(s / 1000).\(s % 1000 / 100) km"
    }

    /// "L2"; nil for an unknown level.
    static func levelLabel(_ level: Int?) -> String? { level.map { "L\($0)" } }

    private static func isUsable(_ p: PointXY?) -> Bool {
        guard let p else { return false }
        return p.x.isFinite && p.y.isFinite
    }
}
