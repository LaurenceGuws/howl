# Raster Special Ownership Compression Plan

Date: 2026-06-13.

Status: accepted planning package; Slice 1 and Slice 2 are accepted in nested render history and the next slice is not yet seeded.

Role owner: researcher.

Orchestrator session id: `orch-2026-06-13-raster-special-01`.

Researcher session id: `research-2026-06-13-raster-special-01`.

Reviewer session id: `review-2026-06-13-raster-special-01`.

Planning commit-hash receipt: root `0e53a8e`.

Question:

- What is the highest-value source-backed owner compression sprint for the current render raster concentration, starting with `howl-render/src/text/raster/special.zig`, and what exact sequential execution slices does that require without inventing new architecture or moving ABI truth?

## Sources Read In Order

1. `loop/flow.md`
2. `loop/orcestrator.md`
3. `loop/researcher.md`
4. `loop/reviewer.md`
5. `loop/coder.md`
6. `loop/researcher.md` reread as the active role contract
7. `sprints/current.txt`
8. `loops/raster-special-ownership-compression-live-loop.txt`
9. `research/2026-06-13-raster-special-ownership-compression-plan.md`
10. `reference-index.md`
11. `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs`
12. `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/atlas.rs`
13. `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs`
14. `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/builtin_font.rs`
15. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
16. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
17. `sprints/2026-06-13-raster-special-ownership-compression-sprint.md`
18. `howl-render/src/text/raster/special.zig`
19. `howl-render/src/text/raster/rasterizer.zig`
20. `howl-render/src/text/raster/special_test.zig`
21. `howl-render/src/text/special_glyphs.zig`
22. `howl-render/src/text/symbol_map.zig`
23. `howl-render/src/text/resolver.zig`
24. `howl-render/src/text/lane.zig`
25. `howl-render/src/text/shape/grouping.zig`
26. `howl-render/src/text/ft_hb/glyph_raster.zig`
27. `howl-render/src/text/scene.zig`
28. `howl-render/src/text/shape/cluster.zig`
29. `howl-linux-host/src/display/render_surface.zig`
30. `howl-render/src/surface/emitter.zig`
31. `howl-linux-host/src/terminal/surface.zig`
32. `howl-render/src/test_unit.zig`
33. `howl-render/build.zig`
34. `build.zig`

## Exact Files And Line References

- `loop/flow.md:14-41,122-137`
- `loop/orcestrator.md:11-24,37-53`
- `loop/researcher.md:15-74`
- `loop/reviewer.md:13-32,33-57`
- `loop/coder.md:13-25,26-39`
- `sprints/current.txt:8-18,39-49`
- `loops/raster-special-ownership-compression-live-loop.txt:30-55,79-91`
- `sprints/2026-06-13-raster-special-ownership-compression-sprint.md:17-45,47-74`
- `research/2026-06-13-raster-special-ownership-compression-plan.md:21-543`
- `howl-render/src/text/raster/special.zig:5-63,66-127,129-176,178-251,253-259,261-866,872-1246,1255-1439,1442-1687,1688-1835`
- `howl-render/src/text/raster/rasterizer.zig:93-136,161-166`
- `howl-render/src/text/raster/special_test.zig:10-742`
- `howl-render/src/text/special_glyphs.zig:10-32,41-49`
- `howl-render/src/text/symbol_map.zig:4-11,22-57`
- `howl-render/src/text/resolver.zig:115-167,265-269,272-342`
- `howl-render/src/text/lane.zig:433-465`
- `howl-render/src/text/shape/grouping.zig:97-120,162-203,259-298`
- `howl-render/src/text/ft_hb/glyph_raster.zig:151-163,239-261`
- `howl-render/src/text/scene.zig:258-312,396-445,768-790`
- `howl-render/src/text/shape/cluster.zig:13-29,31-103,111-170,172-243,245-260`
- `howl-linux-host/src/display/render_surface.zig:34-90,121-227`
- `howl-render/src/surface/emitter.zig:14-20,193-260`
- `howl-linux-host/src/terminal/surface.zig:52-186,188-260`
- `howl-render/src/test_unit.zig:1-12`
- `howl-render/build.zig:53-101,155-171`
- `build.zig:34-38,61-76`
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:11-21,49-95,183-197`
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/atlas.rs:33-61,118-140,247-295`
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs:42-79,208-245`
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/builtin_font.rs:22-38,49-597,599-670`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:90-125,161-176,315-333,374-430`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:94-101,408-423`

## Current-Code Facts

- `special.zig` is the real raster concentration. It owns undercurl request/raster entrypoints at `howl-render/src/text/raster/special.zig:5-47`, generated-special public entrypoints and dispatch at `special.zig:49-127`, and every current generated-special family raster implementation at `special.zig:129-176,178-251,253-259,261-866,872-1246,1255-1439,1442-1687,1688-1795`.
- The public render seam is still `rasterizer.zig`, which re-exports `special.zig` entrypoints at `howl-render/src/text/raster/rasterizer.zig:133-136`.
- Undercurl is already a distinct semantic owner in current source:
  - request constructor: `howl-render/src/text/raster/special.zig:5-17`
  - alpha raster: `howl-render/src/text/raster/special.zig:19-47`
  - undercurl-only helper: `howl-render/src/text/raster/special.zig:1811-1817`
  - scene request construction and append: `howl-render/src/text/scene.zig:276-312,430-445`
  - provider special-case dispatch: `howl-render/src/text/ft_hb/glyph_raster.zig:151-155`
  - proof roots: `howl-render/src/text/raster/special_test.zig:10-19`, `howl-render/src/text/scene.zig:768-790`
