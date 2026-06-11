Owner create bottleneck plan

Historical authority at the time: active researcher plan for the first `owner_create` bottleneck slice after the direct-normal publication scan fix landed.
Why superseded or done: the `owner-create-cache-first-emission` slice landed, was remeasured, and the sprint restarted from the new post-cache-first `owner_create` proof.
Must not be used for: current active planning after the `20260612-005338-ascii` rerun.

Date: 2026-06-12.
Status: archived reviewer-accepted planning package.
Role owner: researcher.
Orchestrator session id: `orch-2026-06-11-ascii-rain-honest-performance-02`.
Researcher session id: `research-2026-06-12-owner-create-plan-01`.
Reviewer session id: `review-2026-06-12-owner-create-plan-01`.
Planning commit-hash receipt: pending until archival.

Preload receipt:

- Role: researcher
- Active sprint:
  - `/home/home/personal/projects/howl/sprints/2026-06-11-ascii-rain-honest-performance-sprint.md`
- Active loop:
  - `/home/home/personal/projects/howl/loops/ascii-rain-live-loop.txt`
- Active research:
  - `/home/home/personal/projects/howl/research/2026-06-12-owner-create-bottleneck-plan.md`
- Current evidence receipts:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-002652-ascii/summary.json`
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-002709-ascii/summary.json`
  - `/tmp/opencode/howl-render-debug-control.log`
- Execution authorized:
  - no implementation is authorized from this research pass

Problem statement

- The direct-normal bottleneck slice landed and improved Howl materially, but the 10-second rerun still trails Alacritty.
- The fresh timing proof now shows `owner_create` above `direct_normal_scan` on the current tree.
- The next step is to turn that new owner ranking into a reviewer-accepted worker slice that attacks the true owner seam in pristine shape without drifting into host-side distractions or stale direct-normal assumptions.

Sources read in order

1. `/home/home/personal/projects/howl/loop/flow.md`
2. `/home/home/personal/projects/howl/loop/orcestrator.md`
3. `/home/home/personal/projects/howl/loop/researcher.md`
4. `/home/home/personal/projects/howl/loop/reviewer.md`
5. `/home/home/personal/projects/howl/loop/coder.md`
6. `/home/home/personal/projects/howl/sprints/current.txt`
7. `/home/home/personal/projects/howl/loops/ascii-rain-live-loop.txt`
8. `/home/home/personal/projects/howl/research/2026-06-12-owner-create-bottleneck-plan.md`
9. `/home/home/personal/projects/howl/reference-index.md`
10. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
11. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
12. `/home/home/personal/projects/howl/utils/tools/rain-bench/README.md`
13. `/home/home/personal/projects/howl/utils/tools/rain-bench/benchmark_terminals.py`
14. `/home/home/personal/projects/howl/utils/tools/rain-bench/ascii_rain_stress.zig`
15. `/home/home/personal/projects/howl/utils/tools/rain-bench/build.zig`
16. `/home/home/personal/projects/howl/howl-linux-host/build.zig`
17. `/home/home/personal/projects/howl/howl-linux-host/src/main.zig`
18. `/home/home/personal/projects/howl/howl-linux-host/src/cli/args.zig`
19. `/home/home/personal/projects/howl/howl-linux-host/src/app/processor.zig`
20. `/home/home/personal/projects/howl/howl-render/src/session/text.zig`
21. `/home/home/personal/projects/howl/howl-render/src/prepared/handle.zig`
22. `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
23. `/home/home/personal/projects/howl/howl-render/src/prepared/surface.zig`
24. `/home/home/personal/projects/howl/howl-render/src/prepared/submit.zig`
25. `/home/home/personal/projects/howl/howl-render/src/prepared/submit_result.zig`
26. `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
27. `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
28. `/home/home/personal/projects/howl/howl-render/src/prepared/sprite_resource_store.zig`
29. `/home/home/personal/projects/howl/howl-render/src/prepared/owner_test.zig`
30. `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter_test.zig`
31. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs`
32. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/atlas.rs`

Exact files and line references

- Proof receipts:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-002652-ascii/summary.json:45-83`
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-002709-ascii/summary.json:45-121`
  - `/tmp/opencode/howl-render-debug-control.log:1-15`
- Benchmark harness authority:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/README.md:20-31`
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/README.md:53-79`
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/build.zig:19-28`
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/benchmark_terminals.py:23-29`
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/benchmark_terminals.py:43-62`
- Current owner seam:
  - `/home/home/personal/projects/howl/howl-render/src/session/text.zig:514-535`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/handle.zig:72-96`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/handle.zig:184-195`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig:328-360`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig:508-615`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig:683-705`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig:760-815`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig:873-899`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/sprite_resource_store.zig:95-159`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/sprite_resource_store.zig:161-198`
- Existing proof roots and invariants:
  - `/home/home/personal/projects/howl/howl-render/src/prepared/owner_test.zig:15-60`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/owner_test.zig:126-250`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter_test.zig:865-911`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter_test.zig:1003-1067`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/sprite_resource_store.zig:296-371`
- Reference anchors:
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs:17-26`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs:200-245`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs:271-317`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/atlas.rs:118-140`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/atlas.rs:247-295`
  - `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:96-113`
  - `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:136-149`
  - `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:249-264`

