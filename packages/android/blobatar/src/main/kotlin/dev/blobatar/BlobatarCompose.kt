package dev.blobatar

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate

/** The path in the 100 x 100 viewBox, at full precision (not the two-decimal markup form). */
fun BlobPath.toComposePath(): Path {
    val out = Path()
    var x = 0f
    var y = 0f
    for (s in segments) {
        when (s) {
            is PathSegment.MoveTo -> { x = s.x.toFloat(); y = s.y.toFloat(); out.moveTo(x, y) }
            is PathSegment.LineTo -> { x = s.x.toFloat(); y = s.y.toFloat(); out.lineTo(x, y) }
            is PathSegment.CubicTo -> {
                x = s.x.toFloat(); y = s.y.toFloat()
                out.cubicTo(s.c1x.toFloat(), s.c1y.toFloat(), s.c2x.toFloat(), s.c2y.toFloat(), x, y)
            }
            is PathSegment.QuadTo -> {
                x = s.x.toFloat(); y = s.y.toFloat()
                out.quadraticTo(s.cx.toFloat(), s.cy.toFloat(), x, y)
            }
            is PathSegment.HorizontalTo -> { x = s.x.toFloat(); out.lineTo(x, y) }
            is PathSegment.VerticalTo -> { y = s.y.toFloat(); out.lineTo(x, y) }
            PathSegment.Close -> out.close()
        }
    }
    return out
}

/** A `#rrggbb` palette color. */
fun blobatarColor(hex: String): Color = Color(0xFF000000.toInt() or BlobatarColor.hexValue(hex))

/**
 * Draws the figure into the largest centered square of [size], in the web renderer's order:
 * backdrop, petals, extra outlines, body, eyes.
 */
fun DrawScope.drawBlobatar(blobatar: Blobatar, size: Size = this.size) {
    val side = minOf(size.width, size.height)
    if (side <= 0f) return
    val layout = blobatar.layout
    val head = blobatarColor(blobatar.palette.head)
    val eye = blobatarColor(blobatar.palette.eye)
    translate((size.width - side) / 2, (size.height - side) / 2) {
        scale(side / 100f, side / 100f, pivot = Offset.Zero) {
            blobatar.backdropPath?.let { drawPath(it.toComposePath(), blobatarColor(blobatar.palette.bg)) }
            translate(0f, layout.bodyOffsetY.toFloat()) {
                for (p in layout.petals) drawCircle(head, p.r.toFloat(), Offset(p.cx.toFloat(), p.cy.toFloat()))
                for (e in layout.extra) drawPath(e.toComposePath(), head)
                drawPath(layout.bodyPath().toComposePath(), head)
                for (e in layout.eyePaths()) drawPath(e.toComposePath(), eye)
            }
        }
    }
}

/**
 * A blobatar for [name]: the same figure the web package draws for that name, drawn natively.
 *
 * ```kotlin
 * Blobatar("alain@example.com", Modifier.size(48.dp))
 * ```
 */
@Composable
fun Blobatar(name: String, modifier: Modifier = Modifier, options: BlobatarOptions = BlobatarOptions()) {
    val blobatar = remember(name, options) { Blobatar(name, options) }
    Canvas(modifier.aspectRatio(1f)) { drawBlobatar(blobatar) }
}