- Generated specials are already a distinct semantic owner in current source:
  - public entrypoints and support gate: `howl-render/src/text/raster/special.zig:49-63`
  - current family table: `howl-render/src/text/raster/special.zig:94-127`
  - support table: `howl-render/src/text/special_glyphs.zig:10-32`
  - route split: `howl-render/src/text/symbol_map.zig:4-11`, `howl-render/src/text/resolver.zig:129-166`
  - grouping kind and keying: `howl-render/src/text/shape/grouping.zig:97-120,162-203`
  - provider fallback raster route: `howl-render/src/text/ft_hb/glyph_raster.zig:156-163`
- The current source already encodes these coarse raster owner boundaries:
  - box owner: `howl-render/src/text/raster/special.zig:129-156,872-1246`
  - powerline owner: `howl-render/src/text/raster/special.zig:158-176,253-259,1442-1687`
  - block plus braille owner through one dispatch function: `howl-render/src/text/raster/special.zig:178-184,1369-1439,1688-1795`
  - legacy-computing route owner from sextant through branch: `howl-render/src/text/raster/special.zig:116-124,186-239,261-866,1255-1367`
- Box already has box-only helper pressure in current source:
  - line/corner owners: `howl-render/src/text/raster/special.zig:872-1246`
  - box-only range/smoothing helpers: `howl-render/src/text/raster/special.zig:1235-1243`
- The reviewer-flagged helper surface is legacy-only in current source:
  - legacy-only enums: `howl-render/src/text/raster/special.zig:317-318`
  - legacy-only geometry helpers: `howl-render/src/text/raster/special.zig:784-866`
  - callers stay inside half-triangle, shade/corner/cross, mid-line, and branch owners at `howl-render/src/text/raster/special.zig:320-781`
- The truly shared retained helper surface is narrower than the previous artifact claimed:
  - `PointF` and `lineY` are shared by smooth-mosaic legacy code and powerline geometry at `howl-render/src/text/raster/special.zig:269-315,1476-1482,1520-1524,1682-1686`
  - `drawLineAlpha` is shared by box cross-lines and powerline diagonals at `howl-render/src/text/raster/special.zig:1246-1253,1456-1465,1659-1680`
  - `Range` and `eighthPartitionRange` are shared by block and legacy partition owners at `howl-render/src/text/raster/special.zig:199-228,1233`
  - `supersampledCoverage` is shared by powerline and braille owners at `howl-render/src/text/raster/special.zig:1504-1554`
  - shared pixel/index helpers stay at `howl-render/src/text/raster/special.zig:1797-1835`
- The proof surface is explicit:
  - curated unit root: `howl-render/src/test_unit.zig:1-12`
  - generated-special proof owner: `howl-render/src/text/raster/special_test.zig:21-679`
  - provider parity proof: `howl-render/src/text/ft_hb/glyph_raster.zig:239-261`
  - route parity proofs: `howl-render/src/text/symbol_map.zig:22-57`, `howl-render/src/text/resolver.zig:294-342`, `howl-render/src/text/lane.zig:449-465`, `howl-render/src/text/shape/grouping.zig:259-298`
  - undercurl scene proof: `howl-render/src/text/scene.zig:768-790`

## Reference Facts

- Alacritty keeps text rendering under one renderer/text boundary, not in host/display files: `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:11-21`.
- Alacritty separates atlas and glyph cache owners from built-in special glyph drawing: `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/atlas.rs:33-61,118-140,247-295`, `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs:42-79,208-245`.
- Alacritty routes built-in specials through a dedicated builtin owner inside the text renderer: `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs:208-245`, `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/builtin_font.rs:22-38`.
- Alacritty’s closest source pressure is coarse raster owner domains, not helper shattering:
  - box-drawing owner pressure: `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/builtin_font.rs:49-597`
  - powerline owner pressure: `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/builtin_font.rs:599-670`
- TigerBeetle requires explicit control flow, assertions, source order, and true owners: `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:90-125,161-176,315-333,374-430`.
- TigerBeetle architecture pressure favors intentional owner cuts over accidental concentration: `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:94-101,408-423`.

## Compact Anchor Map

- Workflow gate:
  - Planning must produce sequential slices with exact allowed files, exact required shape, exact tests, exact non-goals, exact stop conditions, and accountable session ids: `loop/flow.md:22-41`
  - The researcher output contract requires `compact anchor map`, `sprint scratchpad`, `required assertions`, `required tests`, and `readiness judgment`: `loop/researcher.md:60-74`
