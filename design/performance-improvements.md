# Performance Improvements Record

Purpose: record changes that materially improved throughput, responsiveness, smoothness, or our ability to diagnose performance.

Last updated: 2026-05-11

## Measurement Foundation

### Scriptable Host Stress Baselines

Added Python-driven terminal comparisons in `howl-hosts/howl-linux-host/tools/benchmark_terminals.py`.

Material outcome:
- Repeatable Howl/kitty/ghostty comparisons.
- Resource sampling for CPU, RSS, threads, processes, and available GPU signals.
- Artifacts under `artifacts/stress/` with summary JSON and optional trace NDJSON.

Why it matters:
- Prevents tuning against anecdote only.
- Exposes the difference between producer throughput and visible pacing.

### Broadened Peer Field And ReleaseFast Host Baselines

Expanded the Linux-host benchmark harness to cover more peer terminals and to build performance-facing binaries as `ReleaseFast`.

Material outcome:
- Added `alacritty` to the active peer field and briefly captured valid `wezterm` comparison runs before later removing it from the active harness due local launch instability.
- Current hostile producer baselines on this machine show Howl materially stronger than earlier assumptions based only on kitty/ghostty-focused runs:
  - ASCII: Howl roughly `843 FPS`, behind `alacritty` but ahead of `ghostty`, `kitty`, and the recorded `wezterm` run.
  - Mixed: Howl roughly `690 FPS`, again behind `alacritty` but ahead of `ghostty`, `kitty`, and the recorded `wezterm` run.

Why it matters:
- Keeps the race honest by comparing against more than one reference style.
- Changes the optimization target from "raise raw producer throughput at all costs" to "preserve and improve user-visible smoothness while staying ahead on throughput where possible." 

### Opt-In Structured Trace Sink

Added gated NDJSON tracing with `HOWL_TRACE_PATH`.

Material outcome:
- Can trace `term_io`, `term_frame`, `render_atlas`, `host_render`, and `host_frame` without production log noise.
- Confirmed sprint/freeze as frame-gap regressions rather than only subjective smoothness.

Why it matters:
- Gives accurate diagnostics while respecting the “no stale prod logs” rule.

### VT Terminal Module Benchmark

Expanded `howl-vt/src/test/vt_core_benchmark.zig` with NDJSON output, `--runs`, unicode/CSI/scroll/snapshot/queue workloads, and production-sized history coverage.

Material outcome:
- Isolated parser/apply/history behavior from host rendering.
- Found scrollback history allocation pressure independently of the full host.

Why it matters:
- Lets us test module-level hypotheses instead of treating full-host stress as the only signal.

## Runtime And Scheduling Improvements

### Event-Driven Wake Lane With Control-Plane Publication

Locked runtime/host wake contract around one producer-owned lane:

- `howl-term` now owns render wake registration through one minimal C ABI callback surface.
- Producer pending-edge transitions publish render work, bump snapshot sequence, and wake host.
- Control-plane mutations (font/focus/viewport/scrollback) route through the same publish+wake lane.
- Linux host frame demand now includes queued render work, and input binding drain is bounded per turn for fairness.

Material outcome:

- Fixed hard freezes tied to first tab-switch focus updates and repeated font-size changes under active rain churn.
- Preserved hostile-workload throughput while fixing liveness:
  - Pre-fix sequential baseline averages (this machine):
    - ASCII: Howl `~575.6 FPS`, Alacritty `~1007.9 FPS`, Ghostty `~552.4 FPS`
    - Mixed: Howl `~473.7 FPS`, Alacritty `~840.3 FPS`, Ghostty `~437.0 FPS`
  - Post-fix sequential baseline averages (this machine):
    - ASCII: Howl `~568.5 FPS`, Alacritty `~1015.7 FPS`, Ghostty `~559.3 FPS`
    - Mixed: Howl `~475.8 FPS`, Alacritty `~847.1 FPS`, Ghostty `~434.7 FPS`

