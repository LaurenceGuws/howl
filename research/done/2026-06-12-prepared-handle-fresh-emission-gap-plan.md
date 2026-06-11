Prepared handle fresh emission gap plan

Date: 2026-06-12.
Status: active researcher target.
Role owner: researcher.
Orchestrator session id: `orch-2026-06-11-ascii-rain-honest-performance-02`.
Researcher session id: `research-2026-06-12-prepared-handle-fresh-emission-gap-01`.
Reviewer session id: pending.
Planning commit-hash receipt: pending.

Preload receipt:

- Role: researcher
- Active sprint:
  - `/home/home/personal/projects/howl/sprints/2026-06-11-ascii-rain-honest-performance-sprint.md`
- Active loop:
  - `/home/home/personal/projects/howl/loops/ascii-rain-live-loop.txt`
- Active research:
  - `/home/home/personal/projects/howl/research/2026-06-12-prepared-handle-fresh-emission-gap-plan.md`
- Current proof receipts:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-011550-ascii/summary.json`
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-011602-ascii/summary.json`
  - `/tmp/opencode/howl-render-debug-control.log`
- Execution authorized:
  - research and planning only; no implementation from this pass

Problem statement:

- The accepted fresh rollback slice landed in `howl-render` commit `8bd867b` and root commit `36efd55`.
- Howl improved to `36.85 fps`, but Alacritty remains `1009.95 fps` on the same 10-second ASCII-rain telemetry.
- The post-fresh bottleneck proof still ranks `owner_create` first: `owner_create_avg_us=1053`, `prepared_handle_create emit_avg_us=1052`, and `direct_normal_avg_us=952`.
- The visible `emit_prepared` sub-buckets do not fully explain `prepared_handle_create emit_avg_us=1052`; the next research task is to source-pin that fresh emission gap and produce one reviewer-acceptable worker slice.

Required current evidence:

- `howl-render-debug prepared_handle_create count=640 alloc_avg_us=0 alloc_max_us=4 register_avg_us=0 register_max_us=1 emit_avg_us=1052 emit_max_us=4286`
- `howl-render-debug prepare_handle count=640 prepare_surface_avg_us=954 prepare_surface_max_us=16968 input_avg_us=0 session_preparer_avg_us=0 session_prepare_cells_avg_us=0 direct_normal_avg_us=952 direct_normal_scan_avg_us=842 direct_normal_backgrounds_avg_us=30 direct_normal_clears_avg_us=0 direct_normal_decorations_avg_us=46 direct_normal_cursor_avg_us=0 direct_normal_raster_avg_us=31 owner_create_avg_us=1053 owner_create_max_us=4288`

Initial owner focus:

- `/home/home/personal/projects/howl/howl-render/src/session/text.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/handle.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/sprite_resource_store.zig`
- adjacent prepared-surface publication and tests only if the source proves they own the gap

Research requirements:

- Read the live workflow, active loop, current sprint index, this file, TigerBeetle readings, and source/reference anchors before writing a plan.
- Explain the current gap with exact source line references and receipts.
- Do not reopen spent direct-normal, cache-first staging, or fresh rollback work unless fresh proof re-ranks it.
- Do not drift into host-side, GL, benchmark-wrapper, PTY, VT, ABI, or umbrella runtime work.
- Stop and report if the truthful next step exposes a big correctness issue or vague bucket.

Readiness judgment:

- Ready for reviewer gating as a bottleneck-proof worker slice, not an optimization slice.

Research package:

- Researcher session id:
  - `research-2026-06-12-prepared-handle-fresh-emission-gap-01`
- Planning scope:
  - research and planning only
  - no implementation from this researcher pass
  - next worker slice must source-pin the residual fresh-emission wall time before any product optimization is authorized

Sources read in required order:

- `/home/home/personal/projects/howl/loop/flow.md`
- `/home/home/personal/projects/howl/loop/orcestrator.md`
- `/home/home/personal/projects/howl/loop/researcher.md`
- `/home/home/personal/projects/howl/loop/reviewer.md`
- `/home/home/personal/projects/howl/loop/coder.md`
- `/home/home/personal/projects/howl/sprints/current.txt`
- `/home/home/personal/projects/howl/loops/ascii-rain-live-loop.txt`
- `/home/home/personal/projects/howl/research/2026-06-12-prepared-handle-fresh-emission-gap-plan.md`
- `/home/home/personal/projects/howl/reference-index.md`
- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `/home/home/personal/projects/howl/howl-render/src/session/text.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/handle.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/sprite_resource_store.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter_test.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/owner_test.zig`
- `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-011550-ascii/summary.json`
- `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-011602-ascii/summary.json`
- `/tmp/opencode/howl-render-debug-control.log`

Compact anchor map:

- Workflow/accountability anchors:
  - `loop/flow.md:22-41` requires exact allowed files, shape, tests, non-goals, stop conditions, session ids, and receipt status before planning is complete.
  - `loop/flow.md:98-120` requires active `loops/`, `research/`, and `sprints/` hygiene and a live loop note for each non-trivial pass.
  - `loop/researcher.md:60-75` requires source reads, line references, current-code facts, reference facts, owner roles, slice plan, assertions, tests, risks, proof gaps, and readiness judgment.
- Reference anchors:
  - `reference-index.md:19-25` gives Alacritty/Ghostty/TigerBeetle/source-order weight; this slice is not host/runtime/VT, so Alacritty and Ghostty do not authorize host drift here.
  - `reference-index.md:215-235` makes TigerBeetle the governing reference for bounds, assertions, directness, and tests.
  - `TIGER_STYLE.md:96-100` requires fixed bounds on loops and queues.
  - `TIGER_STYLE.md:104-140` requires assertions for function contracts, invariants, positive space, and negative space.
  - `TIGER_STYLE.md:151-156` rejects post-initialization allocation as a performance and safety hazard; current source still allocates a prepared handle payload inside `owner_create`, but the accepted timing shows payload allocation is not yet proven as the residual owner.
  - `TIGER_STYLE.md:231-257` requires performance work to be source-shaped and mechanically sympathetic, not guessed.
  - `TIGER_STYLE.md:416-424` requires checks close to use and rejects distant place-of-check/place-of-use gaps.
  - `ARCHITECTURE.md:408-423` backs separating control-plane proof from data-plane work; the next slice must measure the data-plane residual before changing it.
- Current owner seams:
  - `session/text.zig:514-535` owns the session-level `prepareHandle` timing and records `owner_create` around `PreparedHandle.create`.
  - `handle.zig:72-95` owns `PreparedHandle.create`; its `emit_avg_us` bucket measures `emitRenderSurfacePayload` after handle allocation and registration.
  - `handle.zig:184-195` allocates `RenderSurfacePayload`, calls `emitPreparedFresh`, and stores the payload pointer.
  - `render_surface_emitter.zig:328-361` owns fresh prepared emission and records emitter sub-buckets.
  - `render_surface_emitter.zig:508-639` owns sprite publication emission, including prepared sprite lookup, atlas/resource admission, upload staging, glyph append, draw command append, and transient retire.
  - `render_surface_emitter.zig:789-843` owns publication fixups and host-facing span publication.
  - `sprite_resource_store.zig:108-156` owns fresh-path resource admission rollback.
  - `sprite_resource_store.zig:331-369` owns alpha atlas admission and remains the largest visible emitter sub-bucket in the current receipt.
  - `owner_test.zig:156-199` already proves fresh prepared handles reuse alpha atlas and persistent color resources without second-create uploads.
  - `render_surface_emitter_test.zig:1071-1129` already proves fresh emission failure restores retained resource admission state.

Current proof receipts:

- 3-second Howl-only timing receipt:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-011550-ascii/summary.json:32-44` records `duration_s=3.0`, `mode=ascii`, `cols=320`, `rows=120`, `flush_every=1`.
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-011550-ascii/summary.json:70-80` records final Howl `fps=35.99`, `p50_us=24984`, `p95_us=45782`, `p99_us=62889`, `max_us=93385`.
- 10-second Howl vs Alacritty receipt:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-011602-ascii/summary.json:32-44` records `duration_s=10.0`, `mode=ascii`, `cols=320`, `rows=120`, `flush_every=1`.
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-011602-ascii/summary.json:70-80` records final Howl `fps=36.85`, `p50_us=24359`, `p95_us=44488`, `p99_us=76938`, `max_us=95984`.
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-011602-ascii/summary.json:108-118` records final Alacritty `fps=1009.95`, `p50_us=963`, `p95_us=1269`, `p99_us=1431`, `max_us=2458`.
- Timing log:
  - `/tmp/opencode/howl-render-debug-control.log:13` records `emit_prepared count=640 copy_in_avg_us=0 fills_avg_us=16 sprites_avg_us=336 publish_avg_us=1 copy_out_avg_us=0 sprites_avg=1607 alpha_sprites_avg=1607`.
  - `/tmp/opencode/howl-render-debug-control.log:14` records `prepared_handle_create count=640 alloc_avg_us=0 register_avg_us=0 emit_avg_us=1052`.
  - `/tmp/opencode/howl-render-debug-control.log:15` records `prepare_handle count=640 prepare_surface_avg_us=954 direct_normal_avg_us=952 owner_create_avg_us=1053`.

Current-code facts:

- `TextSessionOwner.prepareHandle` measures `owner_create` only around `PreparedHandle.create`, not around text preparation: `session/text.zig:520-535`.
- `PreparedHandle.create` measures `alloc`, `register`, and `emit`; `alloc_avg_us=0` and `register_avg_us=0` in the receipt leave `emitRenderSurfacePayload` as the only proven hot child of `owner_create`: `handle.zig:72-95`, `/tmp/opencode/howl-render-debug-control.log:14`.
- `emitRenderSurfacePayload` allocates `RenderSurfacePayload`, initializes it, calls `emitPreparedFresh`, and assigns `render_surface_payload`: `handle.zig:184-195`. The current timing does not split this payload allocation/initialization from fresh emission.
- `emitPreparedFresh` now mutates retained resources directly behind admission rollback, with `copy_in_ns=0` and `copy_out_ns=0`: `render_surface_emitter.zig:328-331`, `render_surface_emitter.zig:356-361`.
- `emitPreparedFresh` times fill passes, sprite pass, cursor pass, publish, and then records those totals: `render_surface_emitter.zig:333-360`.
- The visible emitter sub-buckets at count 640 sum to roughly `353us` (`fills=16`, `sprites=336`, `publish=1`, `copy_in=0`, `copy_out=0`) while the enclosing `prepared_handle_create emit_avg_us` is `1052us`: `/tmp/opencode/howl-render-debug-control.log:13-14`.
- The `699us` residual is real enough to block optimization planning, but not source-pinned enough to optimize. It may include payload allocation/initialization, `resetPrepared`, unbucketed fresh-emission control flow, debug record/print overhead, or other work hidden between current sub-bucket timers.
- The current `emit_prepared` timing line is emitted from `DebugEmitPreparedTiming.record`, which is called inside `emitPreparedFresh` after `publishSurface`: `render_surface_emitter.zig:110-184`, `render_surface_emitter.zig:358-360`. Any time spent in `record` itself is inside the enclosing `emit_avg_us` but outside the visible emitter sub-buckets.
- `appendPreparedSprites` is the largest visible emitter bucket and currently handles about `1607` sprites per prepared surface, all alpha sprites in this receipt: `/tmp/opencode/howl-render-debug-control.log:13`, `render_surface_emitter.zig:508-639`.
- The sprite visible sub-buckets at count 640 are `sprite_lookup_avg_us=54`, `atlas_resource_avg_us=154`, `alpha_glyph_append_avg_us=31`, `stage_upload_avg_us=0`, leaving about `97us` inside the sprite pass for bounds/destination/loop/control and timer overhead: `/tmp/opencode/howl-render-debug-control.log:13`, `render_surface_emitter.zig:508-579`.
- `sprite_resource_store.atlasAdmissionForPrepared` still hashes prepared sprite bytes and searches atlas entries for every alpha draw before reuse can be returned: `sprite_resource_store.zig:331-369`, `sprite_resource_store.zig:470-490`. This is a plausible visible sub-bucket optimization later, but it is not enough to explain the current `699us` residual.
- The fresh rollback correctness contract is already owner-local and must not be weakened: `sprite_resource_store.zig:108-156`, `render_surface_emitter_test.zig:1071-1129`.

Gap conclusion:

- The next true bottleneck is not yet an optimizer-owned code shape. It is a measurement gap inside the post-fresh `owner_create` path.
- The only honest next worker slice is temporary owner-local bottleneck proof that splits `PreparedHandle.emitRenderSurfacePayload` and `Emitter.emitPreparedFresh` wall time into enough buckets to identify the residual owner.
- A worker slice that jumps directly to `atlasAdmissionForPrepared`, glyph append batching, host GL, benchmark wrapper changes, ABI changes, direct-normal work, or payload allocation removal would be under-proved against the accepted receipts.

Owner roles and proposed shape:

- `TextSessionOwner` remains the session owner and should not be changed in the next slice except by rerunning existing timing. It already ranks `owner_create`: `session/text.zig:514-535`.
- `PreparedHandle` owns handle lifecycle and payload allocation. It may receive temporary debug timing around `allocator.create(RenderSurfacePayload)`, payload initialization, `emitPreparedFresh`, and payload assignment because that work is inside the measured `prepared_handle_create emit_avg_us`: `handle.zig:184-195`.
- `render_surface_emitter` owns fresh emission. It may receive temporary debug timing only around already-existing owner steps inside `emitPreparedFresh` and `appendPreparedSprites`: `render_surface_emitter.zig:328-361`, `render_surface_emitter.zig:508-639`.
- `sprite_resource_store` owns resource admission. It should not be edited in the next proof slice unless the worker proves that existing emitter-level timing cannot separate store admission from other residual work. The initial allowed proof does not need it because `atlas_resource_avg_us` and `direct_resource_avg_us` already exist: `render_surface_emitter.zig:538-545`, `render_surface_emitter.zig:581-588`.

Proposed next worker slice: `prepared-handle-fresh-emission-residual-proof`

- Worker session id:
  - pending orchestrator seed
- Purpose:
  - add temporary owner-local timing only to source-pin the residual gap between `prepared_handle_create emit_avg_us` and the visible `emit_prepared` sub-buckets
  - produce a fresh receipt that names the next optimization owner, or stops if the residual is debug-timing overhead or a vague bucket
- Allowed files:
  - `/home/home/personal/projects/howl/howl-render/src/prepared/handle.zig`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
- Not allowed:
  - `/home/home/personal/projects/howl/howl-render/src/session/text.zig`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/sprite_resource_store.zig`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter_test.zig`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/owner_test.zig`
  - any host, GL, PTY, VT, ABI, benchmark wrapper, direct-normal, build, or CI file