- Stable reference anchors:
  - Alacritty keeps built-in special glyph raster ownership inside `renderer/text`, not in host display/runtime owners: `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:11-21`, `builtin_font.rs:22-38`
  - TigerBeetle rejects vague buckets and demands owner-true cuts with explicit proof: `TIGER_STYLE.md:90-125,315-333,374-430`, `ARCHITECTURE.md:94-101,408-423`
- Current public seam anchors:
  - `rasterizer.zig` remains the render-facing entrypoint and re-export seam: `howl-render/src/text/raster/rasterizer.zig:133-136`
  - `special_glyphs.zig`, `symbol_map.zig`, `resolver.zig`, `lane.zig`, `grouping.zig`, `glyph_raster.zig`, and `scene.zig` are support, route, caller, and proof seams rather than the first raster owners: `howl-render/src/text/special_glyphs.zig:10-32`, `symbol_map.zig:4-11`, `resolver.zig:129-166`, `lane.zig:449-465`, `grouping.zig:162-203`, `glyph_raster.zig:151-163`, `scene.zig:276-312`
- Current owner-seam anchors:
  - undercurl owner seam: `howl-render/src/text/raster/special.zig:5-47,1811-1817`
  - generated-special root seam: `howl-render/src/text/raster/special.zig:49-127`
  - box owner seam: `howl-render/src/text/raster/special.zig:129-156,872-1246`
  - powerline owner seam: `howl-render/src/text/raster/special.zig:158-176,253-259,1442-1687`
  - block plus braille owner seam: `howl-render/src/text/raster/special.zig:178-184,1369-1439,1688-1795`
  - legacy-computing owner seam: `howl-render/src/text/raster/special.zig:186-239,261-866,1255-1367`
- Proof anchors:
  - unit root: `howl-render/src/test_unit.zig:1-12`
  - raster-special owner proofs: `howl-render/src/text/raster/special_test.zig:10-679`
  - provider parity: `howl-render/src/text/ft_hb/glyph_raster.zig:239-261`
  - route and lane parity: `howl-render/src/text/symbol_map.zig:22-57`, `resolver.zig:294-342`, `lane.zig:449-465`, `grouping.zig:259-298`
  - scene undercurl parity: `howl-render/src/text/scene.zig:768-790`

## Repaired Fallback Ranking

1. `howl-render/src/text/scene.zig` does not preempt `special.zig`.
- `scene.zig` builds requests and appends sprite draws at `howl-render/src/text/scene.zig:258-312,396-445`.
- The raster owner remains behind `rasterizer.zig` re-exports at `howl-render/src/text/raster/rasterizer.zig:133-136`.
- Moving `scene.zig` first would change a caller seam before reducing the `special.zig` raster burden.

2. `howl-linux-host/src/display/render_surface.zig` does not preempt `special.zig`.
- `render_surface.zig` owns host GL texture slots, create/upload/retire validation, and GL realization at `howl-linux-host/src/display/render_surface.zig:34-90,121-227`.
- It is host backend resource realization, not text raster family ownership.
- Moving it first would violate the render-vs-host ownership boundary without reducing `special.zig`.

3. `howl-render/src/surface/emitter.zig` does not preempt `special.zig`.
- `emitter.zig` owns render-surface command/resource emission and emission bounds at `howl-render/src/surface/emitter.zig:14-20,193-260`.
- It consumes prepared sprite outputs; it does not own generated-special alpha geometry.
- Moving it first would reorder a control-plane seam before the real raster concentration.

4. `howl-linux-host/src/terminal/surface.zig` does not preempt `special.zig`.
- `terminal/surface.zig` owns host runtime state, init/deinit, layout, and input orchestration at `howl-linux-host/src/terminal/surface.zig:52-186,188-260`.
- It is host runtime policy, not render raster implementation.
- Moving it first would widen scope into host orchestration with zero reduction in `special.zig`.

5. `howl-render/src/text/shape/cluster.zig` does not preempt `special.zig`.
- `cluster.zig` owns input cell assembly, line-text cache assembly, retained scratch, and cluster construction before resolve/group/raster phases at `howl-render/src/text/shape/cluster.zig:13-29,31-103,111-170,172-243,245-260`.
- It is pre-raster text shaping input, not generated-special raster ownership.
- Moving it first would change an upstream input seam before reducing the raster owner burden.

## Owner Roles And Proposed Shape

- `howl-render/src/text/raster/special.zig`: curated root that re-exports owner files only.
- `howl-render/src/text/raster/undercurl.zig`: owns undercurl request construction, undercurl alpha raster, and the undercurl-only `addAlpha` helper.
- `howl-render/src/text/raster/generated_special.zig`: owns generated-special public entrypoints, family dispatch, and only the exact helper surface still shared after the family extractions.
- `howl-render/src/text/raster/special_box.zig`: owns box-family raster code and every box-only helper, including `centeredRange` and `smoothStep`.
- `howl-render/src/text/raster/special_powerline.zig`: owns powerline-family raster code and powerline-only helpers.
- `howl-render/src/text/raster/special_block_braille.zig`: owns the current block-plus-braille dispatch owner already encoded at `howl-render/src/text/raster/special.zig:178-184`.
- `howl-render/src/text/raster/special_legacy_computing.zig`: owns the current `.legacy_computing` raster families and the legacy-only helper surface already encoded by `howl-render/src/text/raster/special.zig:186-239,261-866,1255-1367`.
- `howl-render/src/text/special_glyphs.zig`: remains the support-table owner.
- `howl-render/src/text/symbol_map.zig`, `resolver.zig`, `lane.zig`, `grouping.zig`, `glyph_raster.zig`, and `scene.zig`: remain caller, route, and proof seams.

