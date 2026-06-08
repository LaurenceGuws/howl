# Sprint: Render-Surface Retrieval Status Hygiene

Date: 2026-06-02

Owner: orchestrator

Status: accepted for worker handoff after current.txt promotion

## User Direction

- The C ABI is code like the rest.
- Howl is young and private; there is no years-old downstream foundation to protect.
- Bad ABI style should be molded while hot.
- ABI cleanup is in scope.
- C ABI only remains non-negotiable: no Zig-shaped host shortcuts, no compatibility shims unless the
  user explicitly requires them.
- Nobody narrows scope besides the user.

## Accepted Research

- `research/cache-2026-06-02-hygiene-offenders-a.md`
- `research/cache-2026-06-02-hygiene-offenders-b.md`
- `research/cache-2026-06-02-hygiene-offenders-c.md`
- `research/cache-2026-06-02-hygiene-readiness-map.md`
- `research/cache-2026-06-02-render-surface-abi-status-readiness.md`

## Accepted Review

The first hygiene implementation slice is ABI/status cleanup before host validation extraction.

Accepted facts:

- `render_surface_emit_status` is a real render-owned consequence.
- It is not prepared-surface metadata.
- It belongs to prepared render-surface retrieval.
- Host retained/context currently duplicate that consequence with private unavailable statuses.
- The first slice must reshape the C ABI and call sites directly; no old enum names, aliases,
  translation shims, or compatibility wrappers.

Rejected shapes:

- `render_surface_emit_status` on `HowlRenderPreparedSurfaceInfo`.
- A bucket result struct for pointer plus status.
- A new `display/renderer/render_surface_contract.zig` owner in this slice.
- Any public ABI compatibility shim.

## Problem

Prepared surface info currently carries `render_surface_emit_status`, but render-surface availability is
not stable prepared metadata. It is the consequence of asking a live prepared handle for its borrowed
`HowlRenderSurface` payload.

Current consequence chain is too broad:

- `howl-render` records `render_surface_emit_status` in `PreparedInfo`.
- `howl_render_prepared_surface_render_surface(...)` returns generic `HowlRenderCallStatus` and nulls the
  surface pointer when the payload is unavailable.
- `howl-linux-host/src/terminal/render/retained.zig` also classifies null/unavailable through
  `PreparedRenderResourcePlanStatus.call_failed` and `.null_surface`.
- `howl-linux-host/src/terminal/context.zig` then maps both the render emit status and retained private
  plan status in the unavailable path.

The slice makes one C-visible retrieval status the single authority for prepared render-surface
availability.

## Exact ABI Shape

In `howl-render/include/howl_render.h`, replace `HowlRenderSurfaceEmitStatus` with:

```c
typedef enum {
    HOWL_RENDER_PREPARED_SURFACE_RENDER_SURFACE_OK = 0,
    HOWL_RENDER_PREPARED_SURFACE_RENDER_SURFACE_MISSING_HANDLE = -1,
    HOWL_RENDER_PREPARED_SURFACE_RENDER_SURFACE_INVALID_ARGUMENT = -2,
    HOWL_RENDER_PREPARED_SURFACE_RENDER_SURFACE_COMMAND_BOUND_OVERFLOW = 1,
    HOWL_RENDER_PREPARED_SURFACE_RENDER_SURFACE_CREATE_BOUND_OVERFLOW = 2,
    HOWL_RENDER_PREPARED_SURFACE_RENDER_SURFACE_DAMAGE_BOUND_OVERFLOW = 3,
    HOWL_RENDER_PREPARED_SURFACE_RENDER_SURFACE_RETIRE_BOUND_OVERFLOW = 4,
    HOWL_RENDER_PREPARED_SURFACE_RENDER_SURFACE_RESOURCE_BOUND_OVERFLOW = 5,
    HOWL_RENDER_PREPARED_SURFACE_RENDER_SURFACE_UPLOAD_BOUND_OVERFLOW = 6,
    HOWL_RENDER_PREPARED_SURFACE_RENDER_SURFACE_UPLOAD_BYTES_OVERFLOW = 7,
    HOWL_RENDER_PREPARED_SURFACE_RENDER_SURFACE_INVALID_PREPARED_SPRITE = 8,
    HOWL_RENDER_PREPARED_SURFACE_RENDER_SURFACE_MISSING_PREPARED_SPRITE = 9,
    HOWL_RENDER_PREPARED_SURFACE_RENDER_SURFACE_ALLOCATION_FAILED = 10,
} HowlRenderPreparedSurfaceRenderSurfaceStatus;
```

Change the function signature to:

```c
HowlRenderPreparedSurfaceRenderSurfaceStatus howl_render_prepared_surface_render_surface(
    HowlRenderPreparedSurfaceHandle prepared_surface_handle,
    const HowlRenderSurface **surface_out
);
```

Remove from `HowlRenderPreparedSurfaceInfo`:

```c
int32_t render_surface_emit_status;
uint32_t reserved2;
```

No old enum name, old constants, field aliases, or compatibility wrappers may remain.

## Allowed Files

Render:

- `howl-render/include/howl_render.h`
- `howl-render/src/ffi/prepared_surface.zig`
- `howl-render/src/prepared/owner.zig`
- `howl-render/src/test/ffi.zig`
- Existing render ABI/layout test owner reached through `howl-render/src/test.zig`, if needed.

