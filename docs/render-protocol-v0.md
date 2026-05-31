# Howl Render Protocol V0 Contract Draft

Owner: `howl-render` ABI contract draft.

Status: draft only. This document authorizes no product-code changes, no C header
changes, no Zig changes, no host changes, and no deletion of the current full-surface
path.

## Purpose

`howl-render-protocol` V0 is a C ABI consequence protocol for prepared terminal
frames. Render produces bounded damage, uploads, commands, and resource lifetime
events. Hosts realize those consequences with host-owned backend resources and
host-owned presentation policy.

V0 exists to replace the current normal full RGBA prepared-surface boundary only
after ABI, software-realizer, protocol-emission, and host-consumer tests prove the
replacement. Until then, the full RGBA surface remains the fallback and test oracle.

## Non-Goals

- V0 is not a generic scene graph.
- V0 does not expose GL, Metal, Vulkan, shader, command encoder, swapchain, window,
  or platform event-loop objects.
- V0 is not a Zig internal import path.
- V0 does not give the host ownership of shaping, glyph identity, atlas packing,
  damage production, upload bytes, or command production.
- V0 does not claim readiness for product-code implementation.
- V0 does not make the full RGBA surface a normal path.

## Current Full-Surface Facts

- `howl-render/include/howl_render.h` defines `HowlRenderPreparedSurfaceBuffer` with
  `status`, `rgba_pixels`, and `uploads_committed`; there is no host-visible damage,
  upload, command, or retire span in that buffer (`howl_render.h:343-347`).
- `howl-render/include/howl_render.h` exposes source dirty metadata through
  `HowlRenderVtSurfaceSlot.dirty_rows`, `dirty_cols_start`, and `dirty_cols_end`,
  but the prepared buffer ABI still exports only `rgba_pixels` as the render output
  (`howl_render.h:283-288`, `howl_render.h:343-347`).
- `howl-render/src/prepared/buffer.zig:compose()` asserts nonzero dimensions,
  allocates `width * height * 4`, seeds the output, and returns a complete CPU RGBA
  surface (`prepared/buffer.zig:7-31`).
- `howl-render/src/prepared/buffer.zig:seedSurfacePixels()` says partial prepared
  surfaces are realized against a render-owned retained base and that hosts only
  consume one complete prepared surface (`prepared/buffer.zig:78-87`).
- `howl-render/src/prepared/buffer.zig` applies clear, background, decoration,
  sprite, and cursor passes into CPU pixels (`prepared/buffer.zig:33-76`).
- `howl-render/src/prepared/owner.zig:Owner` owns `rgba_pixels` and
  `uploads_required` for the prepared handle (`prepared/owner.zig:35-53`).
- `howl-render/src/prepared/owner.zig:Owner.create()` calls `copySurfaceBuffer()`
  before registering the prepared handle (`prepared/owner.zig:61-70`).
- `howl-render/src/prepared/owner.zig:copySurfaceBuffer()` calls
  `prepared_buffer.compose()` and stores the resulting full RGBA pixels on the
  owner (`prepared/owner.zig:209-221`).
- `howl-render/src/prepared/owner.zig:performSubmit()` validates dimensions and
  upload count, retains the submitted RGBA pixels, and consumes the owner
  (`prepared/owner.zig:159-177`, `prepared/owner.zig:312-321`).
- `howl-linux-host/src/window/term_texture.zig:uploadPreparedBuffer()` documents
  that the host treats the prepared buffer as the complete realized surface and
  performs one full `glTexSubImage2D()` over the terminal surface
  (`term_texture.zig:27-39`).

## Ownership

