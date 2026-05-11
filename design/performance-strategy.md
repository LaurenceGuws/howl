# Performance Strategy

Purpose: define how Howl performance work should be executed across layers so we can beat strong references deliberately, without bloating the production host path.

Last updated: 2026-05-11

## Position

We should treat Howl performance as a layered systems problem, not a single FPS number.

The opportunity is not to imitate kitty or ghostty mechanically.
The opportunity is to use Zig, clean ownership boundaries, and separate runtime surfaces to move faster and more safely than codebases with heavier historical baggage.

The host runtime must stay lean.
Instrumentation, synthetic workloads, and intrusive measurement belong in dedicated surfaces unless they are explicitly gated and cheap.

## Working Principles

- Keep production runtime behavior clean by default.
- Measure the narrowest owner that can answer the current question.
- Use end-to-end host stress only when the question is genuinely about visible pacing or real platform/render interaction.
- Prefer deterministic replay and synthetic stress when isolating parser, apply, publication, or batch-building cost.
- Use compound experiment sprints, not isolated tweak-and-revert loops.
- Preserve partial architecture cuts on experiment branches or stashes until the whole theory has been judged.

## Surface Map

### 1. `howl-vt-core`

Best for:
- parser throughput
- apply throughput
- dirty-row and dirty-column behavior
- scrollback/history structure cost
- deterministic replay under hostile byte streams

Existing surfaces:
- `zig build test`
- `zig build test:regression`
- `zig build vt-core-benchmark -- --runs 3`
- `zig build fuzz`

Key files:
- `howl-vt-core/src/test/vt_core_benchmark.zig`
- `howl-vt-core/src/fuzz_tests.zig`
- `howl-vt-core/src/fuzz/scrollback.zig`

Use this layer when asking:
- can we parse or apply faster?
- did dirty tracking become narrower or wider?
- did history changes help the terminal core even before UI is involved?

### 2. `howl-render-core`

Best for:
- render batch generation cost
- damage-to-command expansion behavior
- glyph/fill/upload counts
- retained renderer-owned row or cell storage experiments
- backend submission cost isolated from PTY and terminal logic

Existing surfaces:
- `zig build test`
- direct unit tests already covering `render_batch.zig` and backend behavior
- `zig build render-core-benchmark -- --runs 3`

Current gap:
- no dummy backend submission surface yet

Key files:
- `howl-render-core/src/render_batch.zig`
- `howl-render-core/src/backend/gl/RenderGl.zig`
- `howl-render-core/src/test/root.zig`

Use this layer when asking:
- is transient batch generation itself too expensive?
- how many glyphs, fills, and uploads are we producing for a given damage pattern?
- does a retained row or cell representation reduce CPU or submission cost?

### 3. `howl-term`

Best for:
- runtime thread scheduling
- snapshot publication behavior
- scrollback-view projection cost
- wake and present-ack policy
- term-only integration without SDL host overhead

Existing surfaces:
- `zig build test`
- `zig build fuzz`
- `zig build howl-term-benchmark -- --runs 3`

Useful current owners:
- `howl-term/src/runtime/thread.zig`
- `howl-term/src/render/snapshot.zig`
- `howl-term/src/render/frame.zig`
- `howl-term/src/wake/wake.zig`

Current gap:
- no dummy PTY-backed term benchmark yet
- no dummy renderer consumer benchmark yet

Use this layer when asking:
- are we publishing too much state per frame?
- is snapshot copy too expensive?
- does a scheduling change help before real GL and SDL are involved?

### 4. `howl-linux-host`

Best for:
- visible pacing
- real GL submission behavior
- SDL event loop interaction
- resource usage under full product conditions
- comparison against kitty and ghostty

Existing surfaces:
- `zig build run`
- `zig build stress:rain:ascii`
- `zig build stress:rain:mixed`
- `python3 tools/benchmark_terminals.py ...`

Key files:
- `howl-hosts/howl-linux-host/src/main.zig`
- `howl-hosts/howl-linux-host/src/fuzz/ascii_rain_stress.zig`
- `howl-hosts/howl-linux-host/tools/benchmark_terminals.py`

Use this layer when asking:
- did the user-visible experience get better?
- did the renderer and scheduler interact well on the real host?
- are we actually closing the gap versus reference terminals?

## Default Sprint Ladder

Do not start at the host unless the question is inherently visual.

Recommended order:

1. `vt-core` or `render-core` micro-level confirmation
2. `howl-term` runtime integration confirmation
3. `howl-linux-host` visible pacing confirmation
4. kitty/ghostty comparison only after Howl itself improves or changes behavior materially

