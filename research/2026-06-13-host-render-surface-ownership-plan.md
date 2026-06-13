# Host Render Surface Ownership Plan

Date: 2026-06-13.

Status: accepted planning package; Slice 1 ready for execution seeding.

Role owner: researcher.

Orchestrator session id: `orch-2026-06-13-host-render-surface-01`.

Researcher session id: `research-2026-06-13-host-render-surface-01`.

Reviewer session id: `review-2026-06-13-host-render-surface-01`.

Planning acceptance commit-hash receipt: `455402d` `Accept host render-surface planning`.

Question:

- What is the highest-value source-backed host ownership compression sprint for the current host/render boundary concentration, starting with `howl-linux-host/src/display/render_surface.zig`, and what exact sequential execution slices does that require without inventing new runtime layers or moving render/host truth across the boundary?

## Sources Read In Order

1. `loop/flow.md:1-137`
2. `loop/orcestrator.md:1-61`
3. `loop/researcher.md:1-86`
4. `loop/reviewer.md:1-57`
5. `loop/coder.md:1-60`
6. `loop/researcher.md:1-86` reread as the active role contract
7. `sprints/current.txt:1-57`
8. `loops/host-render-surface-ownership-live-loop.txt:1-77`
9. `research/2026-06-13-host-render-surface-ownership-plan.md:1-361` rejected artifact under repair
10. `reference-index.md:1-273`
11. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:1-400`
12. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:1-400`
13. `sprints/2026-06-13-host-render-surface-ownership-sprint.md:1-67`
14. `howl-linux-host/src/display/render_surface.zig:1-1175`
15. `howl-linux-host/src/display/render_surface_test.zig:1-415`
16. `howl-linux-host/src/terminal/surface.zig:1-760`
17. `howl-linux-host/src/host_test_root.zig:1-14`
18. `howl-render/src/text/shape/cluster.zig:1-260`
19. `howl-render/src/text/scene.zig:1-400`
20. `howl-render/src/surface/emitter.zig:1-360`
21. `howl-vt/src/parser.zig:1-420`
22. `howl-linux-host/src/display/display.zig:1-260`
23. `howl-linux-host/src/display/window.zig:1-222`
24. `howl-linux-host/src/display/present.zig:1-260`
25. `howl-linux-host/src/event.zig:430-549`
26. `howl-linux-host/build.zig:260-369`
27. `howl-linux-host/src/terminal/render_retained.zig:200-279`
28. `howl-render/include/howl_render.h:220-479`
29. `howl-render/src/surface/realizer_resource_store.zig:1-176`
30. `howl-render/src/surface/realizer.zig:45-324`
31. `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:1-320`
32. `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:540-1179`
33. `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:1-320`
34. `utils/dev_references/terminals/alacritty/alacritty/src/display/damage.rs:1-260`
35. `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs:1-320`
36. `utils/dev_references/terminals/alacritty/alacritty/src/event.rs:1-320`
37. `utils/dev_references/terminals/alacritty/alacritty/src/renderer/mod.rs:1-320`

## Exact Files And Line References

- `sprints/2026-06-13-host-render-surface-ownership-sprint.md:39-44`
- `howl-linux-host/src/display/render_surface.zig:34-272`
- `howl-linux-host/src/display/render_surface.zig:274-295`
- `howl-linux-host/src/display/render_surface.zig:297-419`
- `howl-linux-host/src/display/render_surface.zig:421-490`
- `howl-linux-host/src/display/render_surface.zig:492-810`
- `howl-linux-host/src/display/render_surface.zig:812-1134`
- `howl-linux-host/src/display/render_surface.zig:1136-1175`
- `howl-linux-host/src/display/render_surface_test.zig:55-415`
- `howl-linux-host/src/terminal/surface.zig:107-128`
- `howl-linux-host/src/terminal/surface.zig:188-209`
- `howl-linux-host/src/terminal/surface.zig:575-681`
- `howl-linux-host/src/host_test_root.zig:9-14`
- `howl-render/src/text/shape/cluster.zig:13-170`
- `howl-render/src/text/shape/cluster.zig:172-260`
- `howl-render/src/text/scene.zig:40-98`
- `howl-render/src/text/scene.zig:100-172`
- `howl-render/src/text/scene.zig:182-313`
- `howl-render/src/surface/emitter.zig:27-183`
- `howl-render/src/surface/emitter.zig:233-360`
- `howl-vt/src/parser.zig:17-55`
- `howl-vt/src/parser.zig:230-420`
- `howl-linux-host/src/display/display.zig:122-156`
- `howl-linux-host/src/display/present.zig:38-87`
- `howl-render/include/howl_render.h:220-317`
- `howl-render/include/howl_render.h:361-391`
- `howl-render/src/surface/realizer_resource_store.zig:11-176`
- `howl-render/src/surface/realizer.zig:45-324`
- `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs:47-70`
- `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:341-398`
- `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:647-768`
- `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:775-1046`
- `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:24-88`
- `utils/dev_references/terminals/alacritty/alacritty/src/display/damage.rs:12-73`
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/mod.rs:89-279`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:90-100`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:109-149`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:161-176`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:315-332`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:94-101`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:208-222`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:277-279`

