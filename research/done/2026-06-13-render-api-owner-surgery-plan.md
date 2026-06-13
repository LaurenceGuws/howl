Historical authority: accepted research plan during the 2026-06-13 render API owner surgery sprint.

Why superseded or done: sprint closed with final root receipts `8aa8327` and `57bba4b`.

Must not be used for: current sprint authority, new render folder/file owner planning, or execution authorization.

# Render API Owner Surgery Plan

Date: 2026-06-13.

Status: reviewer-accepted planning committed; Slice 1 seeded for execution.

Role owner: researcher.

Orchestrator session id: `orch-2026-06-13-render-api-owner-surgery-01`.

Researcher session id: `research-2026-06-13-render-api-owner-surgery-01`.

Reviewer session id: `review-2026-06-13-render-api-owner-surgery-01`.

Planning commit-hash receipt: root commit `e5f7e4b`.

Question:

- What full source-backed sprint plan cuts `howl-render` into real idiomatic render owners, removes fake `tv_surface`, `session`, and `prepared` bucket structure, repairs false VT/render ownership, and produces exact reviewer-gated execution slices without violating the C ABI boundary?

## Sources Read In Order

1. Workflow and active accountability: `loop/flow.md`, `loop/orcestrator.md`, `loop/researcher.md`, `loop/reviewer.md`, `loop/coder.md`, `sprints/current.txt`, `loops/render-api-owner-surgery-live-loop.txt`, `sprints/2026-06-13-render-api-owner-surgery-sprint.md`.
2. Reference order and law: `reference-index.md`, `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`, `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`.
3. Current render source: `howl-render/src/tv_surface/`, `howl-render/src/session/`, `howl-render/src/prepared/`, `howl-render/src/text/`, `howl-render/src/geometry/`, `howl-render/src/libhowl_render.zig`.
4. ABI and host seams: `howl-render/include/howl_render.h`, `howl-vt/include/howl_vt.h`, `howl-linux-host/src/terminal/term.zig`, `howl-linux-host/src/terminal/vt/surface.zig`.
5. Alacritty anchors: `alacritty/src/renderer/mod.rs`, `alacritty/src/renderer/text/mod.rs`, `alacritty/src/renderer/text/glyph_cache.rs`, `alacritty/src/renderer/text/atlas.rs`, `alacritty/src/display/content.rs`, `alacritty/src/display/damage.rs`, `alacritty_terminal/src/grid/storage.rs`.
6. Ghostty VT and renderer seams: `ghostty/src/terminal/c/terminal.zig`, `ghostty/src/terminal/c/main.zig`, `ghostty/src/lib_vt.zig`, `ghostty/src/renderer.zig`.

## Current-Code Facts

- `howl-render/include/howl_render.h:6` includes `howl_vt.h`, and `howl-render/build.zig:30-36` translates the render header with the VT include path. Render may consume the shipped VT C ABI, but the render implementation must not redefine VT truth or import VT internals.
- `howl-vt/include/howl_vt.h:82-204` owns the C ABI structs for VT surface cells, flags, color state, cursor, selection, and `HowlVtSurface`.
- `howl-render/src/tv_surface/vt.zig:2-15` imports `howl_render_c` and aliases `HowlVtRgb8`, `HowlVtColor`, `HowlVtRenderColorState`, `HowlVtSurfaceCellFlags`, `HowlVtSurfaceCellAttrs`, `HowlVtSurfaceCell`, `HowlVtSelectionPos`, and `HowlVtSelection`. This file is a render-side VT ABI adapter, not a `tv_surface` owner.
- `howl-render/src/tv_surface/vt.zig:18-102` defines `VtSnapshot` and `PublicationSource`; `:104-178` validates VT publication data; `:180-219` copies a `HowlVtSurface` result into render-owned publication storage. The file mixes ABI import, source lifetime, validation, snapshot identity, and conversion.
- `howl-render/src/tv_surface/cell.zig:1-92` defines render-side `Color`, `Cell`, `GridModel`, `DamageInfo`, `ViewportInfo`, `CursorInfo`, and `SurfaceData`. This duplicates terminal/renderable content concepts instead of isolating the shipped VT publication seam.
- `howl-render/src/tv_surface/text_input.zig:9-63` owns default theme and palette; `:64-143` maps VT colors/cursor/underline to text scene types; `:175-209` maps local cell input; `:211-213` delegates publication cell mapping. This mixes color theme, VT-to-text input mapping, and dead/local cell paths.
- `howl-render/src/tv_surface/publication_cell_map.zig:7-18` defines theme and semantic truth; `:22-65` maps VT publication cells to `text/contract.zig`; `:112-120` maps VT cursor; `:145-156` maps semantic colors. This is a renderable-content adapter, not a surface owner.
- `howl-render/src/tv_surface/slot.zig:6-66` owns retained cell and dirty-span storage; `:68-121` copies VT-published source into retained storage; `:123-165` reserves/commits source slots; `:176-220` rebuilds retained views. This is storage, not a `tv_surface` owner.
- `howl-render/src/tv_surface/prepare_request.zig:8-19` defines prepare consume/admission structs; `:21-211` owns active source admission, damage classification, blink refresh, token matching, and retained source retirement. This is prepare queue/admission state, not a `tv_surface` owner.
- `howl-render/src/session/text.zig:1-29` imports geometry, `tv_surface`, `prepared`, text shaping, raster cache, provider, and submitted state; `:141-180` defines config, host surface, submit result, session, nested context, layout aliases, submit execution, and prepare input; `:229-260` maps publication colors, damage, prepare options, font session, and prepared ownership in one method. This is a bucket named `session`, not an idiomatic render owner.
- `howl-render/src/prepared/surface.zig:8-21` defines info and buffer structs; `:23-80` owns prepared identity, geometry, text surface, resolve observability, and emission failure. This is prepared content identity, not the owner of all prepared concerns.
- `howl-render/src/prepared/buffer.zig:7-26` composes CPU pixels; `:28-71` defines draw pass order; `:132-163` reaches back into session atlas raster lookup. This is CPU pixel composition and retained-base realization, not prepared identity.
- `howl-render/src/prepared/handle.zig:62-201` owns C handle lifetime, session tracking, prepared payload emission, state transitions, release/consume, and stale sentinel behavior. This is ABI handle ownership.
- `howl-render/src/prepared/render_surface_emitter.zig:3-18` imports `howl_render_c`, prepared buffer, geometry realizer, sprite resource store, rasterizer, and text session; `:189-220` asserts command bounds and defines emission failure. This is C render-surface emission, not generic prepared ownership.
- `howl-render/src/prepared/sprite_resource_store.zig:2-20` imports the render C ABI and defines C-bound resource/atlas constants; `:37-77` owns resource store state, resource allocation, atlas placement, and rollback; `:98-156` owns rollback/restore assertions. This is an atlas/resource store and should not hide under `prepared`.
- `howl-render/src/text/contract.zig:10-27` mixes text color/effect style facts; `:67-90` mixes decoration/cursor/cell/grid geometry metrics; `:92-112` mixes renderable cell input with effects, colors, and geometry-adjacent text presentation. The user-directed text/effects/geometry recut must split this file rather than keep `contract.zig` as an owner bucket.
- `howl-render/src/text/contract.zig:122-336` owns sprite keys, cell text, renderable cells, glyph groups, sprite positions, draw commands, raster requests, and `TextScene`. These are text scene contract facts, not color/effect/metrics owners.
- `howl-render/src/text/ft_hb/cache.zig:42-73`, `:75-187`, and `:189-220` own FT/HB face-text, shape-run, and glyph-cell caches. This is the exact font/shaping cache owner for this sprint.
- `howl-render/src/text/raster/cache.zig:31-111` owns raster atlas slot reservation, rendered-raster storage, and lookup. This is an atlas owner in Alacritty's sense and must be renamed to an atlas owner, not left as generic cache.
- `howl-render/src/geometry/render_surface_realizer.zig:17-173` owns a C render-surface `ResourceStore` for realized host-side resource state while `howl-render/src/prepared/sprite_resource_store.zig:37-77` owns emit-time sprite/resource allocation. Geometry must not own C render-surface resources; these are two separate `surface` owners.
- `howl-render/build.zig:85-99` already has render test gates: `check`, `test`, `test:unit`, `test:abi`, and `test:build`. `howl-render/build.zig:124-150` also builds `src/benchmark_main.zig` as part of `check`, so every slice that moves a `tv_surface`, `session`, or `prepared` import used by the benchmark must migrate `benchmark_main.zig` before the old owner file is deleted.