| Area | Owner | Contract |
| --- | --- | --- |
| Protocol frame tokens | Render | Render creates, validates, retires, and rejects stale tokens. |
| Resource IDs | Render | Render allocates IDs, versions them, orders lifetime events, and forbids reuse before ack. |
| Glyph identity and shaping | Render | Render decides glyph IDs, row-local glyph runs, style splits, and fallback consequences. |
| Atlas packing | Render | Render assigns atlas pages, upload rectangles, and resource references. |
| Damage | Render | Render computes pixel damage and overdamage needed for correctness. |
| Upload bytes | Render | Render owns pointer contents until the frame lifetime ends. |
| Command stream | Render | Render emits bounded clear/fill, glyph-run, and sprite commands. |
| Backend resources | Host | Host maps render resource IDs to host-owned backend objects. |
| Event loop and wake policy | Host | Host schedules when to request and consume frames. |
| Presentation and swap | Host | Host decides present cadence and platform swap behavior. |
| Platform UX | Host | Host owns windows, tabs, input UX, and compositor integration. |
| Backend objects in ABI | Forbidden | No GL, Metal, Vulkan, shader, buffer, texture, command encoder, window, or swapchain handle crosses V0. |
| Generic retained scene graph | Forbidden | V0 has no nodes, parents, transforms, materials, arbitrary layers, or retained host mutation. |
| Full RGBA normal output | Forbidden | Full RGBA is allowed only as fallback/debug oracle until deletion gates pass. |

## Fixed Bounds

These names are part of the V0 draft contract and must become public constants before
ABI skeleton work:

| Bound | Value | Applies To |
| --- | ---: | --- |
| `HOWL_RENDER_PROTOCOL_V0_VERSION` | `0` | Frame protocol version. |
| `HOWL_RENDER_V0_FRAMES_IN_FLIGHT_MAX` | `2` | Prepared protocol frames retained by render. |
| `HOWL_RENDER_V0_SNAPSHOTS_IN_FLIGHT_MAX` | `2` | Snapshot tokens live across host consumption. |
| `HOWL_RENDER_V0_DAMAGE_ITEMS_MAX` | `1024` | `HowlRenderV0DamageSpan.count`. |
| `HOWL_RENDER_V0_UPLOADS_MAX` | `256` | `HowlRenderV0UploadSpan.count`. |
| `HOWL_RENDER_V0_COMMANDS_MAX` | `8192` | `HowlRenderV0CommandSpan.count`. |
| `HOWL_RENDER_V0_GLYPHS_PER_RUN_MAX` | `256` | `HowlRenderV0GlyphRunSpan.count`. |
| `HOWL_RENDER_V0_UPLOAD_BYTES_MAX` | `8388608` | Sum of upload byte spans per frame. |
| `HOWL_RENDER_V0_ATLAS_PAGES_MAX` | `64` | Live atlas page resources per session. |
| `HOWL_RENDER_V0_RESOURCES_MAX` | `4096` | Live protocol resources per session. |
| `HOWL_RENDER_V0_CREATES_MAX` | `256` | `HowlRenderV0CreateSpan.count`. |
| `HOWL_RENDER_V0_RETIRES_MAX` | `256` | `HowlRenderV0RetireSpan.count`. |
| `HOWL_RENDER_V0_HOST_ACKS_MAX` | `256` | Host-to-render ack input count. |

## Object Model

The structs below are conceptual C ABI structs. Field names are mandatory draft names;
layout and exact type sizes must be proved by ABI skeleton tests before shipping.

