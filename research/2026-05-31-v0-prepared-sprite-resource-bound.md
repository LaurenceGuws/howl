# V0 Prepared Sprite Resource Bound

Owner: workspace root.

Status: promoted to `current.txt`; implementation pending.

Accepted prerequisite commits:

- `howl-linux-host` `e0bffa3` - `host: fix protocol v0 fbo orientation`
- root `5f792f5` - `design: record v0 fbo orientation fix`

## Problem

User `rain` and `btop` runs after the orientation fix exposed a separate resource-bound
regression.

- `btop` initially reached V0 retained sprite patch presentation, then entered steady fallback.
- Diagnostic sample showed `v0_emit_status=5`, which is
  `HOWL_RENDER_V0_EMIT_RESOURCE_BOUND_OVERFLOW`.
- The same sample showed `resource_plan_status=call_failed`, `no_sidecar_call_failed=10`,
  and `rgba_fallback=10` every interval.
- That proves full RGBA fallback for each sampled submit after the resource bound was hit.
- Resource diagnostics showed `slots live=439`, `retired=0`, `delete=0`, with growing
  `gl gen/image/subimage` counts.
- User observed about 980 MB memory usage.
- User reported `rain` still hurts thread performance when zoomed out.

## Code Facts

- `howl-render/src/protocol_v0/emit.zig:SpriteResourceStore` is renderer-owned persistent
  sprite resource storage for prepared V0 frames.
- `SpriteResourceStore.resourceFor()` grows `entries` and `bytes` for each new sprite
  identity/hash/shape until `HOWL_RENDER_V0_RESOURCES_MAX` or the 64 KiB byte budget is hit.
- `Emitter.emitPrepared()` copies `next_resources` back only after all emission succeeds.
- That preserves state on failure, but cache saturation remains a permanent reason to fail
  future V0 sidecars for new sprites.
- Prepared persistent sprite emission does not currently emit same-frame retires for
  non-persistent sprites.
- Host resource deletion is intentionally not protocol ack.
- No host-owned eviction or ack contract exists yet.

## Promoted Slice

- `current.txt` - `V0 Prepared Sprite Resource Bound`

## Required Shape

- Keep reuse of already-persistent prepared sprite resources.
- Bound growth of renderer-owned persistent sprite resources before resource pressure disables
  V0 sidecars.
- For new sprites that cannot be made persistent, emit same-frame create/upload/draw/retire
  when frame create/upload/upload-byte/retire limits allow it.
- If transient emission cannot fit, preserve full RGBA fallback and report the exact bound that
  failed.
- Do not add host-side eviction or ack semantics in this slice.

## Acceptance Gates

- Protocol proof tests cover persistent reuse, persistent cache bound, transient
  create/upload/draw/retire, and exact overflow status.
- `btop` smoke should not remain in steady-state `v0_emit_status=5` with
  `no_sidecar_call_failed=10` per interval after resource pressure.
- Existing root and subrepo gates still pass.

## Implementation

- `howl-render/src/protocol_v0/emit.zig` now caps renderer-owned persistent prepared
  sprite resources at `persistent_sprite_resources_max = 384`, below the ABI resource max.
- Existing persistent resources still reuse their prior resource IDs with no create/upload/retire.
- New sprites beyond the persistent budget receive monotonic transient resource IDs.
- Transient sprites emit create/upload/draw/retire in the same V0 frame.
- Transient retire sequence is the command count after the draw command, so the resource remains
  visible for its draw and is retired immediately after.
- If transient create/upload/upload-byte/command/retire limits are exceeded, emission fails with
  the exact existing bound error and full RGBA remains the oracle/fallback.
- No host-owned eviction, backend ack, or ABI change was added.

## Verification

- From `howl-render`: `zig build test:protocol-proof -- "protocol v0"`
- From `howl-render`: `zig build test:unit -- "protocol v0"`
- From `howl-render`: `zig build test`
- From `howl-render`: `git diff --check`
- From workspace root: `zig build check`
- From workspace root: `zig build test`
- From workspace root: `git diff --check`
- From `howl-linux-host`: `zig build test --summary all`
- From `howl-linux-host`: `zig build -Doptimize=ReleaseFast`
- From `howl-linux-host`: `git diff --check`

Smoke:

- From `howl-linux-host`: `timeout 22s zig build run -Doptimize=ReleaseFast -- --duration-ms 18000 --debug-process-accounting --debug-log-every-ms 5000 --command btop`
- Result did not reproduce the prior steady-state failure:
  `v0_emit_status=0`, `no_sidecar_call_failed=0`, steady intervals with `rgba_fallback=0`,
  and `sprite_patch_present=10`.
- This smoke did not reach the transient cap; protocol proof tests cover the transient path.
