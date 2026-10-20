package dev.blobatar

import java.lang.StrictMath as M

/** A color in OKLCh. */
data class Oklch(val l: Double, val c: Double, val h: Double)

/** The resolved palette: backdrop, body and eyes, as `#rrggbb`. */
data class BlobatarPalette(val bg: String, val head: String, val eye: String)

/** Where a tinting expression heads (hue, lightness, how far of the way, chroma floor). */
data class Tint(val h: Double, val l: Double, val pull: Double, val c: Double) {
    companion object {
        val Hot = Tint(27.0, 0.58, 0.6, 0.18)
        val Rose = Tint(358.0, 0.72, 0.55, 0.16)
        val Blush = Tint(12.0, 0.84, 0.4, 0.1)
        val Bile = Tint(142.0, 0.66, 0.6, 0.13)
    }
}

/**
 * Palette construction. Kotlin port of `packages/blobatar/src/color.ts`.
 *
 * Math goes through [StrictMath] (fdlibm), the same library V8 ports, so results do not depend
 * on the device's intrinsics.
 */
object BlobatarColor {
    internal fun jsRound(v: Double): Double = M.floor(v + 0.5)

    private fun cbrt(x: Double): Double = if (x >= 0) M.pow(x, 1.0 / 3) else -M.pow(-x, 1.0 / 3)

    internal fun hypot2(x: Double, y: Double): Double = M.sqrt(x * x + y * y)

    private class Rgb(val r: Double, val g: Double, val b: Double)

    private fun toLinear(color: Oklch): Rgb {
        val r = color.h * Math.PI / 180
        val a = color.c * M.cos(r)
        val b = color.c * M.sin(r)
        val l_ = color.l + 0.3963377774 * a + 0.2158037573 * b
        val m_ = color.l - 0.1055613458 * a - 0.0638541728 * b
        val s_ = color.l - 0.0894841775 * a - 1.291485548 * b
        val l3 = l_ * l_ * l_
        val m3 = m_ * m_ * m_
        val s3 = s_ * s_ * s_
        return Rgb(
            4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3,
            -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3,
            -0.0041960863 * l3 - 0.7034186147 * m3 + 1.707614701 * s3,
        )
    }

    private fun inGamut(c: Rgb) = c.r >= -1e-4 && c.r <= 1 + 1e-4 && c.g >= -1e-4 && c.g <= 1 + 1e-4 &&
        c.b >= -1e-4 && c.b <= 1 + 1e-4

    /** In-gamut linear sRGB, giving up chroma (not hue) when needed. */
    private fun resolve(color: Oklch): Rgb {
        var rgb = toLinear(color)
        if (!inGamut(rgb)) {
            var lo = 0.0
            var hi = color.c
            repeat(12) {
                val mid = (lo + hi) / 2
                if (inGamut(toLinear(Oklch(color.l, mid, color.h)))) lo = mid else hi = mid
            }
            rgb = toLinear(Oklch(color.l, lo, color.h))
        }
        return Rgb(rgb.r.coerceIn(0.0, 1.0), rgb.g.coerceIn(0.0, 1.0), rgb.b.coerceIn(0.0, 1.0))
    }

    private fun luminance(color: Oklch): Double {
        val c = resolve(color)
        return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
    }

    fun contrast(a: Oklch, b: Oklch): Double {
        val x = luminance(a)
        val y = luminance(b)
        return (maxOf(x, y) + 0.05) / (minOf(x, y) + 0.05)
    }

    /** Pushes [fg]'s lightness away from [bg] until the pair clears [min], leaning first. */
    fun ensureContrast(fg: Oklch, bg: Oklch, min: Double): Oklch {
        if (contrast(fg, bg) >= min) return fg
        val lean = if (fg.l >= bg.l) 1.0 else -1.0
        for (dir in doubleArrayOf(lean, -lean)) {
            var l = fg.l
            for (i in 0 until 60) {
                l = minOf(1.0, maxOf(0.0, l + dir * 0.02))
                val probe = Oklch(l, fg.c, fg.h)
                if (contrast(probe, bg) >= min) return probe
                if (l == 0.0 || l == 1.0) break
            }
        }
        val black = Oklch(0.0, 0.0, fg.h)
        val white = Oklch(1.0, 0.0, fg.h)
        return if (contrast(black, bg) >= contrast(white, bg)) black else white
    }

    private fun hex2(v: Int) = "%02x".format(v)

    fun toHex(color: Oklch): String {
        val c = resolve(color)
        val out = StringBuilder("#")
        for (v in doubleArrayOf(c.r, c.g, c.b)) {
            val s = if (v <= 0.0031308) 12.92 * v else 1.055 * M.pow(v, 1 / 2.4) - 0.055
            out.append(hex2(jsRound(s * 255).toInt()))
        }
        return out.toString()
    }

    internal fun hexValue(hex: String): Int = hex.substring(1).toInt(16)

    fun fromHex(hex: String): Oklch {
        val n = hexValue(hex)
        fun decode(v: Int): Double {
            val s = v / 255.0
            return if (s <= 0.04045) s / 12.92 else M.pow((s + 0.055) / 1.055, 2.4)
        }
        val r = decode((n shr 16) and 255)
        val g = decode((n shr 8) and 255)
        val b = decode(n and 255)
        val l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        val m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        val s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        val a = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s
        val bb = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s
        return Oklch(
            0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
            hypot2(a, bb),
            M.atan2(bb, a) * 180 / Math.PI,
        )
    }

