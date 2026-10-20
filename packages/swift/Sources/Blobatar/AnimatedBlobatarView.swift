#if canImport(SwiftUI)
import SwiftUI

/// A resolved figure whose paths stay fixed while the motion moves it: breathing, bobbing,
/// blinking, glancing around, and morphing between expressions. Swift port of the Flutter
/// `AnimatedBlobatarRenderer`, in the same transform order as the web's CSS.
public struct AnimatedBlobatarRenderer: Sendable {
    /// The figure without any expression; poses are applied as transforms.
    public let base: Blobatar
    public let seeds: MotionSeeds

    public init(_ name: String, options: BlobatarOptions = BlobatarOptions()) {
        var plain = options
        plain.expression = nil
        base = Blobatar(name, options: plain)
        seeds = MotionSeeds(name: name, normalize: options.normalize, traits: options.traits)
    }

    /// The palette an expression wears (its tint resolved against the base palette).
    public func palette(for expression: BlobatarExpression?) -> BlobatarPalette {
        base.palette.expressed(expression ?? .idle)
    }

    /// Paints one frame into the largest centered square of `size`.
    public func draw(in context: inout GraphicsContext, size: CGSize, motion: MotionFrame, pose: Pose,
                     head: String, eye: String) {
        let side = min(size.width, size.height)
        guard side > 0 else { return }
        var ctx = context
        ctx.translateBy(x: (size.width - side) / 2, y: (size.height - side) / 2)
        ctx.scaleBy(x: side / 100, y: side / 100)
        if let backdrop = base.backdropPath {
            ctx.fill(Path(backdrop.cgPath), with: .color(Color(blobatarHex: base.palette.bg)))
        }

        ctx.translateBy(x: motion.shake.x, y: motion.shake.y)
        ctx.translateBy(x: 50, y: 50)
        ctx.scaleBy(x: motion.breathe.x, y: motion.breathe.y)
        ctx.translateBy(x: -50, y: -50)
        ctx.translateBy(x: 0, y: pose.bdy + motion.bob)

        let layout = base.layout
        let headFill = GraphicsContext.Shading.color(Color(blobatarHex: head))
        for petal in layout.petals {
            ctx.fill(Path(ellipseIn: CGRect(x: petal.cx - petal.r, y: petal.cy - petal.r,
                                            width: petal.r * 2, height: petal.r * 2)), with: headFill)
        }
        for extra in layout.extra { ctx.fill(Path(extra.cgPath), with: headFill) }
        ctx.fill(Path(layout.bodyPath().cgPath), with: headFill)

        var eyes = ctx
        eyes.translateBy(x: motion.saccade.x, y: motion.saccade.y)
        let eyeFill = GraphicsContext.Shading.color(Color(blobatarHex: eye))
        for (index, path) in layout.eyePaths().enumerated() {
            let e = layout.eyes[index]
            let side: Double = index == 0 ? -1 : 1
            let selected: Double = index == 0 ? 0 : 1
            let phase = selected * (1 - pose.rock) + pose.rock * ((1 + side * motion.thinkingPhase) / 2)
            var c = eyes
            c.translateBy(x: e.cx + pose.edx * side, y: e.cy + pose.edy + phase * pose.edy2)
            c.rotate(by: .degrees((pose.tilt + selected * pose.tilt2) * side + e.rot * (1 - pose.lock)))
            c.scaleBy(x: pose.esx + selected * pose.esx2, y: pose.esy + selected * pose.esy2)
            c.rotate(by: .degrees(-e.rot))
            c.translateBy(x: -e.cx, y: -e.cy)

            c.translateBy(x: e.cx, y: e.cy)
            c.rotate(by: .degrees(motion.wrap.rotation * side))
            c.scaleBy(x: 1 + motion.wrap.magnitudeX + motion.wrap.side * side, y: 1 + motion.wrap.scaleY)
            c.rotate(by: .degrees(e.rot))
            c.scaleBy(x: 1, y: motion.blink)
            c.rotate(by: .degrees(-e.rot))
            c.translateBy(x: -e.cx, y: -e.cy)
            c.fill(Path(path.cgPath), with: eyeFill)
        }
    }
}

