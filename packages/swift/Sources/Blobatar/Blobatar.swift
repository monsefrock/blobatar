import Foundation

/// The backdrop drawn behind the figure.
public enum BlobatarBackdrop: String, Sendable, Equatable, Hashable {
    case none, square, circle, squircle
}

/// Everything that changes how a name is drawn. The default is the web's.
public struct BlobatarOptions: Sendable, Equatable, Hashable {
    /// Replaces palette entries (`#rrggbb`). Overridden colors skip the contrast guarantee.
    public var bg: String?
    public var head: String?
    public var eye: String?
    /// Locks the hue in degrees, so the name drives shape only.
    public var hue: Double?
    /// Locks the tone, 0 (pale) to just under 1 (ink).
    public var tone: Double?
    /// Pins individual traits, keyed as the layout reads them (`"eye.gap"`).
    public var traits: [String: TraitOverride]?
    /// NFC + trim + lowercase the name first.
    public var normalize: Bool
    /// Enforce the minimum contrast ratios.
    public var contrast: Bool
    public var background: BlobatarBackdrop
    /// The backdrop color as `#rgb`/`#rrggbb`; the body is pushed off it. Ignored when invalid.
    public var backgroundColor: String?
    public var expression: BlobatarExpression?

    public init(bg: String? = nil, head: String? = nil, eye: String? = nil, hue: Double? = nil, tone: Double? = nil,
                traits: [String: TraitOverride]? = nil, normalize: Bool = true, contrast: Bool = true,
                background: BlobatarBackdrop = .none, backgroundColor: String? = nil,
                expression: BlobatarExpression? = nil) {
        self.bg = bg; self.head = head; self.eye = eye
        self.hue = hue; self.tone = tone; self.traits = traits
        self.normalize = normalize; self.contrast = contrast
        self.background = background; self.backgroundColor = backgroundColor
        self.expression = expression
    }
}

/// A name resolved into geometry and colors, ready to draw.
public struct Blobatar: Sendable, Equatable {
    public let name: String
    public let options: BlobatarOptions
    public let layout: BlobatarLayout
    public let palette: BlobatarPalette

    public init(_ name: String, options: BlobatarOptions = BlobatarOptions()) {
        self.name = name
        self.options = options
        let t = Traits(seed: name, normalize: options.normalize, overrides: options.traits)
        let plate = options.background != .none ? options.backgroundColor.flatMap(BlobatarColor.plateHex) : nil
        var palette = BlobatarColor.palette(
            hue: options.hue ?? t.num("hue", 0, 360),
            enforce: options.contrast,
            tone: options.tone ?? t("tone"),
            bg: plate
        )
        if let bg = options.bg { palette.bg = bg }
        if let head = options.head { palette.head = head }
        if let eye = options.eye { palette.eye = eye }

        let layout = BlobatarLayout.make(t)
        if let expression = options.expression {
            self.layout = layout.posed(expression.pose)
            self.palette = palette.expressed(expression)
        } else {
            self.layout = layout
            self.palette = palette
        }
    }

    /// The backdrop plate, if one is drawn.
    public var backdropPath: BlobPath? {
        switch options.background {
        case .none: nil
        case .square: BlobShape.box(cx: 50, cy: 50, rx: 50, ry: 50)
        case .circle: BlobShape.superellipse(cx: 50, cy: 50, rx: 50, ry: 50, n: 2)
        case .squircle: BlobShape.superellipse(cx: 50, cy: 50, rx: 50, ry: 50, n: 6)
        }
    }

    /// The figure as one SVG document, the same markup shape the web renders.
    public func svg(size: Int = 100) -> String {
        var parts: [String] = []
        if let backdrop = backdropPath { parts.append("<path d=\"\(backdrop.toPathData())\" fill=\"\(palette.bg)\"/>") }
        var figure = layout.petals.map {
            "<circle cx=\"\(BlobPath.r2($0.cx))\" cy=\"\(BlobPath.r2($0.cy))\" r=\"\(BlobPath.r2($0.r))\" fill=\"\(palette.head)\"/>"
        }
        figure += layout.extra.map { "<path d=\"\($0.toPathData())\" fill=\"\(palette.head)\"/>" }
        figure.append("<path d=\"\(layout.bodyPath().toPathData())\" fill=\"\(palette.head)\"/>")
        figure += layout.eyePaths().map { "<path d=\"\($0.toPathData())\" fill=\"\(palette.eye)\"/>" }
        let shift = layout.bodyOffsetY == 0 ? "" : " transform=\"translate(0 \(BlobPath.r2(layout.bodyOffsetY)))\""
        parts.append("<g\(shift)>\(figure.joined())</g>")
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\" width=\"\(size)\" height=\"\(size)\">\(parts.joined())</svg>"
    }
}
