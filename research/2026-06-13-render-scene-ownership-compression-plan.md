# Render Scene Ownership Compression Plan

Date: 2026-06-13.

Status: accepted planning package; all three planned slices are accepted in nested render history and final root closure is pending.

Role owner: researcher.

Orchestrator session id: `orch-2026-06-13-render-scene-01`.

Researcher session id: `research-2026-06-13-render-scene-01`.

Reviewer session id: `review-2026-06-13-render-scene-01`.

Planning commit-hash receipt: root `2fde3dd`.

Question:

- What is the highest-value source-backed owner compression sprint for the current render complexity bill, starting with `howl-render/src/text/scene.zig`, and what exact sequential execution slices does that require without inventing new architecture or moving ABI truth?

## 1. Sources Read In Order

1. `loops/render-scene-ownership-compression-live-loop.txt`
2. `research/2026-06-13-render-scene-ownership-compression-plan.md`
3. `sprints/2026-06-13-render-scene-ownership-compression-sprint.md`
4. `howl-render/src/text/scene.zig`
5. `howl-render/src/text/direct_scene.zig`
6. `howl-render/src/text/direct_normal.zig`
7. `howl-render/src/text/surface_preparer.zig`
8. `howl-render/src/text/shape/cluster.zig`
9. `howl-render/src/vt_publication/text_input.zig`
10. `howl-render/src/vt_publication/cursor.zig`
11. `howl-render/src/render_session.zig`
12. `howl-render/src/text/scene_contract.zig`
13. `howl-render/build.zig`

## 2. Exact Files And Line References

### Current Howl source

- `howl-render/src/text/scene.zig:35-45,107-179,181-186,303-345,355-425,578-626,690-1130,1222-1227,1229-1749,1751-1784`
- `howl-render/src/text/direct_scene.zig:5-19,22-76`
- `howl-render/src/text/direct_normal.zig:110-150,249-270,407-413`
- `howl-render/src/text/surface_preparer.zig:295-304,336-352,378-425,662-681,805-839,946-1030,1330-1347,1410-1467`
- `howl-render/src/text/shape/cluster.zig:273-289,329-337,491-517,529-540,577-579,638-676,1039-1142`
- `howl-render/src/vt_publication/text_input.zig:13-15,154-179,197-235,348-378`
- `howl-render/src/vt_publication/cursor.zig:24-49`
- `howl-render/src/render_session.zig:240-292`
- `howl-render/src/text/scene_contract.zig:193-215,271-296`
- `howl-render/build.zig:53-101,155-170`

### References carried by the earlier accepted portions of this plan

- `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:24-29,40-88,112-184`
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:49-75,111-172,182-197`
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/rects.rs:19-33,54-119,158-227`
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/atlas.rs:32-71,118-145,247-295`
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs:42-79,191-275`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:90-149,161-176,273-361,374-387`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:94-101,195-225,277-307`

## 3. Current-Code Facts

### `scene.zig` burden

- `howl-render/src/text/scene.zig` is still the first owner-compression seam. It mixes scene lifetime/storage, damage normalization, clear/background/cursor/decoration rect synthesis, curly underline sprite/raster synthesis, atlas reservation, raster request enqueueing, and owner-local tests in one file (`scene.zig:35-45,107-179,181-186,303-345,578-626,690-1130,1229-1749`).
- `direct_scene.zig` already proves the file is over-compressed. It is only an adapter today: it normalizes damage through `scene.normalizeDamage` and forwards backgrounds, clears, cursor draws, and decorations back into scene-owned unmanaged helpers (`direct_scene.zig:11-19,35-76`).
- `cluster.zig` still duplicates the damage-validity owner through `DamageFilter.init`, `cleanRowSkip`, and `includeSpan` instead of consuming the same owner as `scene.zig` (`cluster.zig:281-289,329-337,504-517,577-579,638-676` versus `scene.zig:578-626`).

### Outward damage boundary still points at `scene.zig`

