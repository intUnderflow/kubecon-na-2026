import Foundation

/// SVG path data (a `d` attribute, e.g. ``MapGeometry/CONE_PATH``) as absolute drawing commands.
/// Kotlin draws these with Compose's `PathParser().parsePathString(d).toPath()`; SwiftUI has no
/// SVG parser, so the view builds its `Path` from ``parse(_:)``:
///
/// ```swift
/// var path = Path()
/// for c in SvgPath.parse(MapGeometry.ICON_UP) {
///     switch c {
///     case .move(let p): path.move(to: CGPoint(x: p.x, y: p.y))
///     case .line(let p): path.addLine(to: CGPoint(x: p.x, y: p.y))
///     case .cubic(let c1, let c2, let p): path.addCurve(to: CGPoint(x: p.x, y: p.y), control1: …, control2: …)
///     case .close: path.closeSubpath()
///     }
/// }
/// ```
///
/// Supports the whole path grammar: M L H V C S Q T A Z in both cases, implicit repeats (extra
/// pairs after M/m are line-tos), compact numbers ("0-11-30", ".5.5", "1e-3") and arc flags
/// written without separators. Quadratic curves are raised to cubics and arcs are converted to
/// cubic Béziers of at most 90° each (SVG 1.1 implementation notes F.6), so a view needs only
/// four cases. Parsing stops at the first malformed token, keeping the commands before it (as
/// browsers render a path up to its error). Pure.
enum SvgPath {
    enum Command: Sendable, Hashable {
        case move(MapOffset)
        case line(MapOffset)
        /// Control point 1, control point 2, end point.
        case cubic(MapOffset, MapOffset, MapOffset)
        case close
    }

    static func parse(_ d: String) -> [Command] {
        var s = Scanner(Array(d.utf8))
        var out: [Command] = []
        var cur = MapOffset.zero
        var start = MapOffset.zero
        var lastCubicCtrl: MapOffset?   // for S/s
        var lastQuadCtrl: MapOffset?    // for T/t
        var cmd: UInt8 = 0
        while true {
            s.skipSeparators()
            guard let c = s.peek() else { break }
            if isCommand(c) {
                cmd = c
                s.advance()
            } else if cmd == 0 || cmd == UInt8(ascii: "z") || cmd == UInt8(ascii: "Z") || !s.atNumber() {
                break // numbers without a command, or after Z: malformed
            }
            let rel = cmd >= UInt8(ascii: "a")
            func abs(_ x: Double, _ y: Double) -> MapOffset { rel ? MapOffset(cur.x + x, cur.y + y) : MapOffset(x, y) }
            var cubicCtrl: MapOffset?
            var quadCtrl: MapOffset?
            switch cmd | 0x20 { // lower case
            case UInt8(ascii: "z"):
                out.append(.close)
                cur = start
            case UInt8(ascii: "m"):
                guard let x = s.number(), let y = s.number() else { return out }
                cur = abs(x, y)
                start = cur
                out.append(.move(cur))
                cmd = rel ? UInt8(ascii: "l") : UInt8(ascii: "L") // further pairs are line-tos
            case UInt8(ascii: "l"):
                guard let x = s.number(), let y = s.number() else { return out }
                cur = abs(x, y)
                out.append(.line(cur))
            case UInt8(ascii: "h"):
                guard let x = s.number() else { return out }
                cur = MapOffset(rel ? cur.x + x : x, cur.y)
                out.append(.line(cur))
            case UInt8(ascii: "v"):
                guard let y = s.number() else { return out }
                cur = MapOffset(cur.x, rel ? cur.y + y : y)
                out.append(.line(cur))
            case UInt8(ascii: "c"):
                guard let x1 = s.number(), let y1 = s.number(), let x2 = s.number(), let y2 = s.number(),
                      let x = s.number(), let y = s.number() else { return out }
                let c1 = abs(x1, y1)
                let c2 = abs(x2, y2)
                let p = abs(x, y)
                out.append(.cubic(c1, c2, p))
                cubicCtrl = c2
                cur = p
            case UInt8(ascii: "s"):
                guard let x2 = s.number(), let y2 = s.number(), let x = s.number(), let y = s.number() else { return out }
                let c1 = lastCubicCtrl.map { MapOffset(2 * cur.x - $0.x, 2 * cur.y - $0.y) } ?? cur
                let c2 = abs(x2, y2)
                let p = abs(x, y)
                out.append(.cubic(c1, c2, p))
                cubicCtrl = c2
                cur = p
            case UInt8(ascii: "q"):
                guard let x1 = s.number(), let y1 = s.number(), let x = s.number(), let y = s.number() else { return out }
                let q = abs(x1, y1)
                let p = abs(x, y)
                out.append(quadToCubic(cur, q, p))
                quadCtrl = q
                cur = p
            case UInt8(ascii: "t"):
                guard let x = s.number(), let y = s.number() else { return out }
                let q = lastQuadCtrl.map { MapOffset(2 * cur.x - $0.x, 2 * cur.y - $0.y) } ?? cur
                let p = abs(x, y)
                out.append(quadToCubic(cur, q, p))
                quadCtrl = q
                cur = p
            case UInt8(ascii: "a"):
                guard let rx = s.number(), let ry = s.number(), let phi = s.number(),
                      let large = s.flag(), let sweep = s.flag(),
                      let x = s.number(), let y = s.number() else { return out }
                let p = abs(x, y)
                out.append(contentsOf: arc(cur, rx, ry, phi, large, sweep, p))
                cur = p
            default:
                return out
            }
            lastCubicCtrl = cubicCtrl
            lastQuadCtrl = quadCtrl
        }
        return out
    }

