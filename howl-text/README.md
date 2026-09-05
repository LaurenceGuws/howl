# howl-text

`howl-text` is a small native Zig text engine for bounded font loading, metrics,
fallback selection, OpenType shaping, source-cluster identity, glyph lookup, and
alpha rasterization.

It deliberately stops before presentation. Windows, widgets, terminal cells,
line wrapping, clipping, GPU resources, and application layout belong to its
callers.

## Boundary

The public module is `howl_text`.

- `FontSet` owns one primary font plus an ordered bounded fallback list.
- `ShapeBuffer` owns reusable bounded HarfBuzz shaping storage.
- `shape` accepts Unicode scalar values plus caller-defined source-cluster IDs
  and returns positioned glyphs borrowing caller storage.
- `faceFor` and `glyphForCodepoint` expose low-level face/glyph lookup when a
  caller does not need shaping.
- `rasterize` returns a tightly packed bounded alpha mask at the configured font
  size with the glyph's natural bearings. It does not rescale or crop to fit a
  presentation box.

Retained FreeType and HarfBuzz state is opaque to consumers. Allocation
ownership and shaping/raster ceilings are explicit in the API.

## Current scope

The library currently uses the system FreeType and HarfBuzz libraries and libc.
Fallback selection is intentionally simple: one complete input sequence is
shaped with the first configured face that covers every scalar in that
sequence. Rich script-itemization and per-span fallback are not hidden behind a
pretend-generic abstraction; they can be added when a real consumer earns that
requirement.

Font discovery is also caller-owned. `Config` takes explicit font paths.

## Build

The package is pinned to the Zig version in `build.zig.zon` and expects
FreeType and HarfBuzz development files to be available through the system
toolchain.

```sh
zig build check
zig build test
```

Deterministic font fixtures used by the native proofs are documented in
`LICENSES/test-fonts.txt`.
