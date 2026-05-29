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

The file name `types.zig` is banned. It is not an owner and must not survive the
restart.

Project-wide banned files found on 2026-05-29:

- `howl-render/src/surface/types.zig`
- `howl-vt/src/kitty/types.zig`
- `howl-vt/src/input/types.zig`

Delete them slice by slice. Do not replace them with another ownerless bucket.

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

## Accepted Research: First Implementation Slice

Status: worker-ready.

Goal:

- Delete `howl-render/src/surface/flow.zig` without changing
  `howl-render/include/howl_render.h`.
- Replace `SurfaceTextOwner.flow` with explicit owners:
  - source slot storage
  - source prepare-request lifecycle
  - submitted/prepared-output mailbox
  - render geometry epoch/layout

### Files To Add

- `howl-render/src/source/vt.zig`
- `howl-render/src/source/damage.zig`
- `howl-render/src/source/slot.zig`
- `howl-render/src/source/prepare_request.zig`
- `howl-render/src/render/geometry.zig`
- `howl-render/src/session/submitted.zig`

### File To Delete

- `howl-render/src/surface/flow.zig`

### First-Slice File Kept Temporarily And Now Rejected

- `howl-render/src/surface/types.zig`

This temporary exception is closed. The next render slice deletes this file.

Reason: it is still a bad mixed owner, but deleting `flow.zig` is already a large
owner split. The next slice must delete or decompose `surface/types.zig`.

### Symbol Movement

Move from `surface/flow.zig` to `source/vt.zig`:

- `VtSnapshot`
- `PublicationSource`
- `ReservedSourceMeta`
- `VtPublishResult`
- `validatePublicationSourceBoundary`
- test helpers `testSourceFromSnapshot` and `ownedTestSource` only if needed by
  moved tests

Move or fold `surface/publication_source.zig` into `source/vt.zig` if practical:

- `SourceRgb`
- `SourceColor`
- `SourceColors`
- `SourceCellFlags`
- `SourceCellAttrs`
- `SourceCell`
- `SourceSelectionPoint`
- `SourceSelection`

If the worker keeps `surface/publication_source.zig` temporarily, it must remain
a narrow VT source shape and must not become a compatibility shim for `flow`.

Move from `surface/flow.zig` to `source/damage.zig`:

- `validateDirtySource`
- `canonicalizeDirtyMetadata`
- `cursorPresentationChanged`
- `colorPresentationChanged`
- `setSourceCursorBlinkVisible`
- `samePublicationSource`
- `classifyDirty`
- `sameSnapshotToken` if shared by source/prepare/submitted tests
- `slotCellCountChecked` only if boundary validation needs it

Move from `surface/flow.zig` to `source/slot.zig`:

- `PublicationSlot`
- `PublicationState.RetainedSlot` renamed to `RetainedSlot`
- `slotCellCount`
- `RetainedSlot.deinit`
- `RetainedSlot.ensureCapacity`
- `RetainedSlot.canHold`
- `RetainedSlot.publicationSlot`
- `syncReservedSlotCapacity`
- `reserveSourceSlot`
- `cancelReservedSource`
- `commitReservedSource`
- `retainedSource`
- `retainedSlotInUse`
- `refreshRetainedSlotViews`
- `refreshRetainedSource`

Exported owner name: `SourceSlot`, not `PublicationState`.

Move from `surface/flow.zig` to `source/prepare_request.zig`:

- `PrepareConsume`
- `Publication`
- `ActivePrepare`
- pending/active/blink lifecycle fields formerly in `PublicationState`
- `acceptSource`
- `takePrepareRequest`
- `consumePrepare`
- `latestToken`
- `requestFullPrepare`
- `retryTakenPrepare`
- `setCursorBlinkVisible`
- `requestBlinkRefresh`
- `retireAtOrBefore`
- `retirePendingAtOrBefore`
- `sourcePending`
- `preparePending`
- `replacePending`
- `dropActive`
- `activatePending`
- `classify`
- `priorSource`

Exported owner name: `PrepareRequests`.

Move from `surface/flow.zig` to `session/submitted.zig`:

- `ThreadMutex`
- `lockMutex`
- `SubmitDecision`
- `TerminalSurface` renamed to `Submitted`
- `SubmitMailbox`
- `submitted_frame`
- `publishPrepared`
- `takeValidatedSubmitWithLatest`
- `validatePrepared`
- `acceptSubmitted`
- `pendingState`
- `prepareTokenForRetainedState`
- `forceFull`
- `isStalePrepared`
- `fullPrepareReason`

Move from `surface/flow.zig` to `render/geometry.zig`:

- `Flow.render_px`
- `Flow.grid_px`
- `Flow.cell_px`
- `Flow.geometry_epoch`
- `Flow.syncGeometry` renamed to `sync`
- `Flow.prepareLayout` renamed to `prepareLayout`

Do not move `source_dirty_epoch` to geometry. Keep it in `SurfaceTextOwner` as
source input sequencing.

### `SurfaceTextOwner` Replacement Fields

Replace:

```zig
flow: flow.Flow,
```

With:

```zig
geometry: render_geometry.GeometryOwner,
source_slot: source_slot.SourceSlot,
prepare_requests: source_prepare.PrepareRequests,
submitted: session_submitted.Submitted,
source_dirty_epoch: u64 = 0,
cursor_blink_visible: bool = true,
```

