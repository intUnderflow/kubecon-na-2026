import Foundation
import Observation

/// The Directions map's camera.
///
/// - **Following** (the default): the map frames the route, me and the destination
///   (``MapFraming/fit(_:_:_:pad:minSpan:)``), re-framing smoothly when the route changes or I
///   walk out of frame.
/// - **Manual**: after a pinch or pan the camera stays where the user put it (the destination
///   pin never leaves the view) until ``refit()``.
///
/// Saved with ``Saver`` (a string for `@SceneStorage`) so the mode survives a scene being
/// recreated: a following camera re-fits the new screen, a manual one keeps its centre and zoom
/// (in points per metre).
///
/// ## Driving it from SwiftUI
///
/// Kotlin runs `frame(...)` in a `LaunchedEffect(camera, w, h, route, dest)` that also watches
/// `me`; Compose's `animate` moves `camera` every frame. Here the view calls the same rules
/// explicitly and draws inside a `TimelineView` while an animation runs:
///
/// ```swift
/// @State private var cam = MapCameraState()          // or MapCameraState.Saver.restore(saved) ?? MapCameraState()
/// GeometryReader { geo in
///     let w = geo.size.width, h = geo.size.height
///     TimelineView(.animation(paused: !cam.isAnimating)) { _ in
///         Canvas { ctx, size in
///             let c = cam.camera ?? MapFraming.fit(MapFraming.frameBounds(route, dest, me), w, h)  // before the first frame
///             … draw with c.screenX / c.screenY / c.z …
///         }
///     }
///     .onAppear { cam.frame(w, h, route, dest, me) }
///     .onChange(of: FrameKey(w, h, route, dest)) { cam.frame(w, h, route, dest, me) }   // restart (Kotlin LaunchedEffect keys)
///     .onChange(of: me) { cam.updateMe(me) }
///     .onDisappear { cam.stopFraming() }
///     .gesture(…) { cam.onGesture(w, h, centroid, pan, zoom, route, dest, me) }   // per-step values, see MapFraming.gesture
/// }
/// Button(DirectionsText.REFIT) { cam.refit() }
/// ```
///
/// `route`, `dest` and `me` are map points (``MapGeometry/toMap(_:)``; the route drawn by the
/// static layer: ``MapGeometry/staticRoute(_:live:)``). ``camera`` is computed from the
/// monotonic clock while an animation runs, so reading it inside the `TimelineView` gives the
/// value for that display frame; ``isAnimating`` turns false (observably) when it ends.
@MainActor
@Observable
final class MapCameraState {
    /// Re-framing animation length (Compose `tween(FRAME_MS, easing = FastOutSlowInEasing)`).
    nonisolated static let FRAME_MS = 650

    /// Auto-framing is on.
    private(set) var follow: Bool

    /// The camera when no animation runs (where the last one ended or was stopped).
    private var resting: MapCamera?

    /// The running re-framing animation, if any.
    private(set) var animation: MapCameraAnimation?

    @ObservationIgnored private var refits = 0
    @ObservationIgnored private let nowMs: () -> Double
    @ObservationIgnored private var framing: Framing?
    @ObservationIgnored private var settle: Task<Void, Never>?

    /// The view size framing last ran for (points); a change means snap, not animate.
    @ObservationIgnored private var viewport: (Double, Double)?

    /// The inputs of the running `frame` (Kotlin: the `frame` coroutine's parameters and locals).
    private struct Framing {
        let width: Double
        let height: Double
        let route: [MapOffset]
        let dest: MapOffset
        var me: MapOffset?
        var first = true
        var seenRefits: Int
        let resized: Bool
    }

    /// `follow` false needs a `camera` to stay put; `MapCameraState()` is Kotlin's
    /// `rememberMapCameraState()` (following, no camera until the map is laid out). `nowMs` is a
    /// monotonic clock in milliseconds for the animation (never the app clock).
    init(_ follow: Bool = true, _ camera: MapCamera? = nil, nowMs: @escaping () -> Double = MapCameraState.monotonicMs) {
        self.follow = follow
        resting = camera
        self.nowMs = nowMs
    }

    /// What the map shows (mid-animation: the value now); nil until the map has been laid out once.
    var camera: MapCamera? { camera(atMs: nowMs()) }

    /// What the map shows at monotonic time `t` (ms, the `nowMs` clock).
    func camera(atMs t: Double) -> MapCamera? {
        if let a = animation { return a.value(atMs: t) }
        return resting
    }