## Reference Facts

- Alacritty renderer root exposes `platform`, `rects`, `shader`, and `text`; it re-exports `GlyphCache` and `LoaderApi` from text at `alacritty/src/renderer/mod.rs:26-35`. This supports explicit renderer/text/cache names, not generic `session` or `prepared` buckets.
- Alacritty renderer owns text rendering through `TextRenderer`, `TextRenderBatch`, `TextRenderApi`, `LoaderApi`, and `GlyphCache` at `alacritty/src/renderer/text/mod.rs:11-21` and `:49-197`. This supports text renderer/cache/loader seams.
- Alacritty `TextRenderApi::draw_cell` consumes `RenderableCell`, consults `GlyphCache`, and batches render items at `alacritty/src/renderer/text/mod.rs:134-172`. Render consumes renderable content; it does not own terminal state.
- Alacritty `GlyphCache` owns the rasterizer, font keys, font size, offsets, metrics, and cache map at `alacritty/src/renderer/text/glyph_cache.rs:42-79`, with explicit `LoadGlyph` loader API at `:17-26`. This supports `glyph_cache` naming and cache ownership.
- Alacritty `Atlas` is a named texture atlas owner with row-placement state at `alacritty/src/renderer/text/atlas.rs:11-61` and insertion bounds at `:118-147`. This supports `atlas` or `resource_store` naming for sprite/glyph resource placement, not `prepared`.
- Alacritty `RenderableContent` is display-side terminal content for renderer consumption at `alacritty/src/display/content.rs:24-38`; construction pulls terminal content and display colors at `:40-88`; iteration skips empty cells and applies flags at `:153-160`. This supports a renderable content adapter for VT publications.
- Alacritty `DamageTracker` owns display damage at `alacritty/src/display/damage.rs:12-28`, with frame swapping, resize, cursor damage, selection damage, and shaped frame damage at `:31-136`. This supports a dedicated damage owner.
- Alacritty grid `Storage<T>` is a ring-buffer storage owner and explicitly refuses `Deref` to avoid exposing invalid `Vec` behavior at `alacritty_terminal/src/grid/storage.rs:15-30`; fields are exact storage facts at `:33-53`. This supports a dedicated `storage` owner for retained VT publication buffers.
- Ghostty terminal C API wraps Zig terminal state in a C-facing `TerminalWrapper` at `ghostty/src/terminal/c/terminal.zig:30-37`, with callback/effects state isolated at `:39-117`. This supports opaque C wrappers and C seam isolation.
- Ghostty terminal C API converts C data at the boundary in trampolines such as `deviceAttributesTrampoline` at `ghostty/src/terminal/c/terminal.zig:142-170`. This supports conversion at boundary modules, not domain files redefining foreign structs.
- Ghostty renderer root is separate from terminal C API and exports renderer modules/types at `ghostty/src/renderer.zig:1-34`; renderer implementation selection is separate at `:36-42`. This supports keeping renderer and VT C surface concerns separated.
- Ghostty C API AGENTS rule for `terminal/c` requires ABI-compatible design, opaque pointers for long-lived objects, and full export/header wiring. This reinforces that ABI files are explicit seams, not hidden convenience imports.
- TigerBeetle style requires assertions for programmer errors and a high assertion density at `TIGER_STYLE.md:104-113`, pair assertions at `:115-123`, positive and negative space assertions at `:136-137`, and direct low-abstraction code pressure at `ARCHITECTURE.md:267-278`. This gates every slice.
- TigerBeetle architecture says static limits force correctness under overload at `ARCHITECTURE.md:208-221` and comprehensive testing leaves little space for bugs at `:262-320`. This gates render command/resource bounds and tests.

## Anchor Map

