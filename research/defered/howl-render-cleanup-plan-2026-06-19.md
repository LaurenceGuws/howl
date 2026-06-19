Historical authority at defer time: this was the active render cleanup research package before the user switched the live sprint to host terminal surface layout redesign on 2026-06-19.
Why superseded or deferred: render cleanup remains retained context, but the current active problem is killing `deriveHostLayout(...)` and replacing host terminal surface geometry with reference-backed ownership.
Must not be used for: current worker scope, current reviewer gates, or active user approval questions unless explicitly re-promoted.

# Howl Render Cleanup Plan

Status: user approval ready for the first non-text clutter extraction from `text/`: move cursor-trail animation out of `text/` to the shallow `cursor_trail.zig` owner. The prior FT/HB-first approval request is superseded by user correction; FT/HB/text stack stays as-is for now.

Orchestrator session id: `orch-2026-06-18-render-cleanup-accountability-01`.
Researcher session id: `research-2026-06-18-render-cleanup-non-text-clutter-10`.
Prior researcher ids: `research-2026-06-18-render-cleanup-inventory-01`, `research-2026-06-18-render-cleanup-correction-02`, `research-2026-06-18-render-cleanup-gate-repair-03`, `research-2026-06-18-render-cleanup-next-slice-04`, `research-2026-06-18-render-cleanup-next-slice-05`, `research-2026-06-18-render-cleanup-next-slice-06`.
Last accepted reviewer id: `review-2026-06-18-render-cleanup-cursor-trail-limit-03`.
Reviewer id for rejected whole-text package: `review-2026-06-18-render-cleanup-text-ownership-01`.
Reviewer id for repaired package: `review-2026-06-18-render-cleanup-text-ownership-02` accepted FT/HB-only readiness, now superseded by user correction before implementation.
Commit-hash receipt status: accepted executable slices closed as `howl-render` `864ea8b Use C cursor cadence ABI directly`, root `f84e1c8 Track cursor cadence ABI cleanup`; `howl-render` `7af878b Delete dead render shapes`, root `6d0e393`; `howl-render` `d7f93b7 Delete cursor trail config bucket`, root `398da7f`; `howl-render` `664efd2 Use ABI cursor trail limit`, root `05da287`. This planning update has no dedicated planning commit yet.

## Scope Rule

- The cleanup sprint is indefinite until deterministic evidence says no cleanup remains in `howl-render`.
- `style.py` is quantitative pressure only. It is not sufficient proof because it misses forbidden terms such as `contract`, `session`, `owner`, `context`, and `state`.
- Every executable slice must combine style pressure, forbidden tokens, dead-code/reachability, and duplicate-shape evidence where applicable.
- Passing tests are never sufficient when stale names, stale paths, dead shapes, compatibility mirrors, duplicated limits, or fake owners remain.
- No compatibility shims, aliases, bridges, fallback names, or fake partial cleanup are allowed.

## Sources Read

Mandatory live accountability and project law, in order:

- `loop/flow.md`
- `loop/orcestrator.md`
- `loop/researcher.md`
- `loop/reviewer.md`
- `loop/coder.md`
- `loop/researcher.md` again as active role contract
- `sprints/current.txt`
- `loops/howl-render-cleanup-loop.txt`
- `research/howl-render-cleanup-plan.md` before this update
- `AGENTS.md`
- `reference-index.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`

Current source/evidence inspected in this pass:

- `style.py`
- `howl-render/include/howl_render.h`
- `howl-render/src/c/text_session.zig`
- `howl-render/src/cursor_presentation.zig`
- `howl-render/src/render_session.zig`
- `howl-render/src/text/cursor_presentation.zig`
- `howl-render/src/text/contract.zig`
- `howl-render/src/text/scene_rects.zig`
- `howl-render/src/text/scene.zig`
- `howl-render/src/text/surface_preparer.zig`
- `howl-render/src/text/direct_normal.zig`
- `howl-render/src/text/ft_hb/support.zig`
- Package-root searches across `howl-render/src/**/*.zig` and `howl-render/include/**/*.h`
- `howl-render/src/text/ft_hb/provider.zig`
- `howl-render/src/text/ft_hb/support_test.zig`
- `howl-render/src/text/provider.zig`
- `howl-render/src/text/session.zig`
- Current workspace status before edits: only untracked `temp.md` and `temp.txt`; untouched.
- `howl-render/src/text/**/*.zig` full path inventory for whole-text ownership surgery.
- Alacritty text-renderer reference anchors: `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs`, `atlas.rs`, `glyph_cache.rs`, and renderer root `renderer/mod.rs`.
- Current Howl text-owner files inspected for classification: `color.zig`, `effects.zig`, `metrics.zig`, `cell_input.zig`, `cursor_presentation.zig`, `cursor_trail.zig`, `scene_contract.zig`, `scene.zig`, `scene_rects.zig`, `direct_scene.zig`, `direct_normal.zig`, `surface_preparer.zig`, `prepare_counters.zig`, `scene_damage.zig`, `lane.zig`, `resolve.zig`, `resolver.zig`, `provider.zig`, `session.zig`, `paths.zig`, `symbol.zig`, `symbol_map.zig`, `special_glyphs.zig`, `shape/*`, `raster/*`, and `ft_hb/*`.
- Rejection repaired in this pass: `loops/howl-render-cleanup-loop.txt:73` / reviewer `review-2026-06-18-render-cleanup-text-ownership-01`.
- Exact FT/HB test-root consequence: `howl-render/src/test_unit.zig:13` imports `text/ft_hb/support_test.zig` and must be allowed in the FT/HB move slice.
- User correction repaired in this pass: the prior FT/HB approval question is wrong focus; leave the text stack as-is for now and prepare the next approval-ready slice around non-text clutter in `howl-render/src/text`.
- Current cursor-trail extraction proof: `howl-render/src/text/cursor_trail.zig`, `howl-render/src/cursor_presentation.zig`, and `howl-render/src/test_unit.zig`.

