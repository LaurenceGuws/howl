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
| `HOWL_RENDER_V0_RESOURCE_GLYPH_ATLAS_ALPHA` | `1` | `HowlRenderV0ResourceId.kind` | Alpha glyph atlas page resource. |
| `HOWL_RENDER_V0_RESOURCE_GLYPH_ATLAS_COLOR` | `2` | `HowlRenderV0ResourceId.kind` | Reserved for color glyph atlas pages; invalid until a later color-glyph slice. |
| `HOWL_RENDER_V0_RESOURCE_SPRITE_ALPHA` | `3` | `HowlRenderV0ResourceId.kind` | Alpha sprite resource for glyph/special/decoration sprite draws. |
| `HOWL_RENDER_V0_RESOURCE_SPRITE_COLOR` | `4` | `HowlRenderV0ResourceId.kind` | RGBA sprite resource for color sprite draws. |
| `HOWL_RENDER_V0_RESOURCE_FALLBACK_RGBA` | `5` | `HowlRenderV0ResourceId.kind` | Full RGBA oracle/debug fallback resource only. |
| `HOWL_RENDER_V0_UPLOAD_ALPHA8` | `1` | `HowlRenderV0Upload.format` and `HowlRenderV0Create.format` | One alpha byte per pixel. |
| `HOWL_RENDER_V0_UPLOAD_RGBA8` | `2` | `HowlRenderV0Upload.format` and `HowlRenderV0Create.format` | Four bytes per pixel in `r`, `g`, `b`, `a` order. |
| `HOWL_RENDER_V0_COMMAND_CLEAR_RECT` | `1` | `HowlRenderV0Command.kind` | Blend-fill `rect` with `color_rgba` as a clear consequence. |
| `HOWL_RENDER_V0_COMMAND_FILL_RECT` | `2` | `HowlRenderV0Command.kind` | Blend-fill `rect` with `color_rgba` as background/decoration/cursor fill. |
| `HOWL_RENDER_V0_COMMAND_DRAW_GLYPH_RUN` | `3` | `HowlRenderV0Command.kind` | Draw row-local alpha glyph refs from glyph atlas resources. |
| `HOWL_RENDER_V0_COMMAND_DRAW_SPRITE` | `4` | `HowlRenderV0Command.kind` | Draw one alpha or color sprite resource. |

`color_rgba` packs bytes as `0xRRGGBBAA`. Any unknown command kind, damage kind,
resource kind, or upload format rejects the frame before lifetime transitions. The
color glyph atlas value is named only to reserve its number; V0 validation must
reject creates, uploads, and commands that use `GLYPH_ATLAS_COLOR` until a later
source-backed slice defines and tests color glyph production and draw semantics.

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

### Same-Frame Lifetime Order

`HowlRenderV0Create.create_seq`, `HowlRenderV0Upload.upload_seq`,
`HowlRenderV0Retire.retire_seq`, and the command span index share one lifetime order
domain. The domain is the zero-based command boundary index for the owning frame.

Commands do not carry a sequence field. The sequence of a command is its zero-based index in
`HowlRenderV0Frame.commands`. The first command has sequence `0`. The command after the last
command is the boundary `commands.count`.

Creates, uploads, and retires use the same command-boundary domain:

- `create_seq` is the first command boundary where the resource exists in the frame. A create with
  `create_seq = 0` exists before command `0`. A create with `create_seq = N` exists after command
  `N - 1` and before command `N`.
- `upload_seq` is the first command boundary where the uploaded bytes are visible to commands in the
  frame. An upload with `upload_seq = 0` is visible before command `0`. An upload with
  `upload_seq = N` is visible after command `N - 1` and before command `N`.
- `retire_seq` is the first command boundary where the resource is retired in the frame. A retire
  with `retire_seq = N` retires the resource after command `N - 1` and before command `N`. A retire
  with `retire_seq = commands.count` retires the resource after the final command.

