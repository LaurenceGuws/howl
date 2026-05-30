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

Command `kind` values are limited to:

- `HOWL_RENDER_V0_COMMAND_CLEAR_RECT`: clear a rect to transparent or terminal clear color.
- `HOWL_RENDER_V0_COMMAND_FILL_RECT`: fill a rect with `color_rgba`.
- `HOWL_RENDER_V0_COMMAND_DRAW_GLYPH_RUN`: draw `glyphs` in order; glyph runs never cross rows.
- `HOWL_RENDER_V0_COMMAND_DRAW_SPRITE`: optional/current-renderer-required only because the
  current renderer has sprite raster consequences in `prepared/buffer.zig:60-62` and
  `prepared/buffer.zig:147-263`. V0 must reject sprite commands if no matching resource exists.

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

Fallback dirty pixel rect uploads may exist only for software oracle/debug fallback. They must not be
the only normal consequence once the host consumer is accepted.

## Command Model

Commands are an ordered, bounded list of terminal render consequences. The host executes commands in
list order against host-owned realized resources. Commands cannot create resources, change backend
pipeline state, present, swap, allocate host resources except as required to realize render resource
IDs, or mutate retained scene state.

Clear/fill rect commands use `rect` and `color_rgba`. Glyph-run commands use `glyphs`; every glyph
references a live atlas resource and a valid atlas rect. Sprite commands are included only because
the current renderer has sprite raster consequences; they remain resource draws, not image-widget or
scene-graph nodes.

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

## Test Gates

Before ABI skeleton:

- ABI layout plan for every V0 struct, including size, alignment, field offsets, and reserved fields.
- Constant tests planned for every named bound above.
- Negative ABI cases planned for null spans, malformed counts, invalid dimensions, stale tokens,
  unknown resources, retired resources, and out-of-order submit/ack.

Before software reference realizer:

- ABI skeleton accepted with layout and bound tests passing.
- Software realizer command semantics specified for clear/fill rect, glyph run, and sprite.
- Equivalence cases selected against current `prepared_buffer.compose()` for full redraw and partial rows.

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
