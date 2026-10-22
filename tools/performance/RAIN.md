# Rain cadence lanes

`rain` supports an explicit `--fps N`. Without it, the default is the upstream
30 ms simulation tick (about 33⅓ steps/s).

Use the same qualified producer binary, seed, terminal profile and complete native
grid for every horse. Launch each rate in a **fresh terminal process**:

```bash
race_producer=/absolute/path/to/qualified/tui-zoo
"$race_producer" rain --fps 240 --duration-ms 20000 --seed 20261022 \
  --cols 384 --rows 83 --synchronized-output
```

The initial lanes are **60, 120 and 240 fps**. Repeat each horse/rate in reversed
order. These are separate workloads from the `cells` dose curve.

## What changes with fps

Rain advances once per emitted frame. Raising `--fps` increases simulation steps
and terminal work per second; it does not hold falling speed constant while
interpolating more display frames. A fixed workload version, seed, geometry and
frame count determines the simulation sequence. Wall-clock runs can emit
different frame counts under backpressure.

`--duration-ms` bounds a timed run. `--frames` instead selects an exact emitted
frame count. `--assert-min-fps` can enforce a producer-throughput requirement;
it does not assert that the terminal displayed those frames.

## Required observations

- Requested producer cadence, achieved cadence, frames and skipped slots.
- Changed-cell count and synchronized-output mode.
- Producer frame-work and deadline-lateness percentiles from the final
  `tui_zoo.rain/v1` JSON receipt on stderr. Frame work includes simulation,
  byte generation and flushing; these are producer-side times.
- Whole-terminal CPU across all terminal threads/helpers, excluding the producer,
  coordinator and compositor. Keep sampled Anonymous and PSS peaks separate.
- Exact producer/terminal/font/config hashes, argv, native PTY extent, terminal
  pixel extent, fullscreen window and output geometry.
- The actual output refresh if the environment exposes it. An unavailable refresh
  remains unavailable; a 240 fps producer does not establish a 240 Hz display.

Actual presentation intervals, missed presentation deadlines and input-to-paint
latency need their own observer. Window mapped/presented state, screenshots and
producer receipts do not supply those timings.

## Full-grid qualification

Use [DP1.md](DP1.md)'s 1920×1080 scale-1 profiles and require **384×83 cells**,
**5×13 pixels per cell**, **1920×1079 drawing pixels**, and unobscured corners.
Keep physical Hyprland and private KWin cohorts separate. Native corner and
visible-rain captures belong in a separate qualification pass, outside CPU timing.

The current producer is the independently qualified ReleaseFast Zig 0.17.0 race
artifact; this lane adds no terminal-specific behavior to TUI Zoo. The final
receipt is producer evidence, not displayed FPS or photon latency.

## Qualified sweep · 22 October 2026

The [race report](race.html#rain-cadence-20261022) records 24 fresh 20s private
runs: two reversed observations per horse/rate, with every CPU value, producer
cadence/miss/work count, sampled Anonymous/PSS peak and producer p99 timing.
All actual windows match the full native grid. The complete workload has no
resource-limit events or CPU throttling. Howl uses qualified Fast 83259505;
daily Safe 814928a8 is unchanged. Physical Hyprland and earlier cell cohorts
remain separate. Raw workstream receipts are under
~/.local/state/workstreams/howl-current/day-20261022/performance/rain-track/.
