# Sprint: Text Proof Surface Consolidation

Date: 2026-06-11.

Owner: orchestrator.

Status: active execution slice.

Orchestrator session id: `orch-2026-06-11-text-proof-surface-consolidation-01`.
Planning orchestrator session id: `orch-2026-06-10-test-accountability-01`.
Planning researcher session ids:
- `research-2026-06-10-text-sprint-01`
- `research-2026-06-10-text-sprint-01-c1`
Execution reviewer session id: `review-2026-06-11-text-proof-surface-consolidation-01`.
Planning reviewer session id: `review-2026-06-10-text-sprint-01`.
Required coder session id: `coder-2026-06-11-text-proof-surface-consolidation-01`.
Required commit-hash receipt: required before slice acceptance.

## User Direction

- Orchestrate autonomously.
- After accepting a slice, commit it and move on.
- Do not stop before the sprint is done or the reviewer returns `user needed`.

## Accepted Planning Inputs

- `sprints/done/2026-06-10-text-sprint-research.md`
- `research/done/2026-06-10-text-sprint-scratchpad.md`
- `loops/done/render-source-cell-model-research.txt`

## Prior Accepted Slice Dependencies

- accepted commits in `howl-render`:
  - `bbf6242`
  - `bc938aa`
  - `74db9a4`
  - `603c0f1`
  - `3a79b00`

## Problem

- The owner and behavior work is now landed, but the proof surface still contains stale tests and incomplete full-suite closure risk.
- The final slice must leave one proof owner for mapper truth, one for renderable or cluster truth, one for scene draw truth, and one full-pipeline frame proof while preserving `test:unit` and `test:abi` as the shipped roots.

## Exact Slice

Slice name: `text-proof-surface-consolidation`.

## Allowed Files

- `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig`
- `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/scene.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
- `/home/home/personal/projects/howl/howl-render/build.zig`

## Required Reads

- `/home/home/personal/projects/howl/howl-render/build.zig`
- `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig`
- `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/scene.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`

## Required Shape

- Delete or rewrite stale tests that encode alpha-hack semantics or duplicated owner behavior.
- Leave one proof owner for mapper truth, one for renderable or cluster truth, one for scene draw truth, and one full-pipeline frame proof.
- Preserve `test:unit` and `test:abi` as the shipped proof roots.

## Required Assertions

- Assert build-time test font options resolve to tracked repo-owned fixtures.
- Assert no text-stack failures remain in the full ABI suite.

## Required Tests

- `zig build test:unit`
- `zig build test:abi`

Run from:

- `/home/home/personal/projects/howl/howl-render`

## Non-Goals

- No benchmark work.
- No host runtime changes.

## Stop Conditions

- Stop if unrelated non-text failures appear; record them as external blockers and stop instead of hiding them inside the text sprint.

## Reviewer Gate

- Reviewer must reject stale alpha-hack proofs that survive the landed owner changes.
- Reviewer must reject proof sprawl that weakens the curated `test:unit` and `test:abi` roots.
- Reviewer must return `user needed` only if a blocker is genuinely outside the text sprint slice.

## Acceptance Receipts

- Required from coder:
  - files changed
  - concise implementation summary
  - verification run and results
  - blockers or deviations
  - coder session id `coder-2026-06-11-text-proof-surface-consolidation-01`
  - commit-hash handoff status
- Required from reviewer:
  - verdict `accept|reject|user needed`
  - findings with exact file references when possible
  - acceptance notes only if accepted
- Required from orchestrator before acceptance:
  - verification result
  - accepted commit hash
  - receipt closure recorded in the active loop artifact