/// A living blobatar: the same figure as `BlobatarView`, breathing, bobbing, blinking and glancing
/// around like the web's animated version. Changing `expression` morphs into it (300 ms in, 400 ms
/// back to idle). With Reduce Motion on, it draws the still figure.
///
/// ```swift
/// AnimatedBlobatarView("alain@example.com", expression: isHappy ? .happy : nil)
///     .frame(width: 48, height: 48)
/// ```
public struct AnimatedBlobatarView: View {
    private let renderer: AnimatedBlobatarRenderer
    private let expression: BlobatarExpression?
    private let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()
    @State private var morph: Morph?

    private struct Morph {
        var from: Pose
        var fromHead: String
        var fromEye: String
        var start: Date
        var duration: Double
    }

    /// - Parameters:
    ///   - expression: the pose to hold; nil is idle.
    ///   - isActive: false freezes it in the still pose (for example off screen).
    public init(_ name: String, options: BlobatarOptions = BlobatarOptions(),
                expression: BlobatarExpression? = nil, isActive: Bool = true) {
        renderer = AnimatedBlobatarRenderer(name, options: options)
        self.expression = expression ?? options.expression
        self.isActive = isActive
    }

    public var body: some View {
        Group {
            if reduceMotion || !isActive {
                BlobatarView(renderer.base.name, options: stillOptions)
            } else {
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        draw(in: &context, size: size, at: timeline.date)
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
        .onChange(of: expression) { newValue in
            let now = Date()
            let current = state(at: now)
            morph = Morph(from: current.pose, fromHead: current.head, fromEye: current.eye, start: now,
                          duration: newValue == nil || newValue == .idle
                              ? BlobatarMotion.expressionExitMilliseconds
                              : BlobatarMotion.expressionEnterMilliseconds)
        }
    }

    private var stillOptions: BlobatarOptions {
        var options = renderer.base.options
        options.expression = expression
        return options
    }

    /// The pose and colors at `date`, partway through a morph or settled on the expression.
    private func state(at date: Date) -> (pose: Pose, head: String, eye: String) {
        let target = expression?.pose ?? Pose()
        let palette = renderer.palette(for: expression)
        guard let morph else { return (target, palette.head, palette.eye) }
        let raw = min(1, max(0, date.timeIntervalSince(morph.start) * 1000 / morph.duration))
        guard raw < 1 else { return (target, palette.head, palette.eye) }
        let t = BlobatarMotion.expressionEnterEase(raw)
        return (BlobatarMotion.lerp(morph.from, target, t),
                BlobatarColor.fadeHex(morph.fromHead, palette.head, t),
                BlobatarColor.fadeHex(morph.fromEye, palette.eye, t))
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, at date: Date) {
        let elapsed = date.timeIntervalSince(startedAt) * 1000
        // The idle motion eases in over 400 ms instead of starting mid-breath.
        let amplitude = BlobatarMotion.easeOut(min(1, max(0, elapsed / BlobatarMotion.ambientRampMilliseconds)))
        let current = state(at: date)
        let motion = BlobatarMotion.frame(renderer.seeds, at: elapsed, amplitude: amplitude, shake: current.pose.shake)
        renderer.draw(in: &context, size: size, motion: motion, pose: current.pose, head: current.head, eye: current.eye)
    }
}

#if DEBUG
#Preview("Animated") {
    struct Demo: View {
        @State private var index = 0
        var body: some View {
            VStack(spacing: 24) {
                AnimatedBlobatarView("centrax", expression: BlobatarExpression.all[index]).frame(width: 160, height: 160)
                Button(BlobatarExpression.all[index].name) { index = (index + 1) % BlobatarExpression.all.count }
                HStack {
                    ForEach(["alain", "ada", "grace", "linus"], id: \.self) {
                        AnimatedBlobatarView($0).frame(width: 56, height: 56)
                    }
                }
            }
        }
    }
    return Demo()
}
#endif
#endif
