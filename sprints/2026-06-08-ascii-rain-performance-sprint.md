ASCII rain performance sprint

Date: 2026-06-08.
Status: active.
Orchestrator session id: orch-2026-06-08-ascii-rain-performance-01.

User direction:

- Full sprint goal: keep iterating on measured bottlenecks until Howl is faster than Alacritty on the agreed ASCII rain benchmark.
- Accountability is the main priority.
- The orchestrator should drive autonomously until a real blocker is reached or the sprint is complete.
- For this sprint, bottleneck proof comes before reference-led correction. References still govern fix shape once the bottleneck is pinned down.
- Slices do not need to be tiny. They must be accountable.

Problem statement:

- Howl is materially slower than the reference terminals on the current ASCII rain workload. The sprint needs a reproducible benchmark, telemetry receipts, measured bottlenecks, accountable fix slices, and repeated re-measurement until Howl exceeds Alacritty on the same benchmark contract.

Primary benchmark contract:

- Benchmark launcher: `utils/tools/benchmark_terminals.py`
- Stress generator: `utils/tools/zig-out/harness/ascii_rain_stress_release_fast`
- Default mode for completion proof: `ascii`
- Initial terminal set for direct completion gate: `howl`, `alacritty`
- Default workload shape for current baseline:
  - `--duration 10`
  - `--cols 320`
  - `--rows 120`
  - `--frames 100000000`
  - `--seed 0xC0FFEE`
  - `--metrics-every 100`
  - `--flush-every 1`
- Build posture:
  - `zig build install -Doptimize=ReleaseFast` in `howl-linux-host`
  - `zig build stress:rain:build -Doptimize=ReleaseFast` in `utils/tools`
- Diagnostic telemetry:
  - benchmark run directory under `artifacts/stress/`
  - generator metrics from stderr
  - `summary.json`
  - resource sampler NDJSON
  - optional `HOWL_TRACE_PATH` for Howl-only diagnostic runs
  - optional profiler host binary built through `zig build profile`

Completion gate:

- The sprint is complete only when a receipted benchmark run proves Howl is faster than Alacritty on the agreed ASCII workload and environment.
- “Faster” must be stated with exact metrics from the benchmark receipt, not by impression.

Execution model:

- First loop: pin down the benchmark surface, collect baseline receipts, and identify the dominant bottleneck.
- Later loops: choose the smallest accountable fix that actually resolves the measured bottleneck, then re-measure against the same benchmark.
- Fix slices may be broad if the bottleneck demands broad change, but every slice still needs exact allowed files, tests, non-goals, stop conditions, review, verification, and receipts.

Accepted planning and review sessions:

- original reviewer session id for the completed bottleneck-proof queue: `rev-2026-06-09-ascii-rain-workflow-01`
- original researcher session id for bottleneck/reference shape: `research-2026-06-09-alacritty-bottleneck-01`
- active reviewer session id for the ownership-correction queue: `rev-2026-06-09-owner-delete-plan-01`
- active researcher session id for the ownership-correction queue: `research-2026-06-09-owner-delete-plan-01`

Sequential slice queue:

1. `baseline-and-owner-proof` — completed
- purpose:
  - benchmark contract
  - Howl vs Alacritty baseline
  - direct host accounting
  - top owner proof
- receipts:
  - `artifacts/stress/20260608-232747-ascii/summary.json`
  - `artifacts/stress/20260608-235810-ascii-direct/howl-direct.accounting.log`

2. `renderer-owner-proof` — completed
- purpose:
  - split `prepareSurface`, `Owner.create`, `direct_normal`, and host upload cost
  - confirm PTY/runtime are not the bottleneck
- receipts:
  - `artifacts/stress/20260609-prepare-handle-timing-3/howl-term.stderr.log`
  - `artifacts/stress/20260609-070618-direct-normal-shape-1/howl-term.stderr.log`
  - `artifacts/stress/20260609-081249-host-command-shape-1/howl-term.stderr.log`

3. `alacritty-shape-research` — completed
- purpose:
  - map the current measured hot path to Alacritty’s content/text/rect renderer organization
  - identify the smallest reference-backed next slice
- receipt:
  - `research/done/cache-2026-06-08-ascii-rain-benchmark-surface.md`

4. `owner-delete-plan` — completed
- purpose:
  - prove that `howl-render/src/prepared/owner.zig` is style debt, not an owner-true seam
  - map exact replacement ownership and exact sequential deletion slices