    /** `color-mix(in oklab, a, b t)`: lerps cartesian a/b, not hue. */
    fun mix(a: Oklch, b: Oklch, t: Double): Oklch {
        fun rad(v: Double) = v * Math.PI / 180
        val ax = a.c * M.cos(rad(a.h))
        val ay = a.c * M.sin(rad(a.h))
        val bx = b.c * M.cos(rad(b.h))
        val by = b.c * M.sin(rad(b.h))
        val x = ax + (bx - ax) * t
        val y = ay + (by - ay) * t
        return Oklch(a.l + (b.l - a.l) * t, hypot2(x, y), M.atan2(y, x) * 180 / Math.PI)
    }

    fun mixHex(a: String, b: String, t: Double): String = toHex(mix(fromHex(a), fromHex(b), t))

    /** An sRGB blend between two finished colors, the way a CSS fill transition travels. */
    fun fadeHex(a: String, b: String, t: Double): String {
        val x = hexValue(a)
        val y = hexValue(b)
        val out = StringBuilder("#")
        for (shift in intArrayOf(16, 8, 0)) {
            val from = ((x shr shift) and 255).toDouble()
            val to = ((y shr shift) and 255).toDouble()
            out.append(hex2(jsRound(from + (to - from) * t).toInt()))
        }
        return out.toString()
    }

    private const val TINT_FLOOR = 4.55

    /** The (head, eye) pair a tinting pose heads toward, keeping 4.5:1 along the whole mix. */
    fun tinted(head: String, eye: String, t: Tint): Pair<String, String> {
        val base = fromHex(head)
        val baseEye = fromHex(eye)
        var hotHead = Oklch(base.l + (t.l - base.l) * t.pull, maxOf(base.c, t.c), t.h)
        hotHead = ensureContrast(hotHead, DARK_SURFACE, SURFACE_FLOOR)
        var hotEye = ensureContrast(baseEye, hotHead, TINT_FLOOR)
        val dir = if (hotEye.l >= hotHead.l) 1.0 else -1.0
        val headHex = toHex(hotHead)
        repeat(40) {
            val eyeHex = toHex(hotEye)
            var worst = Double.POSITIVE_INFINITY
            for (i in 0..10) {
                val tt = i / 10.0
                worst = minOf(worst, contrast(fromHex(mixHex(eye, eyeHex, tt)), fromHex(mixHex(head, headHex, tt))))
            }
            if (worst >= TINT_FLOOR) return headHex to eyeHex
            val l = minOf(1.0, maxOf(0.0, hotEye.l + dir * 0.02))
            if (l == hotEye.l) return headHex to eyeHex
            hotEye = hotEye.copy(l = l)
        }
        return headHex to toHex(hotEye)
    }

    /** (upper band edge, lightness, chroma): pastel, pale neutral, mid, deep, bright, ink. */
    private val tones = listOf(
        doubleArrayOf(0.2, 0.86, 0.085),
        doubleArrayOf(0.36, 0.9, 0.028),
        doubleArrayOf(0.62, 0.73, 0.135),
        doubleArrayOf(0.8, 0.62, 0.165),
        doubleArrayOf(0.93, 0.87, 0.16),
        doubleArrayOf(1.0, 0.34, 0.035),
    )

    /** The darkest host surface a backdrop-less body must stay visible on. */
    val DARK_SURFACE = Oklch(0.145, 0.0, 0.0)
    const val SURFACE_FLOOR = 1.5

    private val shortHex = Regex("^#([0-9a-fA-F])([0-9a-fA-F])([0-9a-fA-F])$")
    private val longHex = Regex("^#[0-9a-fA-F]{6}$")

    /** `#rgb`/`#rrggbb` expanded to `#rrggbb`, or null for anything else. */
    fun plateHex(color: String): String? {
        val m = shortHex.find(color)
        val hex = if (m == null) color else "#" + m.groupValues.drop(1).joinToString("") { it + it }
        return if (longHex.matches(hex)) hex else null
    }

    private fun plateGrey(hex: String): Oklch {
        val n = hexValue(hex)
        var y = 0.0
        for ((shift, w) in listOf(16 to 0.2126, 8 to 0.7152, 0 to 0.0722)) {
            val s = ((n shr shift) and 255) / 255.0
            y += w * (if (s <= 0.04045) s / 12.92 else M.pow((s + 0.055) / 1.055, 2.4))
        }
        return Oklch(M.pow(y, 1.0 / 3), 0.0, 0.0)
    }

    data class Ramp(val bg: Oklch, val head: Oklch, val eye: Oklch)

    /** The palette in OKLCh, before hex encoding. */
    fun ramp(hue: Double, enforce: Boolean = true, tone: Double = 0.0, bg: String? = null): Ramp {
        val t = tones.firstOrNull { tone < it[0] } ?: tones[0]
        val head = ensureContrast(Oklch(t[1], t[2], hue), DARK_SURFACE, SURFACE_FLOOR)
        var r = Ramp(
            Oklch(0.965, 0.01, hue),
            head,
            if (head.l >= 0.5) Oklch(0.17, 0.02, hue) else Oklch(0.97, 0.012, hue),
        )
        val plate = bg?.let(::plateHex)
        if (plate != null) r = r.copy(bg = plateGrey(plate))
        if (enforce) {
            r = r.copy(head = ensureContrast(r.head, r.bg, 1.25))
            r = r.copy(eye = ensureContrast(r.eye, r.head, 4.5))
        }
        return r
    }

    /** The authored palette for a hue and tone. A plate color comes back as written. */
    fun palette(hue: Double, enforce: Boolean = true, tone: Double = 0.0, bg: String? = null): BlobatarPalette {
        val r = ramp(hue, enforce, tone, bg)
        return BlobatarPalette(bg?.let(::plateHex) ?: toHex(r.bg), toHex(r.head), toHex(r.eye))
    }
}