- The current plan cannot leave the public damage boundary to coder invention because render-side callers still name scene-owned damage types directly.
- `scene.BuildOptions` still binds `.damage` to `scene.DamageInput` (`scene.zig:42-45`).
- `direct_normal.prepare` still accepts `scene.DamageInput`, and `damageInput` reconstructs `scene.DamageInput` from `direct_scene.Damage` (`direct_normal.zig:110-117,407-413`).
- `surface_preparer.selectComplexCells` still accepts `scene.DamageInput`, and `mergePreparedScene` still materializes `scene.NormalizedDamage` before calling scene-owned clear/cursor helpers (`surface_preparer.zig:295-304,378-397,662-681`).
- `vt_publication/text_input.zig` still constructs `scene.DamageInput` directly for publication mapping (`text_input.zig:197-208`).
- Therefore Slice 1 must make the alias-vs-caller-edit decision explicit: no scene-owned alias may remain for the damage owner, and these callers must be edited to name the new damage owner directly.

### Underline ownership carve-out is already visible in current source

- Straight and double underlines are rect draws in both paths:
  - unmanaged: `scene.zig:1040-1046`
  - managed: `scene.zig:1082-1085,1090-1098`
- Dotted and dashed underlines are also rect draws in both paths through stepped decoration segments:
  - unmanaged: `scene.zig:1024-1038`
  - managed: `scene.zig:1078-1080,1100-1129`
- Curly underline is not a rect draw path:
  - rect-count path returns zero for `.curly`: `scene.zig:417-425`
  - sprite capacity for curly is counted separately: `scene.zig:381-390`
  - managed underline dispatch routes `.curly` to `appendUndercurl`: `scene.zig:1082-1087`
  - `appendUndercurl` owns raster request generation, sprite key hashing, atlas reservation, and sprite append: `scene.zig:303-339`
- This makes the ownership carve-out exact:
  - rect owner: background, clear, cursor, strikethrough, straight underline, double underline, dotted underline, dashed underline
  - scene sprite/raster owner: curly underline / undercurl only

### Proof roots

- Unit proof root stays curated through `howl-render/src/test_unit.zig` via imports under `render_session.zig`, `surface_preparer.zig`, and `scene.zig` (`build.zig:53-69`).
- ABI proof root stays curated through `howl-render/src/test_abi.zig` (`build.zig:70-101`).
- The build filter mechanism passes exact test names through `b.args`; execution slices can require exact full names instead of broad substrings (`build.zig:155-170`).

## 4. Reference Facts That Govern The Decision

### Alacritty

- Alacritty keeps renderable-content preparation outside the text renderer. `display/content.rs` owns cursor derivation, selection/search effects, and iteration over non-empty cells, while the text renderer consumes renderable content rather than deciding it.
- Alacritty keeps text glyph rendering, atlas ownership, and glyph caching in separate owners.
- Alacritty keeps underline/strikeout/rect geometry in a dedicated rect owner instead of burying it inside the text renderer.
- That pressure still points at `scene.zig` first: split rect/fill geometry away from sprite/raster assembly; do not move host/runtime or ABI seams first.

### TigerBeetle

- TigerBeetle requires explicit control flow, exact owners, paired assertions, and no fake helper shattering.
- A valid split must move durable nouns with real call sites and tests, not extract convenience helpers.
- That pressure still rejects keeping damage truth half in `scene.zig` and half in `cluster.zig`, and rejects a rect owner that also owns curly sprite rasterization.

## 5. Compact Anchor Map

