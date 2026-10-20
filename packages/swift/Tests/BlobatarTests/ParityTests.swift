import Foundation
import XCTest
@testable import Blobatar

/// The cross-language parity gate, against the fixture exported from the
/// TypeScript core (shared with the Flutter port). Everything the fixture
/// marks exact must match exactly; layout floats agree within 1e-9.
final class ParityTests: XCTestCase {
    static let vectors: [String: Any] = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("../flutter/test/fixtures/reference-vectors.json").standardized
        let data = try! Data(contentsOf: url)
        return try! JSONDecoder().decode(JSONValue.self, from: data).any as! [String: Any]
    }()

    static func close(_ a: Double, _ b: Double, _ tol: Double = 1e-9) -> Bool {
        if a == b || (a.isNaN && b.isNaN) { return true }
        return abs(a - b) <= tol * max(1, max(abs(a), abs(b)))
    }

    static func double(_ v: Any?) -> Double { v as! Double }

    static func overrides(_ json: Any?) -> [String: TraitOverride]? {
        guard let map = json as? [String: Any], !map.isEmpty else { return nil }
        return map.mapValues { v in
            if let list = v as? [Any] { return .any(list.map(double)) }
            return .value(double(v))
        }
    }

    static func options(_ json: [String: Any], expression: BlobatarExpression? = nil) -> BlobatarOptions {
        BlobatarOptions(
            hue: json["hue"] as? Double,
            tone: json["tone"] as? Double,
            traits: overrides(json["traits"]),
            normalize: json["normalize"] as? Bool ?? true,
            contrast: json["contrast"] as? Bool ?? true,
            expression: expression
        )
    }

    func testNormalizationAgreesByteForByte() {
        for case let v as [String: Any] in Self.vectors["hash"] as! [Any] {
            let actual = BlobatarHash.normalizeSeed(v["seed"] as! String)
            // Compare scalars: Swift's == treats canonically equivalent strings as equal.
            XCTAssertEqual(Array(actual.unicodeScalars), Array((v["normalized"] as! String).unicodeScalars),
                           "normalizeSeed(\(v["seed"]!))")
        }
    }

    func testSeedStatesAndStreamsAgreeExactly() {
        for case let v as [String: Any] in Self.vectors["hash"] as! [Any] {
            let seed = v["seed"] as! String
            let state = BlobatarHash.seedState(seed)
            XCTAssertEqual(Int(Int32(bitPattern: state)), Int(v["state"] as! Double), "seedState(\(seed))")
            for (key, expected) in v["streams"] as! [String: Any] {
                XCTAssertEqual(BlobatarHash.stream(state, key), Self.double(expected), "stream(\(seed), \(key))")
            }
        }
    }

    func testOverrideReadsAgreeExactly() {
        for case let v as [String: Any] in Self.vectors["overrides"] as! [Any] {
            let t = Traits(seed: v["seed"] as! String, overrides: Self.overrides(v["overrides"]))
            for (key, expected) in v["values"] as! [String: Any] {
                XCTAssertEqual(t(key), Self.double(expected), "\(v["seed"]!) \(key)")
            }
        }
    }

    func testPaletteVectors() {
        for case let v as [String: Any] in Self.vectors["palette"] as! [Any] {
            let hue = Self.double(v["hue"]), tone = Self.double(v["tone"])
            let hex = v["hex"] as! [String: String]
            XCTAssertEqual(BlobatarColor.palette(hue: hue, enforce: true, tone: tone),
                           BlobatarPalette(bg: hex["bg"]!, head: hex["head"]!, eye: hex["eye"]!), "h=\(hue) t=\(tone)")
            let raw = v["rampUnenforced"] as! [String: [String: Any]]
            let r = BlobatarColor.ramp(hue: hue, enforce: false, tone: tone)
            for (key, color) in [("bg", r.bg), ("head", r.head), ("eye", r.eye)] {
                XCTAssertTrue(Self.close(color.l, Self.double(raw[key]!["l"])), "\(key).l h=\(hue) t=\(tone)")
                XCTAssertTrue(Self.close(color.c, Self.double(raw[key]!["c"])), "\(key).c h=\(hue) t=\(tone)")
                XCTAssertTrue(Self.close(color.h, Self.double(raw[key]!["h"])), "\(key).h h=\(hue) t=\(tone)")
            }
        }
    }

    func testAllLayoutCasesAgreeWithTheTypeScriptCore() {
        let cases = Self.vectors["cases"] as! [[String: Any]]
        XCTAssertEqual(cases.count, 1570)
        var failures: [String] = []
        for c in cases {
            let blobatar = Blobatar(c["seed"] as! String, options: Self.options(c["options"] as! [String: Any]))
            if let reason = Self.check(blobatar, against: c) {
                failures.append("seed=\(c["seed"]!) options=\(c["options"]!): \(reason)")
            }
        }
        XCTAssertEqual(failures.count, 0, "first: \(failures.first ?? "")")
    }

    func testExpressionCasesAgree() {
        let expressions = Self.vectors["expressions"] as! [String: [String: Any]]
        XCTAssertEqual(Set(expressions.keys), Set(BlobatarExpression.all.map(\.name)))
        for (name, data) in expressions {
            let expression = BlobatarExpression.named(name)!
            let pose = data["pose"] as! [String: Any]
            let p = expression.pose
            let mine: [String: Double] = [
                "esx": p.esx, "esy": p.esy, "tilt": p.tilt, "edy": p.edy, "edx": p.edx, "esx2": p.esx2, "esy2": p.esy2,
                "tilt2": p.tilt2, "edy2": p.edy2, "lock": p.lock, "heat": p.heat, "shake": p.shake, "rock": p.rock, "bdy": p.bdy,
            ]
            XCTAssertEqual(mine, pose.mapValues(Self.double), name)
            for c in data["cases"] as! [[String: Any]] {
                let blobatar = Blobatar(c["seed"] as! String,
                                        options: Self.options(c["options"] as! [String: Any], expression: expression))
                XCTAssertEqual(blobatar.layout.bodyOffsetY, p.bdy, name)
                XCTAssertNil(Self.check(blobatar, against: c, pathsAndBody: false), "\(name) \(c["seed"]!)")
            }
        }
    }

    /// nil when the case matches, else the first field that does not.
    static func check(_ b: Blobatar, against c: [String: Any], pathsAndBody: Bool = true) -> String? {
        let l = b.layout
        if l.shape.rawValue != c["shape"] as? String { return "shape \(l.shape) != \(c["shape"]!)" }
        let eyes = c["eyes"] as! [[String: Any]]
        if l.eyes.count != eyes.count { return "eyes.count" }
        for (i, e) in eyes.enumerated() {
            let a = l.eyes[i]
            for (key, value) in [("cx", a.cx), ("cy", a.cy), ("rx", a.rx), ("ry", a.ry), ("n", a.n), ("rot", a.rot)]
            where !close(value, double(e[key])) { return "eye\(i).\(key) \(value) != \(e[key]!)" }
        }
        let pal = c["palette"] as! [String: String]
        if b.palette != BlobatarPalette(bg: pal["bg"]!, head: pal["head"]!, eye: pal["eye"]!) {
            return "palette \(b.palette) != \(pal)"
        }
        guard pathsAndBody else { return nil }

        let body = c["body"] as! [String: Any]
        for (key, value) in [("cx", l.body.cx), ("cy", l.body.cy), ("rx", l.body.rx), ("ry", l.body.ry), ("n", l.body.n), ("rot", l.body.rot)]
        where !close(value, double(body[key])) { return "body.\(key)" }
        let radii = (body["radii"] as! [Any]).map(double)
        if l.body.radii.count != radii.count { return "radii.count" }
        for (i, r) in radii.enumerated() where !close(l.body.radii[i], r) { return "radii[\(i)]" }
        if let sides = body["sides"] as? Double, l.body.sides != Int(sides) { return "sides" }
        if let round = body["round"] as? Double, !close(l.body.round ?? .nan, round) { return "round" }

        let face = c["face"] as! [String: Any]
        for (key, value) in [("cx", l.face.cx), ("cy", l.face.cy), ("rx", l.face.rx), ("ry", l.face.ry)]
        where !close(value, double(face[key])) { return "face.\(key)" }

        let petals = c["petals"] as! [[String: Any]]
        if l.petals.count != petals.count { return "petals.count" }
        for (i, p) in petals.enumerated() {
            let a = l.petals[i]
            if !close(a.cx, double(p["cx"])) || !close(a.cy, double(p["cy"])) || !close(a.r, double(p["r"])) { return "petals[\(i)]" }
        }

        let extra = c["extra"] as! [String]
        if l.extra.map({ $0.toPathData() }) != extra { return "extra" }
        if l.bodyPath().toPathData() != c["bodyPath"] as! String {
            return "bodyPath \(l.bodyPath().toPathData()) != \(c["bodyPath"]!)"
        }
        let eyePaths = c["eyePaths"] as! [String]
        if l.eyePaths().map({ $0.toPathData() }) != eyePaths { return "eyePaths" }
        return nil
    }

    func testR2MatchesJavaScriptNumberFormatting() {
        XCTAssertEqual(BlobPath.r2(-0.001), "0")
        XCTAssertEqual(BlobPath.r2(12), "12")
        XCTAssertEqual(BlobPath.r2(12.3), "12.3")
        XCTAssertEqual(BlobPath.r2(12.345), "12.35")
        XCTAssertEqual(BlobPath.r2(-0.05), "-0.05")
        XCTAssertEqual(BlobPath.r2(-1.005), "-1")
        XCTAssertEqual(BlobPath.r2(0.07), "0.07")
    }

    func testIdleMatchesNoExpression() {
        for i in 0..<100 {
            XCTAssertEqual(Blobatar("idle-\(i)", options: BlobatarOptions(expression: .idle)).layout,
                           Blobatar("idle-\(i)").layout)
        }
    }
}