## Reference Anchor Map

- TigerStyle assertions/proof: `TIGER_STYLE.md:104-140` requires assertions for arguments, return values, invariants, positive space, and negative space.
- TigerStyle naming/directness: `TIGER_STYLE.md:273-276` requires exact nouns and verbs; `TIGER_STYLE.md:337-347` rejects overloaded names; `TIGER_STYLE.md:416-429` requires narrow scope and low dimensionality.
- TigerStyle duplicate state: `TIGER_STYLE.md:372-387` rejects duplicate variables/aliases that can diverge.
- TigerBeetle limits: `ARCHITECTURE.md:189-222` treats explicit bounds as a forcing function.
- Howl owner law: `AGENTS.md:178-196` rejects fake owners, bucket structs, and vague ownership.
- Howl ABI law: `AGENTS.md:25-37`, `AGENTS.md:159-166`, and `AGENTS.md:168-176` make the C ABI the product and limit hosts to C contracts.
- Alacritty text renderer pressure keeps text rendering centered around glyph cache, atlas, glyph loader/API, and text draw preparation: `renderer/text/mod.rs:11-21` defines `atlas`, `glyph_cache`, `GlyphCache`, and `LoaderApi`; `renderer/text/mod.rs:49-69` makes `TextRenderer.draw_cells` consume renderable cells through a glyph cache; `renderer/text/mod.rs:183-196` makes `LoaderApi` load rasterized glyphs into atlases.
- Alacritty separates rectangle rendering from text rendering: `renderer/mod.rs:23-31` imports `rects::{RectRenderer, RenderRect}` separately from `mod text`; `renderer/mod.rs:89-92` stores `text_renderer` and `rect_renderer` as separate fields; `renderer/mod.rs:242-255` has `draw_rects` as a separate renderer path; `renderer/rects.rs:19-28` owns `RenderRect`, and `renderer/rects.rs:37-178` owns line/rect geometry.
- No closer Alacritty folder anchor was found for Howl-only retained text-scene assembly, damage-normalized scene scratch, or embeddable C-ABI text-preparation surfaces. Proposed Howl scene/prepare folder moves therefore require explicit proof per symbol before approval; they are not approval-ready in this artifact.
- Howl render law keeps host-facing integration on C ABI contracts; any file move must preserve C ABI names, headers, and host behavior.

## Current Evidence Baseline

Whole-package style command:

```sh
python3 style.py --by-file --format json --sort prod howl-render
```

Current top style rows by `prod` after accepted cursor-trail limit authority cleanup:

| path | prod | proof | lines | asserts | usizes | anytypes | casts | funcs | long_funcs | structs_top_level | bucket_named_structs | bucket_struct_lines |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `(sum)` | 13386 | 7133 | 23991 | 314 | 172 | 66 | 2141 | 1114 | 4 | 203 | 0 | 0 |
| `howl-render/src/render_session.zig` | 831 | 128 | 1082 | 17 | 8 | 1 | 67 | 72 | 0 | 10 | 0 | 0 |
| `howl-render/src/text/scene_rects.zig` | 771 | 70 | 934 | 8 | 26 | 27 | 296 | 63 | 0 | 2 | 0 | 0 |
| `howl-render/src/text/raster/special_legacy_computing.zig` | 725 | 0 | 776 | 2 | 0 | 0 | 124 | 37 | 2 | 0 | 0 | 0 |
| `howl-render/src/surface/emitter.zig` | 717 | 0 | 784 | 79 | 0 | 0 | 18 | 15 | 1 | 2 | 0 | 0 |
| `howl-render/src/surface/realizer.zig` | 713 | 0 | 788 | 1 | 3 | 4 | 46 | 49 | 0 | 2 | 0 | 0 |
| `howl-render/src/text/ft_hb/support.zig` | 628 | 0 | 708 | 1 | 1 | 1 | 62 | 57 | 0 | 5 | 0 | 0 |
| `howl-render/src/text/shape/cluster.zig` | 594 | 276 | 987 | 9 | 2 | 1 | 86 | 53 | 0 | 8 | 0 | 0 |
| `howl-render/src/text/scene.zig` | 587 | 552 | 1232 | 5 | 19 | 2 | 153 | 36 | 0 | 10 | 0 | 0 |
| `howl-render/src/text/surface_preparer.zig` | 566 | 368 | 1017 | 10 | 2 | 1 | 80 | 43 | 0 | 6 | 0 | 0 |
| `howl-render/src/surface/resource_store.zig` | 555 | 109 | 707 | 35 | 0 | 0 | 29 | 22 | 0 | 3 | 0 | 0 |
| `howl-render/src/text/direct_normal.zig` | 477 | 203 | 770 | 19 | 26 | 1 | 66 | 33 | 0 | 6 | 0 | 0 |

Candidate-file metric command:

```sh
python3 style.py --by-file --format json --sort path howl-render/src/render_session.zig howl-render/src/cursor_presentation.zig howl-render/src/text/contract.zig howl-render/src/text/scene_rects.zig howl-render/src/text/scene.zig howl-render/src/text/surface_preparer.zig howl-render/src/text/direct_normal.zig howl-render/src/text/ft_hb/support.zig
```

Current candidate metrics:

