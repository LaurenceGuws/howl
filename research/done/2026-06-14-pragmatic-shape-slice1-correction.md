# Historical Authority

- Historical authority at time: accepted Slice 1 correction package for `orch-2026-06-14-six-target-pragmatic-shape-01`.
- Why superseded or done: promoted into the active sprint contract for corrected Slice 1 execution.
- Must not be used for: direct execution authority after promotion; use the active sprint and loop contract instead.

# Pragmatic Shape Slice 1 Correction

Status:

- Active correction research artifact for rejected pragmatic-shape Slice 1.
- Orchestrator session id: `orch-2026-06-14-six-target-pragmatic-shape-01`.
- Researcher session id: `research-2026-06-14-six-target-pragmatic-shape-01`.
- Reviewer session id: `review-2026-06-14-six-target-pragmatic-shape-01`.
- Trigger: reviewer rejection of Slice 1 because `support.zig` still exposes ownership-probing `anytype` and context-extraction wrappers.
- Reviewer accepted correction.
- No Slice 1 acceptance is authorized until this correction is promoted into the execution scope and the scope is reseeded.
- Correction acceptance receipt: pending orchestrator commit.

Sources read in order:

1. `loop/flow.md`
2. `loop/orcestrator.md`
3. `loop/researcher.md`
4. `loop/reviewer.md`
5. `loop/coder.md`
6. `loop/researcher.md` reread
7. `sprints/current.txt`
8. `loops/six-target-pragmatic-shape-live-loop.txt`
9. `research/2026-06-14-pragmatic-shape-slice1-correction.md`
10. `sprints/2026-06-14-six-target-pragmatic-shape-sprint.md`
11. `research/done/2026-06-14-six-target-pragmatic-shape-plan.md`
12. Current source under study:
    - `howl-render/src/text/ft_hb/support.zig`
    - `howl-render/src/render_session.zig`
    - `howl-render/src/text/ft_hb/glyph_raster.zig`

Compact anchor map:

- Alacritty `glyph_cache.rs:46-99, 191-245`: the text/font owner stays direct; callers do not recover owner state through generic wrapper seams.
- TigerBeetle `TIGER_STYLE.md:90-100, 109-126, 271-360`: remove ambient genericity, keep nouns exact, and do not preserve compatibility shims once the true owner seam is known.
- Accepted Howl planning seam `research/done/2026-06-14-six-target-pragmatic-shape-plan.md:151-194`: `support.zig` must expose explicit `*FtHbSupport` plus `render_session.TextSessionConfig` entry points only.
- Current Howl execution seam `render_session.zig:142-159, 323-355, 373, 491`: `render_session.zig` already switched its callers to explicit `WithConfig` support entry points.
- Current remaining dependency seam `glyph_raster.zig:63-84`: glyph raster still calls probing wrappers from `support.zig`.

Current-code facts:

- `support.zig` no longer uses the earlier `textState`/`configView`/`lockFt`/`unlockFt` owner-probing helpers; explicit `WithConfig` entry points now exist for the real work (`support.zig:133-141, 148-230, 330-353, 366-519, 536-538`).
- `render_session.zig` already extracts `*FtHbSupport` and `TextSessionConfig` at its boundary and calls `WithConfig` entry points directly (`render_session.zig:142, 154-157, 323, 329-346, 355, 373, 491`).
- `support.zig` still exports public wrapper shims that recover state/config from generic context or `anytype` self values (`support.zig:128-131, 143-146, 182-193, 326-343, 355-363, 397-415, 449-462, 475-477, 525-533`).
- The only remaining non-`support.zig` caller that still depends on those public probing wrappers is `glyph_raster.zig`, specifically `ensureFont(self)` and `acquireShapingFaceLocked(self, face_id)` (`glyph_raster.zig:79-83`).
- No remaining current caller uses the public probing wrappers `providerHasCodepoint`, `providerHasCellText`, `providerShapeRun`, `providerGlyphId`, `providerGlyphAdvance`, `providerLookupGlyph`, `ensurePrimaryFont`, `resizeLoadedFaces`, `ensureFallbackFace`, or `deriveCellMetrics`; grep of `howl-render/src/**/*.zig` found only their definitions in `support.zig`.

Reference facts:

- The accepted plan already fixed the intended owner seam: `render_session.zig` is the extraction boundary and `support.zig` should expose only explicit state/config entry points.
- TigerBeetle pressure rejects leaving public compatibility shims once the exact owner seam is known.
- No reference pressure supports keeping the public probing wrappers for convenience once the only remaining caller is local and exact.

Owner roles and proposed shape:

- `support.zig` remains the FT/HB support owner.
- `render_session.zig` remains the only render-session extraction boundary.
- `glyph_raster.zig` is a caller of support, not a competing owner.
- Proposed corrected shape: delete all remaining public probing wrappers from `support.zig`; update `glyph_raster.zig` to pass explicit `*FtHbSupport` and `TextSessionConfig` to support entry points; keep `render_session.zig` on its current explicit seam.

Sprint scratchpad:

- Slice 1 implementation is close, but it stopped one caller short.
- `render_session.zig` no longer blocks the cleanup.
- Scope expansion is narrow and exact: one additional caller file, `glyph_raster.zig`.
- This does not justify a new slice split. It just means the seeded Slice 1 allowed-file scope was incomplete.

Exact inventory of remaining ownership-probing wrappers in `howl-render/src/text/ft_hb/support.zig`:

- `support.zig:128-131` `providerHasCodepoint(comptime ContextType, ctx, ...)`
  - Kind: public context-extracting wrapper.
  - Current dependency: none outside its own definition.
  - Replacement already present: `providerHasCodepointWithConfig` at `133-141`.
- `support.zig:143-146` `providerHasCellText(comptime ContextType, ctx, ...)`
  - Kind: public context-extracting wrapper.
  - Current dependency: none outside its own definition.
  - Replacement already present: `providerHasCellTextWithConfig` at `148-163`.
- `support.zig:182-193` `providerShapeRun(comptime ContextType, ctx, ...)`
  - Kind: public context-extracting wrapper.
  - Current dependency: none outside its own definition.
  - Replacement already present: `providerShapeRunWithConfig` at `195-230`.
- `support.zig:326-328` `providerGlyphId(self: anytype, ...)`
  - Kind: public `anytype` owner-probing wrapper.
  - Current dependency: none outside its own definition.
  - Replacement already present: `providerGlyphIdWithConfig` at `330-339`.
- `support.zig:341-343` `providerGlyphAdvance(self: anytype, ...)`
  - Kind: public `anytype` owner-probing wrapper.
  - Current dependency: none outside its own definition.
  - Replacement already present: `providerGlyphAdvanceWithConfig` at `345-353`.
- `support.zig:355-363` `providerLookupGlyph(comptime ContextType, ctx, ...)`
  - Kind: public context-extracting wrapper.
  - Current dependency: none outside its own definition.
  - Replacement already present: `providerLookupGlyphWithConfig` at `366-386`.
- `support.zig:397-399` `ensurePrimaryFont(self: anytype)`
  - Kind: public `anytype` owner-probing wrapper.
  - Current dependency: none outside its own definition.
  - Replacement already present: `ensurePrimaryFontWithConfig` at `401-405`.
- `support.zig:407-415` `ensureFont(self: anytype)`
  - Kind: public `anytype` owner-probing wrapper.
  - Current dependency: `howl-render/src/text/ft_hb/glyph_raster.zig:79`.
  - Replacement already present: `ensureFontWithConfig` at `418-440`.
- `support.zig:449-451` `resizeLoadedFaces(self: anytype)`
  - Kind: public `anytype` owner-probing wrapper.
  - Current dependency: none outside its own definition.
  - Replacement already present: `resizeLoadedFacesWithConfig` at `453-458`.
- `support.zig:460-462` `ensureFallbackFace(self: anytype, ...)`
  - Kind: public `anytype` owner-probing wrapper.
  - Current dependency: none outside its own definition.
  - Replacement already present: `ensureFallbackFaceWithConfig` at `464-473`.
- `support.zig:475-477` `deriveCellMetrics(self: anytype)`
  - Kind: public `anytype` owner-probing wrapper.
  - Current dependency: none outside its own definition.
  - Replacement already present: `deriveCellMetricsWithConfig` at `479-510`.
- `support.zig:525-533` `acquireShapingFaceLocked(self: anytype, ...)`
  - Kind: public `anytype` owner-probing wrapper.
  - Current dependency: `howl-render/src/text/ft_hb/glyph_raster.zig:82`.
  - Replacement already present: `acquireShapingFaceFromStateLocked` at `536-538`.

Exact remaining callers depending on those wrappers:

- `howl-render/src/text/ft_hb/glyph_raster.zig:79`
  - Calls `provider_mod.ensureFont(self)`.
  - This blocks deletion of `support.zig:407-415` unless `glyph_raster.zig` is brought into slice scope.
- `howl-render/src/text/ft_hb/glyph_raster.zig:82`
  - Calls `provider_mod.acquireShapingFaceLocked(self, face_id)`.
  - This blocks deletion of `support.zig:525-533` unless `glyph_raster.zig` is brought into slice scope.

Exact allowed-file expansion required to finish the cleanup without compatibility shims:

- Current seeded Slice 1 allowed files are insufficient.
- Minimal exact expansion required:
  - `howl-render/src/text/ft_hb/support.zig`
  - `howl-render/src/render_session.zig`
  - `howl-render/src/text/ft_hb/glyph_raster.zig`
  - `howl-render/src/text/ft_hb/support_test.zig`
  - `howl-render/src/text/ft_hb/glyph_raster.zig` as its own existing inline unit-test root
- No additional caller file was found.
- No compatibility shim should be kept once this scope is available.

Decision:

- Repair Slice 1 in place with expanded file scope.
- Do not split the slice.
- Do not stop the sprint.
- Reason: the remaining work is still the same owner-seam cleanup described by accepted planning, and the only missing scope is one exact local caller file, `glyph_raster.zig`.

Corrected Slice 1 execution contract:

- Slice name: `Slice 1 support direct-owner cleanup correction`
- Allowed files:
  - `howl-render/src/text/ft_hb/support.zig`
  - `howl-render/src/render_session.zig`
  - `howl-render/src/text/ft_hb/glyph_raster.zig`
  - `howl-render/src/text/ft_hb/support_test.zig`
- Required shape:
  - Keep `FtHbSupport` as the sole support-state owner in `support.zig`.
  - Keep `render_session.zig` as the only session/context extraction boundary.
  - Delete all remaining public probing wrappers from `support.zig`: `providerHasCodepoint`, `providerHasCellText`, `providerShapeRun`, `providerGlyphId`, `providerGlyphAdvance`, `providerLookupGlyph`, `ensurePrimaryFont`, `ensureFont`, `resizeLoadedFaces`, `ensureFallbackFace`, `deriveCellMetrics`, and `acquireShapingFaceLocked`.
  - Route `glyph_raster.zig` through explicit `WithConfig` or explicit state/config support entry points instead of wrapper recovery.
  - Do not add compatibility shims, alias wrappers, or new vague context buckets.
  - Keep fallback behavior and deterministic test fallback behavior unchanged.
- Exact tests:
  - From `howl-render`, run `zig build test:unit`.
  - Required test files:
    - `howl-render/src/text/ft_hb/support_test.zig`
    - `howl-render/src/text/ft_hb/glyph_raster.zig`
  - Required exact test names in `support_test.zig`:
    - `provider loads fallback face for symbol glyph with primary present`
    - `ft hb state configures explicit retained cache and input capacities`
    - `shape run input assembly reuses retained bounded buffers`
  - Required exact test names in `glyph_raster.zig`:
    - `provider decodes packed monochrome bitmap alpha`
    - `provider box fallback draws routed generated special families`
    - `provider deterministic fallback matches fallback raster for glyph and sprite entry points`
- Non-goals:
  - No `glyph_raster.zig` redesign beyond deleting its dependency on the probing wrappers.
  - No cache policy change.
  - No font fallback policy change.
  - No render-session API redesign beyond the explicit support seam already chosen.
- Stop conditions:
  - Stop if cleanup spreads beyond `support.zig`, `render_session.zig`, and `glyph_raster.zig`.
  - Stop if deleting the wrappers requires a new vague compatibility bucket or replacement shim.
  - Stop if fallback behavior or deterministic fallback test behavior changes.
  - Stop if another caller file outside the expanded scope is discovered to depend on the wrappers.
- Required receipt fields:
  - planning seed receipt: `117b860`
  - accepted planning receipt: `9f20f26`
  - sprint seed receipt: `1f2c1cc`
  - slice 1 seed receipt: `e5d47e2`
  - slice 1 correction seed receipt: `499964b` `Seed pragmatic-shape Slice 1 correction`
  - orchestrator session id: `orch-2026-06-14-six-target-pragmatic-shape-01`
  - researcher session id: `research-2026-06-14-six-target-pragmatic-shape-01`
  - reviewer session id: `review-2026-06-14-six-target-pragmatic-shape-01`
  - coder session id: pending reseed by orchestrator
  - verification result: `zig build test:unit` in `howl-render`
  - commit-hash handoff required on slice acceptance

Risks:

- `glyph_raster.zig` still contains its own internal `anytype` probing helpers, but the reviewer rejection supplied here only requires removing the remaining public support wrappers. The corrected slice must not broaden into an unsourced second cleanup unless the orchestrator reseeds it.

Proof gaps:

- I did not inspect git diff state, per instruction not to touch git. This correction is based on current source plus the live rejection note.
- If execution reveals another hidden caller outside `howl-render/src/text/ft_hb/glyph_raster.zig`, the slice must stop and be reseeded again.

Readiness judgment:

- Ready for reviewer check and orchestrator reseed.
- The correction is exact and points to one minimal scope expansion, not a sprint-level stop.