- VT ABI truth: `howl-vt/include/howl_vt.h:82-204`.
- Render C ABI truth: `howl-render/include/howl_render.h:1-220` and remaining surface command declarations in the same header.
- Render C translate/import seam: `howl-render/build.zig:30-36`, `:101-120`.
- Current false VT/render seam: `howl-render/src/tv_surface/vt.zig:2-15`.
- Current retained publication storage: `howl-render/src/tv_surface/slot.zig:6-121`.
- Current prepare admission: `howl-render/src/tv_surface/prepare_request.zig:21-211`.
- Current renderable content mapping: `howl-render/src/tv_surface/publication_cell_map.zig:22-65`, `:112-120`.
- Current text render bucket: `howl-render/src/session/text.zig:1-29`, `:158-260`.
- Current prepared identity: `howl-render/src/prepared/surface.zig:23-80`.
- Current CPU composition: `howl-render/src/prepared/buffer.zig:7-71`.
- Current C handle lifetime: `howl-render/src/prepared/handle.zig:62-201`.
- Current C surface emission: `howl-render/src/prepared/render_surface_emitter.zig:3-18`, `:189-220`.
- Current resource/atlas store: `howl-render/src/prepared/sprite_resource_store.zig:9-20`, `:37-77`.
- Current text/effects/geometry bucket: `howl-render/src/text/contract.zig:10-27`, `:67-90`, `:92-112`, `:122-336`.
- Current FT/HB cache owners: `howl-render/src/text/ft_hb/cache.zig:42-220`, consumed by `howl-render/src/text/ft_hb/support.zig:47-71`.
- Current raster atlas cache owner: `howl-render/src/text/raster/cache.zig:31-111`, consumed by `howl-render/src/text/surface_preparer.zig:7`, `:53-86`, and `howl-render/src/text/direct_normal.zig:2`, `:102-108`.
- Current realizer resource owner conflict: `howl-render/src/geometry/render_surface_realizer.zig:17-173`, tests at `howl-render/src/geometry/render_surface_realizer_test.zig:15-18`, callers at `howl-render/src/prepared/render_surface_emitter_test.zig:7`, `:940-960`, and `howl-render/src/test_support.zig:14`, `:29`.
- Alacritty renderer/text owner pressure: `renderer/mod.rs:26-35`, `renderer/text/mod.rs:11-21`, `:49-197`.
- Alacritty renderable content/damage/storage pressure: `display/content.rs:24-38`, `display/damage.rs:12-28`, `grid/storage.rs:15-30`.
- Ghostty C seam pressure: `terminal/c/terminal.zig:30-37`, `:142-170`, `renderer.zig:1-34`.

## Owner Roles And Proposed Render Shape

- `src/vt_publication/`: render's sole VT C ABI publication adapter. It may import `howl_render_c`; it owns C ABI validation, copy-in from `HowlVtSurface` result, publication metadata, and conversion into render-owned slices. It must not redefine VT ABI structs or expose host/VT internals. It does not own retained storage.
- `src/renderable_content/`: renderable terminal content adapter in Alacritty's `RenderableContent` sense. It maps a validated VT publication into text scene input, theme/color consequences, cursor input, selection-visible consequences, and semantic empty classification.
- `src/damage/`: damage classification and dirty row/column canonicalization, with cursor/color/scroll/geometry invalidation rules. It is the render equivalent of Alacritty `DamageTracker`, but fed by VT publication metadata and render tokens.
- `src/storage/publication_storage.zig`: retained publication storage. It owns cell and dirty-span capacity, reserved/committed publication slots, view refresh, and explicit bounds. It follows Alacritty storage pressure by exposing only the operations that preserve retained publication invariants. No `vt_publication/storage.zig` is allowed.
- `src/prepare/`: prepare admission queue. It owns active publication admission, token matching, blink refresh forcing, prepare take/consume/retry/retire state, and no text/font work.
- `src/render_session.zig`: the single long-lived C ABI render session owner. It owns allocator, mutex, text support/cache instance, publication storage, prepare queue, submitted surface state, and prepared handle tracking. It delegates VT publication, renderable content, damage, surface emission, CPU composition, and resource storage to their owners.
- `src/text/color.zig`: text RGBA and semantic color facts currently in `text/contract.zig:3-19`.
- `src/text/effects.zig`: text underline, decoration, and presentation effect facts currently in `text/contract.zig:21-27`, `:274-280`, and style/presentation enum facts at `:36-47`.
- `src/text/metrics.zig`: font, face, decoration, cursor, cell, and grid metrics currently in `text/contract.zig:49-90`.
- `src/text/cell_input.zig`: renderable text cell input currently in `text/contract.zig:92-112`.
- `src/text/scene_contract.zig`: text scene, cell text, renderable cells, runs, glyph groups, sprite positions, draw commands, raster requests, shaped/missing glyph facts currently in `text/contract.zig:114-383`.
- `src/text/contract.zig`: curated compatibility root for the text owner modules during this sprint only; it must contain imports/re-exports and tests only, no owner state or mutation.
- `src/text/ft_hb/cache.zig`: final FT/HB face-text, shape-run, and glyph-cell cache owner. It remains named `cache.zig` because the file owns three explicit FT/HB caches under the FT/HB owner.
- `src/text/raster/atlas.zig`: final raster atlas slot/cache owner. It replaces `src/text/raster/cache.zig` because Alacritty names the atlas owner `Atlas` and the current file owns atlas slot/raster storage, not general cache.
- `src/surface/`: prepared render surface identity and retained surface consequences. It owns prepared token/info, geometry epoch, prepared text scene reference, and render-surface emission failure, not CPU composition, C handle lifetime, or resource atlas storage.
- `src/surface/compositor.zig`: CPU pixel composition from a prepared surface and optional retained base. This is a direct draw-pass compositor, not a prepared owner.
- `src/surface/emitter.zig`: C `HowlRenderSurface` emission. It may import `howl_render_c`; it owns command spans, upload spans, damage spans, surface payload lifetime internals, and bound assertions.
- `src/surface/handle.zig`: C ABI prepared-surface handle lifetime and state transitions. It owns opaque handle conversion, release/consume, session tracking registration, and payload destruction.
- `src/surface/resource_store.zig`: emit-time sprite/glyph resource and atlas allocation store. It moves from `prepared/sprite_resource_store.zig` and owns persistent/transient resource allocation, atlas placement, rollback, and static limits before a C render surface is emitted.
- `src/surface/realizer.zig`: CPU realization of a C `HowlRenderSurface` into pixels for tests/host-side validation. It moves from `geometry/render_surface_realizer.zig`.
- `src/surface/realizer_resource_store.zig`: realized C render-surface resource state currently nested as `geometry/render_surface_realizer.zig:17-173`. It validates create/upload/retire transitions and stores realized resource bytes. Geometry owns no C render-surface resources after this move.
- `src/libhowl_render.zig`: FFI/export translator only. It must route C ABI calls into explicit owners and translate statuses. It must not contain render policy.

## Sprint Scratchpad