All three fields must be less than or equal to `commands.count`. Values greater than
`commands.count` reject the frame because they name a boundary outside the frame. A resource created
and retired in a frame must satisfy `create_seq < retire_seq`. An upload for a resource retired in
the same frame must satisfy `create_seq <= upload_seq` and `upload_seq < retire_seq`.

A command at index `command_index` may reference a resource only when all of these are true:

- The resource was created in an earlier frame and is not retired, or a same-frame create exists with
  `create_seq <= command_index`.
- At least one matching upload required by the command is visible at `upload_seq <= command_index`.
- No same-frame retire exists for that resource, or `command_index < retire_seq`.

The valid same-frame temporary-resource pattern is therefore:

1. Create with `create_seq = 0` or any boundary before the first use.
2. Upload with `upload_seq >= create_seq` and `upload_seq <= first command use`.
3. Use by commands whose indexes are `>= create_seq`, `>= upload_seq`, and `< retire_seq`.
4. Retire with `retire_seq > final command use` and `retire_seq <= commands.count`.

Examples:

- Create, upload, command `0`, retire after command `0`: `create_seq = 0`, `upload_seq = 0`,
  `retire_seq = 1`, and `commands.count >= 1`.
- Create, upload, commands `0` and `1`, retire after final use: `create_seq = 0`,
  `upload_seq = 0`, `retire_seq = 2`, and `commands.count >= 2`.
- Create and upload after command `0`, use by command `1`, retire after command `1`:
  `create_seq = 1`, `upload_seq = 1`, `retire_seq = 2`, and `commands.count >= 2`.

Invalid order cases reject the frame with no partial lifetime transition:

- Upload after retire: `upload_seq >= retire_seq` for the same resource.
- Command use after retire: `command_index >= retire_seq` for the same resource.
- Retire before final command use: any command reference with `command_index >= retire_seq`.
- Upload not yet visible to command use: command reference at `command_index < upload_seq`.
- Create not yet visible to upload or command use: `upload_seq < create_seq` or
  `command_index < create_seq`.
- Duplicate retire for the same `{ value, generation, kind }` in one frame.
- Missing resource: no matching live earlier-frame resource and no matching same-frame create.
- Wrong generation: the numeric `value` exists in a different generation than the referenced
  resource.

This contract uses existing ABI fields only. No hidden backend, host, upload-list, or retire-list
ordering is part of resource lifetime validation.

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
  `HOWL_RENDER_V0_RESOURCE_GLYPH_ATLAS_ALPHA` and
  `HOWL_RENDER_V0_RESOURCE_SPRITE_ALPHA`.
- `HOWL_RENDER_V0_UPLOAD_RGBA8` is valid only for
  `HOWL_RENDER_V0_RESOURCE_SPRITE_COLOR` and
  `HOWL_RENDER_V0_RESOURCE_FALLBACK_RGBA`.
- Uploads to `HOWL_RENDER_V0_RESOURCE_GLYPH_ATLAS_COLOR` are invalid until a later
  color-glyph semantics slice.
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
scene-graph nodes. Glyph-run commands are limited to alpha glyph atlas resources in V0.

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

Glyph-run command semantics are accepted only for alpha glyph atlas pages. Current source has
row-local shaping contracts (`contract.zig:154-172`, `contract.zig:332-345`) and sprite-backed
glyph consequences (`scene.zig:695-727`); therefore direct glyph-run product code remains blocked
until tests prove byte-equivalence against the current sprite-backed full-surface oracle. The V0
contract below exists to make that later implementation source-backed and testable.

### Glyph Atlas Identity

`HowlRenderV0GlyphRef.glyph_id` is a render-owned protocol identity, not a host font glyph index,
Unicode scalar value, codepoint, sprite key, cache slot, or backend object. The identity is unique
within the current live render session for one rasterized glyph image and its atlas placement.

A `glyph_id` is bound to all of these render-owned inputs:

- Resolved font face identity and font generation for the current render session.
- `RunFont` style, presentation, scale, subscale, multicell, and alignment fields.
- The shaper/rasterizer feature generation selected by render for the run.
- Source glyph index produced by shaping, including fallback-face resolution.
- Cell metrics: cell width, cell height, baseline, and box thickness.
- Render options that affect pixels: synthetic bold/thicken, glyph offset, font offset, emoji/text
  presentation, box/special fallback route, and color mode.
- Atlas resource `value`, `generation`, `atlas_rect`, and atlas resource generation.

Render must issue a different `glyph_id` when any bound input changes. Hosts must treat `glyph_id`
as diagnostic identity only; drawing uses `atlas_resource`, `atlas_rect`, `x_px`, `y_px`, and
`color_rgba`. Hosts must not persist `glyph_id` across resource retirement, resource generation
changes, geometry changes, font generation changes, or render session teardown.

### Glyph Atlas Resources

Each glyph atlas resource is one atlas page. V0 uses fixed page dimensions:

- `HOWL_RENDER_V0_RESOURCE_GLYPH_ATLAS_ALPHA`: `width_px = 1024`, `height_px = 1024`,
  `format = HOWL_RENDER_V0_UPLOAD_ALPHA8`.
- `HOWL_RENDER_V0_RESOURCE_GLYPH_ATLAS_COLOR`: invalid for create, upload, and use in V0.

The live alpha atlas page count is bounded by `HOWL_RENDER_V0_ATLAS_PAGES_MAX = 64`. This bound is
the sum of alpha and future color glyph atlas pages; because color pages are invalid in V0, all 64
live pages may be alpha pages. Glyph atlas pages also count against `HOWL_RENDER_V0_RESOURCES_MAX`.

Glyph atlas lifetime uses the global resource lifetime order: create, update, use, retire, ack,
reuse. A create establishes page dimensions, resource kind, format, generation, and `create_seq`.
Uploads may update only live, created, unretired pages of matching generation. Commands may use a
page created earlier in the same frame or any previous unretired frame. Retire must occur after the
last command that can read the page. Host ack must occur only after host-side work that could read
the page has completed. Render may reuse a numeric resource `value` only with a greater generation
after ack.

Render must not mutate a glyph atlas rect while any live frame may still draw from the old bytes. To
replace a glyph image, render either allocates a new rect and emits new glyph refs, or retires the
page after its final use and creates/reuses a later generation after ack. Rect reuse within an
unretired page is invalid.

### Glyph Atlas Packing

Render owns atlas packing. Hosts receive only resource-local rects and upload bytes. V0 uses a
one-pixel transparent border around every allocated glyph rect to prevent sampling bleed. The border
is part of `atlas_rect` and upload bytes; alpha border bytes must be zero. The visible glyph image is
inside that rect. Because `HowlRenderV0GlyphRef` has no source-offset field, render must pre-trim or
pre-expand the uploaded bytes so drawing the whole `atlas_rect` at `x_px/y_px` is correct.

Valid alpha glyph atlas rects must satisfy all rules:

- `atlas_rect.width_px > 0` and `atlas_rect.height_px > 0`.
- `atlas_rect.x_px >= 0` and `atlas_rect.y_px >= 0`.
- `atlas_rect.x_px + atlas_rect.width_px <= 1024`.
- `atlas_rect.y_px + atlas_rect.height_px <= 1024`.
- The rect is allocated exactly once on that page generation.
- The rect does not overlap any earlier live rect on that page generation.

Page-full behavior is bounded. If a glyph plus its border does not fit in any live alpha page, render
may create one new alpha page when the live atlas page count is below
`HOWL_RENDER_V0_ATLAS_PAGES_MAX`. If the page count is already 64, direct glyph-run emission for that
frame must fail closed and the prepared full RGBA oracle/fallback remains the only allowed output for
that frame. Render must not grow atlas page dimensions, allocate an unbounded page list, evict a live
rect in place, or silently draw a missing glyph.