```c
typedef struct HowlRenderV0Token {
    uint64_t snapshot_seq;
    uint64_t frame_seq;
    uint64_t geometry_epoch;
    uint64_t resource_epoch;
} HowlRenderV0Token;

typedef struct HowlRenderV0Rect {
    int32_t x_px;
    int32_t y_px;
    uint16_t width_px;
    uint16_t height_px;
} HowlRenderV0Rect;

typedef struct HowlRenderV0DamageItem {
    uint8_t kind;
    uint8_t reserved0;
    uint16_t reserved1;
    HowlRenderV0Rect rect;
} HowlRenderV0DamageItem;

typedef struct HowlRenderV0DamageSpan {
    const HowlRenderV0DamageItem *ptr;
    uint32_t count;
    uint32_t count_max;
} HowlRenderV0DamageSpan;

typedef struct HowlRenderV0ResourceId {
    uint64_t value;
    uint32_t generation;
    uint32_t kind;
} HowlRenderV0ResourceId;

typedef struct HowlRenderV0Upload {
    HowlRenderV0ResourceId resource;
    HowlRenderV0Rect rect;
    const uint8_t *bytes_ptr;
    uint32_t bytes_count;
    uint32_t stride_bytes;
    uint32_t format;
    uint32_t upload_seq;
} HowlRenderV0Upload;

typedef struct HowlRenderV0UploadSpan {
    const HowlRenderV0Upload *ptr;
    uint32_t count;
    uint32_t count_max;
    uint32_t bytes_count_total;
    uint32_t bytes_count_max;
} HowlRenderV0UploadSpan;

typedef struct HowlRenderV0Create {
    HowlRenderV0ResourceId resource;
    uint32_t width_px;
    uint32_t height_px;
    uint32_t format;
    uint64_t create_seq;
} HowlRenderV0Create;

typedef struct HowlRenderV0CreateSpan {
    const HowlRenderV0Create *ptr;
    uint32_t count;
    uint32_t count_max;
} HowlRenderV0CreateSpan;

typedef struct HowlRenderV0GlyphRef {
    HowlRenderV0ResourceId atlas_resource;
    HowlRenderV0Rect atlas_rect;
    int32_t x_px;
    int32_t y_px;
    uint32_t glyph_id;
    uint32_t color_rgba;
} HowlRenderV0GlyphRef;

typedef struct HowlRenderV0GlyphRunSpan {
    const HowlRenderV0GlyphRef *ptr;
    uint32_t count;
    uint32_t count_max;
} HowlRenderV0GlyphRunSpan;

typedef struct HowlRenderV0Command {
    uint8_t kind;
    uint8_t reserved0;
    uint16_t reserved1;
    HowlRenderV0Rect rect;
    uint32_t color_rgba;
    HowlRenderV0ResourceId resource;
    HowlRenderV0GlyphRunSpan glyphs;
} HowlRenderV0Command;

typedef struct HowlRenderV0CommandSpan {
    const HowlRenderV0Command *ptr;
    uint32_t count;
    uint32_t count_max;
} HowlRenderV0CommandSpan;

typedef struct HowlRenderV0Retire {
    HowlRenderV0ResourceId resource;
    uint64_t retire_seq;
} HowlRenderV0Retire;

typedef struct HowlRenderV0RetireSpan {
    const HowlRenderV0Retire *ptr;
    uint32_t count;
    uint32_t count_max;
} HowlRenderV0RetireSpan;

typedef struct HowlRenderV0HostAck {
    HowlRenderV0ResourceId resource;
    uint64_t ack_seq;
} HowlRenderV0HostAck;

typedef struct HowlRenderV0HostAckSpan {
    const HowlRenderV0HostAck *ptr;
    uint32_t count;
    uint32_t count_max;
} HowlRenderV0HostAckSpan;

typedef struct HowlRenderV0Frame {
    uint32_t protocol_version;
    uint32_t reserved0;
    HowlRenderV0Token token;
    HowlRenderPixelSize render_px;
    HowlRenderCellSize cell_px;
    HowlRenderGridSize grid;
    HowlRenderV0DamageSpan damage;
    HowlRenderV0CreateSpan creates;
    HowlRenderV0UploadSpan uploads;
    HowlRenderV0CommandSpan commands;
    HowlRenderV0RetireSpan retires;
} HowlRenderV0Frame;
```

`HowlRenderV0HostAckSpan` is not part of `HowlRenderV0Frame`. It is host input to
the eventual submit/ack ABI call. Render must never report host acknowledgement as
render-produced frame data.

## Named Kind Values

These values are the V0 draft constants required before command validation can be
implemented. Value `0` is invalid for every V0 public kind field unless the row
below names it explicitly.