Current-code facts

- The accepted 3-second rerun improved Howl to `32.31 fps`, and the accepted 10-second rerun improved Howl to `33.85 fps`, but Alacritty still runs at `1012.33 fps` on the same 10-second harness (`summary.json:45-121`).
- The current timing log at count `640` records `owner_create_avg_us=1151` and `prepared_handle_create emit_avg_us=1149`, while allocator and registration stay effectively zero (`/tmp/opencode/howl-render-debug-control.log:13-15`). The bottleneck bucket is therefore not handle allocation or registry mutation.
- `TextSessionOwner.prepareHandle` measures `owner_create` exactly around `PreparedHandle.create(self, &prepared)` after `prepareSurface` completed (`session/text.zig:514-535`).
- `PreparedHandle.create` does four things in order: allocate the handle, move the prepared surface into it, register it with the owner, then emit the render-surface payload immediately (`prepared/handle.zig:72-96`).
- The heavy substep inside `PreparedHandle.create` is `emitRenderSurfacePayload`, which allocates an emitter payload and calls `emitPreparedFresh` (`prepared/handle.zig:184-195`).
- `emitPreparedFresh` rebuilds the render surface from the prepared text scene every prepare and records its own timing buckets (`render_surface_emitter.zig:328-360`).
- In the accepted proof log, `emit_prepared` reports `sprites_avg_us=441`, `stage_upload_avg_us=100`, `atlas_resource_avg_us=105`, `sprite_lookup_avg_us=68`, and `alpha_sprites_avg=1699` at count `640` (`/tmp/opencode/howl-render-debug-control.log:13`). The dominant work inside the emitter is sprite-path work, and the workload is almost entirely alpha glyph sprites.
- `appendPreparedSprites` currently stages upload bytes before asking the sprite resource store whether the sprite is already reusable. The order is: `lookupPreparedSprite` -> `stagePreparedUploadBytes` -> `atlasRegionFor` or `resourceFor` -> maybe roll back the staged bytes on reuse (`render_surface_emitter.zig:508-615`, `render_surface_emitter.zig:683-705`).
- That means repeated alpha glyph draws still pay byte-copy cost even when the atlas entry already exists, since `atlasRegionFor` only returns `uploaded = false` after the copy already happened (`render_surface_emitter.zig:543-559`, `sprite_resource_store.zig:161-198`).
- The color path has the same owner-shape pressure: `resourceFor` needs staged bytes to prove equality, so the emitter must copy bytes before it can learn that the resource is reused (`render_surface_emitter.zig:571-593`, `sprite_resource_store.zig:95-159`).
- `lookupPreparedSprite` first scans `prepared.text_frame.raster_plan.outputs`, then falls back to `session.atlasRaster(sprite_key)` (`render_surface_emitter.zig:873-899`). On this workload the direct-normal raster bucket is already small (`34 us` at count `640`), so most sprites are likely coming from retained atlas state, making wasted restaging especially suspect.
- The current shape already has correctness proof roots for failure reporting, resource persistence, reuse, overflow preservation, and transient retirement in `owner_test.zig`, `render_surface_emitter_test.zig`, and `sprite_resource_store.zig` (`owner_test.zig:15-250`, `render_surface_emitter_test.zig:865-1067`, `sprite_resource_store.zig:296-371`).

Reference facts

- Alacritty keeps glyph admission and atlas upload behind explicit renderer owners: `GlyphCache::get` checks the cache first and only loads a glyph through the loader on a miss (`glyph_cache.rs:200-245`).
- Alacritty resets and preloads cache state through explicit cache owners instead of making every draw path restage texture data (`glyph_cache.rs:271-317`).
- Alacritty's atlas owner inserts rasterized glyphs only when needed and reuses existing atlas state otherwise (`atlas.rs:118-140`, `atlas.rs:247-295`).
- TigerBeetle pressure applies directly here: put a limit on everything and keep owner state explicit (`TIGER_STYLE.md:96-113`), assert both positive and negative space (`TIGER_STYLE.md:136-149`), and make the hot loop explicit enough that redundant work is obvious (`TIGER_STYLE.md:249-264`).
- These references support a cache-first owner seam. They do not support host-side, GL-side, or benchmark-wrapper redesign as the next truthful step.