## Current-Code Facts

### `render_surface.zig` Burden

- `render_surface.zig` is the only production host GL realization choke point for prepared render surfaces. `terminal/surface.zig` calls `term_texture.uploadRenderSurface(&self.render_surface_textures, &self.term_texture, render_surface, upload_stats)` from `ContextSubmitBackend.upload` (`howl-linux-host/src/terminal/surface.zig:625-633`).
- The same file owns retained resource state and mutation through `RenderResourceTextures`, including slot lifecycle, transition simulation, GL create/upload/retire, and retained upload metadata (`howl-linux-host/src/display/render_surface.zig:34-272`).
- The same file owns upload orchestration through `ensureSurface` and `uploadRenderSurface` (`howl-linux-host/src/display/render_surface.zig:421-490`).
- The same file owns render-surface command grammar and draw execution: class classification, patch/full validation, fill upload staging, framebuffer draw setup, sprite draw, glyph draw, quad emission, timing counters, and future-upload visibility checks (`howl-linux-host/src/display/render_surface.zig:297-419`, `492-1134`).
- The same file carries a test facade for resource, command, fill staging, coordinate, and validation internals (`howl-linux-host/src/display/render_surface.zig:1136-1175`).

### Direct Proof Roots

- `render_surface_test.zig` proves the exact host grammar and retained resource facts: fill/fill-patch classification, fill staging bounds, sprite grammar, sprite upload coverage, future upload visibility, glyph grammar, invalid-shape rejection, and persistent live-slot validation (`howl-linux-host/src/display/render_surface_test.zig:55-415`).
- `terminal/surface_test.zig` is required as integration proof because the submit caller unlocks during upload and depends on retry/zeroing semantics around `uploadRenderSurface` (`howl-linux-host/src/terminal/surface.zig:646-681`).
- `host_test_root.zig` already imports both proof roots and does not require wiring for new sibling implementation files when the public import path remains `display/render_surface.zig` (`howl-linux-host/src/host_test_root.zig:9-14`).

### Ranked Fallback Comparison

- Ranked fallback 1, `howl-render/src/text/shape/cluster.zig`, does not preempt the host cut. It has multiple ownership pressures around owned line text, owned renderable cells, cluster scratch, and input assembly (`cluster.zig:13-170`, `172-260`), but it is render-side shaping work, not the active host/render GL realization seam. The active sprint is explicitly host ownership pressure, and `render_surface.zig` is the only host GL prepared-surface realization choke point (`sprints/2026-06-13-host-render-surface-ownership-sprint.md:24-44`, `howl-linux-host/src/terminal/surface.zig:625-633`).
- Ranked fallback 2, `howl-render/src/text/scene.zig`, does not preempt the host cut. It already has recent child-owner pressure in `scene_damage` and `scene_rects`, and the remaining root still coheres around text-scene construction and retained scratch (`scene.zig:40-98`, `100-172`, `182-313`). It is not the host boundary where GL resources are realized from the C render surface.
- Ranked fallback 3, `howl-linux-host/src/terminal/surface.zig`, does not preempt the host cut. It is the runtime caller and submit control spine, with texture state fields and the upload call at `107-112`, `188-194`, and `625-633`, but the GL resource mutation and command execution it calls are inside `render_surface.zig`. Moving GL resource realization into `terminal/surface.zig` would broaden runtime ownership and fight Alacritty’s split between window/runtime aggregate and display/renderer child owners.
- Ranked fallback 4, `howl-render/src/surface/emitter.zig`, does not preempt the host cut. It is render-side publication of the C surface with explicit bounded command/resource arrays and timing (`emitter.zig:233-360`); the host still independently validates and realizes that ABI payload into GL textures (`render_surface.zig:34-490`, `492-1134`). Emitter cleanup would not remove the host mixed owner.
- Ranked fallback 5, `howl-vt/src/parser.zig`, does not preempt the host cut. It has VT parser ownership around bounded CSI/string-control state and actions (`parser.zig:17-55`, `230-420`), but VT shape follows Ghostty and is outside the host/render GL realization seam chosen by the sprint.