- `A1` Alacritty renderable-content owner: `display/content.rs:24-29,40-88,112-184`
- `A2` Alacritty text renderer owner: `renderer/text/mod.rs:49-75,111-172`
- `A3` Alacritty rect owner: `renderer/rects.rs:19-33,54-119,158-227`
- `A4` Alacritty atlas owner: `renderer/text/atlas.rs:32-71,118-145,247-295`
- `A5` Alacritty glyph-cache owner: `renderer/text/glyph_cache.rs:42-79,191-275`
- `T1` TigerBeetle explicit control flow and assertions: `TIGER_STYLE.md:90-149`
- `T2` TigerBeetle push `if`s up and `for`s down: `TIGER_STYLE.md:161-176`
- `T3` TigerBeetle naming/owner truth: `TIGER_STYLE.md:273-361`
- `H1` Howl scene root burden: `scene.zig:35-45,107-179,181-186,303-345,578-626,690-1130`
- `H2` Howl duplicated damage owner pressure: `scene.zig:578-626`; `cluster.zig:638-676`
- `H3` Howl outward damage-type pressure: `direct_normal.zig:110-117,407-413`; `surface_preparer.zig:295-304,378-397,662-681`; `text_input.zig:197-208`
- `H4` Howl rect owner pressure: `scene.zig:690-1130`
- `H5` Howl curly sprite/raster carve-out: `scene.zig:303-339,381-390,417-425,1082-1087`
- `H6` Howl orchestration seam: `surface_preparer.zig:336-425`; `render_session.zig:240-292`

## 6. Owner Roles And Proposed Shape

### Decision

- `scene.zig` remains the first true cut.
- None of the ranked fallback seams preempt it.

### Why `scene.zig` goes first

- It is still the file with the highest combined pressure: file size, duplicated damage truth, rect/sprite mixing, and adapter pressure from `direct_scene.zig`.
- The current reviewer rejection was not a reason to move away from `scene.zig`; it was a reason to make the slice contracts exact enough that coders cannot invent the damage boundary or underline split.

### Required public-boundary decision for Slice 1

- Slice 1 must choose caller edits, not aliases.
- Required rule: `scene.zig` may not retain `pub const DamageInput`, `pub const NormalizedDamage`, or `pub fn normalizeDamage` as outward aliases to the new owner.
- Why:
  - the current direct callers still bind to scene-owned damage types (`direct_normal.zig:110-117,407-413`; `surface_preparer.zig:295-304,378-397,662-681`; `text_input.zig:197-208`)
  - leaving aliases in `scene.zig` would keep the outward damage boundary scene-owned and would not complete the owner move
- `scene.BuildOptions` may stay scene-owned as the scene root API, but its `.damage` field must bind to the new damage owner type, not to a scene-owned alias.

### Proposed shape

- `howl-render/src/text/scene.zig`
  - Curated scene root and complex sprite/raster assembly owner only.
  - Keeps `BuildOptions`, `OwnedTextScene`, `BorrowedTextScene`, `RetainedScratch`, top-level build entrypoints, `SceneAssembly`, sprite-group placement, atlas reservation, raster request enqueueing, sprite color policy, and curly underline / undercurl sprite ownership.
- `howl-render/src/text/scene_damage.zig`
  - Owns `DamageInput`, `NormalizedDamage`, normalization, row/span validity, dirty-row spans, span inclusion, and paired assertions.
  - Consumed directly by `scene.zig`, `direct_scene.zig`, `direct_normal.zig`, `surface_preparer.zig`, `shape/cluster.zig`, and `vt_publication/text_input.zig`.
- `howl-render/src/text/scene_rects.zig`
  - Owns clear/background/cursor/rect-decoration synthesis and geometry only.
  - Owns straight/double/dotted/dashed underline and strikethrough generation.
  - Does not own curly underline rasterization, atlas cache interaction, or sprite requests.

## 7. Sprint Scratchpad Summary

- Goal: compress `scene.zig` into true owners without changing the C ABI, proof roots, or host/runtime boundaries.
- First cut: move damage/span truth out of `scene.zig` and delete scene-owned outward damage aliases.
- Second cut: move rect/fill/cursor/non-curly-decoration ownership out of `scene.zig` and leave undercurl sprite ownership in `scene.zig`.
- Third cut: finish `scene.zig` as the sprite/raster scene root only.
- Keep tests owner-local and preserve the curated `test:unit` and `test:abi` roots.

## 8. Explicit Ordered Slice Plan

### Slice 1: Extract scene damage/span ownership and move callers to it

