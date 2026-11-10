import Foundation

/// The non-drawing rules of the Directions views (Kotlin ui/directions/DirectionsScreen.kt,
/// DirectionsReadout.kt, RouteViews.kt and VenueMap.kt): the texts the composables build
/// inline, which colour a piece takes, which state shows what, and the few sizes the layout
/// computes. The SwiftUI views (ios/KCNA26/Sources/Directions) only lay out and draw.
///
/// Colours are ``PaletteRole``s and coloured lines are ``TextRun``s (see StyleRoles.swift).
enum DirectionsScreenUI {
    // MARK: - Top bar (DirectionsScreen.kt `TopBar`)

    /// "Directions · Wed 10:15–10:45 AM"; just "Directions" for an unknown session or day.
    static func topBarLabel(_ repo: Repository, _ session: Session?) -> String {
        guard let s = session else { return DirectionsText.TITLE }
        let when: String? = repo.dayOf(s).map { "\($0.dow) \(TimeFormat.range(s))" }
        return [DirectionsText.TITLE, when].compactMap { $0 }.joined(separator: " · ")
    }

    /// The session's title, or "Unknown session".
    static func title(_ session: Session?) -> String { session?.title ?? DirectionsText.UNKNOWN_SESSION }

    // MARK: - Live or not (DirectionsScreen.kt `DirectionsScreen` / `LiveDirections`)

    /// What the live map needs: the room, its position and its level.
    struct Live: Sendable, Hashable {
        let room: Room
        let target: PointXY
        let level: Int
    }

    /// The live directions' inputs, or nil for the "Unavailable" variant (unknown session, OFF,
    /// a room without a position). Kotlin: `session != null && room != null && vm.target != null`
    /// (a target implies a level).
    static func live(_ session: Session?, _ room: Room?, _ target: PointXY?) -> Live? {
        guard session != nil, let room, let target, let level = room.level else { return nil }
        return Live(room: room, target: target, level: level)
    }

    /// The "Unavailable" text: off-site events point to the official listing, other rooms have no
    /// map position.
    static func unavailableText(_ session: Session) -> String {
        session.room == "OFF" ? DirectionsText.OFF_SITE : DirectionsText.NO_POSITION
    }

    /// The map's route polyline: the plan's route, else just the room (Kotlin
    /// `route?.points ?: listOfNotNull(room.pos)`).
    static func mapPoints(_ route: Route?, _ room: Room) -> [PointXY] {
        if let route { return route.points }
        return [room.pos].compactMap { $0 }
    }

    /// The From value the picker shows: the plan's validated choice, else the stored one validated.
    static func selectedFrom(_ plan: RoutePlan?, _ options: FromOptions, _ from: String) -> String {
        plan?.from ?? options.validate(from)
    }

    // MARK: - Readout (DirectionsReadout.kt)

    /// The button under the readout while there is no fix: "Allow location" (permission denied)
    /// or "Turn on location" (device-wide location off).
    enum LocationAction: Sendable, Hashable {
        case allowLocation
        case turnOnLocation

        var label: String {
            switch self {
            case .allowLocation: DirectionsText.ALLOW_LOCATION
            case .turnOnLocation: DirectionsText.TURN_ON_LOCATION
            }
        }
    }

    /// Kotlin `LiveDirections`' `action`: none with a fix; else by the status.
    static func locationAction(_ readout: Readout, _ status: LocStatus) -> LocationAction? {
        if readout.hasFix { return nil }
        switch status {
        case .permissionDenied: return .allowLocation
        case .deviceOff: return .turnOnLocation
        case .searching, .noFix: return nil
        }
    }

    /// The readout line "120 M NORTH-EAST · ±12 M": the headline (pink when about here, else
    /// ink), then a muted " · " and the accuracy (amber when GPS is weak, else muted).
    /// Upper-cased (Barlow); VoiceOver reads ``Readout/line``.
    static func readoutRuns(_ r: Readout) -> [TextRun] {
        var runs = [TextRun(r.headline.caps(), role: r.here ? .you : .ink)]
        if let acc = r.accuracy {
            runs.append(TextRun(" · ", role: .muted))
            runs.append(TextRun(acc.caps(), role: r.weakGps != nil ? .note : .muted))
        }
        return runs
    }