| Constant | Value | Field | Meaning |
| --- | ---: | --- | --- |
| `HOWL_RENDER_V0_DAMAGE_RECT` | `1` | `HowlRenderV0DamageItem.kind` | `rect` is damaged and must be consumed as render-pixel damage. |
| `HOWL_RENDER_V0_DAMAGE_FULL` | `2` | `HowlRenderV0DamageItem.kind` | `rect` must equal `{0, 0, render_px.width, render_px.height}`. |
| `HOWL_RENDER_V0_RESOURCE_GLYPH_ATLAS_ALPHA` | `1` | `HowlRenderV0ResourceId.kind` | Reserved and invalid until the glyph atlas semantics slice. |
| `HOWL_RENDER_V0_RESOURCE_GLYPH_ATLAS_COLOR` | `2` | `HowlRenderV0ResourceId.kind` | Reserved and invalid until the glyph atlas semantics slice. |
| `HOWL_RENDER_V0_RESOURCE_SPRITE_ALPHA` | `3` | `HowlRenderV0ResourceId.kind` | Alpha sprite resource for glyph/special/decoration sprite draws. |
| `HOWL_RENDER_V0_RESOURCE_SPRITE_COLOR` | `4` | `HowlRenderV0ResourceId.kind` | RGBA sprite resource for color sprite draws. |
| `HOWL_RENDER_V0_RESOURCE_FALLBACK_RGBA` | `5` | `HowlRenderV0ResourceId.kind` | Full RGBA oracle/debug fallback resource only. |
| `HOWL_RENDER_V0_UPLOAD_ALPHA8` | `1` | `HowlRenderV0Upload.format` and `HowlRenderV0Create.format` | One alpha byte per pixel. |
| `HOWL_RENDER_V0_UPLOAD_RGBA8` | `2` | `HowlRenderV0Upload.format` and `HowlRenderV0Create.format` | Four bytes per pixel in `r`, `g`, `b`, `a` order. |
| `HOWL_RENDER_V0_COMMAND_CLEAR_RECT` | `1` | `HowlRenderV0Command.kind` | Blend-fill `rect` with `color_rgba` as a clear consequence. |
| `HOWL_RENDER_V0_COMMAND_FILL_RECT` | `2` | `HowlRenderV0Command.kind` | Blend-fill `rect` with `color_rgba` as background/decoration/cursor fill. |
| `HOWL_RENDER_V0_COMMAND_DRAW_GLYPH_RUN` | `3` | `HowlRenderV0Command.kind` | Reserved and invalid until the glyph atlas semantics slice. |
| `HOWL_RENDER_V0_COMMAND_DRAW_SPRITE` | `4` | `HowlRenderV0Command.kind` | Draw one alpha or color sprite resource. |

`color_rgba` packs bytes as `0xRRGGBBAA`. Any unknown command kind, damage kind,
resource kind, or upload format rejects the frame before lifetime transitions. The
glyph atlas resource values are named only to reserve their numbers; V0 validation
must reject creates, uploads, and commands that use them until a later source-backed
glyph atlas slice defines atlas packing, upload bytes, glyph identity, placement,
and alpha/color atlas semantics.

## Resource Lifetime

Render owns every `HowlRenderV0ResourceId` lifetime. Host owns the realized backend
object associated with a live ID.

The only valid ordering is:

1. Create: render emits one create event for a new resource ID with a new `generation`,
   dimensions, format, `create_seq`, and current `resource_epoch`.
2. Update: render may emit uploads for a created live resource while no retire for that resource
   has been emitted.
3. Use: render may emit commands that reference a resource created in the same frame or
   an earlier unretired frame.
4. Retire: render emits one retire event after the final command that may use the resource.
5. Ack: host reports one ack only after all host-side work that could read the resource has
   completed.
6. Reuse: render may reuse the numeric `value` only with a greater `generation` after ack.

Stale ID behavior is fail-closed. Upload before create, command before create,
unknown resources, wrong generations, use after retire, double retire, ack before
retire, double ack, and numeric reuse before ack are invalid input.
Invalid resource references reject the frame or submission; render must not reinterpret them.

Frame and snapshot lifetime rules:

- Render owns frame storage until the host submits or rejects that frame, or until render
  invalidates it with a newer stale-token decision.
- Host may read spans only during the call/turn that receives the frame and before the host
  submits or rejects the same token.
- `HOWL_RENDER_V0_FRAMES_IN_FLIGHT_MAX` and `HOWL_RENDER_V0_SNAPSHOTS_IN_FLIGHT_MAX`
  bound retained frame and snapshot state.
- A stale snapshot token is not an implicit success. The host must discard spans and ask for
  a new frame.

## Span Pointer Lifetime

All V0 spans are borrowed from render-owned frame storage.

- `ptr == NULL` is valid only when `count == 0`.
- `ptr != NULL` is required when `count > 0`.
- `count` must be less than or equal to `count_max`.
- `count_max` must equal the named maximum for that span kind.
- Upload `bytes_ptr` is valid only for the owning frame lifetime.
- The host must not store span pointers or upload byte pointers after submit, reject, or stale-token
  observation.
- Render must not mutate span memory while the frame is live.

