import Foundation

/// A color in OKLCh.
public struct Oklch: Sendable, Equatable {
    public var l: Double
    public var c: Double
    public var h: Double

    public init(_ l: Double, _ c: Double, _ h: Double) {
        self.l = l
        self.c = c
        self.h = h
    }

    func with(l: Double) -> Oklch { Oklch(l, c, h) }
}

/// The resolved palette: the backdrop, the body and the eyes, as `#rrggbb`.
public struct BlobatarPalette: Sendable, Equatable {
    public var bg: String
    public var head: String
    public var eye: String

    public init(bg: String, head: String, eye: String) {
        self.bg = bg
        self.head = head
        self.eye = eye
    }
}

/// Where a tinting expression heads (hue, lightness, how far of the way, chroma floor).
public struct Tint: Sendable, Hashable {
    public let h: Double
    public let l: Double
    public let pull: Double
    public let c: Double

    public static let hot = Tint(h: 27, l: 0.58, pull: 0.6, c: 0.18)
    public static let rose = Tint(h: 358, l: 0.72, pull: 0.55, c: 0.16)
    public static let blush = Tint(h: 12, l: 0.84, pull: 0.4, c: 0.1)
    public static let bile = Tint(h: 142, l: 0.66, pull: 0.6, c: 0.13)
}

/// Palette construction. Swift port of `packages/blobatar/src/color.ts`.
/// Hue (and tone) are the only things the seed controls; lightness and chroma
/// are authored, and contrast is enforced against real sRGB luminance.
public enum BlobatarColor {
    /// JS `Math.round`: half toward positive infinity.
    static func jsRound(_ v: Double) -> Double { (v + 0.5).rounded(.down) }

    static func cbrt(_ x: Double) -> Double { x >= 0 ? pow(x, 1.0 / 3) : -pow(-x, 1.0 / 3) }

    static func hypot2(_ x: Double, _ y: Double) -> Double { (x * x + y * y).squareRoot() }

    /// OKLCh to linear-light sRGB. Components may fall outside [0, 1].
    static func toLinear(_ color: Oklch) -> (Double, Double, Double) {
        let r = color.h * .pi / 180
        let a = color.c * cos(r)
        let b = color.c * sin(r)
        let l_ = color.l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = color.l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = color.l - 0.0894841775 * a - 1.291485548 * b
        let L = l_ * l_ * l_
        let M = m_ * m_ * m_
        let S = s_ * s_ * s_
        return (
            4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * S,
            -1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * S,
            -0.0041960863 * L - 0.7034186147 * M + 1.707614701 * S
        )
    }

    static func inGamut(_ rgb: (Double, Double, Double)) -> Bool {
        rgb.0 >= -1e-4 && rgb.0 <= 1 + 1e-4 && rgb.1 >= -1e-4 && rgb.1 <= 1 + 1e-4
            && rgb.2 >= -1e-4 && rgb.2 <= 1 + 1e-4
    }

    /// In-gamut linear sRGB, giving up chroma (not hue) when needed.
    static func resolve(_ color: Oklch) -> (Double, Double, Double) {
        var rgb = toLinear(color)
        if !inGamut(rgb) {
            var lo = 0.0, hi = color.c
            for _ in 0..<12 {
                let mid = (lo + hi) / 2
                if inGamut(toLinear(Oklch(color.l, mid, color.h))) { lo = mid } else { hi = mid }
            }
            rgb = toLinear(Oklch(color.l, lo, color.h))
        }
        func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
        return (clamp(rgb.0), clamp(rgb.1), clamp(rgb.2))
    }

    static func luminance(_ color: Oklch) -> Double {
        let rgb = resolve(color)
        return 0.2126 * rgb.0 + 0.7152 * rgb.1 + 0.0722 * rgb.2
    }

