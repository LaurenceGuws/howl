# Rain Bench

Owner: `utils/tools/rain-bench`

Purpose: standalone ASCII rain workload generation and cross-terminal benchmark receipts.

This tool is not part of the Howl host product surface. The host only launches a command. The rain workload, benchmark wrapper, and local receipts live here.

## Contents

- `ascii_rain_stress.zig`
  Deterministic hostile terminal traffic generator for throughput testing.
- `visual_rain_stress.zig`
  Deterministic visible rain workload for rendering/correctness checks.
- `benchmark_terminals.py`
  Cross-terminal benchmark wrapper for `howl`, `alacritty`, `kitty`, `ghostty`, and `wezterm`.
- `build.zig`
  Local build surface for this tool only.

## Build

From `utils/tools/rain-bench`:

```sh
zig build --release=fast stress:rain:build
```

That stages the stress binary under:

```text
utils/tools/rain-bench/zig-out/harness/
```

## Local Zig Steps

From `utils/tools/rain-bench`:

```sh
zig build -l
```

Current tool-owned steps:

- `stress:rain`
- `stress:rain:build`
- `stress:rain:ascii`
- `stress:rain:ascii:build`
- `stress:rain:mixed`
- `stress:rain:mixed:build`
- `stress:rain:visual`
- `stress:rain:visual:build`

## Benchmark Wrapper

Run from the workspace root:

```sh
python3 utils/tools/rain-bench/benchmark_terminals.py --duration 3 --terminals howl alacritty
```

Or let it build both the Howl host and the local rain binary first:

```sh
python3 utils/tools/rain-bench/benchmark_terminals.py --duration 3 --terminals howl alacritty --build
```

Useful flags:

- `--duration <seconds>`
- `--mode ascii|mixed`
- `--cols <n>`
- `--rows <n>`
- `--frames <n>`
- `--seed <value>`
- `--metrics-every <n>`
- `--flush-every <n>`
- `--terminals howl alacritty ...`
- `--build`
- `--out-dir <path>`

Full flag surface:

```sh
python3 utils/tools/rain-bench/benchmark_terminals.py --help
```

## Receipts

By default the wrapper writes receipts under:

```text
utils/tools/rain-bench/artifacts/stress/
```

Each run gets a timestamped subdirectory containing:

- `<terminal>-<mode>.metrics.ndjson`
- `<terminal>-<mode>.resources.ndjson`
- `summary.json`

## Host Boundary

- Howl host does not own this tool.
- Root workspace build does not expose `stress:rain*`.
- `utils/tools/` parent does not expose `stress:rain*`.
- This subdirectory owns the workload, wrapper, and receipts.