Decision: the ranked fallbacks were read and do not outrank `howl-linux-host/src/display/render_surface.zig` for this sprint.

## Reference Facts

- Alacritty’s `WindowContext` owns one window’s runtime aggregate and contains `display: Display`, terminal state, notifier, and event state; it does not flatten renderer internals into the runtime owner (`window_context.rs:47-70`).
- Alacritty’s `Display` stores child owners such as damage, glyph cache, and renderer rather than a single graphics catchall (`display/mod.rs:341-398`).
- Alacritty splits update handling, content preparation, damage, and renderer work across owner files while preserving a centralized display draw spine (`display/mod.rs:647-768`, `775-1046`, `content.rs:24-88`, `damage.rs:12-73`, `renderer/mod.rs:89-279`).
- TigerBeetle requires simple explicit control flow and a minimum of excellent abstractions, not helper buckets (`TIGER_STYLE.md:90-100`).
- TigerBeetle requires assertions for arguments, invariants, positive space, and negative space (`TIGER_STYLE.md:109-149`).
- TigerBeetle says large function/file pressure should preserve parent control flow and move true leaf/state ownership, and complex nested types should become top-level owners (`TIGER_STYLE.md:161-176`, `315-332`).
- TigerBeetle architecture requires intentional owner limits and explicit boundedness (`ARCHITECTURE.md:94-101`, `208-222`, `277-279`).

## Compact Anchor Map

- Current host root: `howl-linux-host/src/display/render_surface.zig:421-490`
  Why it matters: the upload orchestration spine should remain the public caller target.
- Current retained resource owner candidate: `howl-linux-host/src/display/render_surface.zig:34-272`
  Why it matters: real mutable state, lifecycle, invariants, GL resource mutation, and tests cluster here.
- Current command owner candidate: `howl-linux-host/src/display/render_surface.zig:297-419`, `492-1134`
  Why it matters: one render-surface command grammar and draw executor cluster here.
- Current runtime caller seam: `howl-linux-host/src/terminal/surface.zig:625-633`
  Why it matters: the caller is narrow and should not absorb GL realization internals.
- Current test facade: `howl-linux-host/src/display/render_surface.zig:1136-1175`
  Why it matters: tests should continue entering through the public root while proving child owners.
- Alacritty host split: `window_context.rs:47-70`, `display/mod.rs:341-398`, `renderer/mod.rs:89-279`
  Why it matters: runtime aggregate, display aggregate, and renderer child work are separated.
- TigerBeetle split law: `TIGER_STYLE.md:161-176`, `315-332`
  Why it matters: split by true owners and source order, not by convenience helpers.

## Owner Roles And Proposed Shape

Decision: `render_surface.zig` is the first true cut. No ranked fallback seam preempts it.

Required shape after the sprint:

- `howl-linux-host/src/display/render_surface.zig`
  Role: curated public root and upload orchestration spine. It keeps `deleteTexture`, `ensureSurface`, `uploadRenderSurface`, `UploadStats`, public re-exports, and test facade curation.
- `howl-linux-host/src/display/render_surface_resources.zig`
  Role: retained host resource textures owner. It owns `RenderResourceTextures`, slot lifecycle, resource-transition validation, resource upload validation, GL create/upload/retire, upload metadata, resource-format/texture-upload primitives, and the shared C-surface primitive helpers needed by both resource validation and command validation.
- `howl-linux-host/src/display/render_surface_commands.zig`
  Role: render-surface command grammar and draw owner. It owns class classification, patch/full shape rules, future-upload visibility checks, fill staging, framebuffer command draw, sprite/glyph draw, quad math, color unpacking, and command timing updates.

No new runtime umbrella, no generic helper file, no `types.zig`, no ABI/header churn, no movement into `terminal/surface.zig`, no movement into `display/display.zig`.

## Explicit Ordered Slice Plan

### Slice 1

