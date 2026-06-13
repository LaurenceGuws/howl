Historical authority: active sprint artifact for the completed host render-surface ownership sprint.
Why superseded or done: planning and all seeded execution slices are accepted and closed.
Must not be used for: live sprint authority after close without re-promotion.

# Sprint: Host Render Surface Ownership

Date: 2026-06-13.

Owner: orchestrator.

Status: Slice 3 accepted; sprint execution complete.

Orchestrator session id: `orch-2026-06-13-host-render-surface-01`.

Researcher session id: `research-2026-06-13-host-render-surface-01`.

Reviewer session id: `review-2026-06-13-host-render-surface-01`.

Planning acceptance commit-hash receipt: `455402d` `Accept host render-surface planning`.

Active execution slice:

- Slice 1 acceptance receipt: `5c7a2a2` `Extract host render-surface resources`.
- Slice 2 acceptance receipt: `2977c3b` `Extract host render-surface commands`.
- Slice 3 acceptance receipt: `618d0c5` `Curate host render-surface root`.
- Last coder session id: `coder-2026-06-13-host-render-surface-slice-03`.
- Reviewer session id for execution: `review-2026-06-13-host-render-surface-01`.
- Execution seed commit-hash receipt: `afe558e` `Accept host render-surface Slice 2`.

## Problem Statement

- The raster special ownership sprint is closed and archived.
- The next biggest remaining seam is `howl-linux-host/src/display/render_surface.zig`.
- That host owner currently mixes GL backend realization with local surface-trust validation and transition simulation.
- The next sprint must determine the exact source-backed owner compression cut for that seam without weakening host/backend truth or inventing a runtime layer.

## User Direction

- Do not stay out of host code.
- Make everything pristine.
- Push the next sprint into host ownership pressure rather than avoiding it.

## Planning Boundary

- Primary target: `/home/home/personal/projects/howl/howl-linux-host/src/display/render_surface.zig`.
- Immediate owner seams are in scope only when needed to prove the split boundary or proof obligations:
  - `/home/home/personal/projects/howl/howl-linux-host/src/display/display.zig`
  - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/surface.zig`
  - `/home/home/personal/projects/howl/howl-render/include/howl_render.h`
  - `/home/home/personal/projects/howl/howl-render/src/surface/emitter.zig`
  - current host and render proof roots that cover resource create/upload/retire behavior
- Ranked fallback pressure points if research proves `render_surface.zig` should not go first:
  1. `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig`
  2. `/home/home/personal/projects/howl/howl-render/src/text/scene.zig`
  3. `/home/home/personal/projects/howl/howl-linux-host/src/terminal/surface.zig`
  4. `/home/home/personal/projects/howl/howl-render/src/surface/emitter.zig`
  5. `/home/home/personal/projects/howl/howl-vt/src/parser.zig`

## Execution Authorization

- Slice execution is complete.
- No further implementation is authorized under this sprint.

## Seed Pressure Anchors

- `howl-linux-host/src/display/render_surface.zig:34` `RenderResourceTextures`
- `howl-linux-host/src/display/render_surface.zig:56` `realizeSurface`
- `howl-linux-host/src/display/render_surface.zig:60` `realizeSurfaceLocked`
- `howl-linux-host/src/display/render_surface.zig:92` `validateSurface`
- `howl-linux-host/src/display/render_surface.zig:96` `validateSurfaceTransition`
- `howl-linux-host/src/display/render_surface.zig:121` `noteCreate`
- `howl-linux-host/src/display/render_surface.zig:140` `noteUpload`
- `howl-linux-host/src/display/render_surface.zig:146` `noteRetire`

## Stop Conditions

- Stop if research cannot produce a full slice queue without coder invention.
- Stop if the proposed split needs a user-level override against Alacritty, TigerBeetle, or the host/render boundary.
- Stop if planning drifts into implementation, benchmark theater, or generalized host-runtime redesign.
- Stop if active `loops/`, `research/`, or `sprints/` no longer match real live state.
