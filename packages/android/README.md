# Blobatar for Android (Kotlin, Jetpack Compose)

A native Kotlin port of the Blobatar gen-2 engine (parity version 2.4.0): the same name draws the
same character as the web package, drawn with Compose instead of an SVG.

```kotlin
import dev.blobatar.Blobatar

Blobatar("alain@example.com", Modifier.size(48.dp))

// A plate behind it, and an expression
Blobatar(
    "alain@example.com",
    Modifier.size(48.dp),
    BlobatarOptions(background = BlobatarBackdrop.Circle, expression = BlobatarExpression.Happy),
)
```

- `Blobatar(name, options)` (the class) resolves the geometry (`layout`) and colors (`palette`);
  `DrawScope.drawBlobatar(...)` paints it on any Compose canvas.
- Options mirror the web: `hue`, `tone`, `traits`, `normalize`, `contrast`, `background`,
  `backgroundColor`, palette overrides (`bg`, `head`, `eye`) and the 14 static expressions.
- Math goes through `StrictMath` (fdlibm, which V8 also uses), so results don't depend on the device.
- Not ported yet: the animated renderer.

## Parity

`./gradlew :blobatar:testDebugUnitTest` checks the engine against
`packages/flutter/test/fixtures/reference-vectors.json`, exported from the TypeScript core: hashes,
palettes, path strings and shape names exactly, layout numbers within 1e-9, across all 1,570 layout
cases and 42 expression cases.

The library module is `blobatar/` (namespace `dev.blobatar`, minSdk 21).