Decision:

- `howl-render/src/text/raster/special.zig` remains the first true cut.
- No ranked fallback seam preempts it.
- The first cut is undercurl extraction.
- The generated-special compression must follow current-source owner boundaries already present in `special.zig`:
  - box
  - powerline
  - block plus braille
  - legacy-computing

## Sprint Scratchpad

Active artifacts:

- Sprint: `/home/home/personal/projects/howl/sprints/2026-06-13-raster-special-ownership-compression-sprint.md`
- Loop: `/home/home/personal/projects/howl/loops/raster-special-ownership-compression-live-loop.txt`
- Research artifact: `/home/home/personal/projects/howl/research/2026-06-13-raster-special-ownership-compression-plan.md`

Accountable sprint problem:

- The next loudest render concentration after scene compression is `howl-render/src/text/raster/special.zig`: `sprints/2026-06-13-raster-special-ownership-compression-sprint.md:17-23`
- Planning is authorized; implementation is not: `sprints/2026-06-13-raster-special-ownership-compression-sprint.md:47-52`, `sprints/current.txt:39-49`

Accepted planning direction for the next execution package:

- Start with `special.zig`, not the ranked fallback seams.
- Preserve the render-facing `rasterizer.zig` seam.
- Compress by current raster family owners, not by random helper shattering.
- Keep support tables, caller seams, host files, and ABI truth out of the first cut.

Ordered execution queue:

1. Extract undercurl owner.
2. Create generated-special root and extract box owner.
3. Extract powerline owner.
4. Extract the current block-plus-braille dispatch owner.
5. Extract the current legacy-computing owner.

Non-goal scratch:

- No ABI or header churn.
- No host/display/runtime redesign.
- No benchmark theater.
- No route-table redesign unless a slice stop condition explicitly trips.

## Ordered Slice Plan

### Slice 1: Extract undercurl owner

Edit set:

- `howl-render/src/text/raster/special.zig`
- `howl-render/src/text/raster/undercurl.zig`

Required shape:

- Move `requestForUndercurl` and `rasterizeUndercurlAlpha` from `howl-render/src/text/raster/special.zig:5-47` into `howl-render/src/text/raster/undercurl.zig`.
- Move the undercurl-only helper `addAlpha` from `howl-render/src/text/raster/special.zig:1811-1817` into `howl-render/src/text/raster/undercurl.zig`.
- Keep `howl-render/src/text/raster/special.zig` as the curated re-export root so `howl-render/src/text/raster/rasterizer.zig:133-136` stays unchanged.
- Do not move any generated-special entrypoint or helper.

Neighbor seam status:

- `howl-render/src/text/symbol_map.zig`: excluded from edits and excluded from proof for this slice.
- `howl-render/src/text/resolver.zig`: excluded from edits and excluded from proof for this slice.
- `howl-render/src/text/lane.zig`: excluded from edits and excluded from proof for this slice.
- `howl-render/src/text/shape/grouping.zig`: excluded from edits and excluded from proof for this slice.
- `howl-render/src/text/ft_hb/glyph_raster.zig`: excluded from edits and excluded from proof for this slice.
- `howl-render/src/text/scene.zig`: excluded from edits and included as proof root only.

Required proof roots:

- `howl-render/src/text/raster/special_test.zig:10-19`
- `howl-render/src/text/scene.zig:768-790`
- `howl-render/src/test_unit.zig:1-12`
- `howl-render/build.zig:53-101`
- `build.zig:34-38,61-76`

Non-goals:

- No generated-special family move.
- No route-table change.
- No ABI/header change.
- No host/display edit.

Stop conditions:

- Stop if the extraction requires changing `howl-render/src/text/raster/rasterizer.zig:133-136`.
- Stop if the extraction requires changing any field or enum in `contract.SpriteRasterRequest`.

### Slice 2: Create generated-special root and extract box owner

Edit set:

- `howl-render/src/text/raster/special.zig`
- `howl-render/src/text/raster/generated_special.zig`
- `howl-render/src/text/raster/special_box.zig`

Required shape:

