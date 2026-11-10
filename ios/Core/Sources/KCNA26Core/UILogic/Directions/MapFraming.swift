import Foundation

// Kotlin uses Compose's `Offset` / `Rect` (Float) here. Core cannot use CoreGraphics types
// (Linux, and no CGFloat in the API), so these are two small Double structs with the same
// meaning; the SwiftUI layer converts with `CGPoint(x: o.x, y: o.y)` / `MapOffset(p.x, p.y)`.

/// A 2-D point or vector (Compose `Offset`): a map point in map units (``MapGeometry``: x east,
/// y south), or a screen point / drag delta in points (Android dp).
struct MapOffset: Sendable, Hashable {
    let x: Double
    let y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    init(x: Double, y: Double) {
        self.init(x, y)
    }

    static let zero = MapOffset(0.0, 0.0)

    /// Compose `offset.copy(x = …)` / `copy(y = …)`.
    func copy(x: Double? = nil, y: Double? = nil) -> MapOffset { MapOffset(x ?? self.x, y ?? self.y) }

    static func + (a: MapOffset, b: MapOffset) -> MapOffset { MapOffset(a.x + b.x, a.y + b.y) }
    static func - (a: MapOffset, b: MapOffset) -> MapOffset { MapOffset(a.x - b.x, a.y - b.y) }
    static func * (a: MapOffset, k: Double) -> MapOffset { MapOffset(a.x * k, a.y * k) }
    static func / (a: MapOffset, k: Double) -> MapOffset { MapOffset(a.x / k, a.y / k) }
}

/// An axis-aligned rectangle by its edges (Compose `Rect(left, top, right, bottom)`).
struct MapRect: Sendable, Hashable {
    let left: Double
    let top: Double
    let right: Double
    let bottom: Double

    init(_ left: Double, _ top: Double, _ right: Double, _ bottom: Double) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }

    /// Compose `Rect(topLeft, bottomRight)`.
    init(_ topLeft: MapOffset, _ bottomRight: MapOffset) {
        self.init(topLeft.x, topLeft.y, bottomRight.x, bottomRight.y)
    }

    var width: Double { right - left }
    var height: Double { bottom - top }

    /// Compose `Rect.center`: (left + width / 2, top + height / 2).
    var center: MapOffset { MapOffset(left + width / 2.0, top + height / 2.0) }
}

/// Where the map is looking. `cx`, `cy` is the point (map units, see ``MapGeometry``: x east,
/// y south, 1 unit ≈ 1 m) shown at the centre of the view, and `z` is the zoom in points per map
/// unit (Android: dp per map unit). Points keep a saved camera meaningful on any screen size.
///
/// SwiftUI `Canvas`: a map point `p` is drawn at `CGPoint(x: cam.screenX(p.x, size.width),
/// y: cam.screenY(p.y, size.height))`; lengths in map units scale by `cam.z`.
struct MapCamera: Sendable, Hashable {
    let cx: Double
    let cy: Double
    let z: Double

    init(_ cx: Double, _ cy: Double, _ z: Double) {
        self.cx = cx
        self.cy = cy
        self.z = z
    }

    init(cx: Double, cy: Double, z: Double) {
        self.init(cx, cy, z)
    }

    /// Kotlin `copy(cx =, cy =, z =)`.
    func copy(cx: Double? = nil, cy: Double? = nil, z: Double? = nil) -> MapCamera {
        MapCamera(cx ?? self.cx, cy ?? self.cy, z ?? self.z)
    }

    /// Screen x (points) of map x `u` in a view `width` points wide.
    func screenX(_ u: Double, _ width: Double) -> Double { (u - cx) * z + width / 2.0 }

    /// Screen y (points) of map y `v` in a view `height` points high.
    func screenY(_ v: Double, _ height: Double) -> Double { (v - cy) * z + height / 2.0 }

    /// Screen point of map point `p` in a `width` × `height` view.
    func screen(_ p: MapOffset, _ width: Double, _ height: Double) -> MapOffset {
        MapOffset(screenX(p.x, width), screenY(p.y, height))
    }

    /// Map x of screen x `sx` (points).
    func mapX(_ sx: Double, _ width: Double) -> Double { (sx - width / 2.0) / z + cx }

