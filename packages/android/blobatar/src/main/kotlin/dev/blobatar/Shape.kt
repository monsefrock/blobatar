package dev.blobatar

import java.lang.StrictMath as M

/** One absolute path command; all the library emits. */
sealed interface PathSegment {
    data class MoveTo(val x: Double, val y: Double) : PathSegment
    data class LineTo(val x: Double, val y: Double) : PathSegment
    data class CubicTo(val c1x: Double, val c1y: Double, val c2x: Double, val c2y: Double, val x: Double, val y: Double) : PathSegment
    data class QuadTo(val cx: Double, val cy: Double, val x: Double, val y: Double) : PathSegment
    data class HorizontalTo(val x: Double) : PathSegment
    data class VerticalTo(val y: Double) : PathSegment
    data object Close : PathSegment
}

/** A structured path with a byte-exact SVG serialization (the TypeScript core's strings). */
data class BlobPath(val segments: List<PathSegment>) {
    fun toPathData(): String {
        val d = StringBuilder()
        for (s in segments) {
            when (s) {
                is PathSegment.MoveTo -> d.append("M${r2(s.x)} ${r2(s.y)}")
                is PathSegment.LineTo -> d.append("L${r2(s.x)} ${r2(s.y)}")
                is PathSegment.CubicTo ->
                    d.append("C${r2(s.c1x)} ${r2(s.c1y)} ${r2(s.c2x)} ${r2(s.c2y)} ${r2(s.x)} ${r2(s.y)}")
                is PathSegment.QuadTo -> d.append("Q${r2(s.cx)} ${r2(s.cy)} ${r2(s.x)} ${r2(s.y)}")
                is PathSegment.HorizontalTo -> d.append("H${r2(s.x)}")
                is PathSegment.VerticalTo -> d.append("V${r2(s.y)}")
                PathSegment.Close -> d.append("Z")
            }
        }
        return d.toString()
    }

    companion object {
        /**
         * Two decimals, `-0` as `0`, no trailing zeros: JS `String(Number)` of the rounded value,
         * formatted from the integer hundredths (exactly the shortest form at this precision, and
         * independent of the runtime's `Double.toString`).
         */
        fun r2(v: Double): String {
            val hundredths = M.floor(v * 100 + 0.5).toLong()
            if (hundredths == 0L) return "0"
            val magnitude = Math.abs(hundredths)
            val out = StringBuilder(if (hundredths < 0) "-" else "")
            out.append(magnitude / 100)
            val fraction = (magnitude % 100).toInt()
            if (fraction != 0) {
                out.append('.')
                if (fraction % 10 == 0) out.append(fraction / 10)
                else { if (fraction < 10) out.append('0'); out.append(fraction) }
            }
            return out.toString()
        }
    }
}

/** The path primitives. Kotlin port of `packages/blobatar/src/shape.ts`. */
object BlobShape {
    /** `|x/a|^n + |y/b|^n = 1`, one cubic per quadrant through the 45 degree point. */
    fun superellipse(cx: Double, cy: Double, rx: Double, ry: Double, n: Double = 4.0, rot: Double = 0.0): BlobPath {
        val k = minOf(1.0, (8 * M.pow(2.0, -1 / n) - 4) / 3)
        val a = rx
        val b = ry
        val ak = a * k
        val bk = b * k
        val xs = doubleArrayOf(a, a, ak, 0.0, -ak, -a, -a, -a, -ak, 0.0, ak, a, a)
        val ys = doubleArrayOf(0.0, bk, b, b, b, bk, 0.0, -bk, -b, -b, -b, -bk, 0.0)
        val t = rot * Math.PI / 180
        val cos = M.cos(t)
        val sin = M.sin(t)
        fun x(i: Int) = cx + xs[i] * cos - ys[i] * sin
        fun y(i: Int) = cy + xs[i] * sin + ys[i] * cos
        val segments = mutableListOf<PathSegment>(PathSegment.MoveTo(x(0), y(0)))
        for (i in 1 until 13 step 3) {
            segments += PathSegment.CubicTo(x(i), y(i), x(i + 1), y(i + 1), x(i + 2), y(i + 2))
        }
        segments += PathSegment.Close
        return BlobPath(segments)
    }