    public static func contrast(_ a: Oklch, _ b: Oklch) -> Double {
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// Pushes `fg`'s lightness away from `bg` until the pair clears `minimum`,
    /// in the direction it already leans first.
    public static func ensureContrast(_ fg: Oklch, _ bg: Oklch, _ minimum: Double) -> Oklch {
        if contrast(fg, bg) >= minimum { return fg }
        let lean: Double = fg.l >= bg.l ? 1 : -1
        for dir in [lean, -lean] {
            var l = fg.l
            for _ in 0..<60 {
                l = min(1.0, max(0.0, l + dir * 0.02))
                let probe = Oklch(l, fg.c, fg.h)
                if contrast(probe, bg) >= minimum { return probe }
                if l == 0 || l == 1 { break }
            }
        }
        let black = Oklch(0, 0, fg.h), white = Oklch(1, 0, fg.h)
        return contrast(black, bg) >= contrast(white, bg) ? black : white
    }

    static func hex2(_ v: Int) -> String { String(format: "%02x", v) }

    public static func toHex(_ color: Oklch) -> String {
        let rgb = resolve(color)
        var out = "#"
        for v in [rgb.0, rgb.1, rgb.2] {
            let s = v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
            out += hex2(Int(jsRound(s * 255)))
        }
        return out
    }

    static func hexValue(_ hex: String) -> Int { Int(hex.dropFirst(), radix: 16) ?? 0 }

    /// sRGB hex to OKLCh.
    public static func fromHex(_ hex: String) -> Oklch {
        let n = hexValue(hex)
        func decode(_ v: Int) -> Double {
            let s = Double(v) / 255
            return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        let r = decode((n >> 16) & 255), g = decode((n >> 8) & 255), b = decode(n & 255)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let a = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s
        let bb = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s
        return Oklch(
            0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
            hypot2(a, bb),
            atan2(bb, a) * 180 / .pi
        )
    }

    /// `color-mix(in oklab, a, b t)`: lerps cartesian a/b, not hue.
    public static func mix(_ a: Oklch, _ b: Oklch, _ t: Double) -> Oklch {
        func rad(_ v: Double) -> Double { v * .pi / 180 }
        let ax = a.c * cos(rad(a.h)), ay = a.c * sin(rad(a.h))
        let bx = b.c * cos(rad(b.h)), by = b.c * sin(rad(b.h))
        let x = ax + (bx - ax) * t, y = ay + (by - ay) * t
        return Oklch(a.l + (b.l - a.l) * t, hypot2(x, y), atan2(y, x) * 180 / .pi)
    }

    public static func mixHex(_ a: String, _ b: String, _ t: Double) -> String {
        toHex(mix(fromHex(a), fromHex(b), t))
    }

    /// An sRGB blend between two finished colors, the way a CSS fill transition travels.
    public static func fadeHex(_ a: String, _ b: String, _ t: Double) -> String {
        let x = hexValue(a), y = hexValue(b)
        var out = "#"
        for shift in [16, 8, 0] {
            let from = Double((x >> shift) & 255), to = Double((y >> shift) & 255)
            out += hex2(Int(jsRound(from + (to - from) * t)))
        }
        return out
    }

    static let tintFloor = 4.55

    /// The (head, eye) pair a tinting pose heads toward, derived from the
    /// palette the blobatar is actually wearing. Every point along the mix
    /// keeps the eyes at 4.5:1 against the body.
    public static func tinted(head: String, eye: String, _ t: Tint) -> (head: String, eye: String) {
        let base = fromHex(head)
        let baseEye = fromHex(eye)
        var hotHead = Oklch(base.l + (t.l - base.l) * t.pull, max(base.c, t.c), t.h)
        hotHead = ensureContrast(hotHead, darkSurface, surfaceFloor)
        var hotEye = ensureContrast(baseEye, hotHead, tintFloor)

        let dir: Double = hotEye.l >= hotHead.l ? 1 : -1
        let headHex = toHex(hotHead)
        for _ in 0..<40 {
            let eyeHex = toHex(hotEye)
            var worst = Double.infinity
            for i in 0...10 {
                let tt = Double(i) / 10
                worst = min(worst, contrast(fromHex(mixHex(eye, eyeHex, tt)), fromHex(mixHex(head, headHex, tt))))
            }
            if worst >= tintFloor { return (headHex, eyeHex) }
            let l = min(1.0, max(0.0, hotEye.l + dir * 0.02))
            if l == hotEye.l { return (headHex, eyeHex) }
            hotEye = hotEye.with(l: l)
        }
        return (headHex, toHex(hotEye))
    }

    /// Swatches as (upper band edge, lightness, chroma): pastel, pale neutral,
    /// mid, deep, bright, ink.
    static let tones: [(edge: Double, l: Double, c: Double)] = [
        (0.2, 0.86, 0.085),
        (0.36, 0.9, 0.028),
        (0.62, 0.73, 0.135),
        (0.8, 0.62, 0.165),
        (0.93, 0.87, 0.16),
        (1.0, 0.34, 0.035),
    ]

    /// The darkest host surface a backdrop-less body must stay visible on.
    public static let darkSurface = Oklch(0.145, 0, 0)
    public static let surfaceFloor = 1.5

    /// `#rgb`/`#rrggbb` expanded to `#rrggbb`, or nil for anything else.
    public static func plateHex(_ color: String) -> String? {
        let digits = Array(color.dropFirst())
        guard color.first == "#", digits.allSatisfy(\.isHexDigit) else { return nil }
        if digits.count == 3 { return "#" + digits.map { "\($0)\($0)" }.joined() }
        return digits.count == 6 ? color : nil
    }

    /// A plate as the neutral grey of the same luminance (all the floors read).
    static func plateGrey(_ hex: String) -> Oklch {
        let n = hexValue(hex)
        var y = 0.0
        for (shift, w) in [(16, 0.2126), (8, 0.7152), (0, 0.0722)] {
            let s = Double((n >> shift) & 255) / 255
            y += w * (s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4))
        }
        return Oklch(pow(y, 1.0 / 3), 0, 0)
    }

    /// The palette in OKLCh, before hex encoding.
    public static func ramp(hue: Double, enforce: Bool = true, tone: Double = 0, bg: String? = nil)
        -> (bg: Oklch, head: Oklch, eye: Oklch)
    {
        let t = tones.first { tone < $0.edge } ?? tones[0]
        let head = ensureContrast(Oklch(t.l, t.c, hue), darkSurface, surfaceFloor)
        var r = (
            bg: Oklch(0.965, 0.01, hue),
            head: head,
            eye: head.l >= 0.5 ? Oklch(0.17, 0.02, hue) : Oklch(0.97, 0.012, hue)
        )
        if let bg, let hex = plateHex(bg) { r.bg = plateGrey(hex) }
        if enforce {
            r.head = ensureContrast(r.head, r.bg, 1.25)
            r.eye = ensureContrast(r.eye, r.head, 4.5)
        }
        return r
    }

    /// The authored palette for a hue and tone. A plate color comes back as written.
    public static func palette(hue: Double, enforce: Bool = true, tone: Double = 0, bg: String? = nil) -> BlobatarPalette {
        let r = ramp(hue: hue, enforce: enforce, tone: tone, bg: bg)
        return BlobatarPalette(
            bg: bg.flatMap(plateHex) ?? toHex(r.bg),
            head: toHex(r.head),
            eye: toHex(r.eye)
        )
    }
}