| path | prod | proof | lines | asserts | usizes | anytypes | casts | funcs | long_funcs | structs_top_level | bucket_named_structs | bucket_struct_lines |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `(sum)` | 4212 | 1407 | 6242 | 62 | 82 | 33 | 737 | 312 | 0 | 68 | 0 | 0 |
| `howl-render/src/render_session.zig` | 831 | 128 | 1082 | 17 | 8 | 1 | 67 | 72 | 0 | 10 | 0 | 0 |
| `howl-render/src/submitted_surface.zig` | 58 | 49 | 126 | 2 | 0 | 0 | 3 | 8 | 0 | 2 | 0 | 0 |
| `howl-render/src/text/contract.zig` | 64 | 6 | 77 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `howl-render/src/text/direct_normal.zig` | 477 | 203 | 770 | 19 | 26 | 1 | 66 | 33 | 0 | 6 | 0 | 0 |
| `howl-render/src/text/ft_hb/support.zig` | 628 | 0 | 708 | 1 | 1 | 1 | 62 | 57 | 0 | 5 | 0 | 0 |
| `howl-render/src/text/scene.zig` | 587 | 552 | 1232 | 5 | 19 | 2 | 153 | 36 | 0 | 10 | 0 | 0 |
| `howl-render/src/text/scene_contract.zig` | 230 | 31 | 296 | 0 | 0 | 0 | 10 | 0 | 0 | 27 | 0 | 0 |
| `howl-render/src/text/scene_rects.zig` | 771 | 70 | 934 | 8 | 26 | 27 | 296 | 63 | 0 | 2 | 0 | 0 |
| `howl-render/src/text/surface_preparer.zig` | 566 | 368 | 1017 | 10 | 2 | 1 | 80 | 43 | 0 | 6 | 0 | 0 |

Forbidden-token content command:

```sh
rg -n -i --glob '*.zig' --glob '*.h' --glob '!**/.zig-cache/**' --glob '!**/zig-out/**' --glob '!**/vendor/**' '(contract|session|owner|pipeline|context|state|options|config|info|data|result|manager|controller|types|utils|helper|support)' howl-render/src howl-render/include
```

Current package-root token totals from this pass:

| token | content files | token hits | path files |
| --- | ---: | ---: | ---: |
| `contract` | 51 | 1518 | 3 |
| `session` | 33 | 1042 | 5 |
| `owner` | 22 | 393 | 0 |
| `pipeline` | 0 | 0 | 0 |
| `context` | 3 | 107 | 0 |
| `state` | 21 | 512 | 1 |
| `options` | 8 | 170 | 0 |
| `config` | 18 | 277 | 0 |
| `info` | 9 | 63 | 0 |
| `data` | 3 | 26 | 0 |
| `result` | 18 | 163 | 0 |
| `manager` | 0 | 0 | 0 |
| `controller` | 0 | 0 | 0 |
| `types` | 0 | 0 | 0 |
| `utils` | 0 | 0 | 0 |
| `helper` | 1 | 1 | 0 |
| `support` | 20 | 309 | 3 |

Current deterministic findings:

- `style.py` reports zero package-wide `bucket_named_structs` and zero `bucket_struct_lines`; the cursor-trail limit authority cleanup is accepted and no cursor-trail `16` duplicate remains in `render_session.zig` or `text/cursor_presentation.zig`.
- The prior strongest metric/token overlap was `howl-render/src/text/ft_hb/support.zig`, but the user explicitly corrected the next objective away from FT/HB/text-stack cleanup. FT/HB remains a retained later target, not the next approval question.
- Current source proves the smallest non-text clutter extraction is `howl-render/src/text/cursor_trail.zig`: it owns cursor animation state and geometry easing, not text shaping, glyph rasterization, glyph cache, text scene assembly, or FT/HB font work.
- `text/cursor_trail.zig:5` owns `Target`; `text/cursor_trail.zig:13` owns `CursorTrail`; cursor-trail mutation is `snapToTarget` at `:25`, `setTarget` at `:36`, `update` at `:43`, `updateCorners` at `:57`, `updateOpacity` at `:93`, and `updateNeedsRender` at `:98`; target derivation is `targetFromCursor` at `:111`; owner-local proofs start at `:136`.
- Current import proof is exact and small: `cursor_presentation.zig:5` imports `text/cursor_trail.zig`; `cursor_presentation.zig:55`, `:145`, `:148`, and `:204` use `text_cursor_trail` types/functions; `test_unit.zig:10` imports `text/cursor_trail.zig` for owner-local unit proofs.
- `text/cursor_trail.zig` depends on text metrics/contract only for typed input shapes: `text/cursor_trail.zig:2-3` import `metrics.zig` and `contract.zig`; `:111` accepts `contract.CellMetrics`; `:117` calls `metrics.cursorGeometry`; `:197-202` uses `contract.CursorShape` and `contract.CellExtent` in tests. Moving the owner sideways requires only import-path repair, not symbol or behavior changes.
- `render_session.zig`, `text/scene_rects.zig`, `text/scene.zig`, `text/surface_preparer.zig`, `text/direct_normal.zig`, and `text/ft_hb/support.zig` remain metric-dominant cleanup targets, but they are not the smallest approval-ready non-text clutter extraction.

Reachability command template for the user-needed cursor-trail extraction decision:

```sh
rg -n 'text/cursor_trail\.zig|text_cursor_trail' howl-render/src howl-render/include
rg -n '\bCursorTrail\b|\bTarget\b|targetFromCursor' howl-render/src/text/cursor_trail.zig howl-render/src/cursor_presentation.zig howl-render/src/test_unit.zig
rg --files howl-render/src howl-render/include | rg '(^|/)cursor_trail\.zig$'
```

Duplicate-shape evidence still active after accepted cursor-trail limit authority cleanup:

- The support/provider owner inversion still duplicates and obscures FT/HB provider ownership, but it is explicitly not the next slice after the user's correction.
- Remaining mutex wrappers in `submitted_surface.zig`, `text/ft_hb/support.zig`, and `render_session.zig` remain live after the user-needed cursor-trail decision. `render_session.zig` has extra locked-state assertions and should not be mechanically collapsed with pass-through wrappers without owner proof.
- Scene contract aggregation, metric-dominant render/session files, special raster long functions, and C test-support cleanup remain live later targets.

## Ordered Cleanup Plan