Required imports in `surface/text.zig`:

```zig
const render_geometry = @import("../render/geometry.zig");
const source_vt = @import("../source/vt.zig");
const source_slot = @import("../source/slot.zig");
const source_prepare = @import("../source/prepare_request.zig");
const session_submitted = @import("../session/submitted.zig");
```

Required session-owner methods:

- `nextSourceDirtyEpoch()`
- `submittedToken()`
- `syncGeometry()`
- `setCursorBlinkVisible()`
- `reservePublishSlot()`
- `commitPublishSlot()`
- `cancelPublishSlot()`
- `rejectPublishSlot()`
- `prepare()`
- `publishPrepared()`
- `submit()`
- `acceptSubmitted()`
- `pendingState()`

These methods are explicit composition points. Do not replace `flow.Flow` with a
new umbrella owner.

### Required Call-Site Changes

In `ffi.zig`:

- Remove `const flow = @import("surface/flow.zig");`.
- Replace every `owner.flow.*` call with the matching `owner.*` composition
  method.
- Replace direct `owner.flow.publication_state.reserved` access with an explicit
  `SourceSlot` accessor.
- Replace helper types:
  - `flow.VtPublishResult` -> `source_vt.VtPublishResult`
  - `flow.PublicationSlot` -> `source_slot.PublicationSlot`
  - `flow.PendingState` -> session/source pending DTO selected by worker

In `surface/text.zig`:

- Remove `const flow = @import("flow.zig");`.
- `PrepareInput.state` becomes `source_vt.PublicationSource`.
- `prepareHandle()` consumes from `prepare_requests` and `geometry`, not `flow`.
- Tests initialize explicit owners, preferably through `SurfaceTextOwner.create`.

In `surface/input.zig`:

- Remove `const flow = @import("flow.zig");`.
- Function parameters use `source_vt.PublicationSource`.
- Source cell/color symbols come from `source_vt` if folded, otherwise from the
  temporary narrow publication-source file.

In `surface/prepared_owner.zig`:

- No behavior change expected if `SurfaceTextOwner` retained-pixel and session
  methods keep the same names.

### Tests To Move

Move submitted-output tests to `session/submitted.zig`:

- `surface validates submit candidates before GPU mutation`
- `surface keeps submitted identity as retained base only`
- `surface reports stale submit when newer snapshot already won`

Move prepare lifecycle tests to `source/prepare_request.zig`:

- `flow keeps blink refresh out of source publication queue`
- `flow redraws blinking cursor phase without a fresh vt source`
- `new vt source supersedes pending blink refresh`
- `failed taken prepare is retryable without blink refresh`
- `full prepare after submitted frame carries no retained base`
- `flow coalesces snapshots into latest prepare request`
- `flow turns partial snapshot full without retained base`
- `flow keeps latest source when publish A then B before prepare`
- `flow rejects mismatched prepare token against retained source`
- `flow forces full snapshot damage while prior snapshot is still pending`
- `flow forces full snapshot on scroll row change`
- `flow drops clean snapshot`

Move source damage tests to `source/damage.zig`:

- `cursor movement republishes clean later vt snapshot`
- `cursor shape change republishes clean later vt snapshot`
- `color state change republishes clean later vt snapshot`
- `flow canonicalizes clean dirty metadata before equality dedupe`
- `flow preserves dirty row spans and sentinels while canonicalizing`
- `flow boundary rejects invalid dirty metadata before canonicalization`

Move source slot tests to `source/slot.zig`:

- `flow reuses retained publish slot storage across reservations`
- `flow commit publish slot rejects dirty row byte outside boolean domain`
- `flow commit publish slot accepts dirty row span sentinel without dirty columns`
- `flow commit publish slot canonicalizes clean dirty metadata`

Keep full composition tests in `surface/text.zig`:

- `flow rejects stale submit and requests full latest prepare`
- `flow drops pending prepare at submitted token`
- `flow exposes source pending before queue preparation`
- tests that require geometry, source slot, prepare requests, and submitted
  owner together

Rename moved test names away from `flow`.

### New Tests Required

- `surface text owner keeps source and submitted owners separate`
- `submitted owner has no source publication state`
- `prepare requests do not own submitted mailbox`
- `source slot commit returns source without prepare or submit state`

### Verification

From `/home/home/personal/projects/howl`:

- `zig build check`
- `zig build test`

If root build taxonomy blocks a package-specific aggregate, also run from
`/home/home/personal/projects/howl/howl-render`:

- `zig build check`
- `zig build test`

### Grep Gates

No matches under `howl-render/src`:

- `flow.zig`
- `@import("flow.zig")`
- `surface/flow.zig`
- `\bFlow\b`
- `flow:`
- `owner.flow`
- `.publication_state`

No submitted-output owner symbols under `howl-render/src/source` or
`howl-render/src/render`:

- `SubmitMailbox`
- `submitted_frame`
- `SubmitDecision`

No prepared/submitted output ownership under `howl-render/src/source`:

- `RenderSurfaceFeedback`

Allowed in `source/prepare_request.zig`:

- `tokens.RenderRequest`
- `tokens.SnapshotToken`

No new owner names under the new folders:

- `manager`
- `controller`
- `runtime`
- `screen`
- `pipeline`
- `queue`

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