## Damage Model

Damage is render-owned pixel damage for the terminal render surface. V0 damage items are rects in
render pixel coordinates, clamped to `render_px`. Full damage is represented by one rect covering
the full render surface. Partial damage uses up to `HOWL_RENDER_V0_DAMAGE_ITEMS_MAX` rects.

Damage is a correctness boundary, not a host policy request. Hosts may over-present, but host tests
must prove they consume V0 damage and do not silently fall back to full prepared-buffer upload as the
normal path. Wide glyph overdamage and row-span-to-pixel clamping must be tested before emission.

## Upload Model

Uploads copy render-owned bytes into host-realized resources identified by render-owned IDs. Uploads
are bounded by both `HOWL_RENDER_V0_UPLOADS_MAX` and `HOWL_RENDER_V0_UPLOAD_BYTES_MAX` per frame.
Upload rectangles are resource-local pixel rectangles. `stride_bytes` is explicit and must be large
enough for the declared rect and format. V0 upload formats are terminal-render formats only; they are
not backend texture formats.

Upload validation rules:

- `HOWL_RENDER_V0_UPLOAD_ALPHA8` is valid only for
  `HOWL_RENDER_V0_RESOURCE_SPRITE_ALPHA`.
- `HOWL_RENDER_V0_UPLOAD_RGBA8` is valid only for
  `HOWL_RENDER_V0_RESOURCE_SPRITE_COLOR` and
  `HOWL_RENDER_V0_RESOURCE_FALLBACK_RGBA`.
- Uploads to `HOWL_RENDER_V0_RESOURCE_GLYPH_ATLAS_ALPHA` and
  `HOWL_RENDER_V0_RESOURCE_GLYPH_ATLAS_COLOR` are invalid until the glyph atlas
  semantics slice.
- For alpha uploads, `stride_bytes >= rect.width_px` and
  `bytes_count >= stride_bytes * rect.height_px`.
- For RGBA uploads, `stride_bytes >= rect.width_px * 4` and
  `bytes_count >= stride_bytes * rect.height_px`.
- Upload rects are resource-local and must fit within the created resource dimensions.
- Uploads to unknown, wrong-generation, retired, or wrong-kind resources reject the frame.

Fallback dirty pixel rect uploads may exist only for software oracle/debug fallback. They must not be
the only normal consequence once the host consumer is accepted.

## Command Model

Commands are an ordered, bounded list of terminal render consequences. The host executes commands in
list order against host-owned realized resources. Commands cannot create resources, change backend
pipeline state, present, swap, allocate host resources except as required to realize render resource
IDs, or mutate retained scene state.

Clear/fill rect commands use `rect` and `color_rgba`. Sprite commands are included only because
the current renderer has sprite raster consequences; they remain resource draws, not image-widget or
scene-graph nodes. Glyph-run commands are named but invalid until the glyph atlas semantics slice.

Command order is semantic. V0 emission must preserve the current `composePreparedSurface()` pass
order from `prepared/buffer.zig:69-76`:

1. `HOWL_RENDER_V0_COMMAND_CLEAR_RECT` commands for `scene.clear_draws`.
2. `HOWL_RENDER_V0_COMMAND_FILL_RECT` commands for `scene.background_draws`.
3. `HOWL_RENDER_V0_COMMAND_FILL_RECT` commands for `scene.decoration_draws`.
4. `HOWL_RENDER_V0_COMMAND_DRAW_SPRITE` commands for `scene.sprite_draws`.
5. `HOWL_RENDER_V0_COMMAND_FILL_RECT` commands for `scene.cursor_draws`.

Within each pass, commands preserve source list order. A later command blends over earlier command
results. Hosts must not sort, merge, cull, or reorder commands unless tests prove byte-equivalence
to this order for the exact command set being transformed.

Clear and fill rect semantics are source-backed by `drawSolidRect()` and `blendPixel()` in
`prepared/buffer.zig:273-315`:

- Rect coordinates are render-pixel coordinates.
- Pixels outside the render surface are skipped.
- A rect with zero width or zero height is invalid for command validation.
- Each covered destination pixel is alpha-blended with the command color.
- For each color channel: `dst = (src * src_a + dst * (255 - src_a)) / 255`.
- For alpha: `dst_a = min(255, src_a + dst_a * (255 - src_a) / 255)`.
- Division is integer truncating division, matching the current Zig implementation.
- Clear rect is not a backend clear operation; it is the same per-pixel blend as fill rect, but it
  records that the source consequence came from `scene.clear_draws`.