Oversized glyph behavior is explicit. If the glyph image plus one-pixel border on each side exceeds
`1024 x 1024`, render must not create a glyph ref for it. The frame must fail closed to the full RGBA
oracle/fallback path until a later product slice defines an oversized-glyph fallback command. V0 does
not scale, crop, or split oversized glyphs inside `DRAW_GLYPH_RUN`.

Newly allocated rect uploads must be dirty-rect uploads. Each newly allocated rect emits one upload
whose upload rect equals the allocated `atlas_rect`. Whole-page uploads are valid only when the
upload rect is `{ x_px = 0, y_px = 0, width_px = 1024, height_px = 1024 }` and the upload is caused
by page creation, full page rebuild, or software-oracle test setup. Whole-page uploads must still
obey `HOWL_RENDER_V0_UPLOADS_MAX` and `HOWL_RENDER_V0_UPLOAD_BYTES_MAX`.

### Glyph Upload Formats

Alpha glyph atlas uploads use `HOWL_RENDER_V0_UPLOAD_ALPHA8`: one coverage byte per pixel. The source
RGB for drawing comes from `HowlRenderV0GlyphRef.color_rgba`; the source alpha for each pixel is
`(color_rgba.a * alpha_byte) / 255` before the existing `blendPixel()` source-over formula.

RGBA glyph atlas uploads and color glyph draw semantics are blocked in V0. Creates, uploads, or
commands using `HOWL_RENDER_V0_RESOURCE_GLYPH_ATLAS_COLOR` must reject. `HOWL_RENDER_V0_UPLOAD_RGBA8`
to `GLYPH_ATLAS_ALPHA` must reject. `HOWL_RENDER_V0_UPLOAD_ALPHA8` to
`GLYPH_ATLAS_COLOR` must reject. RGB and subpixel-mask glyph uploads are unsupported; there is no V0
`RGB8`, `BGR8`, LCD, or subpixel format. Full RGBA remains oracle/fallback only, not glyph atlas
color semantics.

Upload stride and count rules for alpha glyph pages:

- `stride_bytes >= upload.rect.width_px`.
- `bytes_count >= stride_bytes * upload.rect.height_px`.
- Bytes are row-major from top-left to bottom-right.
- Rows may include padding after the visible rect width; padding bytes are ignored.
- The upload rect must fit inside the created `1024 x 1024` page.
- The upload resource kind and format must match the create resource kind and format.

### Glyph Placement

`HowlRenderV0GlyphRef.x_px` and `y_px` are the final destination pixel top-left for drawing the
entire `atlas_rect` into the render surface. They are not cell coordinates, baseline coordinates,
bearings, advances, or backend transform inputs. Render must precompute them from row/cell origin,
glyph bearings, shaper `x_offset_px`/`y_offset_px`, baseline, combining-mark anchors, ligature
cluster placement, wide-cell span, and any raster visual-bounds trimming.

Combining marks are encoded as normal glyph refs with their own final `x_px/y_px` and atlas rect.
They may overlap earlier glyph refs in the same run. Ligatures are encoded as one or more glyph refs
covering the shaped ligature output; the refs use final pixels, not per-cell subdivision. Wide cells
use final pixels over the full shaped span. Zero-width glyphs must have final placement already
adjusted by render; hosts must not apply Unicode width rules.

Clipping is render-surface clipping. Destination pixels outside `render_px` are skipped, matching the
current software sprite/rect behavior. Source pixels are clipped by the same amount from the atlas
rect. A glyph ref whose destination rectangle has no overlap with `render_px` must not be produced.
If encountered by validation, reject the frame.

### Glyph Run Splitting

`DRAW_GLYPH_RUN` commands are row-local. A run must never cross a terminal row. Render must split
runs at these boundaries:

- Atlas resource changes.
- Font face, font generation, style, presentation, scale, subscale, multicell, or alignment changes.
- Shaper feature generation changes.
- Foreground `color_rgba` changes for alpha glyphs.
- Cursor, selection, hyperlink/search/hint, or other style boundaries that alter visible pixels or
  damage ownership.
