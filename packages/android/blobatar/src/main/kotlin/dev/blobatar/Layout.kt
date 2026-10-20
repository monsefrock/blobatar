package dev.blobatar

import java.lang.StrictMath as M

/** The core body a silhouette draws and patches. */
data class Body(
    val cx: Double, val cy: Double, val rx: Double, val ry: Double, val n: Double, val rot: Double,
    val radii: List<Double>,
    /** Polygon-only. */
    val sides: Int? = null,
    val round: Double? = null,
)

/** An ellipse-shaped region: the face the eyes must fit inside. */
data class Ellipse(val cx: Double, val cy: Double, val rx: Double, val ry: Double)

/** A circle unioned with the body (petals, caps, lobes, sun rays). */
data class Petal(val cx: Double, val cy: Double, val r: Double)

/** One fitted eye. */
data class Eye(val cx: Double, val cy: Double, val rx: Double, val ry: Double, val n: Double, val rot: Double)

/** The ten-shape gen-2 vocabulary, in band order, with each band's upper edge. Frozen per major. */
enum class BlobatarShape(val id: String, internal val upTo: Double, internal val core: Double) {
    Round("round", 0.22, 1.0),
    Organic("organic", 0.48, 0.98),
    Boxy("boxy", 0.6, 0.86),
    Capsule("capsule", 0.7, 1.02),
    Nub("nub", 0.79, 0.88),
    Cloud("cloud", 0.86, 0.78),
    Droplet("droplet", 0.915, 0.78),
    Hexagon("hexagon", 0.95, 1.05),
    Sun("sun", 0.98, 0.7),
    Triangle("triangle", 1.0, 1.15);

    /** Patches the body before the face is measured. */
    internal fun patch(t: Traits, b: Body): Body = when (this) {
        Boxy -> b.copy(n = t.num("body.n", 3.4, 6.0), rot = t.num("body.rot", -20.0, 20.0))
        Capsule -> b.copy(ry = b.ry * t.num("capsule.squat", 0.55, 0.68))
        Droplet -> b.copy(cy = b.cy + 0.22 * b.ry, n = 2.0)
        Hexagon -> b.copy(sides = 6, rot = t.num("body.rot", -12.0, 12.0), round = t.num("poly.round", 0.24, 0.5))
        Triangle -> b.copy(sides = 3, rot = t.num("body.rot", -5.0, 5.0), round = t.num("poly.round", 0.24, 0.5))
        else -> b
    }

    private fun shrunk(b: Body, k: Double) = Ellipse(b.cx, b.cy, b.rx * k, b.ry * k)

    /** The region the eyes fit inside; null means the body itself. */
    internal fun face(b: Body): Ellipse? = when (this) {
        Organic, Cloud -> shrunk(b, b.radii.min() * 0.95)
        Capsule -> shrunk(b, 0.94)
        Droplet -> Ellipse(b.cx, b.cy + b.ry * 0.05, b.rx * 0.88, b.ry * 0.88)
        Hexagon -> shrunk(b, 0.84)
        Triangle -> Ellipse(b.cx, b.cy + b.ry * 0.1, b.rx * 0.54, b.ry * 0.36)
        else -> null
    }

    internal fun decorate(t: Traits, b: Body, petals: MutableList<Petal>, extra: MutableList<BlobPath>) {
        when (this) {
            Capsule -> for (s in intArrayOf(-1, 1)) petals += Petal(b.cx + s * (b.rx - b.ry), b.cy, b.ry)
            Nub -> for (i in 0 until t.int("nub.n", 1, 2)) {
                val a = t.num("nub.a$i", 0.0, 2 * Math.PI)
                petals += Petal(b.cx + M.cos(a) * b.rx * 0.88, b.cy + M.sin(a) * b.rx * 0.88, b.rx * t.num("nub.r$i", 0.24, 0.4))
            }
            Cloud -> {
                val count = t.int("cloud.n", 4, 6)
                for (i in 0 until count) {
                    val a = Math.PI + (Math.PI * (i + 0.5)) / count
                    petals += Petal(b.cx + M.cos(a) * b.rx * 0.8, b.cy + M.sin(a) * b.rx * 0.5, b.rx * t.num("cloud.r$i", 0.44, 0.62))
                }
            }
            Droplet -> extra += BlobShape.taper(b.cx, b.cy, b.rx, b.ry, t.num("droplet.tip", 1.4, 1.65))
            Sun -> {
                val count = t.int("sun.n", 6, 9)
                val dist = b.rx * t.num("sun.dist", 1.0, 1.08)
                val pr = b.rx * t.num("sun.r", 0.2, 0.26)
                val off = t.num("sun.rot", 0.0, 2 * Math.PI)
                for (i in 0 until count) {
                    val a = off + (2 * Math.PI * i) / count
                    petals += Petal(b.cx + M.cos(a) * dist, b.cy + M.sin(a) * dist, pr)
                }
            }
            else -> Unit
        }
    }

