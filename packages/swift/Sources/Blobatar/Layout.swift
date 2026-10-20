import Foundation

/// The core body a silhouette draws and patches.
public struct Body: Sendable, Equatable {
    public var cx, cy, rx, ry, n, rot: Double
    public var radii: [Double]
    /// Polygon-only.
    public var sides: Int?
    public var round: Double?
}

/// An ellipse-shaped region: the face the eyes must fit inside.
public struct Ellipse: Sendable, Equatable {
    public var cx, cy, rx, ry: Double
}

/// A circle unioned with the body (petals, caps, lobes, sun rays).
public struct Petal: Sendable, Equatable {
    public let cx, cy, r: Double
}

/// One fitted eye.
public struct Eye: Sendable, Equatable {
    public var cx, cy, rx, ry, n, rot: Double
}

/// The ten-shape gen-2 vocabulary, in band order.
public enum BlobatarShape: String, Sendable, CaseIterable {
    case round, organic, boxy, capsule, nub, cloud, droplet, hexagon, sun, triangle

    /// The upper edge of each shape's band in [0, 1). Frozen per major.
    static let bands: [(BlobatarShape, Double)] = [
        (.round, 0.22), (.organic, 0.48), (.boxy, 0.6), (.capsule, 0.7), (.nub, 0.79),
        (.cloud, 0.86), (.droplet, 0.915), (.hexagon, 0.95), (.sun, 0.98), (.triangle, 1.0),
    ]

    static func pick(_ v: Double) -> BlobatarShape {
        bands.first { v < $0.1 }?.0 ?? .triangle
    }

    /// How much of the frame the core body takes.
    var core: Double {
        switch self {
        case .round: 1
        case .organic: 0.98
        case .boxy: 0.86
        case .capsule: 1.02
        case .nub: 0.88
        case .cloud: 0.78
        case .droplet: 0.78
        case .hexagon: 1.05
        case .sun: 0.7
        case .triangle: 1.15
        }
    }

    /// Patches the body before the face is measured.
    func patch(_ t: Traits, _ b: inout Body) {
        switch self {
        case .boxy:
            b.n = t.num("body.n", 3.4, 6)
            b.rot = t.num("body.rot", -20, 20)
        case .capsule:
            b.ry *= t.num("capsule.squat", 0.55, 0.68)
        case .droplet:
            b.cy += 0.22 * b.ry
            b.n = 2
        case .hexagon:
            b.sides = 6
            b.rot = t.num("body.rot", -12, 12)
            b.round = t.num("poly.round", 0.24, 0.5)
        case .triangle:
            b.sides = 3
            b.rot = t.num("body.rot", -5, 5)
            b.round = t.num("poly.round", 0.24, 0.5)
        default:
            break
        }
    }

    private static func shrunk(_ b: Body, _ k: Double) -> Ellipse {
        Ellipse(cx: b.cx, cy: b.cy, rx: b.rx * k, ry: b.ry * k)
    }

    /// The region the eyes fit inside; nil means the body itself.
    func face(_ b: Body) -> Ellipse? {
        switch self {
        case .organic, .cloud: Self.shrunk(b, (b.radii.min() ?? 1) * 0.95)
        case .capsule: Self.shrunk(b, 0.94)
        case .droplet: Ellipse(cx: b.cx, cy: b.cy + b.ry * 0.05, rx: b.rx * 0.88, ry: b.ry * 0.88)
        case .hexagon: Self.shrunk(b, 0.84)
        case .triangle: Ellipse(cx: b.cx, cy: b.cy + b.ry * 0.1, rx: b.rx * 0.54, ry: b.ry * 0.36)
        default: nil
        }
    }

    func decorate(_ t: Traits, _ b: Body) -> (petals: [Petal], extra: [BlobPath]) {
        var petals: [Petal] = []
        var extra: [BlobPath] = []
        switch self {
        case .capsule:
            for s in [-1.0, 1.0] { petals.append(Petal(cx: b.cx + s * (b.rx - b.ry), cy: b.cy, r: b.ry)) }
        case .nub:
            for i in 0..<t.int("nub.n", 1, 2) {
                let a = t.num("nub.a\(i)", 0, 2 * .pi)
                petals.append(Petal(cx: b.cx + cos(a) * b.rx * 0.88, cy: b.cy + sin(a) * b.rx * 0.88,
                                    r: b.rx * t.num("nub.r\(i)", 0.24, 0.4)))
            }
        case .cloud:
            let count = t.int("cloud.n", 4, 6)
            for i in 0..<count {
                let a = Double.pi + (Double.pi * (Double(i) + 0.5)) / Double(count)
                petals.append(Petal(cx: b.cx + cos(a) * b.rx * 0.8, cy: b.cy + sin(a) * b.rx * 0.5,
                                    r: b.rx * t.num("cloud.r\(i)", 0.44, 0.62)))
            }
        case .droplet:
            extra.append(BlobShape.taper(cx: b.cx, cy: b.cy, rx: b.rx, ry: b.ry, tip: t.num("droplet.tip", 1.4, 1.65)))
        case .sun:
            let count = t.int("sun.n", 6, 9)
            let dist = b.rx * t.num("sun.dist", 1.0, 1.08)
            let pr = b.rx * t.num("sun.r", 0.2, 0.26)
            let off = t.num("sun.rot", 0, 2 * .pi)
            for i in 0..<count {
                let a = off + (2 * .pi * Double(i)) / Double(count)
                petals.append(Petal(cx: b.cx + cos(a) * dist, cy: b.cy + sin(a) * dist, r: pr))
            }
        default:
            break
        }
        return (petals, extra)
    }

