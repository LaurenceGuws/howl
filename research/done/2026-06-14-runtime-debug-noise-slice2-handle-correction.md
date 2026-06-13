# Historical Authority

- Historical authority at time: accepted Slice 2 correction package for `orch-2026-06-14-runtime-debug-noise-01`, accepted by `review-2026-06-14-runtime-debug-noise-01`.
- Why superseded or done: promoted into active sprint contract `sprints/2026-06-14-runtime-debug-noise-cleanup-sprint.md` for reseeded Slice 2 execution.
- Must not be used for: direct execution authority after sprint promotion; use the active sprint and loop contract instead.

# Runtime Debug Noise Slice 2 Handle Correction

Status:

- Active correction research artifact for Slice 2 rejection.
- Orchestrator session id: `orch-2026-06-14-runtime-debug-noise-01`.
- Researcher session id: `research-2026-06-14-runtime-debug-noise-01`.
- Reviewer session id: `review-2026-06-14-runtime-debug-noise-01`.
- Planning seed receipt: `e7a90db`.
- Accepted planning receipt: `1ccaddd`.
- Sprint seed receipt: `d52f6d2`.
- Slice 2 seed receipt: `60dde74`.
- Slice 2 correction seed receipt: `7ace906` `Seed runtime debug-noise Slice 2 correction`.
- Trigger: reviewer rejection of Slice 2 due to missed adjacent prepare-handle timing in `howl-render/src/surface/handle.zig`.
- Reviewer accepted correction.
- No Slice 2 acceptance is authorized until this correction is promoted into the execution scope and the scope is reseeded.
- Correction acceptance receipt: `e94864b` `Accept runtime debug-noise Slice 2 correction`.

## Sources Read In Order

1. `loop/flow.md`
2. `loop/orcestrator.md`
3. `loop/researcher.md`
4. `loop/reviewer.md`
5. `loop/coder.md`
6. `loop/researcher.md`
7. `sprints/current.txt`
8. `loops/runtime-debug-noise-cleanup-live-loop.txt`
9. `research/2026-06-14-runtime-debug-noise-slice2-handle-correction.md`
10. `sprints/2026-06-14-runtime-debug-noise-cleanup-sprint.md`
11. `research/done/2026-06-14-runtime-debug-noise-cleanup-plan.md`
12. `howl-render/src/surface/handle.zig`
13. `howl-render/src/render_session.zig`
14. `howl-render/src/surface/handle_test.zig`
15. `howl-render/src/test_unit.zig`
16. `howl-render/build.zig`
17. `howl-render/src/c/prepared_surface_test.zig`
18. `howl-render/src/test_abi.zig`

## Correction Decision

- Decision: repair the existing unaccepted Slice 2 by adding `howl-render/src/surface/handle.zig` to the same Slice 2 scope.
- Rationale: `render_session.zig:458-476` owns `TextSessionOwner.prepareHandle`, and `render_session.zig:474` calls `prepared_handle.PreparedHandle.create`. The missed `handle.zig` timing is in the same active prepare-handle runtime path that Slice 2 is already cleaning. Deferring it would accept a Slice 2 that still contains prepare-handle debug timing noise immediately downstream of the cleaned `render_session.zig` path.
- Not chosen: separate named slice or deferral. That would preserve `HOWL_RENDER_DEBUG_TIMING` timing output in the Slice 2 runtime path after the slice claims prepare timing cleanup.

## Handle Inventory

- `howl-render/src/surface/handle.zig:10-14` `monotonicNs()`.
  Classification: stale migration residue.
  Action: delete.
  Reason: the helper exists only to feed debug timing in `PreparedHandle.create`; it is not a runtime invariant or scheduling fact.
- `howl-render/src/surface/handle.zig:16-58` `DebugPreparedHandleCreateTiming`.
  Classification: stale migration residue.
  Action: delete.
  Reason: env-var-gated profiling branch, aggregate counters, max/total timing fields, and `std.debug.print` are observation-only runtime debug noise.
- `howl-render/src/surface/handle.zig:27-33` `active()` and `HOWL_RENDER_DEBUG_TIMING` gate.
  Classification: stale migration residue.
  Action: delete as part of the debug struct.
  Reason: env-var-gated runtime branch is debugging posture, not product behavior.
- `howl-render/src/surface/handle.zig:35-57` `record()` aggregation and print.
  Classification: stale migration residue.
  Action: delete as part of the debug struct.
  Reason: timing aggregation and periodic print are observation-only; no caller consumes this result for correctness.
- `howl-render/src/surface/handle.zig:60` `debug_prepared_handle_create_timing` global.
  Classification: stale migration residue.
  Action: delete.
  Reason: global mutable debug state has no handle lifecycle consequence.
- `howl-render/src/surface/handle.zig:73-75` allocation timing in `PreparedHandle.create`.
  Classification: stale migration residue.
  Action: delete `alloc_start_ns` and `alloc_ns`; retain the allocation itself.
- `howl-render/src/surface/handle.zig:83-86` registration timing in `PreparedHandle.create`.
  Classification: stale migration residue.
  Action: delete `register_start_ns` and `register_ns`; retain `registerPreparedHandle` and `registered = true`.
- `howl-render/src/surface/handle.zig:87` emit timing start and `handle.zig:94` timing record call.
  Classification: stale migration residue.
  Action: delete `emit_start_ns` and `debug_prepared_handle_create_timing.record(...)`; retain `emitRenderSurfacePayload()` and its error-to-emission-failure mapping at `handle.zig:88-93`.
