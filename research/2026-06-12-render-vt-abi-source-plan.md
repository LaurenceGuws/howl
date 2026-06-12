Render VT ABI source-of-truth plan

Date: 2026-06-12.
Status: reviewer-accepted planning package for slice `render-vt-abi-direct-publish-first-cut`.
Role owner: researcher.
Orchestrator session id: `orch-2026-06-11-ascii-rain-honest-performance-02`.
Researcher session id: `research-2026-06-12-render-vt-abi-source-01`.
Reviewer session id: `review-2026-06-12-render-vt-abi-source-01`.
Planning commit-hash receipt: implementation commits `howl-render` `323237d` and `howl-linux-host` `f8d9898`; root accountability/submodule commit pending.

Question

- What is the first render-shape slice that stops `howl-render` from redefining VT-owned facts, consumes the `howl-vt` C ABI directly as the source of truth, and then cuts `text/contract.zig` only around facts that remain truly render-owned?

Answer

- The first slice is `render-vt-abi-direct-publish-first-cut`.
- Do not sharpen `howl-vt` ABI first. Current `howl-vt` C ABI already exports the needed surface facts through `HowlVtSurfaceResult`, `HowlVtSurface`, `HowlVtSurfaceCell`, dirty spans, cursor, colors, selection, `snapshot_seq`, `dirty_generation`, `history_count`, and `scrollback_offset`.
- The first fake mirror to delete is render/host-side VT publication redefinition: `HowlRenderSource*`, `HowlRenderVtSurfaceSlot`, host `renderCellsFromVt`, and render `Source*` ABI layout asserts. Render must publish from `HowlVtSurfaceResult` or an equivalent VT C ABI surface object, copy into render-owned retained storage internally, and keep only render-owned consequences: damage classification against submitted base, cursor blink phase policy, text shaping, atlas/resource output, render geometry, retained `rdr_sfc`, and submit readiness.

Sources Read In Order

1. `/home/home/personal/projects/howl/loop/flow.md` lines 1-137.
2. `/home/home/personal/projects/howl/loop/orcestrator.md` lines 1-61.
3. `/home/home/personal/projects/howl/loop/researcher.md` lines 1-86.
4. `/home/home/personal/projects/howl/loop/reviewer.md` lines 1-57.
5. `/home/home/personal/projects/howl/loop/coder.md` lines 1-60.
6. `/home/home/personal/projects/howl/loop/researcher.md` lines 1-86 reread.
7. `/home/home/personal/projects/howl/sprints/current.txt` lines 1-36.
8. `/home/home/personal/projects/howl/loops/render-api-pragmatic-shape-live-loop.txt` lines 1-205.
9. `/home/home/personal/projects/howl/research/2026-06-12-render-vt-abi-source-plan.md` previous seed lines 1-79.
10. `/home/home/personal/projects/howl/reference-index.md` lines 1-273.
11. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md` lines 1-260.
12. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md` lines 1-260.
13. Current `howl-render` source and header: exact anchors below.
14. Current `howl-vt` source and header: exact anchors below.
15. Current `howl-linux-host` VT-to-render publication seam: exact anchors below.
16. Ghostty C VT render/screen seams: exact anchors below.
17. Alacritty terminal/display content and damage seams: exact anchors below.

Current-Code Facts