- Move generated-special public entrypoints and family dispatch from `howl-render/src/text/raster/special.zig:49-127` into `howl-render/src/text/raster/generated_special.zig`.
- Move the box owner surface from `howl-render/src/text/raster/special.zig:129-156,872-1246` into `howl-render/src/text/raster/special_box.zig`.
- `special_box.zig` owns exactly:
  - `rasterizeGeneratedBoxAlpha`
  - `RoundedCorner`
  - `BoxLineStyle`
  - `BoxLines`
  - `lineSpec`
  - `lineSpecLight`
  - `lineSpecHeavy`
  - `lineSpecDouble`
  - `lineSpecHalf`
  - `rasterizeBoxLines`
  - `drawBoxVerticalArm`
  - `drawBoxHorizontalArm`
  - `fillRectRange`
  - `BoxLineAxis`
  - `rasterizeDashedBoxLine`
  - `rasterizeRoundedCorner`
  - `snapRoundedCornerConnections`
  - `rasterizeCrossLine`
  - `centeredRange`
  - `smoothStep`
- `generated_special.zig` keeps the generated-special dispatcher and only helpers still needed outside the box owner.

Neighbor seam status:

- `howl-render/src/text/symbol_map.zig`: excluded from edits and included as proof root.
- `howl-render/src/text/resolver.zig`: excluded from edits and included as proof root.
- `howl-render/src/text/lane.zig`: excluded from edits and included as proof root.
- `howl-render/src/text/shape/grouping.zig`: excluded from edits and included as proof root.
- `howl-render/src/text/ft_hb/glyph_raster.zig`: excluded from edits and included as proof root.
- `howl-render/src/text/scene.zig`: excluded from edits and excluded from proof for this slice.

Required proof roots:

- `howl-render/src/text/raster/special_test.zig:21-58,399-617`
- `howl-render/src/text/ft_hb/glyph_raster.zig:239-261`
- `howl-render/src/text/symbol_map.zig:22-24,44-51`
- `howl-render/src/text/resolver.zig:294-342`
- `howl-render/src/text/lane.zig:449-465`
- `howl-render/src/text/shape/grouping.zig:259-275`
- `howl-render/src/test_unit.zig:1-12`
- `howl-render/build.zig:53-101`
- `build.zig:34-38,61-76`

Non-goals:

- No powerline extraction.
- No block or braille extraction.
- No legacy-computing extraction.
- No support-table edit.

Stop conditions:

- Stop if box extraction requires changing route classification in `symbol_map.zig`, `resolver.zig`, `lane.zig`, or `grouping.zig`.
- Stop if box extraction requires changing provider dispatch in `howl-render/src/text/ft_hb/glyph_raster.zig:156-163`.

### Slice 3: Extract powerline owner

Edit set:

- `howl-render/src/text/raster/generated_special.zig`
- `howl-render/src/text/raster/special_powerline.zig`

Required shape:

- Move the powerline owner surface from `howl-render/src/text/raster/special.zig:158-176,253-259,1442-1687` into `howl-render/src/text/raster/special_powerline.zig`.
- `special_powerline.zig` owns exactly:
  - `rasterizeGeneratedPowerlineAlpha`
  - `rasterizeGeneratedPowerlineTriangleAlpha`
  - `rasterizePowerlineTriangle`
  - `rasterizePowerlineHalfDiagonal`
  - `rasterizePowerlineD`
  - `CubicBezier`
  - `rasterizePowerlineFilledD`
  - `TriangleCoverageCtx`
  - `FilledDCoverageCtx`
  - `supersampledTriangleCoverage`
  - `supersampledFilledDCoverage`
  - `triangleContains`
  - `filledDContains`
  - `rasterizePowerlineRoundedD`
  - `findBezierControlX`
  - `findBezierTForX`
  - `drawCubicStrokeAlpha`
  - `bezierX`
  - `bezierY`
  - `bezierValue`
  - `PowerlineCorner`
  - `rasterizePowerlineCornerTriangle`
- `generated_special.zig` keeps the exact helper surface still required by the remaining owners and by the extracted powerline owner:
  - `PointF`
  - `lineY`
  - `drawLineAlpha`
  - `Range`
  - `eighthPartitionRange`
  - `supersampledCoverage`
  - `fillRectAlpha`
  - `saturatingSubU16`
  - `pixelRowOffset`
  - `pixelOffset`
  - `pixelCount`
  - `count32`

Neighbor seam status:

- `howl-render/src/text/symbol_map.zig`: excluded from edits and included as proof root.
- `howl-render/src/text/resolver.zig`: excluded from edits and included as proof root.
- `howl-render/src/text/lane.zig`: excluded from edits and included as proof root.
- `howl-render/src/text/shape/grouping.zig`: excluded from edits and included as proof root.
- `howl-render/src/text/ft_hb/glyph_raster.zig`: excluded from edits and included as proof root.
- `howl-render/src/text/scene.zig`: excluded from edits and excluded from proof for this slice.

Required proof roots:

- `howl-render/src/text/raster/special_test.zig:173-214,618-626`
- `howl-render/src/text/ft_hb/glyph_raster.zig:239-261`
- `howl-render/src/text/symbol_map.zig:26-29,44-51`
- `howl-render/src/text/resolver.zig:294-342`
- `howl-render/src/text/lane.zig:449-465`
- `howl-render/src/text/shape/grouping.zig:277-298`
- `howl-render/src/test_unit.zig:1-12`
- `howl-render/build.zig:53-101`
- `build.zig:34-38,61-76`

Non-goals:

- No box move.
- No block or braille move.
- No legacy-computing move.
- No sprite-key semantic change.

