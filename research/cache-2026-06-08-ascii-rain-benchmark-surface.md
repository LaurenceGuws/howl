# ASCII Rain Benchmark Surface Research

Date: 2026-06-08.
Role: researcher.
Status: active.
Loop: `loops/ascii-rain-baseline-bottleneck.txt`.

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
- Current `Args` does not expose any debug accounting flags yet. Restoring internal accounting therefore requires explicit CLI additions in `src/cli/args.zig` and startup wiring in `src/main.zig` before `Processor.run()` begins (`/home/home/personal/projects/howl/howl-linux-host/src/cli/args.zig:3-44`, `/home/home/personal/projects/howl/howl-linux-host/src/main.zig:19-29`, `/home/home/personal/projects/howl/howl-linux-host/src/main.zig:87-108`).
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
- The already-dirty renderer batching diff in `src/display/renderer/render_surface.zig` is part of the live benchmark tree, but this research does not yet claim whether it is sufficient or insufficient. The next loop exists to measure the tree as it stands.

## Proof Gaps

1. Current source still has no live internal accounting owner or flags. The next slice must restore that explicitly inside current host owners.
2. The direct accounting run path does not yet have an accepted artifact naming contract inside the host. For now, the shell redirection path in the loop contract is the receipt boundary.
3. The exact final artifact directory name cannot be stated before execution because the launcher-generated baseline receipt path depends on wall-clock time, and the direct diagnostic run is intended to write into the same timestamped run directory.
4. This research proves the benchmark surface, current host owner map, and a previously proven accounting shape. It still does not prove the dominant bottleneck class. That requires the accounting run receipts from the next slice.

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
  - owner path: `howl-render/src/text/font/ft_hb/support.zig`
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