Why it matters:

- Confirms the Alacritty-style event-loop ownership move was directionally correct for correctness and stability.
- Narrows next optimization focus to render preparation/shaping cost instead of wake plumbing.

### Smooth Ingest Pacing

Set the practical smooth budget to `16 reads / 64 KiB`.

Material outcome:
- Restored visually smooth host frame cadence after larger ingest chunks caused burst/freeze behavior.
- Traces showed host frame p50/p95 near the `9-12ms` range under the smooth path.

Why it matters:
- Establishes a known-good pacing guardrail while deeper scheduling work proceeds.

### Render Snapshot Storage Boundary

Added `howl-term/src/term/render_snapshot.zig` and moved render-facing cells, cursor, viewport, and dirty metadata into explicit snapshot owners.

Material outcome:
- UI render can copy a render snapshot and prepare the render batch outside the live runtime lock.
- Howl-only stress improved from roughly `94 FPS` ASCII / `85 FPS` mixed to roughly `104 FPS` ASCII / `92 FPS` mixed in comparable rebuilt runs.

Why it matters:
- Separates ownership even though it is not the final threaded publisher design.
- Provides a foundation for future latest-only publication and retained renderer buffers.

### Dirty-Span Snapshot Copy

Changed render snapshot copying to copy dirty row/column spans instead of always copying the full cell grid.

Material outcome:
- Small positive improvement on top of the snapshot boundary.
- Example observed result: ASCII around `135.56 FPS`, mixed around `115.63 FPS` during high-throughput budget probes.

Why it matters:
- Reduces unnecessary memory copy work and keeps snapshot ownership cheap enough to build on.

## VT Terminal Improvements

### ASCII Bridge Fast Paths

Avoided unnecessary ASCII bridge slice merging and fast-pathed single ASCII bridge events.

Material outcome:
- Reduced parser/bridge overhead in common ASCII-heavy traffic.

Why it matters:
- ASCII throughput is a primary terminal benchmark axis and common workload.

### CSI Parser Reset Reduction

Avoided full CSI parser resets in hot paths.

Material outcome:
- Reduced parser overhead for CSI-heavy workloads.

Why it matters:
- CSI formatting traffic is a major throughput benchmark category.

### Dirty Column Ranges

Exposed dirty column ranges from terminal and used them in howl-term snapshot sync.

Material outcome:
- Incremental sync can avoid scanning full rows when changes are narrow.

Why it matters:
- Necessary for efficient publication and future GPU-cell update paths.

### HistoryLine Reuse Ring

Reused authoritative scrollback history line buffers after capacity is reached using an O(1)-style ring slot approach.

Material outcome:
- `scroll_heavy_history1000` improved from roughly `240ms` median and roughly `20k` allocations to roughly `100-120ms` and roughly `1k` allocations in module benchmarks.

Why it matters:
- Strong isolated win even though full-host stress remained dominated elsewhere.

## Render Improvements

### Background Fill Span Merging

Merged same-color background fills into spans.

Material outcome:
- Reduced fill command count for many rows.

Why it matters:
- Lowers transient render batch size before the renderer moves to retained GPU buffers.

### GL Reusable Vertex Arrays

Moved GL fill/glyph submission away from per-quad immediate mode toward reusable CPU vertex arrays and `glDrawArrays(GL_QUADS)`.

Material outcome:
- Reduced immediate draw overhead and improved high-throughput stress results before later pacing tradeoffs.

Why it matters:
- Useful checkpoint toward a more retained renderer.

### Glyph Fallback And Atlas Key Fixes

Tracked resolved glyph atlas keys and avoided duplicate fallback glyph resolution.

Material outcome:
- Improved glyph fallback correctness and reduced redundant atlas resolution work.

Why it matters:
- Mixed/unicode workloads depend on fallback behavior being both correct and cheap.
