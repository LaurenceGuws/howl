# Issue 6 Scratchpad

Owner: workspace root.

Source:

- `feature-gap-scratchpad.md` item 6

Issue:

- Kitty graphics truth exists in VT and is now exported, retained, and prepared above VT, but final drawing is still blocked by the remaining draw-facing contract work.

## Comparison

### Kitty Has

- VT is the source of truth for graphics lifecycle.
- Main and alternate screens have separate graphics owners.
- Physical placements are retained terminal truth, not a render cache.
- Scrolling and clipping mutate retained placement truth.
- `a=T` is real transmit-and-display.
- Omitted `c` and/or `r` dimensions are resolved from source size, aspect ratio, cell size, and offsets.
- Visible ordering uses Kitty z-band semantics.

### Ghostty Has

- A strong VT-owned retained row/location model.
- A public C seam for graphics inspection.
- Integration helpers compute destination/grid/viewport facts from VT-owned truth.
- Useful integration shape reference, not a literal copy target.

### Howl Has Now

- `howl-vt` owns graphics truth.
- Main and alternate screens own separate graphics state.
- Reset, replacement, upward retention, below-screen anchors, and supported clipping are repaired for the supported subset.
- Public ABI exists for graphics meta, indexed image query, indexed placement query, payload copy, and cell pixel size.
- Host pairs surface/meta acquisition and retries on stale item publication.
- Render ingests copied graphics metadata and proves publication-scoped replacement.
- Render prepare now consumes retained graphics images/placements into render-owned prepared graphics records with viewport visibility, clipping, source-rect adjustment, and Kitty z-band classification.
- Render compose now consumes prepared graphics bands at the correct draw-facing insertion points.
- Raw `f=24` / `f=32` and `f=100` payload handoff, decode/cache, and draw consumption are landed.

### Howl Does Not Yet Have

- A truthful drawing contract above VT.
- Virtual/placeholder placements.
- Non-`t=d` media.
- Compression.
- Animation/frame publication.

## Goal

- Kitty-level lifecycle honesty.
- Ghostty-level integration discipline.
- Alacritty-level bounded/simple control flow.
- TigerBeetle-level skepticism and proof.

VT remains the source of truth.
Render translates VT truth.
Hosts use copied C-ABI truth only.

## Supported Subset

- direct payload medium `t=d`
- physical cursor-anchored placements only
- actions `t`, `T`, `p`, `d`
- image ids and image numbers
- source crop truth
- cell-pixel offsets
- row-anchor truth including off-screen retained states

Out of scope:

- placeholders / `U=1`
- relative placements `P/Q/H/V`
- decoded/render-ready image publication
- non-`d` media
- compression
- animation control/composition
- render-derived geometry

## Accepted Coherence Rule

- `copy_surface()` publishes visible truth under `snapshot_seq`.
- `query_graphics_meta()` publishes graphics truth under `publication_seq`.
- Graphics item queries must use that exact `publication_seq`.
- If any item query rejects it, restart the whole acquisition attempt.
- Graphics publication is still conservative, not graphics-local.

## Accepted Above-VT State

- Host acquisition boundary is honest and proved.
- Copied item metadata ingestion is landed.
- Render replacement/invalidation from publication truth is landed.
- Render-prepare graphics viewport/clipping consumption is landed.
- Draw order is not the immediate blocker anymore.

## Current Blocker

- VT now owns and exports resolved destination truth.
- Host acquisition preserves that truth.
- Render metadata retention preserves that truth.
- Render prepare now consumes that truth into render-owned prepared graphics records.
- Render compose now consumes prepared graphics band ordering without inventing a fake scene/runtime layer.
- Render-owned raw and PNG payload handoff, decode/cache, and draw consumption are landed for the supported subset.
- Relative placement truth is landed.
- The remaining blocker is no longer metadata, prepare ownership, draw-band insertion, supported-subset decode/cache ownership, or relative placement truth.
- The remaining unsupported Issue 6 gaps will now be handled in fixed sequence.

## Next Checkpoint

`Virtual/Placeholder Placements`

### Exact Missing Answer

- Promoted first remaining unsupported gap: `Virtual/Placeholder Placements`

### Remaining Queue

1. `Virtual/Placeholder Placements`
2. `Non-\`t=d\` Media`
3. `Compression`
4. `Animation/Frame Publication`

Why this order:

- placeholders are the next largest behavior gap closest to current placement/render truth
- non-`t=d` media and compression extend payload transport/decode
- animation/frame publication comes last because it needs the strongest lifecycle/publication contract

### Question To Answer

- How should VT retain and export virtual/placeholder placement truth?
- What exact render/input contract is required so placeholders become part of the product behavior above VT?
- What is the smallest honest split between VT truth, render prepare truth, and draw/runtime behavior for placeholders?

### VT Pressure

- Use `issue-6-vt-readiness-scratchpad.md` to challenge every remaining graphics blocker from the VT side first before accepting an up-stack explanation.

### Accepted Relative Placement State

- Relative placements are code-landed now.
- VT retains parent image/placement references and parent offsets.
- VT resolves parent-relative anchors into exported placement truth.
- Cycle rejection, depth bound, and parent-tied placement lifetime are landed.
- Named descendant images are not auto-deleted merely because descendant placements were removed.

### Sequential Rule

