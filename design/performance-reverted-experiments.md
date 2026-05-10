# Reverted Performance Experiments

Purpose: preserve what we tried, what happened, and why the original theory did not hold in practice.

Last updated: 2026-05-05

## Frame-Paced Snapshot Publication In Runtime Thread

Theory:
- Move render publication out of the UI path so the UI consumes published state and PTY ingest can run hotter.

What happened:
- Moving `syncSnapshotFromCore()` into the runtime thread made the ingest path pay render-projection cost.
- ASCII and mixed throughput regressed.

Why it crumbled:
- The publication work was not cheap enough to put on the PTY thread.
- It moved contention rather than removing it.

Decision:
- Reverted.
- Kept the broader lesson: build a data boundary first, then add scheduler/threading semantics.

## Larger Ingest Budgets Before Proper Pacing

Theory:
- After reducing render lock time, increase PTY ingest budget to recover throughput.

What happened:
- `32 reads / 128 KiB` and `64 reads / 256 KiB` improved producer FPS.
- Visual pacing regressed into sprint/freeze.
- Trace examples showed host frame gaps moving from roughly `9-11ms` to `20-70ms+` ranges depending on budget.

Why it crumbled:
- Larger chunks created larger dirty publications.
- The renderer then had fewer, heavier visible updates.
- Raw producer throughput improved but user-perceived smoothness got worse.

Decision:
- Restored `16 reads / 64 KiB` as the smooth baseline.

## Naive Publisher Thread With Prepared Batch Handoff

Theory:
- Add a publisher thread to prepare batches off the UI path while GL submission remains UI-owned.

What happened:
- `sync_us` on UI frames dropped to zero.
- Lock time dropped significantly.
- Rendered-frame cadence regressed, with p95 frame gaps around `19ms` in traced runs.

Why it crumbled:
- The publisher did not have a mature frame scheduler or latest-only mailbox policy.
- Prepared-batch availability became the new pacing driver.
- The thread moved work but did not coordinate frame cadence correctly.

Decision:
- Reverted.
- Kept the lesson: a publisher thread must be paired with a scheduler/deadline model and stale-state coalescing.

## Published-Batch Wake Semantics

Theory:
- Wake the host only when a prepared batch is available so the UI does not render raw VT dirtiness.

What happened:
- Mechanically worked, but host cadence was still worse than the smooth baseline.
- Duplicate/stale batch timing and producer/consumer mismatch became visible.

Why it crumbled:
- Batch availability alone is not a good scheduling clock.
- It needs frame-deadline ownership and a clear policy for latest-only consumption.

Decision:
- Reverted with the publisher thread experiment.

## Host Frame Pacer With Larger Ingest Budget

Theory:
- Keep terminal dirtiness sticky and render at a target interval so larger ingest chunks do not directly dictate frame timing.

What happened:
- Larger ingest still produced oversized dirty frames.
- Host frame p50/p95 stayed poor under `64 reads / 256 KiB`.

Why it crumbled:
- Delaying presentation cannot make a too-large render publication cheap.
- The problem was not only host wake timing; it was the amount of changed state per publication.

Decision:
- Reverted.

## PTY Read-Ahead Buffer With Smaller Apply Chunks

Theory:
- Read PTY aggressively into an internal buffer, but apply/publish smaller chunks to preserve smoothness.

What happened:
- Initial version hot-looped on internal buffered bytes and starved host rendering.
- Adding a yield restored frame cadence but reduced producer throughput too much.
- Increasing apply cap recovered throughput but regressed frame pacing.

Why it crumbled:
- Read-ahead without a real apply scheduler just moves the queue from PTY/kernel into Howl.
- Apply chunk size still controls dirty publication size and visible frame cost.

Decision:
- Reverted.
- Kept the lesson: read-ahead needs a scheduler that budgets apply work by frame deadline and backlog, not a fixed cap plus sleep.

## Non-Blocking UI Render Try-Lock

Theory:
- If the UI cannot acquire the runtime lock, skip the render attempt and keep the event loop responsive.

What happened:
- Metrics were effectively unchanged.

Why it crumbled:
- It was a scheduling heuristic, not a real concern separation.
- The UI was not primarily blocked in a way this could exploit.

Decision:
- Reverted.

## Shift-Based HistoryLine Reuse

Theory:
- Reuse old scrollback history line buffers after history capacity is reached.

What happened:
- It improved small module benchmarks but shifted the whole retained history line array when full.
- That was risky for default `4096` history capacity.

Why it crumbled:
- Reuse was correct in spirit but had the wrong data structure behavior.

Decision:
- Replaced with ring-slot reuse.

## Working Rule For Reverts

Revert does not mean the original architectural direction was wrong. It can mean the cut was incomplete, sequenced too early, or missing companion changes. Keep this record so we can revisit compound hypotheses deliberately.

Additional working rule:
- do not default to immediate permanent reverts during a live experiment sprint.
- if a cut appears necessary for a coupled theory but is not yet fit to keep on the main line, stash it or park it on an experiment branch with notes.
- only write the final negative conclusion here after the combined sprint result is clear.
