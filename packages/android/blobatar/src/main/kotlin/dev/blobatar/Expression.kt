package dev.blobatar

/** Every channel an expression may change. */
data class Pose(
    val esx: Double = 1.0, val esy: Double = 1.0, val tilt: Double = 0.0, val edy: Double = 0.0, val edx: Double = 0.0,
    val esx2: Double = 0.0, val esy2: Double = 0.0, val tilt2: Double = 0.0, val edy2: Double = 0.0,
    val lock: Double = 0.0, val heat: Double = 0.0, val shake: Double = 0.0, val rock: Double = 0.0, val bdy: Double = 0.0,
)

/** A named pose and its optional palette tint. */
data class BlobatarExpression(val name: String, val pose: Pose, val tint: Tint? = null) {
    companion object {
        val Idle = BlobatarExpression("idle", Pose())
        val Happy = BlobatarExpression("happy", Pose(esx = 1.72, esy = 0.3, tilt = 8.0, edy = -1.5, edx = 1.5, esx2 = 0.08, esy2 = 0.05, tilt2 = -16.0, lock = 1.0, bdy = -2.2))
        val Sad = BlobatarExpression("sad", Pose(esx = 0.6, esy = 0.56, tilt = 26.0, edy = 3.6, edx = 1.9, esx2 = -0.05, esy2 = -0.07, tilt2 = -7.0, lock = 1.0, bdy = 2.6))
        val Mad = BlobatarExpression("mad", Pose(esx = 1.85, esy = 0.26, tilt = -33.0, edy = 0.4, edx = 0.6, esy2 = -0.03, tilt2 = 5.0, lock = 1.0, heat = 0.62, shake = 0.55, bdy = 0.8), Tint.Hot)
        val Surprised = BlobatarExpression("surprised", Pose(esx = 1.34, esy = 1.2, tilt = -6.0, edy = -1.05, edx = 0.5, esx2 = 0.05, esy2 = 0.07, tilt2 = 3.0, lock = 1.0, bdy = -1.4))
        val Wink = BlobatarExpression("wink", Pose(esx = 1.32, esy = 0.76, tilt = 5.0, edy = -0.6, edx = 0.8, esx2 = 0.26, esy2 = -0.56, tilt2 = -11.0, lock = 1.0, bdy = -1.1))
        val Sleepy = BlobatarExpression("sleepy", Pose(esx = 1.14, esy = 0.22, edy = 2.4, edx = 0.3, esx2 = -0.04, esy2 = 0.03, tilt2 = 4.0, lock = 1.0, bdy = 1.2))
        val Smug = BlobatarExpression("smug", Pose(esx = 1.3, esy = 0.42, tilt = 18.0, edy = -0.5, edx = 0.5, esx2 = 0.06, esy2 = -0.06, tilt2 = -36.0, lock = 1.0, bdy = -1.0))
        val Unsure = BlobatarExpression("unsure", Pose(esx = 0.95, esy = 1.02, tilt = 4.0, edy = -0.2, edx = 0.3, esx2 = 0.24, esy2 = -0.44, tilt2 = -18.0, lock = 1.0))
        val Scared = BlobatarExpression("scared", Pose(esx = 0.78, esy = 0.96, tilt = -12.0, edy = -1.5, edx = -0.8, esx2 = -0.04, esy2 = 0.05, tilt2 = 4.0, lock = 1.0, shake = 0.35, bdy = -0.6))
        val Love = BlobatarExpression("love", Pose(esx = 0.86, esy = 1.28, tilt = -14.0, edy = -0.5, edx = -0.35, esx2 = 0.05, esy2 = 0.06, tilt2 = 6.0, lock = 1.0, heat = 0.6, bdy = -1.6), Tint.Rose)
        val Shy = BlobatarExpression("shy", Pose(esx = 0.62, esy = 0.5, tilt = 10.0, edy = 1.4, edx = -0.2, esx2 = -0.05, esy2 = -0.04, tilt2 = -8.0, lock = 1.0, heat = 0.55, bdy = 0.9), Tint.Blush)
        val Sick = BlobatarExpression("sick", Pose(esx = 1.25, esy = 0.34, tilt = 20.0, edy = 1.8, edx = 0.8, esx2 = 0.05, esy2 = -0.05, tilt2 = -6.0, lock = 1.0, heat = 0.6, shake = 0.18, bdy = 1.4), Tint.Bile)
        val Thinking = BlobatarExpression("thinking", Pose(esx = 1.15, esy = 0.62, edy = 4.2, edx = 0.4, esx2 = 0.02, esy2 = 0.06, edy2 = -8.4, lock = 1.0, rock = 0.8, bdy = -0.4))

        val all = listOf(Idle, Happy, Sad, Mad, Surprised, Wink, Sleepy, Smug, Unsure, Scared, Love, Shy, Sick, Thinking)

        fun named(name: String): BlobatarExpression? = all.firstOrNull { it.name == name }
    }
}

/** The palette a tinting expression wears, resolved against this one. */
fun BlobatarPalette.expressed(expression: BlobatarExpression): BlobatarPalette {
    val target = expression.tint ?: return this
    val (hotHead, hotEye) = BlobatarColor.tinted(head, eye, target)
    return copy(
        head = BlobatarColor.mixHex(head, hotHead, expression.pose.heat),
        eye = BlobatarColor.mixHex(eye, hotEye, expression.pose.heat),
    )
}
