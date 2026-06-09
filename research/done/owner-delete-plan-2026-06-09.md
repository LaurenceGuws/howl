# Post-Owner Performance Research

Date: 2026-06-09.
Role: researcher.
Status: active.
Loop: `loops/ascii-rain-baseline-bottleneck.txt`.
Primary researcher session id: `research-2026-06-09-post-owner-performance-01`.

## Sources Read In Order

1. `/home/home/personal/projects/howl/loop/flow.md`
2. `/home/home/personal/projects/howl/loop/researcher.md`
3. `/home/home/personal/projects/howl/sprints/current.txt`
4. `/home/home/personal/projects/howl/loops/ascii-rain-baseline-bottleneck.txt`
5. `/home/home/personal/projects/howl/research/owner-delete-plan-2026-06-09.md`
6. `/home/home/personal/projects/howl/reference-index.md`
7. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
8. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
9. Current receipts:
   - `/home/home/personal/projects/howl/artifacts/stress/20260609-115340-ascii/summary.json`
   - `/home/home/personal/projects/howl/artifacts/stress/20260609-095340-ascii-direct-post-owner/howl-direct.accounting.log`
   - `/home/home/personal/projects/howl/artifacts/stress/20260609-095743-ascii-direct-post-owner-timing/howl-term.stderr.log`
10. Current Howl source:
   - `/home/home/personal/projects/howl/howl-render/src/session/text.zig`
   - `/home/home/personal/projects/howl/howl-render/src/prepared/surface.zig`
   - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
   - `/home/home/personal/projects/howl/howl-render/src/prepared/sprite_resource_store.zig`
   - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
