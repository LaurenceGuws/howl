# Sprint: Text Renderable Normal Lane Owner

Date: 2026-06-11.

Owner: orchestrator.

Status: active execution slice.

Orchestrator session id: `orch-2026-06-11-text-renderable-normal-lane-owner-01`.
Planning orchestrator session id: `orch-2026-06-10-test-accountability-01`.
Planning researcher session ids:
- `research-2026-06-10-text-sprint-01`
- `research-2026-06-10-text-sprint-01-c1`
Execution reviewer session id: `review-2026-06-11-text-renderable-normal-lane-owner-01`.
Planning reviewer session id: `review-2026-06-10-text-sprint-01`.
Required coder session id: `coder-2026-06-11-text-renderable-normal-lane-owner-01`.
Required commit-hash receipt: required before slice acceptance.

## User Direction

- Orchestrate autonomously.
- After accepting a slice, commit it and move on.
- Do not stop before the sprint is done or the reviewer returns `user needed`.

## Accepted Planning Inputs

- `sprints/done/2026-06-10-text-sprint-research.md`
- `research/done/2026-06-10-text-sprint-scratchpad.md`
- `loops/done/render-source-cell-model-research.txt`

## Prior Accepted Slice Dependency

- `sprints/done/2026-06-11-text-source-mapper-proof-owner.md`
- `loops/done/text-source-mapper-proof-owner.txt`
- `howl-render` commit: `bbf6242`

## Problem

- Source mapping now preserves semantic empty/default-background truth, but the text contract seam still flattens renderable construction across multiple owners.
- The next accepted slice must make `cluster.zig` the sole renderable-cell construction owner and keep `direct_normal.zig` as a consumer of one renderable/text owner instead of rebuilding publication mapping locally.

## Exact Slice

Slice name: `text-renderable-normal-lane-owner`.

## Allowed Files

- `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/contract.zig`
- `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig`
- `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`

## Required Reads

- `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/contract.zig`
- `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig`
- `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
- `/home/home/personal/projects/howl/utils/official_docs/kitty/color-stack.md`
- `/home/home/personal/projects/howl/utils/official_docs/kitty/underlines.md`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/font/shaper/run.zig`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/c/cell.zig`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs`

## Required Shape

- Preserve semantic fg, bg, and underline provenance through the text contract seam instead of flattening source semantics to one RGBA fact before cluster and render policy run.
- `cluster.zig` becomes the sole owner for renderable-cell construction, text interning, span inference, and damage-filter inclusion.
- `direct_normal.zig` consumes one renderable/text owner for raw cells, publication cells, rich inputs, and prepared renderables.
- Publication cell mapping must not happen cell-by-cell inside `direct_normal.sourceItem`.

## Required Assertions

- Assert mapped semantic color kind is within the shipped source range before constructing any contract value that reaches cluster or renderable owners.
- Assert continuation spans are computed once and reused.
- Assert direct-normal rejection happens before any partial draw state is emitted when a non-normal candidate appears under `require_all_normal`.

## Required Tests

- `zig build test:unit -- "cell inputs build text cache renderable cells clusters and runs"`
- `zig build test:unit -- "partial damage filters clean clusters before shaping"`
- `zig build test:unit -- "text preparation direct-renders pure normal cell text inputs"`
- `zig build test:unit -- "text preparation keeps mixed cell text normals out of legacy path"`

Run from:

- `/home/home/personal/projects/howl/howl-render`

## Non-Goals

- No glyph shaping algorithm changes.
- No scene owner convergence.
- No ABI export changes.

## Stop Conditions

- Stop if the slice needs unread shaping owners outside the current read pack to stay correct.

## Reviewer Gate

- Reviewer must reject any fallback to duplicate renderable construction outside `cluster.zig`.
- Reviewer must reject any publication cell-by-cell remapping inside `direct_normal.sourceItem`.
- Reviewer must reject shaping-owner redesign, scene convergence work, or ABI drift in this slice.

## Acceptance Receipts

- Required from coder:
  - files changed
  - concise implementation summary
  - verification run and results
  - blockers or deviations
  - coder session id `coder-2026-06-11-text-renderable-normal-lane-owner-01`
  - commit-hash handoff status
- Required from reviewer:
  - verdict `accept|reject|user needed`
  - findings with exact file references when possible
  - acceptance notes only if accepted
- Required from orchestrator before acceptance:
  - verification result
  - accepted commit hash
  - receipt closure recorded in the active loop artifact
