# Runtime Debug Noise Cleanup Plan

Status:

- Active research artifact for planning.
- Orchestrator session id: `orch-2026-06-14-runtime-debug-noise-01`.
- Researcher session id: `research-2026-06-14-runtime-debug-noise-01`.
- Reviewer session id: `review-2026-06-14-runtime-debug-noise-01`.
- Planning seed receipt: `e7a90db` `Seed runtime debug-noise planning`.
- Reviewer accepted planning.
- No implementation is authorized from this file until the orchestrator seeds execution slices.
- Acceptance receipt: pending orchestrator commit.

## Sources Read In Order

1. `loop/flow.md`
2. `loop/orcestrator.md`
3. `loop/researcher.md`
4. `loop/reviewer.md`
5. `loop/coder.md`
6. `loop/researcher.md`
7. `sprints/current.txt`
8. `loops/runtime-debug-noise-cleanup-live-loop.txt`
9. `research/2026-06-14-runtime-debug-noise-cleanup-plan.md`
10. `reference-index.md`
11. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
12. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
13. `howl-render/src/surface/emitter.zig`
14. `howl-render/src/render_session.zig`
15. `howl-linux-host/src/terminal/surface.zig`
16. `howl-render/src/surface/realizer.zig`
17. `build.zig`
18. `howl-render/build.zig`
19. `howl-linux-host/build.zig`
20. `howl-render/src/test_unit.zig`
21. `howl-render/src/test_abi.zig`
22. `howl-linux-host/src/host_test_root.zig`
23. `howl-linux-host/src/integration_test_root.zig`
24. `howl-render/src/text/surface_preparer.zig`
25. `howl-render/src/text/direct_normal.zig`
26. `howl-render/src/benchmark_main.zig`
27. `howl-render/src/test_unit.zig`
28. `howl-render/src/text/ft_hb/support_test.zig`
29. `howl-linux-host/src/display/render_surface.zig`
30. `howl-render/src/surface/emitter_test.zig`
31. `howl-linux-host/src/terminal/surface_test.zig`
32. `howl-linux-host/src/display/render_surface_test.zig`
33. `howl-linux-host/src/event.zig`
34. `utils/dev_references/terminals/alacritty/alacritty/src/display/meter.rs`
35. `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs`
36. `utils/dev_references/zig_maturity/tigerbeetle/docs/internals/HACKING.md`
37. `utils/dev_references/zig_maturity/tigerbeetle/docs/internals/vopr.md`

## Compact Anchor Map

- TigerBeetle style anchor: `TIGER_STYLE.md:90-100` demands simple explicit bounded control flow; instrumentation branches in hot runtime paths are not runtime truth unless they enforce a bound or invariant.
- TigerBeetle assertion anchor: `TIGER_STYLE.md:104-140` requires assertions and invariant checks to remain. Cleanup must delete timing and counters, not `std.debug.assert` guards or validation.
- TigerBeetle scope anchor: `TIGER_STYLE.md:416-429` says shrink variable scope and prefer simpler return types. Diagnostic timing structs and result wrappers that only carry observation widen runtime dimensionality.
- TigerBeetle benchmark/proof separation anchor: `docs/internals/HACKING.md:124-132` keeps macro benchmark work in benchmark commands, and `docs/internals/vopr.md:48-63` keeps checkers/assertions as proof/safety, not ad hoc runtime logging.
- Alacritty debug anchor: `alacritty/src/display/meter.rs:1-18` and `alacritty/src/display/mod.rs:1328-1347` show a render timer as a UI debug feature behind explicit debug configuration, not env-var profiling mixed through renderer data-plane code.
- Current render surface owner seam: `howl-render/src/surface/emitter.zig` owns converting a prepared text surface plus sprite resources into `HowlRenderSurface` spans; its runtime truth is bounded span mutation and publication.
- Current render session owner seam: `howl-render/src/render_session.zig` owns text session state, source publication preparation, prepared handle lifecycle, submit state, and session work state; its runtime truth is prepare/submit ownership and mutex discipline.
- Current direct-normal text owner seam: `howl-render/src/text/direct_normal.zig` owns the fast direct-normal text preparation path; runtime truth is lane classification, scratch ownership, draw collection, raster request/output ownership, counters, and assertions. Its `Timings` payload is observation-only.
- Current host surface owner seam: `howl-linux-host/src/terminal/surface.zig` owns host terminal runtime turn admission, render prepare/submit orchestration, and host texture realization handoff; runtime truth is `TurnStep`, pending work, submitted snapshot, and present acknowledgement.
- Current render realizer owner seam: `howl-render/src/surface/realizer.zig` owns validating and realizing `HowlRenderSurface` commands into pixels for tests/CPU realization; its validation helpers are safety/proof truth, not debug noise.
- Current host GL realization seam: `howl-linux-host/src/display/render_surface.zig`, `render_surface_commands.zig`, and `render_surface_resources.zig` own host-side GL texture/resource realization. Current `UploadStats` is observation-only and is pulled into `terminal/surface.zig` runtime results.
- Current benchmark seam: `howl-render/src/benchmark_main.zig` is already wired by `howl-render/build.zig:126-152` under `benchmark:render`; benchmark timing that survives should live there, not in active render runtime owners.

