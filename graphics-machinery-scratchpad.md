# Graphics Machinery Scratchpad

Owner: workspace root.

Purpose: sprint scope `graphics` research output and worker-driving backlog.

Reviewer status: accepted after researcher correction. The first research pass was rejected because it incorrectly claimed Kitty protocol placeholder diacritics are 1-based. Kitty docs and source show the protocol value is 0-based; Kitty uses `0` as an internal missing sentinel while scanning and subtracts before cell-image creation.

Current gate: seed coding workers only after `current.txt` is promoted and the git tree is clean.

## Completed GUI Validation

- User-in-the-loop yazi/Kitty comparison validated the placeholder combining and generated-row geometry slice.
- Local yazi reference is under ignored `utils/dev_references/terminal_apps/yazi`.
- Temporary `HOWL_YAZI_PROBE=1` logs were used during diagnosis and removed before commit.
- First yazi probe showed upload/decode/present all work, but VT row assembly split at `U+0483`, the first yazi column diacritic outside Howl's old basic combining range.
- Current behavior slice expands screen combining-mark recognition so those diacritics remain attached to the `U+10EEEE` lead cell before graphics placeholder materialization.
- Second yazi probe reduced resolved placements from `2565` to `154`, but row runs after the first still used `source_y=0` while right-edge fragments advanced. The remaining cause was screen combining attachment preferring a non-empty current cursor cell over the preceding printed placeholder cell when yazi overwrote pane content.
- Third yazi probe reduced resolved placements to `93` and showed row `source_y` advancing correctly, but the image still bled at pane bottoms.
- Bottom bleed root cause was generated placeholder geometry losing exact clipped destination height before FFI publication. Partial rows were recomputed from rounded source aspect ratio, so a row that should end at the cell bottom could publish one pixel too tall.
- Current geometry fix keeps exact generated destination width/height inside VT placement state and publishes those exact bounds without changing the C ABI or adding yazi-specific behavior.
- User probe after the geometry fix confirmed the first row now publishes `dest_cell_px=(0,7,440,20)`, but the visual issue remains. Added probe-only head/tail placement samples plus VT/render placement bounds to distinguish excessive generated extent from render composition bleed-through.
- Focused placeholder-cell probe found the pane-bottom smear begins when yazi reaches `U+0657` and later Arabic row diacritics. Howl did not classify `U+0657...U+065E` as trailing combining marks, so each placeholder consumed an extra screen cell and wrapped into pane bottoms. The screen combining range now includes `0x064B...0x065F`, with a `U+0657` regression.

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

Parser validation slice completed:

- `howl-vt` commit `e4d96af vt: reject malformed graphics fields`.
- Verification passed: `zig build test --summary all`,
  `zig build test:regression:build --summary all`, root `zig build`, root
  `git diff --check`, and `howl-vt` `git diff --check`.

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

- Exact Kitty delete-by-image-number behavior for each selector: answered for first slice; `d=n`/`d=N` use newest matching image-number only, not all matching images.
- Whether virtual placements should count as placed for all quota and delete semantics; first slice treats them as placed/protected.
- Exact access-time update points Howl should eventually model.
- Exact storage bucket Howl should expose long-term once base64 payload stops being product truth.
- Whether generated placeholder placements should become stored VT refs or remain publication-derived until the full ref model lands.

Delete selector research:

- Kitty lowercase selectors remove refs/placements; named image data generally remains.
- Kitty uppercase selectors remove matching refs and free only images whose matched refs are now gone, plus specific unreferenced-image cases for `d=I`, `d=N`, and `d=R`.
- `I=` image-number lookup is newest-only by greatest internal id. Delete-by-number uses `d=n`/`d=N,I=<number>` and targets only that newest matching image.
- `d=i`/`d=I` use client image id. `d=n`/`d=N` use image number. Do not confuse selector `d=I` with parameter `I=`.
- Kitty positional selectors (`p/P`, `q/Q`, `x/X`, `y/Y`, `z/Z`, `c/C`) skip virtual refs and generated cell refs.
- `d=a`/`d=A` clear visible non-cell, non-virtual refs; this is not a global image clear.
- Howl currently deletes image data for lowercase `i`, `n`, and `r`, and uppercase geometry selectors call global `deleteUnplacedImages`, which can sweep unrelated unplaced images. Both differ from Kitty.

Promoted delete selector first slice:

- VT-only, ABI-preserving.
- Separate removing matched placements/virtual placements from deleting image data.
- Lowercase `d=i`, `d=n`, and `d=r` should remove matching placements but keep named image data.
- Uppercase id/number/range selectors may delete image data only for targeted images that are now unplaced.
- Uppercase geometry selectors may delete image data only for images whose placements matched that selector and are now unplaced; they must not run global unplaced-image cleanup.
- Add tests for newest-only `d=N,I=<number>`, lowercase named-image retention, uppercase matched-image freeing, and unrelated unplaced image preservation.
- Leave full visibility filtering for `d=a` and generated cell-ref materialization to later source-proofed slices unless needed by tests.

Delete selector first slice completed:

- `howl-vt` commit `6916aac vt: honor graphics delete lifetimes`.
- Root commit `3af602e design: update graphics delete selectors`.
- Verification passed: `zig build test`, `zig build test:regression:build`, and root `git diff --check`.

Image-number identity research:

- Kitty `Image.internal_id` and `Image.client_id` are distinct, but the next ABI-preserving Howl slice does not need to expose or store a full internal id yet.
- Kitty `I=<number>` upload without `i=` allocates a free positive client id via `get_free_client_id`; it must not collide with existing explicit `i=` images.
- Kitty `I=<number>` creates a new image for that number, and later `I=<number>` references resolve to the newest matching image.
- Howl currently allocates `I=` uploads from `next_image_id`; this can collide with an existing explicit `i=` image and replacement-delete it.
- Howl direct and chunked `a=f,I=<number>` currently validate the target using `resolveImageId`, then use `imageIdForUpload`, which allocates instead of targeting the newest existing image.

Promoted image-number identity slice:

- VT-only, ABI-preserving.
- Replace `next_image_id` allocation for `I=` uploads with lowest-free positive client id allocation.
- Keep explicit `i=<id>` replacement semantics unchanged.
- Repeated `I=<number>` uploads create distinct client ids; placement/query/control/delete by `I=<number>` continue to resolve newest-first.
- Direct and chunked `a=f,I=<number>` frame uploads target the resolved newest existing image; missing targets must not allocate images.
- Leave anonymous `image_id == 0`, full internal image/ref ids, access-time quota, render publication identity, and frame graph completeness for later slices.

Image-number identity acceptance tests:

- `I=` upload after existing `i=1` assigns a non-colliding id and preserves the explicit image.
- Repeated `I=<number>` uploads assign distinct ids and placement by `I=<number>` targets newest.
- `I=` allocation reuses the lowest freed positive client id.
- Direct `a=f,I=<number>` stores a frame on the newest image.
- Chunked `a=f,I=<number>` stores a frame on the newest image captured by the first chunk.
- Missing `a=f,I=<number>` target replies not found and does not allocate an image.

Image-number identity slice completed:

- `howl-vt` commit `4fc2e74 vt: allocate graphics image numbers safely`.
- Root commit `ba0ba8a design: update graphics image identity`.
- Verification passed: `zig build test`, `zig build test:regression:build`, and root `git diff --check`.

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

Frame compose research:

- Kitty source truth: `handle_compose_command`, `compose_rectangles`, `get_coalesced_frame_data`, `frame_for_number`, and `update_current_frame` in `kitty/graphics.c`.
- Kitty docs define `a=c` composition: source frame `r=`, destination frame `c=`, rectangle size `w/h`, destination offset `x/y`, source offset `X/Y`, and operation `C=1` for replacement or default alpha blend.
- Kitty treats frame `1` as the root image frame; source or destination may be root.
- Kitty validates missing image/frame as `ENOENT`, out-of-bounds rectangles as `EINVAL`, and same-frame overlapping rectangles as `EINVAL`.
- Kitty fully coalesces the destination frame after compose and refreshes the current publication if the destination is current.
- Howl currently rejects `a=c` in `State.handle`, but already has retained root/frame payloads, frame coalescing helpers, raw/RGBA compose helpers, and current-frame publication refresh.
- Howl parser currently maps `X` to frame-load compose mode and cell x offset, `Y` to background RGBA and cell y offset, and `C` to put cursor policy. The compose slice must source `a=c` replacement mode from `C` without breaking existing `a=T` cursor movement or `a=f` frame-load `X=1` semantics.

Promoted frame compose slice:

- VT-only, ABI-preserving.
- Add `a=c` handling in `howl-vt/src/kitty/graphics.zig`.
- Adjust parser/vocabulary only as much as needed to distinguish `a=c,C=1` compose replacement from existing put cursor policy and frame-load `X=1` replacement.
- Implement root/source/destination frame coalescing, rectangle bounds checks, same-frame overlap rejection, replacement/alpha blend, destination storage, and current-frame publication refresh.
- Leave decoded cache storage, disk cache quota parity, visibility-driven animation runtime, and full frame graph rewrite for later slices.

Frame compose acceptance tests:

- Compose root frame `r=1` into destination frame `c=2` and store the fully composed destination payload.
- Compose a source-frame sub-rectangle into a destination-frame sub-rectangle using Kitty offsets.
- `C=1` replacement differs from default alpha blending for RGBA source data.
- Missing image/source/destination fails without mutation.
- Out-of-bounds source or destination rectangles fail without mutation.
- Same-frame overlapping rectangles fail without mutation.
- Composing into the selected current frame refreshes publication.

Frame compose slice completed:

- `howl-vt` commit `6b39f78 vt: compose kitty graphics frames`.
- Root commit `b150e82 design: update graphics frame compose`.
- Verification passed: `zig build test`, `zig build test:regression:build`, and root `git diff --check`.

Placement-ref namespace research:

- Kitty uses a single `Image.refs_by_internal_id` namespace per image; physical, virtual, and generated cell refs are one ref type with kind fields such as `is_virtual_ref` and `virtual_ref_id`.
- Kitty `handle_put_command` updates an existing nonzero client placement id ref instead of allowing a physical ref and a virtual ref with the same client id to coexist.
- Howl currently stores physical placements and virtual placements in separate arrays. `upsertPlacement` only searches physical placements, and `upsertVirtualPlacement` only searches virtual placements.
- This means `a=p,i=7,p=9` followed by `a=p,i=7,p=9,U=1` leaves both a physical placement and a virtual prototype, contradicting Kitty's single ref namespace.
- Full Kitty ref parity still needs VT-owned internal ref ids, stable parent links, and eventually generated cell refs. The next small slice only fixes cross-kind replacement for nonzero client placement ids.

Promoted placement kind replacement slice:

- VT-only, ABI-preserving.
- For nonzero `(image_id, placement_id)`, physical and virtual puts replace each other across arrays instead of coexisting.
- Preserve anonymous `p=0` behavior.
- When a parent ref is converted across physical/virtual kind, update direct child parent kind metadata where possible so existing relative placements keep targeting the same client ref.
- Leave omitted-parent `Q=0` drift, internal ref ids, and persistent generated cell refs for later source-proofed slices.

Placement kind replacement acceptance tests:

- Physical placement converted to virtual by same nonzero `p=` leaves only the virtual placement.
- Virtual placement converted to physical by same nonzero `p=` leaves only the physical placement.
- Repeated physical/virtual conversions do not grow total placement count.
- Anonymous `p=0` physical and virtual placements do not replace each other.
- Direct child placement referencing a converted nonzero parent continues resolving through the updated parent kind where possible.

Placement kind replacement slice completed:

- `howl-vt` commit `096e961 vt: replace graphics placement kinds`.
- Root commit `e54b7d5 design: update graphics placement refs`.
- Verification passed: `zig build test`, `zig build test:regression:build`, and root `git diff --check`.