This keeps the expensive, noisy benchmark surface for the end of each sprint instead of every tiny checkpoint.

## New Harnesses We Should Add

### A. `render-core` benchmark executable

Goal:
- repeatedly build or submit synthetic frame workloads without PTY or host noise

Initial workload set:
- full-grid ASCII
- sparse dirty rows
- wide dirty spans
- scroll-heavy frame updates
- mixed glyph and box-drawing workloads

Measurements:
- fills
- glyphs
- atlas uploads
- frame prep wall time
- submission wall time for real and dummy backends

Why:
- `render_batch.zig` is a likely hot path and currently lacks its own benchmark owner surface.

### B. `howl-term` runtime stress harness

Goal:
- drive `runtime/thread.zig`, `render/frame.zig`, and `render/snapshot.zig` without SDL or a real terminal window

Initial shape:
- synthetic session transport that feeds deterministic PTY-like byte streams
- selectable workloads: ASCII flood, mixed text, scroll-heavy, reply-heavy
- optional dummy renderer consumer that records publication size and snapshot age

Measurements:
- reads per tick
- bytes per tick
- apply time
- snapshot copy time
- dirty rows/cells/spans
- publication age

Why:
- we need a place to test scheduler and publication theories without paying real GL cost every iteration.

### C. Dummy renderer or null submission path

Goal:
- distinguish batch generation cost from actual GL submission cost

Shape:
- renderer-facing consumer that accepts `SurfaceFrameData` or `RenderBatch`
- records command counts and timing
- never touches SDL or GL

Why:
- if null submission is already expensive, the problem is earlier than the backend.
- if null submission is cheap but GL is expensive, the backend becomes the primary target.

## Immediate Performance Program

### Sprint 1: Establish sharper measurement surfaces

Deliverables:
- gated publication metrics in `howl-term`
- render-core benchmark entrypoint
- howl-term runtime benchmark entrypoint
- clear scorecard for:
  - vt apply
  - sync-from-core projection
  - snapshot copy
  - batch build
  - backend submission
  - host frame cadence

Success condition:
- we can identify where the next 20 percent of latency or cost really sits without relying on guesswork.

### Sprint 2: Retained renderer-owned visible state

Deliverables:
- prototype retained row or cell storage in `howl-render-core`
- benchmark comparison against transient batch rebuild
- term-level publication metrics showing whether dirty work shrinks meaningfully

Success condition:
- lower CPU cost or smaller publication churn at equal correctness.

### Sprint 3: Deadline-aware apply and latest-only publication

Deliverables:
- bounded apply scheduler in `howl-term`
- latest-only publication semantics
- explicit stale-state replacement policy

Success condition:
- higher throughput without burst/freeze pacing regressions.

## Locked Wake And Scheduling Invariants

These are now long-lived rules, not sprint notes:

- Producer ownership is hard: only `howl-term` producer-side state transitions may publish render wake intent.
- Pending-edge contract is hard: on `pending false -> true`, runtime must publish latest snapshot work, bump snapshot sequence, and fire coalesced wake callback.
- Control-plane mutation contract is hard: font/focus/viewport/scrollback mutations must route through the same publish+wake lane; no seq-only wake paths.
- Bootstrap contract is hard: first-frame geometry/full-dirty transitions must publish render work without host polling.
- Host frame-demand contract is hard: content frame demand must include `needsPrepare`, `needsFrame`, and `hasQueuedRenderWork` so queued work never sleeps behind idle waits.
- Host fairness contract is hard: input binding drains must be bounded per turn so render gets CPU opportunity under key-repeat floods.
- Observability contract is hard: wake/perf traces stay gated and removable; no always-on production logging.

## What Stays Out Of The Main Host Path

- always-on debug logging
- broad tracing by default
- benchmark-only counters that pollute core owners
- scheduling heuristics that exist only to make test numbers prettier

If data is needed in production code, gate it tightly and keep the owner clear.

## Reference-Terminal Bias Seeds

Use references for architectural direction, not cargo-cult copying.

Kitty bias seeds:
- retained GPU-facing cell state
- dirty-line based renderable updates
- shader-driven screen-sized cell submission

Ghostty bias seeds:
- explicit renderer thread ownership
- mailbox-driven wake semantics
- row-wise renderer-owned cell storage

Howl opportunity:
- cleaner owner boundaries than the references
- easier creation of dedicated stress runtimes in Zig
- more deliberate separation between parser, publication, renderer, and host

## Decision Rule

If a question can be answered below the host layer, answer it there first.

If a change only wins in a synthetic harness but loses visibly in the host, it is not done.

If a change loses in isolation but unlocks a better compound direction, keep it alive until the sprint ends.