- Ligature boundaries when shaping requires separate placement groups.
- Dirty-row or damage-span boundaries when partial damage excludes adjacent cells.
- `HOWL_RENDER_V0_GLYPHS_PER_RUN_MAX = 256` overflow.

If a row contains more than 256 glyph refs for the same split class, render emits multiple adjacent
`DRAW_GLYPH_RUN` commands in source order. Splitting must not change blending order. If the command
count would exceed `HOWL_RENDER_V0_COMMANDS_MAX`, direct glyph-run emission for that frame must fail
closed to the full RGBA oracle/fallback path.

### Glyph Draw Semantics

For alpha glyph refs, `atlas_resource.kind` must be `GLYPH_ATLAS_ALPHA`, `atlas_rect` selects
`ALPHA8` coverage bytes, and `color_rgba` packs source color as `0xRRGGBBAA`. Each covered source
byte blends over the destination using the same integer source-over formula as `blendPixel()`.
Render must omit zero-alpha glyph refs during emission. Validation must reject any zero-alpha alpha
glyph ref.

Color glyph refs are blocked. Any `DRAW_GLYPH_RUN` glyph ref whose `atlas_resource.kind` is
`GLYPH_ATLAS_COLOR` must reject. Any attempt to use `RGBA8` bytes as direct color glyph source must
reject until a later source-backed color-glyph slice defines byte order, premultiplication,
modulation, emoji constraints, and oracle tests.

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
- `DRAW_GLYPH_RUN` with any `GLYPH_ATLAS_COLOR`, RGB, subpixel, unknown, retired,
  wrong-generation, or uncreated atlas resource: reject.
- `DRAW_SPRITE` with `glyphs.count != 0`: reject.
- `DRAW_SPRITE` with a nonzero `color_rgba` for a color sprite resource: reject.
- `CLEAR_RECT` or `FILL_RECT` with a nonempty glyph span or nonzero resource ID: reject.
- `DRAW_GLYPH_RUN` with a nonzero command rect, nonzero command resource, or nonzero command
  `color_rgba`: reject.
- `DRAW_GLYPH_RUN` with `glyphs.count == 0`: reject.
- `DRAW_GLYPH_RUN` with an alpha glyph ref whose `color_rgba.a == 0`: reject.
- `DRAW_GLYPH_RUN` with an atlas rect outside the created page or with zero width/height: reject.

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

Glyph-run oracle cases are required before product code can emit direct glyph runs:

- Alpha glyph atlas draw equivalence. Create one alpha atlas page, upload one glyph rect with a
  one-pixel zero border, draw it through `DRAW_GLYPH_RUN`, and compare every RGBA byte with the
  current sprite-backed `prepared_buffer.compose()` result for the same glyph mask and color.
- Final placement equivalence. Cover nonzero bearing/offset by using glyph refs whose `x_px/y_px`
  differ from the cell origin, then compare against the sprite-backed oracle.
- Combining mark overlap. Draw a base glyph and combining mark in one row-local command and prove
  overlap/blending order matches the sprite-backed oracle.
- Ligature and wide-cell placement. Draw a shaped span wider than one cell and prove final pixel
  placement, clipping, and damage overdraw match the sprite-backed oracle.