1. Accepted: ABI cursor cadence mirror deletion closure. Product receipt: `howl-render` `864ea8b`; root receipt: `f84e1c8`.
2. Accepted: dead/self-test-only render shape deletion. Product receipt: `howl-render` `7af878b`; root receipt: `6d0e393`.
3. Accepted: cursor trail decay bucket deletion. Product receipt: `howl-render` `d7f93b7`; root receipt: `398da7f`.
4. Accepted: cursor trail limit authority cleanup. Product receipt: `howl-render` `664efd2`; root receipt: `05da287`.
5. User-needed next decision: cursor-trail extraction from `text/` to root `cursor_trail.zig`; the previous FT/HB support/provider approval request is superseded by user correction and stays later planning only.
6. Metric/token dominant render-session slice: split or rename only source-proved lifecycle pieces in `render_session.zig`, with before/after style row and forbidden-token row. No broad new runtime or manager layer.
7. Text scene contract cleanup: split `text/scene_contract.zig`, reduce `contract` imports in `scene_rects.zig`, `scene.zig`, `lane.zig`, `shape/cluster.zig`, and `surface_preparer.zig`, and preserve only curated re-export roots where exact.
8. Long-function/cast-heavy renderer cleanup: target `text/raster/special_legacy_computing.zig`, `surface/emitter.zig`, `surface/realizer.zig`, and `text/scene_rects.zig` using metric deltas plus owner-local tests. Long functions in product files must trend to zero.
9. Duplicate mutex wrapper cleanup: delete pass-through mutex wrappers in `submitted_surface.zig` and `text/ft_hb/support.zig` after separate owner proof, while preserving `render_session.zig` locked-state assertions unless separately proved removable.
10. Test-support cleanup: shrink `src/c/test_support.zig` aliases and move proof helpers to owner-local tests where still needed.
11. Benchmark cleanup: rename benchmark-only bucket nouns in `benchmark_main.zig` after product/ABI cleanup, without hiding benchmark proof inside unit/ABI roots.

The sprint remains live after each slice. The orchestrator/reviewer must rerun the four evidence lanes and choose the next strongest deterministic target from remaining metrics/tokens/reachability/duplicates.

## Whole Text Ownership Surgery Package

Status: superseded for next execution by the user's correction. This inventory remains useful proof, but the approval-ready next slice is no longer FT/HB. Broader text moves are still not user-approval-ready until exact symbol/move/import consequences are supplied per slice.

Why the broader package is needed:

- Current `howl-render/src/text` mixes contracts, scene data, direct preparation, font session state, FT/HB provider ownership, raster cache/atlas ownership, generated special-glyph rasterizers, lane telemetry, and cursor presentation under one folder.
- Alacritty's text renderer pressure supports a narrow text-renderer owner around glyph cache, atlas, glyph loading, and draw preparation. It does not justify a single `text/contract.zig` root exporting every color, metrics, cursor, scene, raster, and shaping shape.
- TigerBeetle/Howl owner law rejects `contract`, `session`, and `support` when they hide real owners. Current `text/contract.zig`, `text/session.zig`, and `text/ft_hb/support.zig` are the visible path-level wounds.
- The first executable sub-slice must still be small enough to review with deterministic searches and tests; broad approval does not permit one giant implementation diff.

Exact current file classification with line-level source proof:

| current path | current source proof | readiness |
| --- | --- | --- |
| `text/cell_input.zig` | `CellInput` owns host cell input data at `text/cell_input.zig:5`; local bounds proof at `text/cell_input.zig:31`. | Keep; not a move target now. |
| `text/color.zig` | `Rgba8`, `SemanticColorKind`, and `SemanticColor` live at `text/color.zig:3`, `:10`, `:16`; default proof at `:21`. | Keep. |
| `text/contract.zig` | Imports owner modules at `text/contract.zig:3-8` and re-exports their symbols across `:10-70`; test calls it a root at `:72`. | Not approval-ready for deletion until exact replacement imports are listed. |
| `text/cursor_presentation.zig` | Cursor ABI constants and shapes live at `text/cursor_presentation.zig:1-2`, `:4`, `:10`, `:21`, `:28`, `:41`, `:67`. | Keep. |
| `text/cursor_trail.zig` | Cursor trail target/state/update owner lives at `text/cursor_trail.zig:5`, `:13`, `:111`; owner-local proofs start at `:136`; only product importer is root cursor presentation at `cursor_presentation.zig:5`, with unit root at `test_unit.zig:10`. | Approval-ready to move sideways to `howl-render/src/cursor_trail.zig`. |
| `text/direct_normal.zig` | Direct-normal preparation imports scene/rect/damage/raster owners at `text/direct_normal.zig:1-15`, owns `Product`, `Policy`, `Source`, `Scratch`, `Driver`, and `prepare` at `:23`, `:37`, `:42`, `:51`, `:104`, `:112`; tests start at `:526`. | Not approval-ready for move/split; exact symbol consequences still needed. |
| `text/direct_scene.zig` | Direct scene append helpers own `Damage`, `borrowScene`, and append functions at `text/direct_scene.zig:7`, `:24`, `:37`, `:49`, `:60`, `:68`, `:77`. | Not approval-ready for move; no closer reference folder anchor than Howl scene helper proof. |
| `text/effects.zig` | Text effect enums live at `text/effects.zig:3`, `:11`, `:18`, `:24`; stability proof at `:32`. | Keep. |
| `text/ft_hb/c_api.zig` | FT/HB C imports and aliases live at `text/ft_hb/c_api.zig:3`, `:10-12`; C wrappers at `:14`, `:18`, `:22`. | Keep. |
| `text/ft_hb/cache.zig` | FT/HB cache keys/caches live at `text/ft_hb/cache.zig:5`, `:10`, `:18`, `:42`, `:75`, `:189`; hash/proof at `:228`, `:237`, `:263`, `:296`. | Keep. |
| `text/ft_hb/glyph_raster.zig` | Imports current fake provider owner at `text/ft_hb/glyph_raster.zig:7`; typed uses `provider_mod.FtHbSupport` at `:14`, `:30`, `:119`, `:249`, `:254`; tests at `:199`, `:207`, `:274`. | Later FT/HB planning only; user corrected this away from next execution. |
| `text/ft_hb/loaded_faces.zig` | Loaded face aliases and lifecycle owner live at `text/ft_hb/loaded_faces.zig:6-13`, `:15`, `:21`. | Keep. |
| `text/ft_hb/provider.zig` | File currently owns only `FtHbSource` source adapter at `text/ft_hb/provider.zig:8`; callback conversion at `:16` and `:26`. | Later FT/HB planning only; user corrected this away from next execution. |
| `text/ft_hb/support.zig` | Heavy FT/HB provider state is `FtHbSupport` at `text/ft_hb/support.zig:38`; capacity at `:92`; provider operations at `:128`, `:138`, `:172`, `:304`, `:315`, `:325`, `:356`, `:362`, `:400`, `:411`, `:448`, `:457`; test hooks at `:673`. | Later FT/HB planning only; user corrected this away from next execution. |
| `text/ft_hb/support_test.zig` | Imports fake support owner at `text/ft_hb/support_test.zig:6`; tests provider behavior at `:20`, `:44`, `:64`; uses `support.FtHbSupport` at `:45`, `:65`. | Later FT/HB planning only; user corrected this away from next execution. |
| `text/lane.zig` | Lane classification and telemetry owner lives at `text/lane.zig:5`, `:10`, `:42`, `:50`, `:84`, `:89`, `:96`; classifiers at `:208-250`; proofs start at `:373`. | Keep; possible later telemetry split only with proof. |
| `text/metrics.zig` | Font/face/decoration/cursor/cell/grid metrics live at `text/metrics.zig:3`, `:13`, `:21`, `:28`, `:34`, `:41`; cursor geometry at `:46`; proofs at `:59`, `:85`. | Keep. |
| `text/paths.zig` | Font path capacity and storage live at `text/paths.zig:3`, `:4`, `:13`; count conversions at `:107`, `:112`; proofs at `:116`, `:129`, `:158`. | Not approval-ready for rename until import consequences are enumerated. |
| `text/prepare_counters.zig` | Preparation counters single owner at `text/prepare_counters.zig:1`. | Keep until prepare move is exact. |
| `text/provider.zig` | Generic `TextProvider` callback surface lives at `text/provider.zig:8`, `:13`, `:15`, `:24`, `:38`, `:42`, `:46`; dispatch proof at `:75`. | Keep; `provider` is real here, unlike FT/HB source adapter. |
| `text/resolve.zig` | Resolve operation, result, counters, observability, and op live at `text/resolve.zig:4`, `:19`, `:26`, `:32`, `:37`, `:42`, `:55`, `:60`, `:62`; dispatch proof at `:71`. | Not approval-ready for rename. |
| `text/resolver.zig` | Cluster-to-face resolver imports resolve/session at `text/resolver.zig:3-4`; owns request/result/scratch and resolve functions at `:7`, `:13`, `:19`, `:36`, `:41`, `:56`, `:77`, `:115`, `:169`; proofs start at `:272`. | Not approval-ready for rename. |
| `text/scene.zig` | Owns retained/borrowed scene memory and scratch at `text/scene.zig:51`, `:77`, `:92`; build functions at `:134`, `:148`, `:166`; draw color helpers at `:566`, `:570`; proofs start at `:644`. | Not approval-ready for move to `text/scene/owned.zig`; no closer reference folder anchor yet. |
| `text/scene_contract.zig` | Mixed input/run/draw/raster/missing shapes span `text/scene_contract.zig:5-70`, `:79-125`, `:137-206`, `:217-262`; proofs at `:264`, `:271`. | Not approval-ready for split until exact destination per symbol is listed. |
| `text/scene_damage.zig` | Damage input/normalized/range shapes and functions live at `text/scene_damage.zig:4`, `:11`, `:18`, `:55`, `:70`, `:76`, `:83`, `:88`, `:105`, `:112`, `:121`. | Keep until scene move is exact. |
| `text/scene_rects.zig` | Rectangle/cursor/decor geometry owner imports at `text/scene_rects.zig:1-4`; owns `RectDecorationLayout` at `:50`; background/clear/cursor/decoration counts/appends at `:68`, `:72`, `:84`, `:119`, `:131`, `:255`, `:334`, `:345`, `:462`, `:477`; proofs start at `:855`. | Not approval-ready for move/rename; Alacritty separates rects, but Howl destination needs exact import consequences. |
| `text/session.zig` | Font session shapes live at `text/session.zig:6`, `:15`, `:33`, `:42`, `:47`, `:56`; proofs start at `:128`. | Not approval-ready for rename to `font_set`/`font_faces`; exact import and symbol consequences still needed. |
| `text/shape/cluster.zig` | Cell text cache/renderable/cluster scratch owner lives at `text/shape/cluster.zig:10`, `:28`, `:47`, `:58`, `:69`, `:81`, `:92`, `:98`; builders/selectors at `:153-452`; proofs start at `:674`. | Keep. |
| `text/shape/grouping.zig` | Glyph group owner imports resolver/run/key/map at `text/shape/grouping.zig:3-6`; owns groups/policy/functions at `:8`, `:19`, `:24`, `:97`, `:123`; proofs start at `:218`. | Keep. |
| `text/shape/run.zig` | Shaping request/result/op/run scratch owner lives at `text/shape/run.zig:5`, `:10`, `:14`, `:23`, `:39`, `:50`, `:64`, `:74`; shaping functions at `:96`, `:100`, `:111`, `:134`, `:158`, `:173`; proofs start at `:242`. | Keep. |
| `text/special_glyphs.zig` | Special codepoint predicates live at `text/special_glyphs.zig:1`, `:6`, `:11`; proofs at `:35`, `:41`. | Keep. |
| `text/symbol.zig` | Symbol glyph predicate owner at `text/symbol.zig:2`. | Keep pending symbol slice. |
| `text/symbol_map.zig` | Built-in route and icon classification live at `text/symbol_map.zig:4`, `:14`; proofs at `:22-53`. | Keep. |
| `text/raster/atlas.zig` | Atlas cache owner lives at `text/raster/atlas.zig:5`, `:18`, `:20`, `:26`, `:31`; proofs at `:113-166`. | Keep; Alacritty has `text/atlas` but Howl raster folder is acceptable until glyph-cache slice. |
| `text/raster/fallback.zig` | ASCII/placeholder raster function at `text/raster/fallback.zig:1`. | Keep. |
| `text/raster/generated_special.zig` | Generated special dispatcher/helpers live at `text/raster/generated_special.zig:9`, `:17`, `:84`, `:86`, `:109`, `:111`, `:126`, `:155`, `:181`. | Keep; long-function cleanup later. |
| `text/raster/key.zig` | Sprite/glyph key hashing functions live at `text/raster/key.zig:4`, `:18`, `:30`; proofs at `:41`, `:48`, `:55`, `:61`. | Keep. |
| `text/raster/operation.zig` | Raster operation request/output/op owner at `text/raster/operation.zig:4`, `:13`, `:28`, `:30`; proof at `:39`. | Keep. |
| `text/raster/rasterizer.zig` | Raster request/output/bounds/plan/rasterizer owner at `text/raster/rasterizer.zig:5`, `:11`, `:31`, `:68`, `:84`; functions/re-exports at `:93`, `:112`, `:133-136`, `:161`, `:176`, `:184`; proofs start at `:219`. | Keep. |
| `text/raster/special.zig` | Curated raster special root re-exports undercurl/generated functions at `text/raster/special.zig:1-8`. | Keep; not a product umbrella root outside raster. |
| `text/raster/special_block_braille.zig` | Braille/block raster function at `text/raster/special_block_braille.zig:3`. | Keep. |
| `text/raster/special_box.zig` | Box raster and line geometry functions live at `text/raster/special_box.zig:4`, `:33-42`, `:179`, `:235`, `:250`, `:265`, `:284`, `:304`, `:351`, `:374`, `:403`, `:408`. | Keep; long-function cleanup later. |
| `text/raster/special_legacy_computing.zig` | Legacy computing raster family functions live at `text/raster/special_legacy_computing.zig:7`, `:15`, `:23`, `:33`, `:41`, `:55`, `:93`, `:115`, `:144`, `:179`, `:403`, `:541`, `:759`; long helper cluster continues through `:770`. | Keep; long-function cleanup later. |
| `text/raster/special_powerline.zig` | Powerline raster functions at `text/raster/special_powerline.zig:6`, `:26`. | Keep. |
| `text/raster/special_test.zig` | Raster proof root imports at `text/raster/special_test.zig:3-6`; tests span `:11`, `:22`, `:61`, `:114-682`. | Keep. |
| `text/raster/undercurl.zig` | Undercurl raster request/function at `text/raster/undercurl.zig:4`, `:18`. | Keep. |