## Block-Level Inventory And Actions

### 1. `howl-render/src/surface/emitter.zig`

- `emitter.zig:21-25` `monotonicNs()`.
  Classification: stale migration residue.
  Action: delete.
  Reason: exists only to feed debug timings; no runtime invariant depends on wall-clock time in emitter.
- `emitter.zig:27-183` `DebugEmitPreparedTiming` with env-var gate, counters, nested timing buckets, and periodic `std.debug.print`.
  Classification: stale migration residue.
  Action: delete.
  Reason: env-var-gated profiling and aggregate counters in a runtime owner are explicitly debug-shaped noise.
- `emitter.zig:185` global `debug_emit_prepared_timing`.
  Classification: stale migration residue.
  Action: delete.
  Reason: global mutable observation state has no render-surface contract consequence.
- `emitter.zig:278-283` `EmitPreparedPassTotals` carrying only timing bucket values.
  Classification: stale migration residue.
  Action: delete; make `appendPreparedPass` return `Error!void`.
  Reason: result wrapper exists only to move timing observations up to `emitPrepared`.
- `emitter.zig:293-310` timing in `emitPrepared`: copy-in/copy-out/publish clocks and debug record call.
  Classification: stale migration residue.
  Action: delete timing locals and record call; retain copy/rollback pattern, assertions, publish call, and returned surface.
- `emitter.zig:313-325` timing in `emitPreparedFresh`.
  Classification: stale migration residue.
  Action: delete zero timing locals, publish clock, and record call; retain resource rollback, append pass, assertions, publish call, and returned surface.
- `emitter.zig:328-360` timing shape inside `appendPreparedPass`.
  Classification: stale migration residue.
  Action: delete fill/sprite timing locals and totals; keep ordered passes exactly: reset, full damage, full redraw clear, clears, backgrounds, decorations, sprites, cursors.
- `emitter.zig:560-691` `appendPreparedSprites` timing parameter and per-step timing increments.
  Classification: stale migration residue.
  Action: delete `sprite_totals` parameter and all `monotonicNs()` timing locals/increments; retain `sprite_count`-independent runtime logic, resource admissions, staging, assertions, command append, and retire behavior.
- `emitter.zig:841-913` `publishSurface` returns `DebugEmitPreparedTiming.PublishTotals` and measures fixup/span phases.
  Classification: stale migration residue.
  Action: change return type to `void`, delete `totals` locals and timing writes, keep glyph pointer fixup, upload pointer fixup, span publication, and all assertions.
- `emitter.zig:187-191`, `242-252`, `362-384`, `404-416`, `614-616`, `660-662`, `726-727`, `744`, `783-786`, `801-802`, `849-856`, `894-910` assertions and bounds.
  Classification: runtime truth.
  Action: retain as runtime truth.

### 2. `howl-render/src/render_session.zig`

- `render_session.zig:40-44` `monotonicNs()`.
  Classification: stale migration residue.
  Action: delete after all local timing uses are removed.
- `render_session.zig:46-112` `DebugPrepareTiming` with env-var gate, aggregate counters, and periodic `std.debug.print`.
  Classification: stale migration residue.
  Action: delete.
- `render_session.zig:114` global `debug_prepare_timing`.
  Classification: stale migration residue.
  Action: delete.