- Run splitting equivalence. Emit adjacent runs split by atlas page, color, style/font generation,
  and `HOWL_RENDER_V0_GLYPHS_PER_RUN_MAX`, then prove the split output equals one source-order
  sprite-backed composition.

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
| Same-frame create/upload/use/retire | Create sprite `{ value = 89, generation = 1, kind = 3, create_seq = 0 }`, upload it with `upload_seq = 0`, command `0` uses it, retire it with `retire_seq = 1`. | Accept frame; draw command `0`; mark resource retired only after command `0`. |
| Same-frame late create/upload/use/retire | Command `0` does not use the resource, create sprite `{ value = 90, generation = 1, kind = 3, create_seq = 1 }`, upload it with `upload_seq = 1`, command `1` uses it, retire it with `retire_seq = 2`. | Accept frame; command `1` can read the upload; resource retires after command `1`. |
| Upload after retire order | Create sprite `{ value = 91, generation = 1, kind = 3, create_seq = 0 }`, retire it with `retire_seq = 1`, upload it with `upload_seq = 1`. | Reject frame; resource remains not updated. |
| Upload before create order | Create sprite `{ value = 92, generation = 1, kind = 3, create_seq = 1 }`, upload it with `upload_seq = 0`. | Reject frame; resource remains not updated. |
| Command use before create order | Create sprite `{ value = 93, generation = 1, kind = 3, create_seq = 1 }`, command `0` uses it. | Reject frame; no pixels written. |
| Command use before upload order | Create sprite `{ value = 94, generation = 1, kind = 3, create_seq = 0 }`, upload it with `upload_seq = 1`, command `0` uses it. | Reject frame; no pixels written. |
| Command use after retire order | Create sprite `{ value = 95, generation = 1, kind = 3, create_seq = 0 }`, upload it with `upload_seq = 0`, retire it with `retire_seq = 0`, command `0` uses it. | Reject frame; no pixels written. |
| Retire before final command use | Create sprite `{ value = 96, generation = 1, kind = 3, create_seq = 0 }`, upload it with `upload_seq = 0`, command `0` and command `1` use it, retire it with `retire_seq = 1`. | Reject frame; no pixels written. |
| Duplicate ordered retire | Create sprite `{ value = 97, generation = 1, kind = 3 }`, then two retires for the same `{ value, generation, kind }`. | Reject frame; no lifetime transition. |
| Create sequence outside frame | One command exists, create sprite `{ value = 98, generation = 1, kind = 3, create_seq = 2 }`. | Reject frame; create boundary is outside `commands.count`. |
| Upload sequence outside frame | Create sprite `{ value = 99, generation = 1, kind = 3 }`, one command exists, upload it with `upload_seq = 2`. | Reject frame; upload boundary is outside `commands.count`. |
| Retire sequence outside frame | Create sprite `{ value = 100, generation = 1, kind = 3 }`, one command exists, retire it with `retire_seq = 2`. | Reject frame; retire boundary is outside `commands.count`. |
| Color sprite command color | `DRAW_SPRITE` uses `SPRITE_COLOR = 4` and `color_rgba = 0x01020304`. | Reject frame; no pixels written. |
| Sprite command glyph span | `DRAW_SPRITE` has `glyphs.count = 1`. | Reject frame; no pixels written. |
| Fill command resource | `FILL_RECT` has `resource.value = 1`. | Reject frame; no pixels written. |
| Alpha atlas wrong size | Create `GLYPH_ATLAS_ALPHA = 1` with `width_px = 1023` or `height_px = 1025`. | Reject frame; resource remains unknown. |
| Color atlas create | Create with `resource.kind = GLYPH_ATLAS_COLOR = 2`. | Reject frame; color glyph atlas is blocked. |
| Color atlas upload | Upload to `resource.kind = GLYPH_ATLAS_COLOR = 2` with `format = UPLOAD_RGBA8 = 2`. | Reject frame; resource remains not updated. |
| RGBA upload to alpha atlas | Upload to `GLYPH_ATLAS_ALPHA = 1` with `format = UPLOAD_RGBA8 = 2`. | Reject frame; resource remains not updated. |
| Alpha upload to color atlas | Upload to `GLYPH_ATLAS_COLOR = 2` with `format = UPLOAD_ALPHA8 = 1`. | Reject frame; resource remains not updated. |
| Alpha atlas upload stride too small | `stride_bytes = rect.width_px - 1` for `UPLOAD_ALPHA8`. | Reject frame; no upload bytes read past row. |
| Alpha atlas upload byte count too small | `bytes_count = stride_bytes * rect.height_px - 1`. | Reject frame; no upload bytes read past count. |
| Alpha atlas upload outside page | Upload rect `{ x_px = 1023, y_px = 0, width_px = 2, height_px = 1 }`. | Reject frame; resource remains not updated. |
| Missing glyph atlas resource | `DRAW_GLYPH_RUN` references `{ value = 81, generation = 1, kind = 1 }` with no create. | Reject frame; no pixels written. |
| Wrong generation glyph atlas use | Create `{ value = 82, generation = 1, kind = 1 }`, glyph ref uses generation `2`. | Reject frame; no pixels written. |
| Retired glyph atlas use | Retire `{ value = 83, generation = 1, kind = 1 }`, then glyph ref uses it. | Reject frame; no pixels written. |
| Empty glyph run | `DRAW_GLYPH_RUN` has `glyphs.count = 0`. | Reject frame; no pixels written. |
| Glyph ref zero alpha | Alpha glyph ref has `color_rgba = 0x01020300`. | Reject frame; no pixels written. |
| Glyph rect outside page | Glyph ref rect `{ x_px = 1023, y_px = 0, width_px = 2, height_px = 1 }`. | Reject frame; no pixels written. |
| Color glyph run | Glyph ref uses `atlas_resource.kind = GLYPH_ATLAS_COLOR = 2`. | Reject frame; color glyphs are blocked. |
| Oversized glyph fallback | Glyph allocation request needs `1025 x 1` or `1 x 1025` including border. | Do not emit glyph run; use full RGBA oracle/fallback for that frame. |
| Atlas pages exhausted | 64 live alpha pages exist and a new glyph does not fit. | Do not emit glyph run; use full RGBA oracle/fallback for that frame. |

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
- Software realizer command semantics specified for clear/fill rect, sprite, and alpha glyph runs;
  color glyph rejection specified until a later color-glyph semantics slice.