Sprite command semantics are source-backed by `lookupSprite()` and `drawSpriteInstance()` in
`prepared/buffer.zig:147-263`:

- `resource.kind` must be `HOWL_RENDER_V0_RESOURCE_SPRITE_ALPHA` or
  `HOWL_RENDER_V0_RESOURCE_SPRITE_COLOR`.
- The referenced sprite resource must be live, created, not retired, and matching generation;
  missing resources reject the frame. The current equivalent is `error.MissingSprite` from
  `lookupSprite()`.
- `rect` is the final visual destination bounds after render applies sprite visual bounds. The
  command rect therefore corresponds to `draw.x_px + bounds.x_px`, `draw.y_px + bounds.y_px`,
  `min(draw.width_px, bounds.width_px)`, and `min(draw.height_px, bounds.height_px)`.
- If the source raster has zero visual bounds, render uses the draw rect as the visual bounds,
  matching `drawSpriteInstance()` fallback bounds.
- Alpha sprite bytes are one alpha byte per source pixel. Source RGB is `color_rgba.r/g/b` and
  source alpha is `(color_rgba.a * alpha_byte) / 255` before the `blendPixel()` formula.
- Color sprite bytes are RGBA bytes. Source RGBA comes from the resource bytes before the
  `blendPixel()` formula. `color_rgba` is ignored for color sprites and must be zero.
- Destination pixels outside the render surface are skipped.
- Sprite source coordinates start at resource-local `(0, 0)` for the visual resource exposed to V0.
  Render must trim or upload visual-bounds bytes so V0 does not need a backend source-offset field.

Glyph-run command semantics are blocked. Current source has row-local shaping contracts
(`contract.zig:154-172`, `contract.zig:332-345`) and sprite-backed glyph consequences
(`scene.zig:695-727`), but V0 does not yet have source-backed atlas packing, upload bytes,
glyph identity, subpixel placement, or alpha/color atlas semantics sufficient to implement and test
direct `HOWL_RENDER_V0_COMMAND_DRAW_GLYPH_RUN`. Until that separate source-backed slice is accepted:

- `HOWL_RENDER_V0_COMMAND_DRAW_GLYPH_RUN` is invalid and must be rejected by the software realizer.
- `HOWL_RENDER_V0_RESOURCE_GLYPH_ATLAS_ALPHA` and
  `HOWL_RENDER_V0_RESOURCE_GLYPH_ATLAS_COLOR` are reserved values, not valid resources.
- `HOWL_RENDER_V0_UPLOAD_ALPHA8` and `HOWL_RENDER_V0_UPLOAD_RGBA8` are valid only for the non-glyph
  resource pairings listed in the upload model above.

V0 can still use sprite commands for current renderer equivalence because current prepared
composition draws `scene.sprite_draws`.

## Invalid Input Behavior

V0 rejects invalid input with a non-success status and no partial lifetime transition.

- Null output frame pointer: reject as missing handle or invalid argument.
- Null span pointer with nonzero count: reject.
- Non-null span pointer with count greater than the named maximum: reject.
- Span `count_max` not equal to the named maximum: reject.
- Upload byte total greater than `HOWL_RENDER_V0_UPLOAD_BYTES_MAX`: reject.
- Zero render, cell, or grid dimensions: reject.
- Rects with zero width or height where a command/upload requires visible work: reject.
- Rects outside render/resource bounds after clamping would be empty: reject.
- Stale snapshot, frame, geometry, or resource token: return stale and expose no live spans.
- Unknown, retired, wrong-generation, or unacked-reused resource IDs: reject.
- Submit before prepare, double submit, ack before retire, retire before last use, or out-of-order
  frame ack: reject.
- Unknown command kind, upload format, resource kind, or damage kind: reject.
- `DRAW_GLYPH_RUN` before glyph atlas/resource/upload semantics are accepted by a later slice:
  reject in the software realizer.