- `howl-vt/include/howl_vt.h` already owns the C ABI surface cell flags, color, RGB, render color state, attrs, cell span, cursor, selection, surface, visible meta, and surface result. Exact lines: `HowlVtSurfaceCellFlags` lines 82-87, `HowlVtColor` lines 89-92, `HowlVtRgb8` lines 94-98, `HowlVtRenderColorState` lines 100-105, `HowlVtSurfaceCellAttrs` lines 107-118, `HowlVtSurfaceCell` lines 120-137, `HowlVtSurfaceCellSpan` lines 139-142, spans lines 144-152, `HowlVtCursor` lines 154-160, `HowlVtSelection` lines 167-179, `HowlVtSurface` lines 190-204, `HowlVtVisibleMeta` lines 206-215, and `HowlVtSurfaceResult` lines 222-229.
- `howl-vt/include/howl_vt.h` exports the exact read path render needs: `howl_vt_terminal_query_visible_meta` lines 303-306 and `howl_vt_terminal_copy_surface` lines 307-318. It also exports `howl_vt_terminal_ack_surface` at line 398.
- `howl-vt/src/ffi/surface.zig` maps true VT/screen facts to the C ABI: FFI cell/color/cursor/surface structs lines 13-135, `cellOut` lines 167-191, `surfaceResult` lines 193-222, `terminalQueryVisibleMeta` lines 259-262, and `terminalCopySurface` lines 264-312.
- `howl-vt/src/ffi/surface.zig` proves the ABI facts with owner-local tests: short-buffer metadata lines 323-338, style attrs/reset lines 340-370, visible metadata lines 372-389, render color state lines 391-411, semantic color identity lines 413-435, hyperlink snapshot validity lines 451-488, and selection projection lines 490-527.
- `howl-vt/src/terminal.zig` owns VT publication sequencing and dirty generation: `dirty_generation` and `surface_publication` fields lines 35-36, generation bumps on feed/resize/selection lines 124-137 and 239-242, `ackSurface` lines 154-160, `surfaceSnapshot` lines 162-169, and `visibleMeta` lines 171-182.
- `howl-vt/src/surface/publication.zig` owns publication sequence identity and ack validity: `Publication.publish` lines 13-33 and `Publication.canAck` lines 35-38.
- `howl-vt/src/screen_set.zig` owns viewport/cursor/grid/dirty truth: `View` fields lines 13-27, `surfaceSnapshot` lines 197-210, `copyViewCells` lines 216-226, `copyDirtyRows` lines 228-242, and `clearDirtyRows` lines 244-246.
- `howl-render/include/howl_render.h` duplicates VT-owned facts as render ABI structs: `HowlRenderSourceRgb` lines 370-374, `HowlRenderSourceColor` lines 376-382, `HowlRenderSourceCellFlags` lines 384-389, `HowlRenderSourceCellAttrs` lines 391-402, `HowlRenderSourceCell` lines 404-421, `HowlRenderSourceColors` lines 423-428, `HowlRenderSourceSelection*` lines 430-442, `HowlRenderSourceCursor` lines 444-451, `HowlRenderVtCellWriteSpan` lines 453-456, `HowlRenderVtSurfaceSlot` lines 458-463, and `HowlRenderVtSurfaceCommit` lines 465-475.
- `howl-render/include/howl_render.h` exposes a render-owned reserve/commit/reject/cancel VT publication protocol instead of taking the VT C ABI surface directly: `howl_render_text_session_reserve_vt_surface_slot` lines 545-550, `commit_vt_surface` lines 551-554, `reject_vt_surface` lines 555-558, and `cancel_vt_surface` line 559.
- `howl-render/src/tv_surface/vt.zig` duplicates VT cell/color/cursor/selection/grid/dirty facts internally: `SourceRgb` lines 7-11, `SourceColor` lines 13-19, `SourceColors` lines 21-26, `SourceCellFlags` lines 28-33, `SourceCellAttrs` lines 35-46, `SourceCell` lines 48-65, selection lines 67-79, cursor lines 81-88, `VtSnapshot` lines 90-101, and `PublicationSource` lines 103-120.
- `howl-render/src/tv_surface/vt.zig` currently validates render-local VT duplicates rather than VT ABI symbols: cell validation lines 194-204, source cell slice validation lines 206-208, source color validation lines 214-220, underline style validation lines 223-225, and publication boundary validation lines 227-239.
- `howl-render/src/tv_surface/cell.zig` is a second internal VT mirror with non-ABI cell/color/attrs/cursor/grid/damage/surface types: lines 1-92. This is fake for the active VT C ABI surface path except any remaining tests or internal mapper compatibility during the slice.
- `howl-render/src/ffi/vt_surface.zig` bridges render-local ABI mirrors into render-local structs, including `reserveVtSurfaceSlot` lines 13-21, `commitVtSurface` lines 23-42, `vtSurfaceSlotOut` lines 66-72, source cell spans lines 75-77, source metadata conversion lines 94-131, and layout asserts that compare render mirror structs to render header mirror structs lines 133-203.
- `howl-render/src/tv_surface/slot.zig` owns render-side retained storage for duplicated `source_vt.SourceCell` and dirty arrays: `VtSurfaceSlot` lines 6-11, `RetainedSlot` fields lines 13-20, allocation lines 29-51, and retained source creation lines 143-162. This storage is render-owned, but its element type and slot API are fake VT mirroring.
- `howl-render/src/tv_surface/prepare_request.zig` keeps render-owned publication sequencing/damage classification around `PublicationSource`: publication state lines 14-24, `PrepareRequests` fields lines 37-42, accept/canonicalize/classify lines 55-96, prepare consumption lines 123-127, latest token lines 129-141, cursor blink refresh lines 166-182, and classification rules lines 270-294. The damage classification consequence is render-owned; the source data shape is not.
- `howl-render/src/session/text.zig` accepts `source_vt.PublicationSource` as `PrepareInput.state` lines 166-171, prepares from publication cells/colors/cursor/damage lines 220-270, reserves and commits VT surface through render-local source slot lines 600-610, and mutates cursor blink phase in retained publication sources at lines 589-596.
- `howl-render/src/text/contract.zig` contains both true render-owned shapes and VT mirrors. True render-owned examples: font/raster/scene/output shapes lines 29-90 and 114-325, `TextScene` lines 327-335. Mirrored VT input facts: `SemanticColor` lines 10-19, `UnderlineStyle` lines 21-27, `CellInput` lines 92-112, and duplicated fields in `RenderableCell` lines 136-155.
- `howl-render/src/tv_surface/publication_cell_map.zig` owns the render consequence of mapping VT ABI surface facts into render text input: theme from VT colors lines 22-31, publication cell mapping lines 33-66, semantic empty classification lines 81-92 and 186-195, inverse/selection style consequences lines 94-110, and cursor draw mapping lines 112-121. This file currently imports render-local `source_vt` mirrors, but the behavior is render-owned mapping.
- `howl-render/src/tv_surface/text_input.zig` still has legacy `source_cell.Cell` conversion paths lines 175-209 and 385-432 plus the active publication conversion path lines 302-383. The active publication path converts render-local `SourceCell` rather than `HowlVtSurfaceCell`.
- `howl-render/src/text/direct_normal.zig` direct-fast-path reads `source_vt.SourceCell` directly: source union lines 46-57, publication candidate lines 249-274, cell support rules lines 276-290, renderable conversion lines 292-335, color rules lines 343-367, and span logic lines 376-381. The fast-path consequence is render-owned; its source type is a mirror.
- `howl-linux-host/src/terminal/vt/surface.zig` is the clearest fake mirror seam. It queries VT meta lines 68-79, reserves a render VT slot lines 68-70 and 204-218, copies VT cells into host VT scratch lines 220-258, then copies every VT cell/attr/color/cursor/color-state/selection into render ABI mirror structs lines 272-363.
- `howl-linux-host/src/terminal/vt/surface.zig` also owns a host UX overlay: hyperlink hover state lines 9-13 and `applyHyperlinkHover`/`markDirtyRange` lines 379-414. This is not VT truth; it is host-owned visual overlay and may mutate a copied `HowlVtSurfaceCell` scratch buffer before publishing to render, but must not require `HowlRenderSource*`.
- `howl-linux-host/src/terminal/term.zig` already stores VT ABI-shaped scratch cells as `[]vt_c.HowlVtSurfaceCell` lines 35-45 and allocates them through `ensureSurfaceCellScratch` lines 52-64. The host does not need render cell scratch if render accepts VT ABI shape.
- `howl-render/build.zig` already adds `../howl-vt/include` to render test, ABI, FFI, and benchmark modules lines 49-50, 65-66, 97-98, and 119-120. No `howl-vt` ABI header availability blocker exists for render C import.

