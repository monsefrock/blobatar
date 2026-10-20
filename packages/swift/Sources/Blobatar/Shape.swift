import Foundation

/// One absolute path command; all the library emits.
public enum PathSegment: Sendable, Equatable {
    case move(x: Double, y: Double)
    case line(x: Double, y: Double)
    case cubic(c1x: Double, c1y: Double, c2x: Double, c2y: Double, x: Double, y: Double)
    case quad(cx: Double, cy: Double, x: Double, y: Double)
    case horizontal(x: Double)
    case vertical(y: Double)
    case close
}

/// A structured path with a byte-exact SVG serialization (the same strings
/// the TypeScript core emits).
public struct BlobPath: Sendable, Equatable {
    public var segments: [PathSegment]

    public init(_ segments: [PathSegment]) { self.segments = segments }

    /// Two decimal places, `-0` as `0`, no trailing zeros: JS `String(Number)`
    /// of the rounded value. Formatted from the integer hundredths, which is
    /// exactly the shortest round-trip form at this precision.
    static func r2(_ v: Double) -> String {
        let hundredths = Int((v * 100 + 0.5).rounded(.down))
        if hundredths == 0 { return "0" }
        let magnitude = abs(hundredths)
        var out = hundredths < 0 ? "-" : ""
        out += String(magnitude / 100)
        let fraction = magnitude % 100
        if fraction != 0 {
            out += fraction % 10 == 0 ? ".\(fraction / 10)" : (fraction < 10 ? ".0\(fraction)" : ".\(fraction)")
        }
        return out
    }

    public func toPathData() -> String {
        var d = ""
        for segment in segments {
            switch segment {
            case let .move(x, y): d += "M\(Self.r2(x)) \(Self.r2(y))"
            case let .line(x, y): d += "L\(Self.r2(x)) \(Self.r2(y))"
            case let .cubic(c1x, c1y, c2x, c2y, x, y):
                d += "C\(Self.r2(c1x)) \(Self.r2(c1y)) \(Self.r2(c2x)) \(Self.r2(c2y)) \(Self.r2(x)) \(Self.r2(y))"
            case let .quad(cx, cy, x, y): d += "Q\(Self.r2(cx)) \(Self.r2(cy)) \(Self.r2(x)) \(Self.r2(y))"
            case let .horizontal(x): d += "H\(Self.r2(x))"
            case let .vertical(y): d += "V\(Self.r2(y))"
            case .close: d += "Z"
            }
        }
        return d
    }
}

/// The path primitives. Swift port of `packages/blobatar/src/shape.ts`.
public enum BlobShape {
    /// `|x/a|^n + |y/b|^n = 1`, one cubic per quadrant, passing through the
    /// 45 degree point (k clamped so the curve stays inside its bounds).
    public static func superellipse(cx: Double, cy: Double, rx: Double, ry: Double, n: Double = 4, rot: Double = 0) -> BlobPath {
        let k = min(1.0, (8 * pow(2, -1 / n) - 4) / 3)
        let a = rx, b = ry, ak = a * k, bk = b * k
        let pts: [(Double, Double)] = [
            (a, 0), (a, bk), (ak, b), (0, b), (-ak, b), (-a, bk), (-a, 0),
            (-a, -bk), (-ak, -b), (0, -b), (ak, -b), (a, -bk), (a, 0),
        ]
        let t = rot * .pi / 180
        let c = cos(t), s = sin(t)
        func at(_ i: Int) -> (Double, Double) {
            let (x, y) = pts[i]
            return (cx + x * c - y * s, cy + x * s + y * c)
        }
        let p0 = at(0)
        var segments: [PathSegment] = [.move(x: p0.0, y: p0.1)]
        for i in stride(from: 1, to: 13, by: 3) {
            let c1 = at(i), c2 = at(i + 1), p = at(i + 2)
            segments.append(.cubic(c1x: c1.0, c1y: c1.1, c2x: c2.0, c2y: c2.1, x: p.0, y: p.1))
        }
        segments.append(.close)
        return BlobPath(segments)
    }

