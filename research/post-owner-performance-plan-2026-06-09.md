# Post-Owner Performance Plan

Date: 2026-06-09.
Role: researcher.
Status: active.
Loop: `loops/emitter-alpha-reuse-fast-path.txt`.
Primary researcher session id: `research-2026-06-09-post-owner-performance-01`.

## Sources Read In Order

1. `/home/home/personal/projects/howl/loop/flow.md`
2. `/home/home/personal/projects/howl/loop/researcher.md`
3. `/home/home/personal/projects/howl/sprints/current.txt`
4. `/home/home/personal/projects/howl/loops/emitter-alpha-reuse-fast-path.txt`
5. `/home/home/personal/projects/howl/reference-index.md`
6. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
7. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
8. Current receipts:
   - `/home/home/personal/projects/howl/artifacts/stress/20260609-115340-ascii/summary.json`
   - `/home/home/personal/projects/howl/artifacts/stress/20260609-095340-ascii-direct-post-owner/howl-direct.accounting.log`
   - `/home/home/personal/projects/howl/artifacts/stress/20260609-095743-ascii-direct-post-owner-timing/howl-term.stderr.log`
9. Current Howl source:
   - `/home/home/personal/projects/howl/howl-render/src/session/text.zig`
   - `/home/home/personal/projects/howl/howl-render/src/prepared/handle.zig`
   - `/home/home/personal/projects/howl/howl-render/src/prepared/surface.zig`
   - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
   - `/home/home/personal/projects/howl/howl-render/src/prepared/sprite_resource_store.zig`
   - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
