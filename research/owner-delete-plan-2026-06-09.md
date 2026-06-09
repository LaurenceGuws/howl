# Prepared Owner Deletion Research

Date: 2026-06-09.
Role: researcher.
Status: active.
Loop: `loops/ascii-rain-baseline-bottleneck.txt`.
Primary researcher session id: `research-2026-06-09-owner-delete-plan-01`.

## Sources Read In Order

1. `/home/home/personal/projects/howl/loop/flow.md`
2. `/home/home/personal/projects/howl/loop/researcher.md`
3. `/home/home/personal/projects/howl/sprints/current.txt`
4. `/home/home/personal/projects/howl/loops/ascii-rain-baseline-bottleneck.txt`
5. historical benchmark context:
   - `/home/home/personal/projects/howl/research/done/cache-2026-06-08-ascii-rain-benchmark-surface.md`
6. `/home/home/personal/projects/howl/reference-index.md`
7. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
8. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
9. current Howl source:
   - `/home/home/personal/projects/howl/howl-render/src/prepared/owner.zig`
   - `/home/home/personal/projects/howl/howl-render/src/prepared/surface.zig`
   - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
   - `/home/home/personal/projects/howl/howl-render/src/session/text.zig`
   - `/home/home/personal/projects/howl/howl-render/src/ffi/prepared_surface.zig`
   - `/home/home/personal/projects/howl/howl-render/src/ffi/submission.zig`
   - `/home/home/personal/projects/howl/howl-render/src/ffi/handle.zig`
   - `/home/home/personal/projects/howl/howl-render/src/prepared/owner_test.zig`
   - `/home/home/personal/projects/howl/howl-render/src/ffi/prepared_surface_test.zig`
   - `/home/home/personal/projects/howl/howl-render/src/ffi/test_support.zig`