- `DRAW_SPRITE` with `glyphs.count != 0`: reject.
- `DRAW_SPRITE` with a nonzero `color_rgba` for a color sprite resource: reject.
- `CLEAR_RECT` or `FILL_RECT` with a nonempty glyph span or nonzero resource ID: reject.
- `DRAW_GLYPH_RUN` with a nonzero command rect, nonzero command resource, or nonzero command
  `color_rgba`: reject.

## Software Equivalence Oracle

The future software realizer must compare V0 realization against the current
`prepared_buffer.compose()` full RGBA oracle before any V0 emission can replace the normal path.
Selected oracle cases:

- Full redraw with background fill and cursor/decoration fill. Build a full-damage scene with at
  least one background fill and one cursor or decoration fill, emit commands in pass order, and
  compare every RGBA byte with `prepared_buffer.compose()`.
- Partial row retained-base preservation. Seed a nonzero retained base, emit partial clear/background
  commands for only the dirty row span, and prove bytes outside the dirty command rects remain equal
  to the retained base as in `compose preserves retained content outside partial updates`.
- Partial dirty row clear for transparent backgrounds. Use a partial dirty row with transparent cell
  backgrounds and prove the V0 clear command matches the explicit clear produced by
  `scene emits explicit clears for transparent default backgrounds on partial damage`.
- Sprite alpha blending. Only test this without font/backend dependence by constructing an explicit
  alpha sprite resource/upload and sprite command, then comparing against `drawSpriteInstance()`
  semantics through `prepared_buffer.compose()`.
- Sprite color blending. Only test this without font/backend dependence by constructing an explicit
  RGBA sprite resource/upload and sprite command, then comparing against `drawSpriteInstance()`
  semantics through `prepared_buffer.compose()`.

The glyph-run oracle case is blocked. Do not add a glyph-run equivalence test until atlas resource,
upload, placement, and glyph identity semantics are closed by source-backed contract text.

Exact negative software-realizer oracle cases required before implementation:

| Case | Invalid input | Expected result |
| --- | --- | --- |
| Unknown command kind | One command with `kind = 255`. | Reject frame; no resource lifetime transition. |
| Unknown damage kind | One damage item with `kind = 255`. | Reject frame; no resource lifetime transition. |
| Unknown resource kind | One create with `resource.kind = 255`. | Reject frame; no resource lifetime transition. |
| Unknown upload format | One upload with `format = 255`. | Reject frame; no resource lifetime transition. |
| Zero command width | `CLEAR_RECT` with `rect.width_px = 0` and `rect.height_px = 1`. | Reject frame; no pixels written. |
| Zero command height | `FILL_RECT` with `rect.width_px = 1` and `rect.height_px = 0`. | Reject frame; no pixels written. |
| Damage span overflow | `damage.count = HOWL_RENDER_V0_DAMAGE_ITEMS_MAX + 1`. | Reject frame; no span read past max. |
| Upload span overflow | `uploads.count = HOWL_RENDER_V0_UPLOADS_MAX + 1`. | Reject frame; no span read past max. |
| Command span overflow | `commands.count = HOWL_RENDER_V0_COMMANDS_MAX + 1`. | Reject frame; no span read past max. |
| Glyph span overflow | `glyphs.count = HOWL_RENDER_V0_GLYPHS_PER_RUN_MAX + 1`. | Reject frame; no span read past max. |
| Alpha upload to color sprite | Resource kind `SPRITE_COLOR = 4`, upload `format = UPLOAD_ALPHA8 = 1`. | Reject frame; resource remains not updated. |
| RGBA upload to alpha sprite | Resource kind `SPRITE_ALPHA = 3`, upload `format = UPLOAD_RGBA8 = 2`. | Reject frame; resource remains not updated. |
| Upload before create | Upload references `{ value = 77, generation = 1, kind = 3 }` with no create. | Reject frame; resource remains unknown. |
| Missing sprite command resource | `DRAW_SPRITE` references `{ value = 78, generation = 1, kind = 3 }` with no create. | Reject frame; no pixels written. |
| Wrong generation sprite use | Create `{ value = 79, generation = 1, kind = 3 }`, command uses generation `2`. | Reject frame; no pixels written. |
| Retired sprite use | Retire `{ value = 80, generation = 1, kind = 3 }`, then `DRAW_SPRITE` uses it. | Reject frame; no pixels written. |
| Color sprite command color | `DRAW_SPRITE` uses `SPRITE_COLOR = 4` and `color_rgba = 0x01020304`. | Reject frame; no pixels written. |
| Sprite command glyph span | `DRAW_SPRITE` has `glyphs.count = 1`. | Reject frame; no pixels written. |
| Fill command resource | `FILL_RECT` has `resource.value = 1`. | Reject frame; no pixels written. |
| Glyph atlas create | Create with `resource.kind = GLYPH_ATLAS_ALPHA = 1`. | Reject frame; glyph atlas values are reserved. |
| Glyph atlas upload | Upload to `resource.kind = GLYPH_ATLAS_COLOR = 2` with `format = UPLOAD_RGBA8 = 2`. | Reject frame; glyph atlas values are reserved. |
| Blocked glyph run | One command with `kind = DRAW_GLYPH_RUN`, even with `glyphs.count = 0`. | Reject frame; glyph-run semantics are blocked. |

