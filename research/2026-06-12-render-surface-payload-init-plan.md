Render surface payload initialization plan

Date: 2026-06-12.
Status: active researcher target.
Role owner: researcher.
Orchestrator session id: `orch-2026-06-11-ascii-rain-honest-performance-02`.
Researcher session id: `research-2026-06-12-render-surface-payload-init-01`.
Reviewer session id: pending.
Planning commit-hash receipt: pending.

Preload receipt:

- Role: researcher
- Active sprint:
  - `/home/home/personal/projects/howl/sprints/2026-06-11-ascii-rain-honest-performance-sprint.md`
- Active loop:
  - `/home/home/personal/projects/howl/loops/ascii-rain-live-loop.txt`
- Active research:
  - `/home/home/personal/projects/howl/research/2026-06-12-render-surface-payload-init-plan.md`
- Current proof receipts:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-013159-ascii/summary.json`
  - `/tmp/opencode/howl-render-debug-control.log`
- Prior accepted baseline receipts:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-011550-ascii/summary.json`
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-011602-ascii/summary.json`
- Execution authorized:
  - research and planning only; no implementation from this pass

Problem statement:

- The proof-only residual slice removed temporary source instrumentation before handoff and produced a receipt at `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-013159-ascii/summary.json`.
- The proof line-owned the largest post-fresh `owner_create` child bucket to `payload.* = .{}` inside `PreparedHandle.emitRenderSurfacePayload`.
- Current proof lines:
  - `payload_init_avg_us=740`
  - `payload_emit_fresh_avg_us=358`
  - `payload_emit_total_avg_us=1099`
  - `payload_emit_residual_avg_us=0`
  - `fresh_total_avg_us=358`
  - `fresh_residual_avg_us=0`
  - `fresh_record_avg_us=0`
- The next research task is to produce one reviewer-acceptable optimization slice for eliminating or avoiding the hot payload full zero-initialization while preserving prepared handle lifecycle, publication pointer stability, render-surface bounds invariants, and host-facing ABI consequences.

Initial owner focus:

- `/home/home/personal/projects/howl/howl-render/src/prepared/handle.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/surface.zig`
- prepared owner tests only if source proves the lifecycle/pointer-stability contract needs proof there

Research requirements:

- Read the live workflow, active loop, current sprint index, this file, TigerBeetle readings, and source/reference anchors before writing a plan.
- Explain exactly why `payload.* = .{}` is expensive in current source shape and what owner should avoid it.
- Produce one reviewer-acceptable worker slice with exact allowed files, shape, tests, non-goals, stop conditions, assertions, receipt paths, and timing proof expectations.
- Do not drift into host, GL, benchmark-wrapper, PTY, VT, ABI, direct-normal, sprite cache-first, fresh rollback, or temporary instrumentation work.
- Stop and report if the truthful next step exposes a big correctness issue or vague bucket.

Readiness judgment:

- Ready for reviewer gate.

Researcher pass receipt:

- Researcher session id:
  - `research-2026-06-12-render-surface-payload-init-01`
- Scope:
  - research and planning only
  - no source implementation from this pass
- Sources read in required order:
  - `/home/home/personal/projects/howl/loop/flow.md`
  - `/home/home/personal/projects/howl/loop/orcestrator.md`
  - `/home/home/personal/projects/howl/loop/researcher.md`
  - `/home/home/personal/projects/howl/loop/reviewer.md`
  - `/home/home/personal/projects/howl/loop/coder.md`
  - `/home/home/personal/projects/howl/sprints/current.txt`
  - `/home/home/personal/projects/howl/loops/ascii-rain-live-loop.txt`
  - `/home/home/personal/projects/howl/research/2026-06-12-render-surface-payload-init-plan.md`
  - `/home/home/personal/projects/howl/reference-index.md`
  - `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
  - `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/handle.zig`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/surface.zig`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/owner_test.zig`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter_test.zig`
  - `/home/home/personal/projects/howl/howl-render/src/session/text.zig`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/submit.zig`
  - `/home/home/personal/projects/howl/howl-render/include/howl_render.h`
  - `/home/home/personal/projects/howl/howl-render/src/ffi/prepared_surface.zig`
  - `/home/home/personal/projects/howl/howl-render/src/ffi/prepared_surface_test.zig`
  - `/home/home/personal/projects/howl/howl-render/src/test/unit/root.zig`
