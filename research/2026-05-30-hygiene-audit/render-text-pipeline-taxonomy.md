# Render Text Pipeline Taxonomy

Date: 2026-05-30.

## Sources Read

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `current.txt`
- `research/2026-05-30-hygiene-audit/roadmap.md` Phase 2 render taxonomy guidance
- `research/2026-05-30-hygiene-audit/synthesis.md`
- `howl-render/design.md`
- `libs.yaml`
- `howl-render/src/text/pipeline.zig`
- `howl-render/src/session/text.zig`
- `howl-render/src/text/frame_preparer.zig`
- `howl-render/src/text/direct_normal.zig`
- `howl-render/src/text/font/provider.zig`
- `howl-render/src/text/font/resolver.zig`
- `howl-render/src/text/font/ft_hb/support.zig`
- `howl-render/src/text/font/ft_hb/provider.zig`
- `howl-render/src/prepared/surface.zig`
- `howl-render/src/prepared/submit_result.zig`

## Decision

`howl-render/src/text/pipeline.zig` must be split, not renamed whole.

The file is not one owner. It contains resolve observability, prepare counters,
shape-operation request/output contracts, raster-operation request/output contracts,
build/group request-output contracts, and operation callback wrappers. A whole-file rename would
only replace the banned `pipeline` word with another dishonest bucket.

Reject `types.zig`, `api.zig`, manager, controller, engine, runtime, `flow`, and compatibility
aliases. These names would preserve the same vague ownership failure under different spelling.

## Public Symbol Inventory

| Symbol | Category | True owner classification |
| --- | --- | --- |
| `ResolveStage` | resolve | Resolve observability vocabulary for fallback and route reporting. |
| `ResolveRequest` | resolve | Resolve fallback-face operation input. No direct importer currently uses it. |
| `ResolveHit` | resolve | Resolve fallback-face operation success output. No direct importer currently uses it. |
| `ResolveMiss` | resolve | Resolve fallback-face operation miss output. No direct importer currently uses it. |
| `ResolveResult` | resolve | Resolve fallback-face operation union. No direct importer currently uses it. |
| `ResolveCounters` | resolve | Resolve observability counters owned by font/resolve telemetry. |
| `ResolveObservability` | resolve | Resolve observability snapshot carried through prepared and submit owners. |
| `TextPrepareCounters` | prepare counters | Text frame prepare counters owned by `TextFramePreparer` and direct-normal accounting. |
| `BuildRunsRequest` | build request-output | Stale build-runs request contract; no direct importer uses it. |
| `BuildRunsOutput` | build request-output | Stale build-runs output owner for clusters/runs allocation; no direct importer uses it. |
| `GroupGlyphsRequest` | group request-output | Stale grouping request contract; no direct importer uses it. |
| `GroupGlyphsOutput` | group request-output | Stale grouping output owner for glyph groups allocation; no direct importer uses it. |
| `ShapeRequest` | shape operation | Shape operation request for the generic `ShapeClustersOp` wrapper. No direct importer uses it. |
| `ShapeOutput` | shape operation | Shape operation output for generic shaped runs/glyphs/missing lists. No direct importer uses it. |
| `RasterizeRequest` | raster operation | Glyph raster operation request used by direct-normal and providers. |
| `RasterizeOutput` | raster operation | Glyph raster operation output used by providers and raster callbacks. |
| `ShapeClustersFn` | shape operation | Shape operation callback type. No direct importer uses it. |
| `RasterizeGlyphFn` | raster operation | Glyph raster operation callback type used through `RasterizeGlyphOp`. |
| `ResolveFallbackFaceFn` | resolve | Resolve fallback-face callback type. No direct importer currently uses it. |
| `ShapeClustersOp` | shape operation | Shape operation dispatch wrapper. No direct importer uses it. |
| `RasterizeGlyphOp` | raster operation | Glyph raster operation dispatch wrapper used by frame preparation and providers. |
| `ResolveFallbackFaceOp` | resolve | Resolve fallback-face dispatch wrapper. No direct importer currently uses it. |

## Direct Importers

- `howl-render/src/session/text.zig`
  uses `ResolveObservability`, `RasterizeRequest`, and `RasterizeOutput`.
- `howl-render/src/text/frame_preparer.zig`
  uses `TextPrepareCounters` and `RasterizeGlyphOp`.
- `howl-render/src/text/direct_normal.zig`
  uses `RasterizeRequest`, `RasterizeGlyphOp`, and `TextPrepareCounters`.
- `howl-render/src/text/font/provider.zig`
  uses `RasterizeGlyphOp`, `RasterizeRequest`, and `RasterizeOutput`.
- `howl-render/src/text/font/resolver.zig`
  uses `ResolveStage`.
- `howl-render/src/text/font/ft_hb/support.zig`
  uses `ResolveCounters`, `ResolveStage`, and `ResolveObservability`.
- `howl-render/src/text/font/ft_hb/provider.zig`
  uses `RasterizeGlyphOp`.
- `howl-render/src/prepared/surface.zig`
  uses `ResolveObservability`.
- `howl-render/src/prepared/submit_result.zig`
  uses `ResolveObservability`.

No direct importer uses `ResolveRequest`, `ResolveHit`, `ResolveMiss`, `ResolveResult`,
`BuildRunsRequest`, `BuildRunsOutput`, `GroupGlyphsRequest`, `GroupGlyphsOutput`,
`ShapeRequest`, `ShapeOutput`, `ShapeClustersFn`, `ResolveFallbackFaceFn`, `ShapeClustersOp`, or
`ResolveFallbackFaceOp` outside the local `pipeline.zig` test.

