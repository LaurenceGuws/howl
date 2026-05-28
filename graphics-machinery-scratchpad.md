# Graphics Machinery Scratchpad

Owner: workspace root.

Purpose: sprint scope `graphics` research output and worker-driving backlog.

Reviewer status: accepted after researcher correction. The first research pass was rejected because it incorrectly claimed Kitty protocol placeholder diacritics are 1-based. Kitty docs and source show the protocol value is 0-based; Kitty uses `0` as an internal missing sentinel while scanning and subtracts before cell-image creation.

Current gate: do not seed coding workers yet. The repo is dirty across `howl-vt`, `howl-render`, and `howl-linux-host`. Per `loop.txt`, a worker requires a promoted `current.txt` item and a clean git tree.

## Research Truth

- Question 1 primary source is Kitty source, not Ghostty and not only docs.
- Question 2 compares Howl-only hacks against Kitty source and Ghostty.
- Ghostty is allowed for replacement shape and hack detection, not for defining Kitty's own machinery.

## Missing Or Incomplete Kitty Machinery

### 1. VT-owned Unicode placeholder dirty-row to cell-image materialization

Severity: critical for current yazi-like graphics failure.

Kitty machinery:

- `kitty/screen.c`: `screen_render_line_graphics`
- `kitty/screen.c`: `screen_dirty_line_graphics`
- `kitty/screen.c`: placeholder marking via `linebuf_set_line_has_image_placeholders`
- `kitty/graphics.c`: `grman_put_cell_image`
- `kitty/graphics.c`: `grman_remove_cell_images`
- `kitty/graphics.h`: `ImageRef.virtual_ref_id`
- `kitty/graphics.h`: `ImageRef.is_virtual_ref`

Howl current shape:

- `howl-vt/src/kitty/graphics.zig`: `VirtualPlacement`
- `howl-vt/src/kitty/graphics.zig`: `ResolvedPlaceholderRun`
- `howl-vt/src/kitty/graphics.zig`: `walkResolvedPlaceholderRuns`
- `howl-vt/src/kitty/graphics.zig`: `placeholderCellFromScreenCell`
- `howl-vt/src/kitty/graphics.zig`: `backfillPlaceholderRow`
- `howl-render/src/frame/surface_buffer.zig`: `drawPlaceholderRunByIndex`
- `howl-render/src/frame/surface_buffer.zig`: `resolvePlaceholderDrawPlacement`

Problem:

- Kitty materializes Unicode placeholder cells into image refs in terminal/screen code.
- Howl exports placeholder runs and makes render interpret Kitty placeholder protocol.
- This makes render own terminal protocol consequences and makes stale or misresolved run geometry likely.

Full implementation:

- VT tracks rows containing `U+10EEEE` placeholders.
- VT dirties placeholder rows when virtual placements change.
- VT removes generated cell-image placements for a row before rescanning it.
- VT scans dirty placeholder rows and creates generated cell placements equivalent to Kitty cell refs.
- Generated placements carry source image id, virtual placement id, image row/col fragment, run width, screen row/col, z index `-1`, and virtual-ref linkage.
- Render consumes normal prepared placements. Render must not parse placeholder cells or Kitty diacritics.

Acceptance tests:

- Port Kitty unicode placeholder behavior group from `kitty_tests/graphics.py`.
- Updating a virtual placement redraws existing placeholder rows without rewriting cells.
- Overwriting placeholder cells removes stale generated placements.
- Yazi-like split-pane fixture starts preview at the left edge of the target pane.

What not to do:

- Do not add yazi-specific logic.
- Do not move more Kitty protocol interpretation into render.
- Do not fix by compensating in GL or final presentation.

### 2. Placeholder run assembly needs source-proof, not independent heuristics

Severity: high.

Status: proved complete in current VT implementation.

Kitty machinery:

- `kitty/screen.c`: `screen_render_line_graphics`
- `kitty/docs/graphics-protocol.rst`: `U+0305` maps to number `0`

Howl current shape:

- `howl-vt/src/kitty/graphics.zig`: `placeholderDiacriticIndex`
- `howl-vt/src/kitty/graphics.zig`: `placeholderIndex`
- `howl-vt/src/kitty/graphics.zig`: `backfillPlaceholderRow`
- `howl-vt/src/kitty/graphics.zig`: `backfillPlaceholderGroup`
- `howl-vt/src/kitty/graphics.zig`: `PlaceholderRun.canAppend`

Problem:

- Howl's 0-based diacritic decoding is not inherently wrong.
- Howl's run assembly/backfill was invented independently and must be proved against Kitty's exact sentinel and continuation rules.
- Cross-row inheritance is not Kitty machinery and should not be reintroduced.

Full implementation:

- Keep protocol diacritics 0-based.
- Match Kitty continuation rules exactly.
- Missing row, col, and high-byte are sentinels during assembly, not real zero values.
- Publish 0-based image row/col after assembly.

Acceptance tests:

- `U+0305` maps to image row/col `0`.
- Missing column continues previous column plus one on the same row.
- Missing high byte inherits only when Kitty would inherit it.
- Mismatched row, col, placement id, image id, or high byte breaks runs.

What not to do:

- Do not reinterpret protocol diacritics as 1-based.
- Do not add renderer-side corrections.

Proof recorded:

- Kitty `screen_render_line_graphics` uses internal 1-based values where zero is unknown/incorrect, then publishes `prev_img_col - run_length` and `prev_img_row - 1` to `grman_put_cell_image`.
- Kitty `rowcolumn-diacritics.c` maps `U+0305` to internal `1`; Howl's public/internal proof API reports protocol-facing `0` for that same diacritic.
- Howl `placeholderDiacriticIndex` returns 0-based protocol values and `backfillPlaceholderRow` uses nullable missing sentinels before defaulting/inheriting, avoiding real-zero ambiguity.
- Howl `PlaceholderRun.canAppend` requires same row, image id, placement id, contiguous screen cells, and contiguous image columns after row-local backfill.
- VT tests now cover `U+0305 -> 0`, missing column/high-byte inference on the same row, row/col/image/placement/high-byte mismatch breaks, no cross-row inheritance, anonymous placement resolution, stable run order, and yazi-like alt-screen runs.

### 3. Graphics command parser validation is incomplete

Severity: high, protocol correctness.

Kitty machinery:

- `kitty/parse-graphics-command.h`: `parse_graphics_code`
- `kitty/graphics.h`: `GraphicsCommand`

Howl current shape:

- `howl-vt/src/kitty/protocol.zig`: `parseGraphics`
- `howl-vt/src/kitty/protocol.zig`: `parseU32`
- `howl-vt/src/kitty/protocol.zig`: `parseU16`
- `howl-vt/src/kitty/protocol.zig`: `parseI32`
- `howl-vt/src/kitty/graphics.zig`: `State.handle`

Problem:

- Kitty validates command keys, flag domains, delete flags, transmission flags, and integer fields.
- Howl often treats malformed or invalid fields as omitted/zero and continues.
- Invalid protocol can mutate state as valid-but-wrong input.

Full implementation:

- Parser validates syntax before state mutation.
- Invalid integers, flags, keys, and action-specific combinations produce protocol errors.
- Quiet response behavior matches Kitty semantics.

Acceptance tests:

- Invalid action/delete/transmission/compression flags fail without mutation.
- Invalid integer fields fail instead of becoming `0`.
- Unsupported keys produce expected response behavior.

What not to do:

- Do not preserve permissive parsing for convenience.

### 4. Image identity, refs, storage quota, and eviction are incomplete

Severity: medium-high, product machinery.

Kitty machinery:

- `kitty/graphics.h`: `GraphicsManager`
- `kitty/graphics.h`: `Image`
- `kitty/graphics.h`: `ImageRef`
- `kitty/graphics.h`: `Frame`
- `kitty/graphics.h`: `ImageRenderData`
- `kitty/graphics.h`: `GraphicsRenderData`
- `kitty/graphics.c`: `find_or_create_image`
- `kitty/graphics.c`: `get_free_client_id`
- `kitty/graphics.c`: `free_image_resources`
- `kitty/graphics.c`: `remove_images`
- `kitty/graphics.c`: `add_trim_predicate`
- `kitty/graphics.c`: `apply_storage_quota`