- Equivalence cases selected against current `prepared_buffer.compose()` for full redraw and partial rows.
- Kind constant tests planned for every numeric V0 command, damage, resource, and upload value.
- Exact negative software-realizer tests planned for the invalid inputs listed in the
  `Software Equivalence Oracle` table: `kind = 255` for command/damage/resource/upload,
  command rect `width_px = 0`, command rect `height_px = 0`, span `count = count_max + 1`,
  `UPLOAD_ALPHA8` to `SPRITE_COLOR`, `UPLOAD_RGBA8` to `SPRITE_ALPHA`, missing resource
  `{ value = 78, generation = 1, kind = SPRITE_ALPHA }`, wrong generation `2` after create
  generation `1`, retired resource use, upload-before-create, alpha atlas wrong size, color atlas
  create/upload rejection, glyph atlas wrong-format rejection, glyph atlas stride/count rejection,
  glyph atlas missing/wrong-generation/retired use rejection, empty glyph-run rejection, zero-alpha
  glyph rejection, and color glyph-run rejection.

Before protocol emission:

- Software realizer equivalence tests pass against current full-surface output.
- Damage tests pass for full damage, partial row spans, clamping, and wide-glyph overdamage.
- Resource lifetime tests pass for create/update/use/retire/ack, stale IDs, and reuse after ack.
- Ordered same-frame lifetime tests pass for `create_seq`, `upload_seq`, command-index use, and
  `retire_seq` in the shared command-boundary domain: valid create/upload/use/retire, valid late
  create/upload/use/retire, upload after retire rejection, upload before create rejection, command
  use before create rejection, command use before upload rejection, command use after retire
  rejection, retire before final command use rejection, duplicate retire rejection, missing resource
  rejection, wrong generation rejection, `create_seq > commands.count` rejection,
  `upload_seq > commands.count` rejection, and `retire_seq > commands.count` rejection.
- Glyph atlas tests pass for alpha page create/update/use/retire/ack/reuse, rect allocation,
  non-overlap, dirty-rect upload bytes, whole-page upload allowance, page-full fallback,
  oversized-glyph fallback, run splitting, and all glyph negative cases above.

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