Reference Facts

- Ghostty C VT render state is explicitly the C-facing renderable VT surface seam. `include/ghostty/vt/render.h` says render state represents the visible terminal screen/viewport lines 22-27, update reads a terminal instance and then renderers read the render state lines 29-40, and dirty tracking is global plus per-row lines 42-59.
- Ghostty exposes VT-owned render data through C ABI query kinds, not by asking renderers to redefine cells. `GhosttyRenderStateData` includes cols/rows/dirty/row iterator/colors/cursor facts lines 121-191 in `include/ghostty/vt/render.h` and equivalent Zig enum/data mapping lines 81-118 in `src/terminal/c/render.zig`.
- Ghostty C API keeps cursor facts in the VT render-state seam: visual style/visible/blinking/viewport fields are documented in `include/ghostty/vt/render.h` lines 163-189 and implemented in `src/terminal/c/render.zig` lines 256-271.
- Ghostty C screen cell is opaque in the C ABI and queried through accessor APIs, which pressures Howl against duplicating owned VT cell shapes in render. `include/ghostty/vt/screen.h` says `GhosttyCell` is an opaque value and fields must be queried through `ghostty_cell_get` lines 31-40; the query enum for content/tag/wide/style/hyperlink facts is lines 125-208. `src/terminal/c/cell.zig` implements the same accessor model lines 36-100 and 102-169.
- Ghostty C render update implementation reads terminal state into a render state object through `render_state_update` lines 171-180 in `src/terminal/c/render.zig`; row/cell iterators are backed by render state rows/cells/dirty slices lines 25-39 and 231-247. This supports an explicit ABI-owned surface/read state instead of parallel render-local VT structs.
- Alacritty terminal owns renderable terminal content: `alacritty_terminal/src/term/mod.rs` exposes `Term::renderable_content` lines 637-642 and `RenderableContent` carries grid iterator, selection, cursor, display offset, colors, and mode lines 2393-2412.
- Alacritty display consumes terminal content and converts it into renderable cells: `alacritty/src/display/content.rs` imports `RenderableContent as TerminalContent` lines 10-13, constructs it with `term.renderable_content()` line 49, and `RenderableContent` stores terminal content plus display/render policy fields lines 24-38. Iteration skips empty/wide spacer cells and applies cursor consequences lines 153-184.
- Alacritty keeps renderer/content consequences separate from terminal damage truth. Terminal damage types live in `alacritty_terminal/src/term/mod.rs` lines 137-184. Display damage tracking converts terminal damaged lines into viewport damage rects in `alacritty/src/display/damage.rs` lines 92-103 and 215-274. This supports Howl keeping render-owned damage classification/rect realization while sourcing VT dirty rows from VT ABI.
- TigerBeetle style demands assertions and no duplicate fact ownership: assert arguments/invariants lines 104-140 in `TIGER_STYLE.md`, bounded loops and limits lines 90-102, smallest possible scope lines 158-176, and zero technical debt lines 62-79. `ARCHITECTURE.md` reinforces explicit bounds/static allocation as a forcing function lines 189-222.

