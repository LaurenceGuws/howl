# Graphics Machinery Scratchpad

Owner: workspace root.

Purpose: sprint scope `graphics` research output and worker-driving backlog.

Reviewer status: accepted after researcher correction. The first research pass was rejected because it incorrectly claimed Kitty protocol placeholder diacritics are 1-based. Kitty docs and source show the protocol value is 0-based; Kitty uses `0` as an internal missing sentinel while scanning and subtracts before cell-image creation.

Current gate: seed coding workers only after `current.txt` is promoted and the git tree is clean.

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