## First Implementation Move

Move resolve observability symbols first.

Exact source move:

- Add `howl-render/src/text/font/resolve_observability.zig`.
- Move `ResolveStage`, `ResolveCounters`, and `ResolveObservability` from
  `howl-render/src/text/pipeline.zig` into that file.
- Do not move `ResolveRequest`, `ResolveHit`, `ResolveMiss`, `ResolveResult`,
  `ResolveFallbackFaceFn`, or `ResolveFallbackFaceOp` in the first move.

Exact import repairs:

- `howl-render/src/session/text.zig`
  imports `../text/font/resolve_observability.zig` for `ResolveObservability`; keeps the current
  `pipeline.zig` import only for `RasterizeRequest` and `RasterizeOutput` until the raster move.
- `howl-render/src/text/font/ft_hb/support.zig`
  imports `resolve_observability.zig` for `ResolveCounters`, `ResolveStage`, and
  `ResolveObservability`.
- `howl-render/src/text/font/resolver.zig`
  imports `resolve_observability.zig` for `ResolveStage`.
- `howl-render/src/prepared/surface.zig`
  imports `../text/font/resolve_observability.zig` for `ResolveObservability`.
- `howl-render/src/prepared/submit_result.zig`
  imports `../text/font/resolve_observability.zig` for `ResolveObservability`.

Files not touched in the first move unless formatting/import order forces review:

- `howl-render/src/text/frame_preparer.zig`
- `howl-render/src/text/direct_normal.zig`
- `howl-render/src/text/font/provider.zig`
- `howl-render/src/text/font/ft_hb/provider.zig`

## Invariants

- No render behavior changes.
- No public C ABI headers or exported C symbols change.
- `ResolveObservability` remains the prepared/submit resolve telemetry shape.
- `ResolveCounters` fields and zero defaults remain identical.
- `ResolveStage` enum tags and integer backing type remain identical.
- `pipeline.zig` retains only symbols not moved in the first slice; no compatibility aliases remain.
- No `types.zig`, `api.zig`, manager, controller, engine, runtime, or similar bucket is introduced.

## Verification For First Move

- `zig build check`
- `zig build test`
- `git diff --check`

Grep gates after the first move:

- `rg 'ResolveStage|ResolveCounters|ResolveObservability' howl-render/src/text/pipeline.zig`
  prints nothing.
- `rg 'ResolveStage|ResolveCounters|ResolveObservability' howl-render/src/text/font/resolve_observability.zig`
  proves the moved symbols live in the new owner.
- `rg 'text_pipeline\.Resolve|pipeline\.Resolve' howl-render/src`
  prints nothing.
- `rg 'types\.zig|api\.zig|manager|controller|engine|runtime' howl-render/src/text howl-render/src/prepared howl-render/src/session`
  prints nothing except unrelated pre-existing terms if any are explicitly reviewed.
- `rg 'pipeline|text_pipeline|text_flow' howl-render/src libs.yaml`
  still prints remaining accepted work because this first move is intentionally partial.

## Why This Move Is Bounded

The first move touches three symbols with one category and one reason: resolve telemetry. It avoids
the raster operation path, prepare counters, unused build/group request-output contracts, and unused
generic shape/fallback operation wrappers. The import repair set is finite and source-proved by the
nine direct importers above. The move is reviewable by grep because every moved symbol name is exact,
and behavior is unchanged when the enum, counter fields, defaults, and imports are preserved.

## Non-Goals And Stop Conditions

Non-goals:

- Do not rename or delete `howl-render/src/text/pipeline.zig` in the first implementation move.
- Do not move raster operation symbols in the resolve observability move.
- Do not move prepare counters in the resolve observability move.
- Do not revive unused build/group/shape request-output contracts as public owners without a caller.
- Do not change headers, ABI symbols, prepared metrics, submit metrics, shaping, rasterization,
  scene preparation, or submit behavior.
- Do not add compatibility aliases from old `pipeline` names.

Stop conditions:

- Stop if moving the three resolve observability symbols requires changing field names, enum tags,
  backing type, or default values.
- Stop if a direct importer requires both old and new names through an alias.
- Stop if the move exposes a cycle between `font/resolver.zig`, `font/ft_hb/support.zig`,
  `prepared/*`, and `session/text.zig`.
- Stop if the implementation begins moving raster, shape, grouping, or prepare counter symbols in
  the same slice.

## Later Split Direction

- Move `TextPrepareCounters` to a frame-preparation counter owner near
  `howl-render/src/text/frame_preparer.zig` after the resolve move lands.
- Move `RasterizeRequest`, `RasterizeOutput`, `RasterizeGlyphFn`, and `RasterizeGlyphOp` to an exact
  glyph-raster operation owner near `howl-render/src/text/raster/` after direct-normal/provider
  callers are inventoried for that slice.
- Re-evaluate unused `BuildRunsRequest`, `BuildRunsOutput`, `GroupGlyphsRequest`,
  `GroupGlyphsOutput`, `ShapeRequest`, `ShapeOutput`, `ShapeClustersFn`, `ShapeClustersOp`,
  `ResolveRequest`, `ResolveHit`, `ResolveMiss`, `ResolveResult`, `ResolveFallbackFaceFn`, and
  `ResolveFallbackFaceOp` separately. Deleting unused public Zig-only contracts may be safer than
  preserving stale owners, but that is not part of the first move.
