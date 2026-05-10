# Performance Scratchpad

Purpose: hold compound hypotheses and multi-step experiment chains. This is intentionally less polished than the other records.

Last updated: 2026-05-05

## Core Pattern We Keep Seeing

Raw throughput improvements often regress pacing. Single changes that increase producer FPS can be bad for the terminal if they create larger visible dirty publications.

Pattern:
- Bigger ingest/apply chunks: more producer FPS, worse visible frame gaps.
- Moving work to another thread without scheduling: less lock/sync cost, worse or unchanged frame cadence.
- Host pacing without smaller publications: still chunky frames.
- Read-ahead without deadline-aware apply: either starves the host or collapses throughput.

## Experiment Workflow

Working rule:
- do not force every architectural cut to prove itself immediately in isolation.
- run short compound experiment sprints with explicit coupled steps.
- if a step is useful but not mainline-worthy yet, stash it or park it on an experiment branch instead of discarding the idea.

Per sprint, record:
- theory being tested
- the coupled cuts that must land together before judgment
- acceptable temporary regressions during the middle of the sprint
- final evidence for or against the combined theory

Suggested stash or branch labels:
- `perf-sprint-render-publication`
- `perf-sprint-retained-cell-buffer`
- `perf-sprint-deadline-apply`

## Compound Hypothesis A: Deadline-Aware Apply Scheduler

Potential large win requires multiple pieces together:

- PTY reader can drain aggressively into a buffer.
- Apply scheduler processes bytes until a time budget or dirty-work budget is reached.
- Render publication samples latest applied state at a frame cadence.
- Backlog changes policy, but does not let one frame absorb too much changed state.
- Host renders latest state and skips intermediate states.

Why single-step attempts were misleading:
- Read-ahead alone reduced kernel/PTY pressure but did not solve apply cadence.
- Host pacer alone delayed frames but did not reduce frame work.
- Larger apply caps improved throughput but created oversized frames.

Challenge when revisiting:
- Define apply budget in time, dirty rows, or bytes?
- How do we handle escape sequences split across apply chunks?
- How do we guarantee title/clipboard/reply side effects are not delayed too much?

## Compound Hypothesis B: Retained GPU Cell Buffer

Potential large win requires multiple pieces together:

- Renderer owns a persistent cell buffer or GPU-facing cell state.
- Terminal publication emits dirty cell/row updates rather than transient full batches.
- Scroll-heavy paths become offset/copy operations instead of thousands of glyph/fill commands.
- GL backend moves beyond compatibility-style transient draw arrays.

Why single-step attempts were misleading:
- GL reusable vertex arrays helped, but still submit transient batches.
- Dirty column ranges help CPU batch construction, but hostile output still creates many draw commands.
- Snapshot dirty-span copy helps memory copy cost, but not GPU submission model.

Challenge when revisiting:
- Current GL 2.1 compatibility context constrains modern instancing choices.
- Need decide whether to upgrade context/profile or implement a compatible retained path first.

## Compound Hypothesis C: Proper Publisher Thread

Potential large win requires multiple pieces together:

- Publisher owns frame deadlines.
- Publisher reads latest snapshot and coalesces stale states.
- Publisher publishes at most one prepared frame per deadline.
- UI consumes prepared frame without blocking live VT/apply.
- If UI misses a frame, publisher drops stale prepared work and replaces with latest.

Why the first publisher crumbled:
- It published whenever dirty instead of owning cadence.
- Prepared-batch availability became the wake clock.
- It moved sync off UI but did not coordinate dirty epochs with present acknowledgement correctly.

Challenge when revisiting:
- Need a clear mailbox contract: empty, preparing, ready, consumed, stale.
- Need a precise answer for who clears dirty metadata and when.

## Compound Hypothesis D: Better Benchmark Axes

We need separate scorecards:

- Producer throughput: stress generator FPS/latency.
- Render cadence: host frame p50/p95/p99 gaps.
- UI cost: host render and present timings.
- Runtime cost: term_io ingest/apply timings.
- Publication size: dirty rows, glyphs, fills, uploads.
- Resource use: CPU/RSS/thread count.

Do not accept a change that improves one score while silently wrecking another unless it is explicitly a foundation cut and recorded as such.

## Next Candidate Sprint 1: Publication Size Then Render Submission

Theory:
- The next meaningful win may require shrinking publication work and lowering renderer submission cost together.

Coupled cuts:
- Add gated metrics for dirty rows, dirty cells, copied spans, batch quad counts, snapshot age, and GL submission time.
- Change render publication to emit renderer-oriented dirty updates rather than only transient batch inputs.
- Prototype retained renderer-owned row or cell storage for visible content.
- Re-test larger ingest budgets only after the retained submission path exists.

Why this should be judged as a set:
- Metrics alone do not speed up the renderer.
- Retained cell storage alone may not help if publication still creates oversized updates.
- Larger ingest budgets should not be judged again until the publication and renderer path change together.

Exit criteria:
- either visible frame cadence improves at current smooth budget
- or larger ingest budgets become acceptable without sprint/freeze

## Next Candidate Sprint 2: Deadline-Aware Apply With Latest-Only Publication

Theory:
- Read-ahead and publisher ideas may only pay off when one owner budgets apply work against frame deadlines and stale states are coalesced aggressively.

Coupled cuts:
- Introduce a buffered PTY ingest queue.
- Add a time-budget or dirty-budget apply scheduler.
- Add latest-only publication semantics with stale prepared-state replacement.
- Make present acknowledgement feed scheduler state instead of acting as the pacing clock by itself.

Why this should be judged as a set:
- read-ahead alone just moves the queue
- publisher alone just moves work
- host pacing alone just delays oversized frames

Exit criteria:
- host frame p95/p99 stay near smooth baseline while producer throughput rises materially

## Next Candidate Sprint 3: Renderer-Owned Visible Row State On Current GL Path

Theory:
- We may be able to borrow the architectural lesson from kitty and ghostty without first changing GL profile: keep renderer-owned visible row state and update rows in place.

Coupled cuts:
- Define renderer-owned row storage in `howl-render-core`.
- Replace per-frame full transient rebuild of those rows with row invalidation and refresh.
- Track row-level text, fill, and decoration counts to verify reduced churn.
- Compare against current batch builder on hostile ascii and mixed workloads.

Why this should be judged as a set:
- row storage without invalidation policy is just more memory
- invalidation without submission changes may still leave the hot path mostly unchanged

Exit criteria:
- lower batch build cost or lower GL submission cost without pacing regressions

## Current Useful Commands

Run module benchmark:

```sh
zig build vt-core-benchmark -- --runs 3
zig build render-core-benchmark -- --runs 3
zig build howl-term-benchmark -- --runs 3
```

Run full host comparison:

```sh
python3 tools/benchmark_terminals.py --duration 10 --mode ascii --terminals howl kitty ghostty
python3 tools/benchmark_terminals.py --duration 10 --mode mixed --terminals howl kitty ghostty
```

Run traced Howl stress:

```sh
python3 tools/benchmark_terminals.py --duration 6 --mode ascii --terminals howl --trace-howl
```

Summarize trace frame gaps with a small Python helper over the produced `howl-*.trace.ndjson`.

## Open Questions

- Is renderer submission or dirty publication size the dominant visual bottleneck now?
- Would a retained GPU cell buffer make larger ingest budgets visually acceptable?
- Should apply budget be based on elapsed microseconds rather than bytes/read count?
- Do we need a separate PTY reader thread before a publisher thread, or should the runtime worker become the apply scheduler first?
- Can we trace dirty row counts and batch age without cluttering production code?