- `render_session.zig:245` `ResolveObservability` local.
  Classification: runtime truth.
  Action: retain as runtime truth.
  Reason: stored in `PreparedSurface.resolve` at `render_session.zig:328-339`; this is render output metadata, not timing.
- `render_session.zig:257-259` ensure-preparer timing.
  Classification: stale migration residue.
  Action: delete timing locals; call `ensureTextPreparer` directly.
- `render_session.zig:267-269` direct path mutates `direct.timings.session_preparer_us` before ownership.
  Classification: stale migration residue.
  Action: delete timing mutation; retain direct prepared ownership and mutex unlock.
- `render_session.zig:276-288` input/prepare-cells timing and mutations into `prepared.timings`.
  Classification: stale migration residue.
  Action: delete timing locals and mutations; retain scratch capacity, source-to-text input conversion, cell preparation, `errdefer`, ownership, and mutex unlock.
- `render_session.zig:544-567` `prepareHandle` timing around `prepareSurface`, owner creation, `prepare_timings`, and debug record.
  Classification: stale migration residue.
  Action: delete timing locals, `prepare_timings`, and debug record; retain consume/retry behavior, prepared lifetime, mutex assertion, handle create, and `rdr_sfc_handle` assignment.
- `render_session.zig:160-163` `SubmitResult`.
  Classification: runtime truth.
  Action: retain as runtime truth.
  Reason: host surface and damage result are runtime ABI/session consequences.
- `render_session.zig:478-490` submit decision union.
  Classification: runtime truth.
  Action: retain as runtime truth.

Adjacent cleanup required for this slice to be real, not cosmetic:

- `howl-render/src/text/direct_normal.zig:22` `Product.timings` field.
  Classification: benchmark-only scaffolding in runtime owner.
  Action: delete from runtime; do not move sideways into another runtime owner.
  Reason: `Product` is the direct-normal runtime result. Its true payload is damage, raster outputs, and output ownership; timing is observation-only and is copied only into higher-level timing buckets.
- `howl-render/src/text/direct_normal.zig:33-40` `Timings` struct.
  Classification: benchmark-only scaffolding in runtime owner.
  Action: delete from runtime; do not replace with a new runtime timing struct.
  Reason: all fields are elapsed phase observations, not direct-normal state or invariants.
- `howl-render/src/text/direct_normal.zig:122`, `127`, `136`, `139-150`, `151` direct-normal phase timing in `prepare`.
  Classification: benchmark-only scaffolding in runtime owner.
  Action: delete timing local, phase clocks, elapsed writes, and timing argument to `finishScene`; keep damage setup, scratch reset, append visible path, rejection assertions, background/clear/decoration/cursor appends, and return path.
- `howl-render/src/text/direct_normal.zig:514-546` `finishScene` timing parameter, `final_timings`, raster clock, raster timing write, returned `.timings`, `monotonicNs`, and `elapsedUs`.
  Classification: benchmark-only scaffolding in runtime owner.
  Action: delete timing parameter and helpers; `finishScene` should return `Product` with only runtime payload.
- `howl-render/src/text/surface_preparer.zig:25-44` `PrepareTimings`.
  Classification: benchmark-only scaffolding in runtime owner.
  Action: delete from runtime. Benchmark must not keep these fields alive through `OwnedPreparedTextSurface`; if detailed phase measurement is needed later, it requires a separately planned benchmark-owned design that does not put timing fields on runtime products.
  Reason: `render_session.zig` consumes this only for debug printing; `benchmark_main.zig` also reads these fields, so deleting only `DebugPrepareTiming` leaves benchmark scaffolding in product runtime.
- `surface_preparer.zig:46-54`, `121-132`, `142-155`, `166-180`, `190-205`, `210-219`, `263-294`, `338-360`, `429-479`, `535-588` timing locals and timing propagation.
  Classification: benchmark-only scaffolding in runtime owner.
  Action: delete from runtime; retain counters, lane reports, assertions, scratch capacity, direct/complex path decisions, and owned prepared surface contents.
- `howl-render/src/benchmark_main.zig:32-76`, `884`, `896-906`, `1001-1023`, `1055-1080`, `1152-1233` current benchmark reads of runtime `PrepareTimings`.
  Classification: benchmark-only scaffolding.
  Action: delete the detailed per-phase fields/prints that depend on runtime timing payloads. Keep benchmark-owned outer duration (`ns`), allocation, fill/glyph/upload counts, and throughput. Do not move direct-normal phase timing into another runtime file.

