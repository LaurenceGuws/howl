# Howl-Term Host Scorecard

Purpose: lock the Milestone 5 host-visible scorecard for the real `howl-linux-host` embedder path.

Proof layer: host-visible

Last updated: 2026-05-12

## Canonical Host Workload

Canonical command shape:

```sh
python3 howl-hosts/howl-linux-host/tools/benchmark_terminals.py --build --duration 10 --mode ascii --terminals howl alacritty ghostty kitty
python3 howl-hosts/howl-linux-host/tools/benchmark_terminals.py --duration 10 --mode mixed --terminals howl alacritty ghostty kitty
```

Locked workload parameters:
- `duration=10s`
- `cols=320`
- `rows=120`
- `frames=100000000`
- `seed=0xC0FFEE`
- `metrics_every=100`
- `flush_every=1`
- workloads: `ascii`, `mixed`

Measured path rule:
- `howl` results close Milestone 5 only when they come from `howl-linux-host` running the real host-driven `howl-term` path.
- package-local `howl-term` benchmarks may support diagnosis but may not close host-visible claims.

Peer rule:
- peer terminals are optional reference pressure only.
- when used, they must run the same workload and be retained in the same run directory as Howl.

## Scorecard Metrics

Per workload, the scorecard must retain these fields:

- latency:
  - `producer_write_p50_us`
  - `producer_write_p95_us`
  - `producer_write_p99_us`
  - `producer_write_max_us`
- throughput:
  - `producer_fps`
  - `producer_frames`
- CPU:
  - `cpu_percent_avg`
  - `cpu_percent_p50`
  - `cpu_percent_p95`
  - `cpu_percent_max`
  - `rss_kib_peak`
  - `threads_peak`
  - `process_count_peak`
  - `vram_mib_peak` when available
- cadence:
  - `cadence_fps_p50`
  - `cadence_fps_p95`
  - `cadence_fps_min`
  - `cadence_avg_total_us_p50`
  - `cadence_avg_total_us_p95`
  - `cadence_avg_total_us_max`
  - `cadence_avg_draw_us_p95`
  - `cadence_avg_swap_us_p95`

Howl-only attribution signals:
- `prepare_term_us_p50`, `prepare_term_us_p95`, `prepare_term_us_max`
- `prepare_renderer_us_p50`, `prepare_renderer_us_p95`, `prepare_renderer_us_max`
- `prepare_renderer_share_percent_p50`, `prepare_renderer_share_percent_p95`, `prepare_renderer_share_percent_max`
- `render_submit_us_p95`

Interpretation rule:
- generator latency and throughput are child-visible end-to-end pressure signals because the stress process is blocked by the real terminal path, not by a package-local harness.
- cadence metrics come from the real SDL host presentation path.
- attribution signals do not replace host-visible results; they explain which boundary owns a bad host-visible result.

## Artifact Format

Each run directory under `howl-hosts/howl-linux-host/artifacts/stress/<run_id>/` must retain:

- `summary.json`
- `scorecard.json`
- `<terminal>-<mode>.metrics.ndjson`
- `<terminal>-<mode>.resources.ndjson`
- `howl-<mode>.runtime.jsonl` for Howl
- `howl-<mode>.trace.ndjson` only when `--trace-howl` is used

Artifact meaning:
- `metrics.ndjson`: child-visible generator throughput and write-latency under terminal pressure
- `resources.ndjson`: process-tree CPU, RSS, thread, process, and optional GPU signals
- `runtime.jsonl`: Howl host cadence and renderer/runtime attribution signals
- `scorecard.json`: locked Milestone 5 host scorecard distilled from the retained raw artifacts

## Boundary Naming Rule

If a materially bad result remains, the report must name one owning boundary explicitly:

- `API shape`
- `host scheduling`
- `renderer work`
- `lower-module behavior`

Negative space:
- do not call a metric "good enough"
- do not close cadence or latency from package-only benchmarks
- do not cite peer comparisons without the retained run directory