- Name: extract retained host resource owner from `render_surface.zig`.
- Allowed files and exact expected changes:
  - `howl-linux-host/src/display/render_surface.zig`: remove the resource-owner symbols listed below, import `render_surface_resources.zig`, re-export `pub const RenderResourceTextures`, keep `uploadRenderSurface`, keep `UploadStats`, keep all command grammar/draw symbols, add root-local `const` aliases for `spanSlice`, `sameResource`, `bytesPerPixel`, and `rectFitsResource` so the still-rooted command code keeps compiling without duplicate helpers, and keep `render_surface.testing` as the only test import facade by delegating resource tests to `render_surface_resources.testing`.
  - `howl-linux-host/src/display/render_surface_resources.zig`: new file containing only the moved retained resource owner symbols listed below, `pub` exports for `spanSlice`, `sameResource`, `bytesPerPixel`, and `rectFitsResource`, `pub const Slot` inside `RenderResourceTextures`, `pub fn textureSlotFor`, and `pub const testing` exposing only `TextureSlot`, `commitUploadMetadata`, and `validateSurface` for root-facade delegation.
  - `howl-linux-host/src/display/render_surface_test.zig`: only import/reference adjustments required by the preserved `render_surface.RenderResourceTextures` and `render_surface.testing` facade; no test weakening or new test root.
- Exact symbols that move to `render_surface_resources.zig`:
  - `RenderResourceTextures` including nested `Slot`, nested `Slot.State`, and methods `deinit`, `realizeSurface`, `realizeSurfaceLocked`, `glErrorOk`, `validateSurface`, `validateSurfaceTransition`, `noteCreate`, `noteUpload`, `noteRetire`, `createTexture`, `uploadTexture`, `commitUploadMetadata`, `retireTexture`, `find`, `textureSlotFor`, `findEmpty`, `findValue`, `deleteSlot`, and `retireSlot` (`render_surface.zig:34-272`).
  - `resourceFormatValid` (`render_surface.zig:341-349`).
  - `uploadValidForSlot` (`render_surface.zig:351-365`).
  - `rectFitsResource` (`render_surface.zig:367-373`).
  - `sameResource` (`render_surface.zig:393-395`).
  - `glFormat` (`render_surface.zig:397-403`).
  - `bytesPerPixel` (`render_surface.zig:405-407`).
  - `spanSlice` (`render_surface.zig:409-412`).
- Exact symbols that remain in `render_surface.zig` after Slice 1:
  - `deleteTexture`, `panicGlBroken`, `UploadStats`, `RenderSurfaceClass`, `rectHasArea`, `resourceEmpty`, `spriteResourceKind`, `resourceHasFutureUpload`, root-local aliases `rectFitsResource`, `sameResource`, `bytesPerPixel`, and `spanSlice` pointing at `render_surface_resources.zig`, `rectsOverlap`, `destinationOverlaps`, `spanCountValid`, `ensureSurface`, `uploadRenderSurface`, all symbols from `classifyRenderSurface` through `unpackRenderSurfaceRgba`, and `testing`.
- Exact Slice 1 test facade route:
  - `render_surface_resources.zig` must expose `pub const testing.TextureSlot = RenderResourceTextures.Slot`.
  - `render_surface_resources.zig` must expose `pub fn testing.commitUploadMetadata(textures: *RenderResourceTextures, uploads: []const render_c.HowlRenderResourceUpload) void` and call the resource-owned `textures.commitUploadMetadata(uploads)` inside the same file.
  - `render_surface_resources.zig` must expose `pub fn testing.validateSurface(textures: *RenderResourceTextures, surface: *const render_c.HowlRenderSurface) void` and call the resource-owned `textures.validateSurface(surface)` inside the same file.
  - `render_surface.zig` must keep `render_surface.testing.TextureSlot`, `render_surface.testing.commitUploadMetadata`, and `render_surface.testing.validateSurface` by delegating to `render_surface_resources.testing`; tests must not import `render_surface_resources.zig` directly.
- Exact tests:
  - `zig build test-unit -- test-filter test-render-surface`
  - `zig build test-unit -- test-filter test-terminal-surface`
- Exact non-goals:
  - No command grammar split.
  - No movement of `UploadStats`.
  - No movement into `terminal/surface.zig`, `display/display.zig`, render-side files, ABI headers, or test root wiring.
  - No generic shared helper file.
- Exact stop conditions:
  - Stop if moving `RenderResourceTextures` requires `terminal/surface.zig` to own GL resource mutation.
  - Stop if `render_surface.zig` cannot remain the public import path with `render_surface.RenderResourceTextures` preserved.
  - Stop if a moved resource helper is required by command logic in a way not listed above; the only permitted interim bridge is the named root-local aliases for `spanSlice`, `sameResource`, `bytesPerPixel`, and `rectFitsResource`.