### 3. `howl-linux-host/src/terminal/surface.zig`

- `surface.zig:70-94` `TurnResult` timing/upload-stat fields.
  Classification: stale migration residue, except `work_before`, `work_after`, `prepared`, `step`, and `present_snapshot_seq` are runtime truth.
  Action: delete `prepare_ns`, `upload_ns`, `upload_count`, `upload_bytes`, `upload_fill_count`, `upload_sprite_count`, `upload_glyph_run_count`, `upload_glyph_count`, all `*_ns` upload dispatch/draw fields, and `retained_submit_ns`; retain runtime progress fields.
- `surface.zig:397-427` propagation of timing/upload-stat fields from `DriveResult` into `TurnResult`.
  Classification: stale migration residue for timing/stat assignments; runtime truth for lock, work state, drive call, step, prepared, and present snapshot.
  Action: delete timing/stat assignments only.
- `surface.zig:544-566` `DriveResult` timing/upload-stat fields.
  Classification: stale migration residue, except `prepared`, `step`, and `present_snapshot_seq` are runtime truth.
  Action: delete timing/stat fields.
- `surface.zig:590-598` `prepare_start_ns`, `prepare_end_ns`, `prepare_ns` and passing timing to result helpers.
  Classification: stale migration residue.
  Action: delete timing locals; return idle/failed/prepared decisions without duration.
- `surface.zig:657-681` upload and retained-submit clocks plus `UploadStats` local.
  Classification: stale migration residue.
  Action: delete clocks and stats; backend upload should return only success/failure; retained submit should return runtime result and snapshot.
- `surface.zig:684-704` `SubmitPreparedResult` timing/upload-stat fields.
  Classification: stale migration residue, except `result` and `snapshot_seq` are runtime truth.
  Action: delete all timing/stat fields.
- `surface.zig:706-779` idle/failed/stale/submitted helper signatures and zeroed timing/stat fields.
  Classification: stale migration residue for timing/stat plumbing; runtime truth for step/result/snapshot helpers.
  Action: simplify helpers to carry only step/result/snapshot.
- `surface.zig:789-813` `submitDriveResult` timing/stat propagation.
  Classification: stale migration residue for timing/stat propagation; runtime truth for `prepared`, `step`, `present_snapshot_seq`.
  Action: simplify to the runtime fields.
- `surface.zig:1027-1033` testing exposure for failed/stale helpers with timing/stat arguments.
  Classification: proof-only scaffolding for stale migration residue.
  Action: update or delete matching test-only wrappers after runtime helpers are simplified.
- `surface.zig:442-445` `noteRenderTurn` behavior.
  Classification: runtime truth.
  Action: retain; remove no assertions.

Adjacent cleanup required for this slice to be real:

- `howl-linux-host/src/display/render_surface.zig:17-38` `UploadStats`.
  Classification: stale migration residue.
  Action: delete unless a benchmark root owns an explicit measurement path outside runtime.
- `render_surface.zig:40-59` optional `upload_stats` argument.
  Classification: stale migration residue.
  Action: remove optional stats parameter and pass no observation sink into resource/command realization.
- `howl-linux-host/src/display/render_surface_resources.zig:29-47`, `160-185` `upload_stats` generic plumbing and `note` call.
  Classification: stale migration residue.
  Action: delete stats parameter and note call; retain upload validation, GL upload, and resource metadata commits.
- `howl-linux-host/src/display/render_surface_commands.zig:132-218` `upload_stats` generic plumbing and per-command timing/count increments.
  Classification: stale migration residue.
  Action: delete stats parameter, clocks, and increments; retain command classification, GL dispatch, and draw calls.
- `howl-linux-host/src/event.zig:98-101` embeds `TurnResult` in `RenderFrame`.
  Classification: runtime truth.
  Action: retain structurally; compile will require no timing field reads because none were found outside tests.

### 4. `howl-render/src/surface/realizer.zig`

- `realizer.zig:37-85` `realize`, `realizeRetained`, `realizeWithStore`.
  Classification: runtime truth.
  Action: retain as runtime truth.
  Reason: validates surface, copies or clears base pixels, executes commands, and commits retained resources.
