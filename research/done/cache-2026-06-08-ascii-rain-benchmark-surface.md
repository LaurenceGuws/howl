# ASCII Rain Benchmark Surface Research

Date: 2026-06-08.
Role: researcher.
Status: active.
Loop: `loops/ascii-rain-baseline-bottleneck.txt`.
Primary researcher session id: `research-2026-06-09-alacritty-bottleneck-01`.

## Sources Read In Order

1. `/home/home/personal/projects/howl/loop/flow.md`
2. `/home/home/personal/projects/howl/loop/researcher.md`
3. `/home/home/personal/projects/howl/sprints/current.txt`
4. `/home/home/personal/projects/howl/loops/ascii-rain-baseline-bottleneck.txt`
5. Navigation-only grep over `/home/home/personal/projects/howl/research/done`
6. `/home/home/personal/projects/howl/howl-linux-host/stress.md`
7. `/home/home/personal/projects/howl/utils/tools/benchmark_terminals.py`
8. `/home/home/personal/projects/howl/sprints/2026-06-08-ascii-rain-performance-sprint.md`
9. `/home/home/personal/projects/howl/utils/tools/build.zig`
10. `/home/home/personal/projects/howl/utils/tools/ascii_rain_stress.zig`
11. `/home/home/personal/projects/howl/build.zig`
12. `/home/home/personal/projects/howl/howl-linux-host/build.zig`
13. `/home/home/personal/projects/howl/howl-linux-host/src/main.zig`
14. `/home/home/personal/projects/howl/howl-linux-host/src/cli/args.zig`
15. `/home/home/personal/projects/howl/howl-linux-host/src/app/processor.zig`
16. `git show 47dbe56:src/app/process_accounting.zig`
17. `git show 47dbe56:src/main.zig`
18. `git log --all -S 'howl-runtime.jsonl'`
19. `/home/home/personal/projects/howl/howl-linux-host/assets/default_config/init.lua`
20. `/home/home/personal/projects/howl/artifacts/stress/20260608-232747-ascii/summary.json`
21. `/home/home/personal/projects/howl/artifacts/stress/20260608-232747-ascii/howl-ascii.resources.ndjson`

## Current-Code Facts

- The active sprint names the benchmark launcher as `utils/tools/benchmark_terminals.py`, the stress generator as `utils/tools/zig-out/harness/ascii_rain_stress_release_fast`, the default mode as `ascii`, and the direct completion terminals as `howl` and `alacritty` (`/home/home/personal/projects/howl/sprints/2026-06-08-ascii-rain-performance-sprint.md:19-24`).
- The active sprint’s default workload is `--duration 10 --cols 320 --rows 120 --frames 100000000 --seed 0xC0FFEE --metrics-every 100 --flush-every 1` (`/home/home/personal/projects/howl/sprints/2026-06-08-ascii-rain-performance-sprint.md:25-32`).
- The loop explicitly requires: build the ReleaseFast host and stress harnesses, run one clean `howl` + `alacritty` baseline, then run one Howl-only diagnostic trace only if needed (`/home/home/personal/projects/howl/loops/ascii-rain-baseline-bottleneck.txt:21-44`).
- `howl-linux-host/stress.md` says host-side proof must use `../utils/tools/benchmark_terminals.py` before ad hoc profiling, and it documents the same staged build posture and benchmark launcher commands (`/home/home/personal/projects/howl/howl-linux-host/stress.md:7-12`, `/home/home/personal/projects/howl/howl-linux-host/stress.md:28-34`, `/home/home/personal/projects/howl/howl-linux-host/stress.md:77-92`).
- The launcher defaults match the sprint workload: `duration=10.0`, `mode=ascii`, `cols=320`, `rows=120`, `frames=100_000_000`, `seed=0xC0FFEE`, `metrics_every=100`, `flush_every=1`, and terminal choices include `howl` and `alacritty` (`/home/home/personal/projects/howl/utils/tools/benchmark_terminals.py:30-57`).
- The launcher writes its output under `artifacts/stress/` by default (`/home/home/personal/projects/howl/utils/tools/benchmark_terminals.py:43`, `/home/home/personal/projects/howl/utils/tools/benchmark_terminals.py:703-705`).
- The run directory name is generated at execution time as `YYYYMMDD-HHMMSS-<mode>`, so the exact path is not knowable before the run. The path pattern is `/home/home/personal/projects/howl/artifacts/stress/<timestamp>-ascii/` for the loop’s default mode (`/home/home/personal/projects/howl/utils/tools/benchmark_terminals.py:703-705`).
- The launcher builds the stress command as the staged stress binary plus `--cols`, `--rows`, `--frames`, `--duration-ms`, `--seed`, mode, metrics flags, and `2> <metrics_path>` redirection (`/home/home/personal/projects/howl/utils/tools/benchmark_terminals.py:505-520`).
- The stress generator emits deterministic stdout for a fixed config and emits structured metrics to stderr when `--metrics` is enabled (`/home/home/personal/projects/howl/utils/tools/ascii_rain_stress.zig:97-150`, `/home/home/personal/projects/howl/utils/tools/ascii_rain_stress.zig:156-187`).
- The staged stress artifact name is `ascii_rain_stress_release_fast`; `utils/tools/build.zig` installs it under `zig-out/harness/` when `stress:rain:build` runs (`/home/home/personal/projects/howl/utils/tools/build.zig:25-27`, `/home/home/personal/projects/howl/utils/tools/build.zig:32-45`, `/home/home/personal/projects/howl/utils/tools/build.zig:70-74`, `/home/home/personal/projects/howl/utils/tools/build.zig:92-103`).
- The top-level build maps stress commands through `utils/tools` only; this loop should not invent another stress entrypoint (`/home/home/personal/projects/howl/build.zig:56-66`).
- The host build has a dedicated `profile` step that installs `howl_term_profile`, but the current active loop does not require a profile binary yet. The host release-fast binary already accepts `--duration-ms` and `--command`, which is enough to drive the same workload directly for internal accounting (`/home/home/personal/projects/howl/howl-linux-host/build.zig:33-39`, `/home/home/personal/projects/howl/howl-linux-host/build.zig:52-67`, `/home/home/personal/projects/howl/howl-linux-host/src/cli/args.zig:3-10`, `/home/home/personal/projects/howl/howl-linux-host/src/main.zig:19-29`).
- Current host startup wires almost all execution through `Processor` after CLI parsing and startup. That makes `src/app/processor.zig` the true owner for loop-turn accounting in the current tree (`/home/home/personal/projects/howl/howl-linux-host/src/main.zig:87-108`, `/home/home/personal/projects/howl/howl-linux-host/src/app/processor.zig:102-194`).
- Current host CLI already exposes explicit debug accounting opt-in, and current startup already wires it into the loop owner. That accepted host accounting path is now part of the live tree and is no longer a planning gap.
- The repository previously had a bounded `src/app/process_accounting.zig` owner and direct loop integration. Commit `47dbe56` shows the exact old shape: explicit enable flag, periodic logging interval, loop counters, wait/render/present/SDL pump counters, and `/proc/self` thread sampling with no background thread. That shape was later removed, but it is direct proof that the host can support bounded internal accounting without inventing a runtime layer.
- Current source does not contain any live owner for `HOWL_TRACE_PATH`, process-accounting flags, or process-accounting log output. The only current trace-path reference outside the Python launcher is a commented config example in `assets/default_config/init.lua` (`/home/home/personal/projects/howl/howl-linux-host/assets/default_config/init.lua:79-83`).

## Exact Execution Commands

Build posture required by the active loop:

```sh
cd /home/home/personal/projects/howl/howl-linux-host
zig build install -Doptimize=ReleaseFast
```

```sh
cd /home/home/personal/projects/howl/utils/tools
zig build stress:rain:build -Doptimize=ReleaseFast
```

Clean baseline receipt command required by the active loop:

```sh
cd /home/home/personal/projects/howl
python3 utils/tools/benchmark_terminals.py --duration 10 --mode ascii --terminals howl alacritty
```

Direct host diagnostic command shape for the current loop, after the accounting flags are restored:

