# V0 Alpha Atlas Entry Bound

Owner: workspace root.

Status: implemented; pending commit.

## Problem

The host glyph patch slice eliminated host unsupported-shape fallback for no-full-clear glyph frames,
but the user log still shows steady old-path fallback:

- `v0_unsupported_shape=0`
- `v0_emit_status=5`
- `resource_plan_status=call_failed`
- `no_sidecar_call_failed=9-10`
- `rgba_fallback=9-10`
- `create=1`, `upload=384`, `delete=0`, `churn_same_frame=0`

This means the host can present valid glyph patch frames, but the renderer stops producing V0
sidecars after the alpha atlas entry table reaches 384 distinct entries. The host then has no V0
frame and correctly falls back to full RGBA.

## Source Facts

- `HOWL_RENDER_V0_EMIT_RESOURCE_BOUND_OVERFLOW == 5` in `howl-render/include/howl_render.h`.
- `howl-render/src/prepared/owner.zig` maps `error.ResourceBoundOverflow` to status 5.
- `howl-render/src/protocol_v0/emit.zig` uses `persistent_sprite_resources_max = 384` for both
  persistent sprite resources and alpha atlas entries.
- `SpriteResourceStore.atlasRegionFor()` returns `ResourceBoundOverflow` when
  `atlas_count >= persistent_sprite_resources_max`.
- Current atlas emission creates one `HOWL_RENDER_V0_RESOURCE_GLYPH_ATLAS_ALPHA` resource and uploads
  each new alpha raster into that atlas.

## Decision

The next product slice is render-owned V0 sidecar availability. Do not delete the old full-RGBA path
until V0 sidecars stop disappearing in normal workloads.

## Required Shape

- Remove the accidental 384-entry alpha atlas cap from steady normal workloads by replacing it with
  a larger explicit static bound or a bounded multi-page atlas shape.
- Keep resource, upload, command, and byte bounds explicit and tested.
- Preserve fail-closed `ResourceBoundOverflow` when the new bound is truly exhausted.
- Do not change the C ABI.
- Do not add host-owned resource eviction or ack/removal.
- Do not change full RGBA fallback/oracle in this slice.

## Verification

- From `howl-render`: `zig build test:unit -- "protocol v0"`
- From `howl-render`: `zig build test:protocol-proof -- "protocol v0"`
- From `howl-render`: `zig build test`
- From `howl-render`: `git diff --check`
- From workspace root: `zig build check`
- From workspace root: `zig build test`
- From workspace root: `git diff --check`

## Implementation

- Split alpha atlas entry capacity from persistent sprite resource capacity.
- Kept one fixed 1024x1024 alpha atlas resource.
- Added explicit `alpha_atlas_entries_max = 1024` with compile-time assertions.
- `SpriteResourceStore.atlas_entries` now uses `alpha_atlas_entries_max`.
- `atlasRegionFor()` fails closed with `ResourceBoundOverflow` only when the explicit alpha atlas
  entry table is exhausted or atlas packing/resource bounds fail.
- No host, ABI, batching, or full-RGBA fallback changes.

## Accepted Tests

- Unit test: explicit alpha atlas entry exhaustion returns `ResourceBoundOverflow` and preserves
  `atlas_count`.
- Protocol proof test: 385 distinct alpha prepared sprite entries emit V0 successfully, exceeding
  the former 384 cap.

## Verified

- From `howl-render`: `zig build test:unit -- "protocol v0"`
- From `howl-render`: `zig build test:protocol-proof -- "protocol v0"`
- From `howl-render`: `zig build test`
- From `howl-render`: `git diff --check`
- From workspace root: `zig build check`
- From workspace root: `zig build test`
- From workspace root: `git diff --check`

## Follow-Up

- Rerun user `btop` / `nvim` scenario.
- If `rgba_fallback` persists after `v0_emit_status=5` is eliminated, research the next sidecar-loss
  status before touching CPU or deleting fallback.
- Once `rgba_fallback=0` steady state is proved, promote explicit full-RGBA runtime deletion.