- `realizer.zig:87-334` validation blocks.
  Classification: runtime truth.
  Action: retain as runtime truth.
  Reason: these are safety checks and ABI/surface invariants, not diagnostics.
- `realizer.zig:336-461` draw loops and blending.
  Classification: runtime truth.
  Action: retain as runtime truth.
- `realizer.zig:463-788` span, resource, visibility, bounds, byte-size, pixel-index, and color helpers.
  Classification: runtime truth.
  Action: retain as runtime truth.
  Research result: no debug-shaped timing structs, env-var profiling branches, measurement counters, diagnostic result wrappers, or observation-only helper surfaces found in this file.

## Current Proof Roots

- Workspace aggregate checks: `build.zig:20-31` wires package `check` and `test`; `build.zig:34-49` wires unit, ABI, and integration aggregates.
- Render package proof roots: `howl-render/build.zig:87-101` defines `test`, `test:unit`, and `test:abi`; `howl-render/build.zig:123-124` makes `check` depend on the FFI library and test build; `howl-render/build.zig:126-152` defines `benchmark:render` and builds the benchmark under `check`.
- Render unit root: `howl-render/src/test_unit.zig:1-12` imports `surface/realizer_test.zig`, `surface/emitter_test.zig`, `surface/handle_test.zig`, `render_session.zig`, and other render unit owners.
- Render ABI root: `howl-render/src/test_abi.zig:4-11` imports ABI tests; `test_abi.zig:13-64` checks exported C entrypoints, enum values, and struct sizes.
- Emitter direct proof: `howl-render/src/surface/emitter_test.zig` is imported by `test_unit.zig:3` and exercises emitted surfaces through `realizer.zig`.
- Realizer direct proof: `howl-render/src/surface/realizer_test.zig` is imported by `test_unit.zig:2` and covers clear/fill/sprite/glyph/retained validation cases.
- Render session direct proof: inline tests in `howl-render/src/render_session.zig:762-938`, imported by `test_unit.zig:6`.
- Surface preparer/direct-normal proof route: `howl-render/src/render_session.zig` imports `text/surface_preparer.zig`, and `surface_preparer.zig:4` imports `text/direct_normal.zig`; render unit root `test_unit.zig:6` imports `render_session.zig`, so inline tests in `surface_preparer.zig:1034-1168` and `direct_normal.zig:592-614` are covered by `zig build test:unit`.
- Direct-normal direct proof blocks: `howl-render/src/text/direct_normal.zig:592-605` proves zero codepoint fast candidate behavior; `direct_normal.zig:607-614` proves unsupported non-printables fall back out of the fast path.
- Benchmark build proof for timing cleanup: `howl-render/build.zig:126-152` builds `howl-render/src/benchmark_main.zig` under `benchmark:render:build`; `howl-render/build.zig:152` also makes package `check` depend on benchmark build.
- Host package proof roots: `howl-linux-host/build.zig:62-72` defines `check`, `test`, `test:unit`, and `test:integration`; `howl-linux-host/build.zig:233-335` wires unit and integration test artifacts.
- Host test root: `howl-linux-host/src/host_test_root.zig:9-14` imports `display/render_surface_test.zig` and `terminal/surface_test.zig`.
- Host integration root: `howl-linux-host/src/integration_test_root.zig:1-8` imports host roots including `TerminalSurface`.
- Host terminal surface direct proof: `howl-linux-host/src/terminal/surface_test.zig`; timing/stat-specific expectations at `surface_test.zig:518-588` must be deleted or rewritten when runtime fields are removed.
- Host render surface direct proof: `howl-linux-host/src/display/render_surface_test.zig`; classification/resource proof remains relevant after deleting stats.

## Ordered Sprint Slice Plan

### Slice 1: Clean `howl-render/src/surface/emitter.zig`