- Allowed files:
  - `howl-render/src/text/scene.zig`
  - `howl-render/src/text/scene_damage.zig`
  - `howl-render/src/text/direct_scene.zig`
  - `howl-render/src/text/direct_normal.zig`
  - `howl-render/src/text/surface_preparer.zig`
  - `howl-render/src/text/shape/cluster.zig`
  - `howl-render/src/vt_publication/text_input.zig`
- Required shape:
  - Create `scene_damage.zig` as the only owner of `DamageInput`, `NormalizedDamage`, `normalizeDamage`, row-length assertions, dirty-row-span derivation, and span-inclusion logic now split between `scene.zig` and `cluster.zig`.
  - `cluster.zig` must stop owning `DamageFilter`; the duplicated validity and inclusion logic must disappear from `cluster.zig`.
  - `scene.zig` must consume `scene_damage.zig` and must not retain outward aliases for `DamageInput`, `NormalizedDamage`, or `normalizeDamage`.
  - `direct_scene.zig`, `direct_normal.zig`, `surface_preparer.zig`, and `vt_publication/text_input.zig` must import and name `scene_damage` directly anywhere they currently name scene-owned damage types.
  - `scene.BuildOptions` stays scene-owned, but its `.damage` field must bind to the new damage owner type.
- Required tests:
  - `scene damage filters clean rows`
  - `partial damage filters clean clusters before shaping`
  - `sparse cells keep only damaged base cells`
  - `renderable content publication mapping threads partial damage`
  - `renderable content maps only dirty ranges for partial damage`
  - `text preparation partial damage clears use empty default background truth`
- Non-goals:
  - no rect/fill extraction yet
  - no cursor owner move
  - no sprite/raster logic changes
  - no emitter, host, or ABI changes
- Stop conditions:
  - stop if any scene-owned outward alias for the moved damage owner survives
  - stop if `cluster.zig` still carries duplicate damage-validity or span-inclusion logic
  - stop if the move requires a new test root
  - stop if ABI/header-facing truth changes
- Session ids / receipts:
  - orchestrator `orch-2026-06-13-render-scene-01`
  - researcher `research-2026-06-13-render-scene-01`
  - reviewer `review-2026-06-13-render-scene-01`
  - coder session id required before execution
  - commit hash required at slice acceptance

### Slice 2: Extract scene rect/fill ownership with explicit undercurl carve-out

- Allowed files:
  - `howl-render/src/text/scene.zig`
  - `howl-render/src/text/scene_damage.zig`
  - `howl-render/src/text/scene_rects.zig`
  - `howl-render/src/text/direct_scene.zig`
  - `howl-render/src/text/surface_preparer.zig`
- Required shape:
  - Create `scene_rects.zig` as the owner of background, clear, cursor, and rect-decoration synthesis now in `scene.zig:690-1130`.
  - `scene_rects.zig` must own straight, double, dotted, and dashed underlines plus strikethrough.
  - `scene_rects.zig` must not own curly underline / undercurl, any `SpriteRasterRequest`, any atlas-cache interaction, or any sprite append path.
  - `scene.zig` must keep `appendUndercurl`, `countCurlyUnderlineSprites`, and the `.curly` sprite/raster path.
  - `direct_scene.zig` must call the rect owner directly for backgrounds, clears, cursor draws, and non-curly decoration draws.
  - `surface_preparer.buildClearDraws` and `surface_preparer.buildCursorDraws` must call the rect owner directly.
- Required tests:
  - `scene emits background draws from non-continuation cells`
  - `scene merges adjacent same-color background cells on one row`
  - `scene keeps distinct background spans across color changes`
  - `scene emits explicit clears for transparent default backgrounds on partial damage`
  - `scene cursor draws emit shared cursor geometry`
  - `scene build options include cursor draws`
  - `scene emits shared-geometry decoration draws from cells`
  - `scene merges contiguous straight underline spans`
  - `scene double underline count and geometry stay aligned`
  - `scene dotted underline geometry stays aligned with counted capacity`
  - `scene dashed underline geometry stays aligned with counted capacity`
  - `scene merges contiguous strikethrough spans`
  - `text preparation options produce scene cursor draws`
  - `text preparation partial damage clears use empty default background truth`
  - `text preparation publication clears use empty default background truth`