- Full-sprint objective: remove `tv_surface`, `session`, and `prepared` as owner buckets and replace them with source-backed owners above, preserving the shipped C ABI unless a slice proves an ABI change is required and records the exact change.
- Execution rule: one slice at a time. Reviewer must accept each slice before the orchestrator seeds the next coder pass.
- Receipt rule: every accepted slice must record the committed hash in this artifact or the live loop before the next slice begins. Planning commit receipt remains pending until the reviewer accepts this plan and the orchestrator commits it.
- Test rule: every slice must run render proof commands in cwd `/home/home/personal/projects/howl/howl-render`. Every slice runs `zig build test:unit`; every slice that changes C ABI/export/header/handle paths also runs `zig build test:abi`; every slice that changes imports used by `src/benchmark_main.zig` or `build.zig:124-150` also runs `zig build check`. Worker must not substitute repo-root wrapper commands or unproven build flags.
- Naming rule: no owner named `manager`, `engine`, `controller`, `utils`, `types`, `Context`, `State`, `Options`, `Info`, `Data`, `Result`, or `Diagnostics` unless an explicit source-backed exception is recorded before coding.

## Ordered Slice Plan

### Slice 1: VT Publication Boundary And Storage

- Accountable worker session id: `coder-2026-06-13-render-api-owner-surgery-01`.
- Reviewer session id: `review-2026-06-13-render-api-owner-surgery-01`.
- Allowed files: `howl-render/src/tv_surface/vt.zig`, `howl-render/src/tv_surface/cell.zig`, `howl-render/src/tv_surface/slot.zig`, `howl-render/src/tv_surface/damage.zig`, `howl-render/src/prepare_request.zig`, `howl-render/src/benchmark_main.zig`, `howl-render/src/session/text.zig`, `howl-render/src/session/text_test.zig`, `howl-render/src/test_support.zig`, `howl-render/src/test_unit.zig`, `howl-render/src/vt_publication/abi.zig`, `howl-render/src/vt_publication/publication.zig`, `howl-render/src/storage/publication_storage.zig`.
- Required shape: create `vt_publication/publication.zig` for `PublicationSource` and `VtSnapshot`; create `vt_publication/abi.zig` for aliases to shipped `HowlVt*` structs and C result validation; create `storage/publication_storage.zig` for retained publication storage currently in `slot.zig`. `cell.zig` local duplicate structs remain temporary compatibility input only until slice 2 moves them to `renderable_content/content.zig`; they must not become storage or VT ABI truth, and no `vt_publication/storage.zig` may be created.
- Required assertions: cols/rows nonzero before allocation; cell count checked with overflow handling; dirty spans equal rows; copied cell count equals `cols * rows`; `combining_len <= combining.len`; color kind is one of shipped VT kinds; underline style is in range; retained storage sources are never freed as owned duplicates.
- Required tests: keep or move existing `prepare requests` and publication validation tests through the existing unit root; add/keep owner-local tests for invalid color kind, invalid combining length, dirty span length mismatch, retained source deinit not freeing slot storage, and copy-in preserving snapshot/dirty metadata. Proof must include `zig build test:unit` and `zig build check` in cwd `/home/home/personal/projects/howl/howl-render` because `benchmark_main.zig` imports `tv_surface/vt.zig` and `tv_surface/cell.zig` and the benchmark target is wired into `check` at `build.zig:124-150`.
- Non-goals: no text scene mapping, no prepare admission changes beyond imports, no C ABI header changes, no host changes.
- Stop conditions: stop if any render code imports VT Zig internals; stop if a non-ABI duplicate of `HowlVtSurfaceCell` remains as render truth; stop if C header changes seem required.
- Commit receipt demand: after reviewer acceptance, record commit hash as `slice-1-vt-publication-boundary=<hash>`.

### Slice 2: Renderable Content And Damage Owners

- Accountable worker session id: `coder-2026-06-13-render-api-owner-surgery-02`.
- Reviewer session id: `review-2026-06-13-render-api-owner-surgery-01`.
- Allowed files: `howl-render/src/tv_surface/text_input.zig`, `howl-render/src/tv_surface/publication_cell_map.zig`, `howl-render/src/tv_surface/damage.zig`, `howl-render/src/tv_surface/cell.zig`, `howl-render/src/benchmark_main.zig`, `howl-render/src/session/text.zig`, `howl-render/src/session/text_test.zig`, `howl-render/src/text/contract.zig`, `howl-render/src/text/direct_normal.zig`, `howl-render/src/text/surface_preparer.zig`, `howl-render/src/text/shape/cluster.zig`, `howl-render/src/test_support.zig`, `howl-render/src/renderable_content/content.zig`, `howl-render/src/renderable_content/color.zig`, `howl-render/src/renderable_content/cursor.zig`, `howl-render/src/damage/publication_damage.zig`.
- Required shape: move VT-publication-to-text input mapping into `renderable_content/content.zig`; move theme/palette and color mapping into `renderable_content/color.zig`; move cursor mapping into `renderable_content/cursor.zig`; move dirty metadata validation/canonicalization and snapshot classification into `damage/publication_damage.zig`. Names are fixed for this sprint; no `damage/tracker.zig`, broad `map.zig`, or alternate renderable-content file names are allowed.
- Required assertions: semantic empty classification asserts default fg/bg when empty; inverse/selection assert resulting opaque colors; dirty rows assert row bounds and column start/end order; cursor row/col asserts within publication grid when visible; full damage asserts all rows/cols are covered or explicitly classified full.
- Required tests: move existing publication cell map tests; add tests for default background opacity, inverse style, selected style, invisible/continuation not falsely empty, cursor blink hidden/visible mapping, partial dirty row canonicalization, and full damage classification when cursor/color/geometry/scroll changes. Proof must include `zig build test:unit` and `zig build check` in cwd `/home/home/personal/projects/howl/howl-render` because `benchmark_main.zig`, `text/shape/cluster.zig`, `text/surface_preparer.zig`, and `text/direct_normal.zig` import `tv_surface` mapping files.
- Non-goals: no text shaping/raster changes; no resource store changes; no C ABI header changes.
- Stop conditions: stop if `renderable_content` starts owning VT storage or prepare queue state; stop if damage code imports text raster/font owners; stop if the old `tv_surface` folder still contains live owner code after this slice except temporary compatibility imports explicitly scheduled for deletion in slice 3.
- Commit receipt demand: after reviewer acceptance, record commit hash as `slice-2-renderable-content-damage=<hash>`.

### Slice 3: Prepare Queue Cutover And `tv_surface` Deletion