```sh
cd /home/home/personal/projects/howl/howl-linux-host
./zig-out/harness/howl_term_release_fast \
  --duration-ms 12000 \
  --debug-process-accounting \
  --debug-log-every-ms 1000 \
  --command "sh -lc '/home/home/personal/projects/howl/utils/tools/zig-out/harness/ascii_rain_stress_release_fast --cols 320 --rows 120 --frames 100000000 --duration-ms 10000 --seed 0xC0FFEE --mode ascii --metrics --metrics-every 100 --flush-every 1 2> /home/home/personal/projects/howl/artifacts/stress/<timestamp>-ascii/howl-direct-ascii.metrics.ndjson'" \
  > /home/home/personal/projects/howl/artifacts/stress/<timestamp>-ascii/howl-direct.stdout.log \
  2> /home/home/personal/projects/howl/artifacts/stress/<timestamp>-ascii/howl-direct.accounting.log
```

This direct command shape stays inside current host owners. It preserves the exact ASCII rain generator contract but bypasses the launcher for diagnostic ownership proof, which matches the user’s explicit direction for this sprint.

## Exact Output Artifact Paths

The run directory is created as:

- `/home/home/personal/projects/howl/artifacts/stress/<timestamp>-ascii/`

Within that run directory, the launcher writes:

- Clean Howl metrics:
  - `/home/home/personal/projects/howl/artifacts/stress/<timestamp>-ascii/howl-ascii.metrics.ndjson`
- Clean Alacritty metrics:
  - `/home/home/personal/projects/howl/artifacts/stress/<timestamp>-ascii/alacritty-ascii.metrics.ndjson`
- Howl resource samples:
  - `/home/home/personal/projects/howl/artifacts/stress/<timestamp>-ascii/howl-ascii.resources.ndjson`
- Alacritty resource samples:
  - `/home/home/personal/projects/howl/artifacts/stress/<timestamp>-ascii/alacritty-ascii.resources.ndjson`
- Run summary:
  - `/home/home/personal/projects/howl/artifacts/stress/<timestamp>-ascii/summary.json`

For the direct host diagnostic loop, the expected artifacts are:

- `/home/home/personal/projects/howl/artifacts/stress/<timestamp>-ascii/howl-direct-ascii.metrics.ndjson`
- `/home/home/personal/projects/howl/artifacts/stress/<timestamp>-ascii/howl-direct.stdout.log`
- `/home/home/personal/projects/howl/artifacts/stress/<timestamp>-ascii/howl-direct.accounting.log`

The benchmark launcher remains the source of the baseline comparison receipt under `summary.json`. The direct host run exists only to pin the current internal owner path honestly.

## Telemetry Surface

- Generator telemetry comes from the stress generator’s stderr `stress_metrics` records with schema `1`, final flag, frame count, `fps`, and `p50_us`/`p95_us`/`p99_us`/`max_us` latencies (`/home/home/personal/projects/howl/utils/tools/ascii_rain_stress.zig:166-187`).
- The launcher validates completion by reading the last `stress_metrics` record from each metrics file and requiring `schema == 1` and `final == true` (`/home/home/personal/projects/howl/utils/tools/benchmark_terminals.py:573-628`).
- Process-tree resource telemetry is sampled into NDJSON by the launcher, but current receipts showed only start/end snapshots and did not identify a hot owner path. For this active loop, that launcher telemetry is supporting context only, not the primary proof surface.
- The old host accounting owner in commit `47dbe56` logged:
  - loop-turn counters
  - wait-admission counters
  - terminal keep/redraw/drive counters
  - render-step counters
  - present-submission counters
  - SDL wait/poll counters
  - per-thread CPU deltas from `/proc/self/task/*/stat`
- Those old counters align well with current `Processor.runLoopTurn()` structure, because the current owner still centralizes the same decision classes: event pumping, runtime progress, render permission, present submission, and present completion.

## Environment Readiness Facts

- `python3`, `zig`, and `alacritty` are present in the current environment.
- The staged harness binaries already exist at:
  - `/home/home/personal/projects/howl/howl-linux-host/zig-out/harness/howl_term_release_fast`
  - `/home/home/personal/projects/howl/utils/tools/zig-out/harness/ascii_rain_stress_release_fast`

These checks prove the loop has no immediate binary-availability blocker for the seeded baseline commands or for a direct host diagnostic run.

## Owner Mapping For Internal Accounting

- Current `Processor.runLoopTurn()` is the narrowest true owner for internal bottleneck accounting in the live tree. It already centralizes:
  - wait admission computation
  - SDL/event-loop pumping
  - host-owned mutation drain
  - runtime progress driving
  - render permission gating
  - render invocation
  - present submission
  - present completion draining
- Current startup in `src/main.zig` owns CLI-to-processor wiring. That is the right place to create the accounting state and pass it into `Processor`.
- Current CLI parsing in `src/cli/args.zig` is the right place for explicit `--debug-process-accounting` and `--debug-log-every-ms` opt-in flags.
- The previously attempted host-side fill batching path in `src/display/renderer/render_surface.zig` has already been rejected and dropped from the live tree. Current host evidence should therefore be read against the accepted command-shape instrumentation state, not against an assumed live batching experiment.

## Proof Gaps

1. The direct accounting run path still relies on shell redirection naming rather than an owner-true artifact contract inside the host binary.
2. The exact final artifact directory name cannot be stated before execution because the benchmark receipt path depends on wall-clock time.
3. The benchmark-surface half of this file is now historical context; the live blocker is no longer “which owner is hot” but “which renderer/content reduction is reference-shaped enough for the next coder slice”.
4. The remaining proof gap for the next coder slice is classifying the ordinary normal-path fill tax more precisely without broadening into host GL or ABI redesign.

## Measured Receipts

- Clean baseline receipt:
  - run dir: `/home/home/personal/projects/howl/artifacts/stress/20260608-232747-ascii`
  - summary: `/home/home/personal/projects/howl/artifacts/stress/20260608-232747-ascii/summary.json`
  - Howl final metrics: `frames=187`, `fps=18.38`
  - Alacritty final metrics: `frames=10325`, `fps=1032.43`
- Direct host accounting receipt:
  - run dir: `/home/home/personal/projects/howl/artifacts/stress/20260608-235810-ascii-direct`
  - accounting log: `/home/home/personal/projects/howl/artifacts/stress/20260608-235810-ascii-direct/howl-direct.accounting.log`
  - direct metrics: `/home/home/personal/projects/howl/artifacts/stress/20260608-235810-ascii-direct/howl-direct-ascii.metrics.ndjson`
  - direct final metrics: `frames=39`, `fps=3.87`
  - internal proof:
    - `howl-main` stayed near `995-1002 cpu_milli`
    - `howl-term-host` stayed at `0-9 cpu_milli`
    - after startup, loop intervals showed essentially:
      - `wait_false ~= loop_turns`
      - `wait_false_runtime_wake ~= loop_turns`
      - `terminal_should_redraw ~= loop_turns`
      - `terminal_drive_performed ~= loop_turns`
      - `render_step_rendered ~= loop_turns`
    - `present_submitted ~= loop_turns`
    - that pins the current bottleneck class as main-thread render/present churn under continuous terminal redraw, not PTY-thread saturation and not wait-heavy pacing
- Accepted host upload-shape receipt:
  - run dir: `/home/home/personal/projects/howl/artifacts/stress/20260609-070303-host-upload-shape-1`
  - stderr log: `/home/home/personal/projects/howl/artifacts/stress/20260609-070303-host-upload-shape-1/howl-term.stderr.log`
  - metrics: `/home/home/personal/projects/howl/artifacts/stress/20260609-070303-host-upload-shape-1/howl-render.metrics.ndjson`
  - measured result: `frames=455`, `fps=45.42`
  - steady-state proof:
    - `render_upload_count_avg = 0`
    - `render_upload_bytes_avg = 0`
    - steady-state host upload is not texture upload churn