Stable parent-ref identity research:

- Kitty parent links store internal image/ref identity (`ImageRef.parent.img` and `ImageRef.parent.ref`) rather than re-resolving client placement ids on every anchor lookup.
- Kitty `Q=0` selects the first live ref at creation time and stores that ref identity; subsequent map/array changes do not retarget the child.
- Howl currently stores `parent_image_id`, `parent_placement_id`, and `parent_is_virtual`, then resolves by searching arrays. `Q=0` stores client placement id `0`, so anonymous or first-parent children can drift when placements are removed or arrays reorder.
- Howl can add VT-internal `ref_id` fields to physical and virtual placement structs without changing C ABI because FFI copies only published fields.
- Generated placeholder placements should not become persistent refs in this slice; that remains a separate source-proofed step.

Promoted stable parent-ref slice:

- VT-only, ABI-preserving.
- Add internal ref ids to physical and virtual placements and a `next_ref_id` allocator on graphics state.
- Preserve ref ids across same-kind replacement and physical/virtual kind conversion for nonzero client placement ids.
- Store parent links by internal parent ref id while keeping existing public parent image/placement fields for publication and diagnostics.
- Resolve anchors, validate cycles, and delete descendants using parent ref ids where possible.
- Fix `P=<image>,Q=0` drift for physical and virtual refs without implementing persistent generated cell refs.

Stable parent-ref acceptance tests:

- `Q=0` child remains anchored to originally selected physical parent after another parent placement is removed/reordered.
- `Q=0` child remains anchored to originally selected virtual parent after other refs are added or removed.
- Updating/converting a nonzero parent preserves its internal ref id and children remain attached.
- Deleting an anonymous parent removes descendants by internal ref instead of deleting all `placement_id=0` descendants for that image.

Stable parent-ref slice completed:

- `howl-vt` commit `fc7c456 vt: bind graphics parents by ref`.
- Root commit `396cac4 design: update graphics parent refs`.
- Verification passed: `zig build test`, `zig build test:regression:build`, and root `git diff --check`.

Frame deletion research:

- Kitty source truth: `handle_delete_frame_command` in `kitty/graphics.c`.
- Kitty normalizes delete target as `min(extra_frame_count + 1, r)` and defaults missing/zero `r` to frame `1`.
- If extra frames exist and frame `1` is deleted, Kitty promotes the first extra frame to root, removes that extra slot, shifts later frames down, and repairs current frame index/publication.
- If an extra frame is deleted, Kitty removes it positionally, shifts later frames down, and decrements or refreshes current frame selection as needed.
- If no extra frames exist, lowercase `d=f` leaves the image alive; uppercase `d=F` returns the image for deletion.
- Howl currently only removes matching `Frame` rows, uses `swapRemove`, does not promote frame `2` into root, and treats `d=f`/`d=F` identically.

Promoted frame delete promotion slice:

- VT-only, ABI-preserving.
- Implement Kitty root promotion and positional extra-frame deletion in `deleteFrames`/repair helpers.
- Preserve frame order and renumber remaining extra frames after deletion.
- Repair current frame publication when deleting current or prior frames.
- Implement `d=F` image-free behavior only when no extra frames remain.
- Leave decoded-cache storage, full frame graph/cache identity, and runtime timing policy for later slices.

Frame delete promotion acceptance tests:

- Deleting root frame promotes frame `2` to root and shifts old frame `3` to frame `2`.
- Deleting a middle extra frame preserves order and repairs selected current frame.
- Repeated lowercase frame delete promotes until no extra frames remain and keeps final root alive.
- Uppercase `d=F` with no extra frames deletes the image.
- Missing or too-large `r=` deletes Kitty's normalized target frame.

Frame delete promotion slice completed:

- `howl-vt` commit `fd0b49e vt: promote deleted graphics frames`.
- Root commit `3d7d211 design: update graphics frame deletion`.
- Verification passed: `zig build test`, `zig build test:regression:build`, and root `git diff --check`.

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

Render-order ABI research:

- Kitty `grman_update_layers` sorts visible refs by `z_index`, image internal id, then ref internal id before computing layer groups.
- Howl render currently sorts by `z_index`, public `image_id`, public `placement_id`, and publication ordinal.
- Howl VT now has internal placement `ref_id`, including stable parent refs and preservation across placement updates/kind conversions, but the C ABI does not publish it.
- Client `placement_id` is not ref identity: anonymous `p=0` refs all share it, and client ids can be out of creation/ref order.
- Generated placeholder placements are still publication-derived, not persistent refs. For this slice, they can publish a stable render-order key derived from the virtual placement ref plus run order without becoming stored refs.

Promoted render-order ABI slice:

- Add a render-order/ref key field to `HowlVtGraphicsPlacement` and mirror it in render's `FfiVtGraphicsPlacement`/prepared placement state.
- Physical placements publish `Placement.ref_id`.
- Generated placeholder placements publish a nonzero stable key derived from source virtual placement ref and run order.
- Render sorts same-layer placements by `z_index`, `image_id`, render-order key, then ordinal.
- Keep layer bands, raster decode, host event flow, and generated placeholder persistence unchanged.

Render-order ABI acceptance tests:

- VT publishes distinct nonzero render-order keys for multiple anonymous same-image placements.
- Updating or converting a nonzero placement preserves the render-order key.
- Generated placeholder placements publish stable render-order keys.
- Render sorts same-z same-image placements by render-order key rather than client placement id.
- Render uses publication ordinal only as final tie-break for equal render-order keys.

Render-order ABI slice completed:

- `howl-vt` commit `fa2b8af vt: publish graphics render order`.
- `howl-render` commit `bf29292 render: sort graphics by render order`.
- Root commit `873f6bf design: update graphics render order`.
- Verification passed: `zig build test` and `zig build test:regression:build` in `howl-vt`, `zig build test` in `howl-render`, and root `git diff --check`.

### 7. Animation frame load gap semantics differ from Kitty

Severity: medium, protocol correctness.

Kitty machinery:

- `kitty/graphics.c`: `DEFAULT_GAP` is `40`.
- `kitty/graphics.c`: `handle_animation_frame_load_command` gives new transmitted frames `g->gap > 0 ? g->gap : (g->gap < 0) ? 0 : DEFAULT_GAP`.
- `kitty/graphics.c`: editing an existing frame changes gap only when `g->gap != 0`.
- `kitty/graphics.c`: `change_gap` clamps negative gaps to `0`.

Howl current shape:

- `howl-vt/src/kitty/graphics.zig`: `storePayload` passes `cmd.z` directly to `storeFrameOwned`.
- `howl-vt/src/kitty/graphics.zig`: `storeFrameOwned` stores or updates frame gap directly.
- `howl-vt/src/kitty/graphics.zig`: `setFrameGap` already ignores `gap == 0` for animation-control edits.

Problem:

- Howl currently treats `cmd.z == 0` as frame gap `0` for `a=f`.
- Kitty treats missing/zero `z` as default gap `40` for new extra frames.
- Kitty treats missing/zero `z` as preserve previous gap when editing existing frames.
- Kitty clamps negative nonzero gaps to `0`.

Promoted frame-gap semantics slice:

- For `a=f` new extra frames, omitted or zero `z` stores gap `40`.
- For `a=f` new extra frames, negative `z` stores gap `0`.
- For `a=f` existing extra-frame edits, omitted or zero `z` preserves previous gap.
- For `a=f` existing extra-frame edits, nonzero `z` updates gap and clamps negative values to `0`.
- Leave animation runtime, visibility, loop handling, decoded/cache storage, render ABI, and host policy unchanged.

Frame-gap acceptance tests:

- New extra frame without `z=` gets gap `40`.
- New extra frame with `z=0` gets gap `40`.
- New extra frame with `z=-1` gets gap `0`.
- Editing an existing frame without `z=` preserves its old gap.
- Editing an existing frame with `z=0` preserves its old gap.
- Editing an existing frame with `z=-1` changes gap to `0`.

Frame-gap semantics slice completed:

- `howl-vt` commit `f911699 vt: match kitty frame gaps`.
- Verification passed: `zig build test`, `zig build test:regression:build`, and root `git diff --check`.

### 8. Quiet response modes collapse `q=1` and `q=2`

Severity: medium, protocol correctness.

Kitty machinery:

- `kitty_tests/graphics.py`: `test_suppressing_gr_command_responses` covers `q=1` success suppression and `q=2` failure suppression.
- `utils/official_docs/kitty/graphics-protocol.md`: `q=1` suppresses `OK`; `q=2` suppresses failure responses.
- `kitty/graphics.c`: `finish_command_response` suppresses any `OK` when `g->quiet != 0` and suppresses all responses when `g->quiet > 1`.
- `kitty/parse-graphics-command.h`: `quiet` parses as an unsigned integer, not a two-value enum.

Howl current shape:

- `howl-vt/src/action/vocabulary.zig`: `KittyGraphicsCommand.quiet` is `bool`.
- `howl-vt/src/kitty/protocol.zig`: parser sets `quiet = parseU32(q) != 0`, collapsing `q=1` and `q=2`.
- `howl-vt/src/kitty/graphics.zig`: reply sites use `if (!cmd.quiet)` for both successes and failures.
- `howl-vt/src/test/action_mapping.zig`: current parser test only proves nonzero `q` becomes true.

Problem:

- Howl suppresses all replies for both `q=1` and `q=2`.
- Kitty emits failures for `q=1`, and suppresses both failures and successes for `q > 1`.
- Chunked uploads need to preserve the initiating quiet mode until the final response.

Promoted quiet response mode slice:

- Replace the boolean command quiet state with numeric quiet mode.
- Centralize success/failure suppression enough to avoid ad hoc `q=1`/`q=2` mistakes across reply sites.
- Preserve existing reply text, image id, placement id, image number, and mutation behavior except for suppression rules.
- Leave PNG error taxonomy, decode/storage, delete/reset behavior, animation runtime, frame gaps, and ABI/render/host code unchanged.

Quiet response acceptance tests:

- Parser/action mapping keeps `q=0`, `q=1`, `q=2`, and `q=3` distinct.
- Invalid direct upload with `q=1` still emits an error.
- Invalid direct upload with `q=2` emits no error.
- Successful upload/query/placement with `q=1` emits no `OK`.
- Successful upload/query/placement with `q=2` emits no `OK`.
- Failed final chunk with initiating `q=1` emits an error.
- Failed final chunk with initiating `q=2` emits no error.
- Missing image/frame/parent errors with `q=2` emit no error.
- Successful animation/frame control with `q=1` emits no `OK`.

Quiet response mode slice completed:

- `howl-vt` commit `381fb35 vt: honor kitty quiet modes`.
- Review corrected the initial docs-shaped brief to Kitty source truth: nonzero `q` suppresses success, `q > 1` suppresses failure, and `q` remains a parsed unsigned integer.
- Verification passed: `zig build test`, `zig build test:regression:build`, and root `git diff --check`.

### 9. Generated placement dirty/publication proof before persistent refs

Severity: medium-high, placeholder machinery confidence.

Kitty machinery:

- `kitty/screen.c`: `screen_dirty_line_graphics` marks placeholder rows dirty and removes stale generated cell refs when rows may move.
- `kitty/screen.c`: `screen_render_line_graphics` removes row cell refs, rescans placeholders, and recreates refs.
- `kitty/graphics.c`: `grman_put_cell_image` creates real cell-image refs.
- `kitty/graphics.c`: `grman_remove_cell_images` removes generated cell refs for row ranges.

Howl current shape:

- `howl-vt/src/kitty/graphics.zig`: `walkResolvedPlaceholderRuns`, `resolvedGeneratedPlacementCount`, `resolvedGeneratedPlacementAt`, and `generatedPlacementFrom` derive generated placements on demand.
- `howl-vt/src/terminal.zig`: graphics publication is keyed by publication sequence, dirty generation, and active screen state.
- `howl-vt/src/test/terminal_graphics.zig`: existing tests cover generated placement creation, virtual placement update, clear, stale alt-screen publication rejection, and render-order key stability.

Problem:

- Howl does not have persistent generated cell refs, so Kitty's stale-ref removal model is not directly implemented.
- On-demand publication should still match Kitty's observable behavior after row and cell mutations.
- Before adding persistent refs, tests should prove current publication cannot expose stale generated placements for common line/character edit operations.

Promoted generated placement dirty/publication proof slice:

- Add focused VT tests for insert/delete line and insert/delete character mutations across placeholder rows/cells.
- Prove clearing placeholder ranges removes generated placements and stale `publication_seq` queries are rejected after mutation.
- Prove unchanged publication content keeps generated render-order keys deterministic.
- Fix only real bugs exposed by those tests in `howl-vt/src/kitty/graphics.zig` or `howl-vt/src/terminal.zig`.
- Leave persistent generated refs, scrollback viewport publication, ABI, render, and host code unchanged.

Generated dirty/publication acceptance tests:

- Insert lines over placeholder rows removes/moves generated placements to match resulting screen cells.
- Delete lines over placeholder rows removes/moves generated placements to match resulting screen cells.
- Insert/delete chars across placeholder cells updates generated placement runs.
- Clearing a row/range containing placeholders removes generated placements.
- Reusing an old `publication_seq` after placeholder row mutation is rejected.
- Generated placement render-order keys remain stable for unchanged publication content after a non-graphics meta query.

Generated placement dirty/publication proof slice completed:

- `howl-vt` commit `8568194 vt: prove generated placement publication`.
- Tests-only slice; no persistent refs, ABI, render, host, or terminal implementation changes.
- Verification passed: `zig build test`, `zig build test:regression:build`, and root `git diff --check`.

Remaining Unicode placeholder publication research:

- Current VT already publishes placeholder-derived generated placements through normal
  graphics placement publication, including generated flags, destination geometry, and
  stable render-order keys.
- Render now consumes normal placement streams and sorts by `z_index`, `image_id`,
  render-order key, and ordinal; the old named render placeholder helpers are no longer
  present.
- The remaining gap is proof against the rest of Kitty's Unicode placeholder behavior,
  not a render-side protocol interpreter deletion.
- Persistent Kitty-style generated cell refs remain future work. The next slice should
  not add them unless tests prove on-demand VT publication cannot match observable
  behavior.

Promoted remaining Unicode placeholder publication proof slice:

- VT-only, tests-first/proof-only unless a real mismatch is exposed.
- Port remaining Kitty Unicode placeholder behavior at the VT generated-placement
  publication boundary.
- Target `howl-vt/src/test/terminal_graphics.zig` first; fix only direct VT bugs in
  `howl-vt/src/kitty/graphics.zig` or `howl-vt/src/terminal.zig` if tests expose them.
- Do not touch render, ABI, host, virtual-placement ABI cleanup, or persistent generated
  refs in this slice.

Remaining Unicode placeholder acceptance tests:

- Third combining char selects image-id high byte and publishes only matching generated
  placements.
- Multiple virtual placements for one image resolve by underline placement id and publish
  distinct generated placements with expected source geometry/order.
- Scroll-region `index`/`reverse_index` over placeholder rows publishes surviving/moved
  generated placements from VT cell truth.
- Public `placeholder_run_count` remains `0`; proof-only APIs may be used only for
  internal assembly assertions.
- Existing generated placement dirty/publication tests remain green.

Stop conditions:

- Stop if correctness requires render-side placeholder parsing.
- Stop if correctness requires ABI changes.
- Stop if correctness requires persistent generated refs rather than on-demand VT
  publication.
- Stop if the scroll-region case depends on host viewport/render behavior rather than VT
  cell truth.

Remaining Unicode placeholder publication proof slice completed:

- `howl-vt` commit `70015a6 vt: prove unicode placeholder publication`.
- Tests-only slice proving high-byte third-combining-char selection, underline placement
  id resolution across multiple virtual placements, scroll-region `index` and
  `reverse_index` publication, and public `placeholder_run_count == 0`.
- No implementation, render, ABI, host, or persistent generated-ref changes were needed.
- Verification passed: `zig build test --summary all`,
  `zig build test:regression:build --summary all`, root `zig build`, root
  `git diff --check`, and `howl-vt` `git diff --check`.

### 10. Delete-all selectors are broader than Kitty visibility scope

Severity: medium, protocol correctness.

Kitty machinery:

- `kitty/graphics.c`: delete-all skips virtual refs and cell/generated refs.
- `kitty/graphics.c`: default `a=d`/`d=a` deletes visible non-cell refs only.
- `kitty/graphics.c`: `d=A` frees image data only for images whose matched visible refs were removed and are now unused.
- `utils/official_docs/kitty/graphics-protocol.md`: `d=a` deletes all visible placements; `d=A` also deletes image data that becomes unused.

Howl current shape:

- `howl-vt/src/kitty/graphics.zig`: `delete` handles `0, 'a', 'A'` by clearing all physical placements regardless of visibility.
- `howl-vt/src/kitty/graphics.zig`: `d=A` then deletes all images that become unplaced, including images whose only placements were retained/off-screen.
- Existing tests cover retained/off-screen placement states but not delete-all visibility scope.

Problem:

- Howl can delete retained/off-screen physical placements that Kitty would keep.
- Howl can free image data for retained/off-screen-only images on `d=A` even though Kitty only frees after matched visible refs are removed.

Promoted delete-all visibility slice:

- Make default `a=d`, `d=a`, and `d=A` operate on visible physical placements only.
- Preserve fully scrolled-above/off-screen retained physical placements.
- For `d=A`, free image data only for images that became unplaced because visible placements were removed.
- Keep virtual/generated/cell placeholder refs, frame deletion, quiet modes, ABI, render, host, and reset behavior out of scope unless directly required by the visible physical placement rule.

Delete-all visibility acceptance tests:

- `d=a` preserves a fully scrolled-above retained physical placement.
- Default `a=d` behaves like `d=a` and preserves a fully scrolled-above retained physical placement.
- `d=A` preserves image data for an image that only has off-screen/retained placements.
- `d=A` removes visible physical placements and frees only images that became unplaced because of matched visible placements.
- `d=a` removes visible parent placement and its relative descendants by lifetime.

Delete-all visibility slice completed:

- `howl-vt` commit `e912e32 vt: limit delete-all to visible placements`.
- Verification passed: `zig build test`, `zig build test:regression:build`, and root `git diff --check`.

### 11. Animation runtime edge cases differ from Kitty

Severity: medium, protocol/runtime correctness.

Kitty machinery:

- `kitty/graphics.c`: animation progression waits at the last frame in loading mode but advances as soon as a future frame is available after the deadline.
- `kitty/graphics.c`: finite loop counts are consumed at wrap time after the requested repeat count.
- `kitty/graphics.c`: frames with non-positive gap are not displayed as visible runtime frames.
- `kitty_tests/graphics.py`: animation frame loading tests cover loading mode, loop counts, and gapless-frame behavior.

Howl current shape:

- `howl-vt/src/kitty/graphics.zig`: `imageRuntimeObligation`, `progressImageRuntime`, `advanceRuntimeFrame`, and `nextRuntimeFrameNumber` own VT runtime progression.
- Existing tests cover frame gap storage and one basic runtime advance, but not loading-mode future-frame wake, finite repeat exhaustion, or gapless runtime visibility.

Problem:

- Howl can clear `current_frame_shown_at_ns` while loading waits at the last available frame, then wait another full gap after a future frame arrives.
- Howl's finite-loop stop check can stop before completing the requested repeat.
- Howl stores gapless negative-`z` frames but lacks proof that runtime skips them instead of publishing them.

Promoted animation runtime edge-case slice:

- Keep runtime progression VT-owned in `howl-vt/src/kitty/graphics.zig`.
- Make loading mode preserve enough timing state to advance immediately when a future frame arrives after the current frame's deadline.
- Fix finite loop accounting only as needed to match Kitty's requested repeat behavior.
- Ensure runtime skips stored gapless frames and publishes the next positive-gap frame.
- Leave ABI, render, host, parser, quiet, delete/reset, quota, composition, PNG, and generated-placeholder behavior unchanged.

Animation runtime acceptance tests:

- Loading animation advances immediately when a future frame arrives after waiting at the last available frame.
- Finite `v=2` two-frame animation publishes frame sequence `1 -> 2 -> 1 -> 2` before stopping on the next wrap attempt.
- Gapless negative-`z` frame is skipped by runtime publication while remaining stored.

Animation runtime edge-case slice completed:

- `howl-vt` commit `210d989 vt: fix graphics animation runtime`.
- Verification passed: `zig build test`, `zig build test:regression:build`, and root `git diff --check`.

### 12. Invalid PNG payloads do not produce Kitty `EBADPNG`

Severity: medium, protocol correctness and robustness.

Kitty machinery:

- `kitty_tests/graphics.py`: `test_load_png` expects invalid PNG upload failure code `EBADPNG`.
- `kitty_tests/graphics.py`: `test_load_png_simple` expects bad PNG decode to raise `[EBADPNG]`.
- `kitty/graphics.c` and `kitty/png-reader.c`: PNG decode failures are reported as command failures, not assertions.

Howl current shape:

- `howl-vt/src/kitty/graphics.zig`: `decodePngSize` asserts stb info success.
- `howl-vt/src/kitty/graphics.zig`: `decodeBase64PngRgbaOwned` uses `unreachable` for stb load failure.
- `howl-vt/src/kitty/graphics.zig`: command reply mapping distinguishes generic invalid data but not invalid PNG data.
- Existing tests cover valid PNG normalization/replay and PNG zlib rejection, but not invalid PNG protocol replies.

Problem:

- Invalid `f=100` payloads can trip assertions/unreachable or collapse into generic data errors instead of returning `EBADPNG`.
- This is observable at the graphics protocol boundary and should be handled before broader PNG parity work.

Promoted PNG EBADPNG slice:

- Add a PNG-specific decode error in VT graphics.
- Make PNG size/decode helpers return errors instead of asserting on invalid PNG payloads.
- Map invalid PNG payloads to `EBADPNG:*` replies for direct upload and query paths.
- Ensure invalid PNG uploads do not store image data.
- Leave full PNG mode matrix, color management, decoder replacement, PNG zlib support, ABI, render, host, and image-cache rewrites out of scope.

PNG EBADPNG acceptance tests:

- Invalid direct PNG upload returns `EBADPNG` and leaves image count unchanged.
- Invalid PNG query returns `EBADPNG` and leaves image count unchanged.
- Valid PNG normalization/replay tests remain green.

PNG EBADPNG slice completed:

- `howl-vt` commit `4d43182 vt: report invalid png graphics`.
- Review required full stb decode validation before storage, not only `stbi_info` header validation.
- Verification passed: `zig build test`, `zig build test:regression:build`, and root `git diff --check`.

### 13. Kitty simple PNG exact RGBA fixture is not directly ported

Severity: low-medium, test parity confidence.

Kitty machinery:

- `kitty_tests/graphics.py`: `test_load_png_simple` uses a 1x1 transparent PNG fixture.
- Expected decoded RGBA bytes are `00 ff ff 7f`, base64 `AP//fw==`.
- `kitty/png-reader.c`: PNG data is normalized to RGBA.

Howl current shape:

- Existing tests cover valid PNG normalization/replay with a Howl fixture and app-icon replay.
- Existing tests now cover invalid PNG `EBADPNG` behavior.
- No test directly ports Kitty's simple PNG fixture and exact expected bytes.

