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

Promoted first implementation slice:

- Match Kitty `parse_graphics_code` for graphics control-block syntax before state mutation.
- Reject unknown keys, missing `=`, invalid action/delete/transmission/compression flags, empty integer fields, invalid integer bytes, overlarge unsigned integers, invalid signed integers, bad separators, and trailing incomplete fields.
- Preserve Howl's later base64/payload ownership for now; this slice is parser control-block validation, not payload normalization relocation.
- Invalid parser input must not reach `State.handle`, mutate graphics state, or emit graphics protocol replies.
- Remove `unsupported_key` state/handler plumbing if strict parse rejection makes it dead.
- Keep existing supported command behavior and quiet handling unchanged for valid commands.

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

Research round status: source and Howl-gap research complete; implementation not yet promoted.

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

Research questions answered:

- What exact identity model does Kitty use for graphics images, image numbers, anonymous/client ids, refs/placements, frames, access time, storage usage, and quota eviction?
- Which of those semantics are observable at Howl's C ABI/product boundary, and which are internal-only implementation details?
- Where does Howl's current `State/Image/Placement/Frame` model diverge, and what is the smallest first implementation slice that improves correctness without an umbrella runtime layer?
- What tests should gate the slice, especially image-number operations, delete selectors, and quota eviction priority?

Kitty source truth:

- Kitty separates internal image id, client image id, image number, frame id, image ref id, placement id, virtual ref id, cell ref linkage, texture refs, access time, used storage, and cache state.
- `GraphicsManager.images_by_internal_id` is keyed by internal id; protocol `i=` client id and `I=` image number are lookup attributes, not storage keys.
- Image-number lookup resolves the newest matching image by greatest internal id.
- Upload with `I=` and no `i=` creates a new image and assigns the lowest free positive client id.
- Commands with both `i=` and `I=` are invalid.
- Re-upload to an existing client id frees old image resources, refs, frames, textures/cache, and storage accounting before replacing data.
- Placements are `ImageRef`s under an image; `p=` replaces an existing ref with that placement id in the same client-id image context.
- Virtual refs are prototypes, not directly rendered; Unicode placeholders generate separate cell refs linked to the virtual ref.
- Cell refs are removed independently when affected rows/cells are dirtied.
- Storage quota is accounted as image/cache/decoded storage, not base64 transport text.
- Trim/eviction first removes incomplete or unreferenced images, then oldest remaining images by access time if still over quota; the currently added image is not evicted during its quota pass.

Howl current truth:

- Howl VT currently stores linear arrays for `images`, `placements`, `virtual_placements`, and `frames`; `Image.image_id` is both public/client identity and storage identity.
- Howl already has partial image-number support: image-number-only uploads allocate `next_image_id`, and `findNewestImageByNumber` scans newest-first.
- Howl ABI exposes `image_id`, `image_number`, placement geometry, generated-placeholder flags, and retained payload bytes; hosts/render consume the C ABI and should not import Zig internals.
- Howl quota behavior is hard-limit/fail via retained base64/upload byte caps; it does not evict safe candidates.
- Payload-copy ABI currently exposes protocol payload bytes as product behavior, so replacing it with decoded/cache storage is a later explicit ABI contract change.
- Delete selector coverage exists but needs Kitty-port proof, especially image-number and uppercase/free-image selector behavior.

Accepted first implementation direction:

- Do an ABI-preserving VT-only quota/eviction slice before full identity/ref surgery.
- Keep `howl_vt.h`, render, and hosts unchanged.
- Keep public `image_id`, `image_number`, `placement_id`, publication order, and payload-copy behavior unchanged for now.
- Add internal helpers in `howl-vt/src/kitty/graphics.zig` to evict safe candidates before returning retained-payload `ConsequenceLimit`.
- First-slice eviction order should be conservative: incomplete/aborted upload state if applicable, then unplaced images and their frames/override payloads; do not evict images with physical or virtual placements in the first slice.
- Replacement of an existing `image_id` must count bytes freed by the replacement before failing quota.
- Full internal id/ref/cache/decoded-storage model remains a later slice.

First-slice acceptance tests:

- Quota evicts an unplaced image before failing or touching a placed image.
- Quota preserves placed images and returns `ConsequenceLimit` when only placed images could make room.
- Replacement of the same `image_id` succeeds when it fits after subtracting bytes freed by the old image.
- Evicting an unplaced image also removes its frames and current-frame/override payload state.
- Existing image-number newest lookup and delete selector tests remain green; add focused image-number/delete tests only if quota work exposes ambiguity.

Open questions before broader identity/ref work:

- Exact Kitty delete-by-image-number behavior for each selector: newest only vs all matching refs/images.
- Whether virtual placements should count as placed for all quota and delete semantics; first slice treats them as placed/protected.
- Exact access-time update points Howl should eventually model.
- Exact storage bucket Howl should expose long-term once base64 payload stops being product truth.
- Whether generated placeholder placements should become stored VT refs or remain publication-derived until the full ref model lands.

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