- Accountable session ids: orchestrator `orch-2026-06-14-runtime-debug-noise-01`, researcher `research-2026-06-14-runtime-debug-noise-01`, reviewer `review-2026-06-14-runtime-debug-noise-01`, coder session id to be assigned by orchestrator.
- Allowed files: `howl-render/src/surface/emitter.zig`, `howl-render/src/surface/emitter_test.zig` only if compile/test expectations require access changes.
- Required shape: no `monotonicNs`, no `DebugEmitPreparedTiming`, no env-var gate, no timing totals, no timing result wrappers, no debug global, no timing parameters. `emitPrepared`, `emitPreparedFresh`, `appendPreparedPass`, `appendPreparedSprites`, and `publishSurface` must read as direct runtime transformations with existing assertions preserved.
- Exact tests: `zig build test:unit -- surface/emitter` from `howl-render`; `zig build test:unit` from `howl-render`; `zig build test:abi` from `howl-render` if public compile shape changes indirectly affect ABI tests.
- Non-goals: no ABI header changes; no resource admission redesign; no benchmark migration; no deletion of assertions; no new debug/helper/types files.
- Stop conditions: if removing timing requires changing render-surface ABI structs, stop; if a test only proves deleted timing, delete/rewrite that test in the allowed test file rather than preserving timing; if unrelated formatter churn touches other render files, stop and ask orchestrator.
- Required receipt fields: planning seed receipt, accepted planning receipt, coder session id, reviewer verdict, verification commands/results, commit hash after orchestrator acceptance.

### Slice 2: Clean `howl-render/src/render_session.zig` And Runtime Prepare Timing Plumbing

- Accountable session ids: orchestrator `orch-2026-06-14-runtime-debug-noise-01`, researcher `research-2026-06-14-runtime-debug-noise-01`, reviewer `review-2026-06-14-runtime-debug-noise-01`, coder session id to be assigned by orchestrator.
- Allowed files: `howl-render/src/render_session.zig`, `howl-render/src/text/surface_preparer.zig`, `howl-render/src/text/direct_normal.zig`, `howl-render/src/benchmark_main.zig`.
- Required shape: delete `DebugPrepareTiming`, `monotonicNs`, debug global, `prepareHandle` timing, `prepareSurface` timing, and timing mutations. Delete `surface_preparer.PrepareTimings` from runtime prepared-surface ownership. Delete `direct_normal.Timings` from `Product` and direct-normal runtime return paths. Update `benchmark_main.zig` by removing detailed per-phase fields/prints that depended on runtime timing payloads, while retaining benchmark-owned outer duration, allocation, fill/glyph/upload counts, and throughput. Preserve `ResolveObservability`, counters, lane reports, scratch capacity, mutex lock/unlock discipline, prepared ownership, and submit decisions.
- Exact tests: `zig build test:unit -- render session` from `howl-render`; `zig build test:unit -- direct normal` from `howl-render`; `zig build test:unit` from `howl-render`; `zig build benchmark:render:build` from `howl-render`; `zig build check` from `howl-render` because `check` builds benchmark and FFI.
- Non-goals: no renderer architecture redesign; no C ABI header changes; no change to font resolution semantics; no deletion of counters that are runtime aggregate state unless proved observation-only and covered by this slice; no hidden compatibility aliases for removed timing fields.
- Stop conditions: if any file outside the four allowed files needs content changes, stop and reseed exact file scope; if benchmark requirements cannot be satisfied without keeping timing fields in runtime owners, stop for reviewer/user decision; if `OwnedPreparedTextSurface` shape changes cascade into unrelated text owners beyond timing removal, stop and reseed exact owner scope; if assertions around mutex/prepared ownership are at risk, stop.
- Required receipt fields: planning seed receipt, accepted planning receipt, exact decision for benchmark timing ownership, coder session id, reviewer verdict, verification commands/results, commit hash after orchestrator acceptance.

### Slice 3: Clean `howl-linux-host/src/terminal/surface.zig` And Host Upload Stats Plumbing