Exact required shape:

- The worker must add temporary timing guarded by existing `HOWL_RENDER_DEBUG_TIMING`; normal non-debug behavior must be unchanged.
- In `handle.zig`, split `emitRenderSurfacePayload` into temporary reported buckets:
  - `payload_alloc_avg_us`: time for `allocator.create(RenderSurfacePayload)` only
  - `payload_init_avg_us`: time for `payload.* = .{}` only
  - `payload_emit_fresh_avg_us`: time for `payload.emitPreparedFresh(...)` only
  - `payload_publish_avg_us` or `payload_assign_avg_us`: time after fresh emission through `self.render_surface_payload = payload`, if measurable as non-zero
  - `payload_emit_total_avg_us`: wall time for the whole `emitRenderSurfacePayload` body
  - `payload_emit_residual_avg_us`: `payload_emit_total_avg_us - payload_alloc_avg_us - payload_init_avg_us - payload_emit_fresh_avg_us - payload_assign_avg_us`, saturated at zero
- In `render_surface_emitter.zig`, split `emitPreparedFresh` into temporary reported buckets:
  - `fresh_total_avg_us`: wall time from the beginning of `emitPreparedFresh` through before/after current debug record, named explicitly so reviewer can see whether debug record time is included
  - `fresh_rollback_avg_us`: time for `resources.admissionRollback()` only
  - `fresh_reset_avg_us`: time for `self.resetPrepared(prepared)` only
  - `fresh_damage_avg_us`: time for `appendFullDamage` only
  - `fresh_full_clear_avg_us`, `fresh_clear_avg_us`, `fresh_background_avg_us`, `fresh_decoration_avg_us`, `fresh_cursor_avg_us`: one bucket per existing fill step
  - `fresh_sprites_avg_us`: existing sprite wall bucket retained
  - `fresh_publish_avg_us`: existing publish wall bucket retained
  - `fresh_record_avg_us`: time spent in `debug_emit_prepared_timing.record(...)` itself
  - `fresh_residual_avg_us`: `fresh_total_avg_us - rollback - reset - damage - fills - sprites - cursor - publish - record`, saturated at zero