Exact user decision currently ready:

- Approve or reject only the cursor-trail extraction listed in the next section: move `howl-render/src/text/cursor_trail.zig` to `howl-render/src/cursor_trail.zig`, update its imports from `metrics.zig`/`contract.zig` to `text/metrics.zig`/`text/contract.zig`, update `cursor_presentation.zig` to import `cursor_trail.zig`, update `test_unit.zig` to import `cursor_trail.zig`, and rename the import alias from `text_cursor_trail` to `cursor_trail`.

User decisions not ready yet:

- Do not ask the user to approve FT/HB moves now. The user corrected that focus explicitly; `ft_hb` can die/rename later.
- Do not ask the user to choose `text/scene/` versus flat scene filenames yet. The plan has current-source evidence and Alacritty rect/text separation anchors, but it still lacks exact per-symbol destinations and import consequences for `scene.zig`, `scene_rects.zig`, `direct_scene.zig`, and `scene_damage.zig`.
- Do not ask the user to approve `text/color.zig`, `text/effects.zig`, or `text/metrics.zig` moves yet. They are plausible shallow owner extractions, but current users are mostly mediated through `text/contract.zig` plus local text imports, so approval needs an exact contract-root consequence plan first.
- Do not ask the user to approve `text/prepare/` moves yet. Alacritty has text draw preparation pressure, but Howl's embeddable `TextSurfacePreparer`, `OwnedPreparedTextSurface`, and direct-normal path have no closer reference folder anchor than current Howl proof; exact symbol consequences are still missing.
- Do not ask the user to approve `text/session.zig` rename yet. `FontSession` evidence exists at `text/session.zig:56`, but imports/symbol consequences in `render_session.zig`, `surface_preparer.zig`, `direct_normal.zig`, `provider.zig`, `resolver.zig`, and benchmarks must be enumerated first.
- Do not ask the user to approve deleting `text/contract.zig` yet. The aggregate root is proven by `text/contract.zig:3-70`, but exact replacement imports for all product/test consumers must be listed first.

Proposed executable order:

1. Approval-ready after reviewer/user gate: cursor-trail extraction from `text/` to root `cursor_trail.zig`.
2. Planning-only: color/effects/metrics shallow-owner extraction after exact `text/contract.zig` consequences are enumerated.
3. Planning-only: scene contract split slice after exact destination per `scene_contract.zig` symbol is listed.
4. Planning-only: contract-root deletion slice after exact replacement imports are listed.
5. Planning-only: scene/preparation path slice only after exact symbol/move/import consequences and reference-gap receipts are recorded.
6. Planning-only: font-session/font-path noun slices after exact imports/symbol aliases are enumerated.
7. Planning-only: FT/HB owner rename or deletion after user re-promotes text-stack cleanup.
8. Planning-only: raster long-function cleanup slice by metric deltas and owner-local tests.