- Session ids and receipts:
  - Orchestrator: `orch-2026-06-13-host-render-surface-01`
  - Researcher: `research-2026-06-13-host-render-surface-01`
  - Reviewer: `review-2026-06-13-host-render-surface-01`
  - Coder session id required at execution seed time.
  - Commit-hash receipt required before acceptance.

### Slice 2

- Name: extract render-surface command grammar and draw owner.
- Allowed files and exact expected changes:
  - `howl-linux-host/src/display/render_surface.zig`: remove the command-owner symbols listed below, import `render_surface_commands.zig`, keep `deleteTexture`, `panicGlBroken`, `UploadStats`, `ensureSurface`, `uploadRenderSurface`, public re-exports, and `testing` facade curation.
  - `howl-linux-host/src/display/render_surface_commands.zig`: new file containing only the moved command grammar/draw symbols listed below and direct imports needed for them.
  - `howl-linux-host/src/display/render_surface_test.zig`: only import/reference adjustments required by the preserved `render_surface.testing` facade; no test weakening or new test root.
- Exact symbols that move to `render_surface_commands.zig`:
  - `RenderSurfaceClass` (`render_surface.zig:297-317`).
  - `rectHasArea`, `resourceEmpty`, `spriteResourceKind`, `resourceHasFutureUpload`, the root-local aliases for `rectFitsResource`, `sameResource`, `bytesPerPixel`, and `spanSlice`, `rectsOverlap`, `destinationOverlaps`, and `spanCountValid` (`render_surface.zig:319-419`).
  - `classifyRenderSurface`, `assertRenderSurfacePatchHostSurface`, `uploadFillCommands`, and `uploadRenderSurfaceCommands` (`render_surface.zig:492-652`).
  - `renderSurfaceFillOnly`, `renderSurfaceFillPatch`, `renderSurfaceFillCoverage`, `renderSurfaceSprite`, `renderSurfaceSpritePatch`, `renderSurfaceGlyphs`, and `renderSurfaceGlyphPatch` (`render_surface.zig:654-810`).
  - `renderSurfaceFillCommand`, `renderSurfaceSpriteCommand`, `glyphCommandValid`, `glyphSpanValid`, `hasCommands`, `resourceFreeCommands`, `renderSurfaceFullClear`, `uploadFillCommand`, `row_pixels_max`, `fill_upload_tile_bytes_max`, `fillCommandFitsHostRow`, `fillUploadRowBytes`, `fillUploadRowsPerChunk`, `stageFillUploadTile`, `drawFillCommand`, `drawSpriteCommand`, `spriteUploadCoversCommand`, `glyphCommandHasFutureUpload`, `drawGlyphCommand`, `drawQuad`, `emitQuadVerticesWithTex`, `drawTexturedQuad`, `emitTexturedQuadVertices`, `monotonicNs`, `ndcX`, `ndcY`, and `unpackRenderSurfaceRgba` (`render_surface.zig:812-1134`).
- Exact symbols that remain in `render_surface.zig` after Slice 2:
  - `deleteTexture`, `panicGlBroken`, `UploadStats`, `RenderResourceTextures` re-export, command-owner re-exports for public classifier functions used by tests, `ensureSurface`, `uploadRenderSurface`, and `testing`.
- Exact root call shape:
  - `uploadRenderSurface` keeps the top-level order: assert dimensions, compute `had_matching_surface`, call `textures.realizeSurface`, call `ensureSurface`, classify with the command owner, assert patch host surface through the command owner, branch on class in the root, call command owner fill upload for fill classes, call command owner draw upload for sprite/glyph classes, and preserve failed-upload zeroing.
- Exact tests:
  - `zig build test-unit -- test-filter test-render-surface`
  - `zig build test-unit -- test-filter test-terminal-surface`
- Exact non-goals:
  - No movement into `terminal/surface.zig`, `display/display.zig`, render-side files, ABI headers, or `host_test_root.zig`.
  - No GL backend redesign.
  - No command helper bucket outside `render_surface_commands.zig`.
- Exact stop conditions:
  - Stop if the root still owns command grammar or draw execution after extraction.
  - Stop if the split requires a third helper owner to compile.
  - Stop if the split demands a user override against Alacritty or the C ABI boundary.
- Session ids and receipts:
  - Orchestrator: `orch-2026-06-13-host-render-surface-01`
  - Researcher: `research-2026-06-13-host-render-surface-01`
  - Reviewer: `review-2026-06-13-host-render-surface-01`
  - Coder session id required at execution seed time.
  - Commit-hash receipt required before acceptance.