- Accountable worker session id: `coder-2026-06-13-render-api-owner-surgery-03`.
- Reviewer session id: `review-2026-06-13-render-api-owner-surgery-01`.
- Allowed files: `howl-render/src/tv_surface/prepare_request.zig`, `howl-render/src/tv_surface/vt.zig`, `howl-render/src/tv_surface/cell.zig`, `howl-render/src/tv_surface/slot.zig`, `howl-render/src/tv_surface/publication_cell_map.zig`, `howl-render/src/tv_surface/damage.zig`, `howl-render/src/tv_surface/text_input.zig`, `howl-render/src/prepare/queue.zig`, `howl-render/src/prepare_request.zig`, `howl-render/src/benchmark_main.zig`, `howl-render/src/storage/publication_storage.zig`, `howl-render/src/renderable_content/content.zig`, `howl-render/src/renderable_content/color.zig`, `howl-render/src/renderable_content/cursor.zig`, `howl-render/src/vt_publication/abi.zig`, `howl-render/src/vt_publication/publication.zig`, `howl-render/src/session/text.zig`, `howl-render/src/session/text_test.zig`, `howl-render/src/text/direct_normal.zig`, `howl-render/src/text/surface_preparer.zig`, `howl-render/src/text/shape/cluster.zig`, `howl-render/src/test_support.zig`, `howl-render/src/prepare_request_test.zig`, `howl-render/src/test_unit.zig`.
- Required shape: create `prepare/queue.zig` for active prepare admission/take/consume/retry/retire and blink refresh. Prepare queue may depend on `vt_publication`, `storage/publication_storage.zig`, `damage/publication_damage.zig`, `geometry/tokens.zig`, and `geometry/geometry_contract.zig` only. This slice must migrate every remaining live import away from all seven `tv_surface` files, including the remaining users in `storage/publication_storage.zig`, `renderable_content/content.zig`, `renderable_content/color.zig`, `renderable_content/cursor.zig`, `vt_publication/abi.zig`, `vt_publication/publication.zig`, and `session/text.zig`, and then delete `tv_surface/prepare_request.zig`, `tv_surface/vt.zig`, `tv_surface/cell.zig`, `tv_surface/slot.zig`, `tv_surface/publication_cell_map.zig`, `tv_surface/damage.zig`, and `tv_surface/text_input.zig`.
- Required assertions: active source is present before consuming; token equality is asserted before returning prepare consume; retry only flips taken state for the same token; geometry epoch changes force full damage; retained source clone/deinit ownership is explicit; blink refresh cannot fabricate a source.
- Required tests: preserve and relocate all prepare request tests; add tests for no-op duplicate source admission, geometry change forcing full, stale base forcing full for partial damage, blink refresh after taken prepare, retry taken prepare token mismatch, and retire at/before submitted token. Proof must include `zig build test:unit` and `zig build check` in cwd `/home/home/personal/projects/howl/howl-render` because benchmark/check imports must be migrated before `tv_surface` deletion.
- Non-goals: no text session rename yet; no prepared/surface changes; no host changes.
- Stop conditions: stop if any import path still contains `tv_surface/` after this slice; stop if a live concept remains in `tv_surface` without an owner named above; stop if prepare queue needs text/font imports.
- Commit receipt demand: after reviewer acceptance, record commit hash as `slice-3-prepare-storage-cutover=<hash>`.

### Slice 4: Text Effects Geometry Contract Recut

- Accountable worker session id: `coder-2026-06-13-render-api-owner-surgery-04`.
- Reviewer session id: `review-2026-06-13-render-api-owner-surgery-01`.
- Allowed files: `howl-render/src/text/contract.zig`, `howl-render/src/text/color.zig`, `howl-render/src/text/effects.zig`, `howl-render/src/text/metrics.zig`, `howl-render/src/text/cell_input.zig`, `howl-render/src/text/scene_contract.zig`, `howl-render/src/text/raster/cache.zig`, `howl-render/src/text/raster/atlas.zig`, `howl-render/src/text/raster/key.zig`, `howl-render/src/text/raster/operation.zig`, `howl-render/src/text/raster/rasterizer.zig`, `howl-render/src/text/raster/special.zig`, `howl-render/src/text/raster/special_test.zig`, `howl-render/src/text/ft_hb/cache.zig`, `howl-render/src/text/ft_hb/support.zig`, `howl-render/src/text/ft_hb/support_test.zig`, `howl-render/src/text/ft_hb/glyph_raster.zig`, `howl-render/src/text/ft_hb/provider.zig`, `howl-render/src/text/session.zig`, `howl-render/src/text/provider.zig`, `howl-render/src/text/resolver.zig`, `howl-render/src/text/resolve.zig`, `howl-render/src/text/scene.zig`, `howl-render/src/text/direct_scene.zig`, `howl-render/src/text/direct_normal.zig`, `howl-render/src/text/surface_preparer.zig`, `howl-render/src/text/shape/cluster.zig`, `howl-render/src/text/shape/grouping.zig`, `howl-render/src/text/shape/run.zig`, `howl-render/src/text/classify/lane.zig`, `howl-render/src/text/classify/symbol_map.zig`, `howl-render/src/benchmark_main.zig`, `howl-render/src/test_support.zig`, `howl-render/src/session/text.zig`, `howl-render/src/session/text_test.zig`, `howl-render/src/prepared/buffer.zig`, `howl-render/src/prepared/handle_test.zig`, `howl-render/src/prepared/render_surface_emitter.zig`, `howl-render/src/prepared/render_surface_emitter_test.zig`.
- Required shape: split `text/contract.zig` into exact owners: `text/color.zig` for `Rgba8`, `SemanticColorKind`, and `SemanticColor`; `text/effects.zig` for `UnderlineStyle`, `FontStyle`, `TextPresentation`, `DecorationKind`, and effect enums; `text/metrics.zig` for `FontMetrics`, `FaceMetrics26Dot6`, `DecorationGeometry`, `CursorGeometry`, `CellMetrics`, and `GridMetrics`; `text/cell_input.zig` for `CellInput`; `text/scene_contract.zig` for `FontFaceId`, `CellTextId`, `SpriteKey`, `CellText`, `LineTextCache`, `RenderableCell`, `CellCluster`, `RunFont`, `TextRun`, `ResolvedRun`, `GlyphInstance`, `GlyphPlacement`, `GlyphGroupKind`, `GlyphGroup`, `SpriteColorMode`, `SpritePosition`, `TextSpriteDraw`, `TextBackgroundDraw`, `TextClearDraw`, `TextCursorDraw`, `TextDecorationDraw`, `SpriteRasterKind`, `DecorationSpriteRaster`, `BoxDrawingRasterMetrics`, `SpriteRasterRequest`, `TextScene`, `SpecialSpriteRoute`, `TextCluster`, `ShapedGlyph`, `ShapedRun`, `MissingGlyphReason`, and `MissingGlyph`. Keep `text/contract.zig` as a curated re-export root only. Rename `text/raster/cache.zig` to `text/raster/atlas.zig` and update all imports; `text/ft_hb/cache.zig` remains the FT/HB cache owner.
- Required assertions: preserve existing text contract deterministic defaults in owner-local tests; add owner-local tests proving color defaults, effect enum stability, metrics nonzero fixtures, `CellInput.combining_len <= combining.len`, text scene draw spans retain first-cell/cell-span facts, raster atlas reserve/store bounds, and FT/HB cache capacity errors.
- Required tests: `zig build test:unit` and `zig build check` in cwd `/home/home/personal/projects/howl/howl-render`. `check` is required because `benchmark_main.zig` imports `text/contract.zig` and exercises `TextSurfacePreparer.atlas`.
- Non-goals: no VT publication changes; no render session move; no prepared surface split; no C ABI header changes; no feature additions.
- Stop conditions: stop if `text/contract.zig` still owns structs or mutation after this slice; stop if `text/raster/cache.zig` remains as a live owner file; stop if FT/HB caches are merged with raster atlas cache; stop if geometry owner files receive text metrics or render effects.
- Commit receipt demand: after reviewer acceptance, record commit hash as `slice-4-text-effects-geometry-contract-recut=<hash>`.

