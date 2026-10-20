#if canImport(SwiftUI)
import SwiftUI

extension BlobPath {
    /// The path in the 100 x 100 viewBox, at full precision (not the
    /// two-decimal markup form).
    public var cgPath: CGPath {
        let out = CGMutablePath()
        var current = CGPoint.zero
        for segment in segments {
            switch segment {
            case let .move(x, y):
                current = CGPoint(x: x, y: y)
                out.move(to: current)
            case let .line(x, y):
                current = CGPoint(x: x, y: y)
                out.addLine(to: current)
            case let .cubic(c1x, c1y, c2x, c2y, x, y):
                current = CGPoint(x: x, y: y)
                out.addCurve(to: current, control1: CGPoint(x: c1x, y: c1y), control2: CGPoint(x: c2x, y: c2y))
            case let .quad(cx, cy, x, y):
                current = CGPoint(x: x, y: y)
                out.addQuadCurve(to: current, control: CGPoint(x: cx, y: cy))
            case let .horizontal(x):
                current = CGPoint(x: x, y: current.y)
                out.addLine(to: current)
            case let .vertical(y):
                current = CGPoint(x: current.x, y: y)
                out.addLine(to: current)
            case .close:
                out.closeSubpath()
            }
        }
        return out
    }
}

extension Color {
    /// A `#rrggbb` palette color, in sRGB.
    public init(blobatarHex hex: String) {
        let n = BlobatarColor.hexValue(hex)
        self.init(.sRGB, red: Double((n >> 16) & 255) / 255, green: Double((n >> 8) & 255) / 255,
                  blue: Double(n & 255) / 255, opacity: 1)
    }
}

extension Blobatar {
    /// Draws the figure into the largest centered square of `size`, in the
    /// web renderer's order: backdrop, petals, extra outlines, body, eyes.
    public func draw(in context: inout GraphicsContext, size: CGSize) {
        let side = min(size.width, size.height)
        guard side > 0 else { return }
        var ctx = context
        ctx.translateBy(x: (size.width - side) / 2, y: (size.height - side) / 2)
        ctx.scaleBy(x: side / 100, y: side / 100)
        if let backdrop = backdropPath {
            ctx.fill(Path(backdrop.cgPath), with: .color(Color(blobatarHex: palette.bg)))
        }
        ctx.translateBy(x: 0, y: layout.bodyOffsetY)
        let head = GraphicsContext.Shading.color(Color(blobatarHex: palette.head))
        let eye = GraphicsContext.Shading.color(Color(blobatarHex: palette.eye))
        for petal in layout.petals {
            ctx.fill(Path(ellipseIn: CGRect(x: petal.cx - petal.r, y: petal.cy - petal.r, width: petal.r * 2, height: petal.r * 2)), with: head)
        }
        for extra in layout.extra { ctx.fill(Path(extra.cgPath), with: head) }
        ctx.fill(Path(layout.bodyPath().cgPath), with: head)
        for path in layout.eyePaths() { ctx.fill(Path(path.cgPath), with: eye) }
    }
}

/// A blobatar for `name`: the same figure the web package draws for that
/// name, drawn natively. It fills the largest square that fits.
///
/// ```swift
/// BlobatarView("alain@example.com")
///     .frame(width: 48, height: 48)
/// ```
public struct BlobatarView: View {
    private let blobatar: Blobatar

    public init(_ name: String, options: BlobatarOptions = BlobatarOptions()) {
        blobatar = Blobatar(name, options: options)
    }

    public init(_ blobatar: Blobatar) {
        self.blobatar = blobatar
    }

    public var body: some View {
        Canvas { context, size in
            blobatar.draw(in: &context, size: size)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Blobatars") {
    let names = ["alain", "monsef", "centrax", "ada lovelace", "grace", "linus", "rania", "omar", "sara"]
    return ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: 16) {
            ForEach(names, id: \.self) { BlobatarView($0).frame(width: 64, height: 64) }
            ForEach(BlobatarExpression.all, id: \.name) { expression in
                VStack {
                    BlobatarView("centrax", options: BlobatarOptions(expression: expression)).frame(width: 64, height: 64)
                    Text(expression.name).font(.caption2)
                }
            }
        }
        .padding()
    }
}
#endif
#endif
