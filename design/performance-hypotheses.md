# Performance Hypotheses

Purpose: keep a living record of what we believe is limiting Howl throughput, responsiveness, and smoothness compared with kitty and ghostty.

Last updated: 2026-05-05

## Current Read

Howl can process more terminal traffic when we raise ingest/apply budgets, but visible pacing regresses into sprint/freeze behavior. This means raw byte throughput and user-perceived smoothness are currently coupled too tightly.

The current best-balanced state keeps the smooth ingest budget at `16 reads / 64 KiB` while retaining the render snapshot boundary and dirty-span copy work.

## Architecture Gaps Versus Kitty/Ghostty

### Ingest, Apply, And Render Cadence Are Still Coupled

Kitty and ghostty separate child interaction, terminal parsing/state mutation, render preparation, and UI rendering more cleanly.

Howl currently has a runtime worker that reads PTY bytes, feeds/applies VT state, marks dirty work, and indirectly controls render opportunities through wake behavior. Bigger chunks improve producer throughput but also create bigger dirty publications and larger visible jumps.

Hypothesis: Howl needs a scheduler boundary where PTY reads can remain hot while apply/publication is frame-aware and coalesces stale intermediate states.

### Render Publication Is A Data Boundary, But Not A Scheduler Yet

We now have render-facing snapshot storage and a UI-owned render snapshot. This reduced ownership coupling and lets us reason about publication separately.

However, rendering is still driven by dirty/wake flow rather than a deliberate frame scheduler. Attempts to add a publisher thread without a strong scheduler moved work but regressed cadence.

Hypothesis: the next successful publisher design needs a frame-deadline policy and a latest-only mailbox, not just a second thread that builds batches whenever dirty.

### GL Submission Is Still Immediate-Mode Shaped

Howl improved GL submission by using reusable vertex arrays, but it still submits transient fill/glyph batches. Kitty’s renderer updates GPU cell data and draws from retained GPU-facing buffers.

Hypothesis: the largest renderer-side win likely requires a persistent renderer-owned cell/GPU update path, not only command batching.

### Dirty Work Is Too Large Under Heavy Output

Dirty column ranges help incremental updates, but hostile scrolling/output often dirties enough rows that each publication still has thousands of glyphs and fills.

Hypothesis: smooth high throughput needs either smaller frame publications, a scroll-aware renderer path, or retained GPU cell buffers where large scrolls do not require rebuilding and resubmitting equivalent transient commands.

### Telemetry Must Stay Gated And Diagnostic

Runtime logging should remain conservative. We should not add production logs to explain normal behavior. Structured traces behind `HOWL_TRACE_PATH` are the right tool for timing and ownership boundaries.

Hypothesis: better traces should answer precise questions, such as bytes read, bytes applied, dirty rows, prepared batch age, frame gap, and lock hold time, without always-on logging.

## Current Best Baselines

Use these as approximate recent reference points, not permanent truth.

- Smooth Howl path after snapshot boundary and dirty-span copy: host frame p50 roughly `9-10ms`, p95 roughly `10-13ms` under traced ASCII stress.
- Larger `64 reads / 256 KiB` budget: producer FPS can rise to roughly `135-138 FPS`, but host frame p50/p95 can regress to roughly `24-68ms`, which looks visibly bursty.
- ReleaseFast Linux-host peer baseline on this machine under `howl_ascii_rain_stress` now shows a more nuanced picture than the earlier kitty/ghostty-focused comparisons:
  - ASCII run:
    - `alacritty` roughly `1025 FPS`
    - `howl` roughly `843 FPS`
    - `ghostty` roughly `561 FPS`
    - `wezterm` roughly `419 FPS` before later removal from the harness due local launch instability
    - `kitty` roughly `411 FPS`
  - Mixed run:
    - `alacritty` roughly `857 FPS`
    - `howl` roughly `690 FPS`
    - `ghostty` roughly `440 FPS`
    - `kitty` roughly `376 FPS`
    - `wezterm` roughly `372 FPS` before removal from the harness
- Working interpretation:
  - Howl is now competitive enough that broad statements like "kitty and ghostty are simply ahead" are no longer precise for this hostile producer-FPS workload.
  - The remaining gap is more likely about host-visible smoothness, publication size, and efficiency per rendered update than raw generator throughput alone.

## Working Rule

Do not judge a single structural cut only by immediate FPS. Some cuts isolate concerns and become valuable only after later cuts land. Record the hypothesis chain before reverting or keeping large changes.