## Test Gates

Before ABI skeleton:

- ABI layout plan for every V0 struct, including size, alignment, field offsets, and reserved fields.
- Constant tests planned for every named bound above.
- Exact ABI negative cases planned: span `ptr = NULL` with `count = 1`,
  `damage.count = HOWL_RENDER_V0_DAMAGE_ITEMS_MAX + 1`, `render_px.width = 0`,
  stale `token.frame_seq`, unknown resource `{ value = 78, generation = 1,
  kind = SPRITE_ALPHA }`, retired resource `{ value = 80, generation = 1,
  kind = SPRITE_ALPHA }`, and ack before retire.

Before software reference realizer:

- ABI skeleton accepted with layout and bound tests passing.
- Software realizer command semantics specified for clear/fill rect and sprite;
  glyph-run rejection specified until the glyph atlas semantics slice.
- Equivalence cases selected against current `prepared_buffer.compose()` for full redraw and partial rows.
- Kind constant tests planned for every numeric V0 command, damage, resource, and upload value.
- Exact negative software-realizer tests planned for the invalid inputs listed in the
  `Software Equivalence Oracle` table: `kind = 255` for command/damage/resource/upload,
  command rect `width_px = 0`, command rect `height_px = 0`, span `count = count_max + 1`,
  `UPLOAD_ALPHA8` to `SPRITE_COLOR`, `UPLOAD_RGBA8` to `SPRITE_ALPHA`, missing resource
  `{ value = 78, generation = 1, kind = SPRITE_ALPHA }`, wrong generation `2` after create
  generation `1`, retired resource use, upload-before-create, glyph atlas create/upload rejection,
  and blocked `DRAW_GLYPH_RUN` rejection.

Before protocol emission:

- Software realizer equivalence tests pass against current full-surface output.
- Damage tests pass for full damage, partial row spans, clamping, and wide-glyph overdamage.
- Resource lifetime tests pass for create/update/use/retire/ack, stale IDs, and reuse after ack.

Before host consumer:

- Protocol emission runs alongside the current full surface.
- Host-facing tests prove uploads and commands are consumed through V0 spans.
- Tests fail if the normal path silently uses the full prepared RGBA buffer instead of V0.

Before full-surface deletion:

- Host consumer is accepted.
- Full-surface path remains available only as explicitly named fallback/test oracle.
- Tests prove normal-path absence of full `glTexSubImage2D()` terminal-surface upload.
- All replacement tests pass for ABI layout, bounds, invalid input, resource lifetime, software
  equivalence, protocol emission, and host consumption.

## Stop Conditions

- Stop if any public list lacks a named fixed maximum.
- Stop if any lifetime lacks a named owner.
- Stop if create/update/use/retire/ack ordering changes or becomes ambiguous.
- Stop if span pointer lifetime is unclear.
- Stop if GL, Metal, Vulkan, shader, command encoder, window, or swapchain objects enter the ABI.
- Stop if command semantics expand into generic scene graph behavior.
- Stop if full RGBA surface remains the only normal host-visible consequence.
- Stop if software-realizer equivalence is skipped.
- Stop if host fallback to full terminal-surface upload is not explicitly tested against.
- Stop if the draft is used to claim product-code readiness before the test gates pass.