/// The fixture as plain values. JSONDecoder rather than JSONSerialization,
/// which can round doubles in the last place, and the stream values are
/// compared bit for bit.
enum JSONValue: Decodable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    var any: Any? {
        switch self {
        case .null: nil
        case .bool(let v): v
        case .number(let v): v
        case .string(let v): v
        case .array(let v): v.map(\.any)
        case .object(let v): v.mapValues(\.any)
        }
    }
}

/// The motion reference values the Flutter port checks against the TypeScript core.
final class MotionTests: XCTestCase {
    func testSeedsMatchTheTypeScriptCore() {
        let alain = MotionSeeds(name: "alain")
        XCTAssertEqual([alain.phase, alain.bob, alain.blink, alain.blinkPhase, alain.saccade, alain.saccadePhase],
                       [508, 1170, 3619, 2957, 6179, 1350])
        XCTAssertEqual([alain.lookX, alain.lookY, alain.lookMagnitudeX, alain.lookMagnitudeY], [1.95, -0.97, 1.95, 0.97])
        let ada = MotionSeeds(name: "ada")
        XCTAssertEqual([ada.phase, ada.bob, ada.blink, ada.blinkPhase, ada.saccade, ada.saccadePhase],
                       [455, 328, 5328, 58, 5844, 561])
        XCTAssertEqual([ada.lookX, ada.lookY, ada.lookMagnitudeX, ada.lookMagnitudeY], [-1.78, -1.36, 1.78, 1.36])
    }