    /// Map y of screen y `sy` (points).
    func mapY(_ sy: Double, _ height: Double) -> Double { (sy - height / 2.0) / z + cy }
}

/// Space (points) kept clear on each side of the framed content, for the pin label and the map's buttons.
struct MapInsets: Sendable, Hashable {
    let left: Double
    let top: Double
    let right: Double
    let bottom: Double

    init(left: Double, top: Double, right: Double, bottom: Double) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }
}

/// Framing for the Directions map. Pure, so it is unit-tested.
///
/// - ``fit(_:_:_:pad:minSpan:)`` auto-frames the route, me and the destination, so being far
///   outside the venue fits both me and the room.
/// - ``inFrame(_:_:_:_:edge:)`` decides when me has walked out of frame (then the map re-frames).
/// - ``gesture(_:_:_:_:_:_:_:)`` and ``keepInView(_:_:_:_:edge:)`` handle pinch-zoom and pan,
///   which never push the destination off the screen.
///
/// Sizes are in points (Android dp), map coordinates in map units. ``MapCameraState`` drives
/// these for the view; a view only needs ``labelOnLeft(pinX:width:gap:labelWidth:margin:)``
/// itself.
///
/// Kotlin -> Swift: Float -> Double (so results can differ from Android's in the last
/// float digits, never by a visible amount); `min`/`max` keep Java's NaN rules and `coerceIn`
/// never traps.
enum MapFraming {
    /// Auto-framing never shows less than this many map units (≈ m) across the padded area.
    static let MIN_SPAN = 140.0

    /// Pinch-zoom stops at this many map units across the smaller side of the view.
    static let MIN_ZOOM_SPAN = 30.0

    /// Me closer than this to the view's edge (points) counts as out of frame.
    static let EDGE = 20.0

    /// The destination pin's centre always stays at least this far (points) inside the view.
    static let PIN_EDGE = 18.0

    /// Padding (points) around auto-framed content: the "L2" label fits right of a pin at the
    /// right padding, the north rose sits in the top padding, the re-fit button in the bottom.
    static let PADDING = MapInsets(left: 40.0, top: 46.0, right: 60.0, bottom: 62.0)

    /// The whole venue drawing (the web's 512×510 viewBox).
    static let VENUE = MapRect(0.0, 0.0, MapGeometry.VIEW_W, MapGeometry.VIEW_H)

    /// Bounds of the finite `points`, or nil if there are none.
    static func bounds<S: Sequence>(_ points: S) -> MapRect? where S.Element == MapOffset {
        var minX = Double.infinity
        var minY = Double.infinity
        var maxX = -Double.infinity
        var maxY = -Double.infinity
        for p in points {
            if !p.x.isFinite || !p.y.isFinite { continue }
            minX = javaMin(minX, p.x)
            minY = javaMin(minY, p.y)
            maxX = Geo.javaMax(maxX, p.x)
            maxY = Geo.javaMax(maxY, p.y)
        }
        return minX > maxX ? nil : MapRect(minX, minY, maxX, maxY)
    }

    /// What the map frames: the route, the destination and me (when there is a fix).
    static func frameBounds(_ route: [MapOffset], _ dest: MapOffset, _ me: MapOffset?) -> MapRect {
        var all = route
        all.append(dest)
        if let me { all.append(me) }
        return bounds(all) ?? MapRect(dest, dest)
    }

    /// The camera that shows `b` as large as it fits inside a `width` × `height` view with
    /// `pad` kept clear, but never closer than `minSpan` map units across the smaller side of
    /// the padded area. `b` is centred in the padded area.
    static func fit(_ b: MapRect, _ width: Double, _ height: Double, pad: MapInsets = PADDING, minSpan: Double = MIN_SPAN) -> MapCamera {
        let aw = Geo.javaMax(1.0, width - pad.left - pad.right)
        let ah = Geo.javaMax(1.0, height - pad.top - pad.bottom)
        let zMax = javaMin(aw, ah) / minSpan
        let zx = b.width > 0.0 ? aw / b.width : Double.infinity
        let zy = b.height > 0.0 ? ah / b.height : Double.infinity
        let z = javaMin(zx, javaMin(zy, zMax))
        let dx = pad.left + aw / 2.0 - width / 2.0
        let dy = pad.top + ah / 2.0 - height / 2.0
        let c = b.center
        return MapCamera(c.x - dx / z, c.y - dy / z, z)
    }

