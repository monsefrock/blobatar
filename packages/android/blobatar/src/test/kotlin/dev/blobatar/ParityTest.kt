package dev.blobatar

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * The cross-language parity gate, against the fixture exported from the TypeScript core (shared
 * with the Flutter port). Exact where the fixture says exact; layout floats within 1e-9.
 */
@Suppress("UNCHECKED_CAST")
class ParityTest {
    companion object {
        val vectors: Map<String, Any?> by lazy {
            var dir = File("").absoluteFile
            while (!File(dir, "flutter/test/fixtures/reference-vectors.json").exists()) dir = dir.parentFile!!
            Json(File(dir, "flutter/test/fixtures/reference-vectors.json").readText()).value() as Map<String, Any?>
        }

        fun close(a: Double, b: Double, tol: Double = 1e-9): Boolean {
            if (a == b || (a.isNaN() && b.isNaN())) return true
            return Math.abs(a - b) <= tol * maxOf(1.0, maxOf(Math.abs(a), Math.abs(b)))
        }

        fun overrides(json: Any?): Map<String, TraitOverride>? {
            val map = json as? Map<String, Any?> ?: return null
            if (map.isEmpty()) return null
            return map.mapValues { (_, v) ->
                if (v is List<*>) TraitOverride.AnyOf(v.map { it as Double }) else TraitOverride.Value(v as Double)
            }
        }

        fun options(json: Map<String, Any?>, expression: BlobatarExpression? = null) = BlobatarOptions(
            hue = json["hue"] as Double?,
            tone = json["tone"] as Double?,
            traits = overrides(json["traits"]),
            normalize = json["normalize"] as Boolean? ?: true,
            contrast = json["contrast"] as Boolean? ?: true,
            expression = expression,
        )

        /** null when the case matches, else the first field that does not. */
        fun check(b: Blobatar, c: Map<String, Any?>, pathsAndBody: Boolean = true): String? {
            val l = b.layout
            if (l.shape.id != c["shape"]) return "shape ${l.shape.id} != ${c["shape"]}"
            val eyes = c["eyes"] as List<Map<String, Any?>>
            if (l.eyes.size != eyes.size) return "eyes.size"
            for ((i, e) in eyes.withIndex()) {
                val a = l.eyes[i]
                for ((k, v) in listOf("cx" to a.cx, "cy" to a.cy, "rx" to a.rx, "ry" to a.ry, "n" to a.n, "rot" to a.rot)) {
                    if (!close(v, e[k] as Double)) return "eye$i.$k $v != ${e[k]}"
                }
            }
            val pal = c["palette"] as Map<String, Any?>
            val expected = BlobatarPalette(pal["bg"] as String, pal["head"] as String, pal["eye"] as String)
            if (b.palette != expected) return "palette ${b.palette} != $expected"
            if (!pathsAndBody) return null

            val body = c["body"] as Map<String, Any?>
            for ((k, v) in listOf("cx" to l.body.cx, "cy" to l.body.cy, "rx" to l.body.rx, "ry" to l.body.ry, "n" to l.body.n, "rot" to l.body.rot)) {
                if (!close(v, body[k] as Double)) return "body.$k"
            }
            val radii = body["radii"] as List<Double>
            if (l.body.radii.size != radii.size) return "radii.size"
            for ((i, r) in radii.withIndex()) if (!close(l.body.radii[i], r)) return "radii[$i]"
            (body["sides"] as Double?)?.let { if (l.body.sides != it.toInt()) return "sides" }
            (body["round"] as Double?)?.let { if (!close(l.body.round ?: Double.NaN, it)) return "round" }

            val face = c["face"] as Map<String, Any?>
            for ((k, v) in listOf("cx" to l.face.cx, "cy" to l.face.cy, "rx" to l.face.rx, "ry" to l.face.ry)) {
                if (!close(v, face[k] as Double)) return "face.$k"
            }
            val petals = c["petals"] as List<Map<String, Any?>>
            if (l.petals.size != petals.size) return "petals.size"
            for ((i, p) in petals.withIndex()) {
                val a = l.petals[i]
                if (!close(a.cx, p["cx"] as Double) || !close(a.cy, p["cy"] as Double) || !close(a.r, p["r"] as Double)) return "petals[$i]"
            }
            if (l.extra.map { it.toPathData() } != c["extra"]) return "extra"
            val bodyPath = l.bodyPath().toPathData()
            if (bodyPath != c["bodyPath"]) return "bodyPath $bodyPath != ${c["bodyPath"]}"
            if (l.eyePaths().map { it.toPathData() } != c["eyePaths"]) return "eyePaths"
            return null
        }
    }

    @Test fun normalizationAgreesByteForByte() {
        for (v in vectors["hash"] as List<Map<String, Any?>>) {
            assertEquals("normalizeSeed(${v["seed"]})", v["normalized"], BlobatarHash.normalizeSeed(v["seed"] as String))
        }
    }

    @Test fun seedStatesAndStreamsAgreeExactly() {
        for (v in vectors["hash"] as List<Map<String, Any?>>) {
            val seed = v["seed"] as String
            val state = BlobatarHash.seedState(seed)
            assertEquals("seedState($seed)", (v["state"] as Double).toLong(), state.toLong())
            for ((key, expected) in v["streams"] as Map<String, Any?>) {
                assertEquals("stream($seed, $key)", expected as Double, BlobatarHash.stream(state, key), 0.0)
            }
        }
    }