Compact Anchor Map

`howl-vt` ABI anchors:

- `howl-vt/include/howl_vt.h` lines 82-204: VT-owned C ABI surface facts.
- `howl-vt/include/howl_vt.h` lines 222-229: `HowlVtSurfaceResult` packages snapshot/dirty/source facts.
- `howl-vt/include/howl_vt.h` lines 303-318: query/copy visible surface API.
- `howl-vt/include/howl_vt.h` line 398: VT ack API.
- `howl-vt/src/ffi/surface.zig` lines 193-222 and 264-312: VT FFI implementation that populates the C ABI surface result.
- `howl-vt/src/ffi/surface.zig` lines 323-527: VT ABI tests proving metadata, styles, colors, hyperlinks, and selection.

`howl-render` mirror anchors:

- `howl-render/include/howl_render.h` lines 370-475: render-local `HowlRenderSource*` and VT slot/commit mirrors.
- `howl-render/include/howl_render.h` lines 545-559: render-local reserve/commit/reject/cancel publication protocol.
- `howl-render/src/tv_surface/vt.zig` lines 7-120: internal duplicated VT source facts.
- `howl-render/src/ffi/vt_surface.zig` lines 13-203: FFI mirror translation and layout asserts.
- `howl-render/src/tv_surface/slot.zig` lines 6-162: retained storage currently typed as render-local VT source.
- `howl-render/src/tv_surface/prepare_request.zig` lines 55-127 and 270-294: render-owned damage/publication consequence around mirrored source.
- `howl-render/src/text/contract.zig` lines 92-155: VT-shaped render input mirrors mixed with render-owned text consequences.

Host mirror anchors:

- `howl-linux-host/src/terminal/vt/surface.zig` lines 68-87: host asks VT, reserves render slot, acquires VT, commits render mirror.
- `howl-linux-host/src/terminal/vt/surface.zig` lines 204-218: render slot reservation.
- `howl-linux-host/src/terminal/vt/surface.zig` lines 220-270: VT copy into host scratch and visible copy.
- `howl-linux-host/src/terminal/vt/surface.zig` lines 272-363: explicit VT-to-render mirror conversion functions to delete.
- `howl-linux-host/src/terminal/vt/surface.zig` lines 379-414: host-owned hover overlay to preserve using VT ABI-shaped scratch.
- `howl-linux-host/src/terminal/term.zig` lines 35-64: existing VT ABI cell scratch.

Reference seam anchors:

- Ghostty `include/ghostty/vt/render.h` lines 22-59 and 121-191: C-facing render state owns visible VT facts and dirty/cursor/color queries.
- Ghostty `src/terminal/c/render.zig` lines 171-180 and 225-276: update from terminal, then query render state facts.
- Ghostty `include/ghostty/vt/screen.h` lines 31-40 and 125-208: opaque VT cell C surface and accessor query pattern.
- Alacritty `alacritty_terminal/src/term/mod.rs` lines 637-642 and 2393-2412: terminal owns renderable content.
- Alacritty `alacritty/src/display/content.rs` lines 24-38, 49, and 153-184: display consumes terminal content and applies render cursor/empty-cell consequences.
- Alacritty `alacritty/src/display/damage.rs` lines 92-103 and 215-274: display converts terminal damage into render damage rectangles.

Owner Roles And Proposed Shape

- `howl-vt` owns cells, semantic colors, palette/default colors, cursor row/col/shape/blink visibility fact, selection projection, grid rows/cols, scroll row, history count, alternate-screen flag, snapshot sequence, dirty generation, dirty row spans, and ack validity.
- `howl-render` owns the publication consequence after receiving a VT C ABI surface: copy/retain the borrowed VT surface for async prepare, classify full/partial/none against prior publication, invalidate on geometry/cursor presentation/color/scroll/alt/grid changes, apply cursor blink phase policy, map VT cells/colors/cursor to text/render consequences, shape/rasterize text, emit `rdr_sfc`, and validate submit readiness.
- `howl-linux-host` owns when to query VT, host-side scrollback offset, hover overlay, event loop cadence, wake/presentation, and ack choreography. It must stop translating VT structs into render-owned mirror structs.
- The first API shape should be a render C ABI publish entrypoint that accepts VT ABI surface data directly. Exact proposed public seam:
  - Add `#include <howl_vt.h>` to `howl-render/include/howl_render.h`.
  - Replace reserve/commit/reject/cancel with `HowlRenderVtSurfacePublishResult howl_render_text_session_publish_vt_surface(HowlRenderTextSessionHandle handle, const HowlVtSurfaceResult *vt_surface);`
  - The caller passes a `HowlVtSurfaceResult` returned from `howl_vt_terminal_copy_surface`; render rejects non-OK VT status, missing handle, null pointer, zero rows/cols, invalid spans, invalid `snapshot_seq`, invalid `dirty_generation`, invalid dirty metadata, and invalid cell fields.
  - Render copies the borrowed VT surface into its retained source storage before returning. No pointer from `HowlVtSurfaceResult` may be retained.
  - Delete render ABI structs `HowlRenderSource*`, `HowlRenderVtCellWriteSpan`, `HowlRenderVtSurfaceSlot`, and `HowlRenderVtSurfaceCommit` in the same slice; there is no downstream compatibility need.
  - Internally, rename or reshape only what is touched enough to make the source type obviously VT ABI-shaped. Full `text/contract.zig` cleanup is not in the first slice.

Fake Render-Local VT Mirrors Versus True Render-Owned Consequences

- Fake mirrors to remove in first slice: `HowlRenderSourceRgb`, `HowlRenderSourceColor`, `HowlRenderSourceCellFlags`, `HowlRenderSourceCellAttrs`, `HowlRenderSourceCell`, `HowlRenderSourceColors`, `HowlRenderSourceSelection*`, `HowlRenderSourceCursor`, `HowlRenderVtCellWriteSpan`, `HowlRenderVtSurfaceSlot`, `HowlRenderVtSurfaceCommit`, `source_vt.Source*` layout asserts against render header mirror structs, and host conversion functions from `HowlVt*` to `HowlRenderSource*`.
- Fake mirrors to quarantine or delete if touched: `tv_surface/cell.zig` `Cell`, `GridModel`, `DamageInfo`, `ViewportInfo`, `CursorInfo`, and `SurfaceData`; legacy `vtStateTo*` conversion paths that consume generic `state.grid.cells` instead of VT ABI cells.
- True render-owned consequences to keep: `SurfaceTheme` as resolved render colors, semantic empty classification for render draw suppression, inverse/selection color application for rendering, cursor draw input after blink phase, damage classification for retained render output, geometry tokens, prepared/rdr_sfc handles, text shaping/raster/atlas state, and render surface emission.
- Host-owned consequence to keep outside VT truth: hyperlink hover underline overlay. It may mutate the host's copied `HowlVtSurfaceCell` scratch and dirty arrays before publishing to render because that is host UX overlay, not a new VT fact.

Sprint Scratchpad