Problem:

- A source-backed simple valid PNG parity proof is missing.
- Full PNG mode matrix remains broader, but this fixture is narrow and likely tests-only.

Promoted simple PNG exact RGBA slice:

- Add a VT test using Kitty's 1x1 PNG fixture.
- Exercise through current-frame publication so the decoded RGBA bytes are observable at the VT model boundary.
- Assert published image is `format=32`, `width=1`, `height=1`, and `base64_payload="AP//fw=="`.
- Optionally prove `a=q,f=100` accepts the same PNG and stores no image.
- Leave PNG mode matrix, color management, decoder replacement, root decoded storage truth, ABI, render, host, and unrelated graphics behavior out of scope.

Simple PNG acceptance tests:

- Kitty 1x1 PNG fixture selected as a current frame publishes exact RGBA base64 `AP//fw==`.
- Optional query proof with the same PNG returns `OK` and stores no image.

Simple PNG exact RGBA slice completed:

- `howl-vt` commit `622cfd5 vt: prove simple png parity`.
- Tests-only slice using Kitty's 1x1 PNG fixture.
- Verification passed: `zig build test`, `zig build test:regression:build`, and root `git diff --check`.

### 14. Valid PNG query path is not directly proved

Severity: low-medium, protocol proof coverage.

Kitty machinery:

- `kitty/graphics.c`: query commands load/process data for validation but skip image/cache storage.
- `kitty_tests/graphics.py`: load query returns `OK` and image count stays zero.
- `kitty_tests/graphics.py`: simple PNG fixture is a source-backed valid PNG input.

Howl current shape:

- Existing tests prove raw `a=q` returns `OK` without storing.
- Existing tests prove invalid PNG query returns `EBADPNG` without storing.
- Existing tests prove Kitty's simple PNG fixture publishes exact RGBA through current-frame publication.
- No test directly proves valid PNG `a=q` validates and replies `OK` without storing.

Problem:

- Valid PNG query is a narrow protocol path not covered by the invalid-query or publication tests.

Promoted valid PNG query proof slice:

- Add a tests-only VT proof using Kitty's 1x1 PNG fixture with `a=q,f=100`.
- Assert reply is `OK` and image/placement/frame/upload state remains empty.
- Leave PNG mode matrix, color management, decoder replacement, ABI, render, host, and unrelated graphics behavior out of scope.

Valid PNG query acceptance tests:

- `a=q,f=100` with Kitty's 1x1 PNG fixture replies `OK` and stores no graphics state.

Valid PNG query proof slice completed:

- `howl-vt` commit `0649502 vt: prove png query parity`.
- Tests-only slice.
- Verification passed: `zig build test`, `zig build test:regression:build`, and root `git diff --check`.

### 15. PNG mode matrix needs fixed-fixture VT proof

Severity: medium, PNG parity confidence.

Kitty machinery:

- `kitty_tests/graphics.py`: `test_load_png` exercises RGBA and RGB, and visibly intends L/P mode coverage.
- `kitty/png-reader.c`: PNG input is normalized to RGBA by stripping/expanding modes and adding alpha.

Howl current shape:

- `howl-vt/src/kitty/graphics.zig`: `decodeBase64PngRgbaOwned` calls stb with requested channels `4`.
- Existing tests cover invalid PNG, simple RGBA PNG, valid PNG query, and app-icon replay.
- No fixed-fixture test covers RGB, grayscale, or palette PNG normalization.

Problem:

- The simple PNG proof covers one RGBA fixture only.
- A narrow fixed-fixture mode matrix can prove common PNG mode normalization without broad color-management or decoder replacement work.

Palette PNG blocker found:

- The fixed `P` fixture is rejected by current `stb_image` validation as `EBADPNG` while Kitty/libpng expands it.
- This is a decoder behavior dependency and is deferred instead of widening this proof slice.

Palette PNG blocker re-research:

- `kitty/png-reader.c` normalizes PNG input to RGBA. For palette PNGs it calls
  `png_set_palette_to_rgb`, converts `tRNS` chunks to alpha with
  `png_set_tRNS_to_alpha`, and adds opaque alpha where no alpha exists.
- The exact previously failed fixed `P` fixture is not preserved in the current tree or
  scratchpad, so the failure cannot be audited from committed bytes.
- Howl's vendored `stb_image` documents palette PNG depalettization and accepts a
  freshly generated valid palette PNG with `tRNS` when called directly with
  `stbi_info_from_memory` and `stbi_load_from_memory(..., 4)`.
- Do not replace the decoder or add custom palette expansion on the old blocker alone;
  first prove valid palette fixtures through the VT publication path.

Promoted palette PNG VT proof slice:

- Tests-only unless a valid fixture fails through Howl.
- Add fixed inline base64 fixtures for valid palette PNG and palette PNG with `tRNS`.
- Exercise current-frame publication and assert `format=32`, dimensions, and exact
  normalized RGBA payload.
- Leave decoder replacement, Wuffs/libpng dependency decisions, render decode matrix,
  gamma/ICC/color management, 16-bit/interlace/APNG, PNG zlib, ABI, host, and
  storage-model changes out of scope.

Palette PNG proof acceptance tests:

- Palette PNG fixture publishes expected palette-expanded RGBA bytes.
- Palette PNG with `tRNS` publishes exact alpha bytes.
- Existing RGBA/RGB/L PNG normalization tests remain green.
- Existing invalid PNG `EBADPNG` tests remain green.

Stop conditions:

- Stop if a valid palette fixture is rejected by direct vendored stb but accepted by
  Kitty/libpng.
- Stop if proving parity requires adding or replacing a PNG decoder.
- Stop if the slice grows into ABI, render storage, color management, or dependency
  policy.

Palette PNG VT proof slice completed:

- `howl-vt` commit `8e4d554 vt: prove palette png graphics`.
- Tests-only slice proving fixed palette PNG and palette `tRNS` fixtures publish exact
  normalized RGBA through VT current-frame publication.
- No decoder replacement or implementation change was needed for these valid fixtures.
- Verification passed: `zig build test --summary all`,
  `zig build test:regression:build --summary all`, root `zig build`, root
  `git diff --check`, and `howl-vt` `git diff --check`.

Promoted PNG non-palette mode matrix VT proof slice:

- Add fixed inline base64 fixtures for `RGBA`, `RGB`, and `L` mode PNGs.
- For each fixture, exercise current-frame publication and assert normalized raw RGBA output.
- Keep the slice VT tests-only unless a simple fixture exposes a real decode mismatch.
- Leave palette PNG, render decode matrix, gamma/ICC/color management, 16-bit/interlace/APNG, PNG zlib, ABI, host, and storage-model changes out of scope.

PNG mode matrix acceptance tests:

- RGBA PNG fixture publishes expected RGBA base64.
- RGB PNG fixture publishes expected RGBA base64 with alpha `ff`.
- L PNG fixture publishes expected grayscale-expanded RGBA base64.

PNG non-palette mode matrix proof slice completed:

- `howl-vt` commit `9ee74a1 vt: prove png mode normalization`.
- Tests-only slice covering RGBA, RGB, and grayscale `L`; palette `P` remains blocked on decoder behavior.
- Verification passed: `zig build test`, `zig build test:regression:build`, and root `git diff --check`.

### 16. Non-direct media incorrectly rejects `m=1`

Severity: medium, protocol compatibility.

Kitty/Ghostty machinery:

- Kitty `load_image_data` treats chunking as meaningful only for direct payloads and loads `t=f`, `t=t`, and `t=s` immediately.
- Ghostty explicitly ignores `m` for local-only media and notes Kitty/mpv compatibility.

Howl current shape:

- `howl-vt/src/kitty/graphics.zig`: `storeIndirectPayload` rejects `cmd.more_chunks` with `EINVAL:chunked kitty graphics upload requires direct medium`.
- Existing file/temp/shared-memory tests cover non-chunked media only.

Problem:

- Howl rejects valid Kitty/mpv-style local media commands that set `m=1` even though no continuation is needed for non-direct media.

Promoted ignore-indirect-`m` slice:

- Ignore `m=1` for `t=f`, `t=t`, and `t=s` in VT graphics indirect payload handling.
- Keep direct `t=d` chunk semantics unchanged.
- Keep safe temp deletion and shared-memory unlink policy unchanged.
- Leave parser, quiet, EBADPNG, quota, animation, delete/reset, render, host, and ABI code out of scope.

Ignore-indirect-`m` acceptance tests:

- File medium `t=f,m=1` loads and stores payload immediately with no active upload.
- Temp-file medium `t=t,m=1` loads, stores payload, deletes the safe temp file, and leaves no active upload.
- Shared-memory medium `t=s,m=1` loads, stores payload, unlinks the object, and leaves no active upload.

Ignore-indirect-`m` slice completed:

- `howl-vt` commit `21fb500 vt: ignore chunks for indirect graphics`.
- Verification passed: `zig build test`, `zig build test:regression:build`, and root `git diff --check`.

### 17. Raw direct payloads are retained without validation

Severity: medium, protocol correctness.

Kitty/Ghostty machinery:

- Kitty direct raw uploads accumulate decoded image bytes and reject insufficient or mismatched data size before loading.
- Kitty validates raw dimensions and requires loaded size to match `width * height * bytes_per_pixel`.
- Ghostty decodes APC payload base64 before execution and rejects completed images whose decoded data length does not match dimensions/depth.

Howl current shape:

- `howl-vt/src/kitty/graphics.zig`: `normalizeDirectPayloadOwned` duplicates uncompressed non-PNG payload bytes without validating base64 syntax or decoded length.
- `howl-vt/src/kitty/graphics.zig`: `expectedRawPayloadLen` already defines raw byte-length expectations for compressed raw payloads.
- Several VT graphics tests use fixture `s=2,v=1,t=d,f=24;QUJD`, which decodes to 3 bytes while the declared raw image requires 6 bytes.

Problem:

- Invalid direct raw data can become Howl image truth and pass through the ABI as retained base64.
- Existing successful-upload tests may be proving permissive invalid fixtures rather than protocol-correct raw image loading.

Promoted raw direct validation slice:

- Validate base64 syntax for uncompressed direct raw `f=24` and `f=32` uploads.
- Decode only for validation and keep retaining original base64 transport bytes for current ABI behavior.
- Require decoded byte length to equal `width * height * bytes_per_pixel`.
- Correct graphics and FFI-test success fixtures that currently declare dimensions larger than the decoded payload.
- Leave PNG, zlib, chunk lifecycle, parser, ABI, render, host, storage-model, animation, delete/reset, and generated-placeholder behavior out of scope.

Raw direct validation acceptance tests:

- Valid RGB direct raw upload succeeds.
- Valid RGBA direct raw upload succeeds.
- Invalid base64 direct raw upload fails with graphics `EINVAL` and stores no image.
- Decoded-length mismatch direct raw upload fails with graphics `EINVAL` and stores no image.

Raw direct validation slice completed:

- `howl-vt` commit `f71306a vt: validate direct raw graphics`.
- Verification passed: `zig build test`, `zig build test:regression:build`, and root `git diff --check`.

### 18. Indirect raw explicit-size undersize is accepted

Severity: medium, protocol correctness.

Kitty/Ghostty machinery:

- Kitty `mmap_img_file` maps `S=` bytes for file/shared-memory media.
- Kitty `initialize_load_data` computes raw RGB/RGBA byte count as `width * height * bytes_per_pixel` and rejects zero dimensions.
- Kitty `process_image_data` fails uncompressed indirect raw media with `ENODATA` when mapped bytes are smaller than the expected raw size.
- Ghostty `LoadingImage.readFile` reads local media with size bounds, and `LoadingImage.complete` rejects completed raw data whose length does not match dimensions/depth.

Howl current shape:

- `howl-vt/src/kitty/graphics.zig`: `loadIndirectPayloadNormalized` encodes uncompressed non-PNG indirect bytes without raw undersize validation.
- `howl-vt/src/kitty/graphics.zig`: `graphicsReadLength` uses explicit `S=` directly and only applies raw expected-length checks when `S=` is omitted.

Problem:

- `t=f`, `t=t`, or `t=s` with `f=24`/`f=32` and `S=` smaller than `width * height * bytes_per_pixel` can store undersized retained base64 payloads.

Promoted indirect raw undersize slice:

- Reject uncompressed indirect raw media whose loaded byte count is smaller than required by dimensions/depth.
- Preserve valid omitted-`S=` indirect raw behavior.
- Preserve safe temp deletion and shared-memory unlink policy.
- Leave larger-than-expected `S=`, PNG, zlib, direct media, parser, ABI, render, host, storage-model, animation, delete/reset, and generated-placeholder behavior out of scope.

Indirect raw undersize acceptance tests:

- File medium `t=f,S=2,s=1,v=1,f=24` against a 3-byte file fails with `ENODATA` and stores no image.
- Temp-file medium `t=t,S=2,s=1,v=1,f=24` fails with `ENODATA`, stores no image, and deletes a safe temp file.
- Shared-memory medium `t=s,S=2,s=1,v=1,f=24` fails with `ENODATA`, stores no image, and unlinks the object.

Indirect raw undersize slice completed:

- `howl-vt` commit `c12a3b7 vt: reject undersized indirect graphics`.
- Verification passed: `zig build test`, `zig build test:regression:build`, and root `git diff --check`.

### 19. Indirect raw explicit-size oversize is retained as image truth

Severity: medium, protocol correctness.

Kitty/Ghostty machinery:

- Kitty `mmap_img_file` maps `S=` bytes when present, but raw image truth remains `width * height * bytes_per_pixel`.
- Kitty `process_image_data` accepts indirect raw when mapped bytes are at least expected raw size.
- Kitty `handle_add_command` stores `currently_loading.data_sz` bytes, so extra mapped bytes are ignored.
- Ghostty clips local-media reads to the expected raw size and `LoadingImage.complete` requires final data length to match dimensions/depth.

Howl current shape:

- `howl-vt/src/kitty/graphics.zig`: `graphicsReadLength` honors explicit `S=` directly.
- `howl-vt/src/kitty/graphics.zig`: `loadIndirectPayloadNormalized` rejects undersize but still base64-encodes all loaded indirect raw bytes.

Problem:

- `t=f`, `t=t`, or `t=s` with `f=24`/`f=32` and `S=` larger than expected can retain trailing padding as image payload.

Promoted indirect raw oversize slice:

- For uncompressed indirect raw media, retain and publish only the expected raw byte count.
- Keep undersize validation and omitted-`S=` behavior unchanged.
- Preserve safe temp deletion and shared-memory unlink policy.
- Leave PNG, zlib, direct media, parser, ABI, render, host, storage-model, animation, delete/reset, and generated-placeholder behavior out of scope.

Indirect raw oversize acceptance tests:

- File medium `t=f,S=5,s=1,v=1,f=24` over `ABCXY` stores payload `QUJD` for `ABC` only.
- Temp-file medium `t=t,S=5,s=1,v=1,f=24` stores `QUJD` and deletes a safe temp file.
- Shared-memory medium `t=s,S=5,s=1,v=1,f=24` stores `QUJD` and unlinks the object.

Indirect raw oversize slice completed:

- `howl-vt` commit `7ffbc54 vt: truncate oversized indirect graphics`.
- Verification passed: `zig build test`, `zig build test:regression:build`, and root `git diff --check`.

### 20. Graphics query without lowercase image id replies incorrectly

Severity: low-medium, protocol correctness.

Kitty machinery:

- Kitty `handle_graphics_command` handles `a=q` by saving lowercase `i=` as `q_iid`, setting upload target `iid=0`, and breaking with only an internal error report when `q_iid == 0`.
- Kitty query response is built with `finish_command_response(&(GraphicsCommand){.id=q_iid, ...}, ...)`, so query replies are keyed only by lowercase `i=`.
- `finish_command_response` emits no protocol reply when neither `id` nor `image_number` is present.

Howl current shape:

- `howl-vt/src/kitty/graphics.zig`: `State.handle` dispatches all `a=q` commands to `queryImageSupport` before checking for lowercase `i=`.
- `queryImageSupport` can validate payloads and append replies using `cmd.image_id`, including `i=0` or validation failures for missing-`i=` queries.

Problem:

- Howl can emit query replies or validation failures for `a=q` without lowercase `i=`, while Kitty emits no graphics protocol reply and stores no image.

Promoted require-query-`i` slice:

- `a=q` with lowercase `i=` keeps existing query behavior.
- `a=q` without lowercase `i=` emits no protocol reply and stores no image.
- `a=q,I=...` without lowercase `i=` also emits no protocol reply and stores no image.
- Missing-`i=` queries do not validate payloads or emit payload validation failures.
- Leave upload/place/delete/frame/animation/media/parser/ABI/render/host behavior out of scope.

Require-query-`i` acceptance tests:

- Missing-`i=` query produces no output and stores no image.
- Image-number-only query produces no output and stores no image.
- Missing-`i=` invalid PNG query produces no `EBADPNG` output and stores no image.
- Existing lowercase-`i=` query success still returns `OK` and stores no image.

Require-query-`i` slice completed:

- `howl-vt` commit `bb49020 vt: require image id for graphics query`.
- Verification passed: `zig build test`, `zig build test:regression:build`, and root `git diff --check`.

Research notes for later slices:

- Animation frame dimensions larger than the base image may be a future VT-only slice, but failure reply behavior should be researched before promotion.

### 21. Direct raw oversize slack is rejected instead of truncated

Severity: medium, protocol correctness.

Kitty machinery:

- Kitty `parse_graphics_code` base64-decodes APC payloads before graphics dispatch, so `load_image_data` receives decoded image bytes.
- Kitty `initialize_load_data` computes raw RGB/RGBA byte count as `width * height * bytes_per_pixel`.
- For direct uncompressed raw uploads, Kitty allocates `data_sz + 10` bytes of direct-upload buffer slack.
- Kitty `load_image_data` rejects raw direct data that needs to grow beyond that initial slack with `EFBIG`, but accepts cumulative decoded length up to `expected_raw_len + 10`.
- Kitty storage uses `currently_loading.data_sz`, so accepted slack bytes are ignored.

Howl current shape:

- `howl-vt/src/kitty/protocol.zig`: direct payloads remain base64 text after parsing.
- `howl-vt/src/kitty/graphics.zig`: `validateBase64RawPayload` currently requires decoded raw length to equal expected length exactly.
- Completed chunked direct uploads concatenate base64 text and run through `normalizeDirectPayloadOwned` at completion.

Problem:

- Howl rejects direct raw payloads with decoded length in Kitty's accepted `expected_raw_len + 10` slack range.
- If slack is accepted, Howl must not retain trailing slack bytes as image truth.

Promoted direct raw oversize slack slice:

- Accept uncompressed direct raw payloads whose decoded length is greater than expected raw length and no more than `expected_raw_len + 10`.
- Retain/publish only the first expected raw bytes, re-encoded as base64.
- Keep exact-length direct raw behavior unchanged.
- Keep undersize and invalid-base64 behavior unchanged.
- Keep larger-than-slack rejection on Howl's existing invalid raw failure path; exact Kitty `EFBIG` taxonomy is deferred.
- Leave parser payload ownership, PNG, zlib, indirect media, ABI, render, host, storage-model, animation, frame, delete/reset, and generated-placeholder behavior out of scope.

Direct raw oversize slack acceptance tests:

- Single direct RGB raw upload with decoded length `expected + 10` stores only the expected bytes.
- Single direct RGBA raw upload with decoded length `expected + 10` stores only the expected bytes.
- Single direct raw upload with decoded length `expected + 11` rejects and stores no image.
- Chunked direct RGB raw upload with final decoded length `expected + 10` stores only the expected bytes.
- Chunked direct raw upload with final decoded length `expected + 11` rejects and stores no image.

Direct raw oversize slack slice completed:

- `howl-vt` commit `a086dd2 vt: truncate direct raw graphics slack`.
- Verification passed: `zig build test`, `zig build test:regression:build`, and root `git diff --check`.

Research notes for later slices:

- Exact Kitty `EFBIG` response taxonomy for larger-than-slack direct raw remains deferred.

Exact direct-raw `EFBIG` taxonomy research:

- `kitty/parse-graphics-command.h:326-337`: Kitty base64-decodes APC payloads before
  graphics dispatch, so direct chunk sizes are decoded byte lengths.
- `kitty/graphics.c:667-681`: raw RGB/RGBA direct uploads allocate
  `expected_raw_len + 10` bytes for uncompressed data.
- `kitty/graphics.c:554-568`: each direct chunk append checks remaining buffer and
  rejects non-PNG over-capacity data with `EFBIG:Too much data`.
- Cumulative decoded direct raw bytes up to `expected_raw_len + 10` are accepted, but
  trailing slack is ignored as image truth.
- The first direct raw append that would exceed `expected_raw_len + 10` replies
  `EFBIG:Too much data`; chunked direct raw uses the same check.
- Existing quiet behavior applies: `q=1` emits failures and `q=2` suppresses them.
- Howl currently rejects beyond-slack direct raw as `EINVAL:invalid kitty graphics data`.

Promoted direct raw `EFBIG` taxonomy slice:

- VT-only, ABI-preserving.
- Distinguish decoded direct raw oversize beyond Kitty's `+10` slack from other invalid
  raw data.
- Reply with `EFBIG:Too much data` for single direct raw uploads and completed chunked
  direct raw uploads that exceed the slack.
- Preserve `EINVAL:invalid kitty graphics data` for undersize raw, invalid base64, and
  non-oversize invalid raw data.
- Preserve accepted `expected_raw_len + 10` truncation behavior.
- Leave PNG, zlib, indirect media, parser payload ownership, render, host, ABI, storage,
  placement, animation, delete/reset, and generated-placeholder behavior out of scope.

Direct raw `EFBIG` acceptance tests:

- Single direct RGB raw upload with decoded length `expected + 11` replies
  `EFBIG:Too much data` and stores no image.
- Chunked direct RGB raw upload with final decoded length `expected + 11` replies
  `EFBIG:Too much data`, clears pending upload, and stores no image.
- Single direct raw `expected + 11,q=1` emits the same failure reply.
- Single direct raw `expected + 11,q=2` emits no reply and stores no image.
- Existing `expected + 10` slack tests, undersize tests, and invalid-base64 tests remain
  green with their existing behavior.

Direct raw `EFBIG` taxonomy slice completed:

- `howl-vt` commit `e2b76f2 vt: report oversized raw graphics`.
- Review rejected the first pass because invalid base64 with a large calculated decoded
  length was classified before base64 decode validation; the accepted implementation
  decodes before returning `EFBIG`, preserving invalid-base64 `EINVAL` taxonomy.
- Verification passed: `zig build test --summary all`,
  `zig build test:regression:build --summary all`, root `zig build`, root
  `git diff --check`, and `howl-vt` `git diff --check`.

### 22. Animation frame dimensions may exceed base image dimensions

Severity: medium, protocol correctness.

Kitty machinery:

- Kitty `handle_animation_frame_load_command` loads/processes frame payloads, then rejects when loaded frame width is greater than base image width.
- Kitty also rejects when loaded frame height is greater than base image height.
- Failure replies are `EINVAL:Frame width {frame_width} larger than image width: {image_width}` and `EINVAL:Frame height {frame_height} larger than image height: {image_height}` through `finish_command_response`.
- `q=1` still emits failures; `q=2` suppresses failures.

