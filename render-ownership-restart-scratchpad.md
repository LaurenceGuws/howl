# Render Ownership Restart Scratchpad

Owner: workspace root.

Status: active restart; supersedes the accepted direction in
`render-host-boundary-scratchpad.md` and `cleanupscratchpad.md` for render.

Purpose:

- Restart the render sprint from source facts after the prior cleanup preserved
  the wrong owner shape under `howl-render/src/surface/`.
- Delete `howl-render/src/surface/flow.zig`; it is an umbrella owner that mixes
  VT input/source state, render preparation requests, submitted-output state,
  and submit feedback.
- Separate input ownership from output ownership. `surface` is the thing rendered
  by render and the thing exposed by VT; it is not a bucket for every state machine.

## Rejected Prior Scratchpads

The following scratchpads did not produce an acceptable render shape:

- `render-host-boundary-scratchpad.md`
- `host-reshape-scratchpad.md`
- `cleanupscratchpad.md`

Do not continue their render naming by inertia. Use this scratchpad for the new
render sprint.

## Current Source Facts

### `howl-render/src/surface/flow.zig`

This file is not one owner. It currently contains at least four owners:

- VT/source ingestion and retained source slot state:
  - `PublicationSource`
  - `PublicationSlot`
  - `ReservedSourceMeta`
  - `PublicationState`
  - retained slot allocation and reservation
  - dirty row validation/canonicalization
  - source equality and source damage classification
- Prepare-request lifecycle:
  - `PrepareConsume`
  - active/pending source promotion
  - `takePrepareRequest()`
  - `consumePrepare()`
  - `retryTakenPrepare()`
  - blink refresh forcing full prepare
- Submitted/render-output lifecycle:
  - `TerminalSurface`
  - `submitted_frame`
  - submit mailbox
  - submitted-token validation
  - stale prepared-frame handling
- Geometry/state aggregation:
  - `Flow.render_px`
  - `Flow.grid_px`
  - `Flow.cell_px`
  - `Flow.geometry_epoch`
  - `Flow.source_dirty_epoch`
  - `Flow.cursor_blink_visible`

This is exactly the fake-simple bucket TigerBeetle rules reject.

### `howl-render/src/surface/types.zig`

This file also mixes unrelated concepts:

- geometry primitives: `CellSize`, `PixelSize`, `GridSize`, `SurfaceLayout`
- VT/source-like cell model: `Color`, `CellFlags`, `CellAttrs`, `Cell`,
  `GridModel`, `DamageInfo`, `ViewportInfo`, `CursorInfo`, `FrameData`
- prepared render output: `PreparedSurface`
- host execution feedback: `RenderSurfaceFeedback`

The file name `types.zig` is tolerated only because it was the previous explicit
move target. It is not an owner and must not survive the restart.

### `howl-render/src/surface/text.zig`

This file owns two things today:

- `SurfaceText`: text rendering/session implementation.
- `SurfaceTextOwner`: public render object owner used by FFI.

`SurfaceTextOwner` currently owns:

- `session: SurfaceText`
- `flow: flow.Flow`
- prepared handle caches
- font config memory
- retained submitted pixels for partial output composition

That means `SurfaceTextOwner` should compose explicit input/output/geometry
owners directly, not a vague `flow` owner.

### `howl-render/src/surface/input.zig`

This file translates VT/source cells into text scene input. Its dependency on
`flow.PublicationSource` is wrong. It should depend on a source-owned input type,
not the output/submit lifecycle owner.

### Public C FFI

`howl-render/include/howl_render.h` currently names one opaque object:

- `HowlRenderSurfaceTextHandle`

The C ABI includes both input and output actions on that handle:

- input/source side:
  - `reserve_publish_slot`
  - `commit_publish_slot`
  - `reject_publish_slot`
  - `cancel_publish_slot`
  - `take_prepare_request`
  - `pending_state`
- output/prepared side:
  - `prepare_handle`
  - `publish_prepared`
  - `publish_prepared_handle`
  - `take_submit_decision`
  - `take_submit_handle`
  - `accept_submitted`
  - `submit`
  - `submit_handle`
  - prepared-surface describe/buffer/diagnostics/release

