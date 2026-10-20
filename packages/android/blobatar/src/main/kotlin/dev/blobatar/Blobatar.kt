package dev.blobatar

/** The backdrop drawn behind the figure. */
enum class BlobatarBackdrop { None, Square, Circle, Squircle }

/** Everything that changes how a name is drawn. The defaults are the web's. */
data class BlobatarOptions(
    /** Replace palette entries (`#rrggbb`); overridden colors skip the contrast guarantee. */
    val bg: String? = null,
    val head: String? = null,
    val eye: String? = null,
    /** Locks the hue in degrees, so the name drives shape only. */
    val hue: Double? = null,
    /** Locks the tone, 0 (pale) to just under 1 (ink). */
    val tone: Double? = null,
    /** Pins individual traits, keyed as the layout reads them (`"eye.gap"`). */
    val traits: Map<String, TraitOverride>? = null,
    /** NFC + trim + lowercase the name first. */
    val normalize: Boolean = true,
    /** Enforce the minimum contrast ratios. */
    val contrast: Boolean = true,
    val background: BlobatarBackdrop = BlobatarBackdrop.None,
    /** The backdrop color as `#rgb`/`#rrggbb`; the body is pushed off it. Ignored when invalid. */
    val backgroundColor: String? = null,
    val expression: BlobatarExpression? = null,
)

/** A name resolved into geometry and colors, ready to draw. */
class Blobatar(val name: String, val options: BlobatarOptions = BlobatarOptions()) {
    val layout: BlobatarLayout
    val palette: BlobatarPalette

    init {
        val t = Traits(name, options.normalize, options.traits)
        val plate = if (options.background != BlobatarBackdrop.None) options.backgroundColor?.let(BlobatarColor::plateHex) else null
        var p = BlobatarColor.palette(
            options.hue ?: t.num("hue", 0.0, 360.0),
            options.contrast,
            options.tone ?: t("tone"),
            plate,
        )
        p = p.copy(bg = options.bg ?: p.bg, head = options.head ?: p.head, eye = options.eye ?: p.eye)
        val base = BlobatarLayout.make(t)
        val expression = options.expression
        layout = if (expression == null) base else base.posed(expression.pose)
        palette = if (expression == null) p else p.expressed(expression)
    }

    /** The backdrop plate, if one is drawn. */
    val backdropPath: BlobPath?
        get() = when (options.background) {
            BlobatarBackdrop.None -> null
            BlobatarBackdrop.Square -> BlobShape.box(50.0, 50.0, 50.0, 50.0)
            BlobatarBackdrop.Circle -> BlobShape.superellipse(50.0, 50.0, 50.0, 50.0, 2.0)
            BlobatarBackdrop.Squircle -> BlobShape.superellipse(50.0, 50.0, 50.0, 50.0, 6.0)
        }
}