10. Alacritty references:
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/mod.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs`

## Current-Code Facts

- `howl-render/src/prepared/owner.zig` is broad bucket ownership, not an owner-true seam:
  - debug timing: `/home/home/personal/projects/howl/howl-render/src/prepared/owner.zig:20-64`
  - exported metadata/failure types: `/home/home/personal/projects/howl/howl-render/src/prepared/owner.zig:66-93`
  - handle object state and lifecycle: `/home/home/personal/projects/howl/howl-render/src/prepared/owner.zig:95-180`
  - info/buffer/render-surface accessors: `/home/home/personal/projects/howl/howl-render/src/prepared/owner.zig:182-215`
  - submit validation and execution: `/home/home/personal/projects/howl/howl-render/src/prepared/owner.zig:217-249`
  - consume/release/deinit: `/home/home/personal/projects/howl/howl-render/src/prepared/owner.zig:251-284`
  - summary construction and failure mapping: `/home/home/personal/projects/howl/howl-render/src/prepared/owner.zig:287-316`
- `TextSessionOwner` already owns the parent choreography seam:
  - cached publish/submit handles and handle array: `/home/home/personal/projects/howl/howl-render/src/session/text.zig:440-444`
  - prepare handoff into `Owner.create`: `/home/home/personal/projects/howl/howl-render/src/session/text.zig:499-523`
  - handle registration and cached-handle clearing: `/home/home/personal/projects/howl/howl-render/src/session/text.zig:525-533`
- `PreparedSurface` already owns prepared render data and token derivation:
  - `/home/home/personal/projects/howl/howl-render/src/prepared/surface.zig:7-43`
- `render_surface_emitter.zig` already owns render-surface emission:
  - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig:117-240`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig:243-679`
- FFI currently depends on `Owner` for too much:
  - prepared-surface boundary: `/home/home/personal/projects/howl/howl-render/src/ffi/prepared_surface.zig:21-80`
  - submission boundary: `/home/home/personal/projects/howl/howl-render/src/ffi/submission.zig:15-189`
  - handle casts: `/home/home/personal/projects/howl/howl-render/src/ffi/handle.zig:10-15`

## Reference Facts

- Alacritty keeps content prep, frame orchestration, and renderer submission separate:
  - renderable cell filtering: `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:153-183`
  - empty-cell rule: `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:301-307`
  - display orchestration: `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:783-1008`
  - renderer APIs only: `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/mod.rs:177-255`
- TigerBeetle pressure rejects vague bucket ownership and requires the true parent owner to keep centralized policy.

## Proposed Shape

Delete `prepared/owner.zig` by moving responsibilities into true owners:

1. `howl-render/src/prepared/surface.zig`
- own prepared metadata truth:
  - `PreparedInfo`
  - `PreparedBuffer`
  - pure metadata helpers

2. `howl-render/src/prepared/render_surface_emitter.zig`
- own render-surface emission failure type and failure mapping

3. `howl-render/src/prepared/handle.zig`
- new domain-true owner `PreparedHandle`
- own only:
  - opaque handle storage
  - lifecycle state
  - session pointer
  - owned `PreparedSurface`
  - optional emitted payload pointer
  - liveness/release/consume

4. `howl-render/src/session/text.zig`
- own:
  - handle allocation
  - handle registration arrays
  - publish/submit choreography
  - submit execution against `session.submitSurface(...)`

5. `howl-render/src/ffi/*`
- translation only
- no lifecycle or submit policy

## Exact Dependent Files

First-order source:

- `/home/home/personal/projects/howl/howl-render/src/prepared/owner.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/handle.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/surface.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
- `/home/home/personal/projects/howl/howl-render/src/session/text.zig`
- `/home/home/personal/projects/howl/howl-render/src/ffi/handle.zig`
- `/home/home/personal/projects/howl/howl-render/src/ffi/prepared_surface.zig`
- `/home/home/personal/projects/howl/howl-render/src/ffi/submission.zig`

First-order tests/support:

- `/home/home/personal/projects/howl/howl-render/src/prepared/owner_test.zig`
- `/home/home/personal/projects/howl/howl-render/src/ffi/prepared_surface_test.zig`
- `/home/home/personal/projects/howl/howl-render/src/ffi/test_support.zig`
- `/home/home/personal/projects/howl/howl-render/src/test/unit/root.zig`

## Sequential Slice Plan

1. `owner-map-landing`
- introduce `PreparedHandle`
- move metadata to `surface.zig`
- move emission failure mapping to `render_surface_emitter.zig`
- rewire `TextSessionOwner` handle storage
- `prepared/owner.zig` may remain only as a temporary shim in this slice

2. `session-submit-choreography`
- move publish/submit policy and execution into `TextSessionOwner`
- keep `PreparedHandle` as storage/liveness only

3. `prepared-surface-boundary-cleanup`
- make `ffi/prepared_surface.zig` and `ffi/handle.zig` independent from `prepared/owner.zig`

4. `delete-owner-zig`
- remove `prepared/owner.zig`
- replace owner-bucket tests with owner-true tests

5. `post-owner-performance`
- resume measured optimization only after slice 4 is accepted

## Required Assertions

- lifecycle transitions on `PreparedHandle`
- session ownership checks at the session boundary
- prepared-token equality separate from execution geometry checks
- one-to-one failure mapping from emitter errors to prepared-surface boundary status

## Required Tests

- lifecycle tests for `PreparedHandle`
- metadata tests for `PreparedSurface`
- failure-mapping tests for `render_surface_emitter.zig`
- FFI prepared-surface boundary tests
- FFI submission choreography tests

## Non-Goals

- no host GL work
- no benchmark-tool work
- no PTY/runtime work
- no new umbrella runtime or submission layer
- no performance claims before `prepared/owner.zig` is deleted

## Readiness Judgment

Ready for the first ownership-correction slice.

- The user direction is explicit.
- The replacement seams are source-backed.
- The ABI can stay stable while internal ownership changes.
- `prepared/owner.zig` should now be treated as deletion work, not optimization surface.