### Slice 5: Render Session Owner

- Accountable worker session id: `coder-2026-06-13-render-api-owner-surgery-05`.
- Reviewer session id: `review-2026-06-13-render-api-owner-surgery-01`.
- Allowed files: `howl-render/src/session/text.zig`, `howl-render/src/session/submitted.zig`, `howl-render/src/session/text_test.zig`, `howl-render/src/render_session.zig`, `howl-render/src/submitted_surface.zig`, `howl-render/src/text_session.zig`, `howl-render/src/handle.zig`, `howl-render/src/work_state.zig`, `howl-render/src/submission.zig`, `howl-render/src/prepared_surface.zig`, `howl-render/src/prepare_request.zig`, `howl-render/src/libhowl_render.zig`, `howl-render/src/text/ft_hb/support.zig`, `howl-render/src/text/ft_hb/glyph_raster.zig`, `howl-render/src/text/ft_hb/support_test.zig`, `howl-render/src/prepared/buffer.zig`, `howl-render/src/prepared/handle.zig`, `howl-render/src/prepared/render_surface_emitter.zig`, `howl-render/src/prepared/handle_test.zig`, `howl-render/src/prepared/render_surface_emitter_test.zig`, `howl-render/src/test_support.zig`, `howl-render/src/text_session_test.zig`, `howl-render/src/submission_test.zig`, `howl-render/src/surface_geometry.zig`, `howl-render/src/test/unit/root.zig`.
- Required shape: replace generic `session/text.zig` with `render_session.zig` as the single long-lived C ABI render session owner. Move submitted-token tracking from `session/submitted.zig` to `submitted_surface.zig`. Keep text shaping/font/raster owners under existing `text/` files; use `text/ft_hb/cache.zig` for FT/HB face/shape/glyph-cell caches and `text/raster/atlas.zig` for raster atlas slot/cache ownership. Do not create `text/renderer.zig` or `text/glyph_cache.zig` in this sprint. Delete `session/text.zig`, `session/submitted.zig`, and `session/text_test.zig` after all imports are migrated.
- Required assertions: mutex-protected state mutations enter through the long-lived owner; font fallback count is bounded by existing constants; scratch cell input length matches publication cell count; derived grid and cell sizes are nonzero; prepared surface creation cannot hold lock across handle registration unless explicitly asserted safe; submitted token monotonicity is asserted.
- Required tests: existing text prepare tests continue through unit root after moving from `session/text_test.zig`; add or preserve tests for derive layout nonzero checks, invalid font path behavior, publication-to-cell-input scratch reuse bounds, submitted token stale/needs-prepare decisions, and font fallback cap. Proof must include `zig build test:unit`, `zig build test:abi`, and `zig build check` in cwd `/home/home/personal/projects/howl/howl-render` because `libhowl_render.zig`, ABI boundary files, and benchmark/check build all depend on the long-lived session owner.
- Non-goals: no C render surface emission behavior changes; no resource store ownership move; no ABI header changes. Exported symbol rename pressure is a stop condition, not an implementation choice in this slice.
- Stop conditions: stop if renaming exported C ABI symbols is required; stop if `TextSessionOwner` or an equivalent in `render_session.zig` still directly owns VT mapping, damage classification, CPU composition, C surface emission, and resource store logic after imports are corrected; stop if any import path still contains `session/text.zig` after this slice.
- Commit receipt demand: after reviewer acceptance, record commit hash as `slice-5-render-session-owner=<hash>`.

### Slice 6: Prepared Surface And Surface Resource Split