- The first slice is a seam cut, not a whole renderer rewrite.
- `howl-vt` ABI is sufficient for the first cut; no ABI sharpening blocker.
- The host already has `HowlVtSurfaceCell` scratch; use it and stop allocating/render-reserving `HowlRenderSourceCell` scratch.
- Render build already has `../howl-vt/include` include paths, so adding `#include <howl_vt.h>` to render header is build-supported.
- Keep the old render internal retained storage if needed, but type it from VT ABI structs, not render mirror structs.
- Do not import `howl-vt` Zig internals from render or host.
- Do not let `text/contract.zig` become the new owner of VT facts. Only adapt mapping functions enough to consume VT ABI cell structs.
- Do not leave old public `HowlRenderSource*` in the shipped render header after the first slice.

Ordered Slice Plan

1. Slice id: `render-vt-abi-direct-publish-first-cut`.

Allowed files:

- `howl-render/include/howl_render.h`
- `howl-render/src/ffi/vt_surface.zig`
- `howl-render/src/ffi/vt_surface_test.zig`
- `howl-render/src/ffi/test_support.zig`
- `howl-render/src/libhowl_render.zig`
- `howl-render/src/tv_surface/vt.zig`
- `howl-render/src/tv_surface/slot.zig`
- `howl-render/src/tv_surface/prepare_request.zig`
- `howl-render/src/tv_surface/damage.zig`
- `howl-render/src/tv_surface/publication_cell_map.zig`
- `howl-render/src/tv_surface/text_input.zig`
- `howl-render/src/text/direct_normal.zig`
- `howl-render/src/session/text.zig`
- `howl-render/src/session/text_test.zig`
- `howl-render/src/benchmark_main.zig` only for compile fallout from source type rename/removal, not benchmark redesign.
- `howl-render/src/test_abi.zig` only if ABI deleted-symbol checks live there.
- `howl-linux-host/build.zig` only to add `howl_vt_include` to the `howl_render_c` translate-C include paths if host translated-C cannot find `howl_vt.h` through `howl_render.h`.
- `howl-linux-host/src/terminal/vt/surface.zig`
- `howl-linux-host/src/terminal/term.zig` only if render-cell scratch removal requires it.
- `howl-linux-host/src/terminal/render/retained.zig` only for tests that still publish test sources through the old render slot.

Required shape:

- Public render header includes `howl_vt.h` and exposes one VT publication entrypoint: `howl_render_text_session_publish_vt_surface(HowlRenderTextSessionHandle handle, const HowlVtSurfaceResult *vt_surface)`.
- Delete public render ABI definitions for `HowlRenderSourceRgb`, `HowlRenderSourceColor`, `HowlRenderSourceCellFlags`, `HowlRenderSourceCellAttrs`, `HowlRenderSourceCell`, `HowlRenderSourceColors`, `HowlRenderSourceSelectionPos`, `HowlRenderSourceSelection`, `HowlRenderSourceCursor`, `HowlRenderVtCellWriteSpan`, `HowlRenderVtSurfaceSlot`, and `HowlRenderVtSurfaceCommit`.
- Delete public render entrypoints `howl_render_text_session_reserve_vt_surface_slot`, `howl_render_text_session_commit_vt_surface`, `howl_render_text_session_reject_vt_surface`, and `howl_render_text_session_cancel_vt_surface`.
- `ffi/vt_surface.zig` accepts `c.HowlVtSurfaceResult` or pointer to it from translated C, validates status/shape, and converts only at the FFI translation boundary into an internal retained publication source. It must no longer assert layout against `HowlRenderSource*` types.
- Internal retained storage may use a render-local owner type, but its source fields must be obviously sourced from VT ABI. Prefer `VtSurfaceCell = c.HowlVtSurfaceCell`/equivalent imported C ABI type if compile shape allows; otherwise a single internal copy struct is allowed only as render-owned retained storage, not a public ABI mirror, and must be named as retained publication storage rather than `Source*` ABI.
- Render must copy `HowlVtSurfaceResult.source.surface_cells`, `dirty_rows`, `dirty_cols_start`, and `dirty_cols_end` before returning from publish. It must not retain host/VT pointers.
- `TextSessionOwner` no longer reserves or cancels VT slots. It has one publish method that accepts a copied VT ABI surface result and enqueues prepare work.
- Host `publishSourceLockedWith` queries visible meta if still useful, obtains/copies `HowlVtSurfaceResult` using host `HowlVtSurfaceCell` scratch and dirty scratch, applies hover overlay to that VT ABI-shaped scratch, and calls `howl_render_text_session_publish_vt_surface` directly. It no longer calls render reserve/commit/reject/cancel and no longer has `renderCellsFromVt`, `renderCellFromVt`, `renderCellAttrsFromVt`, `renderColorFromVt`, `renderCursorFromVt`, `renderColorsFromVt`, `renderRgbFromVt`, `renderSelectionFromVt`, or `renderSelectionPosFromVt`.
- Host reject path for a failed VT copy becomes no-op or a local failed publish result without mutating render, because render has no reserved slot to cancel.
- Hover overlay remains host-owned but mutates `vt_c.HowlVtSurfaceCell` scratch/dirty arrays, not render source cells.

