# Sprint: Raster Special Ownership Compression

Date: 2026-06-13.

Owner: orchestrator.

Status: implementation complete; Slice 5 accepted and sprint ready to close.

Orchestrator session id: `orch-2026-06-13-raster-special-01`.

Researcher session id: `research-2026-06-13-raster-special-01`.

Reviewer session id: `review-2026-06-13-raster-special-01`.

Commit-hash receipt: root `0e53a8e`.

## Problem Statement

- The render scene compression sprint is closed and archived.
- The next loudest current render concentration is `howl-render/src/text/raster/special.zig`.
- That owner currently carries undercurl request construction, generated-special family routing, box/powerline/block/sextant/octant/branch rasterization, curve coverage helpers, and local proof pressure in one large file.
- The next sprint must determine the exact source-backed owner compression cut for that seam without widening into render-wide redesign, ABI churn, or host work.

## User Direction

- Seed the next sprint now because the active surface is clean but empty.
- Prefer `howl-render/src/text/raster/special.zig` as the next battlefield.
- Pressure the target with reference guidance before any execution plan is accepted.

## Planning Boundary

- Primary target: `/home/home/personal/projects/howl/howl-render/src/text/raster/special.zig`.
- Immediate owner seams are in scope only when needed to prove the split boundary or proof obligations:
  - `/home/home/personal/projects/howl/howl-render/src/text/raster/rasterizer.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/raster/key.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/special_glyphs.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/scene.zig`
  - current render unit proof roots that already prove generated-special and undercurl raster behavior
- Ranked fallback pressure points if research proves `special.zig` should not go first:
  1. `/home/home/personal/projects/howl/howl-render/src/text/scene.zig`
  2. `/home/home/personal/projects/howl/howl-linux-host/src/display/render_surface.zig`
  3. `/home/home/personal/projects/howl/howl-render/src/surface/emitter.zig`
  4. `/home/home/personal/projects/howl/howl-linux-host/src/terminal/surface.zig`
  5. `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig`
- Planning must produce the full sequential slice queue with exact allowed files, exact required shape, exact tests, exact non-goals, and exact stop conditions.

## Execution Authorization

- Slice 1 is accepted in `howl-render` `42b68b8`; root `a8c3e50`.
- Slice 2 is accepted in `howl-render` `a542d8a`; root `c52f69d`.
- Slice 3 is accepted in `howl-render` `24286d6`; root `0a73776`.
- Slice 4 is accepted in `howl-render` `1986d89`; root `b9954fb`.
- Slice 5 is accepted in `howl-render` `9270a11`; root receipt pending orchestrator commit.
- The accepted plan is `/home/home/personal/projects/howl/research/2026-06-13-raster-special-ownership-compression-plan.md`.
- No further slice is authorized until the orchestrator closes or reseeds the sprint.

## Seed Pressure Anchors

- `howl-render/src/text/raster/special.zig:5` `requestForUndercurl`
- `howl-render/src/text/raster/special.zig:19` `rasterizeUndercurlAlpha`
- `howl-render/src/text/raster/special.zig:49` `rasterizeGeneratedSpecialAlpha`
- `howl-render/src/text/raster/special.zig:53` `rasterizeGeneratedSpecialAlphaWithMetrics`
- `howl-render/src/text/raster/special.zig:383` `SpriteShade`
- `howl-render/src/text/raster/special.zig:742` `BranchNode`
- `howl-render/src/text/raster/special.zig:874` `BoxLines`
- `howl-render/src/text/raster/special.zig:1233` `Range`
- `howl-render/src/text/raster/special.zig:1477` `CubicBezier`
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/atlas.rs:32-71`
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs:42-79`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:90-99`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:102-176`

## Stop Conditions

- Stop if research cannot produce a full slice queue without coder invention.
- Stop if the proposed split needs a user-level override against Alacritty, TigerBeetle, or the C ABI boundary.
- Stop if planning drifts into implementation, benchmark theater, or generalized render redesign.
- Stop if active `loops/`, `research/`, or `sprints/` no longer match real live state.
