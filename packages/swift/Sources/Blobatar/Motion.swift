import Foundation

/// Seeded periods, phases and look direction for one blobatar's idle motion. Swift port of
/// `motion.ts` (via the Dart port): every loop is a pure function of elapsed time, so a renderer
/// can redraw from a clock without keeping state.
public struct MotionSeeds: Sendable, Equatable {
    /// Breathing and bob phase offsets, in milliseconds.
    public var phase: Int, bob: Int
    /// Blink period and phase, in milliseconds.
    public var blink: Int, blinkPhase: Int
    /// Saccade (glance) period and phase, in milliseconds.
    public var saccade: Int, saccadePhase: Int
    /// Signed look distances, and their magnitudes.
    public var lookX: Double, lookY: Double, lookMagnitudeX: Double, lookMagnitudeY: Double

    public init(_ t: Traits) {
        func round(_ v: Double) -> Int { Int((v + 0.5).rounded(.down)) }
        func round2(_ v: Double) -> Double { Double(round(v * 100)) / 100 }
        let blink = round(t.num("motion.blink", 3500, 6500))
        let saccade = round(t.num("motion.saccade", 4200, 7600))
        let lookX = round2(t.num("motion.lookX", 1, 2.2))
        let lookY = round2(t.num("motion.lookY", 0.8, 1.7))
        phase = round(t.num("motion.phase", 0, 2800))
        bob = round(t.num("motion.bob", 0, 3400))
        self.blink = blink
        blinkPhase = round(t.num("motion.blinkPhase", 0, Double(blink)))
        self.saccade = saccade
        saccadePhase = round(t.num("motion.saccadePhase", 0, Double(saccade)))
        self.lookX = lookX * (t.bool("motion.lookXFlip") ? -1 : 1)
        self.lookY = lookY * (t.bool("motion.lookYFlip") ? -1 : 1)
        lookMagnitudeX = lookX
        lookMagnitudeY = lookY
    }

    public init(name: String, normalize: Bool = true, traits: [String: TraitOverride]? = nil) {
        self.init(Traits(seed: name, normalize: normalize, overrides: traits))
    }
}

/// One frame of every idle-motion channel.
public struct MotionFrame: Sendable, Equatable {
    /// Mad-expression tremor, in viewBox units.
    public var shake: (x: Double, y: Double)
    /// Horizontal and vertical breathing scales.
    public var breathe: (x: Double, y: Double)
    /// Vertical body translation, in viewBox units.
    public var bob: Double
    /// Shared eye translation (glance), in viewBox units.
    public var saccade: (x: Double, y: Double)
    /// The thinking seesaw, -1 to 1.
    public var thinkingPhase: Double
    /// Vertical eye scale; 1 is open.
    public var blink: Double
    /// Eye foreshortening for the current glance: (shared x, side x, y, rotation degrees).
    public var wrap: (magnitudeX: Double, side: Double, scaleY: Double, rotation: Double)

    public static func == (a: Self, b: Self) -> Bool {
        a.shake == b.shake && a.breathe == b.breathe && a.bob == b.bob && a.saccade == b.saccade
            && a.thinkingPhase == b.thinkingPhase && a.blink == b.blink && a.wrap == b.wrap
    }
}

public enum BlobatarMotion {
    public static let breatheMilliseconds = 2800.0
    public static let bobMilliseconds = 3400.0
    public static let thinkingMilliseconds = 900.0
    public static let shakeMilliseconds = 112.0
    public static let expressionEnterMilliseconds = 300.0
    public static let expressionExitMilliseconds = 400.0
    public static let ambientRampMilliseconds = 400.0