- Proof receipts read:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-013159-ascii/summary.json`
  - `/tmp/opencode/howl-render-debug-control.log`

Compact anchor map:

- TigerBeetle style anchors:
  - `TIGER_STYLE.md:96-100` requires fixed bounds for loops and queues; this supports preserving the existing fixed render-surface max arrays instead of new dynamic staging.
  - `TIGER_STYLE.md:104-140` requires assertions for arguments, return values, invariants, and positive/negative space; the worker slice must add assertions around the fresh-emitter initialization boundary and retain overflow/failure tests.
  - `TIGER_STYLE.md:151-156` prefers memory allocated up front and bounded, not dynamic growth; the slice must not replace the payload with a variable heap buffer or host-side allocation scheme.
  - `TIGER_STYLE.md:381-387` explicitly prefers in-place initialization with pointer stability for large structs; the correct optimization is in-place fresh payload construction, not return-by-value construction or host copying.
  - `TIGER_STYLE.md:435-438` warns about buffer bleeds; avoiding full initialization is allowed only if every host-visible span pointer/count and every consumed record is definitely written before publication.
  - `ARCHITECTURE.md:353-363` frames memory layout and straight-line data-plane work as performance-critical; the hot path must stop writing the whole large payload when only counts/spans and active records matter.
  - `ARCHITECTURE.md:408-423` supports keeping control-plane assertions separate from data-plane loops; the proof belongs in emitter publication/reset code and owner tests, not host or benchmark wrapper code.
- Current Howl owner seams:
  - `handle.zig:62-70` owns the prepared handle state, borrowed prepared surface, optional render-surface payload pointer, lifecycle state, and registration flag.
  - `handle.zig:72-95` moves the prepared surface into the handle, registers it, emits the render-surface payload, and records owner-create timing.
  - `handle.zig:184-195` is the current bottleneck seam: allocate payload, execute `payload.* = .{}`, emit fresh prepared surface into it, then publish the payload pointer to the handle.
  - `render_surface_emitter.zig:260-277` defines the fixed payload storage: large arrays for damage, creates, uploads, upload offsets, commands, glyphs, retires, upload bytes, scalar counts, and `surface_storage`.
  - `render_surface_emitter.zig:328-362` is the fresh emitter path; it already calls `resetPrepared` before appending any records and publishes only after append steps complete.
  - `render_surface_emitter.zig:364-382` resets all scalar counts and assigns all top-level host-visible surface identity fields before emission.
  - `render_surface_emitter.zig:789-844` publishes host-visible spans from scalar counts and fixed arrays; it only scans `command_count` and `upload_count`, then writes span pointers/counts/count_max.
  - `surface.zig:23-33` keeps `PreparedSurface` ownership separate from render-surface emission failure state.
  - `session/text.zig:514-535` calls `PreparedHandle.create` as the owner-create phase measured in the active timing receipts.
  - `session/text.zig:652-660` and `session/text.zig:674-729` preserve the prepared handle pointer through publish and submit; the payload pointer must remain stable after render-surface retrieval.
  - `ffi/prepared_surface.zig:43-52` returns a borrowed `HowlRenderSurface` pointer or maps the owner-local emission failure to a C status.
  - `include/howl_render.h:304-316` defines the host-facing surface as spans, not inline arrays; hosts can observe only the published span metadata and referenced active payload records.

Current-code facts:

- `PreparedHandle.create` allocates the handle, moves the `PreparedSurface` into it, empties the caller surface, registers the handle, then calls `emitRenderSurfacePayload`; emission failure is recorded in `prepared.render_surface_emission_failure` instead of failing handle creation (`handle.zig:72-95`).
- `emitRenderSurfacePayload` currently asserts no payload is already published, allocates `RenderSurfacePayload`, writes `payload.* = .{}`, destroys the allocation on emission failure, calls `emitPreparedFresh`, and assigns `self.render_surface_payload = payload` only after success (`handle.zig:184-195`).
- The hot `payload.* = .{}` has aggregate type `render_surface_emitter.Emitter(.{})`, whose fields include all fixed upper-bound arrays, including `glyphs`, `commands`, `upload_bytes`, `damage`, creates/uploads/retires, and `surface_storage` (`render_surface_emitter.zig:257-277`). The timing receipt proves this full aggregate assignment is not free in the current build.
- The success path does not require prior array contents to be zero. `resetPrepared` sets every scalar count to zero and assigns `surface_storage = emptySurface()` plus token/render/cell/grid identity before any append (`render_surface_emitter.zig:364-382`). Append methods write each record before incrementing the matching count, for example damage at `render_surface_emitter.zig:384-398`, creates at `render_surface_emitter.zig:641-663`, uploads at `render_surface_emitter.zig:665-704`, commands at `render_surface_emitter.zig:737-741`, glyph refs at `render_surface_emitter.zig:743-778`, and retires at `render_surface_emitter.zig:780-787`.
- `publishSurface` derives host-facing spans from counts and arrays after emission, rewrites glyph run pointers only for `command_index < command_count`, rewrites upload byte pointers only for `upload_index < upload_count`, and assigns null pointers when counts are zero (`render_surface_emitter.zig:789-844`).
- On `emitPreparedFresh` failure, the caller's payload is not stored in `PreparedHandle.render_surface_payload`; `errdefer` destroys the allocation and `renderSurface` returns null via the recorded failure (`handle.zig:88-93`, `handle.zig:184-195`, `handle.zig:136-145`).
- Existing owner tests already prove important adjacent contracts: missing sprite returns no surface (`owner_test.zig:15-60`), borrowed upload pointer remains stable through repeated `handle.renderSurface()` calls (`owner_test.zig:126-154`), release nulls the payload (`owner_test.zig:224-238`), overflow reports no surface (`owner_test.zig:240-270`), allocation failure maps to no surface (`owner_test.zig:272-296`), fresh sprite reuse emits zero uploads in handle flow (`owner_test.zig:156-199`), and fresh failure restores retained resource admission state (`render_surface_emitter_test.zig:1071-1129`).
- The unit root imports both prepared emitter tests and prepared owner tests (`src/test/unit/root.zig:1-9`), so a `zig build test:unit` run reaches the proof roots relevant to this slice.
- The C ABI sees only a borrowed `HowlRenderSurface` pointer returned by `ffi/prepared_surface.zig:43-52`; no host-facing struct layout or status code change is needed.

Current proof receipts:

- Active 3-second receipt:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-013159-ascii/summary.json`
  - Howl-only final FPS: `25.65` at `summary.json:70-80`