Howl current shape:

- `howl-vt/src/kitty/graphics.zig`: `storePayload` sends `a=f` uploads directly to `storeFrameOwned` after payload normalization.
- `storeFrameOwned` computes intrinsic frame dimensions but does not reject dimensions larger than the base image before storing or replacing frame state.

Problem:

- Howl can store animation frames whose dimensions exceed the base image dimensions, which Kitty rejects.

Promoted oversized-animation-frame slice:

- Add the smallest pre-mutation check for `a=f` frame uploads.
- Reject frame width greater than base image width with Kitty-style `EINVAL` failure.
- Reject frame height greater than base image height with Kitty-style `EINVAL` failure.
- Preserve existing image/frame state on rejection and honor quiet failure suppression.
- Leave broader root-frame edit parity, frame graph/ref semantics, cache/storage identity, animation runtime, parser, ABI, render, host, and decoded-storage work out of scope.

Oversized-animation-frame acceptance tests:

- Width-oversized raw frame upload against a `1x1` base image replies with the width `EINVAL` and stores no frame.
- Height-oversized raw frame upload against a `1x1` base image replies with the height `EINVAL` and stores no frame.
- Existing-frame edit with oversized dimensions rejects and preserves previous frame payload/metadata.
- `q=1` emits the failure; `q=2` suppresses the failure and stores no frame.

Oversized-animation-frame slice completed:

- `howl-vt` commit `ed8e3b3 vt: reject oversized graphics frames`.
- Verification passed: `zig build test`, `zig build test:regression:build`, and root `git diff --check`.

### 23. Commands with both image id and image number are not uniformly rejected

Severity: medium, protocol correctness.

Kitty/Ghostty machinery:

- Kitty docs state that specifying both `i` and `I` in any graphics command is an error and must reply with `EINVAL` unless silenced.
- Kitty `handle_graphics_command` checks `g->id && g->image_number` before action dispatch and replies `EINVAL:Must not specify both image id and image number`.
- Ghostty rejects transmit commands with both image id and image number as mutually exclusive.

Howl current shape:

- `howl-vt/src/kitty/graphics.zig`: `resolveImageId` returns null for both ids, making some commands report `ENOENT`.
- Upload paths use `imageIdForUpload`, which can prefer lowercase `i=` and store a command that should be rejected.

Problem:

- Commands with both id forms can mutate state or report the wrong failure class instead of failing uniformly before command-specific behavior.

Promoted both-id rejection slice:

- Reject any graphics command with both `image_id` and `image_number` before command-specific mutation.
- Reply with `EINVAL:Must not specify both image id and image number` unless quiet failure suppression applies.
- Preserve existing valid `i=` only, `I=` only, and anonymous behavior.
- Leave parser changes, identity/ref rewrites, ABI, render, host, media normalization, query/delete/frame/animation semantics, storage, and generated placeholders out of scope.

Both-id rejection acceptance tests:

- Direct transmit with both id forms rejects and stores no image.
- Place with both id forms rejects as `EINVAL` instead of `ENOENT` and stores no placement.
- Animation/frame path with both id forms rejects before mutation.
- `q=2` suppresses the failure and still does not mutate state.

Both-id rejection slice completed:

- `howl-vt` commit `6b65f19 vt: reject graphics id conflicts`.
- Verification passed: `zig build test`, `zig build test:regression:build`, and root `git diff --check`.

Research notes for later slices:

- Root-frame edit parity remains broader and should not be pulled into this oversized-frame slice.
- Exact Kitty `EFBIG` response taxonomy for larger-than-slack direct raw remains deferred.

### 24. Combined animation controls reject real Kitty Go traffic

Severity: medium-high, real client animation compatibility.

Kitty source truth:

- `kitty/graphics.h`: command fields intentionally overlap by action; `s`, `v`, `r`,
  `c`, `z`, and `C` carry animation/frame meanings for graphics commands.
- `kitty/parse-graphics-command.h`: accepts `a=a`, `s`, `v`, `r`, `c`, and `z` in the
  same control block.
- `kitty/graphics.c:1729-1769`: `handle_animation_control_command` applies all present
  controls independently in one command: frame gap by `r/z`, current-frame select by
  `c`, animation state by `s`, and loop count by `v`.

Real Go client traffic:

- `kittens/icat/transmit.go:318-367`: `icat` reuses one animation control command.
  After root upload it writes `a=a,r=<root>,z=<root_gap>[,v=<loops>]`; after frame 1
  it writes loading mode by adding `s=2` while retaining `r/z/v`; after all frames it
  writes running mode by changing `s=3` while still retaining `r/z/v`.
- `kittens/choose_files/graphics.go:199-247`: `choose_files` uses the same retained
  command pattern, with `v=1` retained for previews.
- `kittens/icat/transmit.go:46-81` and `kittens/choose_files/graphics.go:201-227`:
  extra frames use `a=f`, `z=<delay>`, `C=1` for replacement, `c=<compose_onto>`, and
  `x/y` frame offsets.

Howl current shape:

- `howl-vt/src/kitty/protocol.zig`: parser already preserves the overlapped fields.
- `howl-vt/src/kitty/graphics.zig:913-920`: `controlAnimation` counts control
  categories and rejects commands containing more than one category.
- Existing runtime tests split controls into separate commands; they do not replay the
  retained Go command shape.

Problem:

- Real Kitty Go clients can send `a=a,s=2,r=1,z=7,v=1` or `a=a,s=3,r=1,z=7,v=1`.
- Kitty accepts and applies these combined controls.
- Howl rejects them as `EINVAL`, so animated `icat` and `choose_files` traffic can fail
  even though isolated frame upload/runtime tests pass.

Promoted combined-animation-control slice:

- VT-only, ABI-preserving.
- Change `controlAnimation` so one `a=a` command may apply all present Kitty controls.
- Apply `r/z` frame-gap edit when `r` is present and `z != 0`.
- Apply `c` current-frame selection when `c` is present.
- Apply `s` animation state when `s` is present.
- Apply `v` loop count when `v` is present.
- Preserve existing success/failure reply behavior and quiet behavior.
- Leave parser, render, host, ABI, frame upload, compose, delete, runtime timing,
  storage identity, and generated placeholders out of scope.

Combined-animation-control acceptance tests:

- `icat`-style direct replay: root upload, extra frame upload, `a=a,r=1,z=7`,
  `a=a,s=2,r=1,z=7`, then `a=a,s=3,r=1,z=7` produces no `EINVAL`, preserves root gap,
  reaches running state, and runtime advances.
- `choose_files`-style replay with retained `v=1`: `a=a,r=1,z=7,v=1`,
  `a=a,s=2,r=1,z=7,v=1`, then `a=a,s=3,r=1,z=7,v=1` preserves the expected finite-loop
  state and runtime behavior.
- Loading replay with retained `r/z/v` still advances immediately when a future frame is
  uploaded after waiting at the last available frame.
- Existing split-control runtime tests continue to pass.

Stop conditions:

- Stop if accepting combined controls conflicts with a deeper Howl invariant; reshape
  `controlAnimation` around Kitty's independent-field model instead of adding a special
  Go-client exception.
- Stop if a replay requires chunking, compression, file media, render, or host behavior;
  keep this slice to animation-control semantics only.

Combined-animation-control slice completed:

- `howl-vt` commit `30cbfc9 vt: accept combined animation controls`.
- Verification passed: `zig build test --summary all`,
  `zig build test:regression:build --summary all`, root `zig build`, root
  `git diff --check`, and `howl-vt` `git diff --check`.

### 25. Root-frame edits with `a=f,r=1` diverge from Kitty

Severity: medium, frame edit parity.

Kitty source truth:

- `kitty/graphics.h`: root frame is stored separately from extra frames.
- `kitty/graphics.c:1334-1344`: frame number `1` maps to root, `2+` maps to extra
  frames, and `0` is missing.
- `kitty/graphics.c:1557-1561`: omitted/zero or too-large `r` on `a=f` appends at the
  next extra-frame number.
- `kitty/graphics.c:1648-1667`: `a=f,r=1` uses the existing-frame edit path. It
  coalesces current root data, composes the transmitted rectangle at `x/y`, preserves
  full root dimensions, and stores the result back as root.
- `kitty/graphics.c:1347-1353` and `kitty/graphics.c:1651`: existing-frame edit changes
  gap only when `z != 0`, clamping negative gaps to `0`.

Howl current shape:

- `howl-vt/src/kitty/graphics.zig`: root image bytes live on `Image`; extra frames live
  in `State.frames`.
- `howl-vt/src/kitty/graphics.zig`: `a=f,r=1` has an ad hoc root replacement path that
  only accepts full root replacement under narrow conditions.
- Partial `a=f,r=1,x/y/s/v` root edits are not Kitty-compatible.
- Root replacement can change root dimensions to transmitted dimensions, while Kitty's
  root edit preserves full image dimensions after composition.

Root-frame-edit future slice:

- Keep omitted `r` and `r=0` as append-new-extra-frame behavior.
- Normalize too-large explicit `r` to append at the next frame number.
- Implement `a=f,r=1` as existing root-frame edit, including partial rectangle compose
  at `x/y` and full root dimension preservation.
- Preserve root gap for omitted/zero `z`; update root gap for nonzero `z` and clamp
  negative gaps to `0`.
- Leave ABI, render, host, decoded-cache storage, frame graph identity, runtime timing,
  PNG/media, and generated placeholders out of scope.

Root-frame-edit slice completed:

- `howl-vt` commit `3b39abe vt: edit kitty root frames`.
- Review caught and corrected `a=f,r=1,c=<missing>`: Kitty ignores `c` on existing
  frame edits, so root edits must not pre-resolve the compose base frame.
- Verification passed: `zig build test --summary all`,
  `zig build test:regression:build --summary all`, root `zig build`, root
  `git diff --check`, and `howl-vt` `git diff --check`.

### 26. Go animation frame uploads omit `r=` and need replay proof

Severity: medium, real client animation proof.

Kitty and Go source truth:

- `kitty_tests/graphics.py:1132-1186`: Kitty proves missing-image `a=f`, root upload,
  chunked frame upload, omitted-`r` append, frame edits, partial edits, and base-frame
  loading in `test_animation_frame_loading`.
- `kitty/graphics.c:1557-1561`: omitted/zero/out-of-range frame numbers append the next
  extra frame.
- `kittens/icat/transmit.go:46-81`: `icat` uploads frame `0` as root and extra frames
  as `a=f` with `z`, `C`, `c`, `x`, and `y`, but without serializing `r=`.
- `kittens/choose_files/graphics.go:199-247`: `choose_files` also sends extra frames
  without `r=` and then retained animation controls.

Howl current shape:

- `howl-vt/src/kitty/graphics.zig`: `storeFrameOwned` appears to append when
  `frame_number == 0`, but real Go omitted-`r` traffic is under-proved.
- Current animation replay tests prove retained controls but use explicit `r=2`/`r=3`
  frame uploads before those controls.

Promoted omitted-`r` frame upload proof slice:

- Tests-only unless a real mismatch is exposed.
- Prove direct `a=f` without `r=` appends frame `2` after root upload.
- Prove repeated direct omitted-`r` frame uploads append frames in order.
- Prove chunked omitted-`r` frame upload captures the append target from the first chunk
  and stores one frame at completion.
- Prove Go-style omitted-`r` frame upload plus retained combined `a=a` controls advances
  runtime.
- Leave root-frame edit parity, parser, render, host, ABI, decoded-cache storage, frame
  graph rewrite, compose/delete, media transports, and runtime timing changes out of
  scope unless these tests expose a direct bug.

Omitted-`r` proof acceptance tests:

- Direct omitted-`r` `a=f` after root upload stores frame `2`.
- A second direct omitted-`r` `a=f` stores frame `3`.
- Chunked omitted-`r` `a=f,m=1` followed by final chunk stores exactly one appended
  frame with the expected payload.
