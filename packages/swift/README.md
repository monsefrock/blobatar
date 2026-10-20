# Blobatar for Swift (iOS, iPadOS, macOS)

A native Swift port of the Blobatar gen-2 engine (parity version 2.4.0): the same name draws the
same character as the web package, drawn with SwiftUI instead of an SVG.

```swift
import Blobatar

BlobatarView("alain@example.com")
    .frame(width: 48, height: 48)

// A plate behind it, and an expression
BlobatarView("alain@example.com", options: BlobatarOptions(background: .circle, expression: .happy))
```

- `Blobatar(name, options:)` resolves the geometry (`layout`) and colors (`palette`) once;
  `draw(in:size:)` paints it into any `GraphicsContext`, and `svg()` returns the markup.
- Options mirror the web: `hue`, `tone`, `traits`, `normalize`, `contrast`, `background`,
  `backgroundColor`, palette overrides (`bg`, `head`, `eye`) and the 14 static expressions.
- `AnimatedBlobatarView` is the living version: it breathes, bobs, blinks and glances around on
  the same seeded timing as the web, and morphs between expressions. Reduce Motion shows it still.

## Parity

`swift test` checks the engine against `packages/flutter/test/fixtures/reference-vectors.json`,
exported from the TypeScript core: hashes, palettes, path strings and shape names exactly, layout
numbers within 1e-9, across all 1,570 layout cases and 42 expression cases. The motion seeds and
frames are checked against the TypeScript core's values too.

Add it with Swift Package Manager (this repo, path `packages/swift`).
