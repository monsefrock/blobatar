import Foundation

/// Pins one trait key. `.value` is the [0, 1) position the hash would have
/// produced; `.any` means "any of these", with the key's own hash choosing.
/// An empty `.any` is the same as no override.
public enum TraitOverride: Sendable, Equatable, Hashable {
    case value(Double)
    case any([Double])
}

/// A trait reader over one hashed seed. Every value is addressed by a string
/// key, so adding a key later never disturbs existing blobatars.
public struct Traits: Sendable {
    public let state: UInt32
    public let overrides: [String: TraitOverride]?

    public init(state: UInt32, overrides: [String: TraitOverride]? = nil) {
        self.state = state
        self.overrides = overrides
    }

    public init(seed: String, normalize: Bool = true, overrides: [String: TraitOverride]? = nil) {
        self.init(state: BlobatarHash.seedState(seed, normalize: normalize), overrides: overrides)
    }

    /// Uniform float in [0, 1). Overrides are clamped rather than trusted, and
    /// NaN falls to 0.
    public func callAsFunction(_ key: String) -> Double {
        var o: Double?
        switch overrides?[key] {
        case .value(let v):
            o = v
        case .any(let options) where !options.isEmpty:
            let index = Int((BlobatarHash.stream(state, key) * Double(options.count)).rounded(.down))
            o = options[index]
        default:
            break
        }
        guard let o else { return BlobatarHash.stream(state, key) }
        if o > 0 { return o < 1 ? o : 0.999999 }
        return 0
    }

    /// Uniform float in [min, max).
    public func num(_ key: String, _ min: Double, _ max: Double) -> Double {
        min + self(key) * (max - min)
    }

    /// Uniform integer from `min` through `max`, inclusive.
    public func int(_ key: String, _ min: Int, _ max: Int) -> Int {
        min + Int((self(key) * Double(max - min + 1)).rounded(.down))
    }

    /// True with probability `p`.
    public func bool(_ key: String, _ p: Double = 0.5) -> Bool { self(key) < p }

    /// Symmetric jitter in [-amount, amount).
    public func jitter(_ key: String, _ amount: Double) -> Double {
        (self(key) * 2 - 1) * amount
    }
}
