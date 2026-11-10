import SwiftUI

// Kotlin ui/directions/VenueMap.kt: the live north-up venue map. Geometry (map units, labels,
// SVG shapes), framing, pinch/pan and the camera animation are Core's (`MapGeometry`, `SvgPath`,
// `MapFraming`, `MapCameraState`); the label/pulse rules are `DirectionsScreenUI`'s. This file
// draws with `Canvas`.

extension Path {
    /// Core ``SvgPath`` commands (absolute, in the path data's own units) as a SwiftUI path
    /// (Kotlin `PathParser().parsePathString(d).toPath()`).
    init(svgCommands: [SvgPath.Command]) {
        self.init()
        for command in svgCommands {
            switch command {
            case .move(let p):
                move(to: CGPoint(x: p.x, y: p.y))
            case .line(let p):
                addLine(to: CGPoint(x: p.x, y: p.y))
            case .cubic(let c1, let c2, let p):
                addCurve(
                    to: CGPoint(x: p.x, y: p.y),
                    control1: CGPoint(x: c1.x, y: c1.y),
                    control2: CGPoint(x: c2.x, y: c2.y)
                )
            case .close:
                closeSubpath()
            }
        }
    }
}

/// The live north-up venue map, the headline of the Directions screen (a zoomable port of the
/// web's mapSVG): streets, building outlines, hall zones, the dashed walking route (on a live
/// route its first point is me), me (dot, accuracy circle, heading cone) and the destination pin
/// labelled with its level.
///
/// - `camera` auto-frames the route, me and the destination; pinch-zoom and pan switch to manual
///   until the re-fit button. The destination is never pushed off the view.
/// - Lines and labels keep a constant on-screen size at any zoom; labels have a halo in the page
///   colour so they read in light and dark, and hide when their zone is too small.
/// - Three layers (base, destination, me), so the pin's pulse and the heading cone each redraw
///   only their own `Canvas`. `heading` is read by the cone layer only (it changes many times a
///   second).
/// - The screen stops the camera's framing when it leaves (``MapCameraState/stopFraming()``),
///   not this view: a compact/wide switch replaces the map, and the new one's framing must not be
///   cancelled by the old one disappearing after it.
///
/// - Parameters:
///   - points: route polyline in local metres; for a `live` route the first point is me.
///   - here: within "You’re about here" range: the destination pin is highlighted.
///   - fix: the latest fix (me), or nil.
///   - heading: the smoothed true heading (``DirectionsViewModel/heading``), nil to hide the cone.
struct VenueMap: View {
    let venue: Venue
    let room: Room
    let points: [PointXY]
    let live: Bool
    let here: Bool
    let fix: Fix?
    let heading: () -> Double?
    let camera: MapCameraState

    @Environment(\.appColors) private var colors
    /// The running gestures' last values (a plain box: updating it must not re-render the map).
    @State private var tracks = GestureTracks()

    init(
        venue: Venue,
        room: Room,
        points: [PointXY],
        live: Bool,
        here: Bool,
        fix: Fix?,
        heading: @escaping () -> Double?,
        camera: MapCameraState
    ) {
        self.venue = venue
        self.room = room
        self.points = points
        self.live = live
        self.here = here
        self.fix = fix
        self.heading = heading
        self.camera = camera
    }

    var body: some View {
        if let pos = room.pos, let level = room.level {
            map(dest: MapGeometry.toMap(pos), level: level)
        }
    }