- Non-goals:
  - no curly underline / undercurl move
  - no atlas ownership move
  - no emitter-side merge cleanup
  - no benchmark edits
- Stop conditions:
  - stop if `scene_rects.zig` becomes a bucket for both rect logic and sprite/raster logic
  - stop if curly underline leaves `scene.zig`
  - stop if draw ordering by `first_cell` is no longer explicit and asserted
  - stop if proof is weakened to make the move land
- Session ids / receipts:
  - orchestrator `orch-2026-06-13-render-scene-01`
  - researcher `research-2026-06-13-render-scene-01`
  - reviewer `review-2026-06-13-render-scene-01`
  - coder session id required before execution
  - commit hash required at slice acceptance

### Slice 3: Finish `scene.zig` as the sprite/raster scene root only

- Allowed files:
  - `howl-render/src/text/scene.zig`
  - `howl-render/src/text/scene_damage.zig`
  - `howl-render/src/text/scene_rects.zig`
  - `howl-render/src/text/surface_preparer.zig`
- Required shape:
  - `scene.zig` must finish as the scene root plus sprite/raster assembly owner only.
  - Keep `BuildOptions`, `OwnedTextScene`, `BorrowedTextScene`, `RetainedScratch`, build entrypoints, `SceneAssembly`, group sprite append, icon span extension, atlas reservation, raster request enqueueing, sprite color policy, and curly underline / undercurl ownership in `scene.zig`.
  - Remove any remaining damage normalization or rect synthesis ownership from `scene.zig`; it must consume `scene_damage.zig` and `scene_rects.zig`.
  - `surface_preparer.buildComplexScene` must still build the complex borrowed scene through the scene root and must still record lane proof from produced sprite draws.
- Required tests:
  - `scene builds ordered sprite draws from groups`
  - `scene emits undercurl sprite for curly underline`
  - `scene carries group placement offsets into sprite draw`
  - `scene extends wide icon groups into available blank cells`
  - `scene positions sprite draws by grid columns`
  - `scene reuses atlas slots for repeated sprite keys`
  - `scene does not request raster for cache hit`
  - `borrowed scene reuses retained draw list storage`
  - `text scene applies kitty dim opacity at render-time for sprite draws`
  - `text preparation scene is grid positioned`
  - `text preparation rerasterizes pending atlas entries across prepares`
  - `text preparation marks curly underline cells complex before shaping`
  - `text preparation prepares publication cells through shared full pipeline surface`
  - final acceptance sweep: `zig build test:unit`
- Non-goals:
  - no emitter cleanup
  - no render-session orchestration redesign
  - no host/runtime changes
  - no ABI/header edits
- Stop conditions:
  - stop if `scene.zig` still owns rect synthesis or duplicated damage truth after the slice
  - stop if curly underline ownership leaves the sprite/raster owner
  - stop if lane-report proof no longer lines up with the sprite-producing owner
- Session ids / receipts:
  - orchestrator `orch-2026-06-13-render-scene-01`
  - researcher `research-2026-06-13-render-scene-01`
  - reviewer `review-2026-06-13-render-scene-01`
  - coder session id required before execution
  - commit hash required at slice acceptance

## 9. Required Assertions

- Preserve and pair the positive-space damage assertions:
  - dirty-row arrays must match row count before partial-damage normalization (`scene.zig:578-590`)
  - normalized damage arrays must stay length-aligned when consumed (`scene.zig:1222-1227`)
- Preserve explicit cursor draw-count assertions on both retained and unmanaged paths (`scene.zig:347-353,796-808`).
- Preserve width/height non-zero assertions before rasterized sprite append (`scene.zig:272-288`).
- Preserve sorted-by-`first_cell` assertions at merged scene boundaries (`surface_preparer.zig:633-690`).
- Slice 1 must keep paired assertions in the new damage owner so normalization and all consumers still assert the same invariants.
- Slice 2 must preserve decoration-merge invariants for contiguous rect draws (`scene.zig:290-301,447-455,1052-1063`).

