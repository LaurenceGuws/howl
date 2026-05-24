# Issue 6 Viewport Consumer Sub-Scratchpad

Owner: workspace root.

Parent:

- `issue-6-scratchpad.md`

Blocked item:

- `First Runtime Viewport Consumer`

Research result:

- No honest non-drawing runtime consumer exists above the current metadata-retention seam.
- The first real consumer is render-prepare or drawing-facing work.

Next smaller question:

- What is the first honest render-prepare owner and ABI shape in Howl that should consume retained `graphics_images` plus `graphics_placements` to resolve viewport visibility/clipping and produce draw-ready placement records, following Ghostty helper shape and Kitty `grman_update_layers` behavior, without adding a fake scene/runtime layer?

Research answer:

## Smallest True Owner

- `howl-render/src/frame/surface_text.zig`, `SurfaceText.prepareSurface()`
- `queue.Flow.consumePrepare()` is transport only.
- `graphics_viewport.zig` should remain a leaf helper, not a new owner.

## Exact Seam

- First real consumer seam: `howl-render/src/frame/surface_text.zig` inside `SurfaceText.prepareSurface()`, after `prepare.state` is available and before returning `surface.PreparedSurface`.
- Keep upstream handoff as:
  - `howl-render/src/frame/queue.zig`, `Flow.consumePrepare()` -> `PrepareConsume { request, layout, state }`
- `SurfaceText.prepareSurface()` should call a render-owned helper in `howl-render/src/frame/graphics_viewport.zig`.
- That helper should consume:
  - `prepare.layout`
  - `prepare.state.graphics_images`
  - `prepare.state.graphics_placements`
  - viewport state from `prepare.state`
- `SurfaceText.prepareSurface()` should store prepared graphics records onto `surface.PreparedSurface`.

## Minimum Input Contract

- Keep host/render publication ingress as-is:
  - `graphics.publication_seq`
  - `graphics_images[]`
  - `graphics_placements[]`
  - `rows`
  - `history_count`
  - `scroll_row`
  - `is_alternate_screen`
- Add one missing internal prepare-layout field:
  - `surface.PrepareLayout.grid_px`
- Minimum placement fields used by the helper:
  - `image_id`
  - `placement_id`
  - `z_index`
  - `anchor.kind`
  - `anchor.value`
  - `anchor_col`
  - `source_x`
  - `source_y`
  - `source_width`
  - `source_height`
  - `dest_left_cell_px`
  - `dest_top_cell_px`
  - `dest_right_cell_px`
  - `dest_bottom_cell_px`
- Minimum image fields used by the helper:
  - `image_id`
  - `width`
  - `height`
  - `format`
- Image lookup should be by `image_id` against retained `graphics_images`.

## Output Shape

- Add a render-owned field on `howl-render/src/frame/surface.zig`, `PreparedSurface.graphics`.
- Minimum internal records:
  - `PreparedGraphicsImageRef { image_id, width, height, format }`
  - `PreparedGraphicsPlacement { image_index, placement_ordinal, z_index, layer, dest_x_px, dest_y_px, dest_width_px, dest_height_px, src_x_px, src_y_px, src_width_px, src_height_px }`
  - `PreparedGraphics { publication_seq, images, placements, below_bg_count, below_text_count, above_text_count }`
- Behavior:
  - emit only visible placements
  - resolve viewport row from retained anchor truth plus `history_count` / `scroll_row`
  - resolve destination rect in top-origin grid space
  - clip against `layout.grid_px`
  - adjust source rect to match clipping
  - classify Kitty z bands exactly:
    - `z_index < INT32_MIN/2` => `below_bg`
    - `INT32_MIN/2 <= z_index < 0` => `below_text`
    - `z_index >= 0` => `above_text`
  - sort by:
    - `z_index`
    - `image_id`
    - `placement_ordinal`
- `placement_ordinal` should use retained placement slice index as the smallest current tie-breaker.

## Must Remain Render-Owned

- viewport mapping from retained row anchors to current pixel coordinates
- clipping against current grid viewport
- source-rect adjustment caused by clipping
- z-band classification and final draw order
- prepared placement buffers, image lookup tables, later decoded-image/cache handles
- none of this should leak back into `howl-vt`

## Smallest Proof Plan

- Pure render tests in `howl-render/src/frame/graphics_viewport.zig` for:
  - fully visible placement
  - clipped-above placement
  - clipped-left/right placement
  - fully off-screen rejection
  - z-band classification
  - source-rect adjustment after clipping
- Integration test at `howl-render/src/frame/surface_text.zig` or `queue.zig` level:
  - publish one image + placement through `Flow.commitPublishSlot()`
  - call `Flow.consumePrepare()`
  - run `SurfaceText.prepareSurface()`
  - assert `prepared.graphics.publication_seq`, counts, sort order, and resolved dest/src fields

## Risks / Open Points

- `surface.PrepareLayout` currently drops `grid_px`; clipping is not honest without adding it.
- There is no exported VT internal placement identity; retained placement slice index is the smallest current ordering tie-breaker.
- Current render side still carries protocol-payload metadata only, not decoded image handles; later draw-contract work still needs the decode/cache seam.
- If render later gains non-zero grid origin, this contract will need explicit grid origin fields.

Required answer shape:

1. Name the smallest true owner.
2. Name the exact file/function seam where retained graphics first become render-prepare truth.
3. State the minimum ABI/input contract that seam needs.
4. State what must remain render-owned and not leak back into VT.
5. State the smallest proof plan for landing it.

Known blocker:

- `howl-vt` exports truthful placement edges/grid extent.
- `howl-linux-host` copies and forwards them.
- `howl-render` retains/coalesces/replaces them.
- No live runtime path consumes them.
- A local viewport helper without a runtime consumer is fake progress.
- The next honest consumer is therefore render-prepare or drawing-facing.

Required references:

- Ghostty:
  - `utils/dev_references/terminals/ghostty/src/terminal/c/kitty_graphics.zig`
  - `utils/dev_references/terminals/ghostty/include/ghostty/vt/kitty_graphics.h`
- Kitty:
  - `utils/official_docs/kitty/graphics-protocol.md`
  - `utils/dev_references/terminals/kitty/kitty/graphics.c`
  - `utils/dev_references/terminals/kitty/kitty/graphics.h`
- TigerBeetle:
  - `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`

Required local code:

- `howl-vt/src/kitty/graphics.zig`
- `howl-vt/src/ffi.zig`
- `howl-vt/include/howl_vt.h`
- `howl-linux-host/src/terminal/vt/surface.zig`
- `howl-render/src/ffi_types.zig`
- `howl-render/src/frame/queue.zig`
- `howl-render/src/frame/graphics_viewport.zig`
- `howl-render/src/frame/surface_text.zig`
- `howl-render/src/frame/surface.zig`

Current accepted state:

- VT resolves and exports destination extent truth.
- Host acquisition and render retention preserve it.
- No live runtime consumer above that seam currently uses it for viewport inclusion/clipping.

Deliverable:

- A short research answer that defines the first render-prepare contract seam tightly enough to create a code-ready sub-scratchpad item.

Status:

- Research complete.
- This sub-scratchpad is now code-ready.