Howl current shape:

- `howl-vt/src/kitty/graphics.zig`: `State`
- `howl-vt/src/kitty/graphics.zig`: `Image`
- `howl-vt/src/kitty/graphics.zig`: `Placement`
- `howl-vt/src/kitty/graphics.zig`: `VirtualPlacement`
- `howl-vt/src/kitty/graphics.zig`: `Frame`
- `howl-vt/src/kitty/graphics.zig`: `storeImageOwned`
- `howl-vt/src/kitty/graphics.zig`: `imageIdForUpload`
- `howl-vt/src/kitty/graphics.zig`: `findNewestImageByNumber`
- `howl-vt/src/kitty/graphics.zig`: `ensureRetainedPayloadStore`

Problem:

- Kitty separates internal ids, client ids, image numbers, ref ids, texture refs, access time, used storage, and cache state.
- Howl stores arrays keyed mostly by client id and retains base64 payloads as image truth.
- Image-number-only behavior, anonymous images, unplaced-image trimming, and quota semantics are not complete.

Full implementation:

- VT owns protocol identity and lifetime.
- Separate internal image identity from client id and image number.
- Track refs/placements, access time, used bytes, and eviction candidates.
- Render publication derives from VT image/ref state.

Acceptance tests:

- Port Kitty image number operations.
- Port delete behavior by selector.
- Quota test evicts unplaced/incomplete images before placed images.

What not to do:

- Do not treat base64 transport payload as long-term product state.

### 5. Frame, animation, and compose machinery is partial

Severity: medium.

Kitty machinery:

- `kitty/graphics.h`: `Frame`
- `kitty/graphics.h`: `AnimationState`
- `kitty/graphics.c`: `handle_animation_frame_load_command`
- `kitty/graphics.c`: `handle_animation_control_command`
- `kitty/graphics.c`: `handle_delete_frame_command`
- `kitty/graphics.c`: `handle_compose_command`
- `kitty/graphics.c`: `get_coalesced_frame_data`
- `kitty/graphics.c`: `reference_chain_too_large`
- `kitty/graphics.c`: `scan_active_animations`
- `kitty/graphics.c`: `update_current_frame`

Howl current shape:

- `howl-vt/src/kitty/graphics.zig`: `Frame`
- `howl-vt/src/kitty/graphics.zig`: `storeFrameOwned`
- `howl-vt/src/kitty/graphics.zig`: `selectCurrentFrame`
- `howl-vt/src/kitty/graphics.zig`: `setFrameGap`
- `howl-vt/src/kitty/graphics.zig`: `setAnimationControl`
- `howl-vt/src/kitty/graphics.zig`: `refreshCurrentFramePublication`
- `howl-vt/src/kitty/graphics.zig`: `coalesceFrameRawOwned`
- `howl-vt/src/kitty/graphics.zig`: `progressRuntime`
- `howl-vt/src/kitty/graphics.zig`: `deleteFrames`

Problem:

- Howl has real frame work, but it is not Kitty-complete.
- Current runtime can advance images independent of actual drawn visibility.
- Current frame publication is rebuilt as retained base64 override payload.

Full implementation:

- VT owns animation frame graph and state mutation.
- Render owns decoded raster cache/current raster binding.
- Runtime advances only visible/drawn images.
- Implement default gap, deletion repair, compose command, chain limits, loop behavior, and loading-state behavior.

Acceptance tests:

- Port Kitty animation frame loading tests.
- Port frame deletion tests.
- Port animation control and compose tests.
- Hidden/unplaced image does not drive animation runtime.

What not to do:

- Do not bolt runtime policy into render leaf helpers.

### 6. Render-layer sorting and grouping differs from Kitty

Severity: medium.

Kitty machinery:

- `kitty/graphics.c`: `grman_update_layers`
- `kitty/graphics.c`: `gpu_data_for_image`
- `kitty/graphics.h`: `ImageRenderData`
- `kitty/graphics.h`: `GraphicsRenderData`

Howl current shape:

- `howl-render/src/frame/graphics_viewport.zig`: `prepareGraphics`
- `howl-render/src/frame/graphics_viewport.zig`: `classifyLayer`
- `howl-render/src/frame/graphics_viewport.zig`: `sortPreparedPlacements`
- `howl-render/src/frame/surface_buffer.zig`: `drawGraphicsBelowText`

Problem:

- Kitty sorts visible refs by z-index, image internal id, and ref internal id, then computes layer groups.
- Howl has layer counts plus a separate placeholder ordering path.
- Mixed placeholders and normal placements can diverge from Kitty ordering.

Full implementation:

- Publish one ordered placement stream after VT materializes cell refs.
- Preserve Kitty-compatible ordering by z-index class, image identity, and stable ref/placement ordinal.
- Remove separate placeholder ordering path after VT materialization exists.

Acceptance tests:

- Port Kitty image layer grouping behavior.
- Mixed normal placement and placeholder-generated placement ordering test.

What not to do:

- Do not delete placeholder render code before normal generated placements exist.

## Howl-Only Hacks

### 1. Render-side Kitty placeholder interpreter

Removal confidence: high after VT materialization exists, unsafe before then.

Howl files/functions:

- `howl-render/src/frame/surface_buffer.zig`: `drawPlaceholderRunByIndex`
- `howl-render/src/frame/surface_buffer.zig`: `resolvePlaceholderDrawPlacement`
- `howl-render/src/frame/surface_buffer.zig`: `placeholderSourceRect`
- `howl-render/src/frame/surface_buffer.zig`: `placeholderGrid`
- `howl-render/src/frame/surface_buffer.zig`: `sortPlaceholderRuns`
- `howl-render/src/frame/surface_buffer.zig`: `placeholderRunSortLessPlacement`

Reference contradiction:

- Kitty materializes placeholders in terminal/screen code.
- Ghostty keeps placeholder parsing in terminal kitty graphics unicode code.
- Neither reference makes renderer parse Kitty placeholder protocol.

Delete or replace:

- Replace with VT-generated cell placements.
- Delete render placeholder geometry and ordering only after VT publication is complete.

Risk:

- High if deleted now.

### 2. Base64 retained payload as graphics truth

Removal confidence: not deletion-only.

Howl files/functions:

- `howl-vt/src/kitty/graphics.zig`: `Image.base64_payload`
- `howl-vt/src/kitty/graphics.zig`: `Frame.base64_payload`
- `howl-vt/src/kitty/graphics.zig`: `storeImageOwned`
- `howl-vt/src/kitty/graphics.zig`: `storeFrameOwned`
- `howl-vt/src/kitty/graphics.zig`: `refreshCurrentFramePublication`
- `howl-render/src/frame/graphics_prepare.zig`: `ensureDecodedGraphicsRaster`
- `howl-render/src/frame/graphics_prepare.zig`: `decodeGraphicsRaster`

Reference contradiction:

- Kitty stores loaded image/frame data with cache/texture refs, not base64 as model truth.
- Ghostty stores loaded image state and render placements, not base64 transport as truth.

Delete or replace:

- Replace with decoded/validated image payload state behind the ABI.
- Keep base64 only as transport input.

Risk:

- High migration cost.

### 3. Placeholder image refs injected in render preparation

Removal confidence: medium after VT materialization exists.

Howl files/functions:

- `howl-render/src/frame/graphics_prepare.zig`: `ensureVirtualPlacementImageRefs`
- `howl-render/src/frame/graphics_prepare.zig`: `preparePlaceholderGraphics`

Reference contradiction:

- Kitty creates cell refs before render data construction.
- Ghostty render placement flow does not require render prep to invent missing refs for virtual placements.

Delete or replace:

- Remove after VT publishes generated cell placements and their images as normal graphics publication entries.