11. Alacritty references:
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs`

## Exact File And Line References

Howl:

- `TextSessionOwner.prepareHandle` still splits the live post-delete hot path into `prepareSurface` and `PreparedHandle.create`: `/home/home/personal/projects/howl/howl-render/src/session/text.zig:514-535`
- `PreparedSurface` is now a small data owner and no longer a broad policy seam: `/home/home/personal/projects/howl/howl-render/src/prepared/surface.zig:8-67`
- `direct_normal.prepare` timing split is explicit and local:
  - scan: `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig:124-139`
  - candidate walk: `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig:178-210`
  - renderable append and atlas reserve: `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig:261-306`
- `render_surface_emitter` owns bounded render-surface emission, not session policy:
  - bounded storage and limits: `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig:157-198`
  - emission entrypoints: `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig:210-259`
  - fill append and merge: `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig:316-404`
  - sprite emission and resource lookup: `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig:406-505`
  - upload staging: `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig:532-596`
  - glyph-run append and publish fixup: `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig:604-698`
- `SpriteResourceStore` is the cache owner for persistent resources and atlas placements:
  - direct resource reuse path: `/home/home/personal/projects/howl/howl-render/src/prepared/sprite_resource_store.zig:95-159`
  - alpha atlas reuse path: `/home/home/personal/projects/howl/howl-render/src/prepared/sprite_resource_store.zig:161-198`

Alacritty:

- content preparation filters renderable cells before renderer work: `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:153-183`
- display orchestrates clear, cell draw, line rects, and rect submission in separate steps: `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:783-1008`
- renderer text path asks glyph cache for a glyph and only then batches it: `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:135-170`
- Alacritty glyph cache returns immediately on cache hit instead of rebuilding upload bytes first: `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs:200-245`

## Current-Code Facts

- Post-delete clean benchmark moved Howl from `18.38 fps` to `79.42 fps`; Alacritty on the same rerun is `1039.12 fps`:
  - receipt: `/home/home/personal/projects/howl/artifacts/stress/20260609-115340-ascii/summary.json`
- Direct host post-delete run is `109.56 fps` and still saturates `howl-main`, not PTY:
  - receipt: `/home/home/personal/projects/howl/artifacts/stress/20260609-095340-ascii-direct-post-owner/howl-direct.accounting.log`
- The current post-delete timing split is:
  - `prepare_surface_avg_us ~= 735`
  - `owner_create_avg_us ~= 945`
  - `direct_normal_scan_avg_us ~= 664-671`
  - `emit_prepared sprites_avg_us ~= 265-273`
  - `stage_upload_avg_us ~= 87-90`
  - `atlas_resource_avg_us ~= 92-95`
  - receipt: `/home/home/personal/projects/howl/artifacts/stress/20260609-095743-ascii-direct-post-owner-timing/howl-term.stderr.log`
- `direct_normal` is now a clean owner seam. Its remaining cost is overwhelmingly candidate scan and append, not backgrounds, clears, decorations, or raster:
  - scan dominates at `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig:124-139`
  - append path is `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig:261-306`
- `render_surface_emitter` is also a clean seam after `owner.zig` deletion. It does one domain job: transform a `PreparedSurface` plus sprite-resource state into a bounded C render surface:
  - no submit policy
  - no session lifecycle
  - no FFI translation
  - no cross-domain compatibility wrapper
- However, the current alpha glyph path inside the emitter is still doing false steady-state work:
  - it stages upload bytes first in `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig:431-438`
  - then asks `SpriteResourceStore.atlasRegionFor(...)` whether the atlas entry already exists at `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig:441-448`
  - on atlas reuse, it rolls back `upload_bytes_count` only after the bytes were already copied: `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig:449-455`
- The alpha atlas cache owner confirms that reuse detection itself does not need upload bytes, only key/hash/dimensions:
  - `/home/home/personal/projects/howl/howl-render/src/prepared/sprite_resource_store.zig:161-198`
- That means the emitter is copying pixel bytes for many glyphs before learning that the atlas already has them. On a steady-state ASCII workload, that is unnecessary work on the hot path.

## Reference Facts

- Alacritty keeps content prep, display orchestration, and renderer submission separate rather than collapsing them into a bucket owner:
  - content prep: `display/content.rs`
  - orchestration: `display/mod.rs`
  - renderer batching: `renderer/text/mod.rs`
- Alacritty’s renderer path does not eagerly rebuild upload payloads for cached glyphs. It asks `glyph_cache.get(...)` first and returns immediately on cache hit:
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:155-170`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs:204-207`
- TigerBeetle pressure here is:
  - keep owners small and direct
  - centralize policy in the true parent
  - do not keep knowingly false work in the hot path once it is identified
  - prefer explicit bounds and local proof over cross-cutting bucket wrappers

## Owner Roles And Proposed Shape

### 1. Exact next owner-true slice recommendation

Next slice should target the alpha glyph steady-state fast path in:

- `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/sprite_resource_store.zig`

Reason:

- `owner_create_avg_us` is now the single largest post-delete owner.
- Inside it, the live code still stages sprite bytes before asking the atlas cache whether the glyph is already resident.
- That is false work on the steady-state ASCII path and it lives fully inside the render-surface emission/resource-cache seam.

Recommended fix shape:

1. Add an atlas-lookup-first path for alpha sprites in `SpriteResourceStore`.
2. In `render_surface_emitter.appendPreparedSprites`, query reuse before `stagePreparedUploadBytes`.
3. Stage and upload bytes only for atlas misses.
4. Leave session choreography, FFI, and host GL untouched.

This is the right next cut before `direct_normal` scan work, because it removes measured false work from the hottest current owner without reopening another broad ownership correction.

### 2. Whether `render_surface_emitter.zig` is owner-true

`render_surface_emitter.zig` is owner-true enough to optimize directly.

Why it is not another `owner.zig`:

- It owns one domain object: bounded render-surface emission state.
- Its storage, bounds, append rules, and publish fixups are all about the render-surface payload itself.
- It does not own submit policy, session lifecycle, FFI translation, or benchmark orchestration.

What it is allowed to own:

- command arrays
- upload arrays and byte staging
- fill merge rules
- glyph-run packing
- damage/create/upload/retire publication

What it should not absorb:

- session policy from `session/text.zig`
- font selection or renderable-cell classification from `text/direct_normal.zig`
- host realization policy

So the emitter is not the next bucket deletion target. It is the next real performance owner.

## Sprint Scratchpad

- Broad goal is unchanged: beat Alacritty on the ASCII-rain benchmark.
- `prepared/owner.zig` deletion is accepted and materially improved the hot path.
- Post-delete hot order is now:
  1. `PreparedHandle.create` / render-surface emission
  2. `direct_normal` scan
  3. host upload/playback tail
- Immediate false-work opportunity is alpha glyph atlas reuse doing byte staging before reuse detection.
- Publication background correctness remains a separate correctness track, not authorized in this performance slice.

## Explicit Ordered Slice Plan

1. `emitter-alpha-reuse-fast-path`
   - eliminate eager upload-byte staging on atlas hits
   - keep work inside emitter/resource-cache owners
   - remeasure direct host timing and clean benchmark

2. `direct-normal-scan-reduction`
   - only after slice 1 is accepted
   - target candidate walk / append path in `direct_normal.zig`
   - no emitter redesign in that slice

3. `host-fill-tail-revisit`
   - only after slices 1 and 2
   - use refreshed receipts to decide whether host fill playback still clears the bar for a host-side pass

## Exact Allowed Files For The Next Slice

Required owner files:

- `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/sprite_resource_store.zig`

Proof-only file if needed:

- `/home/home/personal/projects/howl/howl-render/src/benchmark_main.zig`

No other files should be in the slice unless reviewer-corrected planning explicitly expands it.

## Required Assertions

- Assert the alpha atlas fast path does not stage or retain upload bytes on atlas hits.
- Assert atlas-hit and atlas-miss paths both preserve bounded counts and byte limits.
- Assert the atlas resource id is stable on reuse.
- Assert miss path still creates/uploads exactly when needed.

## Required Tests

- `cd /home/home/personal/projects/howl/howl-render && zig build test:unit`
- targeted owner tests for `sprite_resource_store.zig`:
  - atlas hit returns reuse without upload requirement
  - atlas miss still allocates/upload-marks correctly
- if proof output changes are added:
  - `cd /home/home/personal/projects/howl/howl-render && zig build benchmark:render -- --runs 20`
- full verification receipts:
  - `cd /home/home/personal/projects/howl/howl-linux-host && zig build install -Doptimize=ReleaseFast`
  - rerun direct host timing receipt on ASCII rain
  - rerun clean Howl vs Alacritty benchmark receipt

## Non-Goals

- no new ownership refactor unless the slice itself reveals another real bucket seam
- no session/text choreography changes
- no `ffi/*` changes
- no host GL work
- no publication background correctness work
- no PTY/runtime work
- no benchmark-tool changes
- no attempt to optimize `direct_normal` in the same slice

## Stop Conditions

- stop if the best implementation path needs files outside:
  - `prepared/render_surface_emitter.zig`
  - `prepared/sprite_resource_store.zig`
  - optional `benchmark_main.zig`
- stop if proving the fast path requires reopening session or FFI ownership
- stop if the slice reveals `render_surface_emitter.zig` is not actually the smallest true owner after all
- stop if clean benchmark or direct host receipts regress against the accepted post-delete baseline

## Risks

- The measured `owner_create_avg_us` remainder is not entirely isolated yet; a portion may still live in glyph-run packing or publish fixup even after upload staging is reduced.
- ASCII steady state may benefit more than mixed text workloads if the win is mostly atlas-hit reuse.
- If the slice broadens into command-shape redesign, it will mix two owners and should be rejected.

## Proof Gaps

- Current timing split proves `stage_upload` and `atlas_resource` are meaningful, but it does not isolate `appendGlyphRef` and `publishSurface` as separate subowners yet.
- I have not produced a fresh host-side receipt after a hypothetical atlas-hit fast path because this is research only.

## Readiness Judgment

Ready for the next performance slice.

- `prepared/owner.zig` is gone.
- `render_surface_emitter.zig` is not another false bucket seam.
- The next measured false work is source-backed and owner-true.
- The slice boundary is exact and small enough to review harshly without optimizing lies.