    /// The readout line's font size: 32 with a position, 28 for the states ("FINDING YOU…").
    static func readoutFontSize(_ r: Readout) -> Double { r.hasFix ? 32.0 : 28.0 }

    /// The readout line's line height (Kotlin `lineHeight = 34.sp`).
    static let READOUT_LINE_HEIGHT = 34.0

    /// About here, a plain "Room is on Level 2" would repeat the pink reminder right below it; an
    /// up/down instruction (escalator, stairs) still shows.
    static func showsFloorInstruction(_ readout: Readout, _ floor: FloorReminder) -> Bool {
        !(readout.here && readout.detail != nil && floor.action == nil)
    }

    /// The detail sentence's colour: pink (and bold 16) about here, else muted (small 15).
    static func detailRole(_ r: Readout) -> PaletteRole { r.here ? .you : .muted }

    // MARK: - Floor headline (DirectionsReadout.kt `FloorHeadline`)

    /// "Salt Palace · 251 A–C" with a no-break space before a short (1–3 character) word that
    /// ends a part ("251 A–C", "Room 151"), so the headline never wraps between "251" and "A–C".
    static func headlineRest(_ reminder: FloorReminder) -> String {
        SHORT_TAIL_SPACE.replace(reminder.buildingAndRoom, "\u{00A0}")
    }

    /// "LEVEL 2 · SALT PALACE · 251 A–C": the level in pink, the rest in the line's colour (ink).
    /// VoiceOver reads ``FloorReminder/headline``.
    static func headlineRuns(_ reminder: FloorReminder) -> [TextRun] {
        let rest = headlineRest(reminder)
        var runs: [TextRun] = []
        if let level = reminder.levelLabel {
            runs.append(TextRun(level.caps(), role: .you))
            if !rest.isEmpty { runs.append(TextRun(" · ")) }
        }
        runs.append(TextRun(rest.caps()))
        return runs
    }

    /// A space before a 1–3 character word that ends a headline part ("251 A–C", "Room 151").
    private static let SHORT_TAIL_SPACE = KRegex(" (?=\\S{1,3}(?: · |$))")

    // MARK: - From picker (RouteViews.kt)

    /// "40 m · L2" under a nearest-first row; empty (no second line) without either.
    static func nearestDetails(_ item: FromMenuItem) -> String {
        [item.distance, item.level].compactMap { $0 }.joined(separator: " · ")
    }

    /// What VoiceOver reads for ``nearestDetails(_:)``: "40 m, Level 2".
    static func nearestDetailsDescription(_ item: FromMenuItem) -> String {
        [item.distance, item.option.level.map { "Level \($0)" }].compactMap { $0 }.joined(separator: ", ")
    }

    /// Spoken before a nearest-first row's name: "Entrance", "Room"; nil for "My location (GPS)",
    /// which says it already.
    static func kindDescription(_ kind: FromKind) -> String? {
        switch kind {
        case .live: nil
        case .entrance: DirectionsText.ENTRANCE
        case .room: DirectionsText.ROOM
        }
    }

    // MARK: - Steps (RouteViews.kt `StepIcon`, `StepsList`)

    /// A step icon's circle and glyph colours: up/down ink with page-colour glyphs, the end pink
    /// with white, start and walk the page colour with ink. The end pin's hole is `surface`.
    static func stepIconRoles(_ kind: StepKind) -> (background: PaletteRole, foreground: PaletteRole) {
        switch kind {
        case .up, .down: (.ink, .bg)
        case .end: (.you, .onYou)
        case .start, .walk: (.bg, .ink)
        }
    }

    /// The end step ("Room 251 A–C is on your left") is bold.
    static func stepIsBold(_ kind: StepKind) -> Bool { kind == .end }

