# Perf Logging Blocker Scratchpad

Owner: workspace root.

Purpose:

- Track the perf logging subsystem as a new blocker.
- Treat it as either removal or deep redesign work, not incremental patching.

## Trigger

- Host run still aborts with `free(): double free detected in tcache 2`.
- Current suspicion is that the perf logger thread and/or perf logger state is involved until proved otherwise.

## Current Working Hypothesis

- The perf logger thread, state ownership, or teardown contract is the cause of the crash until disproven.

## Requirement

- Investigation and any follow-up design must meet production TigerBeetle-style quality gates:
  - explicit ownership
  - bounded behavior
  - directness
  - audited teardown
  - no hand-waving

## Scope

- Investigate whether perf logging should:
  - be removed entirely
  - be radically simplified
  - be redesigned around a smaller owner-true contract

## Constraint

- This is large enough to require its own research loop and documented plan before implementation.