Stop conditions:

- Stop if the move changes powerline spacer absorption proved by `howl-render/src/text/shape/grouping.zig:277-298`.
- Stop if the move changes route classification proved by `howl-render/src/text/symbol_map.zig:26-29,44-51` and `howl-render/src/text/resolver.zig:294-342`.

### Slice 4: Extract the current block-plus-braille dispatch owner

Edit set:

- `howl-render/src/text/raster/generated_special.zig`
- `howl-render/src/text/raster/special_block_braille.zig`

Required shape:

- Move the current block-plus-braille dispatch owner from `howl-render/src/text/raster/special.zig:178-184,1369-1439,1688-1795` into `howl-render/src/text/raster/special_block_braille.zig`.
- `special_block_braille.zig` owns exactly:
  - `rasterizeGeneratedBlockAlpha`
  - `rasterizeBlockElementAlpha`
  - `fillRows`
  - `fillCols`
  - `BlockQuadrant`
  - `fillQuadrants`
  - `fillQuadrant`
  - `ShadeDensity`
  - `fillShade`
  - `rasterizeBrailleAlpha`
  - `drawBrailleDotAlpha`
  - `BrailleLayout`
  - `brailleLayout`
  - `BrailleDotCoverageCtx`
  - `supersampledBrailleDotCoverage`
  - `brailleDotContains`
- `generated_special.zig` keeps the exact shared helpers already used outside this owner:
  - `Range`
  - `eighthPartitionRange`
  - `PointF`
  - `lineY`
  - `drawLineAlpha`
  - `supersampledCoverage`
  - `fillRectAlpha`
  - `saturatingSubU16`
  - `pixelRowOffset`
  - `pixelOffset`
  - `pixelCount`
  - `count32`

Neighbor seam status:

- `howl-render/src/text/symbol_map.zig`: excluded from edits and included as proof root.
- `howl-render/src/text/resolver.zig`: excluded from edits and included as proof root.
- `howl-render/src/text/lane.zig`: excluded from edits and included as proof root.
- `howl-render/src/text/shape/grouping.zig`: excluded from edits and included as proof root.
- `howl-render/src/text/ft_hb/glyph_raster.zig`: excluded from edits and included as proof root.
- `howl-render/src/text/scene.zig`: excluded from edits and excluded from proof for this slice.

Required proof roots:

- `howl-render/src/text/raster/special_test.zig:113-171,216-301`
- `howl-render/src/text/ft_hb/glyph_raster.zig:239-261`
- `howl-render/src/text/symbol_map.zig:22-24,44-51`
- `howl-render/src/text/resolver.zig:294-342`
- `howl-render/src/text/lane.zig:449-465`
- `howl-render/src/text/shape/grouping.zig:259-275`
- `howl-render/src/test_unit.zig:1-12`
- `howl-render/build.zig:53-101`
- `build.zig:34-38,61-76`

Non-goals:

- No sextant move.
- No octant move.
- No branch move.
- No support-table edit.

Stop conditions:

- Stop if the move requires changing the current route split between `.block`, `.braille`, and `.legacy_computing` proved by `howl-render/src/text/symbol_map.zig:6-10`.
- Stop if the move requires changing provider fallback routing proved by `howl-render/src/text/ft_hb/glyph_raster.zig:156-163,239-261`.

### Slice 5: Extract the current legacy-computing owner

Edit set:

- `howl-render/src/text/raster/generated_special.zig`
- `howl-render/src/text/raster/special_legacy_computing.zig`

Required shape:

- Move the current legacy-computing raster owner from `howl-render/src/text/raster/special.zig:186-239,261-866,1255-1367` into `howl-render/src/text/raster/special_legacy_computing.zig`.
- `special_legacy_computing.zig` owns exactly:
  - `rasterizeGeneratedEightBarAlpha`
  - `rasterizeGeneratedSextantAlpha`
  - `rasterizeEightBarAlpha`
  - `rasterizeGeneratedOctantAlpha`
  - `generatedOctantPattern`
  - `rasterizeGeneratedSmoothMosaicAlpha`
  - `smoothMosaicPoints`
  - `drawSmoothMosaic`
  - `SpriteEdge`
  - `AlphaCorner`
  - `rasterizeGeneratedHalfTriangleAlpha`
  - `drawHalfTriangle`
  - `rasterizeGeneratedEightBarCompositeAlpha`
  - `SpriteShade`
  - `rasterizeGeneratedShadeCornerCrossAlpha`
  - `drawCheckerShade`
  - `drawCrossShade`
  - `applyCornerMask`
  - `rasterizeGeneratedMidLineAlpha`
  - `drawMidLine`
  - `rasterizeGeneratedBranchAlpha`
  - `BranchNode`
  - `BranchEdge`
  - `drawBranchNode`
  - `drawBranchLine`
  - `drawBranchArc`
  - `fillTriangleAlpha`
  - `pointInTriangle`
  - `triangleEdge`
  - `drawSegmentStrokeAlpha`
  - `distanceToSegment`
  - `fillCircleAlpha`
  - `drawCircleArcAlpha`
  - `rasterizeOctantAlpha`
  - `fillOctantSegment`
  - `fourthRange`
  - `octantMask`
  - `rasterizeSextantAlpha`
  - `drawSextantRow`
  - `fillSextantCell`