- Remaining unsupported Issue 6 graphics gaps are now handled sequentially unless a later item is proven to be a hard dependency of the current item.

### Current Proven State

- `howl-vt` resolves implicit destination extent truth.
- `howl-vt` exports explicit resolved destination pixel edges and resolved grid extent.
- `howl-vt` clipping now follows resolved destination truth.
- `howl-linux-host` paired acquisition and stale-retry proofs preserve resolved destination truth.
- `howl-render` ABI mirrors and retained publication proofs preserve resolved destination truth.
- `howl-render` prepare owns viewport mapping, clipping, source-rect adjustment, z-band classification, and stable ordering on prepared graphics records.
- Draw-facing owner and insertion points are now identified.
- Draw-facing composition order is now landed.
- Decode/cache owner and invalidation rules are now identified.
- Raw `f=24` / `f=32` and `f=100` payload decode, cache reuse/replacement, and draw consumption are landed.

### Research Inputs

- Ghostty runtime/view seam:
  - `utils/dev_references/terminals/ghostty/src/terminal/c/kitty_graphics.zig`
  - `utils/dev_references/terminals/ghostty/include/ghostty/vt/kitty_graphics.h`
- Kitty behavior truth:
  - `utils/official_docs/kitty/graphics-protocol.md`
  - `utils/dev_references/terminals/kitty/kitty/graphics.c`
  - `utils/dev_references/terminals/kitty/kitty/graphics.h`
- Local code chain:
  - `howl-vt/src/kitty/graphics.zig`
  - `howl-vt/src/ffi.zig`
  - `howl-vt/include/howl_vt.h`
  - `howl-linux-host/src/terminal/vt/surface.zig`
  - `howl-render/src/ffi_types.zig`
  - `howl-render/src/frame/queue.zig`
  - `howl-render/src/frame/graphics_viewport.zig`
  - `howl-render/src/frame/surface_text.zig`
  - `howl-render/src/frame/surface.zig`
  - `howl-render/src/frame/surface_buffer.zig`
  - immediate draw-facing consumers only

### Draw Contract Result

- Smallest true owner:
  - `howl-render/src/frame/surface_buffer.zig`, `compose()`
- Exact seam:
  - consume `prepared.graphics` directly in `compose()`
  - insert bands at existing composition points:
    - after clear draws: `below_bg`
    - after background draws: `below_text`
    - after text/decorations/sprites: `above_text`
    - keep cursor last as render-owned terminal UX policy
- Minimum draw-facing input contract:
  - `surface.PreparedGraphics.publication_seq`
  - `images`
  - `placements`
  - `below_bg_count`
  - `below_text_count`
  - `above_text_count`
  - `PreparedGraphicsImageRef { image_id, width, height, format }`
  - `PreparedGraphicsPlacement { image_index, layer, dest_x_px, dest_y_px, dest_width_px, dest_height_px, src_x_px, src_y_px, src_width_px, src_height_px }`
- Draw submission does not need VT anchor or cell-edge fields anymore; prepare already consumed them.

### Landed Decode/Cache Seam

- Host copies payload bytes through `howl_vt_terminal_copy_graphics_payload()`.
- Host commits one flat `graphics_payload_bytes` span in `graphics_images` order.
- Render retains payload identity and lifetime on `SurfaceText`.
- Render base64-decodes and normalizes raw and PNG payloads into render-private decoded raster records.
- Draw path now looks up draw-ready raster state by render-private cache identity.

### Decode/Cache Result

- Smallest true owner:
  - `howl-render/src/frame/surface_text.zig`, `SurfaceText`
- Exact seam:
  - ingress at `howl-render/src/frame/surface_text_ffi.zig:commitPublishSlot()` into `queue.PublicationSource`
  - decode/cache in `SurfaceText.prepareSurface()` after prepared placement truth exists and before `ownPreparedSurface()`
- Minimum host-to-render payload contract:
  - `graphics_payload_bytes: FfiByteSpan` on render publish-slot commit
  - `sum(graphics_images[i].payload_len) == graphics_payload_bytes.len`
  - payload byte order matches `graphics_images` order exactly
- Cache identity and invalidation rule:
  - content identity:
    - `DecodedGraphicsKey { format, width, height, payload_len, payload_hash64 }`
  - publication-local `image_id -> DecodedGraphicsKey` map
  - changed key for same `image_id` means replacement
  - unreferenced decoded rasters are dropped on sweep
- Draw-ready output shape:
  - render-private cache record:
    - `DecodedGraphicsRaster { key, width, height, stride, pixels_rgba }`
  - prepared-facing ref:
    - `raster_index: u32` on `surface.PreparedGraphicsImageRef`
  - landed normalized inputs:
    - `f=24` => RGB -> RGBA
    - `f=32` => RGBA
    - `f=100` => PNG -> RGBA

### Must Remain Render-Owned

- draw insertion order in `compose()`
- decode policy
- decoded raster lifetime
- cache invalidation
- upload lifetime
- sampling/blending policy
- cursor-over-graphics ordering policy
- base64 decode of VT-copied payload bytes
- PNG/raw image normalization
- decoded raster lifetime
- cache replacement/eviction

### Stop Condition

- Stop only if the next promoted unsupported gap is not yet clear from the current owner/boundary rules.
- Otherwise, promote the next real unsupported Issue 6 graphics gap and repeat the loop.