- Active debug timing proof:
  - `/tmp/opencode/howl-render-debug-control.log`
  - 640-frame proof lines:
    - `emit_prepared count=640 ... sprites_avg_us=339 ... publish_avg_us=2 ... copy_out_avg_us=0` at `howl-render-debug-control.log:21`
    - `emit_prepared_fresh_residual count=640 fresh_total_avg_us=358 ... fresh_residual_avg_us=0 ... fresh_record_avg_us=0` at `howl-render-debug-control.log:22`
    - `payload_emit count=640 payload_alloc_avg_us=0 payload_init_avg_us=740 payload_emit_fresh_avg_us=358 payload_assign_avg_us=0 payload_emit_total_avg_us=1099 payload_emit_residual_avg_us=0` at `howl-render-debug-control.log:23`
    - `prepared_handle_create count=640 ... emit_avg_us=1099` at `howl-render-debug-control.log:24`
    - `prepare_handle count=640 ... direct_normal_avg_us=1139 ... owner_create_avg_us=1100` at `howl-render-debug-control.log:25`
- Prior accepted baseline receipts:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-011550-ascii/summary.json`
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-011602-ascii/summary.json`
  - accepted baseline result from the live loop: Howl `36.85 fps`, Alacritty `1009.95 fps`.

Bottleneck explanation:

- The hot line is not semantic work. `payload.* = .{}` initializes a full `RenderSurfacePayload` aggregate before the emitter fresh path immediately resets counts and publishes only active spans.
- The payload object is large because it contains all bounded storage arrays, especially glyph refs and upload bytes. The C ABI surface is a span view into those arrays, so zeroing inactive array tails does not change host-facing behavior when counts and pointers are correct.
- The true owner seam is split but narrow:
  - `PreparedHandle` owns allocation, lifecycle, failure mapping, and publication pointer stability.
  - `render_surface_emitter.Emitter` owns the invariant that fresh emission initializes all fields that can become visible through `Surface` before returning success.
- The correct optimization is therefore not a new ABI, host-side copy, GL path, sprite cache, direct-normal change, benchmark change, or temporary instrumentation. It is to make fresh payload construction explicitly in-place and initialized-by-emission, then remove the full aggregate assignment from the prepared handle hot path.

Owner roles and proposed shape:

- `PreparedHandle` remains the only owner that allocates and publishes a payload pointer.
- `PreparedHandle.emitRenderSurfacePayload` must allocate `RenderSurfacePayload` and call the fresh emission method without first assigning `payload.* = .{}`.
- `render_surface_emitter.Emitter.emitPreparedFresh` must explicitly support entry with undefined payload storage by resetting all scalar counts and `surface_storage` before appending or publishing.
- The worker should not introduce a separate payload owner, manager, context, options struct, or compatibility path.
- The worker should not add host-facing ABI changes. `HowlRenderSurface` continues to expose borrowed spans from the payload storage.

Required worker slice: `prepared-handle-fresh-payload-in-place-init`

- Purpose:
  - eliminate the full `RenderSurfacePayload` aggregate assignment in `PreparedHandle.emitRenderSurfacePayload` by making fresh render-surface emission explicitly initialize an undefined payload in place.
- Researcher session id:
  - `research-2026-06-12-render-surface-payload-init-01`
- Required future coder/worker session id:
  - pending orchestrator seed
- Required future reviewer session id:
  - pending reviewer gate for this research package
- Allowed files:
  - `/home/home/personal/projects/howl/howl-render/src/prepared/handle.zig`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter_test.zig`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/owner_test.zig`
- Not allowed:
  - any other source file
  - `howl-render/include/howl_render.h`
  - `howl-render/src/ffi/*`
  - `howl-linux-host/*`
  - `utils/tools/rain-bench/*`
  - PTY, VT, direct-normal, sprite resource store, render realizer, benchmark wrapper, GL, or temporary instrumentation changes