    /** The core path; null means a superellipse. */
    internal fun path(b: Body): BlobPath? = when (this) {
        Organic, Cloud -> BlobShape.blobPath(b.cx, b.cy, b.rx, b.ry, b.radii, b.rot)
        Capsule -> BlobShape.box(b.cx, b.cy, b.rx - b.ry, b.ry)
        Hexagon, Triangle -> BlobShape.polygon(b.cx, b.cy, b.rx, b.ry, b.sides ?: 6, b.round ?: 0.3, b.rot)
        else -> null
    }

    companion object {
        internal fun pick(v: Double): BlobatarShape = entries.firstOrNull { v < it.upTo } ?: Triangle
    }
}

/** The resolved layout for one seed in a 100 x 100 viewBox. */
data class BlobatarLayout(
    val shape: BlobatarShape,
    val body: Body,
    val face: Ellipse,
    val eyes: List<Eye>,
    val petals: List<Petal>,
    val extra: List<BlobPath>,
    val bodyOffsetY: Double = 0.0,
) {
    /** The core body's path: the shape's own, or a superellipse. */
    fun bodyPath(): BlobPath = shape.path(body) ?: BlobShape.superellipse(body.cx, body.cy, body.rx, body.ry, body.n, body.rot)

    fun eyePaths(): List<BlobPath> = eyes.map { BlobShape.superellipse(it.cx, it.cy, it.rx, it.ry, it.n, it.rot) }

    /** Bakes a static pose into the eye geometry and body offset. */
    fun posed(pose: Pose): BlobatarLayout = copy(
        eyes = eyes.mapIndexed { i, e ->
            val second = i == 1
            val side = if (i == 0) -1.0 else 1.0
            Eye(
                e.cx + pose.edx * side,
                e.cy + pose.edy + (if (second) pose.edy2 else 0.0),
                e.rx * (pose.esx + (if (second) pose.esx2 else 0.0)),
                e.ry * (pose.esy + (if (second) pose.esy2 else 0.0)),
                e.n,
                e.rot * (1 - pose.lock) + (pose.tilt + (if (second) pose.tilt2 else 0.0)) * side,
            )
        },
        bodyOffsetY = pose.bdy,
    )

    companion object {
        /** Resolves one seed's traits into the full layout (Blobatar 2's style). */
        fun make(t: Traits): BlobatarLayout {
            val shape = BlobatarShape.pick(t("shape"))
            val r = t.num("body.r", 31.0, 38.0) * shape.core
            var body = Body(
                cx = 50 + t.jitter("body.x", 1.5),
                cy = 50 + t.jitter("body.y", 1.5),
                rx = r,
                ry = r * t.num("body.ratio", 0.92, 1.08),
                n = t.num("body.n", 1.9, 2.5),
                rot = 0.0,
                radii = List(t.int("body.pts", 6, 8)) { 1 + t.jitter("body.r$it", 0.16) },
            )
            body = shape.patch(t, body)
            val face = shape.face(body) ?: Ellipse(body.cx, body.cy, body.rx, body.ry)
            val petals = mutableListOf<Petal>()
            val extra = mutableListOf<BlobPath>()
            shape.decorate(t, body, petals, extra)
            return BlobatarLayout(shape, body, face, faceFit(t, body, face), petals, extra)
        }

        private fun faceFit(t: Traits, b: Body, face: Ellipse): List<Eye> {
            val rx = b.rx
            val er0 = t.num("eye.rx", 0.075, 0.105) * rx
            val ratio = t.num("eye.ratio", 1.9, 3.2)
            val scale = t.num("eye.scale", 0.78, 1.24)
            val stretch = t.num("eye.stretch", 0.85, 1.18)
            val clearance = t.num("eye.gap", 0.1, 0.24) * rx
            val wide = er0 * maxOf(1.0, scale)
            val tall = er0 * ratio * maxOf(1.0, scale * stretch)
            val gap0 = wide + rx * 0.03 + clearance

            val gx = t.jitter("gaze.x", 0.09) * face.rx
            val gy = t.num("gaze.y", -0.2, 0.08) * face.ry
            val dy = t.jitter("eye.dy", 0.04) * face.ry
            val reach = BlobatarColor.hypot2(wide, tall)
            val need = BlobatarColor.hypot2((Math.abs(gx) + gap0 + reach) / face.rx, (Math.abs(gy) + Math.abs(dy) + reach) / face.ry)
            val fit = if (need > 0.9) 0.9 / need else 1.0

            val er = er0 * fit
            val eyeRy = er * ratio
            val gap = gap0 * fit
            val room = maxOf(0.0, minOf(1.0, clearance / tall))
            val bound = minOf(12.0, M.asin(room) * 180 / Math.PI)
            val lean = t.num("eye.lean", -1.0, 1.0) * bound
            val lean2 = maxOf(-12.0, minOf(12.0, lean + t.jitter("eye.lean2", 3.5)))

            val cx = face.cx + gx * fit
            val cy = face.cy + gy * fit
            return listOf(
                Eye(cx - gap, cy, er, eyeRy, t.num("eye.n", 3.5, 6.0), lean),
                Eye(cx + gap, cy + dy * fit, er * scale, eyeRy * scale * stretch, t.num("eye.n", 3.5, 6.0), lean2),
            )
        }
    }
}
