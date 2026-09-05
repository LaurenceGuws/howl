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

Font discovery is also caller-owned. `Config` takes explicit font paths;
`MemoryConfig` takes bytes copied into the font owner.

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

## Owned font bytes

`FontSet.initMemory(allocator, MemoryConfig)` complements the existing path-based
constructor. It copies the primary and ordered fallback font bytes into the
opaque owner; callers may release or overwrite their input immediately after
construction. Native faces close before their copied font storage is released,
on both successful teardown and partial-construction failure.

Memory input is bounded before any allocation or native access: one required
nonempty primary, at most 24 fallbacks, at most 32 MiB per font and 64 MiB total
copied font data. Those limits do not include the separate native library
allocations. Sizing, metrics, fallback selection, shaping and natural rasterization
share the same engine as path loading. This is not a second browser text engine.

Native proofs compare path/memory metrics, source clusters, glyphs, variation
fallback and alpha masks after destroying the caller's input. They exercise
configuration limits and every Zig allocation-failure point, including cleanup
of already-opened fallback faces. C-library allocation failure is not exhaustively
injected by those tests.

## Target-built dependencies

The ordinary module build still uses system FreeType/HarfBuzz and libc. It does
not download the optional upstream dependencies. A consuming build can request
`bundled = true` to build the exact content-pinned upstream sources recorded in
`build.zig.zon`. `bundled.zig` owns their configuration and linkage. No caller
passes machine-local source mirrors or modifies a dependency cache.

This bundled configuration is **memory-only**: filesystem font streams,
environment configuration, HarfBuzz file/mmap loading and threading are disabled.
Use `FontSet.initMemory`, not filesystem path loading, with that configuration.
The normal system-backed module retains path loading. Both configurations retain
the actual FreeType/HarfBuzz shaping and rasterization implementations.

The current Web target is `wasm32-wasi` with exception handling, not the
zero-import freestanding wire canary. The exact pinned compiler's C nonlocal-jump
path needs LLVM SjLj lowering, a matching declaration macro during C translation,
and the narrow exception-tag definition in `config/wasi-exception-tag.c`. That
file defines the missing tag only; the real jump implementation comes from the
compiler's libc. A C regression probe tests both nonzero and zero longjmp values.
Reassess this compatibility detail when the tracked compiler changes.

The maintained target proof is owned by the Web consumer:

```sh
cd ../howl-web
zig build text-check
zig build text-web
```

`text-check` builds the same upstream revisions natively and for Wasm, then
compares metadata and every raster byte. `text-web` creates a **local-only**
font/raster test site at `text/zig-out/text-web/`. It is not the terminal client,
an installed PWA or a public font distribution.

The text canary's browser runtime admits exactly four WASI functions:
`fd_close`, `fd_seek`, `fd_write` and `random_get`. It provides bounded console
output, explicit bad-descriptor/nonseekable errors and real host entropy, but no
filesystem. It recreates memory views after Wasm calls because libc can grow
linear memory. The proof uses 64 MiB initial memory and a 96 MiB maximum; these
are coarse canary budgets, not a finished terminal footprint or an
allocation-free promise. Fifty repeated font lifetimes must reproduce the native
result without increasing warmed-up linear memory.

Dependency notices are retained in `LICENSES/bundled-dependencies.txt` and copied
into the local browser proof alongside the existing fixture licences.