    /** Radii sampled around a circle, joined by a closed Catmull-Rom spline. */
    fun blobPath(cx: Double, cy: Double, rx: Double, ry: Double, radii: List<Double>, rot: Double = 0.0): BlobPath {
        val n = radii.size
        val t0 = rot * Math.PI / 180
        val px = DoubleArray(n) { cx + rx * radii[it] * M.cos(t0 + 2 * Math.PI * it / n) }
        val py = DoubleArray(n) { cy + ry * radii[it] * M.sin(t0 + 2 * Math.PI * it / n) }
        fun w(i: Int) = ((i % n) + n) % n
        val segments = mutableListOf<PathSegment>(PathSegment.MoveTo(px[w(0)], py[w(0)]))
        for (i in 0 until n) {
            val i0 = w(i - 1); val i1 = w(i); val i2 = w(i + 1); val i3 = w(i + 2)
            segments += PathSegment.CubicTo(
                px[i1] + (px[i2] - px[i0]) / 6, py[i1] + (py[i2] - py[i0]) / 6,
                px[i2] - (px[i3] - px[i1]) / 6, py[i2] - (py[i3] - py[i1]) / 6,
                px[i2], py[i2],
            )
        }
        segments += PathSegment.Close
        return BlobPath(segments)
    }

    /** A regular polygon (vertex on top), corners cut back by [round] and joined through the vertex. */
    fun polygon(cx: Double, cy: Double, rx: Double, ry: Double, sides: Int, round: Double = 0.3, rot: Double = 0.0): BlobPath {
        val k = if (round > 0) (if (round < 1) round / 2 else 0.5) else 0.0
        val t0 = rot * Math.PI / 180 - Math.PI / 2
        val vx = DoubleArray(sides) { cx + rx * M.cos(t0 + 2 * Math.PI * it / sides) }
        val vy = DoubleArray(sides) { cy + ry * M.sin(t0 + 2 * Math.PI * it / sides) }
        fun w(i: Int) = ((i % sides) + sides) % sides
        fun cutX(i: Int, j: Int) = vx[w(i)] + (vx[w(j)] - vx[w(i)]) * k
        fun cutY(i: Int, j: Int) = vy[w(i)] + (vy[w(j)] - vy[w(i)]) * k
        val segments = mutableListOf<PathSegment>(PathSegment.MoveTo(cutX(0, -1), cutY(0, -1)))
        for (i in 0 until sides) {
            segments += PathSegment.QuadTo(vx[w(i)], vy[w(i)], cutX(i, i + 1), cutY(i, i + 1))
            if (k < 0.5) segments += PathSegment.LineTo(cutX(i + 1, i), cutY(i + 1, i))
        }
        segments += PathSegment.Close
        return BlobPath(segments)
    }

    /** A plain box (the straight run of a capsule). */
    fun box(cx: Double, cy: Double, rx: Double, ry: Double) = BlobPath(listOf(
        PathSegment.MoveTo(cx - rx, cy - ry),
        PathSegment.HorizontalTo(cx + rx),
        PathSegment.VerticalTo(cy + ry),
        PathSegment.HorizontalTo(cx - rx),
        PathSegment.Close,
    ))

    /** A droplet's taper: the two tangents from an apex to the body ellipse, eased at the tip. */
    fun taper(cx: Double, cy: Double, rx: Double, ry: Double, tip: Double): BlobPath {
        val t = maxOf(1.05, tip)
        val tx = rx * M.sqrt(1 - 1 / (t * t))
        val ty = cy - ry / t
        val apex = cy - t * ry
        val px = tx * 0.14
        val py = ty + 0.86 * (apex - ty)
        return BlobPath(listOf(
            PathSegment.MoveTo(cx - tx, ty),
            PathSegment.LineTo(cx - px, py),
            PathSegment.QuadTo(cx, apex, cx + px, py),
            PathSegment.LineTo(cx + tx, ty),
            PathSegment.Close,
        ))
    }
}
