# Sprint: Text Publication Full Path

Date: 2026-06-11.

Owner: orchestrator.

Status: active execution slice.

Orchestrator session id: `orch-2026-06-11-text-publication-full-path-01`.
Planning orchestrator session id: `orch-2026-06-10-test-accountability-01`.
Planning researcher session ids:
- `research-2026-06-10-text-sprint-01`
- `research-2026-06-10-text-sprint-01-c1`
Execution reviewer session id: `review-2026-06-11-text-publication-full-path-01`.
Planning reviewer session id: `review-2026-06-10-text-sprint-01`.
Required coder session id: `coder-2026-06-11-text-publication-full-path-01`.
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

- `howl-render` commits:
  - `bbf6242`
  - `bc938aa`
  - `74db9a4`

## Problem

- Publication still does not fully enter the same normal-then-complex pipeline as raw VT cells and rich inputs.
- The accepted sprint requires publication damage, cursor, selection, and color-state facts to reach the same cluster and scene owners as VT source facts, without returning `null` mixed or complex publication frames.

## Exact Slice

Slice name: `text-publication-full-path`.

## Allowed Files

- `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig`
- `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig`
- `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`

## Required Reads

- `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
- `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig`
- `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`
- `/home/home/personal/projects/howl/utils/official_docs/kitty/color-stack.md`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/style.zig`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs`

## Required Shape

- Publication must enter the same normal-then-complex pipeline as raw VT cells and rich inputs.
- `preparePublicationWithSessionOptions` may not return `null` for mixed or complex text once the slice lands.
- Publication damage, cursor, selection, and color-state facts must arrive at the same cluster and scene owners as VT source facts.

## Required Assertions

- Assert publication complex-cell counts match lane-report complex-cell counts before shaping.
- Assert publication path reaches the same scene owner as raw cells when direct normal rejects.

## Required Tests

- `zig build test:abi -- "source text input borrowed publication mapping reuses caller storage"`
- `zig build test:abi -- "source text input borrowed publication mapping applies selection styling across scrollback rows"`
- `zig build test:unit -- "text preparation prepares mixed publication cells through non-null publication frame"`
- `zig build test:unit -- "text preparation prepares complex publication cells through non-null publication frame"`

Run from:

- `/home/home/personal/projects/howl/howl-render`

## Non-Goals

- No `SourceCell` layout changes.
- No exported symbol changes.

## Stop Conditions

- Stop if publication needs a different host-facing ABI contract instead of the current source/publication contract.
- Stop if the slice cannot prove non-null mixed and complex publication frames inside `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`.

## Reviewer Gate

- Reviewer must reject any separate publication-only lane that bypasses the established normal-then-complex owners.
- Reviewer must reject `null` mixed or complex publication frames after the slice lands.
- Reviewer must reject ABI drift or source-layout changes.

## Acceptance Receipts

- Required from coder:
  - files changed
  - concise implementation summary
  - verification run and results
  - blockers or deviations
  - coder session id `coder-2026-06-11-text-publication-full-path-01`
  - commit-hash handoff status
- Required from reviewer:
  - verdict `accept|reject|user needed`
  - findings with exact file references when possible
  - acceptance notes only if accepted
- Required from orchestrator before acceptance:
  - verification result
  - accepted commit hash
  - receipt closure recorded in the active loop artifact