### Slice 3

- Name: root curation and proof-root cleanup after both owner extractions.
- Allowed files and exact expected changes:
  - `howl-linux-host/src/display/render_surface.zig`: remove stale root-local command/resource helpers, order imports/re-exports/orchestration/testing facade, and ensure the root is only the public upload spine.
  - `howl-linux-host/src/display/render_surface_resources.zig`: source-order cleanup only; no behavior changes.
  - `howl-linux-host/src/display/render_surface_commands.zig`: source-order cleanup only; no behavior changes.
- Exact tests:
  - `zig build test-unit -- test-filter test-render-surface`
  - `zig build test-unit -- test-filter test-terminal-surface`
- Exact non-goals:
  - No new owner extraction beyond the two child owners.
  - No new test roots.
  - No `host_test_root.zig` edits.
  - No `render_surface_test.zig` edits.
  - No changes to `display/display.zig`, `event.zig`, `present.zig`, `terminal/surface.zig`, render-side files, or ABI headers.
- Exact stop conditions:
  - Stop if cleanup would broaden into display/runtime redesign.
  - Stop if test coverage can only be preserved by inventing extra helper exports rather than routing through the two real child owners.
- Session ids and receipts:
  - Orchestrator: `orch-2026-06-13-host-render-surface-01`
  - Researcher: `research-2026-06-13-host-render-surface-01`
  - Reviewer: `review-2026-06-13-host-render-surface-01`
  - Coder session id required at execution seed time.
  - Commit-hash receipt required before acceptance.

## Required Assertions

- Preserve the patch/full host-surface contract: patch classes must assert a matching existing host surface before execution (`render_surface.zig:502-506`).
- Preserve host surface dimension assertions before fill or FBO draw execution (`render_surface.zig:509-512`, `531-533`).
- Preserve retained resource invariants: no zero-sized creates, no format mismatch, no live-resource reuse, no retired-value reuse, no slot-capacity overflow, no upload outside slot bounds, no retire of a missing live slot (`render_surface.zig:121-155`, `187-225`).
- Preserve command visibility assertions: sprite and glyph commands must not execute before their final visible upload (`render_surface.zig:619-635`).
- Preserve fill staging bounds assertions: host row width and tile byte bounds must stay asserted (`render_surface.zig:887-894`, `926-949`).
- Preserve terminal submit assertions around unlocked upload phase, stable handle, nonzero snapshot, and non-pending present (`terminal/surface.zig:653-666`).
- If helper migration creates new owner entrypoints, pair assertions at both the root call site and leaf owner entrypoint per TigerBeetle assertion law.

## Required Tests

- `zig build test-unit -- test-filter test-render-surface`
- `zig build test-unit -- test-filter test-terminal-surface`

These two tests are required for every execution slice because `render_surface_test.zig` proves the local grammar/resource owners and `terminal/surface_test.zig` proves the submit-path contract that calls the public root.

## Risks

- The resource owner and command owner share primitives today. The slice plan intentionally assigns each listed symbol once to avoid a fake helper bucket.
- `sameResource`, `spanSlice`, `bytesPerPixel`, and `rectFitsResource` are intentionally assigned to the resource owner in Slice 1 because `RenderResourceTextures` calls them directly. The root may keep temporary aliases only until Slice 2 moves command code out of the root; no duplicate helper body is allowed.
- `RenderResourceTextures.Slot`, `commitUploadMetadata`, and `validateSurface` are intentionally exposed only through `render_surface_resources.testing` and the existing root `render_surface.testing` facade in Slice 1, so tests keep the public root import path without forcing production methods public.
- The `testing` facade is intentionally centralized in `render_surface.zig`; careless direct test imports of child files would weaken the public-root proof surface.

## Proof Gaps

- No blocking proof gaps remain for planning. The ranked fallback files were read directly and do not outrank the host render-surface cut, the Slice 1 shared helper ownership needed by the moved resource owner is explicit, and the Slice 1 resource testing facade route is explicit.
- Cross-boundary host/render validation duplication remains a broader future question, but it does not block this sprint because this plan preserves the C ABI and only moves host-side owners.

## Readiness Judgment

Accept-ready after repair.

Why:

- current source and references support `render_surface.zig` as the first true host cut;
- ranked fallback files were read and compared directly;
- each slice names exact allowed files, exact symbol moves, exact tests, exact non-goals, exact stop conditions, and accountable session ids;
- no implementation or reference override is authorized by this planning artifact.
