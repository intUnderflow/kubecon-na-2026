import Foundation

/// Geometry of the web's mapSVG, in its 512×510 viewBox units (1 unit ≈ 1 m):
/// svgX = x + 492, svgY = 492 − y (north up). These "map units" are what the zoomable venue
/// map (SwiftUI `Canvas`) and ``MapFraming`` work in. Pure, so it is unit-tested.
///
/// Kotlin -> Swift: Compose `Float`s are `Double`s here (a `CGFloat` on Apple platforms:
/// `CGFloat(v)`), and map points are ``MapOffset``s (``toMap(_:)``).
enum MapGeometry {
    static let VIEW_W = 512.0
    static let VIEW_H = 510.0
    private static let OFFSET = 492.0

    static func svgX(_ x: Double) -> Double { x + OFFSET }
    static func svgY(_ y: Double) -> Double { OFFSET - y }

    /// A point in local metres as a map point (Kotlin VenueMap `Offset(svgX(p.x), svgY(p.y))`).
    static func toMap(_ p: PointXY) -> MapOffset { MapOffset(svgX(p.x), svgY(p.y)) }

    /// Accuracy circle radius in map units, clamped like the web: min(250, max(8, acc)).
    static func accuracyRadius(_ accuracyM: Double) -> Double { accuracyM.coerceIn(8.0, 250.0) }

    /// How a ``Label`` hangs off its point (SVG `text-anchor`): start = left-aligned, middle =
    /// centred, end = right-aligned.
    enum Anchor: Sendable, Hashable, CaseIterable {
        case start, middle, end
    }

    /// A text label at a baseline point in view units. `rotateDeg` rotates around (x, y)
    /// (positive = clockwise on screen, like SVG `rotate`).
    struct Label: Sendable, Hashable {
        let text: String
        let x: Double
        let y: Double
        let anchor: Anchor
        let rotateDeg: Double

        init(_ text: String, _ x: Double, _ y: Double, _ anchor: Anchor = .start, rotateDeg: Double = 0.0) {
            self.text = text
            self.x = x
            self.y = y
            self.anchor = anchor
            self.rotateDeg = rotateDeg
        }
    }

    /// The destination pin's level label (web: "L2").
    static func levelText(_ level: Int) -> String { "L\(level)" }

    /// Street names, placed as in the web's mapSVG.
    static let streetLabels: [Label] = [
        Label("West Temple", 498.0, 250.0, .middle, rotateDeg: 90.0),
        Label("200 South", 292.0, 505.0),
        Label("100 South", 140.0, OFFSET - 246),
        Label("South Temple", 270.0, 12.0),
        Label("200 West", 240.0, 60.0, rotateDeg: 90.0),
        Label("300 W", 2.0, 20.0),
    ]

    /// The web's short zone labels and positions (local metres), keyed by venue.json zone name.
    private static let zoneLabels: [String: (text: String, x: Double, y: Double)] = [
        "Hall DE": ("Hall DE", -182.0, 140.0),
        "Halls A–C": ("Halls A–C", -182.0, 286.0),
        "Halls 1–5": ("Halls 1–5", -455.0, 385.0),
        "Grand Ballroom": ("Ballroom", -80.0, 190.0),
        "Rooms 155 / 255": ("155·255", -210.0, 450.0),
    ]

    /// Label for a hall zone; unknown zones get the web's default spot (x0 + 4, y1 − 14).
    static func zoneLabel(_ zone: Zone) -> Label {
        let (text, lx, ly) = zoneLabels[zone.name] ?? (zone.name, zone.x0 + 4, zone.y1 - 14)
        return Label(text, svgX(lx), svgY(ly))
    }

    /// The "Hyatt" label inside the Hyatt outline.
    static let hyattLabel: Label = Label("Hyatt", svgX(-78.0), svgY(30.0))

    /// The polyline drawn by the static map layer. For a live route the first point is "me" and is
    /// drawn by the live layer from the current fix to `points[1]`; so the static part starts at 1.
    static func staticRoute(_ points: [PointXY], live: Bool) -> [PointXY] {
        live ? Array(points.dropFirst()) : points
    }

    // SVG path data from the web (24×24 icon box unless noted). Kotlin parses them with Compose's
    // `PathParser`; SwiftUI: ``SvgPath/parse(_:)`` gives absolute move/line/cubic/close commands.

    /// Heading cone around "me", 32 units long.
    static let CONE_PATH = "M0 0-11-30A32 32 0 0 1 11-30z"
    /// North rose around its centre, in a 34-unit disc.
    static let ROSE_PATH = "M0-12 5 4 0 1-5 4z"
    static let ICON_WALK = "M5 12h12M13 7l5 5-5 5"
    static let ICON_UP = "M4 19h5l7-12h4M15 7h5v5"
    static let ICON_DOWN = "M4 7h5l7 12h4M15 19h5v-5"
    static let ICON_END = "M12 21s-6-5.6-6-10a6 6 0 1 1 12 0c0 4.4-6 10-6 10z"
}