Whole-text package stop conditions:

- The user has not approved the exact cursor-trail move/import list if the next worker is seeded for cursor-trail extraction.
- Any broader text move is treated as approval-ready before exact symbol/move/import consequences are recorded.
- Reviewer has not gated each executable sub-slice before worker implementation.
- Any sub-slice introduces compatibility aliases, bridge roots, or stale import shims.
- Any sub-slice changes C ABI headers, host-visible layouts, glyph output, shaping behavior, fallback-font limits, cursor presentation behavior, or surface ownership policy.
- A worker tries to combine two executable slices without a fresh reviewer gate.

Whole-text verification gates for every executable sub-slice:

- Before/after `python3 style.py --by-file --format json --sort prod howl-render`.
- Before/after forbidden-token content and path scans from this artifact.
- Reachability searches for every moved file path, deleted symbol, stale import alias, and replacement symbol.
- `zig build test:unit`, `zig build test:abi`, and `zig build check` in `howl-render`.
- Root `zig build check` after render package verification passes.

## User-Needed Next Slice

Name: Cursor-trail extraction from `text/`.

Why user approval is needed:

- The user corrected the next objective away from FT/HB and toward non-text clutter under `howl-render/src/text`.
- `text/cursor_trail.zig` is cursor animation/presentation state, not the true text stack. Its only product consumer is root `cursor_presentation.zig`, which already owns host cursor cadence and presentation behavior.
- Fixing the path requires a file move from `text/` to a shallow root owner; broad file moves require exact user approval before implementation.
- This is smaller and more coherent than color/effects/metrics or scene moves because it needs exactly one file move and two import repairs, with no contract-root deletion, scene split, ABI/header change, or FT/HB/text-stack change.

File-by-file proof for the selected slice:

- `howl-render/src/text/cursor_trail.zig:5` owns `Target`.
- `howl-render/src/text/cursor_trail.zig:13` owns `CursorTrail`.
- `howl-render/src/text/cursor_trail.zig:25`, `:36`, `:43`, `:57`, `:93`, and `:98` own cursor-trail mutation and animation state updates.
- `howl-render/src/text/cursor_trail.zig:111` owns `targetFromCursor`, which derives cursor-trail target geometry from cursor presentation shape and cell metrics.
- `howl-render/src/text/cursor_trail.zig:136` starts owner-local cursor-trail proofs.
- `howl-render/src/cursor_presentation.zig:5` is the only product import of `text/cursor_trail.zig`.
- `howl-render/src/cursor_presentation.zig:55`, `:145`, `:148`, and `:204` are the exact production alias/type/function consequences.
- `howl-render/src/test_unit.zig:10` is the exact unit-root import consequence.
- `howl-render/src/text/cursor_trail.zig:2-3` imports text-local `metrics.zig` and `contract.zig`; after the move these become `text/metrics.zig` and `text/contract.zig`.

Exact proposed move/import list for user approval:

- Move `howl-render/src/text/cursor_trail.zig` to `howl-render/src/cursor_trail.zig`.
- Inside moved `howl-render/src/cursor_trail.zig`, change `@import("metrics.zig")` to `@import("text/metrics.zig")` and `@import("contract.zig")` to `@import("text/contract.zig")`.
- In `howl-render/src/cursor_presentation.zig`, change `const text_cursor_trail = @import("text/cursor_trail.zig");` to `const cursor_trail = @import("cursor_trail.zig");` and update only the alias uses at `:55`, `:145`, `:148`, and `:204` from `text_cursor_trail` to `cursor_trail`.
- In `howl-render/src/test_unit.zig`, change `@import("text/cursor_trail.zig")` to `@import("cursor_trail.zig")`.
- Delete the old path `howl-render/src/text/cursor_trail.zig`; no compatibility bridge or re-export may remain.

Files that would be allowed after approval:

- `howl-render/src/text/cursor_trail.zig` only as the moved-from path; it must not remain after implementation
- `howl-render/src/cursor_trail.zig` as the moved-to owner
- `howl-render/src/cursor_presentation.zig`
- `howl-render/src/test_unit.zig`
- `loops/howl-render-cleanup-loop.txt` only for required teammate notes after execution/review

Required changes after approval:

- Apply exactly the move/import-alias list above, with no compatibility aliases, no re-export bridge under `text/`, no new folder, no umbrella owner, and no fallback import path.
- Preserve cursor trail animation math, target geometry, opacity behavior, host cursor cadence behavior, C ABI names/layouts, scene contracts, and all text stack behavior.
- Preserve current public render C ABI names and shipped headers.
- Do not move or rename FT/HB, color, effects, metrics, scene, raster, `text/contract.zig`, `text/session.zig`, or `render_session.zig` in this slice.

Required reachability/deletion searches after an approved implementation:

```sh
rg -n 'text/cursor_trail\.zig|text_cursor_trail' howl-render/src howl-render/include
rg -n 'cursor_trail\.zig|\bcursor_trail\.' howl-render/src howl-render/include
rg -n '\bCursorTrail\b|\bTarget\b|targetFromCursor' howl-render/src/cursor_trail.zig howl-render/src/cursor_presentation.zig howl-render/src/test_unit.zig
rg --files howl-render/src howl-render/include | rg '(^|/)cursor_trail\.zig$'
```

Expected search result after approval and implementation:

- First command returns no matches: the stale text path and stale alias must be gone.
- Second command shows `howl-render/src/cursor_presentation.zig` importing `cursor_trail.zig` and using the `cursor_trail` alias; no other new product consumers are expected.
- Third command shows `CursorTrail`, `Target`, and `targetFromCursor` only in the moved owner and root cursor-presentation call sites/tests.
- Fourth command shows exactly one product path: `howl-render/src/cursor_trail.zig`.