Required tests:

- Run `cd /home/home/personal/projects/howl/howl-render && zig build test`.
- Run `cd /home/home/personal/projects/howl/howl-linux-host && zig build test`.
- Add/update render ABI tests proving `howl_render_text_session_publish_vt_surface` accepts a valid `HowlVtSurfaceResult` and produces a prepare request with the VT `snapshot_seq` and `dirty_generation`.
- Add/update render ABI tests proving invalid VT surface inputs are rejected: null pointer, non-OK VT status, zero `snapshot_seq`, zero `dirty_generation`, cells span length not equal `rows * cols`, dirty span length mismatch, invalid dirty row byte, invalid dirty col range, invalid codepoint, invalid combining length, invalid color kind/value, invalid underline style.
- Add/update render tests proving no public `HowlRenderSource*`, `HowlRenderVtSurfaceSlot`, or `HowlRenderVtSurfaceCommit` symbol/type remains reachable through `howl_render.h` translation. If the existing test style checks deleted ABI absence with compile failures, use that. Otherwise add a positive translated-C test that uses `HowlVtSurfaceResult` through `howl_render.h` and no render source mirror types.
- Add/update host tests proving `publishSourceLockedWith` no longer calls render reserve/commit/reject and publishes the VT ABI surface result directly.
- Add/update host test proving hyperlink hover overlay still underlines matching copied VT cells and marks dirty spans before direct publish.
- Preserve existing submit/prepare/rdr_sfc tests from the previous slice.

Non-goals:

- No `howl-vt` Zig internal import from render or host.
- No `howl-vt` ABI sharpening in this slice unless implementation proves a missing fact despite this research. If that happens, stop and return to planning.
- No whole `text/contract.zig` rewrite.
- No renderer algorithm rewrite, direct-normal optimization, atlas redesign, geometry redesign, or presentation/host runtime redesign.
- No compatibility aliases or deprecated wrappers for removed render source mirror ABI types/functions.
- No new umbrella runtime layer.
- No C ABI shortcut that redefines `HowlVt*` structs under `HowlRender*` names.

Stop conditions:

- Stop if `howl_render.h` cannot include or name `HowlVtSurfaceResult` without a build-system or package dependency decision from the orchestrator.
- Stop if render needs a VT fact not present in `HowlVtSurfaceResult`/`HowlVtSurface`/`HowlVtSurfaceCell`; the correct next move then becomes a `howl-vt` ABI sharpening slice, not render-local mirroring.
- Stop if the implementation would retain pointers into host/VT scratch after `publish_vt_surface` returns.
- Stop if any public render ABI `HowlRenderSource*` or `HowlRenderVtSurfaceSlot` type remains after the slice.
- Stop if hover overlay cannot be expressed as host mutation of a copied VT ABI-shaped scratch surface.
- Stop if tests require weakening ABI or unit roots.
- Stop if translated-C include ordering forces any host C import wrapper edit; ask orchestrator to reseed exact allowed include-file changes instead of touching wrappers in this slice.

Receipt fields required for execution handoff:

- Orchestrator session id: `orch-2026-06-11-ascii-rain-honest-performance-02`.
- Researcher session id: `research-2026-06-12-render-vt-abi-source-01`.
- Reviewer session id: `review-2026-06-12-render-vt-abi-source-01`.
- Coder session id: pending orchestrator seed.
- Slice id: `render-vt-abi-direct-publish-first-cut`.
- Commit-hash handoff status: pending until execution accepted and committed.
- Verification receipts: exact `howl-render` and `howl-linux-host` `zig build test` command output summaries.
- ABI receipt: deleted render mirror symbols/types verified absent and direct `HowlVtSurfaceResult` publish verified present.

2. Slice id: `render-contract-vt-input-name-cleanup`.

Allowed files:

- To be reviewer-planned after slice 1 lands; expected area is `howl-render/src/text/contract.zig`, `howl-render/src/tv_surface/publication_cell_map.zig`, `howl-render/src/tv_surface/text_input.zig`, `howl-render/src/text/direct_normal.zig`, `howl-render/src/text/shape/cluster.zig`, and tests.