- Exact required implementation shape:
  - In `handle.zig`, remove the hot full aggregate assignment `payload.* = .{}` from `PreparedHandle.emitRenderSurfacePayload`.
  - Keep `std.debug.assert(self.render_surface_payload == null)` at entry.
  - Keep allocation through `self.session_owner.allocator.create(RenderSurfacePayload)`.
  - Keep `errdefer self.session_owner.allocator.destroy(payload)` before emission, so failed emission leaves no published payload and no leak.
  - Keep `self.render_surface_payload = payload` only after `emitPreparedFresh` succeeds.
  - Do not change `PreparedHandle.create` failure mapping, release/consume/destroy lifecycle, session registration, publication state transitions, or C ABI render-surface retrieval behavior.
  - In `render_surface_emitter.zig`, make the fresh-emission contract explicit in owner code: `emitPreparedFresh` may be called on undefined `Self` storage and must initialize all counts and `surface_storage` before any append method can publish host-visible state.
  - The simplest acceptable code shape is to keep `emitPreparedFresh` as the entrypoint and ensure its first `self` mutation is `self.resetPrepared(prepared)` before any read from `self`; if the worker adds a helper, it must be owner-true and small, not a vague initializer bucket.
  - Add assertions after reset or around publication that prove the initialized control fields are valid: counts are zero after reset before append, `surface_storage.surface_version` equals `HOWL_RENDER_SURFACE_VERSION`, span count_max values match ABI constants after publication, and active pointer/count relationships are valid.
  - Do not zero inactive array tails. They are not host-visible when counts and pointers are correct.
  - Do not preserve `.init()` as the hidden proof for this path; the proof must show fresh emission itself initializes undefined payload storage.
- Required new or sharpened tests:
  - In `render_surface_emitter_test.zig`, add an owner-local test that declares `var emitter: Emitter(.{}) = undefined;`, calls `emitPreparedFresh`, and proves the returned `Surface` has correct version, token/render/cell/grid, span counts/count_max/null pointer rules, and realizes to the prepared-buffer oracle.
  - The undefined-fresh-emitter test must include at least one command-producing prepared surface so the commands span is non-null and active command data is read by the realizer.
  - The undefined-fresh-emitter test must include at least one zero-count span expectation, for example creates/uploads/retires are null with count zero and ABI count_max values intact, so stale uninitialized pointer exposure is rejected.
  - In `owner_test.zig`, add or sharpen a prepared-handle test proving the borrowed surface pointer and at least one nested active pointer remain stable across repeated `handle.renderSurface()` calls after in-place fresh initialization. The existing upload pointer stability test at `owner_test.zig:126-154` may be sharpened if it remains owner-true and readable.
  - Existing failure tests must remain green: missing sprite, command overflow, owned overflow once, allocation failure, release clearing payload, fresh resource admission rollback, and FFI render-surface failure mapping through existing roots.
- Required assertions:
  - Entry assertion in `PreparedHandle.emitRenderSurfacePayload`: no existing payload is published.
  - Fresh emitter reset assertions: counts are zero after reset before append work observes them.
  - Publish assertions: glyph fixup consumes exactly `glyph_count`; upload byte offsets are below `upload_bytes_count` for each published upload; span `count_max` values match ABI constants; non-zero counts imply non-null pointers and zero counts imply null pointers for top-level spans.
  - Failure-path assertions/tests: failed fresh emission does not assign `PreparedHandle.render_surface_payload` and does not mutate retained resource admission state beyond the existing rollback contract.
- Required verification commands:
  - `/home/home/personal/projects/howl/howl-render`: `zig build test:unit`
  - `/home/home/personal/projects/howl/howl-linux-host`: `zig build install -Doptimize=ReleaseFast`
  - `/home/home/personal/projects/howl/utils/tools/rain-bench`: `zig build --release=fast stress:rain:build`
  - `/home/home/personal/projects/howl`: `env HOWL_RENDER_DEBUG_TIMING=1 python3 utils/tools/rain-bench/benchmark_terminals.py --duration 3 --mode ascii --terminals howl 2> /tmp/opencode/howl-render-debug-control.log`
  - `/home/home/personal/projects/howl`: `python3 utils/tools/rain-bench/benchmark_terminals.py --duration 10 --mode ascii --terminals howl alacritty`