- `generated_special.zig` keeps only the helpers that are still truly shared after slices 1 through 4:
  - public generated-special entrypoints and family dispatch from `howl-render/src/text/raster/special.zig:49-127`
  - `PointF`
  - `lineY`
  - `drawLineAlpha`
  - `Range`
  - `eighthPartitionRange`
  - `supersampledCoverage`
  - `fillRectAlpha`
  - `saturatingSubU16`
  - `pixelRowOffset`
  - `pixelOffset`
  - `pixelCount`
  - `count32`
- Legacy-only helpers from `howl-render/src/text/raster/special.zig:317-318,784-866` must not remain in `generated_special.zig`.

Neighbor seam status:

- `howl-render/src/text/symbol_map.zig`: excluded from edits and included as proof root.
- `howl-render/src/text/resolver.zig`: excluded from edits and included as proof root.
- `howl-render/src/text/lane.zig`: excluded from edits and included as proof root.
- `howl-render/src/text/shape/grouping.zig`: excluded from edits and included as proof root.
- `howl-render/src/text/ft_hb/glyph_raster.zig`: excluded from edits and included as proof root.
- `howl-render/src/text/scene.zig`: excluded from edits and excluded from proof for this slice.

Required proof roots:

- `howl-render/src/text/raster/special_test.zig:60-111,302-310,312-378,628-679`
- `howl-render/src/text/ft_hb/glyph_raster.zig:239-261`
- `howl-render/src/text/symbol_map.zig:31-41,44-51`
- `howl-render/src/text/resolver.zig:294-342`
- `howl-render/src/text/lane.zig:449-465`
- `howl-render/src/text/shape/grouping.zig:259-275`
- `howl-render/src/test_unit.zig:1-12`
- `howl-render/build.zig:53-101`
- `build.zig:34-38,61-76`

Non-goals:

- No route-table expansion.
- No ABI/header change.
- No host/display edit.
- No render-wide redesign.

Stop conditions:

- Stop if the move requires changing the `.legacy_computing` route proved by `howl-render/src/text/symbol_map.zig:10,31-49` and `howl-render/src/text/resolver.zig:307-327,330-341`.
- Stop if the move requires retaining any legacy-only helper from `howl-render/src/text/raster/special.zig:317-318,784-866` inside `generated_special.zig`.
- Stop if the move requires introducing any new generic helper bucket outside `generated_special.zig`.

## Required Assertions

- Preserve `width_px > 0` and `height_px > 0` assertions on the undercurl request path at `howl-render/src/text/raster/special.zig:5-7`.
- Preserve generated raster buffer-bound assertion before generated-special public raster entrypoints at `howl-render/src/text/raster/special.zig:53-55`.
- Preserve support-table gate before family dispatch at `howl-render/src/text/raster/special.zig:55-63`.
- Preserve existing `unreachable` use only behind the family table and codepoint-specific switches already proved by tests at `howl-render/src/text/raster/special.zig:110-127,129-176,178-251,253-259,320-331,348-380,385-427,606-739`.
- Preserve the shared pixel/index helper bounds at `howl-render/src/text/raster/special.zig:1797-1835`.

## Required Tests

Global accountable test surface for every slice:

- Package-local run surface is `howl-render` `zig build test:unit`, wired through `howl-render/build.zig:87-101`.
- Workspace aggregate availability remains `zig build test:unit`, wired through `build.zig:61-76`.
- Every slice must keep `howl-render/src/test_unit.zig:1-12` as the curated unit root.

Slice 1 accountable test surface:

- `special_test.zig`: `test "undercurl raster request generates alpha mask"`
- `scene.zig`: `test "scene emits undercurl sprite for curly underline"`
- Required run expectation: package-local `howl-render` unit step covering those two named tests.

Slice 2 accountable test surface:

- `special_test.zig`:
  - `test "generated special support table matches rasterizer dispatch"`
  - `test "generated special current family table proves shared or fallback owner"`
  - `test "generated special raster draws box diagonal lines"`
  - `test "generated special raster draws double box lines"`
  - `test "generated special raster draws dashed box lines"`
  - `test "generated box connectors stop at stroke edges"`
  - `test "generated tee connectors use centered light joins"`
  - `test "generated special raster draws rounded box corners"`
  - `test "generated rounded corners align with straight box arms"`
  - `test "generated rounded corners honor box drawing thickness"`
  - `test "generated special raster draws box crossing diagonals"`
- `glyph_raster.zig`: `test "provider box fallback draws routed generated special families"`
- `symbol_map.zig`: `test "builtin route classifies box drawing"`, `test "builtin route classifies generated special sprite families"`
- `resolver.zig`: `test "resolver separates shared and fallback special sprite routes before font resolution"`
- `lane.zig`: `test "lane marks shared and fallback special sprite routes as complex"`
- `grouping.zig`: `test "grouping classifies emoji icon and sprite route groups"`
- Required run expectation: package-local `howl-render` unit step covering the named box and route proofs.