    /// A re-framing animation is running (drive a `TimelineView(.animation)` while true).
    var isAnimating: Bool { animation != nil }

    /// Where the running animation is heading (nil when idle).
    private var goal: MapCamera? { animation?.to }

    /// Back to auto-framing, animated (the re-fit button; also a new From choice).
    func refit() {
        follow = true
        refits += 1
        evaluate() // Kotlin: the snapshotFlow sees `refits` change
    }

    /// Starts framing for a `width` × `height` view showing `route` and `dest` (map units), with
    /// me at `me` (or nil without a fix). Call it when the map appears and again whenever the
    /// view size, the route or the destination changes (Kotlin restarts its `frame` coroutine on
    /// those keys); between those calls report `me` with ``updateMe(_:)``.
    func frame(_ width: Double, _ height: Double, _ route: [MapOffset], _ dest: MapOffset, _ me: MapOffset?) {
        cancelFraming()
        let resized = viewport.map { $0.0 != width || $0.1 != height } ?? true
        viewport = (width, height)
        framing = Framing(width: width, height: height, route: route, dest: dest, me: me, seenRefits: refits, resized: resized)
        evaluate()
    }

    /// My position (map units) changed, or nil when the fix is gone. No-op unless framing runs
    /// or when it equals the last one (Kotlin's snapshotFlow only emits changes).
    func updateMe(_ me: MapOffset?) {
        guard var f = framing, f.me != me else { return }
        f.me = me
        framing = f
        evaluate()
    }

    /// The map left the screen (Kotlin: the `frame` coroutine is cancelled). A running animation
    /// stops where it is.
    func stopFraming() {
        cancelFraming()
    }

    /// One pinch/pan step in points (see ``MapFraming/gesture(_:_:_:_:_:_:_:)``); switches to
    /// manual. Ignored before the first ``frame(_:_:_:_:_:)`` gave the map a camera.
    func onGesture(
        _ width: Double,
        _ height: Double,
        _ centroid: MapOffset,
        _ pan: MapOffset,
        _ zoom: Double,
        _ route: [MapOffset],
        _ dest: MapOffset,
        _ me: MapOffset?
    ) {
        guard let cam = camera else { return }
        stop()
        let wasFollowing = follow
        follow = false
        let range = MapFraming.zoomRange(fitZ: fitFor(route, dest, me, width, height).z, width: width, height: height)
        let moved = MapFraming.gesture(cam, width, height, centroid, pan, zoom, range)
        resting = MapFraming.keepInView(moved, width, height, dest)
        if wasFollowing { evaluate() } // Kotlin: the snapshotFlow sees `follow` change
    }

    /// One emission of Kotlin's `snapshotFlow { Triple(follow, me.value, refits) }` in `frame`.
    private func evaluate() {
        guard var f = framing else { return }
        let start = f.first
        f.first = false
        let asked = refits != f.seenRefits
        f.seenRefits = refits
        framing = f
        let cam = camera
        let m = f.me
        if !follow {
            stop()
            resting = MapFraming.keepInView(cam ?? fitFor(f.route, f.dest, m, f.width, f.height), f.width, f.height, f.dest)
            return
        }
        let target = fitFor(f.route, f.dest, m, f.width, f.height)
        if cam == nil || (start && f.resized) {
            stop()
            resting = target
        } else if start || asked {
            animateTo(target)
        } else if let m, let base = goal ?? cam, !MapFraming.inFrame(base, f.width, f.height, m) {
            animateTo(target)
        }
    }

    private func fitFor(_ route: [MapOffset], _ dest: MapOffset, _ me: MapOffset?, _ width: Double, _ height: Double) -> MapCamera {
        MapFraming.fit(MapFraming.frameBounds(route, dest, me), width, height)
    }