Host:

- `howl-linux-host/src/terminal/render/retained.zig`
- `howl-linux-host/src/terminal/context.zig`
- Existing retained/context tests in those files only as needed.

Allowed only if a compile break proves a direct signature dependency:

- `howl-linux-host/src/display/renderer/render_surface.zig`

## Required Render Changes

- Remove `HowlRenderSurfaceEmitStatus` from the public header.
- Add `HowlRenderPreparedSurfaceRenderSurfaceStatus` exactly as specified above.
- Remove `render_surface_emit_status` and `reserved2` from `HowlRenderPreparedSurfaceInfo`.
- Remove `render_surface_emit_status` from `prepared_owner.PreparedInfo`.
- Keep owner-local storage of the render-surface emit consequence if needed, but expose it through
  prepared render-surface retrieval only.
- Change `prepared_surface.renderSurface(...)` to return
  `HowlRenderPreparedSurfaceRenderSurfaceStatus` values directly.
- On missing handle, return `MISSING_HANDLE` and null the output pointer if present.
- On null output pointer, return `INVALID_ARGUMENT`.
- On released/non-live handle, return `INVALID_ARGUMENT` and null the output pointer if present.
- On available surface, write the surface pointer and return `OK`.
- On unavailable render surface payload, return the exact render-owned retrieval status corresponding to
  the original emit failure and leave the output pointer null.

## Required Host Changes

- `PreparedUpload` must carry:
  - `info: c.HowlRenderPreparedSurfaceInfo`
  - `render_surface_status: c.HowlRenderPreparedSurfaceRenderSurfaceStatus`
  - `render_surface_probe`
  - `render_surface_resource_plan`
  - `render_surface`
- `retained.zig` must call `howl_render_prepared_surface_render_surface(...)` and store the returned
  retrieval status.
- `PreparedRenderResourcePlanStatus.call_failed` and `.null_surface` must not be the context authority
  for render-owned emission failure after this slice.
- `context.zig` must panic from the retrieval status when `render_surface == null`.
- `context.zig` must not call `crashOnRenderSurfaceUnavailable(...)` for render emission failure.
- Display renderer `FailureBucket` remains display-private for GL/resource realization failures.

## Required Tests

Render FFI tests through `howl-render/src/test.zig` must cover:

- New retrieval status constants are stable.
- `HowlRenderPreparedSurfaceInfo` layout reflects the removed field.
- Missing handle returns `MISSING_HANDLE` and nulls output when provided.
- Null output pointer returns `INVALID_ARGUMENT`.
- Released/non-live handle returns `INVALID_ARGUMENT`.
- Live prepared surface with payload returns `OK` and writes a non-null pointer.
- At least one reachable emission-failure prepared surface returns the matching new retrieval status.

Host tests through existing host curated roots must cover:

- `PreparedUpload` records the retrieval status.
- Context unavailable path panics or maps from retrieval status, not private plan status.
- Existing retained, render-surface, and terminal-context tests still pass.

Do not add duplicate test roots or side-entry test files.

## Non-Goals

- Do not extract host validation into a new owner in this slice.
- Do not create `render_surface_contract.zig` or any other new owner file.
- Do not change GL texture ownership or move GL mutation out of `display/renderer/render_surface.zig`.
- Do not broadly split `terminal/context.zig`.
- Do not change VT or PTY ABI in this slice.
- Do not introduce compatibility aliases, old enum constants, old field names, or wrapper APIs.
- Do not import internal `howl-render` Zig modules into the host.

## Stop Conditions

- Stop if preserving behavior appears to require keeping old enum names, aliases, or compatibility shims.
- Stop if the worker cannot produce a single retrieval-status authority for surface availability.
- Stop if a public ABI layout assertion cannot be updated without weakening coverage.
- Stop if any host code still treats `PreparedRenderResourcePlanStatus.call_failed` or `.null_surface` as
  render emission failure authority after the slice.
- Stop if a duplicate test root or build-step split appears necessary.
- Stop if any malformed-surface defense, bounds check, or trusted panic is weakened.
- Stop if GL mutation moves into validation/status code.

## Verification

From `howl-render`:

- `zig fmt include src`
- `zig build check`
- `zig build test --summary all`
- `zig build -Doptimize=ReleaseFast`
- `git diff --check`

From `howl-linux-host`:

- `zig fmt src`
- `zig build check`
- `zig build test:unit --summary all`
- `zig build test --summary all`
- `zig build -Doptimize=ReleaseFast`
- `git diff --check`

Runtime smoke from `howl-linux-host`:

- `zig build run -Doptimize=ReleaseFast -- --command exit`

Workspace hygiene:

- Changed Zig/header lines must not exceed 190 chars.
- Root `git diff --check` must pass before commit.

## Reviewer Gates

- C ABI remains the only host-facing integration boundary.
- No Zig-shaped host shortcut appears.
- No compatibility shim appears.
- Old emit-status enum and prepared-info field are gone.
- Retrieval status is the single prepared render-surface availability consequence.
- Retained/display/context private statuses no longer duplicate render-owned emission failure authority.
- Assertions, bounds, layout tests, and trusted panic policy are preserved or sharpened.