    /// True when map point `p` is on screen at least `edge` points inside the view.
    static func inFrame(_ cam: MapCamera, _ width: Double, _ height: Double, _ p: MapOffset, edge: Double = EDGE) -> Bool {
        let sx = cam.screenX(p.x, width)
        let sy = cam.screenY(p.y, height)
        return sx >= edge && sx <= width - edge && sy >= edge && sy <= height - edge
    }

    /// Moves `cam` as little as possible so map point `p` is at least `edge` points inside the view.
    static func keepInView(_ cam: MapCamera, _ width: Double, _ height: Double, _ p: MapOffset, edge: Double = PIN_EDGE) -> MapCamera {
        let hx = Geo.javaMax(0.0, width / 2.0 - edge) / cam.z
        let hy = Geo.javaMax(0.0, height / 2.0 - edge) / cam.z
        return cam.copy(cx: kotlinCoerceIn(cam.cx, p.x - hx, p.x + hx), cy: kotlinCoerceIn(cam.cy, p.y - hy, p.y + hy))
    }

    /// One pinch/pan step: the fingers' centre is at `centroid` (points) after moving `pan`
    /// points, and they spread by `zoom` (a factor, 1 = no change). The map point that was under
    /// them stays under them; the zoom is clamped to `zoomRange`.
    ///
    /// The arguments are per step, like Compose's `detectTransformGestures`: SwiftUI's
    /// `MagnifyGesture` / `DragGesture` report totals since the gesture began, so pass
    /// `magnification / lastMagnification` and `translation − lastTranslation`.
    static func gesture(
        _ cam: MapCamera,
        _ width: Double,
        _ height: Double,
        _ centroid: MapOffset,
        _ pan: MapOffset,
        _ zoom: Double,
        _ zoomRange: ClosedRange<Double>
    ) -> MapCamera {
        let factor = zoom.isFinite && zoom > 0.0 ? zoom : 1.0
        let z = (cam.z * factor).clamped(to: zoomRange)
        let ax = cam.mapX(centroid.x - pan.x, width)
        let ay = cam.mapY(centroid.y - pan.y, height)
        return MapCamera(ax - (centroid.x - width / 2.0) / z, ay - (centroid.y - height / 2.0) / z, z)
    }

    /// Pinch-zoom range: out to half the zoom that fits the framed content or the whole venue
    /// (whichever is further out), in to ``MIN_ZOOM_SPAN`` map units across.
    static func zoomRange(fitZ: Double, width: Double, height: Double) -> ClosedRange<Double> {
        let venueZ = fit(VENUE, width, height).z
        let zMin = javaMin(fitZ, venueZ) / 2.0
        let zMax = Geo.javaMax(zMin, javaMin(width, height) / MIN_ZOOM_SPAN)
        // Kotlin builds `zMin..zMax` even when a NaN size makes it empty (its coerceIn then
        // throws); a ClosedRange cannot hold that, so that case gives the 1:1 range.
        guard zMin <= zMax else { return 1.0...1.0 }
        return zMin...zMax
    }

    /// The pin's level label goes left of the pin when it would not fit on the right.
    static func labelOnLeft(pinX: Double, width: Double, gap: Double, labelWidth: Double, margin: Double = 4.0) -> Bool {
        pinX + gap + labelWidth > width - margin
    }

    /// Java `Math.min(double, double)`: NaN if either is NaN; −0.0 is less than +0.0.
    static func javaMin(_ a: Double, _ b: Double) -> Double {
        if a.isNaN { return a }
        if a == 0.0 && b == 0.0 && b.sign == .minus { return b }
        return a <= b ? a : b
    }

    /// Kotlin `Double.coerceIn(min, max)` without its exception for `min > max` (never traps):
    /// `min` if below it, `max` if above it, else the value (NaN stays NaN).
    static func kotlinCoerceIn(_ x: Double, _ lo: Double, _ hi: Double) -> Double {
        if x < lo { return lo }
        if x > hi { return hi }
        return x
    }
}