    @ViewBuilder
    private func map(dest: MapOffset, level: Int) -> some View {
        // The drawn polyline; for a live route the leg from me is drawn from the current fix.
        let route: [MapOffset] = MapGeometry.staticRoute(points, live: live).map { MapGeometry.toMap($0) }
        let start: MapOffset? = live ? nil : route.first
        let me: MapOffset? = fix.map { MapOffset(MapGeometry.svgX($0.x), MapGeometry.svgY($0.y)) }
        let base: MapBaseModel = MapBaseModel(venue: venue, route: route, start: start)
        let leg: MapOffset? = live && !route.isEmpty ? me : nil
        let shape = RoundedRectangle(cornerRadius: 14, style: .circular)
        GeometryReader { geo in
            let w: Double = Double(geo.size.width)
            let h: Double = Double(geo.size.height)
            // Used only until the camera has run once (the first frame).
            let initial: MapCamera = MapFraming.fit(MapFraming.frameBounds(route, dest, me), w, h)
            TimelineView(.animation(paused: !camera.isAnimating)) { _ in
                let cam: MapCamera = camera.camera ?? initial
                ZStack {
                    MapBaseLayer(model: base, cam: cam, me: leg)
                    MapDestinationLayer(cam: cam, dest: dest, level: level, here: here)
                    MapMeLayer(cam: cam, fix: fix, heading: heading)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(transformGesture(w, h, route, dest, me))
            .onAppear {
                camera.frame(w, h, route, dest, me)
            }
            .onChange(of: MapFrameKey(width: w, height: h, route: route, dest: dest)) { _, _ in
                camera.frame(w, h, route, dest, me)
            }
            .onChange(of: me) { _, now in
                camera.updateMe(now)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: DirectionsText.mapDescription(room.venueCode, level)))
        .overlay(alignment: .topTrailing) {
            NorthRose()
                .padding(8)
        }
        .overlay(alignment: .bottomTrailing) {
            RefitButton { camera.refit() }
                .padding(6)
        }
        .background(colors.bg)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(colors.line, lineWidth: 1)
        }
    }

    // MARK: - Pinch and pan (Kotlin `detectTransformGestures` -> `camera.onGesture`)

    /// SwiftUI reports totals since a gesture began; `MapCameraState.onGesture` wants per-step
    /// values like Compose's `detectTransformGestures` (`pan` = Δtranslation, `zoom` =
    /// magnification / last magnification, `centroid` = the fingers' centre now). The first drag
    /// event only starts tracking: Compose drops the touch-slop movement too, and a tap never
    /// switches the camera to manual.
    private func transformGesture(
        _ w: Double,
        _ h: Double,
        _ route: [MapOffset],
        _ dest: MapOffset,
        _ me: MapOffset?
    ) -> some Gesture {
        let drag = DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { v in
                let previous: DragTrack? = tracks.drag.flatMap { $0.start == v.startLocation ? $0 : nil }
                tracks.drag = DragTrack(start: v.startLocation, translation: v.translation, location: v.location)
                guard let previous else { return }
                let dx: Double = Double(v.translation.width - previous.translation.width)
                let dy: Double = Double(v.translation.height - previous.translation.height)
                if dx == 0 && dy == 0 { return }
                let centroid = MapOffset(Double(v.location.x), Double(v.location.y))
                camera.onGesture(w, h, centroid, MapOffset(dx, dy), 1.0, route, dest, me)
            }
            .onEnded { _ in
                tracks.drag = nil
            }
        let pinch = MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { v in
                let previous: PinchTrack? = tracks.pinch.flatMap { $0.start == v.startLocation ? $0 : nil }
                let dragNow: CGSize = tracks.drag?.translation ?? .zero
                let dragAtStart: CGSize = previous?.dragAtStart ?? dragNow
                tracks.pinch = PinchTrack(start: v.startLocation, magnification: v.magnification, dragAtStart: dragAtStart)
                let last: CGFloat = previous?.magnification ?? 1
                guard last > 0 else { return }
                let zoom: Double = Double(v.magnification / last)
                let cx: Double = Double(v.startLocation.x + dragNow.width - dragAtStart.width)
                let cy: Double = Double(v.startLocation.y + dragNow.height - dragAtStart.height)
                camera.onGesture(w, h, MapOffset(cx, cy), MapOffset.zero, zoom, route, dest, me)
            }
            .onEnded { _ in
                tracks.pinch = nil
            }
        return drag.simultaneously(with: pinch)
    }
}

/// One drag gesture's last translation and location (`start` tells gestures apart, so a
/// cancelled one that never ended can't leak into the next).
private struct DragTrack: Equatable {
    let start: CGPoint
    let translation: CGSize
    let location: CGPoint
}

/// One pinch's last magnification, and the drag translation when it began (the fingers' centre
/// moves with the drag).
private struct PinchTrack: Equatable {
    let start: CGPoint
    let magnification: CGFloat
    let dragAtStart: CGSize
}

/// The map's gesture tracking, kept out of SwiftUI's state so a gesture step re-renders only
/// what the camera change redraws.
private final class GestureTracks {
    var drag: DragTrack?
    var pinch: PinchTrack?
}

/// What restarts the camera's framing (Kotlin `LaunchedEffect(camera, w, h, route, dest)`).
private struct MapFrameKey: Equatable {
    let width: Double
    let height: Double
    let route: [MapOffset]
    let dest: MapOffset
}

/// Shapes parsed once.
private enum MapPaths {
    /// The heading cone, 32 units long, pointing up from (0, 0).
    static let cone = Path(svgCommands: SvgPath.parse(MapGeometry.CONE_PATH))
    /// The north rose around its centre.
    static let rose = Path(svgCommands: SvgPath.parse(MapGeometry.ROSE_PATH))
}

/// Map text (web `.map text`): Barlow, 0.04 em, upper-cased by the caller; constant on-screen
/// size at any zoom (it still follows Dynamic Type, as Kotlin's sp follow the font scale).
private enum MapText {
    static let street: AppTextStyle = label(12)
    static let zone: AppTextStyle = label(12.5)
    /// The pin's "L2": white on pink, big enough to read at a glance in light and dark.
    static let pin: AppTextStyle = label(16, .bold).copy(letterSpacing: 0.06)
    static let rose: AppTextStyle = label(10, .bold)