- In `render_surface_emitter.zig`, split sprite pass only enough to prove whether the residual is inside sprite control flow:
  - keep existing `sprite_lookup`, `atlas_resource`, `direct_resource`, `stage_upload`, `alpha_glyph_append`, `direct_command_append`, and `transient_retire` buckets
  - add one temporary `sprite_residual_avg_us` computed as `sprites_ns - visible_sprite_sub_buckets`, saturated at zero
  - do not add per-sprite print lines
  - do not add per-sprite allocation or new storage
- The temporary timing output must be one aggregate line per 128 frames at most, matching the current debug cadence.
- The worker must keep all new timing structs owner-local and explicit. No generic `TimingContext`, `Diagnostics`, `Metrics`, `Manager`, `Engine`, or helper bucket file is allowed.
- The worker must not change render commands, resource ids, uploads, glyph refs, retained resource state, failure mapping, publication surface spans, or benchmark behavior.
- Temporary instrumentation disposition is part of the slice: the worker may run proof with temporary edits in the two allowed files, but must restore those source files to their pre-proof content before final handoff unless the orchestrator explicitly asks for a separate instrumentation commit.

Required assertions:

- Assert every residual subtraction is bounded by saturating arithmetic or guarded comparisons; no underflow is allowed.
- Assert current counts used in debug totals remain inside existing bounds before reporting:
  - `command_count <= limits.commands_max`
  - `glyph_count <= limits.glyph_refs_max`
  - `upload_count <= limits.uploads_max`
  - `upload_bytes_count <= limits.upload_bytes_max`
  - `retire_count <= limits.retires_max`
- Keep existing resource rollback assertions intact: `sprite_resource_store.zig:108-156`.
- Do not weaken assertions in `publishSurface`: `render_surface_emitter.zig:797-804`, `render_surface_emitter.zig:810-811`.

Required tests and verification:

- `/home/home/personal/projects/howl/howl-render`: `zig build test:unit`
- `/home/home/personal/projects/howl/howl-linux-host`: `zig build install -Doptimize=ReleaseFast`
- `/home/home/personal/projects/howl/utils/tools/rain-bench`: `zig build --release=fast stress:rain:build`
- `/home/home/personal/projects/howl`: `env HOWL_RENDER_DEBUG_TIMING=1 python3 utils/tools/rain-bench/benchmark_terminals.py --duration 3 --mode ascii --terminals howl 2> /tmp/opencode/howl-render-debug-control.log`
- No 10-second Howl vs Alacritty run is required for this proof-only slice unless the worker accidentally changes behavior or the orchestrator asks for it.

Required proof output from worker:

- coder/worker session id
- exact files changed
- exact commands run
- exact 3-second summary receipt path
- exact stderr timing log path
- quoted old comparison baseline:
  - `prepared_handle_create emit_avg_us=1052`
  - `emit_prepared fills_avg_us=16 sprites_avg_us=336 publish_avg_us=1`
  - `owner_create_avg_us=1053`
- quoted new timing lines with:
  - `payload_emit_total_avg_us`
  - `payload_emit_fresh_avg_us`
  - `payload_emit_residual_avg_us`
  - `fresh_total_avg_us`
  - `fresh_reset_avg_us`
  - `fresh_record_avg_us`
  - `fresh_residual_avg_us`
  - `sprite_residual_avg_us`
- explicit ranking of the largest post-fresh `owner_create` child bucket after the new proof
- explicit cleanup receipt stating whether temporary source edits were removed before handoff, with `git diff`/`git status` confirmation for `handle.zig` and `render_surface_emitter.zig`
- commit-hash handoff status pending orchestrator closure

Non-goals:

- no optimization
- no permanent metrics API
- no tests added solely for temporary debug output
- no changes to render semantics, ABI, host GL, PTY, VT, benchmark wrapper, direct-normal path, fresh rollback, cache-first reuse admission, or source publication flow
- no deletion or weakening of existing debug timing; cleanup may remove only the temporary additions from this proof slice

Stop conditions:

- stop if the residual is mostly `fresh_record_avg_us` or timer/debug-print overhead; report that the debug harness is contaminating the proof instead of optimizing product code
- stop if the largest new bucket remains `fresh_residual_avg_us` or `payload_emit_residual_avg_us` without line-owned explanation after the added splits
- stop if source-pinning the residual requires edits outside the two allowed files
- stop if proving the residual requires changing behavior, not timing it
- stop if unit tests fail for any existing prepared emission, retained resource, failure mapping, or owner handle proof
- stop if the fresh timing run no longer ranks `owner_create`/`prepared_handle_create emit` near the accepted baseline and no source change explains the ranking shift
- stop if the proof exposes a correctness issue in retained resource rollback, surface publication pointer stability, or prepared handle lifecycle
- stop if the temporary instrumentation cannot be removed cleanly back to the pre-proof source state after producing receipts

Risks:

- Timing with `clock_gettime` and debug printing may itself be the residual; this is exactly why the next slice must prove `fresh_record_avg_us` and residual buckets before optimization.
- The accepted proof log was captured with debug timing enabled, so absolute microsecond values are not product-hot-path truth. They are only ranking evidence inside the debug harness.
- The next worker may find that no source optimization is justified until a lower-overhead proof surface exists. That is a valid stop result, not a failed slice.

Proof gaps:

- The current source does not measure wall time for `emitPreparedFresh` as a whole inside the emitter, so the exact residual owner is not line-pinned yet.
- The current source does not measure `debug_emit_prepared_timing.record` time, so timing/printing overhead may be hiding under `PreparedHandle.create emit_avg_us`.
- The current source does not split payload allocation/initialization from fresh emission inside `emitRenderSurfacePayload`.
- The visible `atlas_resource_avg_us=154` remains a plausible later optimization target, but it cannot be selected while about `699us` of enclosing emit time is unexplained.

Reviewer acceptance gate for this plan:

- accept only if the reviewer agrees that the next slice is proof-only and exactly bounded to `handle.zig` plus `render_surface_emitter.zig`
- accept only if worker acceptance requires temporary instrumentation cleanup before final handoff, or a separate explicit orchestrator receipt if the instrumentation is intentionally kept
- reject if the reviewer requires a direct optimization before residual ownership is proved
- reject if the reviewer sees an owner-seam reason that `sprite_resource_store.zig` must be in the first proof slice; if so, require a corrected plan before worker execution
- reject if the reviewer considers temporary timing output untestable or too contaminating to be useful
- reject if cleanup ownership, source disposition, or final `git status`/`git diff` expectations are not explicit enough for a proof-only worker slice