    private static func isCommand(_ c: UInt8) -> Bool {
        switch c | 0x20 {
        case UInt8(ascii: "m"), UInt8(ascii: "l"), UInt8(ascii: "h"), UInt8(ascii: "v"), UInt8(ascii: "c"),
             UInt8(ascii: "s"), UInt8(ascii: "q"), UInt8(ascii: "t"), UInt8(ascii: "a"), UInt8(ascii: "z"):
            return c >= 0x41 && c <= 0x7A
        default:
            return false
        }
    }

    private static func quadToCubic(_ p0: MapOffset, _ q: MapOffset, _ p: MapOffset) -> Command {
        let c1 = MapOffset(p0.x + 2.0 / 3.0 * (q.x - p0.x), p0.y + 2.0 / 3.0 * (q.y - p0.y))
        let c2 = MapOffset(p.x + 2.0 / 3.0 * (q.x - p.x), p.y + 2.0 / 3.0 * (q.y - p.y))
        return .cubic(c1, c2, p)
    }

    /// An elliptical arc from `p0` to `p` as cubics (SVG 1.1 F.6.5/F.6.6: out-of-range radii
    /// are scaled up, zero radii give a line, equal end points draw nothing).
    static func arc(
        _ p0: MapOffset, _ rx0: Double, _ ry0: Double, _ phiDeg: Double, _ largeArc: Bool, _ sweep: Bool, _ p: MapOffset
    ) -> [Command] {
        if p0 == p { return [] }
        var rx = Swift.abs(rx0)
        var ry = Swift.abs(ry0)
        if !(rx > 0) || !(ry > 0) { return [.line(p)] }
        let phi = phiDeg * Double.pi / 180.0
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)
        let dx2 = (p0.x - p.x) / 2.0
        let dy2 = (p0.y - p.y) / 2.0
        let x1p = cosPhi * dx2 + sinPhi * dy2
        let y1p = -sinPhi * dx2 + cosPhi * dy2
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            rx *= lambda.squareRoot()
            ry *= lambda.squareRoot()
        }
        let rx2 = rx * rx
        let ry2 = ry * ry
        let num = rx2 * ry2 - rx2 * y1p * y1p - ry2 * x1p * x1p
        let den = rx2 * y1p * y1p + ry2 * x1p * x1p
        let coef = (den > 0 ? Swift.max(0.0, num / den) : 0.0).squareRoot() * (largeArc == sweep ? -1.0 : 1.0)
        let cxp = coef * rx * y1p / ry
        let cyp = -coef * ry * x1p / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p.x) / 2.0
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p.y) / 2.0
        let ux = (x1p - cxp) / rx
        let uy = (y1p - cyp) / ry
        let vx = (-x1p - cxp) / rx
        let vy = (-y1p - cyp) / ry
        let theta1 = atan2(uy, ux)
        var dTheta = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        if !sweep && dTheta > 0 { dTheta -= 2 * Double.pi }
        if sweep && dTheta < 0 { dTheta += 2 * Double.pi }
        let n = Swift.max(1, Int((Swift.abs(dTheta) / (Double.pi / 2)).rounded(.up)))
        let delta = dTheta / Double(n)
        let k = 4.0 / 3.0 * tan(delta / 4.0)
        func point(_ t: Double) -> MapOffset {
            MapOffset(cx + rx * cosPhi * cos(t) - ry * sinPhi * sin(t), cy + rx * sinPhi * cos(t) + ry * cosPhi * sin(t))
        }
        func tangent(_ t: Double) -> MapOffset {
            MapOffset(-rx * cosPhi * sin(t) - ry * sinPhi * cos(t), -rx * sinPhi * sin(t) + ry * cosPhi * cos(t))
        }
        var out: [Command] = []
        var t1 = theta1
        var from = p0
        for i in 0..<n {
            let t2 = t1 + delta
            let end = i == n - 1 ? p : point(t2)
            let d1 = tangent(t1)
            let d2 = tangent(t2)
            out.append(.cubic(MapOffset(from.x + k * d1.x, from.y + k * d1.y), MapOffset(end.x - k * d2.x, end.y - k * d2.y), end))
            from = end
            t1 = t2
        }
        return out
    }

    /// A byte scanner over the path data.
    private struct Scanner {
        let b: [UInt8]
        var i = 0

        init(_ b: [UInt8]) {
            self.b = b
        }

        func peek() -> UInt8? { i < b.count ? b[i] : nil }
        mutating func advance() { i += 1 }

        mutating func skipSeparators() {
            while i < b.count, b[i] == 0x20 || b[i] == 0x09 || b[i] == 0x0A || b[i] == 0x0D || b[i] == 0x0C || b[i] == 0x2C {
                i += 1
            }
        }

        /// The next token starts a number.
        mutating func atNumber() -> Bool {
            skipSeparators()
            guard let c = peek() else { return false }
            return isDigit(c) || c == 0x2D || c == 0x2B || c == 0x2E
        }

        /// An SVG number: [+-] digits [. digits] [(e|E) [+-] digits], or nil.
        mutating func number() -> Double? {
            skipSeparators()
            let s = i
            if i < b.count, b[i] == 0x2B || b[i] == 0x2D { i += 1 }
            var digits = 0
            while i < b.count, isDigit(b[i]) {
                i += 1
                digits += 1
            }
            if i < b.count, b[i] == 0x2E {
                i += 1
                while i < b.count, isDigit(b[i]) {
                    i += 1
                    digits += 1
                }
            }
            guard digits > 0 else {
                i = s
                return nil
            }
            if i < b.count, b[i] == 0x65 || b[i] == 0x45 { // e / E
                var j = i + 1
                if j < b.count, b[j] == 0x2B || b[j] == 0x2D { j += 1 }
                if j < b.count, isDigit(b[j]) {
                    while j < b.count, isDigit(b[j]) { j += 1 }
                    i = j
                }
            }
            let text = String(decoding: b[s..<i], as: UTF8.self)
            guard let v = Double(text), v.isFinite else {
                i = s
                return nil
            }
            return v
        }

        /// An arc flag: a single "0" or "1" (no separator needed after it).
        mutating func flag() -> Bool? {
            skipSeparators()
            guard let c = peek(), c == 0x30 || c == 0x31 else { return nil }
            i += 1
            return c == 0x31
        }

        private func isDigit(_ c: UInt8) -> Bool { c >= 0x30 && c <= 0x39 }
    }
}