    private static func label(_ size: CGFloat, _ weight: AppFontWeight = .semibold) -> AppTextStyle {
        var style: AppTextStyle = AppTextStyle.barlow(size, weight, spacing: 0.04)
        style.tabularNumbers = false
        return style
    }

    static func text(_ s: String, _ style: AppTextStyle) -> Text {
        Text(verbatim: s).font(style.font).tracking(style.tracking)
    }

    /// Offsets of the halo copies (Kotlin: a 3 dp round-joined stroke behind the fill).
    static let halo: [CGSize] = {
        let r: CGFloat = 1.5
        let d: CGFloat = r * 0.7071
        return [
            CGSize(width: r, height: 0), CGSize(width: -r, height: 0), CGSize(width: 0, height: r), CGSize(width: 0, height: -r),
            CGSize(width: d, height: d), CGSize(width: -d, height: d), CGSize(width: d, height: -d), CGSize(width: -d, height: -d),
        ]
    }()

    static let unbounded = CGSize(width: 10_000, height: 10_000)
}

/// The base layer's geometry in map units (Kotlin `MapBase`).
private struct MapBaseModel: Sendable {
    let streets: [(from: MapOffset, to: MapOffset)]
    let saltPalace: [MapOffset]?
    let hyatt: [MapOffset]?
    let hyattWidth: Double
    let zones: [(rect: MapRect, label: MapGeometry.Label)]
    let route: [MapOffset]
    let start: MapOffset?

    init(venue: Venue, route: [MapOffset], start: MapOffset?) {
        streets = venue.streets.map { (from: MapGeometry.toMap($0.from), to: MapGeometry.toMap($0.to)) }
        saltPalace = venue.buildings["SP"].map { b in b.outline.map { MapGeometry.toMap($0) } }
        let hy: Building? = venue.buildings["HY"]
        hyatt = hy.map { b in b.outline.map { MapGeometry.toMap($0) } }
        hyattWidth = hy.map { DirectionsScreenUI.outlineWidth($0.outline) } ?? 0
        zones = venue.zones.map { z in
            let rect = MapRect(MapGeometry.svgX(z.x0), MapGeometry.svgY(z.y1), MapGeometry.svgX(z.x1), MapGeometry.svgY(z.y0))
            return (rect: rect, label: MapGeometry.zoneLabel(z))
        }
        self.route = route
        self.start = start
    }
}

/// Screen-space helpers for one camera in a `size` view.
private struct MapProjection {
    let cam: MapCamera
    let width: Double
    let height: Double