- Accepted direct-normal shape receipt:
  - run dir: `/home/home/personal/projects/howl/artifacts/stress/20260609-070618-direct-normal-shape-1`
  - stderr log: `/home/home/personal/projects/howl/artifacts/stress/20260609-070618-direct-normal-shape-1/howl-term.stderr.log`
  - metrics: `/home/home/personal/projects/howl/artifacts/stress/20260609-070618-direct-normal-shape-1/howl-render.metrics.ndjson`
  - measured result: `frames=462`, `fps=46.16`
  - steady-state proof:
    - `direct_normal_avg_us = 741-746`
    - `direct_normal_scan_avg_us = 675-679`
    - backgrounds, decorations, and raster are smaller secondary costs
- Accepted host command-shape receipt:
  - run dir: `/home/home/personal/projects/howl/artifacts/stress/20260609-081249-host-command-shape-1`
  - stderr log: `/home/home/personal/projects/howl/artifacts/stress/20260609-081249-host-command-shape-1/howl-term.stderr.log`
  - metrics: `/home/home/personal/projects/howl/artifacts/stress/20260609-081249-host-command-shape-1/howl-render.metrics.ndjson`
  - measured result: `frames=429`, `fps=42.83`
  - steady-state proof:
    - `render_upload_avg_us = 536-614`
    - `render_upload_fill_count_avg = 2294-2921`
    - `render_upload_fill_avg_us = 309-384`
    - `render_upload_glyph_avg_us = 79-130`
    - `render_upload_sprite_count_avg = 0`
  - defensible conclusion:
    - the remaining host upload cost is dominated by fill command playback, not texture uploads and not sprite playback
Howl resource receipts for the baseline run captured only two samples:

- first sample at process start with one live `howl-main` process and no computed CPU deltas
- second sample after process exit with `process_count=0`, `cpu_percent=0.0`, and no thread records

Receipt proof:

- clean summary result fields: `/home/home/personal/projects/howl/artifacts/stress/20260608-232747-ascii/summary.json`
- Howl resource events: `/home/home/personal/projects/howl/artifacts/stress/20260608-232747-ascii/howl-ascii.resources.ndjson`

## Measurement Blocker Analysis

- The launcher baseline proved the large performance gap, but it did not pin a current internal owner path strongly enough to justify a fix slice.
- The user explicitly rejected spending the next slice on wrapper repair, so the launcher’s weak diagnostic surface is now a non-authoritative side fact for this sprint.
- Current-code proof instead supports a direct host diagnostic move:
  - current host loop ownership is centralized in `Processor`
  - current CLI already supports direct workload execution through `--command`
  - previous host accounting code proves bounded internal logging is feasible in this product without a new runtime layer
- The direct host accounting receipt resolved that blocker. The next blocker is no longer “which owner is hot”; it is “what render-path change is strong enough and reference-shaped enough to remove the churn without destabilizing the host.”

## Failed Reduction Receipt

- A follow-up experimental reduction replaced glyph immediate-mode submission with GL client-side vertex arrays in `howl-linux-host/src/display/renderer/render_surface.zig`.
- That attempt is rejected.
- Receipt:
  - benchmark run dir: `/home/home/personal/projects/howl/artifacts/stress/20260609-000131-ascii`
  - summary: `/home/home/personal/projects/howl/artifacts/stress/20260609-000131-ascii/summary.json`
  - Howl outcome:
    - `returncode = -11`
    - `metrics_complete = false`
    - `duration_s = 0.529`
- Defensible conclusion:
  - client-array tricks are not an acceptable narrow fix on the current GL host path
  - the next render slice should be shaped more like Alacritty’s explicit buffered text renderer than a compatibility-profile shortcut
- A later fill-command batching probe in `howl-linux-host/src/display/renderer/render_surface.zig` is also rejected.
- Outcome:
  - instrumented run reached only `frames=441`, `fps=43.99`
  - clean verification regressed to `frames=347`, `fps=34.66`
- Defensible conclusion:
  - batching fills inside the current fixed-function host path is not an accepted improvement and remains dropped from the live tree

## Current Renderer Proof

- Host-side phase timing is now source-backed in the live tree through:
  - `howl-linux-host/src/terminal/context.zig`
  - `howl-linux-host/src/app/process_accounting.zig`
  - `howl-linux-host/src/app/processor.zig`
- Direct host timing receipt before the accepted renderer reduction:
  - run dir: `/home/home/personal/projects/howl/artifacts/stress/20260609-010018-ascii-direct`
  - accounting log: `/home/home/personal/projects/howl/artifacts/stress/20260609-010018-ascii-direct/howl-direct.accounting.log`
  - direct metrics: `/home/home/personal/projects/howl/artifacts/stress/20260609-010018-ascii-direct/howl-direct-ascii.metrics.ndjson`
  - measured result: `frames=39`, `fps=3.82`
  - steady-state timing proof:
    - `render_turn_avg_us ~= 8388-8721`
    - `render_prepare_avg_us ~= 7954-8185`
    - `render_upload_avg_us ~= 426-527`
    - `render_retained_submit_avg_us ~= 1`
    - `present_submit_avg_us ~= 118-136`
- Defensible conclusion:
  - most render-turn cost sits inside `howl-render` prepare
  - host GL upload/present are real but clearly secondary on this workload
- Later accepted host-upload diagnostics refined that secondary host work:
  - texture resource upload is near zero in steady state
  - host upload time is mostly playback of thousands of fill commands plus a smaller glyph draw tail
  - future host-side work should focus on render-surface command shape or command-count reduction, not atlas upload plumbing

- `howl-render` already had benchmark timing for `resolve`, `shape`, `group`, and `scene`, but the normal-only fast path was invisible because `direct_normal` time was not recorded.
- The live accepted renderer slice added `direct_normal_us` timing in:
  - `howl-render/src/text/frame_preparer.zig`
  - `howl-render/src/benchmark_main.zig`
- Benchmark receipt before the accepted renderer reduction:
  - `cd /home/home/personal/projects/howl/howl-render && zig build benchmark:render -- --runs 20`
  - `ascii_full`: `warm_median_ns=143696`, `warm_median_direct_normal_us=143`
  - `lsd_like_plain`: `warm_median_ns=370929`, `warm_median_direct_normal_us=370`
- Current-code proof in `howl-render/src/text/direct_normal.zig` showed a redundant full-source walk:
  - `prepare(...)` first called `countVisible(...)`
  - then called `appendVisible(...)`
  - both functions re-ran `sourceCandidate(...)` and `candidateDecision(...)` across the full source
  - `Scratch.reset(...)` did not actually use `visible_count` to size any fast-path arrays differently, so the first pass was pure tax on the normal-only path
- Accepted renderer reduction:
  - removed the redundant `countVisible(...)` pass
  - kept rejection behavior by letting `appendVisible(...)` return `false` on `Policy.require_all_normal` rejection
- Benchmark receipt after the accepted renderer reduction:
  - `cd /home/home/personal/projects/howl/howl-render && zig build benchmark:render -- --runs 20`
  - `ascii_full`: `warm_median_ns=62838`, `warm_median_direct_normal_us=62`
  - `lsd_like_plain`: `warm_median_ns=198834`, `warm_median_direct_normal_us=198`
  - `cell_text_ascii_full`: `warm_median_ns=61698`, `warm_median_direct_normal_us=61`
- End-to-end host receipt after the accepted renderer reduction:
  - run dir: `/home/home/personal/projects/howl/artifacts/stress/20260609-010535-ascii-direct`
  - accounting log: `/home/home/personal/projects/howl/artifacts/stress/20260609-010535-ascii-direct/howl-direct.accounting.log`
  - direct metrics: `/home/home/personal/projects/howl/artifacts/stress/20260609-010535-ascii-direct/howl-direct-ascii.metrics.ndjson`
  - measured result: `frames=40`, `fps=3.95`
- Real host prepare-handle split receipt:
  - run dir: `/home/home/personal/projects/howl/artifacts/stress/20260609-prepare-handle-timing-3`
  - stderr log: `/home/home/personal/projects/howl/artifacts/stress/20260609-prepare-handle-timing-3/howl-term.stderr.log`
  - final metrics: `/home/home/personal/projects/howl/artifacts/stress/20260609-prepare-handle-timing-3/howl-render.metrics.ndjson`
  - measured result: `frames=8`, `fps=4.03`
  - live host split:
    - `render_prepare_avg_us = 8359`
    - `prepare_surface_avg_us = 6216`
    - `owner_create_avg_us = 2088`
    - `input_avg_us = 508`
    - `session_preparer_avg_us = 3881`
    - `session_prepare_cells_avg_us = 1824`
    - `direct_normal_avg_us = 570`