- receipt:
  - `research/owner-delete-plan-2026-06-09.md`

5. `owner-map-landing` — completed
- allowed files:
  - `howl-render/src/prepared/handle.zig`
  - `howl-render/src/prepared/surface.zig`
  - `howl-render/src/prepared/render_surface_emitter.zig`
  - `howl-render/src/session/text.zig`
  - `howl-render/src/ffi/handle.zig`
  - `howl-render/src/prepared/owner_test.zig`
  - `howl-render/src/ffi/prepared_surface_test.zig`
  - `howl-render/src/ffi/test_support.zig`
  - `howl-render/src/test/unit/root.zig` only if needed to keep the curated root honest
- required shape:
  - introduce `PreparedHandle`
  - move prepared metadata truth to `prepared/surface.zig`
  - move emission-failure ownership to `prepared/render_surface_emitter.zig`
  - rewire `TextSessionOwner` handle storage to the new owner
  - keep `prepared/owner.zig` only as a temporary shim if strictly necessary
- required tests:
  - `cd howl-render && zig build test:unit`
- non-goals:
  - no host GL work
  - no benchmark-tool changes
  - no ABI reshaping
  - no performance claims from this slice
- stop condition:
  - no caller still needs metadata or emission-failure ownership from `prepared/owner.zig`
- accepted result:
  - `PreparedInfo` and `PreparedBuffer` moved to `prepared/surface.zig`
  - emission failure ownership moved to `prepared/render_surface_emitter.zig`
  - `TextSessionOwner` handle storage moved to `*prepared_handle.PreparedHandle`
  - `prepared/owner.zig` reduced to a temporary compatibility shim
- receipt:
  - `howl-render` commit `3c786f7` `split prepared handle metadata ownership`

6. `session-submit-choreography` — completed
- allowed files:
  - `howl-render/src/session/text.zig`
  - `howl-render/src/prepared/handle.zig`
  - `howl-render/src/ffi/submission.zig`
  - related owner-true tests/support only
- required shape:
  - move publish/submit state policy and execution into `TextSessionOwner`
  - keep `PreparedHandle` as storage/liveness only
  - keep FFI translation-only
- required tests:
  - `cd howl-render && zig build test:unit`
- non-goals:
  - no ABI changes
  - no host-side renderer work
- stop condition:
  - submit policy no longer lives in the prepared-handle file
- accepted result:
  - publish/submit policy moved into `TextSessionOwner`
  - `ffi/submission.zig` became translation-only
  - `PreparedHandle` no longer owns submit policy
- receipt:
  - `howl-render` commit `0ee034a` `move prepared submit policy to session`

7. `prepared-surface-boundary-cleanup` — completed
- allowed files:
  - `howl-render/src/ffi/prepared_surface.zig`
  - `howl-render/src/ffi/handle.zig`
  - `howl-render/src/prepared/handle.zig`
  - `howl-render/src/prepared/surface.zig`
  - `howl-render/src/prepared/render_surface_emitter.zig`
  - related owner-true tests/support only
- required shape:
  - describe reads `PreparedSurface` metadata helpers
  - render-surface failure mapping comes from the emitter owner
  - no FFI file imports `prepared/owner.zig`
- required tests:
  - `cd howl-render && zig build test:unit`
- non-goals:
  - no ABI changes
  - no performance-only edits
- stop condition:
  - `ffi/*` no longer depends on `prepared/owner.zig`
- accepted result:
  - `ffi/prepared_surface.zig` no longer imports `prepared/owner.zig`
  - prepared-surface FFI uses `PreparedHandle`, `PreparedSurface`, and emitter-owned failure mapping directly
  - the shim is isolated to itself plus owner tests
- receipt:
  - `howl-render` commit `590694b` `remove prepared owner from ffi surface`

8. `delete-owner-zig` — completed
- allowed files:
  - `howl-render/src/prepared/handle.zig`
  - `howl-render/src/prepared/surface.zig`
  - `howl-render/src/prepared/render_surface_emitter.zig`
  - `howl-render/src/session/text.zig`
  - `howl-render/src/ffi/prepared_surface.zig`
  - `howl-render/src/ffi/submission.zig`
  - `howl-render/src/ffi/handle.zig`
  - `howl-render/src/prepared/owner_test.zig`
  - related owner-true tests/support only
  - delete `howl-render/src/prepared/owner.zig`
- required shape:
  - final tree has no `Owner` seam for prepared-surface lifecycle
  - tests are split by true owner instead of one bucket-owner test file