    init(_ cam: MapCamera, _ size: CGSize) {
        self.cam = cam
        width = Double(size.width)
        height = Double(size.height)
    }

    func point(_ p: MapOffset) -> CGPoint {
        CGPoint(x: cam.screenX(p.x, width), y: cam.screenY(p.y, height))
    }

    func polyline(_ points: [MapOffset], closed: Bool) -> Path {
        var path = Path()
        for (i, p) in points.enumerated() {
            if i == 0 { path.move(to: point(p)) } else { path.addLine(to: point(p)) }
        }
        if closed { path.closeSubpath() }
        return path
    }

    func rect(_ r: MapRect) -> CGRect {
        let topLeft = point(MapOffset(r.left, r.top))
        return CGRect(x: topLeft.x, y: topLeft.y, width: CGFloat(r.width * cam.z), height: CGFloat(r.height * cam.z))
    }
}

private func circlePath(_ c: CGPoint, _ r: CGFloat) -> Path {
    Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
}

/// Draws `text` with its baseline at screen point `at`, anchored like SVG `text-anchor`, rotated
/// by `rotateDeg` around `at`, with a halo of `halo` behind it.
private func drawHaloText(
    _ ctx: GraphicsContext,
    _ resolved: GraphicsContext.ResolvedText,
    at: CGPoint,
    anchor: MapGeometry.Anchor,
    rotateDeg: Double,
    color: Color,
    halo: Color
) {
    let size: CGSize = resolved.measure(in: MapText.unbounded)
    let baseline: CGFloat = resolved.firstBaseline(in: size)
    let left: CGFloat = CGFloat(DirectionsScreenUI.labelLeft(anchor, x: Double(at.x), width: Double(size.width)))
    let rect = CGRect(x: left, y: at.y - baseline, width: size.width, height: size.height)
    var c = ctx
    if rotateDeg != 0 {
        c.translateBy(x: at.x, y: at.y)
        c.rotate(by: .degrees(rotateDeg))
        c.translateBy(x: -at.x, y: -at.y)
    }
    var text = resolved
    text.shading = .color(halo)
    for o in MapText.halo {
        c.draw(text, in: rect.offsetBy(dx: o.width, dy: o.height))
    }
    text.shading = .color(color)
    c.draw(text, in: rect)
}

/// Layer 1: streets, buildings, zones, labels, the route and (live) the leg from me.
private struct MapBaseLayer: View {
    let model: MapBaseModel
    let cam: MapCamera
    /// Set for a live route: the dashed leg from me to the route's first node.
    let me: MapOffset?

    @Environment(\.appColors) private var colors