    /// Radii sampled around a circle, joined by a closed Catmull-Rom spline.
    public static func blobPath(cx: Double, cy: Double, rx: Double, ry: Double, radii: [Double], rot: Double = 0) -> BlobPath {
        let n = radii.count
        let t0 = rot * .pi / 180
        let p: [(Double, Double)] = (0..<n).map { i in
            let angle = t0 + 2 * .pi * Double(i) / Double(n)
            return (cx + rx * radii[i] * cos(angle), cy + ry * radii[i] * sin(angle))
        }
        func at(_ i: Int) -> (Double, Double) { p[((i % n) + n) % n] }
        let start = at(0)
        var segments: [PathSegment] = [.move(x: start.0, y: start.1)]
        for i in 0..<n {
            let (x0, y0) = at(i - 1), (x1, y1) = at(i), (x2, y2) = at(i + 1), (x3, y3) = at(i + 2)
            segments.append(.cubic(
                c1x: x1 + (x2 - x0) / 6, c1y: y1 + (y2 - y0) / 6,
                c2x: x2 - (x3 - x1) / 6, c2y: y2 - (y3 - y1) / 6,
                x: x2, y: y2
            ))
        }
        segments.append(.close)
        return BlobPath(segments)
    }

    /// A regular polygon (vertex on top) with corners cut back by `round` and
    /// joined with a quadratic through the vertex.
    public static func polygon(cx: Double, cy: Double, rx: Double, ry: Double, sides: Int, round: Double = 0.3, rot: Double = 0) -> BlobPath {
        let k = round > 0 ? (round < 1 ? round / 2 : 0.5) : 0
        let t0 = rot * .pi / 180 - .pi / 2
        let v: [(Double, Double)] = (0..<sides).map { i in
            let angle = t0 + 2 * .pi * Double(i) / Double(sides)
            return (cx + rx * cos(angle), cy + ry * sin(angle))
        }
        func at(_ i: Int) -> (Double, Double) { v[((i % sides) + sides) % sides] }
        func cut(_ i: Int, _ j: Int) -> (Double, Double) {
            let (x0, y0) = at(i), (x1, y1) = at(j)
            return (x0 + (x1 - x0) * k, y0 + (y1 - y0) * k)
        }
        let m0 = cut(0, -1)
        var segments: [PathSegment] = [.move(x: m0.0, y: m0.1)]
        for i in 0..<sides {
            let vertex = at(i), end = cut(i, i + 1)
            segments.append(.quad(cx: vertex.0, cy: vertex.1, x: end.0, y: end.1))
            if k < 0.5 {
                let l = cut(i + 1, i)
                segments.append(.line(x: l.0, y: l.1))
            }
        }
        segments.append(.close)
        return BlobPath(segments)
    }

    /// A plain box (the straight run of a capsule).
    public static func box(cx: Double, cy: Double, rx: Double, ry: Double) -> BlobPath {
        BlobPath([.move(x: cx - rx, y: cy - ry), .horizontal(x: cx + rx), .vertical(y: cy + ry), .horizontal(x: cx - rx), .close])
    }

    /// A droplet's taper: the two tangents from an apex to the body ellipse,
    /// eased with a quadratic through the apex.
    public static func taper(cx: Double, cy: Double, rx: Double, ry: Double, tip: Double) -> BlobPath {
        let t = max(1.05, tip)
        let tx = rx * (1 - 1 / (t * t)).squareRoot()
        let ty = cy - ry / t
        let apex = cy - t * ry
        let px = tx * 0.14
        let py = ty + 0.86 * (apex - ty)
        return BlobPath([
            .move(x: cx - tx, y: ty),
            .line(x: cx - px, y: py),
            .quad(cx: cx, cy: apex, x: cx + px, y: py),
            .line(x: cx + tx, y: ty),
            .close,
        ])
    }
}