- `howl-render/src/surface/handle.zig:72`, `74`, `76-82`, `84-85`, `88-93`, `95` `PreparedHandle.create` runtime ownership path.
  Classification: runtime truth.
  Action: retain.
  Reason: create owns handle allocation, prepared-surface transfer to the handle, source value reset, registration with the session owner, render-surface payload emission, emission failure recording, and returned handle.
- `howl-render/src/surface/handle.zig:103-204` destroy/release/live/query/consume/payload lifecycle.
  Classification: runtime truth.
  Action: retain.
  Reason: lifecycle, ownership, and payload cleanup are not debug instrumentation.

## Reseeded Slice 2 Scope

- Coder session id: `coder-2026-06-14-runtime-debug-noise-slice-02` unless the orchestrator explicitly assigns a replacement correction coder id.
- Allowed files: `howl-render/src/render_session.zig`, `howl-render/src/text/surface_preparer.zig`, `howl-render/src/text/direct_normal.zig`, `howl-render/src/benchmark_main.zig`, `howl-render/src/surface/handle.zig`.
- Required shape: complete the previously seeded Slice 2 cleanup and also delete handle creation timing. `handle.zig` must have no `monotonicNs`, no `DebugPreparedHandleCreateTiming`, no `HOWL_RENDER_DEBUG_TIMING`, no debug timing global, no aggregate timing fields, no timing locals in `PreparedHandle.create`, and no timing `std.debug.print`. `PreparedHandle.create` must remain a direct owner transfer: allocate handle, move prepared surface into the handle, reset caller value, register handle, emit payload, record emission failure if payload emission fails, return handle.
- Exact tests from `howl-render`: `zig build test:unit -- render session`; `zig build test:unit -- direct normal`; `zig build test:unit -- prepared handle`; `zig build test:unit`; `zig build benchmark:render:build`; `zig build check`.
- ABI proof if public behavior is suspected: `zig build test:abi` from `howl-render`. Expected not required for pure private timing deletion, but run it if any exported prepared-handle ABI compile path changes.

## Proof Roots

- Render unit root: `howl-render/src/test_unit.zig:1-12`; `test_unit.zig:4` imports `surface/handle_test.zig`, and `test_unit.zig:6` imports `render_session.zig`.
- Handle direct proof: `howl-render/src/surface/handle_test.zig:16-61` proves missing-sprite emission failure without double free; `handle_test.zig:127-159` proves prepared owner surface realization and pointer stability; `handle_test.zig:161-204` proves retained sprite resource reuse across handle creation; `handle_test.zig:206-227` proves partial surface realization; `handle_test.zig:229-260` proves release and payload cleanup; `handle_test.zig:262-274` proves session ownership; `handle_test.zig:277-333` proves overflow and allocation-failure emission behavior.
- Render session path proof: `howl-render/src/render_session.zig:458-476` is the caller path that reaches `PreparedHandle.create`; inline render-session tests are imported by `test_unit.zig:6`.
- ABI prepared-surface proof: `howl-render/src/test_abi.zig:4-11` imports `c/prepared_surface_test.zig`; `test_abi.zig:30-32` checks exported `howl_render_rdr_sfc_*` entrypoints; `howl-render/src/c/prepared_surface_test.zig:89-122` creates prepared handles and validates render-surface retrieval and emission failure over the C-facing path.
- Benchmark build proof: `howl-render/build.zig:126-152` builds `benchmark_main.zig` under `benchmark:render:build`; `build.zig:152` makes package `check` depend on the benchmark build.

## Non-Goals

- No ABI header changes.
- No changes to `howl-render/src/surface/handle_test.zig` or ABI tests unless the correction is reseeded again with exact test-file scope.
- No new debug, metrics, instrumentation, helper, or types files.
- No relocation of handle timing into `render_session.zig`, `handle.zig`, benchmark code, or any other runtime owner.
- No lifecycle redesign for `PreparedHandle`, registration, release, consume, payload allocation, or emission failure mapping.
- No deletion of assertions, bounds, ownership transfer, or error handling.

## Stop Conditions

- If any file outside the five allowed files needs content changes, stop and reseed exact scope before editing.
- If deleting handle timing requires changing exported ABI headers or C-visible struct/enum values, stop for orchestrator/reviewer/user decision.
- If a test only proves timing/debug output, stop and reseed exact test-file scope before deleting or rewriting that test.
- If `PreparedHandle.create` ownership transfer, `errdefer prepared_handle.destroy()`, `registerPreparedHandle`, `registered = true`, or emission failure mapping would be weakened, stop.
- If benchmark detailed phase timing is requested in a way that requires runtime timing payloads, stop; benchmark-owned redesign is not authorized by this correction.

## Receipt Fields

- Planning seed receipt: `e7a90db`.
- Accepted planning receipt: `1ccaddd`.
- Sprint seed receipt: `d52f6d2`.
- Slice 2 seed receipt: `60dde74`.
- Slice 2 correction seed receipt: `7ace906` `Seed runtime debug-noise Slice 2 correction`.
- Coder session id.
- Reviewer verdict from `review-2026-06-14-runtime-debug-noise-01`.
- Verification commands and results.
- Benchmark timing ownership decision: delete runtime timing payloads; keep only benchmark-owned outer duration/allocation/count observations already scoped in Slice 2.
- Commit hash after orchestrator acceptance, or explicit uncommitted handoff status while correction is under review.

## Readiness Judgment

- Ready for reviewer correction review.
- Not ready for Slice 2 acceptance until reviewer accepts this correction and the orchestrator reseeds Slice 2 with `howl-render/src/surface/handle.zig` added to the allowed files.