10. Alacritty references:
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs`

## Exact File And Line References

Howl:

- `TextSessionOwner.prepareHandle` still splits the live hot path into `prepareSurface` and `PreparedHandle.create`: `/home/home/personal/projects/howl/howl-render/src/session/text.zig:514`
- `PreparedHandle.create` is now a small owner boundary that delegates emission instead of hosting broad policy: `/home/home/personal/projects/howl/howl-render/src/prepared/handle.zig:92`
- `PreparedSurface` is a small metadata owner, not a bucket seam: `/home/home/personal/projects/howl/howl-render/src/prepared/surface.zig:8`
- `direct_normal.prepare` remains dominated by candidate scan and append:
  - scan and bounds walk: `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig:124`
  - append and atlas reserve path: `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig:261`
- `render_surface_emitter` owns bounded render-surface emission and resource publication:
  - bounded state and limits: `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig:157`
  - fill emission: `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig:316`
  - sprite emission and atlas lookup: `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig:406`
  - upload-byte staging: `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig:532`
- `SpriteResourceStore` owns atlas and direct-resource reuse truth:
  - direct resource reuse: `/home/home/personal/projects/howl/howl-render/src/prepared/sprite_resource_store.zig:95`
  - alpha atlas reuse: `/home/home/personal/projects/howl/howl-render/src/prepared/sprite_resource_store.zig:161`

Alacritty:

- content filtering stays separate from renderer submission: `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:153`
- display orchestration keeps text/rect submission split by true owner: `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:783`
- text rendering asks the glyph cache first and batches after the cache answer: `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:135`
- glyph cache returns immediately on cache hit instead of building upload payload first: `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs:200`

## Current-Code Facts

- Post-delete clean benchmark receipt moved Howl from `18.38 fps` to `79.42 fps`, while Alacritty on the same rerun is `1039.12 fps`:
  - `/home/home/personal/projects/howl/artifacts/stress/20260609-115340-ascii/summary.json`
- Post-delete direct host run is `109.56 fps` and still saturates `howl-main`, not PTY:
  - `/home/home/personal/projects/howl/artifacts/stress/20260609-095340-ascii-direct-post-owner/howl-direct.accounting.log`
- Stable post-delete host accounting intervals show:
  - `render_prepare_avg_us ~= 1290-1350`
  - `render_upload_avg_us ~= 306-342`
  - `present_submit_avg_us ~= 79-88`
  - `render_upload_fill_avg_us ~= 168-189`
  - `render_upload_glyph_avg_us ~= 61-75`
- Stable render timing split shows:
  - `prepare_surface_avg_us ~= 732-738`
  - `owner_create_avg_us ~= 938-951`
  - `direct_normal_avg_us ~= 731-737`
  - `direct_normal_scan_avg_us ~= 664-671`
  - `emit_prepared sprites_avg_us ~= 265-273`
  - `stage_upload_avg_us ~= 87-90`
  - `atlas_resource_avg_us ~= 92-95`
  - receipt: `/home/home/personal/projects/howl/artifacts/stress/20260609-095743-ascii-direct-post-owner-timing/howl-term.stderr.log`
- `direct_normal` is currently owner-true enough to leave alone for one more slice. Its remaining cost is mostly scan/append, not backgrounds, clears, decorations, or raster.
- `render_surface_emitter` is currently owner-true enough to optimize directly. It owns one thing: conversion of a prepared surface plus resource-store state into a bounded render surface.
- The current alpha glyph path still does false steady-state work:
  - it stages upload bytes before it knows whether the atlas already has the sprite
  - then asks the sprite-resource store for atlas reuse
  - on reuse, it rolls back upload-byte accounting only after the bytes were already copied
- The sprite-resource store proves atlas-hit detection itself does not require staged bytes, only the atlas key and dimensions.

## Reference Facts

- Alacritty keeps content prep, renderer batching, and display submission split by true owner. It does not retain a broad compatibility bucket for this seam.
- Alacritty checks the glyph cache before paying upload work on steady-state hits.
- TigerBeetle pressure here is:
  - keep the next slice inside the smallest true owner
  - remove measured false work before deeper redesign
  - stop performance work if another bucket seam is exposed

## Owner Roles And Proposed Shape

- `render_surface_emitter.zig` is the current smallest true owner for the hottest remaining false work.
- `sprite_resource_store.zig` is the cache truth owner that the emitter must ask first.
- `session/text.zig`, `prepared/handle.zig`, and `prepared/surface.zig` should not be reopened in the next slice unless implementation proves the current ownership map is still false.

## Sprint Scratchpad

- Broad sprint goal is unchanged: beat Alacritty on the agreed ASCII-rain benchmark.
- The last ownership-correction pass is complete and already paid off materially.
- The next performance slice should stay entirely inside the cleaned render emission/cache seam unless a new bucket is exposed.
- If the next implementation proves `render_surface_emitter.zig` is another false owner, stop the performance loop and reopen ownership correction before optimizing further.

## Explicit Ordered Slice Plan

1. `emitter-alpha-reuse-fast-path`
   - query atlas reuse before staging upload bytes for alpha sprites
   - keep all work inside emitter/resource-store owners
   - rerun direct host timing and clean Howl-vs-Alacritty receipts

2. `direct-normal-scan-reduction`
   - only after slice 1 is accepted
   - target candidate walk and append pressure in `direct_normal.zig`

3. `host-fill-tail-revisit`
   - only after slices 1 and 2
   - use fresh receipts to decide whether host fill playback still clears the bar for a host-side pass

## Exact Allowed Files For The Next Slice

Required owner files:

- `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/sprite_resource_store.zig`

Proof-only file if needed:

- `/home/home/personal/projects/howl/howl-render/src/benchmark_main.zig`

## Required Assertions

- Assert atlas-hit alpha sprites do not stage upload bytes.
- Assert atlas-hit and atlas-miss paths both preserve bounded counts and byte limits.
- Assert reused atlas regions keep stable resource identifiers.
- Assert atlas misses still stage and publish exactly once when required.

## Required Tests

- `cd /home/home/personal/projects/howl/howl-render && zig build test:unit`
- targeted owner tests covering atlas hit and atlas miss behavior in `sprite_resource_store.zig`
- if benchmark proof output changes:
  - `cd /home/home/personal/projects/howl/howl-render && zig build benchmark:render -- --runs 20`
- verification receipts:
  - `cd /home/home/personal/projects/howl/howl-linux-host && zig build install -Doptimize=ReleaseFast`
  - rerun direct host timing receipt on ASCII rain
  - rerun clean Howl vs Alacritty benchmark receipt

## Non-Goals

- no ownership refactor unless the slice reveals another false owner
- no `session/text.zig` changes
- no `ffi/*` changes
- no host GL work
- no publication background correctness work
- no PTY/runtime work
- no benchmark-tool changes
- no `direct_normal` work in the same slice

## Stop Conditions

- stop if the implementation needs files outside:
  - `prepared/render_surface_emitter.zig`
  - `prepared/sprite_resource_store.zig`
  - optional `benchmark_main.zig`
- stop if session or FFI ownership needs reopening
- stop if the slice reveals `render_surface_emitter.zig` is not the smallest true owner after all
- stop if clean benchmark or direct host receipts regress against the accepted post-owner baseline

## Risks

- `owner_create_avg_us` may still hide additional cost in glyph-run packing or publish fixup after upload staging is reduced.
- ASCII steady state may benefit more than mixed text workloads if the win is mostly atlas-hit reuse.

## Proof Gaps

- Current timing split does not yet isolate glyph-run packing and publish fixup as separate subowners.
- No post-fix receipt exists yet. This file is planning authority only.

## Readiness Judgment

Ready for the next performance slice.

- `prepared/owner.zig` is gone.
- no new false owner is proved in the current hottest seam
- the next slice boundary is exact
- the next fix removes measured false work instead of optimizing around stale structure