- `icat`-style replay uses omitted-`r` frame upload plus retained `a=a,r/z`, `s=2`,
  and `s=3`, and then advances runtime.
- `choose_files`-style replay uses omitted-`r` frame upload plus retained `v=1` and
  preserves the expected loop state.

Omitted-`r` frame upload proof completed:

- Tests-only; no implementation mismatch found.
- `howl-vt` commit `3c03285 vt: prove omitted frame append`.
- Verification passed: `zig build test --summary all`,
  `zig build test:regression:build --summary all`, root `zig build`, root
  `git diff --check`, and `howl-vt` `git diff --check`.

## Current Live Graphics Gaps

### 1. Base64 retained payload remains graphics truth

Ownership: VT/render/ABI cross-submodule.

Risk: high; do not start with deletion-only work.

Source contradiction:

- Kitty stores loaded image/frame data with cache/texture refs, not base64 transport text
  as model truth.
- Ghostty stores loaded image state and render placements, not base64 transport text as
  graphics truth.

Current Howl shape:

- `howl-vt/src/kitty/graphics.zig`: `Image.base64_payload`, `Frame.base64_payload`,
  `storeImageOwned`, `storeFrameOwned`, and `refreshCurrentFramePublication` keep
  base64 retained payload as VT graphics state.
- `howl-render/src/frame/graphics_prepare.zig`: render decodes graphics rasters from
  ABI payload bytes.

Next safe work:

- Research/design the ABI-preserving bridge from transport base64 to decoded/validated
  VT-owned image/frame bytes before changing code.
- Do not remove retained payload fields or ABI payload publication without an explicit C
  ABI/storage contract slice.
- Correction from the chunk-decode proof attempt: Kitty's `base64_decode8()` decodes each
  APC payload before graphics dispatch but ignores libbase64's return value. A partial
  chunk such as `Q` is therefore not a parser rejection; it contributes zero decoded
  bytes. The observable mismatch is still real because Howl concatenates base64 text
  before final validation, while Kitty/Ghostty concatenate decoded bytes.
- The tempting narrow test `m=1;Q` then `m=0;UJD` should not be implemented as a parser
  rejection proof. Making it source-true requires an explicit decoded-transport bridge:
  pending direct chunks must accumulate decoded bytes, then the current ABI-preserving
  retained payload, if kept temporarily, must be derived from those bytes rather than
  from concatenated base64 text.
- Research verdict: promote a VT-only decoded-transport bridge now. The bridge is
  ABI-preserving because `Upload.data` can become decoded pending bytes, then final
  storage can re-encode once and continue publishing base64 through `Image.base64_payload`,
  `Frame.base64_payload`, FFI, render, and host. Stop if implementation requires changing
  `howl_vt_terminal_copy_graphics_payload`, render payload decode, or host publication.
- Direct chunk decoded-transport bridge completed in `howl-vt` commit `8beeb93
  vt: decode direct graphics chunks`.
- Accepted behavior: chunked direct uploads decode each APC payload independently into
  pending decoded bytes, then re-encode once for the existing retained base64 ABI seam.
- Proofs include a non-concatenation case where `m=1;Q` followed by `m=0;UJD` no longer
  stores `ABC`, valid-boundary chunk success, raw slack/EFBIG preservation, zlib chunk
  preservation, frame upload preservation, and FFI fixture updates.
- Verification passed after main-agent review fixes: `zig build test --summary all` in
  `howl-vt`, `zig build test:regression:build --summary all` in `howl-vt`, root
  `zig build --summary all`, root `git diff --check`, and `howl-vt git diff --check`.
- Main-agent review fixed two accountability issues before commit: decode
  `ConsequenceLimit` now aborts the pending upload, and retained-payload accounting counts
  pending decoded upload bytes by their final base64 encoded size.

### 2. Animation runtime is not drawn-visibility gated

Ownership: VT/runtime plus render/host visibility truth; likely cross-submodule.

Risk: completed for drawn-feedback gate; remaining cache/presentation edge cases are
medium.

Source truth:

- Kitty updates image visibility/drawn state from visible refs and advances animations
  only for drawn images.
- Howl now gates `imageNeedsRuntime` on VT image drawn state, which is fed by render
  prepared graphics image refs through the host and C ABI.

Completed slice:

- Kitty `grman_update_layers()` resets `Image.is_drawn`, skips virtual refs, skips
  off-screen refs, and sets drawn only after visible non-virtual render data exists;
  `image_is_animatable()` requires that drawn bit.
- Ghostty has no direct runtime model because Kitty graphics animation is not
  implemented there.
- VT images now carry stable nonzero `image_ref_id` values.
- Render preserves `image_ref_id` through visible/clipped/raster-bound prepared
  graphics refs and exposes those refs from prepared surfaces.
- Host reports rendered prepared image refs to VT with
  `howl_vt_terminal_note_drawn_graphics`.
- VT tests cover unplaced animation, deleted-placement plus empty drawn feedback,
  and virtual-only/no-placeholder animation having no runtime obligation.
- Render tests cover visible placement preserving the image ref id and fully
  off-screen placement producing no prepared image refs.

Remaining caution:

- The drawn set is render-feedback cached, matching Kitty's layer-update model more
  closely than eager VT mutation. Do not replace it with VT placement-count policy.

### 3. Persistent generated cell refs are not implemented

Ownership: VT first; possible ABI/render follow-up.

Risk: medium-high.

Source truth:

- Kitty materializes placeholder cells into real cell-image refs and removes stale refs
  when rows/cells are dirtied.
- Howl currently derives generated placements on demand from live VT cell truth.

Current proof status:

- Placeholder assembly, dirty/publication behavior, render order, palette/yazi-like
  publication, high-byte image ids, multiple virtual placements, and scroll-region
  placeholder publication have durable tests.

Next safe work:

- Do not add persistent generated refs unless a new Kitty behavior proof exposes an
  observable mismatch in on-demand publication.

### 4. Full decoded/cache quota parity is incomplete

Ownership: VT/render/ABI cross-submodule.

Risk: medium-high.

Source truth:

- Kitty accounts decoded/cache storage and evicts incomplete, unreferenced, and old
  images through cache/storage policy.
- Howl currently enforces conservative retained-payload quotas and has tests for that
  first slice.

Next safe work:

- Research decoded/cache storage ownership together with the base64-truth replacement.
- Do not widen quota code independently of the storage model.

Decoded storage ABI research after direct chunk bridge:

- Verdict: first slice is worker-ready.
- Kitty source truth: parser decodes APC payloads before graphics dispatch; `LoadData`
  owns decoded bytes for direct payloads, mapped file/temp/shared-memory data, zlib
  inflated bytes, and PNG-decoded bytes before image/frame storage. Image/frame metadata
  and cache entries are not base64 payload truth.
- Ghostty source truth: graphics command parsing returns owned decoded `data`; loading
  images and completed images own decoded bytes; storage quota/eviction accounts decoded
  `Image.data.len`.
- Howl product ABI truth: `HowlVtGraphicsImage.payload_len` and
  `howl_vt_terminal_copy_graphics_payload` explicitly expose retained protocol/base64
  bytes and must remain byte-for-byte compatible unless a product-breaking ABI decision
  is made.
- Howl stale internal shape: `Image.base64_payload`, `Frame.base64_payload`, current-frame
  coalescing from retained base64, and render decoding from the old payload ABI. These
  should be transitioned behind an additive decoded publication path rather than broken
  in place.
- Promoted next slice: add parallel VT decoded graphics image query/copy ABI, preserve the
  existing base64 ABI exactly, keep render/host switchover out of scope, and prove direct
  raw, zlib, PNG RGBA, chunked direct, and invalid publication/index behavior in VT tests.
- Stop conditions: no old ABI behavior changes, no render/host switchover, no unbounded
  decoded memory duplication, no frame-graph redesign hidden in the ABI slice.
- VT decoded publication ABI completed in `howl-vt` commit `386ae6a vt: expose decoded
  graphics payloads`.
- Accepted behavior: new parallel decoded query/copy ABI exposes VT-owned decoded bytes
  while the existing base64/protocol payload ABI remains unchanged. Decoded publication
  covers direct RGB/RGBA, zlib, chunked direct, and PNG-as-RGBA. Invalid publication and
  image-index checks are covered for decoded APIs.
- Verification passed after main-agent review: `zig build test --summary all` in
  `howl-vt`, `zig build test:regression:build --summary all` in `howl-vt`, root
  `zig build --summary all`, root `git diff --check`, and `howl-vt git diff --check`.
- Next safe work: research how render/host should consume decoded VT publication without
  breaking the existing render base64 ABI or moving Kitty protocol decode into host/render.

Decoded render bridge research:

- Verdict: first slice is worker-ready and owned by `howl-render`.
- Existing render ABI truth: `HowlRenderPublishSlotCommit`, `HowlRenderVtSurface`, and
  internal `PublicationSource.graphics_payload_bytes` carry old VT `HowlVtGraphicsImage`
  metadata plus base64/protocol payload bytes. `graphics_prepare.zig` decodes those bytes
  from base64 for RGB/RGBA.
- Dependency order: render must gain decoded ABI before Linux host switches to VT decoded
  copy APIs. If the host switched first, old render ABI would treat decoded pixels as
  base64. Host re-encoding is rejected as wrong ownership and wasted work.
- Promoted next slice: add a parallel render decoded commit-slot ABI, preserve old render
  ABI unchanged, add explicit internal payload kind (`legacy base64/protocol` vs `decoded
  pixels`), validate decoded RGB/RGBA byte lengths, and include payload kind in raster
  cache keys.
- Out of scope for first slice: Linux host switchover, old ABI deprecation, direct decoded
  `publish_vt_source` unless required by implementation coherence, quota/eviction
  redesign, and renderer-side Kitty protocol interpretation.
- Render decoded graphics commit ABI completed in `howl-render` commit `0313678 render:
  accept decoded graphics payloads`.
- Accepted behavior: render now has a parallel decoded commit-slot ABI, keeps existing
  base64/protocol ABI unchanged, validates decoded RGB/RGBA lengths, rejects unsupported
  decoded formats, and keys raster cache entries by payload kind.
- Verification passed after main-agent review fix for zero decoded dimensions:
  `zig build test --summary all` in `howl-render`, root `zig build --summary all`, root
  `git diff --check`, and `howl-render git diff --check`.
- Next safe work: switch Linux host graphics acquisition to VT decoded query/copy and
  render decoded commit ABI. Do not decode or re-encode protocol payloads in host.
- Linux host decoded graphics bridge completed in `howl-linux-host` commit `966cb78
  host: publish decoded graphics payloads`.
- Accepted behavior: host now queries VT decoded image metadata, copies VT decoded payload
  bytes, and commits through render's decoded graphics slot. Host continues to own only
  transient ABI copies and does not decode or re-encode protocol payloads.
- Verification passed: `zig build test:integration:kitty-graphics-replay:build --summary
  all` in `howl-linux-host`, `zig build
  test:integration:kitty-graphics-replay:app:build --summary all` in `howl-linux-host`,
  root `zig build --summary all`, root `git diff --check`, and `howl-linux-host git diff
  --check`.
- Broader `zig build test --summary all` in `howl-linux-host` still has an unrelated
  app-loop failure expecting `error.ActiveTabExited` and receiving `void`; it is not part
  of this graphics slice.
- End-to-end decoded graphics publication path is now present from VT through host into
  render. Remaining work is compatibility/internal cleanup: classify old base64/protocol
  paths as public ABI compatibility, internal debt, or still-needed bridge before removing
  anything.

Base64 compatibility retirement research:

- Verdict: first cleanup slice is worker-ready and owned by `howl-vt`.
- Public ABI compatibility that must remain: VT `HowlVtGraphicsImage.payload_len`,
  `howl_vt_terminal_query_graphics_image`, `howl_vt_terminal_copy_graphics_payload`,
  render `HowlRenderPublishSlotCommit`, `HowlRenderVtSurface.graphics_payload_bytes`,
  and `howl_render_surface_text_commit_publish_slot`.
- Internal debt: VT `Image.base64_payload`, `Frame.base64_payload`,
  `current_override_payload`, direct/indirect normalization returning base64 as model
  truth, and frame coalescing decoding from legacy base64 fields.
- Still-needed bridges: VT decoded query/copy ABI, render payload-kind split, and host
  decoded VT-to-render bridge.
- Promoted next slice: VT-only decoded-truth internal cleanup. Decoded image/frame bytes
  become the source for frame coalescing while old base64/protocol bytes remain bounded
  compatibility publication for old ABI copy/query APIs.
- Stop conditions: no old ABI byte changes, no render/host changes, no quota/eviction
  redesign, no broad frame graph rewrite.
- VT decoded-truth cleanup completed in `howl-vt` commit `e944cdc vt: coalesce graphics
  from decoded payloads`.
- Accepted behavior: VT internal image/frame coalescing now reads decoded payload bytes,
  not old compatibility base64/protocol bytes. Old public payload query/copy ABI remains
  byte-compatible through `legacy_payload`; decoded query/copy remains unchanged.
- Verification passed after main-agent review cleanup removing dead base64 RGBA helpers:
  `zig build test --summary all` in `howl-vt`, `zig build test:regression:build --summary
  all` in `howl-vt`, root `zig build --summary all`, root `git diff --check`, and
  `howl-vt git diff --check`.
- Next safe work: research decoded storage quota/eviction now that VT decoded bytes are
  model truth. Keep render raster cache quota separate unless source proves dependency.

Decoded quota research:

- Strategic handoff goal: keep driving the graphics cleanup loop autonomously until Howl's
  graphics machinery is cleaner and more accountable than Kitty's, without fake progress.
- Verdict: first quota slice is worker-ready and owned by `howl-vt`.
- Kitty source truth: root image storage accounts decoded bytes in `Image.used_storage`
  and `GraphicsManager.used_storage`; quota eviction trims incomplete/no-ref images first,
  then oldest remaining images. Extra animation frames are disk-cache/load-data bounded.
- Ghostty source truth: completed images own decoded `Image.data`; storage quota accounts
  `img.data.len`; placements are eviction-protection state, not byte quota.
- Howl ownership decision: VT protocol storage quota counts decoded image payloads, frame
  decoded payloads, current decoded override payloads, and in-flight decoded upload bytes.
  Render raster cache quota remains render-owned and separate.
- Compatibility decision: legacy/base64 bytes stay under the existing retained-payload
  compatibility bound until old public ABI retirement is explicitly decided.
- Promoted next slice: make `ensureDecodedPayloadStore` evict safe unplaced images before
  failing, preserve physical and virtual placements, count replacement-freed decoded bytes,
  and prove eviction removes frames/current overrides.
- Out of scope: render cache policy, host changes, public ABI changes, full internal
  id/ref/LRU redesign, and access-time implementation.
- VT decoded quota eviction completed in `howl-vt` commit `e302b3d vt: evict decoded
  graphics payloads`.
- Accepted behavior: decoded quota now evicts safe unplaced images before failing,
  preserves physical and virtual placements, counts decoded bytes freed by replacement,
  removes frame/current override bytes with evicted images, and leaves the legacy/base64
  compatibility quota separate.
- Main-agent review found and fixed a root-frame compose pointer-shift bug introduced by
  decoded quota eviction. Compose now reacquires the protected image after eviction before
  mutating it, with a regression proving an earlier unplaced image can be evicted safely.
- Verification passed after review fix: `zig build test --summary all` in `howl-vt` with
  `636/636` tests, `zig build test:regression:build --summary all` in `howl-vt`, root
  `zig build --summary all`, root `git diff --check`, and `howl-vt git diff --check`.
- Next safe work: research Kitty/Ghostty image identity, ref, access-time, and LRU
  semantics now that decoded payload bytes are VT storage truth. Do not promote an
  implementation slice until the boundary between observable protocol behavior and
  internal cleanup is source-backed.

Access-order quota research:

- Verdict: first follow-up slice is worker-ready and owned by `howl-vt`, but it must stay
  narrower than full image identity/ref/LRU redesign.
- Kitty source truth: `Image.atime` and `Image.used_storage` live on each image;
  `apply_storage_quota` first removes trim candidates, then sorts remaining candidates by
  oldest `atime`; `atime` is updated on load, put, and cell-image realization, not every
  render walk.
- Ghostty source truth: storage eviction builds candidates with placement-used status and
  transmit time, prioritizes unused images first, then oldest transmit time, and removes
  image plus placements if selected. Its candidate-list allocation and exact-byte edge are
  not shapes to copy into Howl.
- Howl current truth: after decoded quota eviction, Howl evicts only safe unplaced images
  and scans array order. Array order is not access order once an older image is placed or
  otherwise used and then later becomes unplaced again.
- Boundary decision for the next slice: add VT-owned monotonically increasing image access
  order and use it only to order currently safe unplaced quota victims. Do not evict placed
  images, do not change public ABI, do not replace current image-number semantics, and do
  not implement full internal ids/refs.
- Required work: add image access order state, mark access on root image load/reload and
  successful physical/virtual placement upsert, and choose oldest-accessed unplaced image
  for retained and decoded quota eviction. Existing generated placeholder publication does
  not mutate VT state, so Kitty cell-realization atime parity remains a follow-up unless a
  materialization slice is promoted.
- Required tests: prove decoded quota evicts the least-recently-accessed unplaced image,
  prove retained quota uses the same access order, prove a successful placement access can
  make an older image survive after its placement is deleted, and keep placed-image
  preservation tests green.
- Stop conditions: stop if this requires public ABI changes, placed-image eviction,
  full internal image/ref identity redesign, generated placeholder materialization, or
  renderer/host changes.
- VT access-order quota eviction completed in `howl-vt` commit `43f53c1 vt: order
  graphics eviction by access`.
- Accepted behavior: VT images now carry a monotonic access order, root image load/reload
  assigns access order, successful physical and virtual placement upserts refresh access,
  and retained plus decoded quota eviction pick the least-recently-accessed safe unplaced
  image rather than array order.
- Verification passed: `zig build test --summary all` in `howl-vt` with `638/638` tests,
  `zig build test:regression:build --summary all` in `howl-vt`, root `zig build --summary
  all`, root `git diff --check`, and `howl-vt git diff --check`.
- Remaining proof gaps: generated placeholder publication still does not materialize
  Kitty-style cell refs in VT state, so placeholder realization does not refresh access
  order. Placed-image LRU eviction remains deliberately out of scope until a full
  identity/ref/lifetime slice is promoted.

Placeholder run publication research:

- Verdict: first source-backed slice is worker-ready and owned by `howl-vt`.
- Kitty source truth: `screen_render_line_graphics` scans placeholder cells into row runs
  and calls `grman_put_cell_image`; generated cell-image refs are Kitty's retained
  publication consequence. Howl already converts placeholder runs into generated
  placements, but only through proof/query-time paths.
- Howl current truth: `Terminal.graphicsMeta` hardcodes `placeholder_run_count = 0`,
  `Terminal.graphicsPlaceholderRun` always returns null, while proof APIs and generated
  placement publication already resolve the same placeholder runs. This is an ABI truth
  gap inside VT: the public placeholder-run count/query lies even when generated
  placements are present.
- Promoted next slice: make the existing VT placeholder-run ABI report and query resolved
  placeholder runs through the same VT resolver used by generated placements. Keep render
  and host unchanged, keep proof APIs temporarily as aliases to the same behavior, and do
  not add retained materialization yet.
- Required tests: update placeholder-run tests so `meta.placeholder_run_count` equals the
  proof/resolved count, `graphicsPlaceholderRun` returns the same run as the proof path,
  stale publication rejection still works, clearing placeholder cells drops both generated
  placements and placeholder runs, and missing virtual/image cases still report zero.
- Stop conditions: stop if this needs public ABI layout changes, render/host changes, or
  retained generated-placement storage. Retained materialization and access refresh on
  placeholder realization remain a follow-up slice.
- VT placeholder-run publication completed in `howl-vt` commit `549e3f1 vt: publish
  graphics placeholder runs`.
- Accepted behavior: `Terminal.graphicsMeta().placeholder_run_count` now reports the
  resolved placeholder-run count, `Terminal.graphicsPlaceholderRun` returns those runs,
  and proof APIs alias the same resolver. FFI tests now prove the existing C ABI exposes
  placeholder runs without layout changes.
- Verification passed: `zig build test --summary all` in `howl-vt` with `638/638` tests,
  `zig build test:regression:build --summary all` in `howl-vt`, root `zig build --summary
  all`, root `git diff --check`, and `howl-vt git diff --check`.
- Remaining proof gap: placeholder runs and generated placements are still recomputed from
  screen state during a valid publication instead of retained as materialized VT state.
  The next slice should either materialize publication runs/placements or explicitly prove
  the publication-sequence invariant is sufficient and bounded.

Placeholder materialization access research:

- Verdict: first source-backed follow-up slice is worker-ready and owned by `howl-vt`.
- Kitty source truth: `grman_put_cell_image` updates `img->atime = monotonic()` when
  placeholder cells are materialized into generated cell-image refs. This makes visible
  Unicode placeholder use count as image access for later quota decisions.
- Howl current truth: after `549e3f1`, `graphicsMeta` and `graphicsPlaceholderRun` expose
  resolved placeholder runs, and generated placements are published from those runs, but
  resolving placeholder runs still does not refresh image access order.
- Boundary decision: treat `Terminal.graphicsMeta()` as Howl VT's placeholder
  materialization point for this slice. It already mints/validates a graphics publication
  and computes generated placement counts; marking access there keeps ownership in VT and
  avoids render/host policy.
- Promoted next slice: add a VT method that scans resolved placeholder runs and marks the
  referenced image as accessed when the image still exists. Call it from `graphicsMeta`
  before counts are returned. Keep public ABI, render, host, and retained materialization
  unchanged.
- Required tests: prove a placeholder-resolved image becomes newer for decoded quota
  eviction, prove missing-image placeholder runs do not crash or fabricate access, and keep
  placeholder-run publication tests green.
- Stop conditions: stop if this requires render/host changes, public ABI changes, retained
  generated-placement storage, or changing generated placement geometry.

## Completed Or Stale Graphics Backlog

- Render-side Kitty placeholder interpreter: completed/stale. The named render helpers
  (`drawPlaceholderRunByIndex`, `resolvePlaceholderDrawPlacement`, `placeholderSourceRect`,
  `placeholderGrid`, and placeholder-run sorting helpers) no longer exist.
- Render placeholder image-ref injection: completed/stale. `ensureVirtualPlacementImageRefs`
  and `preparePlaceholderGraphics` no longer exist.
- Temporary cross-layer graphics logging: completed by `howl-vt` commit `b997271`,
  `howl-render` commit `0e571e1`, and `howl-linux-host` commit `e01c169`. No source
  matches remain for `graphics_log`, `HOWL_GRAPHICS_LOG`, or `vt-mutate`.
- Worker backlog items for placeholder assembly, VT generated placements, render normal
  placement replacement, parser hardening, and broad Kitty behavior-group porting are
  stale as active queue items. They are now covered by the completed slices above and the
  live gaps listed in this section.
- Deletion worker gate is closed. The tree is clean, dependency-ordered deletion work has
  run, and future deletion work must be promoted from current source truth rather than
  old placeholder POC notes.