    /// The core path; nil means a superellipse.
    func path(_ b: Body) -> BlobPath? {
        switch self {
        case .organic, .cloud:
            BlobShape.blobPath(cx: b.cx, cy: b.cy, rx: b.rx, ry: b.ry, radii: b.radii, rot: b.rot)
        case .capsule:
            BlobShape.box(cx: b.cx, cy: b.cy, rx: b.rx - b.ry, ry: b.ry)
        case .hexagon, .triangle:
            BlobShape.polygon(cx: b.cx, cy: b.cy, rx: b.rx, ry: b.ry, sides: b.sides ?? 6, round: b.round ?? 0.3, rot: b.rot)
        default:
            nil
        }
    }
}

/// The resolved layout for one seed in a 100 x 100 viewBox: everything a
/// renderer needs and nothing about how to draw it.
public struct BlobatarLayout: Sendable, Equatable {
    public let shape: BlobatarShape
    public var body: Body
    public var face: Ellipse
    public var eyes: [Eye]
    public var petals: [Petal]
    public var extra: [BlobPath]
    public var bodyOffsetY: Double = 0

    /// The core body's path: the shape's own, or a superellipse.
    public func bodyPath() -> BlobPath {
        shape.path(body)
            ?? BlobShape.superellipse(cx: body.cx, cy: body.cy, rx: body.rx, ry: body.ry, n: body.n, rot: body.rot)
    }

    public func eyePaths() -> [BlobPath] {
        eyes.map { BlobShape.superellipse(cx: $0.cx, cy: $0.cy, rx: $0.rx, ry: $0.ry, n: $0.n, rot: $0.rot) }
    }

    /// Resolves one seed's traits into the full layout (Blobatar 2's style).
    public static func make(_ t: Traits) -> BlobatarLayout {
        let shape = BlobatarShape.pick(t("shape"))
        let r = t.num("body.r", 31, 38) * shape.core
        var body = Body(
            cx: 50 + t.jitter("body.x", 1.5),
            cy: 50 + t.jitter("body.y", 1.5),
            rx: r,
            ry: r * t.num("body.ratio", 0.92, 1.08),
            n: t.num("body.n", 1.9, 2.5),
            rot: 0,
            radii: (0..<t.int("body.pts", 6, 8)).map { 1 + t.jitter("body.r\($0)", 0.16) }
        )
        shape.patch(t, &body)
        let face = shape.face(body) ?? Ellipse(cx: body.cx, cy: body.cy, rx: body.rx, ry: body.ry)
        let deco = shape.decorate(t, body)
        return BlobatarLayout(shape: shape, body: body, face: face, eyes: faceFit(t, body, face),
                              petals: deco.petals, extra: deco.extra)
    }

    /// Fits the eye pair inside the face region on both axes.
    static func faceFit(_ t: Traits, _ b: Body, _ face: Ellipse) -> [Eye] {
        let rx = b.rx
        let er0 = t.num("eye.rx", 0.075, 0.105) * rx
        let ratio = t.num("eye.ratio", 1.9, 3.2)
        let scale = t.num("eye.scale", 0.78, 1.24)
        let stretch = t.num("eye.stretch", 0.85, 1.18)
        let clearance = t.num("eye.gap", 0.1, 0.24) * rx
        let wide = er0 * max(1, scale)
        let tall = er0 * ratio * max(1, scale * stretch)
        let gap0 = wide + rx * 0.03 + clearance

        let gx = t.jitter("gaze.x", 0.09) * face.rx
        let gy = t.num("gaze.y", -0.2, 0.08) * face.ry
        let dy = t.jitter("eye.dy", 0.04) * face.ry
        let reach = BlobatarColor.hypot2(wide, tall)
        let need = BlobatarColor.hypot2((abs(gx) + gap0 + reach) / face.rx, (abs(gy) + abs(dy) + reach) / face.ry)
        let fit = need > 0.9 ? 0.9 / need : 1

        let er = er0 * fit
        let eyeRy = er * ratio
        let gap = gap0 * fit
        let room = max(0, min(1, clearance / tall))
        let bound = min(12, asin(room) * 180 / .pi)
        let lean = t.num("eye.lean", -1, 1) * bound
        let lean2 = max(-12.0, min(12.0, lean + t.jitter("eye.lean2", 3.5)))

        let cx = face.cx + gx * fit
        let cy = face.cy + gy * fit
        return [
            Eye(cx: cx - gap, cy: cy, rx: er, ry: eyeRy, n: t.num("eye.n", 3.5, 6), rot: lean),
            Eye(cx: cx + gap, cy: cy + dy * fit, rx: er * scale, ry: eyeRy * scale * stretch,
                n: t.num("eye.n", 3.5, 6), rot: lean2),
        ]
    }
}