- Required timing proof expectations:
  - Before baseline for this slice:
    - `payload_init_avg_us=740`
    - `payload_emit_fresh_avg_us=358`
    - `payload_emit_total_avg_us=1099`
    - `prepared_handle_create emit_avg_us=1099`
    - `owner_create_avg_us=1100`
  - The 3-second timing rerun must quote the latest `payload_emit`, `prepared_handle_create`, and `prepare_handle` lines from `/tmp/opencode/howl-render-debug-control.log`.
  - Acceptance target:
    - `payload_init_avg_us` must be eliminated or reduced to no more than `50` us.
    - `payload_emit_total_avg_us` must drop below the accepted `1099` baseline.
    - `prepared_handle_create emit_avg_us` must drop below the accepted `1099` baseline.
    - The benchmark rerun must not expose a correctness failure or crash.
  - If `payload_init_avg_us` is not present after the worker because the temporary proof labels were removed from source before handoff, the worker must instead quote the nearest accepted built-in timing fields and explicitly state whether the payload-init proof seam is no longer emitted. The worker must not add temporary instrumentation unless the orchestrator seeds a proof-only instrumentation slice.
- Required receipt fields from the worker:
  - coder/worker session id
  - files changed
  - exact tests run and results
  - exact 3-second summary path
  - exact 10-second summary path
  - exact stderr timing log path
  - quoted timing lines from the rerun
  - exact before/after values for `payload_init_avg_us` when available, `payload_emit_total_avg_us` when available, `prepared_handle_create emit_avg_us`, and `owner_create_avg_us`
  - commit-hash handoff status pending orchestrator closure

Non-goals:

- No host, GL, PTY, VT, direct-normal, sprite cache-first, fresh rollback, benchmark wrapper, or C ABI work.
- No temporary instrumentation work in this optimization slice.
- No new runtime layer, manager, engine, controller, context, options, config, diagnostics, or broad bucket struct.
- No dynamic payload sizing or heap buffer substitution.
- No change to host-visible `HowlRenderSurface` layout, render-surface status codes, or borrowed pointer lifecycle.
- No cleanup of unrelated tests, formatting, comments, or timing code outside the allowed files.

Stop conditions:

- Stop if `emitPreparedFresh` cannot be made correct from undefined storage without widening outside the allowed files.
- Stop if any append or publish path reads inactive array contents before the corresponding count is written.
- Stop if removing `payload.* = .{}` exposes host-visible stale pointers, stale counts, or uninitialized `Surface` fields.
- Stop if success requires changing the C ABI, FFI status mapping, host GL consumption, session publication state machine, or prepared handle lifecycle.
- Stop if a test failure shows a correctness bug in render-surface pointer ownership, retained resource rollback, or prepared surface lifecycle rather than just payload initialization cost.
- Stop if timing does not improve and the only available next step would be temporary instrumentation; report the proof gap instead of adding logs in the optimization slice.

Risks:

- The main safety risk is a buffer bleed: an inactive array tail might contain junk. This is acceptable only while counts and top-level spans prevent host access to inactive records.
- The second safety risk is stale pointer exposure through `surface_storage` if publication misses a span. The required undefined-fresh-emitter test must catch null/count rules for zero spans and realizer access for active commands.
- The performance risk is that the compiler may still materialize a large initialization through another aggregate assignment, especially `surface_storage = emptySurface()`. That assignment is small relative to the full payload and must remain until a later proof says otherwise.
- The workflow risk is relying on `payload_init_avg_us` after the proof-only worker removed temporary instrumentation. The worker must not recreate temporary instrumentation unless explicitly seeded; built-in timing may be sufficient to prove `prepared_handle_create emit_avg_us` and `owner_create_avg_us` improvements.

Proof gaps:

- The active proof log contains temporary line-owned fields for `payload_init_avg_us`; current source read after cleanup does not include those `payload_emit` timing labels in `handle.zig`. The optimization slice can still be planned because the accepted proof receipt line-owned the bottleneck, but the worker may not be able to quote `payload_init_avg_us` after the fix without a separate instrumentation slice.
- There is no dedicated test today that calls `emitPreparedFresh` on undefined emitter storage. This is the required new proof for the worker slice.
- Existing FFI tests prove borrowed-surface lifecycle and failure mapping, but they are not in the allowed file set for this slice and should remain unchanged.