    private func animateTo(_ target: MapCamera) {
        let t = nowMs()
        let from = camera(atMs: t) ?? target
        settle?.cancel()
        let a = MapCameraAnimation(from: from, to: target, startMs: t, durationMs: Double(MapCameraState.FRAME_MS))
        resting = from
        animation = a
        settle = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(MapCameraState.FRAME_MS) * 1_000_000)
            guard !Task.isCancelled else { return }
            self?.finish(a)
        }
    }

    /// The animation ran its course: rest on its target (Compose ends exactly on the target).
    private func finish(_ a: MapCameraAnimation) {
        guard animation == a else { return }
        resting = a.to
        animation = nil
        settle = nil
    }

    /// Kotlin `stop()`: cancels a running animation where it is.
    private func stop() {
        if let a = animation {
            resting = a.value(atMs: nowMs())
            animation = nil
        }
        settle?.cancel()
        settle = nil
    }

    /// Kotlin: the `frame` coroutine (and the animation launched in its scope) is cancelled.
    private func cancelFraming() {
        stop()
        framing = nil
    }

    /// Milliseconds of `ContinuousClock` (monotonic, keeps counting while the device sleeps).
    nonisolated static func monotonicMs() -> Double {
        let d = clockOrigin.duration(to: ContinuousClock.now)
        let c = d.components
        return Double(c.seconds) * 1000.0 + Double(c.attoseconds) / 1e15
    }

    private nonisolated static let clockOrigin = ContinuousClock.now

    /// Kotlin's `listSaver`: `[true]` for a following camera (it re-fits the next screen), else
    /// `[false, cx, cy, z]`. Here a string, so SwiftUI can keep it in `@SceneStorage`.
    enum Saver {
        /// "follow", or "manual:<cx>,<cy>,<z>" (shortest round-trip decimals: restores exactly).
        @MainActor
        static func save(_ s: MapCameraState) -> String {
            guard !s.follow, let c = s.camera else { return "follow" }
            return "manual:\(c.cx),\(c.cy),\(c.z)"
        }

        /// The state `saved` describes; nil for a string ``save(_:)`` did not write (use
        /// `MapCameraState()` then).
        @MainActor
        static func restore(_ saved: String) -> MapCameraState? {
            if saved == "follow" { return MapCameraState(true, nil) }
            guard saved.hasPrefix("manual:") else { return nil }
            let parts = saved.dropFirst("manual:".count).split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count == 3, let cx = Double(parts[0]), let cy = Double(parts[1]), let z = Double(parts[2]) else {
                return nil
            }
            return MapCameraState(false, MapCamera(cx, cy, z))
        }
    }
}

/// One re-framing animation (Compose `animate` with `tween(FRAME_MS, FastOutSlowInEasing)` over
/// Kotlin's `CameraConverter`): the centre moves linearly and the zoom on a log scale (so big
/// zoom changes feel even), both along the eased fraction. Pure.
struct MapCameraAnimation: Sendable, Hashable {
    let from: MapCamera
    let to: MapCamera
    let startMs: Double
    let durationMs: Double

    /// The camera `t` ms (same clock as `startMs`) into the animation: `from` before it starts,
    /// exactly `to` once it is over.
    func value(atMs t: Double) -> MapCamera {
        let elapsed = t - startMs
        if !(elapsed < durationMs) || !(durationMs > 0) { return to }
        if elapsed <= 0 { return from }
        let e = MapCameraAnimation.fastOutSlowIn(elapsed / durationMs)
        let lz = MapCameraAnimation.lerp(log(from.z), log(to.z), e)
        return MapCamera(MapCameraAnimation.lerp(from.cx, to.cx, e), MapCameraAnimation.lerp(from.cy, to.cy, e), exp(lz))
    }

    /// Whether the animation is over at `t`.
    func isFinished(atMs t: Double) -> Bool { !(t - startMs < durationMs) }

    /// Compose animation-core `lerp`: start·(1 − f) + stop·f.
    static func lerp(_ start: Double, _ stop: Double, _ fraction: Double) -> Double {
        start * (1 - fraction) + stop * fraction
    }

    /// Compose `FastOutSlowInEasing` = `CubicBezierEasing(0.4, 0.0, 0.2, 1.0)`: y of the cubic
    /// Bézier from (0, 0) to (1, 1) at the point whose x is `fraction`.
    static func fastOutSlowIn(_ fraction: Double) -> Double { cubicBezier(0.4, 0.0, 0.2, 1.0, fraction) }

    /// Compose `CubicBezierEasing(a, b, c, d).transform(fraction)` (control points (a, b) and
    /// (c, d)); 0 and 1 (and anything outside) pass through unchanged.
    static func cubicBezier(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ fraction: Double) -> Double {
        guard fraction > 0, fraction < 1 else { return fraction }
        func bezier(_ p1: Double, _ p2: Double, _ t: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t
        }
        // x(t) is increasing on [0, 1] for 0 ≤ a, c ≤ 1: bisection to full precision.
        var lo = 0.0
        var hi = 1.0
        var t = fraction
        for _ in 0..<64 {
            let x = bezier(a, c, t)
            if x == fraction { break }
            if x < fraction { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return bezier(b, d, t)
    }
}
