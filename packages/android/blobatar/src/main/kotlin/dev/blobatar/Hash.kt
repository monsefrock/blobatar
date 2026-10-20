package dev.blobatar

import java.text.Normalizer

/**
 * Seed hashing. Kotlin port of `packages/blobatar/src/hash.ts` (via the Dart port at 2.4.0).
 *
 * The seed is hashed once; each trait key continues from that state, so trait values are
 * independent of one another. Kotlin's `Int` multiplication already wraps like JavaScript's
 * `Math.imul`, so the uint32 semantics come for free.
 */
object BlobatarHash {
    private const val SEPARATOR = 0xff

    internal fun feed(start: Int, bytes: ByteArray): Int {
        var h = start
        for (b in bytes) {
            h = (h xor (b.toInt() and 0xff)) * -862048943 // 3432918353
            h = (h shl 13) or (h ushr 19)
        }
        return h
    }

    /** murmur3 fmix32: a bijection on uint32 with full avalanche. */
    internal fun finalize(start: Int): Int {
        var h = start
        h = (h xor (h ushr 16)) * -2048144789 // 2246822507
        h = (h xor (h ushr 13)) * -1028477387 // 3266489909
        return h xor (h ushr 16)
    }

    /** NFC, then JavaScript `trim`, then JavaScript `toLowerCase`. */
    fun normalizeSeed(seed: String): String =
        jsToLower(jsTrim(Normalizer.normalize(seed, Normalizer.Form.NFC)))

    /** The hashed seed, as the signed 32-bit value the JavaScript core holds. */
    fun seedState(seed: String, normalize: Boolean = true): Int {
        val s = if (normalize) normalizeSeed(seed) else seed
        return feed(1779033703 xor s.length, utf8(s))
    }

    /** One uniform float in [0, 1) for [key], independent of every other key. */
    fun stream(state: Int, key: String): Double {
        val h = finalize(feed(feed(state, byteArrayOf(SEPARATOR.toByte())), utf8(key)))
        return (h.toLong() and 0xffffffffL).toDouble() / 4294967296.0
    }

    /** UTF-8 the way `TextEncoder` does it: a lone surrogate becomes U+FFFD, not `?`. */
    internal fun utf8(s: String): ByteArray {
        val out = java.io.ByteArrayOutputStream(s.length)
        var i = 0
        while (i < s.length) {
            var cp = s[i].code
            if (cp in 0xD800..0xDBFF && i + 1 < s.length && s[i + 1].code in 0xDC00..0xDFFF) {
                cp = 0x10000 + ((cp - 0xD800) shl 10) + (s[i + 1].code - 0xDC00)
                i++
            } else if (cp in 0xD800..0xDFFF) {
                cp = 0xFFFD
            }
            when {
                cp < 0x80 -> out.write(cp)
                cp < 0x800 -> { out.write(0xC0 or (cp shr 6)); out.write(0x80 or (cp and 0x3F)) }
                cp < 0x10000 -> {
                    out.write(0xE0 or (cp shr 12)); out.write(0x80 or ((cp shr 6) and 0x3F)); out.write(0x80 or (cp and 0x3F))
                }
                else -> {
                    out.write(0xF0 or (cp shr 18)); out.write(0x80 or ((cp shr 12) and 0x3F))
                    out.write(0x80 or ((cp shr 6) and 0x3F)); out.write(0x80 or (cp and 0x3F))
                }
            }
            i++
        }
        return out.toByteArray()
    }

    /** The WhiteSpace and LineTerminator sets `String.prototype.trim` strips; Kotlin's `trim` differs. */
    private fun isJsWhitespace(c: Char): Boolean = when (c.code) {
        in 0x09..0x0D, 0x20, 0xA0, 0x1680, in 0x2000..0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF -> true
        else -> false
    }

    private fun jsTrim(s: String): String {
        var start = 0
        var end = s.length
        while (start < end && isJsWhitespace(s[start])) start++
        while (end > start && isJsWhitespace(s[end - 1])) end--
        return s.substring(start, end)
    }

    /**
     * JavaScript lowercases with the full Unicode mapping plus the Final_Sigma context. The
     * sigma context is applied explicitly (with the same approximation as the Dart port), then
     * the rest goes through the locale-neutral full mapping, which turns `İ` into `i` + U+0307.
     */
    private fun jsToLower(s: String): String {
        if (s.indexOf('Σ') < 0) return s.lowercase(java.util.Locale.ROOT)
        val out = StringBuilder(s.length)
        for (i in s.indices) {
            val c = s[i]
            if (c == 'Σ' && precededByCased(s, i) && !followedByCased(s, i)) out.append('ς')
            else if (c == 'Σ') out.append('σ')
            else out.append(c)
        }
        return out.toString().lowercase(java.util.Locale.ROOT)
    }

    private fun precededByCased(s: String, i: Int): Boolean {
        for (j in i - 1 downTo 0) {
            if (isCased(s[j].code)) return true
            if (!isCaseIgnorable(s[j].code)) return false
        }
        return false
    }

    private fun followedByCased(s: String, i: Int): Boolean {
        for (j in i + 1 until s.length) {
            if (isCased(s[j].code)) return true
            if (!isCaseIgnorable(s[j].code)) return false
        }
        return false
    }

    private fun isCaseIgnorable(u: Int) = u in 0x0300..0x036F || u == 0x00AD || u == 0x200B

    private fun isCased(u: Int) = u in 0x41..0x5A || u in 0x61..0x7A ||
        (u in 0xC0..0x24F && u != 0xD7 && u != 0xF7) || u in 0x370..0x3FF || u in 0x400..0x4FF ||
        u in 0x1E00..0x1FFF
}

/** Pins one trait key: a [0, 1) position, or "any of these" chosen by the key's own hash. */
sealed interface TraitOverride {
    data class Value(val value: Double) : TraitOverride
    data class AnyOf(val values: List<Double>) : TraitOverride
}

/** A trait reader over one hashed seed. Every value is addressed by a string key. */
class Traits(val state: Int, private val overrides: Map<String, TraitOverride>? = null) {
    constructor(seed: String, normalize: Boolean = true, overrides: Map<String, TraitOverride>? = null) :
        this(BlobatarHash.seedState(seed, normalize), overrides)

    /** Uniform float in [0, 1). Overrides are clamped rather than trusted; NaN falls to 0. */
    operator fun invoke(key: String): Double {
        val o: Double? = when (val v = overrides?.get(key)) {
            is TraitOverride.Value -> v.value
            is TraitOverride.AnyOf -> if (v.values.isEmpty()) null
                else v.values[Math.floor(BlobatarHash.stream(state, key) * v.values.size).toInt()]
            null -> null
        }
        if (o == null) return BlobatarHash.stream(state, key)
        if (o > 0) return if (o < 1) o else 0.999999
        return 0.0
    }

    fun num(key: String, min: Double, max: Double): Double = min + this(key) * (max - min)

    fun int(key: String, min: Int, max: Int): Int = min + Math.floor(this(key) * (max - min + 1)).toInt()

    fun jitter(key: String, amount: Double): Double = (this(key) * 2 - 1) * amount
}