Risk:

- Medium; currently required by the placeholder POC path.

### 4. Temporary cross-layer graphics logging

Removal confidence: high when diagnosis is done.

Howl files/functions:

- `howl-vt/src/kitty/apply.zig`: `graphics_log.event("vt-mutate", ...)`
- `howl-render/src/frame/surface_buffer.zig`: `tracePlaceholderReject`
- `howl-render/src/frame/surface_buffer.zig`: `tracePlaceholderDraw`
- `howl-linux-host/src/terminal/terminal_panel.zig`: graphics proof/upload logging helpers

Reference contradiction:

- These are temporary proof hooks, not product machinery.

Delete or replace:

- Delete after tests cover placeholder placement.
- Keep gated while current live failure lacks a durable test.

Risk:

- Low functional risk, but deleting now reduces observability.

## Worker Backlog

### Item 1: Prove placeholder run assembly against Kitty

Owner: `howl-vt`.

Type: machinery proof/fix.

Target files:

- `howl-vt/src/kitty/graphics.zig`
- `howl-vt/src/test/terminal_graphics.zig`

Acceptance tests:

- `U+0305` maps to image row/col `0`.
- Same-row missing col/high-byte inference matches Kitty.
- Mismatched row, col, image id, placement id, or high byte breaks runs.

What not to do:

- Do not alter render geometry.
- Do not reintroduce cross-row inference.

### Item 2: Implement VT-owned generated cell placements

Owner: `howl-vt`.

Type: machinery implementation.

Target files:

- `howl-vt/src/kitty/graphics.zig`
- `howl-vt/src/terminal.zig`
- `howl-vt/src/ffi.zig`

Acceptance tests:

- Placeholder cells create generated z `-1` placements.
- Rewriting a placeholder row removes stale generated placements.
- Updating a virtual placement redraws existing placeholder rows.
- Yazi-like pane preview starts at the target pane's left edge.

What not to do:

- Do not special-case yazi.
- Do not add render-owned protocol interpretation.

### Item 3: Replace render placeholder path with normal placement rendering

Owner: `howl-render`.

Type: machinery implementation followed by deletion.

Target files:

- `howl-render/src/frame/surface_buffer.zig`
- `howl-render/src/frame/graphics_prepare.zig`
- `howl-render/src/frame/graphics_viewport.zig`
- `howl-render/src/frame/surface.zig`

Acceptance tests:

- Placeholder-generated placements participate in `prepareGraphics` like normal placements.
- Mixed placeholder/normal image z ordering matches Kitty.
- No render-side Kitty placeholder geometry remains after replacement.

What not to do:

- Do not delete this path before VT generated placements exist.

### Item 4: Harden graphics parser to Kitty source shape

Owner: `howl-vt`.

Type: machinery implementation.

Target files:

- `howl-vt/src/kitty/protocol.zig`
- `howl-vt/src/kitty/apply.zig`

Acceptance tests:

- Invalid action/delete/transmission/compression flags fail without mutation.
- Invalid integer fields fail instead of becoming `0`.
- Quiet response behavior matches Kitty tests.

What not to do:

- Do not keep invalid values permissive for compatibility without a reference reason.

### Item 5: Port Kitty graphics tests by behavior group

Owner: test worker.

Type: machinery proof.

Target files:

- `howl-vt/src/test/terminal_graphics.zig`
- Render tests as needed under `howl-render/src/frame/`

Acceptance tests:

- Load images.
- PNG load.
- Image numbers.
- Image put.
- Parents.
- Unicode placeholders.
- Scroll.
- Delete.
- Animation frame loading.

What not to do:

- Do not bless current Howl placeholder POC behavior as golden.

## Deletion Worker Gate

Do not seed a deletion-only worker yet.

Reasons:

- The tree is dirty, violating `loop.txt` code workflow.
- The high-confidence hacks are dependency-ordered. Render placeholder hacks cannot be deleted until VT generated cell placements exist.
- Temporary graphics logging is deletion-only but currently supports diagnosis and should be removed only after durable tests replace it.