    var body: some View {
        let colors = self.colors
        let model = self.model
        let cam = self.cam
        let me = self.me
        Canvas { ctx, size in
            drawMapBase(&ctx, size, model, cam, me, colors)
        }
    }
}

/// Draws layer 1 (Kotlin `MapBase.draw`). A free function: Canvas may call its renderer off the
/// main actor.
private func drawMapBase(
    _ ctx: inout GraphicsContext,
    _ size: CGSize,
    _ m: MapBaseModel,
    _ cam: MapCamera,
    _ me: MapOffset?,
    _ colors: AppColors
) {
    let proj = MapProjection(cam, size)
    let z: Double = cam.z

    // Streets: 6 m wide, at least 3 pt.
    let streetStyle = StrokeStyle(lineWidth: CGFloat(max(6.0 * z, 3.0)), lineCap: .round)
    for s in m.streets {
        var p = Path()
        p.move(to: proj.point(s.from))
        p.addLine(to: proj.point(s.to))
        ctx.stroke(p, with: .color(colors.line), style: streetStyle)
    }
    if let sp = m.saltPalace {
        let p = proj.polyline(sp, closed: true)
        ctx.fill(p, with: .color(colors.surface))
        ctx.stroke(p, with: .color(colors.muted), lineWidth: 1.5)
    }
    if let hy = m.hyatt {
        let p = proj.polyline(hy, closed: true)
        ctx.fill(p, with: .color(colors.mapHyatt))
        ctx.stroke(p, with: .color(colors.muted), lineWidth: 1.5)
    }
    let zoneStyle = StrokeStyle(lineWidth: 1.2, dash: [4, 3])
    for zone in m.zones {
        ctx.stroke(Path(proj.rect(zone.rect)), with: .color(colors.line), style: zoneStyle)
    }

    // The route: a light casing, then the dashed ink line (web .ln).
    let casing = StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
    let line = StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [7, 5])
    let casingColor: Color = colors.surface.opacity(0.85)
    var leg: Path?
    if let me, let first = m.route.first {
        var p = Path()
        p.move(to: proj.point(me))
        p.addLine(to: proj.point(first))
        leg = p
    }
    let routePath: Path? = m.route.count >= 2 ? proj.polyline(m.route, closed: false) : nil
    if let leg { ctx.stroke(leg, with: .color(casingColor), style: casing) }
    if let routePath { ctx.stroke(routePath, with: .color(casingColor), style: casing) }
    if let leg { ctx.stroke(leg, with: .color(colors.ink), style: line) }
    if let routePath { ctx.stroke(routePath, with: .color(colors.ink), style: line) }
    if let start = m.start {
        let dot = circlePath(proj.point(start), 7)
        ctx.fill(dot, with: .color(colors.ink))
        ctx.stroke(dot, with: .color(colors.surface), lineWidth: 3)
    }

    // Labels: constant size, hidden when there is no room for them.
    if DirectionsScreenUI.showsStreetLabels(z) {
        for label in MapGeometry.streetLabels {
            let text = ctx.resolve(MapText.text(label.text.caps(), MapText.street))
            drawHaloText(
                ctx, text, at: proj.point(MapOffset(label.x, label.y)), anchor: label.anchor,
                rotateDeg: label.rotateDeg, color: colors.muted, halo: colors.bg
            )
        }
    }
    for zone in m.zones {
        let text = ctx.resolve(MapText.text(zone.label.text.caps(), MapText.zone))
        let labelSize: CGSize = text.measure(in: MapText.unbounded)
        let fits: Bool = DirectionsScreenUI.zoneLabelFits(
            width: zone.rect.width, height: zone.rect.height, z: z,
            labelWidth: Double(labelSize.width), labelHeight: Double(labelSize.height)
        )
        if !fits { continue }
        drawHaloText(
            ctx, text, at: proj.point(MapOffset(zone.label.x, zone.label.y)), anchor: zone.label.anchor,
            rotateDeg: 0, color: colors.muted, halo: colors.surface
        )
    }
    if m.hyatt != nil {
        let label: MapGeometry.Label = MapGeometry.hyattLabel
        let text = ctx.resolve(MapText.text(label.text.caps(), MapText.zone))
        let labelSize: CGSize = text.measure(in: MapText.unbounded)
        if DirectionsScreenUI.hyattLabelFits(width: m.hyattWidth, z: z, labelWidth: Double(labelSize.width)) {
            drawHaloText(
                ctx, text, at: proj.point(MapOffset(label.x, label.y)), anchor: label.anchor,
                rotateDeg: 0, color: colors.muted, halo: colors.mapHyatt
            )
        }
    }
}

/// Layer 2: the destination pin (web .dst), its pulse (.pulse) and the "L2" label pill. The
/// pulse runs on its own timeline; with Reduce Motion a still ring replaces it.
private struct MapDestinationLayer: View {
    let cam: MapCamera
    let dest: MapOffset
    let level: Int
    let here: Bool

