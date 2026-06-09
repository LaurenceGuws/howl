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