This restart should not rename the C ABI first. The implementation must separate
owners behind the current ABI before deciding whether a later ABI break is worth
it.

## Reference Pressure

- Alacritty separates terminal renderable content from display/rendering:
  - `alacritty_terminal::term::RenderableContent` is terminal/VT-derived input.
  - `alacritty/src/display/content.rs` adapts terminal content to renderable
    cells/cursor.
  - Display/window own presentation and backend surface.
- Howl render is an embeddable C ABI state engine, not an Alacritty display.
  Therefore it needs explicit internal seams:
  - VT/source input owner.
  - render preparation owner.
  - prepared output owner.
  - submitted/retained output owner.
- TigerBeetle pressure forbids one `flow`/`types` file owning all of those.

## Target Owner Shape

Do not use `flow`, `pipeline`, `queue`, `manager`, `controller`, `runtime`, or
generic ownerless `types` for the restart.

Proposed render tree after this sprint:

```text
howl-render/src/
  ffi.zig
  libhowl_render.zig

  source/
    vt.zig                 # VT/source cells, colors, cursor, selection, dirty rows
    slot.zig               # reserve/commit/cancel source slot storage
    damage.zig             # source dirty classification and source equality
    prepare_request.zig    # pending/active source to render request lifecycle

  render/
    geometry.zig           # pixel/cell/grid layout and geometry epoch
    tokens.zig             # snapshot/prepared/submitted tokens only
    text.zig               # text renderer session; consumes source.PrepareInput
    input.zig              # source -> text scene input translation

  prepared/
    surface.zig            # prepared render output data
    owner.zig              # prepared handle lifecycle
    buffer.zig             # retained pixel composition
    feedback.zig           # host execution feedback -> render metrics

  session/
    text.zig               # public object owner behind HowlRenderSurfaceTextHandle
    submitted.zig          # submitted/retained token and submit mailbox
```

This is a target, not permission for one huge rewrite. Promote one owner cut at a
time.

## Ownership Rules

- `source/*` owns VT-derived input snapshots and dirty/source metadata only.
- `source/*` must not own prepared render output, host execution feedback, or
  submitted-surface tokens.
- `prepared/*` owns prepared render output and prepared-handle lifecycle only.
- `prepared/*` must not own VT source reservation or host cadence.
- `session/*` composes the current public render object behind the C handle.
- `session/submitted.zig` owns only submitted/retained render-output token state
  and submit mailbox decisions.
- `render/*` owns text rendering and render geometry, not VT source slot storage.
- `surface` is a product term at the ABI boundary, not an umbrella source folder.

## First Research Questions

Before code, answer these with exact symbols and files:

1. What is the minimal first code slice that deletes `surface/flow.zig` without
   changing the C ABI?
2. Which symbols move to `source/vt.zig`, `source/slot.zig`,
   `source/damage.zig`, `source/prepare_request.zig`, and
   `session/submitted.zig`?
3. What should `SurfaceTextOwner` own after the first slice instead of
   `flow.Flow`?
4. Which tests move with each owner, and which new tests prove input/output owner
   separation?
5. Which grep gates prove that `flow` and generic `types` no longer hide the
   bad shape?

## First Slice Candidate

Likely first implementation slice, pending research validation:

- Delete `surface/flow.zig` by splitting only the existing state machines, with
  no ABI changes and no behavior changes.
- Do not yet rename all public C `SurfaceText` vocabulary.
- Replace `SurfaceTextOwner.flow` with explicit fields, likely:
  - `source_slot`
  - `prepare_requests`
  - `submitted`
  - `geometry`
  - `cursor_blink_visible` or source-owned blink phase if research proves it.

This candidate is not worker-ready until exact symbol movement is recorded.

## Hard Gates For Restart

- No `howl-render/src/surface/flow.zig`.
- No `Flow` owner.
- No `surface/types.zig` as a generic mixed owner by the end of this restart.
- No new umbrella `screen`, `surface`, `pipeline`, `queue`, `manager`,
  `controller`, or `runtime` bucket.
- Input/source and output/prepared/submitted owners must be separate files and
  separate fields in the session owner.
- Render still does not own backend presentation or host cadence.
- Host continues through the shipped C ABI.
