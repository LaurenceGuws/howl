# Runtime Debug Noise Cleanup Sprint

Status:

- Active execution sprint contract.
- Orchestrator session id: `orch-2026-06-14-runtime-debug-noise-01`.
- Researcher session id: `research-2026-06-14-runtime-debug-noise-01`.
- Reviewer session id: `review-2026-06-14-runtime-debug-noise-01`.
- Planning seed receipt: `e7a90db` `Seed runtime debug-noise planning`.
- Accepted planning receipt: `1ccaddd` `Accept runtime debug-noise planning`.
- Sprint seed receipt: pending orchestrator commit.

Problem:

- Remove observation-only timing/accounting/debug posture from active runtime owners.
- Preserve runtime truth, assertions, bounds, ABI behavior, proof roots, and owner-true state.
- Prefer deletion over relocation. Measurement needed by benchmarks must be benchmark-owned, not runtime-owned.

Primary target order:

1. `howl-render/src/surface/emitter.zig`
2. `howl-render/src/render_session.zig`
3. `howl-linux-host/src/terminal/surface.zig`
4. `howl-render/src/surface/realizer.zig`

Global non-goals:

- No ABI header changes without explicit re-approval.
- No new `debug.zig`, `metrics.zig`, `instrumentation.zig`, `helpers.zig`, `types.zig`, or bucket files.
- No sideways relocation of debug-shaped noise into another runtime owner.
- No assertion, bound, validation, lifecycle, or ownership weakening.
- No architecture redesign unless a seeded stop condition forces reseeding.

## Slice 1: Clean `howl-render/src/surface/emitter.zig`

- Coder session id: `coder-2026-06-14-runtime-debug-noise-slice-01`.
- Allowed files: `howl-render/src/surface/emitter.zig`, `howl-render/src/surface/emitter_test.zig` only if compile/test expectations require access changes.
- Required shape: no `monotonicNs`, no `DebugEmitPreparedTiming`, no env-var gate, no timing totals, no timing result wrappers, no debug global, no timing parameters. `emitPrepared`, `emitPreparedFresh`, `appendPreparedPass`, `appendPreparedSprites`, and `publishSurface` must read as direct runtime transformations with existing assertions preserved.
- Exact tests: from `howl-render`, run `zig build test:unit -- surface/emitter`, `zig build test:unit`, and `zig build test:abi` if public compile shape changes indirectly affect ABI tests.
- Non-goals: no ABI header changes; no resource admission redesign; no benchmark migration; no deletion of assertions; no new debug/helper/types files.
- Stop conditions: if removing timing requires changing render-surface ABI structs, stop; if a test only proves deleted timing, delete/rewrite that test in the allowed test file rather than preserving timing; if unrelated formatter churn touches other render files, stop and ask orchestrator.
- Required receipt fields: planning seed receipt `e7a90db`, accepted planning receipt `1ccaddd`, coder session id, reviewer verdict, verification commands/results, commit hash after orchestrator acceptance.

## Slice 2: Clean `howl-render/src/render_session.zig` And Runtime Prepare Timing Plumbing

- Coder session id: `coder-2026-06-14-runtime-debug-noise-slice-02`.
- Allowed files: `howl-render/src/render_session.zig`, `howl-render/src/text/surface_preparer.zig`, `howl-render/src/text/direct_normal.zig`, `howl-render/src/benchmark_main.zig`.
- Required shape: delete `DebugPrepareTiming`, `monotonicNs`, debug global, `prepareHandle` timing, `prepareSurface` timing, and timing mutations. Delete `surface_preparer.PrepareTimings` from runtime prepared-surface ownership. Delete `direct_normal.Timings` from `Product` and direct-normal runtime return paths. Update `benchmark_main.zig` by removing detailed per-phase fields/prints that depended on runtime timing payloads, while retaining benchmark-owned outer duration, allocation, fill/glyph/upload counts, and throughput. Preserve `ResolveObservability`, counters, lane reports, scratch capacity, mutex lock/unlock discipline, prepared ownership, and submit decisions.
- Exact tests: from `howl-render`, run `zig build test:unit -- render session`, `zig build test:unit -- direct normal`, `zig build test:unit`, `zig build benchmark:render:build`, and `zig build check`.
- Non-goals: no renderer architecture redesign; no C ABI header changes; no change to font resolution semantics; no deletion of counters that are runtime aggregate state unless proved observation-only and covered by this slice; no hidden compatibility aliases for removed timing fields.
- Stop conditions: if any file outside the four allowed files needs content changes, stop and reseed exact file scope; if benchmark requirements cannot be satisfied without keeping timing fields in runtime owners, stop for reviewer/user decision; if `OwnedPreparedTextSurface` shape changes cascade into unrelated text owners beyond timing removal, stop and reseed exact owner scope; if assertions around mutex/prepared ownership are at risk, stop.
- Required receipt fields: planning seed receipt `e7a90db`, accepted planning receipt `1ccaddd`, exact decision for benchmark timing ownership, coder session id, reviewer verdict, verification commands/results, commit hash after orchestrator acceptance.