    /// Solves a CSS cubic Bézier timing function at elapsed fraction `x`.
    public static func cubicBezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        let cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx
        let cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by
        var t = x
        for _ in 0..<8 {
            let error = ((ax * t + bx) * t + cx) * t - x
            if abs(error) < 1e-5 { break }
            let derivative = (3 * ax * t + 2 * bx) * t + cx
            if abs(derivative) < 1e-6 { break }
            t -= error / derivative
        }
        return ((ay * t + by) * t + cy) * t
    }

    public static func easeInOut(_ v: Double) -> Double { cubicBezier(v, 0.42, 0, 0.58, 1) }
    public static func easeIn(_ v: Double) -> Double { cubicBezier(v, 0.42, 0, 1, 1) }
    public static func easeOut(_ v: Double) -> Double { cubicBezier(v, 0, 0, 0.58, 1) }
    public static func expressionEnterEase(_ v: Double) -> Double { cubicBezier(v, 0.45, 0.05, 0.5, 1) }

    private static func cycle(_ time: Double, _ phase: Double, _ period: Double) -> Double {
        let v = (time + phase) / period
        return v - v.rounded(.down)
    }

    private static func alternate(_ time: Double, _ phase: Double, _ period: Double) -> Double {
        let v = (time + phase) / period
        let iteration = v.rounded(.down)
        let fraction = v - iteration
        return Int(iteration) % 2 != 0 ? 1 - fraction : fraction
    }

    private static func stops(_ value: Double, _ table: [[Double]], _ column: Int) -> Double {
        for index in stride(from: table.count - 1, through: 0, by: -1) {
            let row = table[index]
            if value < row[0] { continue }
            if index + 1 == table.count { return row[column] }
            let next = table[index + 1]
            let span = next[0] - row[0]
            if span <= 0 { return row[column] }
            return row[column] + (next[column] - row[column]) * ((value - row[0]) / span)
        }
        return table[0][column]
    }

    private static let saccadeStops: [[Double]] = [
        [0, 0, 0], [0.15, 0, 0], [0.165, -0.8, -0.9], [0.31, -0.8, -0.9], [0.325, 1, 0.1], [0.47, 1, 0.1],
        [0.485, -0.15, 0.85], [0.63, -0.15, 0.85], [0.645, 0.75, -0.8], [0.79, 0.75, -0.8],
        [0.805, -1, -0.15], [0.985, -1, -0.15], [1, 0, 0],
    ]

    private static let wrapStops: [[Double]] = [
        [0, 0, 0, 0, 0], [0.15, 0, 0, 0, 0],
        [0.165, -0.0176, 0.008, -0.027, 0.648], [0.31, -0.0176, 0.008, -0.027, 0.648],
        [0.325, -0.022, -0.01, -0.003, 0.09], [0.47, -0.022, -0.01, -0.003, 0.09],
        [0.485, -0.0033, 0.0015, -0.0255, -0.115], [0.63, -0.0033, 0.0015, -0.0255, -0.115],
        [0.645, -0.0165, -0.0075, -0.024, -0.54], [0.79, -0.0165, -0.0075, -0.024, -0.54],
        [0.805, -0.022, 0.01, -0.0045, 0.135], [0.985, -0.022, 0.01, -0.0045, 0.135],
        [1, 0, 0, 0, 0],
    ]

    private static let shakeStops: [[Double]] = [
        [0, 0.62, -0.34], [0.25, -0.7, 0.22], [0.5, 0.38, 0.66], [0.75, -0.44, -0.6], [1, 0.62, -0.34],
    ]

    /// Every motion channel at `elapsed` milliseconds, with ambient `amplitude` 0–1 and the
    /// expression's `shake`.
    public static func frame(_ seeds: MotionSeeds, at elapsed: Double, amplitude: Double, shake: Double = 0) -> MotionFrame {
        let breathe = easeInOut(alternate(elapsed, Double(seeds.phase), breatheMilliseconds))
        let bob = easeInOut(alternate(elapsed, Double(seeds.bob), bobMilliseconds))
        let saccade = cycle(elapsed, Double(seeds.saccadePhase), Double(seeds.saccade))
        let shakeCycle = cycle(elapsed, 0, shakeMilliseconds)
        let thinkingCycle = cycle(elapsed, 0, thinkingMilliseconds)
        let thinkingPhase = thinkingCycle < 0.5
            ? 1 - 2 * easeInOut(thinkingCycle * 2)
            : -1 + 2 * easeInOut(thinkingCycle * 2 - 1)
        let blinkCycle = cycle(elapsed, Double(seeds.blinkPhase), Double(seeds.blink))
        let blink = blinkCycle < 0.972 ? 1
            : blinkCycle < 0.986 ? 1 - 0.92 * amplitude * easeIn((blinkCycle - 0.972) / 0.014)
            : 1 - 0.92 * amplitude * (1 - easeOut((blinkCycle - 0.986) / 0.014))
        return MotionFrame(
            shake: (stops(shakeCycle, shakeStops, 1) * shake, stops(shakeCycle, shakeStops, 2) * shake),
            breathe: (1 + 0.022 * amplitude * breathe, 1 - 0.018 * amplitude * breathe),
            bob: -1.1 * amplitude * bob,
            saccade: (stops(saccade, saccadeStops, 1) * seeds.lookX * amplitude,
                      stops(saccade, saccadeStops, 2) * seeds.lookY * amplitude),
            thinkingPhase: thinkingPhase,
            blink: blink,
            wrap: (stops(saccade, wrapStops, 1) * seeds.lookMagnitudeX * amplitude,
                   stops(saccade, wrapStops, 2) * seeds.lookX * amplitude,
                   stops(saccade, wrapStops, 3) * seeds.lookMagnitudeY * amplitude,
                   stops(saccade, wrapStops, 4) * seeds.lookX * seeds.lookY * amplitude)
        )
    }

    /// Linearly interpolates every expression channel.
    public static func lerp(_ a: Pose, _ b: Pose, _ t: Double) -> Pose {
        func l(_ x: Double, _ y: Double) -> Double { x * (1 - t) + y * t }
        return Pose(esx: l(a.esx, b.esx), esy: l(a.esy, b.esy), tilt: l(a.tilt, b.tilt), edy: l(a.edy, b.edy),
                    edx: l(a.edx, b.edx), esx2: l(a.esx2, b.esx2), esy2: l(a.esy2, b.esy2), tilt2: l(a.tilt2, b.tilt2),
                    edy2: l(a.edy2, b.edy2), lock: l(a.lock, b.lock), heat: l(a.heat, b.heat),
                    shake: l(a.shake, b.shake), rock: l(a.rock, b.rock), bdy: l(a.bdy, b.bdy))
    }
}