Compact anchor map

- Stable references:
  - Alacritty `glyph_cache.rs`: cache admission before raster upload.
  - Alacritty `atlas.rs`: atlas insert only on miss; reuse otherwise.
  - TigerBeetle `TIGER_STYLE.md`: explicit owner, bounded work, paired assertions, hot-loop directness.
- Current Howl owner seam:
  - `TextSessionOwner.prepareHandle` owns the outer prepare-to-handle step.
  - `PreparedHandle.create` is only a thin owner wrapper around immediate render-surface emission.
  - `render_surface_emitter.appendPreparedSprites` is the hot owner function inside `owner_create`.
  - `sprite_resource_store` is the cache owner, but its current API shape forces the emitter to restage bytes before the cache can decide reuse.
- Decision anchor:
  - The next slice must attack `render_surface_emitter` plus `sprite_resource_store` together.
  - It must not reopen `direct_normal`, host runtime, or the benchmark wrapper.

Exact proof receipts being relied on

- `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-002652-ascii/summary.json`
  - Howl-only 3-second rerun after the accepted direct-normal slice: `32.31 fps`.
- `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-002709-ascii/summary.json`
  - 10-second rerun: Howl `33.85 fps`, Alacritty `1012.33 fps`.
- `/tmp/opencode/howl-render-debug-control.log`
  - Accepted timing proof showing `owner_create_avg_us=1151` and `prepared_handle_create emit_avg_us=1149` at count `640`.
  - Accepted sub-buckets showing sprite-path work dominates emitter time.
- Accepted live-loop receipt in `/home/home/personal/projects/howl/loops/ascii-rain-live-loop.txt:234-260`.

Owner roles and proposed shape

- `session/text.zig` owns the outer prepare transaction and timing receipt only.
- `prepared/handle.zig` owns handle lifecycle and failure mapping only.
- `prepared/render_surface_emitter.zig` is the true hot owner for the new bottleneck. It owns converting prepared scene draws into bounded render-surface creates, uploads, commands, retires, and published spans.
- `prepared/sprite_resource_store.zig` owns sprite and atlas reuse decisions.
- Proposed shape:
  - Move reuse admission ahead of upload-byte staging.
  - The cache owner must be able to decide `reused` vs `needs upload` from owner-true sprite identity and source-byte equality without first forcing the emitter to copy bytes into `upload_bytes` scratch.
  - The emitter should stage bytes only for `uploaded` alpha atlas inserts and `persistent|transient` color resource allocations.
  - Keep payload publication and ABI surface unchanged.

Sprint scratchpad

- The current honest bottleneck is still inside render preparation, not host runtime.
- The accepted direct-normal slice already stopped correctly when `owner_create` overtook `direct_normal_scan`.
- The next slice should sharpen owner truth before chasing any broader optimization.
- The cache-first seam is the smallest slice that matches both current proof and reference pressure.

Explicit ordered worker slice plan

1. Slice: `owner-create-cache-first-emission`
   - Purpose:
     - remove repeated upload-byte staging from the hot prepared-surface emission path when the sprite/atlas cache already proves reuse
   - Why this slice first:
     - current proof places the bottleneck inside `PreparedHandle.create`
     - current source shows the true hot owner is `render_surface_emitter.appendPreparedSprites`
     - current emitter/store API shape forces redundant byte copies before reuse admission
   - Receipt fields required from the worker:
     - coder session id
     - files changed
     - exact tests run
     - exact updated receipt paths
     - quoted timing lines from `/tmp/opencode/howl-render-debug-control.log`
     - exact before/after `owner_create_avg_us`, `prepared_handle_create emit_avg_us`, `stage_upload_avg_us`, and `sprites_avg_us`
     - commit-hash handoff status: pending orchestrator receipt closure

2. No second slice is authorized yet.
   - Re-rank the bottleneck after the first slice.
   - If `owner_create` remains on top, planning restarts from the new proof.

Exact allowed files

- `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/sprite_resource_store.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter_test.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/owner_test.zig`

- Stop and escalate instead of widening into any other file unless the current owner tests prove the seam is impossible to fix honestly inside these files.

Exact required shape