Metric recording required before and after an approved implementation:

```sh
python3 style.py --by-file --format json --sort prod howl-render
python3 style.py --by-file --format json --sort path howl-render/src/text/cursor_trail.zig howl-render/src/cursor_trail.zig howl-render/src/cursor_presentation.zig howl-render/src/test_unit.zig
```

Expected metric consequence after approval and implementation:

- Whole-package `bucket_named_structs` and `bucket_struct_lines` remain `0`.
- Whole-package path inventory no longer reports `text/cursor_trail.zig`.
- The moved `cursor_trail.zig` keeps comparable product/proof line totals because this is an owner move/import repair slice, but no new `long_funcs`, `anytypes`, `usizes`, `bucket_named_structs`, or bucket lines may be introduced.
- No forbidden-token count may increase from this move.

Forbidden-token recording required before and after an approved implementation:

```sh
rg -n -i --glob '*.zig' --glob '*.h' --glob '!**/.zig-cache/**' --glob '!**/zig-out/**' --glob '!**/vendor/**' '(contract|session|owner|pipeline|context|state|options|config|info|data|result|manager|controller|types|utils|helper|support)' howl-render/src/text/cursor_trail.zig howl-render/src/cursor_trail.zig howl-render/src/cursor_presentation.zig howl-render/src/test_unit.zig
rg -n -i --glob '*.zig' --glob '*.h' --glob '!**/.zig-cache/**' --glob '!**/zig-out/**' --glob '!**/vendor/**' '(contract|session|owner|pipeline|context|state|options|config|info|data|result|manager|controller|types|utils|helper|support)' howl-render/src howl-render/include
rg --files howl-render/src howl-render/include | rg -i '(^|/)[^/]*(contract|session|owner|pipeline|context|state|options|config|info|data|result|manager|controller|types|utils|helper|support)[^/]*$'
```

Expected forbidden-token consequence after approval and implementation:

- Allowed-file token hits may shift line numbers only; no forbidden-token count may increase.
- Package-root path scan no longer includes `text/cursor_trail.zig`; this path is not itself a forbidden-token path, so the required proof is the exact stale-path negative search above.
- `contract`, `session`, `owner`, `state`, `config`, `result`, and `support` totals may remain high; this slice does not rename scene contracts, render-session owners, FT/HB, or C test-support.
- No `manager`, `controller`, `types`, or `utils` token/path hits may be introduced.

Required tests after approval and implementation:

- `zig build test:unit` in `howl-render`
- `zig build test:abi` in `howl-render`
- `zig build check` in `howl-render`
- `zig build check` at workspace root after package check passes

Non-goals after approval:

- Do not change C ABI headers, C ABI layouts, host-facing behavior, cursor trail math, glyph raster output, shaping behavior, fallback-font limits, or text scene contracts.
- Do not add compatibility aliases such as a new `text/cursor_trail.zig` re-export.
- Do not create new folders or broad umbrella roots.
- Do not rename `render_session.zig`, `text/contract.zig`, `text/session.zig`, scene files, FT/HB files, raster files, or C test-support in this slice.
- Do not collapse mutex wrappers or change lock semantics in this slice.
- Do not use this move to do metric-driven refactors inside cursor-trail behavior.

Stop conditions after approval:

- The worker needs files outside the approved allowed list.
- Any product import or file path named `text/cursor_trail.zig` remains.
- `howl-render/src/test_unit.zig` still imports `text/cursor_trail.zig` after the move.
- Any compatibility alias or bridge preserves the old `text/cursor_trail.zig` path.
- Tests require behavior changes outside import-path and import-alias consequences.
- More than exactly one `cursor_trail.zig` file exists after implementation.
- The implementation attempts to solve FT/HB naming, render-session ownership, scene contract aggregation, duplicate mutex wrappers, color/effects/metrics extraction, raster cleanup, or C test-support cleanup in the same slice.

Receipt fields required after approval:

- Orchestrator session id: `orch-2026-06-18-render-cleanup-accountability-01`.
- Researcher session id: `research-2026-06-18-render-cleanup-non-text-clutter-10`.
- User approval receipt for the exact cursor-trail move/import list above.
- Reviewer session id that accepts the approved next-slice package.
- Coder/worker session id.
- Commit hash for accepted implementation or explicit open commit-hash handoff status.
- Before/after metric rows for whole-package `(sum)` and all allowed product files.
- Before/after forbidden-token evidence for allowed files, package-root content totals, and package-root path-scan matches.
- Results for all required tests and all deletion/reachability searches.

## Next-Slice Forcing Gates

After the user resolves the cursor-trail extraction decision and that slice is accepted, the next planning/execution seed must choose from these remaining deterministic targets unless fresh evidence shows a stronger one:

- Non-text clutter still under `text/`: color/effects/metrics, cursor presentation structs, scene/rect/damage concepts, and preparation surfaces only after exact symbol/move/import consequences are supplied.
- Metric/token dominant files `render_session.zig`, `text/ft_hb/support.zig`, `text/surface_preparer.zig`, `text/scene.zig`, `text/shape/cluster.zig`, `text/scene_rects.zig`, `text/direct_normal.zig`, and `text/raster/special_legacy_computing.zig`.
- Scene contract aggregation in `text/scene_contract.zig` and `text/contract.zig`.
- Remaining duplicate mutex wrappers in `submitted_surface.zig`, `text/ft_hb/support.zig`, and `render_session.zig` after lifecycle-owner proof.
- Test-support cleanup in `src/c/test_support.zig`.

The sprint cannot be declared complete until all four lanes produce either clean negative results or explicit, source-backed retained-shape receipts in this artifact or its accepted successor.
