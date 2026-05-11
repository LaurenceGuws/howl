# Performance Index

Purpose: provide one entrypoint for Howl terminal performance history, active hypotheses, and experiment records.

Last updated: 2026-05-11

## Read Order

1. `performance-hypotheses.md`
   - Current understanding of what is structurally behind Howl's gap versus kitty and ghostty.
2. `performance-strategy.md`
   - Which runtime surface should answer which performance question, and the default sprint ladder.
3. `performance-improvements.md`
   - Changes that materially improved throughput, smoothness, or measurement quality.
4. `performance-reverted-experiments.md`
   - Failed or incomplete experiments and why they broke down.
5. `performance-scratchpad.md`
   - Compound hypotheses and multi-step experiment chains that should not be judged too early.

## How To Use These Docs

- Before starting an experiment:
  - write or update the hypothesis in `performance-hypotheses.md` or `performance-scratchpad.md`
- Before starting a multi-step experiment sprint:
  - define the candidate change set and expected combined payoff in `performance-scratchpad.md`
  - decide up front which cuts are foundation-only and should not be judged in isolation
- After a successful checkpoint:
  - record the result in `performance-improvements.md`
- After a revert or failed result:
  - record the theory and why it failed in `performance-reverted-experiments.md`
- When a change only isolates a concern but does not yet improve FPS:
  - record it anyway if it changes ownership boundaries or de-risks later work
- When a partial cut is useful but not ready to keep on the main working line:
  - prefer stashing it or parking it on a side branch rather than forgetting it
  - evaluate the full compound set at the end of the sprint before concluding against the theory

## Evaluation Rules

- Do not accept raw stress FPS as the only performance signal.
- Always consider:
  - producer throughput
  - host frame cadence
  - render cost
  - lock hold time
  - dirty publication size
  - CPU/RSS/thread cost
- A revert does not mean the architecture idea was wrong.
- Some ideas require multiple companion changes before they can be judged fairly.
- Foundation cuts may temporarily worsen or fail to improve FPS while still being worth keeping for the sprint.

## Experiment Sprint Rules

- Prefer short experiment sprints over isolated one-change verdicts.
- Define the sprint first:
  - target bottleneck
  - 2-4 coupled cuts
  - exit criteria
  - which metrics can fail temporarily during the middle of the sprint
- During the sprint:
  - keep notes in `performance-scratchpad.md`
  - keep measurement checkpoints after each cut
  - do not declare the architecture theory dead until the coupled set has been tried
- If an intermediate cut is not ready to keep in the main worktree:
  - stash it with a descriptive name or park it on an experiment branch in the child repo
  - record what it changed, what depended on it, and why it was parked
- At sprint end:
  - promote actual wins to `performance-improvements.md`
  - move disproven or net-negative sets to `performance-reverted-experiments.md`
  - keep any still-plausible partial foundations in the scratchpad for recombination later
  - delete temporary sprint-tracking docs after their invariants are promoted into long-lived docs

## Current Stable Reference

As of this update, the best stable runtime reference is:

- render snapshot boundary kept
- dirty-span snapshot copy kept
- smooth ingest pacing at `16 reads / 64 KiB`
- later larger-budget, host-pacer, publisher-thread, and read/apply-split experiments reverted

Current working style preference:

- use the stable runtime reference as the comparison point
- but allow temporary compound-sprint branches or stashes before deciding whether to keep or revert a direction

## Related Files

- `howl-hosts/howl-linux-host/STRESS.md`
- `howl-term/design.md`
- `design/design-rules.md`
- `design/performance-strategy.md`