## 10. Required Tests

- Damage owner proof must stay exact:
  - `scene damage filters clean rows`
  - `partial damage filters clean clusters before shaping`
  - `sparse cells keep only damaged base cells`
  - `renderable content publication mapping threads partial damage`
  - `renderable content maps only dirty ranges for partial damage`
- Rect owner proof must stay exact:
  - `scene emits background draws from non-continuation cells`
  - `scene merges adjacent same-color background cells on one row`
  - `scene keeps distinct background spans across color changes`
  - `scene emits explicit clears for transparent default backgrounds on partial damage`
  - `scene cursor draws emit shared cursor geometry`
  - `scene build options include cursor draws`
  - `scene emits shared-geometry decoration draws from cells`
  - `scene merges contiguous straight underline spans`
  - `scene double underline count and geometry stay aligned`
  - `scene dotted underline geometry stays aligned with counted capacity`
  - `scene dashed underline geometry stays aligned with counted capacity`
  - `scene merges contiguous strikethrough spans`
  - `text preparation options produce scene cursor draws`
  - `text preparation partial damage clears use empty default background truth`
  - `text preparation publication clears use empty default background truth`
- Sprite/raster scene proof must stay exact:
  - `scene builds ordered sprite draws from groups`
  - `scene emits undercurl sprite for curly underline`
  - `scene carries group placement offsets into sprite draw`
  - `scene extends wide icon groups into available blank cells`
  - `scene positions sprite draws by grid columns`
  - `scene reuses atlas slots for repeated sprite keys`
  - `scene does not request raster for cache hit`
  - `borrowed scene reuses retained draw list storage`
  - `text scene applies kitty dim opacity at render-time for sprite draws`
  - `text preparation scene is grid positioned`
  - `text preparation rerasterizes pending atlas entries across prepares`
  - `text preparation marks curly underline cells complex before shaping`
  - `text preparation prepares publication cells through shared full pipeline surface`
- Curated proof roots must stay unchanged:
  - `howl-render/src/test_unit.zig`
  - `howl-render/src/test_abi.zig`

## 11. Risks

- Boundary-fake-progress risk: keeping scene-owned aliases for damage types would make Slice 1 look complete while leaving the outward boundary unchanged.
- Curly-carve-out risk: a coder could wrongly move undercurl into the rect owner even though current source proves it is a sprite/raster path.
- Test-filter risk: broad substring filters could accidentally pass the wrong proof; exact full test names are required because the build wiring accepts exact args as filters.
- Merge-order risk: rect-owner extraction still feeds `surface_preparer.mergePreparedScene`; `first_cell` ordering and merge assertions must stay intact.

## 12. Proof Gaps

- The exact new file names remain a Howl invention; the acceptable invention stays limited to the smallest split that matches Alacritty’s content-vs-rect-vs-glyph separation and TigerBeetle owner truth.
- I did not run builds or tests in this repair pass.
- No reference conflict was found that requires a user override receipt.

## 13. Readiness Judgment

- `accept-ready`
- Why:
  - the rejected gaps are now closed with exact current-source file boundaries
  - Slice 1 now makes the alias-vs-caller-edit decision explicit and source-backed
  - Slice 2 now states the exact underline carve-out with exact source proof
  - all listed test obligations are now exact unique full test names, not broad substrings

## 14. Concise Loop Note Text

```text
2. Role: researcher
- Session id: `research-2026-06-13-render-scene-01`
- Hello: hi
- Intended task: repair the rejected render scene ownership plan so the slices are executable without coder invention.
- How one task went: tightened Slice 1 to require caller edits instead of scene-owned damage aliases, proved the exact curly-vs-rect underline split from current source, and replaced broad test filters with exact full proof names including the cluster partial-damage checks.
- Next handoff or blocker: reviewer should re-gate the repaired three-slice package; no implementation is authorized until reviewer acceptance and orchestrator seeding of an execution slice.
```

## 15. Replacement Markdown For This File

This file already contains the exact replacement markdown.
