import Foundation

/// Every channel an expression may change.
public struct Pose: Sendable, Equatable {
    public var esx = 1.0, esy = 1.0, tilt = 0.0, edy = 0.0, edx = 0.0
    public var esx2 = 0.0, esy2 = 0.0, tilt2 = 0.0, edy2 = 0.0
    public var lock = 0.0, heat = 0.0, shake = 0.0, rock = 0.0, bdy = 0.0

    public init(esx: Double = 1, esy: Double = 1, tilt: Double = 0, edy: Double = 0, edx: Double = 0,
                esx2: Double = 0, esy2: Double = 0, tilt2: Double = 0, edy2: Double = 0,
                lock: Double = 0, heat: Double = 0, shake: Double = 0, rock: Double = 0, bdy: Double = 0) {
        self.esx = esx; self.esy = esy; self.tilt = tilt; self.edy = edy; self.edx = edx
        self.esx2 = esx2; self.esy2 = esy2; self.tilt2 = tilt2; self.edy2 = edy2
        self.lock = lock; self.heat = heat; self.shake = shake; self.rock = rock; self.bdy = bdy
    }
}

/// A named pose and its optional palette tint.
public struct BlobatarExpression: Sendable, Equatable, Hashable {
    public let name: String
    public let pose: Pose
    public let tint: Tint?

    public static func == (a: Self, b: Self) -> Bool { a.name == b.name && a.pose == b.pose && a.tint == b.tint }
    public func hash(into hasher: inout Hasher) { hasher.combine(name) }

    public static let idle = Self(name: "idle", pose: Pose(), tint: nil)
    public static let happy = Self(name: "happy", pose: Pose(esx: 1.72, esy: 0.3, tilt: 8, edy: -1.5, edx: 1.5, esx2: 0.08, esy2: 0.05, tilt2: -16, lock: 1, bdy: -2.2), tint: nil)
    public static let sad = Self(name: "sad", pose: Pose(esx: 0.6, esy: 0.56, tilt: 26, edy: 3.6, edx: 1.9, esx2: -0.05, esy2: -0.07, tilt2: -7, lock: 1, bdy: 2.6), tint: nil)
    public static let mad = Self(name: "mad", pose: Pose(esx: 1.85, esy: 0.26, tilt: -33, edy: 0.4, edx: 0.6, esy2: -0.03, tilt2: 5, lock: 1, heat: 0.62, shake: 0.55, bdy: 0.8), tint: .hot)
    public static let surprised = Self(name: "surprised", pose: Pose(esx: 1.34, esy: 1.2, tilt: -6, edy: -1.05, edx: 0.5, esx2: 0.05, esy2: 0.07, tilt2: 3, lock: 1, bdy: -1.4), tint: nil)
    public static let wink = Self(name: "wink", pose: Pose(esx: 1.32, esy: 0.76, tilt: 5, edy: -0.6, edx: 0.8, esx2: 0.26, esy2: -0.56, tilt2: -11, lock: 1, bdy: -1.1), tint: nil)
    public static let sleepy = Self(name: "sleepy", pose: Pose(esx: 1.14, esy: 0.22, edy: 2.4, edx: 0.3, esx2: -0.04, esy2: 0.03, tilt2: 4, lock: 1, bdy: 1.2), tint: nil)
    public static let smug = Self(name: "smug", pose: Pose(esx: 1.3, esy: 0.42, tilt: 18, edy: -0.5, edx: 0.5, esx2: 0.06, esy2: -0.06, tilt2: -36, lock: 1, bdy: -1), tint: nil)
    public static let unsure = Self(name: "unsure", pose: Pose(esx: 0.95, esy: 1.02, tilt: 4, edy: -0.2, edx: 0.3, esx2: 0.24, esy2: -0.44, tilt2: -18, lock: 1), tint: nil)
    public static let scared = Self(name: "scared", pose: Pose(esx: 0.78, esy: 0.96, tilt: -12, edy: -1.5, edx: -0.8, esx2: -0.04, esy2: 0.05, tilt2: 4, lock: 1, shake: 0.35, bdy: -0.6), tint: nil)
    public static let love = Self(name: "love", pose: Pose(esx: 0.86, esy: 1.28, tilt: -14, edy: -0.5, edx: -0.35, esx2: 0.05, esy2: 0.06, tilt2: 6, lock: 1, heat: 0.6, bdy: -1.6), tint: .rose)
    public static let shy = Self(name: "shy", pose: Pose(esx: 0.62, esy: 0.5, tilt: 10, edy: 1.4, edx: -0.2, esx2: -0.05, esy2: -0.04, tilt2: -8, lock: 1, heat: 0.55, bdy: 0.9), tint: .blush)
    public static let sick = Self(name: "sick", pose: Pose(esx: 1.25, esy: 0.34, tilt: 20, edy: 1.8, edx: 0.8, esx2: 0.05, esy2: -0.05, tilt2: -6, lock: 1, heat: 0.6, shake: 0.18, bdy: 1.4), tint: .bile)
    public static let thinking = Self(name: "thinking", pose: Pose(esx: 1.15, esy: 0.62, edy: 4.2, edx: 0.4, esx2: 0.02, esy2: 0.06, edy2: -8.4, lock: 1, rock: 0.8, bdy: -0.4), tint: nil)

    public static let all: [Self] = [idle, happy, sad, mad, surprised, wink, sleepy, smug, unsure, scared, love, shy, sick, thinking]

    public static func named(_ name: String) -> Self? { all.first { $0.name == name } }
}


extension BlobatarLayout {
    /// Bakes a static pose into the eye geometry and body offset.
    public func posed(_ pose: Pose) -> BlobatarLayout {
        var out = self
        out.eyes = eyes.enumerated().map { i, e in
            let second = i == 1
            let side: Double = i == 0 ? -1 : 1
            return Eye(
                cx: e.cx + pose.edx * side,
                cy: e.cy + pose.edy + (second ? pose.edy2 : 0),
                rx: e.rx * (pose.esx + (second ? pose.esx2 : 0)),
                ry: e.ry * (pose.esy + (second ? pose.esy2 : 0)),
                n: e.n,
                rot: e.rot * (1 - pose.lock) + (pose.tilt + (second ? pose.tilt2 : 0)) * side
            )
        }
        out.bodyOffsetY = pose.bdy
        return out
    }
}

extension BlobatarPalette {
    /// The palette a tinting expression wears, resolved against this one.
    public func expressed(_ expression: BlobatarExpression) -> BlobatarPalette {
        guard let target = expression.tint else { return self }
        let hot = BlobatarColor.tinted(head: head, eye: eye, target)
        var out = self
        out.head = BlobatarColor.mixHex(head, hot.head, expression.pose.heat)
        out.eye = BlobatarColor.mixHex(eye, hot.eye, expression.pose.heat)
        return out
    }
}
