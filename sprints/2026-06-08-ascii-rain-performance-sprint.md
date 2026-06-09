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

- reviewer session id: `rev-2026-06-09-ascii-rain-workflow-01`
- active researcher session id for next bottleneck shape: `research-2026-06-09-alacritty-bottleneck-01`

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
  - `research/cache-2026-06-08-ascii-rain-benchmark-surface.md`

4. `normal-fill-class-proof` — next coder slice
- allowed files:
  - `howl-render/src/text/direct_normal.zig`
  - `howl-render/src/prepared/render_surface_emitter.zig`
  - `howl-render/src/benchmark_main.zig` only if needed for proof output
- required shape:
  - separate ordinary normal-path background work from clears, decorations, and cursor work
  - prove which fill commands are semantically required vs ordinary tax on the normal path
  - reduce no behavior yet unless a proof-only reduction is inseparable from the measurement surface
- required tests:
  - `cd howl-render && zig build test:unit`
  - `cd howl-render && zig build benchmark:render -- --runs 20`
  - direct host receipt on the existing ASCII-rain harness
- non-goals:
  - no host GL changes
  - no ABI reshaping
  - no `utils/tools/*`
  - no broad renderer redesign
- stop condition:
  - receipts identify whether ordinary normal backgrounds dominate the remaining fill-command tax strongly enough to justify the next implementation slice

5. `normal-background-inband-reduction` — queued, conditional on slice 4 proof
- allowed files:
  - `howl-render/src/text/direct_normal.zig`
  - `howl-render/src/prepared/render_surface_emitter.zig`
  - adjacent owner-true tests only if required
- required shape:
  - move ordinary normal-path background handling toward the text path where source-backed proof permits
  - keep explicit rect emission for clears, decorations, cursor, and non-text cases that cannot honestly stay in-band
- required tests:
  - same as slice 4 plus direct host comparison against accepted receipts
- non-goals:
  - no host GL path work
  - no new runtime layer
  - no umbrella renderer abstraction
- stop condition:
  - lower `render_upload_fill_count_avg`
  - lower `render_upload_fill_avg_us`
  - no crash

6. `host-buffered-rect-path` — queued only if slice 5 lands cleanly and host upload remains a real secondary owner
- allowed files:
  - `howl-linux-host/src/display/renderer/render_surface.zig`
  - host-side owner-true tests only if required
- required shape:
  - follow Alacritty `renderer/rects.rs` pressure toward buffered rect submission
  - keep policy out of the host GL layer
- required tests:
  - `cd howl-linux-host && zig build test:unit`
  - `cd howl-linux-host && zig build install -Doptimize=ReleaseFast`
  - direct host receipt on the existing ASCII-rain harness
- non-goals:
  - no PTY/runtime redesign
  - no Python-tool changes
  - no ABI reshaping
- stop condition:
  - clean direct-host improvement after renderer command-count reductions have already landed

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