    @Environment(\.appColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let colors = self.colors
        let cam = self.cam
        let dest = self.dest
        let level = self.level
        let here = self.here
        TimelineView(.animation(paused: reduceMotion)) { context in
            let pulse: Double? = reduceMotion
                ? nil
                : DirectionsScreenUI.pulse(atMs: context.date.timeIntervalSinceReferenceDate * 1000, here: here)
            Canvas { ctx, size in
                drawMapDestination(&ctx, size, cam, dest, level, here, pulse, colors)
            }
        }
    }
}

/// Draws layer 2 (Kotlin `drawDestination`).
private func drawMapDestination(
    _ ctx: inout GraphicsContext,
    _ size: CGSize,
    _ cam: MapCamera,
    _ dest: MapOffset,
    _ level: Int,
    _ here: Bool,
    _ pulse: Double?,
    _ colors: AppColors
) {
    let proj = MapProjection(cam, size)
    let c: CGPoint = proj.point(dest)
    if here {
        ctx.fill(circlePath(c, 26), with: .color(colors.you.opacity(0.18)))
    }
    let ring = DirectionsScreenUI.pulseRing(pulse, here: here)
    ctx.stroke(
        circlePath(c, CGFloat(ring.radius)),
        with: .color(colors.you.opacity(ring.alpha)),
        lineWidth: CGFloat(ring.lineWidth)
    )
    let r: CGFloat = CGFloat(DirectionsScreenUI.pinRadius(here: here))
    let pin = circlePath(c, r)
    ctx.fill(pin, with: .color(colors.you))
    ctx.stroke(pin, with: .color(colors.surface), lineWidth: 3)

    var label = ctx.resolve(MapText.text(MapGeometry.levelText(level), MapText.pin))
    label.shading = .color(colors.onYou)
    let labelSize: CGSize = label.measure(in: MapText.unbounded)
    let padX: CGFloat = 6
    let padY: CGFloat = 3
    let pillW: CGFloat = labelSize.width + 2 * padX
    let pillH: CGFloat = labelSize.height + 2 * padY
    let gap: CGFloat = r + 6
    let onLeft: Bool = MapFraming.labelOnLeft(
        pinX: Double(c.x), width: Double(size.width), gap: Double(gap), labelWidth: Double(pillW), margin: 4
    )
    let left: CGFloat = onLeft ? c.x - gap - pillW : c.x + gap
    let top: CGFloat = c.y - pillH / 2
    ctx.fill(
        Path(roundedRect: CGRect(x: left - 1.5, y: top - 1.5, width: pillW + 3, height: pillH + 3), cornerRadius: 7.5),
        with: .color(colors.surface)
    )
    ctx.fill(Path(roundedRect: CGRect(x: left, y: top, width: pillW, height: pillH), cornerRadius: 6), with: .color(colors.you))
    ctx.draw(label, in: CGRect(x: left + padX, y: top + padY, width: labelSize.width, height: labelSize.height))
}

/// Layer 3: me (web #me): accuracy circle in metres, heading cone (once there is a heading), dot.
/// The cone's angle (Kotlin `rememberConeAngle`): the short way round (Core's
/// ``ConeAngleTracker``), at once when it appears, then a critically damped spring (Compose
/// `spring(dampingRatio = 1f, stiffness = 300f)`).
private struct MapMeLayer: View {
    let cam: MapCamera
    let fix: Fix?
    let heading: () -> Double?

    @State private var tracker = ConeAngleTracker()
    @State private var cone: Double = 0
    @State private var coneVisible = false

    /// Compose `spring(dampingRatio = 1f, stiffness = 300f)` (mass 1).
    private static let coneSpring: Animation = .interpolatingSpring(
        mass: 1, stiffness: 300, damping: 2 * 300.0.squareRoot(), initialVelocity: 0
    )