- Accountable worker session id: `coder-2026-06-13-render-api-owner-surgery-06`.
- Reviewer session id: `review-2026-06-13-render-api-owner-surgery-01`.
- Allowed files: `howl-render/src/prepared/surface.zig`, `howl-render/src/prepared/buffer.zig`, `howl-render/src/prepared/handle.zig`, `howl-render/src/prepared/render_surface_emitter.zig`, `howl-render/src/prepared/sprite_resource_store.zig`, `howl-render/src/prepared/handle_test.zig`, `howl-render/src/prepared/render_surface_emitter_test.zig`, `howl-render/src/prepared_surface.zig`, `howl-render/src/submission.zig`, `howl-render/src/handle.zig`, `howl-render/src/render_session.zig`, `howl-render/src/test_support.zig`, `howl-render/src/prepared_surface_test.zig`, `howl-render/src/submission_test.zig`, `howl-render/src/test/unit/root.zig`, `howl-render/src/geometry/render_surface_realizer.zig`, `howl-render/src/geometry/render_surface_realizer_test.zig`, `howl-render/src/surface/prepared_surface.zig`, `howl-render/src/surface/compositor.zig`, `howl-render/src/surface/handle.zig`, `howl-render/src/surface/emitter.zig`, `howl-render/src/surface/resource_store.zig`, `howl-render/src/surface/realizer.zig`, `howl-render/src/surface/realizer_resource_store.zig`, `howl-render/src/surface/handle_test.zig`, `howl-render/src/surface/emitter_test.zig`, `howl-render/src/surface/realizer_test.zig`.
- Required shape: move prepared identity to `surface/prepared_surface.zig`; move CPU composition to `surface/compositor.zig`; move C handle lifetime to `surface/handle.zig`; move C surface emission to `surface/emitter.zig`; move emit-time sprite/glyph resource allocation from `prepared/sprite_resource_store.zig` to `surface/resource_store.zig`; move CPU realization from `geometry/render_surface_realizer.zig` to `surface/realizer.zig`; move the nested realizer `ResourceStore` from `geometry/render_surface_realizer.zig:17-173` to `surface/realizer_resource_store.zig`. Delete `prepared/` after imports are cut over and leave geometry owning only geometry.
- Required assertions: prepared token required base seq rules; surface dimensions nonzero; CPU pixel buffer length equals `width * height * 4` with overflow checks; base pixels length matches output length for partial composition; handle state transitions are valid; `render_surface_payload` is null before emission and null after free; resource/atlas counts stay within C ABI maxima; rollback restore exactly matches saved state.
- Required tests: preserve prepared surface identity test; add/keep tests for handle release/consume idempotence, handle belongs-to-session, emission failure mapping for each bound overflow, compositor base length assertion in test-safe form, emit-time resource store persistent/reused/transient allocation, atlas full handling, rollback/restore invariants, realizer resource create/upload/retire validation, and retained realizer resource reuse. Proof must include `zig build check`, `zig build test:unit`, and `zig build test:abi` in cwd `/home/home/personal/projects/howl/howl-render` because FFI handle files and tests import prepared/surface owners.
- Non-goals: no VT/renderable content changes; no text shaping changes; no C ABI header changes. Public API names that expose removed owner names are handled only in slice 6.
- Stop conditions: stop if any import path still contains `prepared/` after this slice; stop if `prepared` remains as a live directory after slice; stop if `geometry/render_surface_realizer.zig` remains live; stop if emitter imports `render_session.zig` for anything except owner-approved cache/resource lookup; stop if emit-time resource store and realizer resource store are merged.
- Commit receipt demand: after reviewer acceptance, record commit hash as `slice-6-prepared-surface-resource-split=<hash>`.

### Slice 7: FFI And ABI Owner Sweep

- Accountable worker session id: `coder-2026-06-13-render-api-owner-surgery-07`.
- Reviewer session id: `review-2026-06-13-render-api-owner-surgery-01`.
- Allowed files: `howl-render/src/libhowl_render.zig`, `howl-render/include/howl_render.h`, `howl-render/src/test_abi.zig`, `howl-render/src/text_session.zig`, `howl-render/src/prepare_request.zig`, `howl-render/src/prepared_surface.zig`, `howl-render/src/submission.zig`, `howl-render/src/work_state.zig`, `howl-render/src/handle.zig`, `howl-render/src/render_session.zig`, `howl-render/src/surface/handle.zig`, `howl-render/src/surface/prepared_surface.zig`, `howl-render/src/surface/emitter.zig`, `howl-render/src/text_session_test.zig`, `howl-render/src/prepare_request_test.zig`, `howl-render/src/prepared_surface_test.zig`, `howl-render/src/submission_test.zig`, `howl-render/src/test_support.zig`, `howl-linux-host/src/terminal/term.zig`, `howl-linux-host/src/terminal/vt/surface.zig`.
- Required shape: keep `libhowl_render.zig` as FFI/export translator only. Exported C names remain stable in this sprint. If a C ABI rename is still necessary after owner surgery, stop for explicit user approval and record the override before changing header, translated usage, ABI tests, or host call sites.
- Required assertions: every C handle argument checked before use; every span pointer/length pair checked before slicing; status mapping covers all internal errors; public enum values remain stable or are deliberately changed with receipt; output structs are fully initialized before returning OK.
- Required tests: run and update ABI tests for C struct sizes/enum values/exported functions/status mappings; add tests for missing handle, invalid argument, render surface emission status, prepare/submit status translation, and header translation compile. Proof must include `zig build check`, `zig build test:unit`, and `zig build test:abi` in cwd `/home/home/personal/projects/howl/howl-render`. If either listed host file changes, worker must also run the host test command named by `howl-linux-host/build.zig` for terminal/render surface tests and record the exact command and cwd.
- Non-goals: no new Zig-shaped host convenience API; no umbrella runtime; no behavior changes outside ABI translation.
- Stop conditions: stop if an ABI-breaking change is proposed without explicit user approval and recorded override; stop if host needs a Zig import into render internals.
- Commit receipt demand: after reviewer acceptance, record commit hash as `slice-7-ffi-abi-sweep=<hash>`.

### Slice 8: Final Source Order, Deletion, And Proof Sweep