Required shape:

- Split or rename only the touched VT input conversion shapes so `text/contract.zig` does not present VT facts as render-owned facts. Keep render-owned `RenderableCell`, glyph/raster/scene outputs, and text shaping contracts.

Non-goal:

- Not authorized until the direct VT ABI publish seam is accepted.

Required Assertions

- In render publish FFI: assert or validate `vt_surface != null`, status equals `HOWL_VT_CALL_OK`, `snapshot_seq != 0`, `dirty_generation != 0`, `source.rows > 0`, `source.cols > 0`, `source.surface_cells.ptr != null`, and `source.surface_cells.len == rows * cols`.
- In render publish FFI: validate dirty span pointers are non-null and lengths equal `rows`.
- In render publish FFI: validate dirty row bytes are only 0 or 1 and dirty column spans follow the existing sentinel/range contract from `howl-render/src/tv_surface/damage.zig` lines 5-21.
- In render copy path: assert copied cell count and dirty row count equal source counts after allocation/copy.
- In render retained publication: assert no borrowed `HowlVtSurfaceResult` pointer or host scratch pointer is stored.
- In damage classification: keep assertions that dirty span lengths match rows before classifying, equivalent to current `damage.zig` lines 86-89.
- In host publish path: assert `HowlVtSurfaceResult.source.rows/cols` match queried visible meta when meta is used, surface cell span equals `rows * cols`, and scrollback offset does not exceed history count.
- In host hover overlay: assert computed hover indices and dirty row indices stay within copied VT scratch spans before mutation.
- Compile-time or ABI tests must prove `howl_render.h` sees `HowlVtSurfaceResult` from `howl_vt.h` rather than redefining it.

Required Tests

- `cd /home/home/personal/projects/howl/howl-render && zig build test`.
- `cd /home/home/personal/projects/howl/howl-linux-host && zig build test`.
- Render unit/ABI valid direct publish from `HowlVtSurfaceResult`.
- Render unit/ABI invalid direct publish cases listed in slice 1.
- Host direct publish flow with no render reserve/commit/reject calls.
- Host hover overlay with VT ABI-shaped copied cells.
- Deleted render mirror ABI absence.
- Existing VT ABI tests remain unchanged; this slice should not require `howl-vt` edits.

Risks

- `howl_render.h` including `howl_vt.h` creates an explicit C header dependency from render to VT. This is aligned with the user's direction to use the VT ABI directly, and render build already has the include path, but reviewer should gate the ABI dependency explicitly.
- If translated-C in `howl-linux-host` does not expose `HowlVtSurfaceResult` through `howl_render_c` because of include ordering, the worker must stop. Host C import wrapper edits are not allowed in this slice without a new orchestrator seed.
- The stopped implementation proved the exact include-path fallout: `howl_render_c` translation needs the VT include path because `howl_render.h` now includes `howl_vt.h`. The only authorized fallout is adding `howl_vt_include` to that translate-C module in `howl-linux-host/build.zig`; wrapper header edits remain disallowed.
- Deleting public render mirror types is source-breaking. This project is private and has no downstream, and the user explicitly wants the mirror gone.
- Host hover overlay mutates copied VT ABI cells. This must remain host-owned UX overlay, not VT source truth; tests must prove no VT internals are mutated.
- Internal render retained storage may still look like a VT copy after slice 1. That is acceptable only as private retained storage copied from the VT ABI and should be pressure-cleaned in the next contract cleanup slice.
- `text/contract.zig` still contains VT-shaped `CellInput` facts after slice 1. That is a known next slice, not a blocker for direct ABI source-of-truth if public/render seam mirrors are deleted.

Proof Gaps

- I did not run builds or tests; this is research-only.
- I did not inspect every test helper that may mention `HowlRenderSource*`; worker must search exact symbols before editing.
- I did not prove whether Zig translate-C exposes `HowlVtSurfaceResult` through `howl_render_c` when `howl_render.h` includes `howl_vt.h`; first worker compile will prove this. Stop condition covers failure.
- I did not plan a complete `text/contract.zig` split because the first source-backed slice is the ABI seam and host conversion deletion.

Readiness Judgment

- Ready for reviewer gate.
- Reviewer can gate slice `render-vt-abi-direct-publish-first-cut` now if they accept the explicit render header dependency on `howl_vt.h` as the direct C ABI source-of-truth boundary.
- No user-needed blocker is present from the research. The correct first move is not `howl-vt` ABI sharpening because existing VT ABI facts cover render's current input needs.