- Accepted `FtHbSupport` metrics-cache reduction:

## Owner Delete Plan

Date: 2026-06-09.
Role: researcher.
Researcher session id: `research-2026-06-09-owner-delete-plan-01`.
Status: active planning research for a sprint-direction change.

### Sources Read In Order

1. `/home/home/personal/projects/howl/loop/flow.md`
2. `/home/home/personal/projects/howl/loop/researcher.md`
3. `/home/home/personal/projects/howl/sprints/current.txt`
4. `/home/home/personal/projects/howl/loops/ascii-rain-baseline-bottleneck.txt`
5. `/home/home/personal/projects/howl/research/cache-2026-06-08-ascii-rain-benchmark-surface.md`
6. `/home/home/personal/projects/howl/reference-index.md`
7. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
8. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
9. Current Howl source:
   - `/home/home/personal/projects/howl/howl-render/src/prepared/owner.zig`
   - `/home/home/personal/projects/howl/howl-render/src/prepared/surface.zig`
   - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
   - `/home/home/personal/projects/howl/howl-render/src/session/text.zig`
   - `/home/home/personal/projects/howl/howl-render/src/ffi/prepared_surface.zig`
   - `/home/home/personal/projects/howl/howl-render/src/ffi/submission.zig`
   - `/home/home/personal/projects/howl/howl-render/src/ffi/handle.zig`
   - `/home/home/personal/projects/howl/howl-render/src/prepared/owner_test.zig`
   - `/home/home/personal/projects/howl/howl-render/src/ffi/prepared_surface_test.zig`
   - `/home/home/personal/projects/howl/howl-render/src/ffi/test_support.zig`
