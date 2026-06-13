# Sprint: Render Scene Ownership Compression

Date: 2026-06-13.

Owner: orchestrator.

Status: Slice 1 accepted; Slice 2 seeded for execution.

Orchestrator session id: `orch-2026-06-13-render-scene-01`.

Researcher session id: `research-2026-06-13-render-scene-01`.

Reviewer session id: `review-2026-06-13-render-scene-01`.

Commit-hash receipt: root `2fde3dd`.

## Problem Statement

- Render still carries the biggest remaining structural complexity bill after the shallow-owner cleanup sprints.
- `howl-render/src/text/scene.zig` is the highest-pressure current owner seam because it bundles retained scratch ownership, scene assembly, draw-capacity counting, raster request accumulation, and multiple draw-family packing in one file.
- The next sprint must determine the exact source-backed owner compression cut for that seam without inventing a new architecture, moving ABI truth, or broadening into unrelated render churn.

## User Direction

- Use the next sprint on the render complexity bill.
- Start with `howl-render/src/text/scene.zig` unless the references and current source prove a different target must go first.
- Researcher must pressure the target with reference guidance before any execution plan is accepted.

## Planning Boundary

- Primary target: `/home/home/personal/projects/howl/howl-render/src/text/scene.zig`.
- Current adjacent owner seams are in scope only when needed to prove the split boundary or proof obligations:
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
  - `/home/home/personal/projects/howl/howl-render/src/render_session.zig`
  - `/home/home/personal/projects/howl/howl-render/src/vt_publication/text_input.zig`
  - `/home/home/personal/projects/howl/howl-render/src/surface/emitter.zig`
  - `/home/home/personal/projects/howl/howl-render/build.zig`
  - current render unit and benchmark proof roots that already exercise the scene owner
- Ranked fallback pressure points if research proves `scene.zig` is not the first true cut:
  1. `/home/home/personal/projects/howl/howl-render/src/surface/emitter.zig`
  2. `/home/home/personal/projects/howl/howl-linux-host/src/display/render_surface.zig`
  3. `/home/home/personal/projects/howl/howl-linux-host/src/terminal/surface.zig`
  4. `/home/home/personal/projects/howl/howl-vt/src/ffi/surface.zig`
  5. `/home/home/personal/projects/howl/howl-vt/src/parser.zig`
- Planning must produce the full sequential slice queue with exact allowed files, exact required shape, exact tests, exact non-goals, and exact stop conditions.

## Execution Authorization

- Slice 1 is accepted in `howl-render` `959576d`; root `5bbe0ec`.
- The accepted plan is `/home/home/personal/projects/howl/research/2026-06-13-render-scene-ownership-compression-plan.md`.
- Slice 2 is authorized through the live-loop execution contract only.

## Seed Pressure Anchors

- `howl-render/src/text/scene.zig:77` `RetainedScratch`
- `howl-render/src/text/scene.zig:107` `buildSceneWithOptions`
- `howl-render/src/text/scene.zig:138` `buildBorrowedSceneWithAtlasCacheOptions`
- `howl-render/src/text/scene.zig:160` `appendSceneAssemblyPopulation`
- `howl-render/src/text/scene.zig:188` `DrawCapacities`
- `howl-render/src/text/scene.zig:196` `SceneAssembly`
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:49-197`
- `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:24-208`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:90-99`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:102-176`

## Stop Conditions

- Stop if research cannot produce a full slice queue without coder invention.
- Stop if the proposed split needs a user-level override against Alacritty, TigerBeetle, or the C ABI boundary.
- Stop if planning drifts into implementation, benchmark theater, or generalized render redesign.
- Stop if active `loops/`, `research/`, or `sprints/` no longer match real live state.