- Accountable worker session id: `coder-2026-06-13-render-api-owner-surgery-08`.
- Reviewer session id: `review-2026-06-13-render-api-owner-surgery-01`.
- Allowed files: `howl-render/build.zig`, `howl-render/src/test_unit.zig`, `howl-render/src/test_abi.zig`, `howl-render/src/test/unit/root.zig`, `howl-render/src/benchmark_main.zig`, `howl-render/src/libhowl_render.zig`, `howl-render/src/text_session.zig`, `howl-render/src/prepare_request.zig`, `howl-render/src/prepared_surface.zig`, `howl-render/src/submission.zig`, `howl-render/src/work_state.zig`, `howl-render/src/handle.zig`, `howl-render/src/render_session.zig`, `howl-render/src/submitted_surface.zig`, `howl-render/src/vt_publication/abi.zig`, `howl-render/src/vt_publication/publication.zig`, `howl-render/src/storage/publication_storage.zig`, `howl-render/src/renderable_content/content.zig`, `howl-render/src/renderable_content/color.zig`, `howl-render/src/renderable_content/cursor.zig`, `howl-render/src/damage/publication_damage.zig`, `howl-render/src/prepare/queue.zig`, `howl-render/src/surface/prepared_surface.zig`, `howl-render/src/surface/compositor.zig`, `howl-render/src/surface/handle.zig`, `howl-render/src/surface/emitter.zig`, `howl-render/src/surface/resource_store.zig`, `howl-render/src/surface/realizer.zig`, `howl-render/src/surface/realizer_resource_store.zig`, `howl-render/src/surface/realizer_test.zig`, `howl-render/src/text/color.zig`, `howl-render/src/text/effects.zig`, `howl-render/src/text/metrics.zig`, `howl-render/src/text/cell_input.zig`, `howl-render/src/text/scene_contract.zig`, `howl-render/src/text/contract.zig`, `howl-render/src/text/raster/atlas.zig`, `howl-render/src/text/direct_normal.zig`, `howl-render/src/text/surface_preparer.zig`, `howl-render/src/text/shape/cluster.zig`, `howl-render/src/text/ft_hb/support.zig`, `howl-render/src/text/ft_hb/glyph_raster.zig`, `howl-render/src/text/ft_hb/support_test.zig`, `howl-render/src/test_support.zig`, `howl-render/src/text_session_test.zig`, `howl-render/src/prepare_request_test.zig`, `howl-render/src/prepared_surface_test.zig`, `howl-render/src/submission_test.zig`, `howl-render/src/surface/handle_test.zig`, `howl-render/src/surface/emitter_test.zig`.
- Required shape: delete empty compatibility wrappers, stale imports, and false directories; enforce source order inside owners; collapse formatter-resistant signatures only if under the house limit; ensure public roots curate exports only; ensure namespace wrappers aggregate owners only.
- Required assertions: audit each new owner for positive/negative-space assertions at boundaries, count/capacity assertions before slice/indexing, and pair assertions around C ABI copy-in/copy-out.
- Required tests: `zig build check`, `zig build test:unit`, and `zig build test:abi` in cwd `/home/home/personal/projects/howl/howl-render`. If `howl-linux-host/src/terminal/term.zig` or `howl-linux-host/src/terminal/vt/surface.zig` changed in slice 7, rerun the exact host test command recorded in slice 7.
- Non-goals: no new features; no renderer backend architecture expansion; no UX changes.
- Stop conditions: stop if any directory named `tv_surface`, `session`, or `prepared` remains with live render owner code; stop if `geometry/render_surface_realizer.zig` or `text/raster/cache.zig` remains live; stop if any new bucket/generic owner exists; stop if tests are weakened or duplicate roots are added.
- Commit receipt demand: after reviewer acceptance, record commit hash as `slice-8-final-proof-sweep=<hash>` and final sprint proof hash.

## Required Assertions

- VT publication boundaries assert nonzero dimensions, checked cell counts, valid C pointers for nonzero spans, span lengths matching rows/cells, codepoint and combining bounds, color kind bounds, underline style bounds, cursor shape bounds, and dirty metadata row/column bounds.
- Renderable content asserts semantic empty truth, selection/inverse color consequences, cursor visibility/blink consequences, and no out-of-grid cursor draw.
- Damage asserts full/partial/none classification preconditions, geometry epoch transitions, submitted base token compatibility, scroll/alternate screen invalidation, and canonical dirty metadata after mutation.
- Storage asserts retained capacity before exposing slices, ownership before deinit/free, no reserved slot overwrite, and refreshed retained views preserve metadata.
- Prepare queue asserts active source presence, exact token match, retry/taken state transitions, blink refresh preconditions, and retirement ordering.
- Text color/effects/metrics/input asserts semantic color kind range, effect enum stability, nonzero cell/grid metrics where required, and `CellInput.combining_len <= combining.len` before text preparation.
- Text cache asserts FT/HB cache capacities before insert, shape-run glyph storage bounds, glyph-cell cache replacement behavior, raster atlas slot bounds, and rendered-raster ownership before replacement/deinit.
- Text renderer asserts font fallback caps, scratch lengths, nonzero geometry/cell sizes, cache bounds, and submitted token monotonicity.
- Surface compositor asserts pixel length overflow checks, base/output length equality, draw bounds before indexing, sprite stride/visual bounds, and alpha/color mode stride rules.
- Surface emitter asserts every C ABI max before append, failure mapping coverage, payload lifetime, emit-time resource store rollback, and upload byte limits.
- Surface realizer asserts C resource create/upload/retire transition validity, realized resource byte bounds, upload format/resource kind validity, and retained realizer resource reuse ordering.
- FFI asserts handle presence, pointer/span validity, enum/status mapping coverage, and fully initialized C outputs.

## Required Tests

- Unit root: all owner-local tests remain reachable through exactly one render unit root.
- ABI root: all C ABI status, size, enum, and export tests remain reachable through the render ABI root.
- Slice proof commands: record exact command, cwd, result, and failures for every slice.
- Required coverage by end of sprint: invalid VT source rejection, retained publication storage ownership, renderable cell semantic mapping, cursor blink mapping, dirty damage classification, prepare queue token lifecycle, text color/effect/metrics/input owner tests, FT/HB cache bounds, raster atlas bounds, text renderer layout/font/cache bounds, prepared token identity, compositor draw bounds, surface emission bound failures, emit-time resource store reuse/transient/atlas rollback, realizer resource transition/reuse tests, C handle lifecycle, and FFI status translation.

## Risks

- The current C ABI names include `TextSession` and prepared surface handles; changing exported symbols would be ABI-breaking. Because this is a young private product, change may be allowed, but slice 7 must stop for explicit user approval if public symbol renames are proposed.
- Moving `session/text.zig` is resolved to `render_session.zig`; the risk is import churn across ABI, prepared handle, text support, and tests, not naming uncertainty.
- The emit-time resource store depends on C resource constants and text raster outputs; its final owner is `surface/resource_store.zig`. The realized resource transition store depends on C render-surface commands/uploads/retires; its final owner is `surface/realizer_resource_store.zig`. These stores must remain separate.
- Tests may currently rely on side-entry imports from old folders. Worker must move tests to owner-local files while preserving one curated root per test class.
- Host code may depend on current ABI spelling. Since there is no downstream but there is a host in repo, ABI changes must update host call sites in the same slice or stop.

## Residual Implementation Inspection

- I did not enumerate every function in `libhowl_render.zig`; slice 7 must inspect every export and status mapping before implementation.
- Cache ownership is final for this sprint: `text/ft_hb/cache.zig` owns FT/HB face/shape/glyph-cell caches, and `text/raster/atlas.zig` owns raster atlas slot/cache state after moving from `text/raster/cache.zig`.
- I did not inspect every host render call site line-by-line; slice 7 must do so if ABI names or handle types change.
- I did not run tests because this was research-only and no product code changed.

## Readiness Judgment

- Ready for reviewer gate.
- No user override is required for this plan as written because the plan follows Alacritty for renderer/content/cache/damage/storage naming pressure, Ghostty for C/VT seam isolation, TigerBeetle for ownership/assertion/test gates, and the existing Howl C ABI boundary.
- Coding is not authorized until reviewer accepts this plan and the orchestrator records the planning commit-hash receipt.