10. Alacritty references:
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/mod.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs`

### Exact File And Line References

- `prepared/owner.zig` currently mixes:
  - debug timing: `/home/home/personal/projects/howl/howl-render/src/prepared/owner.zig:20-64`
  - exported metadata/failure types: `/home/home/personal/projects/howl/howl-render/src/prepared/owner.zig:66-93`
  - handle object state and lifecycle: `/home/home/personal/projects/howl/howl-render/src/prepared/owner.zig:95-180`
  - info/buffer/render-surface accessors: `/home/home/personal/projects/howl/howl-render/src/prepared/owner.zig:182-215`
  - submit validation and submit execution: `/home/home/personal/projects/howl/howl-render/src/prepared/owner.zig:217-249`
  - consume/release/deinit: `/home/home/personal/projects/howl/howl-render/src/prepared/owner.zig:251-284`
  - summary construction and failure mapping: `/home/home/personal/projects/howl/howl-render/src/prepared/owner.zig:287-316`
- `TextSessionOwner` already owns prepared-handle arrays and cached publish/submit handles in `/home/home/personal/projects/howl/howl-render/src/session/text.zig:430-444`.
- `TextSessionOwner.prepareHandle` already owns the prepare request consume, `session.prepareSurface`, and current handoff into `Owner.create` in `/home/home/personal/projects/howl/howl-render/src/session/text.zig:499-523`.
- `TextSessionOwner` already owns handle registration and cached-handle clearing in `/home/home/personal/projects/howl/howl-render/src/session/text.zig:525-533`.
- `PreparedSurface` already owns prepared render data and token derivation in `/home/home/personal/projects/howl/howl-render/src/prepared/surface.zig:7-43`.
- `render_surface_emitter.zig` already owns render-surface payload construction and bounded command/resource emission in `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig:117-240`, `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig:243-679`.
- FFI prepared-surface boundary currently depends on `Owner` for handle cast, liveness, metadata, surface access, and emission-failure mapping in `/home/home/personal/projects/howl/howl-render/src/ffi/prepared_surface.zig:21-80`.
- FFI submission boundary currently depends on `Owner` for belongs-to-session checks, state transitions, token validation, and submit execution in `/home/home/personal/projects/howl/howl-render/src/ffi/submission.zig:15-23`, `/home/home/personal/projects/howl/howl-render/src/ffi/submission.zig:57-70`, `/home/home/personal/projects/howl/howl-render/src/ffi/submission.zig:82-189`.
- FFI handle casts currently depend on `PreparedSurfaceHandle` from `owner.zig` in `/home/home/personal/projects/howl/howl-render/src/ffi/handle.zig:10-15`.
- Test roots directly encode `Owner` shape in:
  - `/home/home/personal/projects/howl/howl-render/src/prepared/owner_test.zig:1-262`
  - `/home/home/personal/projects/howl/howl-render/src/ffi/prepared_surface_test.zig:21-103`
  - `/home/home/personal/projects/howl/howl-render/src/ffi/test_support.zig:12-33`
  - `/home/home/personal/projects/howl/howl-render/src/ffi/test_support.zig:63-79`
- Alacritty keeps cell/content preparation separate from frame orchestration and renderer submission:
  - renderable cell filtering and empty-cell rule: `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:153-183`, `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:301-307`
  - display orchestration of clear, cell draw, rect collection, rect draw: `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:783-1008`
  - renderer root keeps drawing APIs only: `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/mod.rs:177-255`
  - text renderer keeps batching/draw-cell ownership only: `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:49-172`

### Current-Code Facts

- `prepared/owner.zig` is not a small owner. It holds one object that spans:
  - prepared data ownership
  - cached render-surface payload ownership
  - publish/submit/release lifecycle
  - C-handle casting target
  - submit validation against session and execution geometry
  - render-surface emission failure translation
  - debug timing
- The file name and symbol name are both weak under repo law. `Owner` is a generic bucket noun, and the file combines unrelated policy seams.
- The ABI does not require `Owner` as a concept. The ABI only requires:
  - an opaque prepared-surface handle
  - stable token/describe/render-surface calls
  - stable publish/submit/release choreography
- Current code already exposes natural owner seams:
  - prepared render data: `prepared/surface.zig`
  - render-surface emission: `prepared/render_surface_emitter.zig`
  - session-side prepare and submission orchestration: `session/text.zig`
  - FFI translation only: `ffi/prepared_surface.zig`, `ffi/submission.zig`, `ffi/handle.zig`

### Reference Facts

- Alacritty does not centralize content prep, frame orchestration, rect submission, and text draw batching inside a generic owner wrapper. The roles stay separate across `display/content.rs`, `display/mod.rs`, and `renderer/*`.
- TigerBeetle law is against vague ownership and broad containers. The current `Owner` symbol and mixed file responsibility are on the wrong side of that pressure. The style docs explicitly push toward small direct owners, centralized policy in the true parent, and bounded leaf helpers.

### Owner Roles And Proposed Shape

Exact split for deleting `prepared/owner.zig` safely:

1. `howl-render/src/prepared/surface.zig`
- Keep `PreparedSurface` as the prepared data owner.
- Move here:
  - `PreparedInfo`
  - `PreparedBuffer`
  - any pure metadata derivation now built by `ownerBase(...)`
- Add owner-true helpers on `PreparedSurface` for:
  - info export
  - upload-count truth
  - token/geometry summary needed by FFI
- Do not put lifecycle state here.

2. `howl-render/src/prepared/render_surface_emitter.zig`
- Keep bounded render-surface emission here.
- Move here:
  - `RenderSurfaceEmissionFailure`
  - `renderSurfaceEmissionFailureFromError(...)`
  - `RenderSurfacePayload` alias or equivalent emitter-owned payload type
- Keep emission failure mapping close to the emitting owner, not in a session/handle wrapper.
- Keep payload allocation-free semantics inside the emitter path where possible; the session/handle owner should only own the pointer lifecycle, not command construction rules.

3. New `howl-render/src/prepared/handle.zig`
- Replace `Owner` with a domain-true handle owner: `PreparedHandle`.
- This file should own only:
  - opaque prepared-handle storage
  - `State`
  - pointer to `TextSessionOwner`
  - owned `PreparedSurface`
  - optional emitted render-surface payload pointer
  - release/consume/liveness transitions
  - borrowed surface access
- This file should not own:
  - emission failure mapping logic
  - prepared metadata shaping
  - session submit policy
  - debug timing

4. `howl-render/src/session/text.zig`
- Expand `TextSessionOwner` to own the session-side handle choreography it already partially owns:
  - handle allocation from prepared surface
  - prepared-handle registration array
  - cached publish/submit handle slots
  - session-owned publish/submit transitions
  - session-side submit execution against `session.submitSurface(...)`
- Move submit policy out of `PreparedHandle.submit(...)` and `submitOwned(...)` into `TextSessionOwner` methods.
- Keep the session as the parent control-flow owner. That matches TigerBeetle pressure and the file’s current role.

5. `howl-render/src/ffi/handle.zig`
- Retain opaque C-handle casts only.
- Update casts from `PreparedSurfaceHandle`/`Owner` to `PreparedHandle`.
- Do not add policy here.

6. `howl-render/src/ffi/prepared_surface.zig`
- Keep C ABI translation only.
- Read metadata from `PreparedSurface` helpers through `PreparedHandle`.
- Read render-surface failure enum from `render_surface_emitter.zig` or its emitter-owned export, not from a bucket handle file.

7. `howl-render/src/ffi/submission.zig`
- Keep token parsing and C ABI statuses only.
- Delegate publish/submit state transitions to `TextSessionOwner` and `PreparedHandle`.
- Do not keep copied submit policy in the FFI layer.

### Exact Dependent Files That Must Change First

First-order source dependencies:

- `/home/home/personal/projects/howl/howl-render/src/session/text.zig`
- `/home/home/personal/projects/howl/howl-render/src/ffi/prepared_surface.zig`
- `/home/home/personal/projects/howl/howl-render/src/ffi/submission.zig`
- `/home/home/personal/projects/howl/howl-render/src/ffi/handle.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/surface.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`

First-order test dependencies:

- `/home/home/personal/projects/howl/howl-render/src/prepared/owner_test.zig`
- `/home/home/personal/projects/howl/howl-render/src/ffi/prepared_surface_test.zig`
- `/home/home/personal/projects/howl/howl-render/src/ffi/test_support.zig`

Second-order test fallout likely touched by symbol rename/choreography changes:

- `/home/home/personal/projects/howl/howl-render/src/test_abi.zig`
- any curated roots that import the three tests above through the ABI/unit suites

### Sprint Scratchpad

- The user changed sprint direction explicitly: delete `prepared/owner.zig` before more optimization.
- That is compatible with the references. Current `Owner` is style debt and a mixed-responsibility seam.
- The split must preserve the C ABI exactly. Handle type remains opaque C ABI; internal Zig owner shape can change.
- The split should not invent a new umbrella runtime or submission layer. Existing seams already exist and should absorb the responsibilities.

### Explicit Ordered Slice Plan

1. Slice: prove and land the new owner map without deletion yet
- Allowed files:
  - `howl-render/src/prepared/handle.zig`
  - `howl-render/src/prepared/surface.zig`
  - `howl-render/src/prepared/render_surface_emitter.zig`
  - `howl-render/src/session/text.zig`
  - `howl-render/src/ffi/handle.zig`
  - tests/support files needed for new symbols
- Shape:
  - introduce `PreparedHandle`
  - move metadata types to `surface.zig`
  - move emission failure mapping to `render_surface_emitter.zig`
  - keep old `owner.zig` as a compile-through shim only for one slice if needed
- Stop condition:
  - no call site needs `PreparedInfo`, `PreparedBuffer`, or emission-failure types from `owner.zig`

2. Slice: move session-side submit and lifecycle policy into `TextSessionOwner`
- Allowed files:
  - `howl-render/src/session/text.zig`
  - `howl-render/src/prepared/handle.zig`
  - `howl-render/src/ffi/submission.zig`
  - related tests/support
- Shape:
  - `PreparedHandle` keeps only state/liveness/storage
  - `TextSessionOwner` owns publish/submit transitions and execution
  - FFI submission becomes translation-only
- Stop condition:
  - submit policy no longer lives in the prepared-handle file

3. Slice: move prepared-surface describe/render-surface boundary to the new owners
- Allowed files:
  - `howl-render/src/ffi/prepared_surface.zig`
  - `howl-render/src/ffi/handle.zig`
  - `howl-render/src/prepared/handle.zig`
  - `howl-render/src/prepared/surface.zig`
  - `howl-render/src/prepared/render_surface_emitter.zig`
  - related tests/support
- Shape:
  - describe reads `PreparedSurface` metadata helpers
  - render-surface failure mapping comes from emitter owner
  - handle cast layer uses `PreparedHandle`, not `Owner`
- Stop condition:
  - no FFI file imports `prepared/owner.zig`

4. Slice: delete `prepared/owner.zig` and replace tests with owner-true coverage
- Allowed files:
  - delete `howl-render/src/prepared/owner.zig`
  - delete or rename `howl-render/src/prepared/owner_test.zig`
  - update imports in affected files
- Shape:
  - final compile tree has no `Owner` symbol and no `owner.zig`
  - tests are split by true owner:
    - prepared-handle lifecycle tests
    - prepared-surface metadata tests
    - render-surface emission failure mapping tests
    - FFI prepared-surface boundary tests
    - FFI submission choreography tests
- Stop condition:
  - `rg 'owner\\.zig|\\bOwner\\b' howl-render/src` returns only unrelated words or none for this seam

5. Slice: only after deletion, resume performance work on the cleaned seam
- This is outside the current research request and should not start until reviewer acceptance of the deletion plan and the deletion slices.

### Required Assertions

- Assert positive/negative lifecycle transitions on `PreparedHandle`:
  - prepared -> published allowed
  - published -> submit_ready allowed
  - released/consumed are terminal
  - invalid transitions fail explicitly
- Assert session ownership at the session boundary, not only at FFI entry.
- Assert prepared token equality/mismatch separately from execution-geometry equality.
- Assert that render-surface emission failure mapping remains one-to-one with emitter errors after the split.

### Required Tests

- Prepared-handle lifecycle tests:
  - liveness before/after release
  - consume clears cached handles
  - release/consume do not double free payload/prepared surface
- Prepared-surface metadata tests:
  - info and upload-count truth remain correct after moving types/helpers to `surface.zig`
- Emitter tests:
  - all emission errors map to stable ABI-facing failure enums
- FFI prepared-surface tests:
  - describe still returns stable ABI layout
  - render-surface retrieval still maps all failure statuses correctly
- FFI submission tests:
  - publish/submit/take-submit-handle choreography remains stable
  - stale/missing/mismatched token cases remain rejected

### Explicit Non-Goals

- No performance optimization in this planning change.
- No publication-background semantic fix in this planning change.
- No host GL changes.
- No ABI signature changes.
- No new umbrella runtime/submission layer.
- No Python tooling work.

### Risks

- The current test support and FFI tests directly instantiate `Owner`; they will break early in the split and must move with the owner map, not after.
- `TextSessionOwner.destroy()` currently destroys all prepared handles through the `Owner` API. That teardown path must stay safe while the split is in flight.
- If the split leaves submit policy half in FFI and half in the session owner, the result will be worse than the current bucket.

### Proof Gaps

- I have not yet mapped the exact curated unit-test roots that pull `owner_test.zig` into `zig build test:unit`; execution planning should confirm that root before seeding coder slices.
- I have not yet proposed exact new file names beyond `prepared/handle.zig`; reviewer may still reject that name if another narrower domain noun emerges during planning review.

### Readiness Judgment

- This is ready for reviewer gating as planning research.
- The evidence is strong enough to treat deletion of `prepared/owner.zig` as the next sprint queue, not an optional cleanup.
- The split can preserve the C ABI without keeping the current bucket owner alive.
  - owner path: `howl-render/src/text/font/ft_hb/support.zig`

## Alacritty Bottleneck Shape Research

Date: 2026-06-09.
Role: researcher.
Researcher session id: `research-2026-06-09-alacritty-bottleneck-01`.
Scope: source-backed mapping of the current measured Howl hot owners to Alacritty, focused on render/content/display organization and the smallest accountable next slice.

### Sources Read In Order

1. `/home/home/personal/projects/howl/loop/flow.md`
2. `/home/home/personal/projects/howl/loop/researcher.md`
3. `/home/home/personal/projects/howl/sprints/current.txt`
4. `/home/home/personal/projects/howl/loops/ascii-rain-baseline-bottleneck.txt`
5. `/home/home/personal/projects/howl/research/cache-2026-06-08-ascii-rain-benchmark-surface.md`
6. `/home/home/personal/projects/howl/reference-index.md`
7. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
8. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
9. `/home/home/personal/projects/howl/howl-render/src/prepared/owner.zig`
10. `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
11. `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
12. `/home/home/personal/projects/howl/howl-render/src/session/text.zig`
13. `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`
14. `/home/home/personal/projects/howl/howl-linux-host/src/display/renderer/render_surface.zig`
15. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs`
16. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/damage.rs`
17. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs`
18. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/mod.rs`
19. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/rects.rs`
20. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs`
21. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs`
22. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glsl3.rs`
23. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/gles2.rs`

### Current-Code Facts

- `howl-render/src/session/text.zig` keeps prepare ownership in `TextSession.prepareSurface(...)`, with current timing split around `ensureTextPreparer`, publication mapping, direct-normal preparation, and `prepared_owner.Owner.create(...)` (`howl-render/src/session/text.zig:220-240`).
- `howl-render/src/prepared/owner.zig` makes `Owner.create(...)` the retained-surface owner: allocate owner, register handle, then emit the render-surface payload (`howl-render/src/prepared/owner.zig:95-140`).
- `howl-render/src/prepared/render_surface_emitter.zig` converts prepared scene data into ABI commands. The hot path is still a full fill/sprite/cursor emission pass inside `emitPreparedFresh(...)` (`howl-render/src/prepared/render_surface_emitter.zig:210-231`).
- Fill work is emitted as one command per clear/background/decoration/cursor rectangle, with only same-row horizontal merging in `tryMergePreparedFillCommand(...)` (`howl-render/src/prepared/render_surface_emitter.zig:288-329`, `howl-render/src/prepared/render_surface_emitter.zig:357-376`).
- `howl-render/src/text/direct_normal.zig` still performs a full source scan in `appendVisible(...)`, then separately emits background, clear, decoration, and cursor draw lists from the accumulated renderable cells (`howl-render/src/text/direct_normal.zig:110-140`, `howl-render/src/text/direct_normal.zig:178-210`).
- The publication path already imports Alacritty-like empty-cell semantics at the cell-map boundary: `mapPublicationCellInput(...)` marks a cell empty only when it is a plain space with transparent default background and no styling (`howl-render/src/source/publication_cell_map.zig:24-45`, `howl-render/src/source/publication_cell_map.zig:137-150`).
- `howl-linux-host/src/display/renderer/render_surface.zig` realizes uploads separately from command playback, then plays commands through multiple shape-specialized paths (`howl-linux-host/src/display/renderer/render_surface.zig:433-473`).
- The remaining host upload/playback cost is fill-dominated because `uploadRenderSurfaceCommands(...)` still executes one GL immediate-mode quad per fill command and one immediate-mode grouped loop per glyph-run command (`howl-linux-host/src/display/renderer/render_surface.zig:497-609`, `howl-linux-host/src/display/renderer/render_surface.zig:880-905`, `howl-linux-host/src/display/renderer/render_surface.zig:940-971`).

### Reference Facts

- Alacritty splits render preparation from renderer execution at the display layer. `Display` first collects `RenderableContent`, drains only non-empty cells, tracks line decorations, and then hands cells to the text renderer and rects to the rect renderer (`utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:783-881`, `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:895-1009`).
- Alacritty reduces content-preparation work before GL by skipping empty/background-only cells in `RenderableContent::next()`: only cursor cells or non-empty non-spacer cells become render items (`utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:156-184`).
- Alacritty also reduces rect work before GL by aggregating underline/strikeout spans into `RenderLines`, only materializing `RenderRect`s after the text-cell pass (`utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:839-881`, `utils/dev_references/terminals/alacritty/alacritty/src/renderer/rects.rs:158-227`).
- Alacritty further reduces frame scope with damage shaping. `DamageTracker` stores per-line and extra-rect damage, and converts that into bounded render rects rather than treating every frame as a full redraw (`utils/dev_references/terminals/alacritty/alacritty/src/display/damage.rs:16-103`, `utils/dev_references/terminals/alacritty/alacritty/src/display/damage.rs:138-202`).
- Alacritty does not realize backgrounds as standalone host-side fill commands for ordinary cells. Text rendering batches per-glyph instance data, and each instance carries both foreground and background color; the shader renders background and text in separate passes from the same batch (`utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:33-69`, `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glsl3.rs:223-260`, `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glsl3.rs:351-374`, `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/gles2.rs:395-420`).
- Alacritty’s text renderer batches by atlas texture and flushes only on texture change or batch capacity, not per cell (`utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:111-132`, `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glsl3.rs:223-260`, `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glsl3.rs:321-403`).
- Alacritty’s standalone rect path is explicit and buffered. `Renderer.draw_rects(...)` hands `Vec<RenderRect>` to `RectRenderer`, which builds vertex vectors and submits them through one VBO-backed draw per rect kind, not immediate-mode per rectangle (`utils/dev_references/terminals/alacritty/alacritty/src/renderer/mod.rs:242-265`, `utils/dev_references/terminals/alacritty/alacritty/src/renderer/rects.rs:247-370`).
- Alacritty front-loads stable font metrics and hot glyphs in `GlyphCache::new(...)` and `load_glyphs_for_font(...)`, which matches the accepted Howl metrics-cache win and confirms that repeated font/session setup should stay out of the frame hot path (`utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs:81-124`).

### Proposed Shape

- The closest Alacritty correspondence for `howl-render/src/text/direct_normal.zig` is `display/content.rs` plus the text-facing half of `display/mod.rs`: content iteration should decide what is renderable and avoid manufacturing ordinary background work as separate draw commands when the text path can carry it.
- The closest Alacritty correspondence for `howl-render/src/prepared/render_surface_emitter.zig` is split across `renderer/text/*` and `renderer/rects.rs`: text payloads are batched by texture and rendered with background in-band, while only non-text rect classes stay on a separate rect path.
- The closest Alacritty correspondence for `howl-render/src/prepared/owner.zig` is the `Display` to `Renderer` handoff in `display/mod.rs`: one owner prepares frame-local content, then hands a ready-to-submit buffered representation to the renderer without redoing policy in the GL layer.
- The closest Alacritty correspondence for `howl-linux-host/src/display/renderer/render_surface.zig` is `renderer/mod.rs` plus `renderer/rects.rs`: the host GL layer should realize already-batched commands through buffered draw paths; it should not be the place where thousands of ordinary cell backgrounds are still being paid as individual fill commands.

### Direct Answer To The Fill Question

- Alacritty reduces ordinary background/fill work primarily at the content-preparation layer and carries the surviving per-cell background through the text batch itself.
- Alacritty also reduces line/decor rect count at the rect-emission layer through `RenderLines`.
- Alacritty does use a buffered GL rect draw layer, but the reference shape does not rely on the GL layer to rescue an explosion of ordinary per-cell background commands after the fact.
- For Howl, the measured fill bottleneck is therefore upstream of host GL realization. The host immediate-mode cost is real, but the reference-backed correction starts by reducing how many fill commands exist at all for normal text frames.

### Explicit Next Slice Plan

1. Research/coder target files only:
   - `howl-render/src/text/direct_normal.zig`
   - `howl-render/src/prepared/render_surface_emitter.zig`
   - tests/bench surface already used by the active loop
2. Keep out of scope:
   - `utils/tools/*`
   - `howl-linux-host/src/display/renderer/render_surface.zig`
   - ABI contract reshaping
3. Required shape:
   - prove which normal-path backgrounds can stay in-band with glyph rendering rather than being emitted as standalone fill commands
   - preserve explicit rect emission only for clears, decorations, cursor, and genuinely non-text background cases that cannot be represented in the glyph/text path
   - if a full in-band move is too broad for one accountable slice, first cut a proof-backed pre-emission suppression path for plain default-background cells on the normal publication path, since Alacritty already drops those at content iteration (`display/content.rs:156-184`) and Howl already has an `empty` cell predicate at `publication_cell_map.zig:137-150`
4. Stop condition:
   - accepted receipt shows lower `render_upload_fill_count_avg` and lower `render_upload_fill_avg_us` on the same direct ASCII-rain harness
   - no regression in `zig build test:unit` for `howl-render`
   - no host-path crash

### Required Tests

- `cd /home/home/personal/projects/howl/howl-render && zig build test:unit`
- `cd /home/home/personal/projects/howl/howl-render && zig build benchmark:render -- --runs 20`
- direct host receipt on the existing harness and accounting surface, compared against:
  - `/home/home/personal/projects/howl/artifacts/stress/20260609-070618-direct-normal-shape-1/howl-term.stderr.log`
  - `/home/home/personal/projects/howl/artifacts/stress/20260609-081249-host-command-shape-1/howl-term.stderr.log`

### Risks

- The strongest reference-backed fix crosses the renderer contract boundary between text payload and fill payload. That is the right direction, but it can broaden quickly if the slice tries to redesign the entire render-surface ABI in one step.
- The current host path still uses immediate mode, so a renderer-side fill reduction might expose glyph-run cost more sharply after the fill count drops.
- If Howl’s embeddable render ABI requires explicit background rectangles for host independence, any move toward in-band background must be justified as ABI-preserving or escalated for orchestrator review.

### Proof Gaps

1. This research proves Alacritty’s shape, but it does not yet prove which exact subset of Howl background draws are plain default-background tax versus semantically required explicit rects.
2. The current receipts separate fill playback time, but they do not yet separate clear/background/decoration/cursor command counts on the host path.
3. A stronger reference-backed long-term shape would likely require buffered host draw realization too, but that is not the smallest accountable next slice while fill-command count is still inflated upstream.

### Readiness Judgment

- Ready for a coder slice.
- The next slice should be renderer-side command-count reduction, not another host GL micro-probe.
- Reference pressure points first to content-preparation and rect-emission suppression, then to buffered host realization if needed.
  - receipt:
    - run dir: `/home/home/personal/projects/howl/artifacts/stress/20260609-prepare-handle-timing-4`
    - stderr log: `/home/home/personal/projects/howl/artifacts/stress/20260609-prepare-handle-timing-4/howl-term.stderr.log`
    - final metrics: `/home/home/personal/projects/howl/artifacts/stress/20260609-prepare-handle-timing-4/howl-render.metrics.ndjson`
  - measured result: `frames=101`, `fps=55.66`
  - live host split after warmup:
    - `render_prepare_avg_us = 2348`
    - `prepare_surface_avg_us = 394`
    - `owner_create_avg_us = 1922`
    - `input_avg_us = 185`
    - `session_preparer_avg_us = 0`
    - `session_prepare_cells_avg_us = 207`
    - `direct_normal_avg_us = 207`
- Defensible conclusion:
  - the redundant-pass removal is accepted: it materially improved the renderer benchmark and slightly improved the real host workload without destabilizing the tree
  - the metrics-cache reduction is accepted: it removed the previously dominant `ensureTextPreparer` tax on the real host path
  - the sprint is still not done, but the dominant owner moved to `prepared_owner.Owner.create` / render-surface emission, which justified a narrower prepared-owner slice

- Accepted fresh-payload emission reduction:
  - owner paths:
    - `howl-render/src/prepared/owner.zig`
    - `howl-render/src/prepared/render_surface_emitter.zig`
  - current-code proof before the reduction:
    - `Owner.create` always allocates a fresh `RenderSurfacePayload`
    - `Emitter.emitPrepared(...)` still paid for full `self.*` copy-in and copy-out even on that fresh payload path
    - the general emitter API must preserve accepted-surface state on failure, and unit coverage proved that removing the general rollback contract is rejected
  - accepted shape:
    - keep `emitPrepared(...)` rollback semantics for the general emitter API
    - add a fresh-payload emission entrypoint for `Owner.create`, where no accepted-surface rollback is needed
    - preserve resource-store rollback through a copied `next_resources`
  - timing receipt with owner split:
    - run dir: `/home/home/personal/projects/howl/artifacts/stress/20260609-owner-create-timing-2`
    - stderr log: `/home/home/personal/projects/howl/artifacts/stress/20260609-owner-create-timing-2/howl-term.stderr.log`
    - metrics: `/home/home/personal/projects/howl/artifacts/stress/20260609-owner-create-timing-2/howl-render.metrics.ndjson`
  - measured result with timing enabled:
    - `frames=80`, `fps=44.38`
  - stable split after warmup:
    - `emit_prepared copy_in_avg_us = 0`
    - `emit_prepared fills_avg_us = 36`
    - `emit_prepared sprites_avg_us = 275`
    - `emit_prepared publish_avg_us = 2`
    - `emit_prepared stage_upload_avg_us = 90`
    - `emit_prepared atlas_resource_avg_us = 87`
    - `owner_create_avg_us = 1011`
    - `prepare_surface_avg_us = 733`
    - `render_prepare_avg_us = 1787`
    - `render_upload_avg_us = 482`
    - `present_submit_avg_us = 99`
  - clean verification receipt:
    - run dir: `/home/home/personal/projects/howl/artifacts/stress/20260609-owner-create-verify-1`
    - stderr log: `/home/home/personal/projects/howl/artifacts/stress/20260609-owner-create-verify-1/howl-term.stderr.log`
    - metrics: `/home/home/personal/projects/howl/artifacts/stress/20260609-owner-create-verify-1/howl-render.metrics.ndjson`
  - clean profiled direct result:
    - `frames=92`, `fps=50.60`
- Defensible conclusion:
  - the fresh-payload emission reduction is accepted: it removed the dominant copy tax from the true owner path without weakening the general emitter rollback contract
  - the dominant costs have moved again, and the next measured owner order is now:
    - first: remaining `prepareSurface` work at about `733 us`
    - second: host/render upload work at about `460-482 us`
    - third: sprite staging and atlas lookup work still inside `render_surface_emitter`

- Rejected direct-normal dirty-span scan probe:
  - owner path: `howl-render/src/text/direct_normal.zig`
  - hypothesis:
    - limit normal-only scanning to damaged spans only
  - receipts:
    - benchmark command: `cd /home/home/personal/projects/howl/howl-render && zig build benchmark:render -- --runs 20`
    - dropped host run dir: `/home/home/personal/projects/howl/artifacts/stress/20260609-direct-normal-dirty-scan-1`
  - accountable result:
    - partial-damage microbenches improved
    - full-grid microbenches regressed materially
    - real host result regressed to `frames=71`, `fps=38.78`
  - conclusion:
    - dropped from acceptance

- Accepted publication-source normal-only fast path:
  - owner paths:
    - `howl-render/src/source/publication_cell_map.zig`
    - `howl-render/src/source/text_input.zig`
    - `howl-render/src/text/direct_normal.zig`
    - `howl-render/src/text/frame_preparer.zig`
    - `howl-render/src/session/text.zig`
  - current-code proof before the reduction:
    - `TextSession.prepareSurface(...)` always built full `CellInput` buffers from `PublicationSource` before trying the normal-only renderer path
    - the accepted owner split already showed:
      - `input_avg_us ~= 525`
      - `session_prepare_cells_us ~= 516`
      - `direct_normal_us ~= 516`
    - that meant the normal-only publication path was paying for full publication remapping before `direct_normal` even decided the frame could stay on the fast path
  - accepted shape:
    - add a publication-cell mapping owner shared by the source and direct-normal paths
    - try the normal-only renderer path directly from `PublicationSource`
    - keep the existing full mapped-cell fallback only for reject cases
  - timing receipt:
    - run dir: `/home/home/personal/projects/howl/artifacts/stress/20260609-publication-fastpath-1`
    - stderr log: `/home/home/personal/projects/howl/artifacts/stress/20260609-publication-fastpath-1/howl-term.stderr.log`
    - metrics: `/home/home/personal/projects/howl/artifacts/stress/20260609-publication-fastpath-1/howl-render.metrics.ndjson`
  - measured result with timing enabled:
    - `frames=185`, `fps=102.26`
  - stable split:
    - `prepare_surface_avg_us = 715`
    - `input_avg_us = 0`
    - `session_prepare_cells_avg_us = 0`
    - `direct_normal_avg_us = 713`
    - `owner_create_avg_us = 990`
    - `emit_prepared sprites_avg_us = 201`
    - `emit_prepared stage_upload_avg_us = 61`
    - `render_upload_avg_us = 455`
  - clean verification receipt:
    - run dir: `/home/home/personal/projects/howl/artifacts/stress/20260609-publication-fastpath-verify-1`
    - stderr log: `/home/home/personal/projects/howl/artifacts/stress/20260609-publication-fastpath-verify-1/howl-term.stderr.log`
    - metrics: `/home/home/personal/projects/howl/artifacts/stress/20260609-publication-fastpath-verify-1/howl-render.metrics.ndjson`
  - clean profiled direct result:
    - `frames=153`, `fps=84.75`
- Defensible conclusion:
  - the publication-source normal-only fast path is accepted
  - it removed the full publication remap tax from the normal-only host path
  - after that cut, the measured owner order moves again to:
    - first: `prepared_owner.Owner.create` / `render_surface_emitter` at about `990 us`
    - second: remaining direct-normal publication prepare at about `713-715 us`
    - third: host/render upload at about `455-465 us`
- Accepted upload-shape diagnostics:
  - run dir: `/home/home/personal/projects/howl/artifacts/stress/20260609-070303-host-upload-shape-1`
  - stderr log: `/home/home/personal/projects/howl/artifacts/stress/20260609-070303-host-upload-shape-1/howl-term.stderr.log`
  - metrics: `/home/home/personal/projects/howl/artifacts/stress/20260609-070303-host-upload-shape-1/howl-render.metrics.ndjson`
  - direct result: `frames=455`, `fps=45.42`
  - stable host proof:
    - `render_prepare_avg_us ~= 1664-1805`
    - `render_upload_avg_us ~= 439-526`
    - `render_upload_count_avg = 0`
    - `render_upload_bytes_avg = 0`
  - defensible conclusion:
    - steady-state host upload cost is not texture-resource upload churn
    - the remaining upload phase is command playback / host realization work
- Accepted direct-normal subphase diagnostics:
  - run dir: `/home/home/personal/projects/howl/artifacts/stress/20260609-070618-direct-normal-shape-1`
  - stderr log: `/home/home/personal/projects/howl/artifacts/stress/20260609-070618-direct-normal-shape-1/howl-term.stderr.log`
  - metrics: `/home/home/personal/projects/howl/artifacts/stress/20260609-070618-direct-normal-shape-1/howl-render.metrics.ndjson`
  - direct result: `frames=462`, `fps=46.16`
  - stable split:
    - `prepare_surface_avg_us ~= 743-747`
    - `direct_normal_avg_us ~= 741-746`
    - `direct_normal_scan_avg_us ~= 675-679`
    - `direct_normal_backgrounds_avg_us ~= 27`
    - `direct_normal_decorations_avg_us ~= 30-31`
    - `direct_normal_raster_avg_us ~= 5-6`
    - `owner_create_avg_us ~= 969-977`
  - defensible conclusion:
    - the remaining direct-normal cost is overwhelmingly scan/append work
    - backgrounds, decorations, cursor, and raster are not the next meaningful target
- Rejected per-prepare glyph-cache probe:
  - owner path: `howl-render/src/text/direct_normal.zig`
  - dropped receipt dir: `/home/home/personal/projects/howl/artifacts/stress/20260609-070957-glyph-cache-verify-1`
  - rejection reason:
    - real host result moved only within noise to `frames=489`, `fps=48.82`
    - the direct-normal split did not improve cleanly enough to justify acceptance
  - accountable outcome:
    - the glyph-cache probe is dropped from acceptance and not part of the live tree

## Proposed Next Slice Contract Shape

Purpose: next real render-path fix, shaped by the measured main-thread churn and Alacritty’s buffered text submission.

Likely allowed files:

- `loops/ascii-rain-baseline-bottleneck.txt`
- `research/cache-2026-06-08-ascii-rain-benchmark-surface.md`
- `howl-render/src/prepared/owner.zig`
- `howl-render/src/prepared/render_surface_emitter.zig`
- `howl-linux-host/src/terminal/context.zig`
- `howl-linux-host/src/app/processor.zig`
- any small adjacent owner-true files strictly required to support a bounded emission or upload reduction

Exact tests and verification:

- `zig test src/cli/args.zig`
- `zig test src/app/process_accounting.zig`
- `zig test src/app/processor.zig`
- `zig build install -Doptimize=ReleaseFast`
- `python3 utils/tools/benchmark_terminals.py --duration 10 --mode ascii --terminals howl alacritty`
- one direct host accounting rerun on the same `320x120` ASCII-rain harness
- verify:
  - no crash on the seeded benchmark
  - Howl benchmark receipt remains complete
  - `render_prepare_avg_us` improves against `/home/home/personal/projects/howl/artifacts/stress/20260609-owner-create-verify-1/howl-term.stderr.log`
  - or `render_upload_avg_us` improves against that same accepted receipt

Exact non-goals:

- no edits to `utils/tools/benchmark_terminals.py`
- no benchmark workload redesign
- no hidden runtime layer
- no acceptance of client-array or similar compatibility-profile shortcuts that break the real benchmark
- no reopening of the fresh-payload copy tax or publication-input remap tax; both owners are already accepted and committed

Exact stop conditions:

- stop if the render-surface emission change crashes the host on the benchmark
- stop if the change broadens into backend-wide architecture without an updated sprint slice
- stop if reference pressure requires a larger buffered-renderer move than can fit honestly in one accountable slice

## Readiness Judgment

Ready for the next performance-fix slice.

Reason:

- The active loop’s benchmark launcher, stress generator, build steps, baseline commands, and artifact paths are source-backed.
- The measured receipts now pin a defensible owner path:
  - first to host render/submit churn
  - then to `howl-render` prepare
  - then to `prepareSurface ~= 6.2 ms` vs `Owner.create ~= 2.1 ms`
  - then inside `prepareSurface` before the metrics-cache reduction to:
    - `session_preparer ~= 3.9 ms`
    - `prepare_cells ~= 1.8 ms`
    - `input ~= 0.5 ms`
    - `direct_normal ~= 0.57 ms`
  - and after the accepted metrics-cache reduction to:
    - `prepareSurface ~= 0.39 ms`
    - `Owner.create ~= 1.92 ms`
    - `render_prepare ~= 2.35 ms`
  - and after the accepted fresh-payload emission reduction to:
    - `prepareSurface ~= 0.73 ms`
    - `Owner.create ~= 1.01 ms`
    - `render_prepare ~= 1.76-1.79 ms`
    - `render_upload ~= 0.46-0.48 ms`
  - and after the accepted publication-source normal-only fast path to:
    - `prepareSurface ~= 0.71 ms`
    - `input ~= 0`
    - `session_prepare_cells ~= 0`
    - `direct_normal ~= 0.71 ms`
    - `Owner.create ~= 0.99 ms`
    - `render_upload ~= 0.45-0.46 ms`
  - and after the accepted upload/direct-normal diagnostics to:
    - exclude steady-state resource uploads as the main host upload owner
    - pin the remaining direct-normal work specifically to `scan/append ~= 0.67-0.68 ms`
    - keep `Owner.create ~= 0.94-0.98 ms` as the next strongest owner
- One accepted renderer reduction is already proved with both renderer-benchmark and real-host receipts.
- The next accountable move is not more Python or wrapper work. It is either:
  - a bounded emission / command-playback reduction across the prepared emitter and host upload seam, or
  - a bounded direct-normal scan reduction now that scan/append is the only meaningful remaining direct-normal subphase.