- Preserve `TextSessionOwner.prepareHandle` and `PreparedHandle.create` public behavior.
- Preserve `PreparedSurface` and render-surface ABI consequences.
- Add or refactor owner-true cache admission in `sprite_resource_store.zig` so the emitter can ask whether a sprite/atlas upload is needed before copying bytes into `Emitter.upload_bytes` scratch.
- Keep byte staging owned by `render_surface_emitter.zig`; do not move upload-buffer ownership into the store.
- Preserve persistent resource reuse, atlas reuse, transient resource behavior, overflow behavior, and failure mapping.
- Do not add a bucket struct, manager, controller, helper runtime, or host-side cache layer.
- Do not add lazy publication or deferred host realization just to dodge the current owner seam.

Exact tests

- `/home/home/personal/projects/howl/howl-render`: `zig build test:unit`
- `/home/home/personal/projects/howl/howl-linux-host`: `zig build install -Doptimize=ReleaseFast`
- `/home/home/personal/projects/howl/utils/tools/rain-bench`: `zig build --release=fast stress:rain:build`
- `/home/home/personal/projects/howl`: `env HOWL_RENDER_DEBUG_TIMING=1 python3 utils/tools/rain-bench/benchmark_terminals.py --duration 3 --mode ascii --terminals howl 2> /tmp/opencode/howl-render-debug-control.log`
- `/home/home/personal/projects/howl`: `python3 utils/tools/rain-bench/benchmark_terminals.py --duration 10 --mode ascii --terminals howl alacritty`
- Required existing proof roots to keep green:
  - `render surface surface emitter persists prepared sprite resource across surfaces` in `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter_test.zig:865-911`
  - `render surface surface emitter failure preserves accepted persistent resource state` in `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter_test.zig:1003-1019`
  - `render-surface sprite resource store reuses last atlas and resource lookups` in `/home/home/personal/projects/howl/howl-render/src/prepared/sprite_resource_store.zig:333-371`
  - `create reports missing-sprite diagnostic without double free` in `/home/home/personal/projects/howl/howl-render/src/prepared/owner_test.zig:15-60`
- Required new owner-local tests:
  - add one new test in `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter_test.zig` proving a reused alpha atlas sprite emits zero uploads and leaves `upload_bytes_count` unchanged on the second emission
  - add one new test in `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter_test.zig` proving a reused persistent color sprite emits zero uploads and leaves `upload_bytes_count` unchanged on the second emission
  - add one new test in `/home/home/personal/projects/howl/howl-render/src/prepared/sprite_resource_store.zig` proving cache admission can report reuse before emitter-side byte staging for both atlas and color sprite paths

Exact non-goals

- no `direct_normal` edits
- no host GL, SDL, PTY, VT, or event-loop edits
- no benchmark-wrapper redesign
- no ABI changes
- no broad atlas redesign beyond the emitter/store owner seam
- no lazy publication redesign in `PreparedHandle`

Exact stop conditions

- stop if truthful cache-first admission requires widening beyond the four allowed files
- stop if current tests expose a correctness bug in sprite/resource identity rather than a pure performance debt
- stop if the worker cannot preserve existing failure mapping and persistent/transient semantics
- stop if the 3-second timing rerun does not lower `owner_create_avg_us` below the current accepted baseline `1151`
- stop if the benchmark rerun changes semantics or breaks existing proof roots even when `owner_create_avg_us` improves

Required assertions

- Assert in `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig` that the cache admission result and upload decision agree:
  - reused entries must not consume staged upload bytes
  - uploaded entries must consume staged upload bytes exactly once
- Assert any byte-range rollback returns `upload_bytes_count` to the exact prior start when an upload is not needed.
- Assert persistent resource entries and atlas entries stay within existing bounds.
- Assert command, upload, and retire consequences remain bounded and published exactly as before.
- Preserve or strengthen the existing overflow and allocation-failure proofs in `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter_test.zig` and `/home/home/personal/projects/howl/howl-render/src/prepared/owner_test.zig` instead of weakening them.

Risks

- The main risk is introducing cache-admission API churn that duplicates sprite identity rules in two places.
- A second risk is preserving transient resource semantics while changing when bytes are staged.
- A third risk is mistaking noisy benchmark movement for proof; owner-local tests must carry the reuse contract.

Proof gaps

- The current built-in timing seam proves the hot owner and shows sprite-path sub-buckets, but it does not split every remaining micro-cost inside `appendPreparedSprites`.
- The log does not fully explain why `prepared_handle_create emit_avg_us` is much larger than the visible `emit_prepared` sub-bucket sum. That is a measurement gap, not a blocker for the next slice, because both measurements still point at the same emitter owner.
- I did not find current-source proof that the next truthful step requires host-side or direct-normal work again.

Readiness judgment

- Ready.
- The next worker slice is reviewer-seedable now.
- The truthful owner seam is `prepared/render_surface_emitter.zig` plus `prepared/sprite_resource_store.zig`, centered on cache-first reuse admission before upload-byte staging.