    var body: some View {
        MapMeCanvas(cam: cam, fix: fix, coneVisible: coneVisible, cone: cone)
            .onChange(of: heading(), initial: true) { _, h in
                switch tracker.update(h) {
                case .hide:
                    coneVisible = false
                case .snap(let v):
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) {
                        cone = v
                        coneVisible = true
                    }
                case .animate(let v):
                    withAnimation(MapMeLayer.coneSpring) {
                        cone = v
                    }
                }
            }
    }
}

/// Draws layer 3; `cone` (degrees clockwise from north) is animatable.
private struct MapMeCanvas: View, Animatable {
    let cam: MapCamera
    let fix: Fix?
    let coneVisible: Bool
    var cone: Double

    @Environment(\.appColors) private var colors

    var animatableData: Double {
        get { cone }
        set { cone = newValue }
    }

    var body: some View {
        let colors = self.colors
        let cam = self.cam
        let fix = self.fix
        let cone: Double? = coneVisible ? self.cone : nil
        Canvas { ctx, size in
            guard let f = fix else { return }
            let proj = MapProjection(cam, size)
            let c: CGPoint = proj.point(MapOffset(MapGeometry.svgX(f.x), MapGeometry.svgY(f.y)))
            let me: Color = colors.mapMe
            let r: CGFloat = CGFloat(MapGeometry.accuracyRadius(f.accuracyM) * cam.z)
            let accuracy = circlePath(c, r)
            ctx.fill(accuracy, with: .color(me.opacity(0.14)))
            ctx.stroke(accuracy, with: .color(me.opacity(0.45)), lineWidth: 1.5)
            if let cone {
                let k: CGFloat = 40.0 / 32.0
                var coneCtx = ctx
                coneCtx.translateBy(x: c.x, y: c.y)
                coneCtx.rotate(by: .degrees(cone))
                coneCtx.scaleBy(x: k, y: k)
                coneCtx.fill(MapPaths.cone, with: .color(me.opacity(0.4)))
            }
            let dot = circlePath(c, 8)
            ctx.fill(dot, with: .color(me))
            ctx.stroke(dot, with: .color(colors.surface), lineWidth: 3)
        }
    }
}

/// Kotlin `NorthRose`: the small "N" rose in the top-right corner (the map is always north-up).
private struct NorthRose: View {
    @Environment(\.appColors) private var colors

    var body: some View {
        let colors = self.colors
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r: CGFloat = min(size.width, size.height) / 2
            ctx.fill(circlePath(c, r), with: .color(colors.surface))
            ctx.stroke(circlePath(c, r - 0.5), with: .color(colors.line), lineWidth: 1)
            let k: CGFloat = min(size.width, size.height) / 34
            var rose = ctx
            rose.translateBy(x: c.x, y: c.y - 2)
            rose.scaleBy(x: k, y: k)
            rose.fill(MapPaths.rose, with: .color(colors.you))
            var n = ctx.resolve(MapText.text("N", MapText.rose))
            n.shading = .color(colors.ink)
            let nSize: CGSize = n.measure(in: MapText.unbounded)
            let baseline: CGFloat = n.firstBaseline(in: nSize)
            ctx.draw(n, in: CGRect(x: c.x - nSize.width / 2, y: c.y + 13 - baseline, width: nSize.width, height: nSize.height))
        }
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
    }
}

/// Kotlin `RefitButton`: back to auto-framing (48 pt, surface, hairline, a light shadow).
private struct RefitButton: View {
    let onClick: () -> Void

    @Environment(\.appColors) private var colors

    var body: some View {
        Button(action: onClick) {
            AppIconImage(.fitScreen, size: 22)
                .foregroundStyle(colors.ink)
                .frame(width: 48, height: 48)
                .background {
                    // Material `shadowElevation = 2.dp`.
                    Circle()
                        .fill(colors.surface)
                        .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                }
                .overlay {
                    Circle().strokeBorder(colors.line, lineWidth: 1)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: DirectionsText.REFIT))
    }
}