    @Test fun overrideReadsAgreeExactly() {
        for (v in vectors["overrides"] as List<Map<String, Any?>>) {
            val t = Traits(v["seed"] as String, overrides = overrides(v["overrides"]))
            for ((key, expected) in v["values"] as Map<String, Any?>) {
                assertEquals("${v["seed"]} $key", expected as Double, t(key), 0.0)
            }
        }
    }

    @Test fun paletteVectors() {
        for (v in vectors["palette"] as List<Map<String, Any?>>) {
            val hue = v["hue"] as Double
            val tone = v["tone"] as Double
            val hex = v["hex"] as Map<String, Any?>
            assertEquals("h=$hue t=$tone", BlobatarPalette(hex["bg"] as String, hex["head"] as String, hex["eye"] as String),
                BlobatarColor.palette(hue, true, tone))
            val raw = v["rampUnenforced"] as Map<String, Map<String, Any?>>
            val r = BlobatarColor.ramp(hue, false, tone)
            for ((key, color) in listOf("bg" to r.bg, "head" to r.head, "eye" to r.eye)) {
                assertTrue("$key.l h=$hue t=$tone", close(color.l, raw[key]!!["l"] as Double))
                assertTrue("$key.c h=$hue t=$tone", close(color.c, raw[key]!!["c"] as Double))
                assertTrue("$key.h h=$hue t=$tone", close(color.h, raw[key]!!["h"] as Double))
            }
        }
    }

    @Test fun allLayoutCasesAgreeWithTheTypeScriptCore() {
        val cases = vectors["cases"] as List<Map<String, Any?>>
        assertEquals(1570, cases.size)
        val failures = cases.mapNotNull { c ->
            check(Blobatar(c["seed"] as String, options(c["options"] as Map<String, Any?>)), c)
                ?.let { "seed=${c["seed"]} options=${c["options"]}: $it" }
        }
        assertEquals("first: ${failures.firstOrNull()}", 0, failures.size)
    }

    @Test fun expressionCasesAgree() {
        val expressions = vectors["expressions"] as Map<String, Map<String, Any?>>
        assertEquals(BlobatarExpression.all.map { it.name }.toSet(), expressions.keys)
        for ((name, data) in expressions) {
            val expression = BlobatarExpression.named(name)!!
            val p = expression.pose
            val mine = mapOf("esx" to p.esx, "esy" to p.esy, "tilt" to p.tilt, "edy" to p.edy, "edx" to p.edx,
                "esx2" to p.esx2, "esy2" to p.esy2, "tilt2" to p.tilt2, "edy2" to p.edy2, "lock" to p.lock,
                "heat" to p.heat, "shake" to p.shake, "rock" to p.rock, "bdy" to p.bdy)
            assertEquals(name, data["pose"], mine)
            for (c in data["cases"] as List<Map<String, Any?>>) {
                val b = Blobatar(c["seed"] as String, options(c["options"] as Map<String, Any?>, expression))
                assertEquals(p.bdy, b.layout.bodyOffsetY, 0.0)
                assertNull("$name ${c["seed"]}", check(b, c, pathsAndBody = false))
            }
        }
    }

    @Test fun r2MatchesJavaScriptNumberFormatting() {
        assertEquals("0", BlobPath.r2(-0.001))
        assertEquals("12", BlobPath.r2(12.0))
        assertEquals("12.3", BlobPath.r2(12.3))
        assertEquals("12.35", BlobPath.r2(12.345))
        assertEquals("-0.05", BlobPath.r2(-0.05))
        assertEquals("0.07", BlobPath.r2(0.07))
    }
}

/** A minimal JSON reader: numbers become exact Doubles via `toDouble()`. */
private class Json(private val s: String) {
    private var i = 0

    fun value(): Any? {
        ws()
        return when (s[i]) {
            '{' -> obj()
            '[' -> arr()
            '"' -> str()
            't' -> { i += 4; true }
            'f' -> { i += 5; false }
            'n' -> { i += 4; null }
            else -> num()
        }
    }

    private fun ws() { while (i < s.length && s[i].isWhitespace()) i++ }

    private fun obj(): Map<String, Any?> {
        val out = LinkedHashMap<String, Any?>()
        i++; ws()
        if (s[i] == '}') { i++; return out }
        while (true) {
            ws(); val k = str(); ws(); i++ // ':'
            out[k] = value(); ws()
            if (s[i++] == '}') return out
        }
    }

    private fun arr(): List<Any?> {
        val out = ArrayList<Any?>()
        i++; ws()
        if (s[i] == ']') { i++; return out }
        while (true) {
            out += value(); ws()
            if (s[i++] == ']') return out
        }
    }

    private fun str(): String {
        val out = StringBuilder()
        i++
        while (s[i] != '"') {
            if (s[i] == '\\') {
                i++
                when (s[i]) {
                    'n' -> out.append('\n'); 't' -> out.append('\t'); 'r' -> out.append('\r')
                    'b' -> out.append('\b'); 'f' -> out.append('\u000c')
                    'u' -> { out.append(s.substring(i + 1, i + 5).toInt(16).toChar()); i += 4 }
                    else -> out.append(s[i])
                }
            } else out.append(s[i])
            i++
        }
        i++
        return out.toString()
    }

    private fun num(): Double {
        val start = i
        while (i < s.length && (s[i].isDigit() || s[i] in "+-.eE")) i++
        return s.substring(start, i).toDouble()
    }
}
