import Foundation

/// Seed hashing.
///
/// Swift port of `packages/blobatar/src/hash.ts` (via the Dart port at 2.4.0).
/// The seed is hashed once; each trait key then continues from that state, so
/// trait values are independent of one another. JavaScript's uint32 semantics
/// are reproduced exactly with wrapping `UInt32` arithmetic.
public enum BlobatarHash {
    private static let separator: UInt8 = 0xff

    /// Mixes bytes into a 32-bit state.
    static func feed<S: Sequence>(_ start: UInt32, _ bytes: S) -> UInt32 where S.Element == UInt8 {
        var h = start
        for byte in bytes {
            h = (h ^ UInt32(byte)) &* 3_432_918_353
            h = (h << 13) | (h >> 19)
        }
        return h
    }

    /// murmur3 fmix32: a bijection on uint32 with full avalanche.
    static func finalize(_ start: UInt32) -> UInt32 {
        var h = start
        h = (h ^ (h >> 16)) &* 2_246_822_507
        h = (h ^ (h >> 13)) &* 3_266_489_909
        return h ^ (h >> 16)
    }

    /// NFC, then JavaScript `trim`, then JavaScript `toLowerCase`, so inputs a
    /// human considers equal hash equally (`Alain@x.com` and `alain@x.com`).
    public static func normalizeSeed(_ seed: String) -> String {
        jsToLower(jsTrim(seed.precomposedStringWithCanonicalMapping))
    }

    /// Hashes the seed once into a reusable state. Hashing runs over the UTF-8
    /// bytes; the length mixed in first is the UTF-16 length, as in JavaScript.
    public static func seedState(_ seed: String, normalize: Bool = true) -> UInt32 {
        let s = normalize ? normalizeSeed(seed) : seed
        return feed(1_779_033_703 ^ UInt32(truncatingIfNeeded: s.utf16.count), s.utf8)
    }

    /// One uniform float in [0, 1) for `key`, independent of every other key.
    public static func stream(_ state: UInt32, _ key: String) -> Double {
        Double(finalize(feed(feed(state, [separator]), key.utf8))) / 4_294_967_296
    }

    // MARK: JavaScript string semantics

    /// The WhiteSpace and LineTerminator sets `String.prototype.trim` strips.
    /// Spelled out because Foundation's whitespace set is not the same.
    private static func isJSWhitespace(_ v: UInt32) -> Bool {
        switch v {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
            return true
        default:
            return false
        }
    }

    private static func jsTrim(_ s: String) -> String {
        let scalars = Array(s.unicodeScalars)
        var start = 0, end = scalars.count
        while start < end, isJSWhitespace(scalars[start].value) { start += 1 }
        while end > start, isJSWhitespace(scalars[end - 1].value) { end -= 1 }
        var out = String.UnicodeScalarView()
        out.append(contentsOf: scalars[start..<end])
        return String(out)
    }

    /// JavaScript lowercases with the full Unicode mapping, including the
    /// Final_Sigma context: a capital sigma preceded by a cased letter and not
    /// followed by one becomes `ς`. Swift's `lowercased()` already uses the
    /// full mapping (so `İ` becomes `i` + U+0307) but has no context rules.
    private static func jsToLower(_ s: String) -> String {
        let scalars = Array(s.unicodeScalars)
        guard scalars.contains(where: { $0.value == 0x03A3 }) else { return s.lowercased() }
        var out = String.UnicodeScalarView()
        for (i, scalar) in scalars.enumerated() {
            if scalar.value == 0x03A3, precededByCased(scalars, i), !followedByCased(scalars, i) {
                out.append(Unicode.Scalar(0x03C2)!)
            } else {
                out.append(scalar)
            }
        }
        return String(out).lowercased()
    }

    private static func precededByCased(_ s: [Unicode.Scalar], _ i: Int) -> Bool {
        var j = i - 1
        while j >= 0 {
            if isCased(s[j].value) { return true }
            if !isCaseIgnorable(s[j].value) { return false }
            j -= 1
        }
        return false
    }

    private static func followedByCased(_ s: [Unicode.Scalar], _ i: Int) -> Bool {
        var j = i + 1
        while j < s.count {
            if isCased(s[j].value) { return true }
            if !isCaseIgnorable(s[j].value) { return false }
            j += 1
        }
        return false
    }

    private static func isCaseIgnorable(_ u: UInt32) -> Bool {
        (0x0300...0x036F).contains(u) || u == 0x00AD || u == 0x200B
    }

    private static func isCased(_ u: UInt32) -> Bool {
        (0x41...0x5A).contains(u) || (0x61...0x7A).contains(u)
            || ((0xC0...0x24F).contains(u) && u != 0xD7 && u != 0xF7)
            || (0x370...0x3FF).contains(u) || (0x400...0x4FF).contains(u)
            || (0x1E00...0x1FFF).contains(u)
    }
}