    private func check(_ f: MotionFrame, _ expected: [Double], file: StaticString = #filePath, line: UInt = #line) {
        let actual = [f.shake.x, f.shake.y, f.breathe.x, f.breathe.y, f.bob, f.saccade.x, f.saccade.y,
                      f.thinkingPhase, f.blink, f.wrap.magnitudeX, f.wrap.side, f.wrap.scaleY, f.wrap.rotation]
        for (a, e) in zip(actual, expected) { XCTAssertEqual(a, e, accuracy: 1e-12, file: file, line: line) }
    }

    func testFramesMatchTheTypeScriptCore() {
        let seeds = MotionSeeds(name: "alain")
        check(BlobatarMotion.frame(seeds, at: 0, amplitude: 1, shake: 0.55),
              [0.341, -0.18700000000000003, 1.001470229356656, 0.998797085071827, -0.27170814718541325, -1.56, 0.873,
               1, 1, -0.03432, 0.0156, -0.026189999999999998, -1.225692])
        check(BlobatarMotion.frame(seeds, at: 1234, amplitude: 1, shake: 0.55),
              [0.28914285714285864, -0.16500000000000065, 1.015462618780544, 0.9873487664522821, -0.903594833714393,
               1.95, -0.097, -0.7249387100885838, 1, -0.042899999999999994, -0.0195, -0.00291, -0.170235])
        check(BlobatarMotion.frame(seeds, at: 5000, amplitude: 1, shake: 0.55),
              [-0.04871428571429122, -0.03300000000000846, 1.0000455442519844, 0.9999627365211037, -0.0767684801351858,
               0, 0, -0.9510907709234386, 1, 0, 0, 0, 0])
    }

    func testBlinkClosesOnceWithoutInversion() {
        let seeds = MotionSeeds(name: "alain")
        let closed = 0.986 * Double(seeds.blink) - Double(seeds.blinkPhase)
        XCTAssertEqual(BlobatarMotion.frame(seeds, at: closed, amplitude: 1).blink, 0.08, accuracy: 1e-9)
        for i in 0..<4000 {
            XCTAssertGreaterThan(BlobatarMotion.frame(seeds, at: Double(i) * Double(seeds.blink) / 4000, amplitude: 1).blink, 0)
        }
    }

    func testZeroAmplitudeIsStill() {
        let seeds = MotionSeeds(name: "alain")
        for time in stride(from: 0.0, to: 20000, by: 137) {
            let f = BlobatarMotion.frame(seeds, at: time, amplitude: 0)
            XCTAssertTrue(f.breathe == (1, 1) && f.blink == 1 && abs(f.bob) < 1e-12 && abs(f.saccade.x) < 1e-12)
        }
    }
}