Slice 3 accountable test surface:

- `special_test.zig`:
  - `test "generated special raster draws powerline triangle"`
  - `test "generated special raster draws powerline separator"`
  - `test "generated special raster draws cubic powerline D"`
  - `test "generated special raster draws stroked powerline D"`
  - `test "generated special raster draws powerline diagonal aliases"`
- `glyph_raster.zig`: `test "provider box fallback draws routed generated special families"`
- `symbol_map.zig`: `test "builtin route leaves kitty symbol-map powerline glyphs alone"`, `test "builtin route classifies generated special sprite families"`
- `resolver.zig`: `test "resolver separates shared and fallback special sprite routes before font resolution"`
- `lane.zig`: `test "lane marks shared and fallback special sprite routes as complex"`
- `grouping.zig`:
  - `test "powerline sprite route absorbs adjacent spacer cells"`
  - `test "powerline spacer absorption lets concat drop covered space group"`
- Required run expectation: package-local `howl-render` unit step covering the named powerline geometry and spacer-absorption proofs.

Slice 4 accountable test surface:

- `special_test.zig`:
  - `test "generated special raster draws braille dots"`
  - `test "generated braille preserves gaps at small cell sizes"`
  - `test "generated braille uses antialiased dots when possible"`
  - `test "generated special raster draws eighth block"`
  - `test "generated special raster draws top half block"`
  - `test "generated special raster draws quadrant block"`
  - `test "generated special raster distributes eighth blocks"`
  - `test "generated special raster draws left seven eighths block"`
- `glyph_raster.zig`: `test "provider box fallback draws routed generated special families"`
- `symbol_map.zig`: `test "builtin route classifies box drawing"`, `test "builtin route classifies generated special sprite families"`
- `resolver.zig`: `test "resolver separates shared and fallback special sprite routes before font resolution"`
- `lane.zig`: `test "lane marks shared and fallback special sprite routes as complex"`
- `grouping.zig`: `test "grouping classifies emoji icon and sprite route groups"`
- Required run expectation: package-local `howl-render` unit step covering the named block/braille geometry proofs plus provider/resolver/lane parity.

Slice 5 accountable test surface:

- `special_test.zig`:
  - `test "generated special current family table proves shared or fallback owner"`
  - `test "generated special raster uses uniform shade intensity"`
  - `test "generated special raster draws sextants"`
  - `test "generated special raster draws upper-range sextant mapping"`
  - `test "generated special raster draws octants"`
  - `test "generated special raster draws terminal octant aliases"`
  - `test "generated shade preserves fallback intensity levels"`
  - `test "generated inverted shade preserves extension intensities"`
  - `test "generated branch pure arc preserves quadrant geometry"`
  - `test "generated branch line plus arc preserves both components"`
  - `test "generated branch nodes preserve filled and unfilled variants"`
- `glyph_raster.zig`: `test "provider box fallback draws routed generated special families"`
- `symbol_map.zig`:
  - `test "builtin route classifies octant symbols"`
  - `test "builtin route classifies kitty eight bars"`
  - `test "builtin route classifies kitty legacy computing tail"`
  - `test "builtin route classifies generated special sprite families"`
- `resolver.zig`: `test "resolver separates shared and fallback special sprite routes before font resolution"`
- `lane.zig`: `test "lane marks shared and fallback special sprite routes as complex"`
- `grouping.zig`: `test "grouping classifies emoji icon and sprite route groups"`
- Required run expectation: package-local `howl-render` unit step covering the named legacy-computing geometry proofs plus route/provider parity.

## Risks

- Support-table drift between `special_glyphs.zig`, route classification, and generated-special dispatch.
- Fake helper extraction that moves small math helpers without reducing owner burden.
- Silent route regression if sprite-route classification or provider fallback changes while raster code moves.
- Shared-helper drift if the retained helper surface in `generated_special.zig` is widened beyond the exact helper list named above.

## Proof Gaps

- Alacritty does not provide a direct source shape for Howl’s private-use branch families.
- Alacritty does not provide an undercurl owner in Howl’s exact ABI shape.
- Current tests prove route parity and many geometry cases, but several legacy-computing families still rely on the current family-table proof root at `howl-render/src/text/raster/special_test.zig:60-111` rather than a family-specific geometry test.

## Readiness Judgment

- `accept-ready`

Why:

- The sources-read list now places `reference-index.md` before external references, records Alacritty before TigerBeetle per `reference-index.md`, and lists current Howl source only after those reference reads.
- The artifact now includes the required `compact anchor map`, `sprint scratchpad`, `required assertions`, `required tests`, and `readiness judgment` sections demanded by `loop/researcher.md:60-74`.
- Slice 5 no longer leaves legacy-only helpers ambiguously retained in `generated_special.zig`; the retained helper surface is now limited to helpers that remain genuinely shared after the earlier family extractions.
- Every slice names an exact edit set, exact retained-owner rule, exact accountable test surface, exact non-goals, and exact stop conditions.
- No reference override is needed from current evidence.