- required tests:
  - `cd howl-render && zig build test:unit`
  - `cd howl-render && rg 'owner\\.zig|\\bOwner\\b' src -n -S`
- non-goals:
  - no further optimisation work in the same slice
- stop condition:
  - `prepared/owner.zig` is gone and no retained dependency on it remains
- accepted result:
  - `prepared/owner.zig` deleted
  - owner tests rewritten against the real seams
  - compatibility aliasing removed entirely
- receipt:
  - `howl-render` commit `5c812b8` `delete prepared owner shim`

9. `post-owner-performance-rebaseline` — completed
- purpose:
  - rerun the accepted benchmark/accounting receipts on the cleaned seam after deleting `prepared/owner.zig`
  - prove the new hot owner order on the cleaned seam before queuing the next fix
- accepted result:
  - clean benchmark moved to Howl `79.42 fps` vs Alacritty `1039.12 fps`
  - direct host run moved to `109.56 fps`
  - post-delete hot order is now:
    1. `PreparedHandle.create` / render-surface emission
    2. `direct_normal` scan
    3. host fill playback tail
- receipts:
  - `artifacts/stress/20260609-115340-ascii/summary.json`
  - `artifacts/stress/20260609-095340-ascii-direct-post-owner/howl-direct.accounting.log`
  - `artifacts/stress/20260609-095743-ascii-direct-post-owner-timing/howl-term.stderr.log`

10. `emitter-alpha-reuse-fast-path` — rejected
- purpose:
  - remove measured false steady-state work from the cleaned emitter/resource-cache seam
- rejected execution:
  - reviewer session id: `rev-2026-06-09-post-owner-performance-01`
  - coder session id: `coder-2026-06-09-emitter-alpha-reuse-fast-path-01`
- rejection reason:
  - the probe removed staged upload work but replaced it with a worse per-query prepared-sprite byte hash
  - real benchmark and direct host receipts regressed, so the slice is dropped
- restart point:
  - restart from researcher correction for the next slice premise, not from another coder pass on the same shape

11. `post-owner-performance-research-restart` — active
- purpose:
  - correct the next-slice premise after the rejected alpha-reuse probe
  - decide whether the next valid cut remains in emitter/resource-store or switches to `direct_normal`
- current authority:
  - `loops/done/post-owner-performance-research-restart.txt`
  - `research/post-owner-performance-restart-2026-06-09.md`
- accepted result:
  - the next valid slice is `direct-normal-scan-reduction`
  - the emitter/resource-store seam stays owner-true, but no longer has a source-backed next-cut premise

12. `direct-normal-scan-reduction` — next slice
- purpose:
  - reduce repeated normal-path candidate-walk and append work inside `direct_normal`
- allowed files:
  - `howl-render/src/text/direct_normal.zig`
  - `howl-render/src/text/prepare_counters.zig` only if needed for proof fields
  - `howl-render/src/benchmark_main.zig` only if needed for proof output
- required shape:
  - reduce repeated candidate-walk / append work inside `direct_normal`
  - preserve current normal-path eligibility and visible-span behavior
  - leave emitter/resource-store, session, FFI, and host GL untouched
- required tests:
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:unit`
  - `cd /home/home/personal/projects/howl/howl-render && zig build benchmark:render -- --runs 20` if proof output changes
  - `cd /home/home/personal/projects/howl/howl-linux-host && zig build install -Doptimize=ReleaseFast`
  - rerun fresh direct host timing receipt
  - rerun fresh clean Howl vs Alacritty benchmark receipt
- non-goals:
  - no ownership refactor unless the slice exposes a new false owner
  - no emitter/resource-store work
  - no `session/text.zig`
  - no `ffi/*`
  - no host GL work
- stop conditions:
  - stop if implementation needs files outside the allowed set
  - stop if a new bucket seam is exposed
  - stop if the slice needs emitter/session/host reshaping
  - stop if receipts regress against the accepted post-owner baseline

Autonomy rule for this sprint:

- The orchestrator should continue without routine check-ins.
- Stop only for:
  - a real benchmark/profiling surface blocker that cannot be reconstructed safely,
  - a reference conflict that requires explicit override,
  - result ambiguity that would make the next slice dishonest,
  - sprint completion.

Receipts required for every accepted loop:

- loop artifact path
- research artifact path when research was used
- reviewer session id
- coder/worker session id
- verification commands and results
- benchmark receipt paths
- final decision by orchestrator session id