    // MARK: - Layout (DirectionsScreen.kt `LiveDirections`)

    /// Compact: the map is about half the window high, 240–640 points (PROMPT redesign: 45–55 %).
    static func compactMapHeight(windowHeight: Double) -> Double {
        (windowHeight * 0.5).clamped(to: 240.0...640.0)
    }

    /// Wide: the two columns together are at most this wide, centred.
    static let WIDE_MAX_WIDTH = 1180.0
    /// Wide: the map column's share of the row (the readout column has the rest, 0.44).
    static let WIDE_MAP_WEIGHT = 0.56

    // MARK: - Map (VenueMap.kt)

    /// Below this zoom (points per metre) the street names would crowd a tiny venue.
    static let STREET_LABEL_MIN_Z = 0.45

    /// Street labels show unless zoomed out below ``STREET_LABEL_MIN_Z``.
    static func showsStreetLabels(_ z: Double) -> Bool { !(z < STREET_LABEL_MIN_Z) }

    /// Room (points) a label needs around it inside its zone or building.
    static let LABEL_GAP = 6.0

    /// A zone label shows only when the zone, `width` × `height` map units at zoom `z`, has room
    /// for it (label size in points) plus ``LABEL_GAP`` both ways.
    static func zoneLabelFits(width: Double, height: Double, z: Double, labelWidth: Double, labelHeight: Double) -> Bool {
        !(width * z < labelWidth + LABEL_GAP || height * z < labelHeight + LABEL_GAP)
    }

    /// The "Hyatt" label shows when the Hyatt outline (`width` map units) is wide enough for it.
    static func hyattLabelFits(width: Double, z: Double, labelWidth: Double) -> Bool {
        width * z >= labelWidth + LABEL_GAP
    }

    /// A building outline's width in map units (max x − min x); 0 for an empty outline (Kotlin's
    /// `maxOf` would throw; no data has one).
    static func outlineWidth(_ outline: [PointXY]) -> Double {
        guard let minX = outline.map(\.x).min(), let maxX = outline.map(\.x).max() else { return 0.0 }
        return maxX - minX
    }

    /// Left edge (points) of a label `width` points wide anchored at screen x `x` (SVG `text-anchor`).
    static func labelLeft(_ anchor: MapGeometry.Anchor, x: Double, width: Double) -> Double {
        switch anchor {
        case .start: x
        case .middle: x - width / 2.0
        case .end: x - width
        }
    }

    /// One cycle of the destination pin's pulse: 1.2 s while "You’re about here", else 1.8 s.
    static func pulseDurationMs(here: Bool) -> Double { here ? 1200.0 : 1800.0 }

    /// The pulse's progress (0 ..< 1) at monotonic time `t` ms: a restarting tween with Compose's
    /// `LinearOutSlowInEasing` (cubic Bézier 0, 0, 0.2, 1).
    static func pulse(atMs t: Double, here: Bool) -> Double {
        let d = pulseDurationMs(here: here)
        var phase = t.truncatingRemainder(dividingBy: d)
        if phase < 0 { phase += d }
        return MapCameraAnimation.cubicBezier(0.0, 0.0, 0.2, 1.0, phase / d)
    }

    /// The destination's ring: `radius` and `lineWidth` in points, `alpha` of the pink.
    struct Ring: Sendable, Hashable {
        let radius: Double
        let alpha: Double
        let lineWidth: Double
    }

    /// The pulse ring at progress `pulse` (web ping: scale .6 → 2.2 and fade out; stronger while
    /// "You’re about here"), or the still ring when animations are reduced (`pulse` nil).
    static func pulseRing(_ pulse: Double?, here: Bool) -> Ring {
        guard let pulse else {
            return Ring(radius: here ? 20.0 : 15.0, alpha: 0.6, lineWidth: 2.0)
        }
        let k = 0.6 + (here ? 2.6 : 1.6) * pulse
        return Ring(radius: 11.0 * k, alpha: (here ? 0.95 : 0.8) * (1.0 - pulse), lineWidth: here ? 3.0 : 2.0)
    }