- Accountable session ids: orchestrator `orch-2026-06-14-runtime-debug-noise-01`, researcher `research-2026-06-14-runtime-debug-noise-01`, reviewer `review-2026-06-14-runtime-debug-noise-01`, coder session id to be assigned by orchestrator.
- Allowed files: `howl-linux-host/src/terminal/surface.zig`, `howl-linux-host/src/terminal/surface_test.zig`, `howl-linux-host/src/display/render_surface.zig`, `howl-linux-host/src/display/render_surface_commands.zig`, `howl-linux-host/src/display/render_surface_resources.zig`, `howl-linux-host/src/display/render_surface_test.zig` only if compile/test expectations require stats signature changes.
- Required shape: `TurnResult`, `DriveResult`, and `SubmitPreparedResult` carry runtime decision facts only: work before/after, prepared flag, step, present snapshot, submit result, snapshot sequence. Delete upload timing, upload counts/bytes, dispatch/draw timings, retained-submit timing, `UploadStats`, optional stats sinks, and clocks. Preserve render action, present blocking, stale-handle checks, GL upload behavior, resource metadata commits, and assertions.
- Exact tests: `zig build test:unit -- terminal surface` from `howl-linux-host`; `zig build test:unit -- render surface` from `howl-linux-host`; `zig build test:unit` from `howl-linux-host`; `zig build test:integration` from `howl-linux-host`; `zig build check` from `howl-linux-host`.
- Non-goals: no host runtime architecture redesign; no presentation cadence changes; no SDL/GL resource policy changes; no new profiler/debug/metrics file; no ABI header changes.
- Stop conditions: if any non-test runtime caller requires upload timing/count fields for behavior, stop and classify that caller before proceeding; if GL upload correctness starts depending on observation structs, stop; if deletion would weaken present/submitted ordering assertions, stop.
- Required receipt fields: planning seed receipt, accepted planning receipt, coder session id, reviewer verdict, verification commands/results, commit hash after orchestrator acceptance.

### Slice 4: Verify `howl-render/src/surface/realizer.zig` Is Pristine Runtime Truth

- Accountable session ids: orchestrator `orch-2026-06-14-runtime-debug-noise-01`, researcher `research-2026-06-14-runtime-debug-noise-01`, reviewer `review-2026-06-14-runtime-debug-noise-01`, coder session id to be assigned by orchestrator.
- Allowed files: none for editing. Read-only inspection of `howl-render/src/surface/realizer.zig` is allowed.
- Required shape: no-op verification only. Coder must inspect and confirm no timing structs, env-var profiling, measurement counters, diagnostic wrappers, or observation-only helpers remain. Assertions, validation, retained resource checks, and drawing helpers remain untouched.
- Exact tests: `zig build test:unit -- realizer` from `howl-render`; prior slice `zig build test:unit` from `howl-render` remains supporting proof.
- Non-goals: no validation weakening; no CPU realizer performance rewrite; no retained resource redesign; no test fixture cleanup.
- Stop conditions: if coder or reviewer finds a real debug-only block missed by research, stop with no edits and reseed exact block action before any `realizer.zig` change; if any proposed deletion is an invariant or ABI validation, stop.
- Required receipt fields: planning seed receipt, accepted planning receipt, coder session id, reviewer verdict, verification commands/results, commit hash after orchestrator acceptance or explicit no-op receipt if no code change is made.

## Risks And Proof Gaps

- Risk: restricting execution to only the four primary files would leave stale timing scaffolding in `direct_normal.zig`, `surface_preparer.zig`, `benchmark_main.zig`, `display/render_surface.zig`, `render_surface_commands.zig`, and `render_surface_resources.zig`. That would be fake cleanup because target files currently consume those observation surfaces.
- Risk: `howl-render/src/benchmark_main.zig` currently expects detailed prepare timing fields. This repaired plan chooses reduced benchmark output: retain benchmark-owned outer duration/allocation/count observations and delete detailed runtime phase timing rather than move `direct_normal.Timings` sideways.
- Risk: host tests currently assert timing/stat propagation in `surface_test.zig:518-588`. Those tests should be deleted or rewritten to assert runtime result shape, not preserve noise.
- Proof gap: no execution diff exists yet, so final allowed-file lists may need reviewer pressure if compile errors reveal additional timing-only dependents. Stop conditions above require escalation rather than broad opportunistic edits.
- Proof gap: Alacritty contains a render timer debug feature, but it is explicit UI debug configuration (`display/mod.rs:1328-1347`), not env-var profiling through renderer ownership. This supports deletion from Howl runtime paths; it does not justify moving the same noise sideways into new runtime files.

## Readiness Judgment

- Ready for reviewer planning review with one hard condition: Slice 2 and Slice 3 must be accepted with the adjacent allowed files named above, or the sprint will leave debug-shaped scaffolding in runtime under different names.
- Not ready for coder execution until reviewer accepts this plan and orchestrator seeds exact slice contracts with coder session ids and receipt fields.