## Slice 3: Clean `howl-linux-host/src/terminal/surface.zig` And Host Upload Stats Plumbing

- Coder session id: `coder-2026-06-14-runtime-debug-noise-slice-03`.
- Allowed files: `howl-linux-host/src/terminal/surface.zig`, `howl-linux-host/src/terminal/surface_test.zig`, `howl-linux-host/src/display/render_surface.zig`, `howl-linux-host/src/display/render_surface_commands.zig`, `howl-linux-host/src/display/render_surface_resources.zig`, `howl-linux-host/src/display/render_surface_test.zig` only if compile/test expectations require stats signature changes.
- Required shape: `TurnResult`, `DriveResult`, and `SubmitPreparedResult` carry runtime decision facts only: work before/after, prepared flag, step, present snapshot, submit result, snapshot sequence. Delete upload timing, upload counts/bytes, dispatch/draw timings, retained-submit timing, `UploadStats`, optional stats sinks, and clocks. Preserve render action, present blocking, stale-handle checks, GL upload behavior, resource metadata commits, and assertions.
- Exact tests: from `howl-linux-host`, run `zig build test:unit -- terminal surface`, `zig build test:unit -- render surface`, `zig build test:unit`, `zig build test:integration`, and `zig build check`.
- Non-goals: no host runtime architecture redesign; no presentation cadence changes; no SDL/GL resource policy changes; no new profiler/debug/metrics file; no ABI header changes.
- Stop conditions: if any non-test runtime caller requires upload timing/count fields for behavior, stop and classify that caller before proceeding; if GL upload correctness starts depending on observation structs, stop; if deletion would weaken present/submitted ordering assertions, stop.
- Required receipt fields: planning seed receipt `e7a90db`, accepted planning receipt `1ccaddd`, coder session id, reviewer verdict, verification commands/results, commit hash after orchestrator acceptance.

## Slice 4: Verify `howl-render/src/surface/realizer.zig` Is Pristine Runtime Truth

- Coder session id: `coder-2026-06-14-runtime-debug-noise-slice-04`.
- Allowed files: none for editing. Read-only inspection of `howl-render/src/surface/realizer.zig` is allowed.
- Required shape: no-op verification only. Coder must inspect and confirm no timing structs, env-var profiling, measurement counters, diagnostic wrappers, or observation-only helpers remain. Assertions, validation, retained resource checks, and drawing helpers remain untouched.
- Exact tests: from `howl-render`, run `zig build test:unit -- realizer`; prior slice `zig build test:unit` from `howl-render` remains supporting proof.
- Non-goals: no validation weakening; no CPU realizer performance rewrite; no retained resource redesign; no test fixture cleanup.
- Stop conditions: if coder or reviewer finds a real debug-only block missed by research, stop with no edits and reseed exact block action before any `realizer.zig` change; if any proposed deletion is an invariant or ABI validation, stop.
- Required receipt fields: planning seed receipt `e7a90db`, accepted planning receipt `1ccaddd`, coder session id, reviewer verdict, verification commands/results, commit hash after orchestrator acceptance or explicit no-op receipt if no code change is made.