    /// The destination pin's radius (points): bigger while "You’re about here".
    static func pinRadius(here: Bool) -> Double { here ? 12.0 : 10.0 }

    // MARK: - Calibration hint (DirectionsReadout.kt `FigureEight`)

    /// One trip of the phone around the figure 8.
    static let FIGURE_EIGHT_PERIOD_MS = 2400.0

    /// The figure 8's parameter (radians, 0 ..< 2π) at monotonic time `t` ms (linear, restarting).
    static func figureEightPhase(atMs t: Double) -> Double {
        var phase = t.truncatingRemainder(dividingBy: FIGURE_EIGHT_PERIOD_MS)
        if phase < 0 { phase += FIGURE_EIGHT_PERIOD_MS }
        return 2.0 * Double.pi * phase / FIGURE_EIGHT_PERIOD_MS
    }

    /// The lemniscate point at parameter `u` for half-width `a` around (`cx`, `cy`), stretched
    /// 1.3× vertically.
    static func figureEightPoint(_ u: Double, a: Double, cx: Double, cy: Double) -> MapOffset {
        let s = sin(u)
        let d = 1.0 + s * s
        return MapOffset(cx + a * cos(u) / d, cy + a * s * cos(u) / d * 1.3)
    }

    /// The closed figure 8 as `n` + 1 points (u = 0 … 2π).
    static func figureEightPath(a: Double, cx: Double, cy: Double, n: Int = 48) -> [MapOffset] {
        (0...n).map { i in figureEightPoint(2.0 * Double.pi * Double(i) / Double(n), a: a, cx: cx, cy: cy) }
    }

    /// The little phone's rotation (degrees) at `u`: along the curve, upright to its direction.
    static func figureEightPhoneDeg(_ u: Double, a: Double, cx: Double, cy: Double) -> Double {
        let p = figureEightPoint(u, a: a, cx: cx, cy: cy)
        let q = figureEightPoint(u + 0.05, a: a, cx: cx, cy: cy)
        return Geo.javaAtan2(q.y - p.y, q.x - p.x) * 180.0 / Double.pi + 90.0
    }

    // MARK: - Map camera restoration (DirectionsScreen.kt `rememberMapCameraState` saver)

    /// What the scene keeps for a Directions screen's camera: the session id, then
    /// ``MapCameraState/Saver/save(_:)``'s string.
    static func storedCamera(_ sessionId: String, _ saved: String) -> String { sessionId + "\n" + saved }

    /// The saved camera string for `sessionId` from ``storedCamera(_:_:)``'s value, or nil
    /// (nothing stored, or another session's).
    static func restoredCamera(_ sessionId: String, _ stored: String) -> String? {
        guard let cut = stored.firstIndex(of: "\n") else { return nil }
        guard kotlinEquals(String(stored[..<cut]), sessionId) else { return nil }
        return String(stored[stored.index(after: cut)...])
    }
}

/// The heading cone's angle (Kotlin VenueMap.kt `rememberConeAngle`): turns the short way round
/// (``ArrowRotation``), appears at once (snap) when the compass wakes up, then animates (a
/// critically damped spring in the view), and hides while there is no heading. One per map.
final class ConeAngleTracker {
    /// What the view does with a new heading.
    enum Update: Sendable, Hashable {
        /// No heading: hide the cone.
        case hide
        /// The first heading after none: show the cone at this angle, without animating.
        case snap(Double)
        /// Turn the shown cone to this angle (degrees, unwrapped: never more than 180° away).
        case animate(Double)
    }

    private let turns = ArrowRotation()

    /// The cone is shown.
    private(set) var visible = false

    init() {}

    /// `heading`: degrees clockwise from north, or nil (no compass yet).
    func update(_ heading: Double?) -> Update {
        guard let heading else {
            visible = false
            return .hide
        }
        let v = turns.update(heading)
        if !visible {
            visible = true
            return .snap(v)
        }
        return .animate(v)
    }
}
