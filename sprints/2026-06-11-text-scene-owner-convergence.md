# Sprint: Text Scene Owner Convergence

Date: 2026-06-11.

Owner: orchestrator.

Status: active execution slice.

Orchestrator session id: `orch-2026-06-11-text-scene-owner-convergence-01`.
Planning orchestrator session id: `orch-2026-06-10-test-accountability-01`.
Planning researcher session ids:
- `research-2026-06-10-text-sprint-01`
- `research-2026-06-10-text-sprint-01-c1`
Execution reviewer session id: `review-2026-06-11-text-scene-owner-convergence-01`.
Planning reviewer session id: `review-2026-06-10-text-sprint-01`.
Required coder session id: `coder-2026-06-11-text-scene-owner-convergence-01`.
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

- `sprints/done/2026-06-11-text-source-mapper-proof-owner.md`
- `loops/done/text-source-mapper-proof-owner.txt`
- `howl-render` commit: `bbf6242`
- `sprints/done/2026-06-11-text-renderable-normal-lane-owner.md`
- `loops/done/text-renderable-normal-lane-owner.txt`
- `howl-render` commit: `bc938aa`

## Problem

- Draw construction is still split between `text/scene.zig` and `text/direct_scene.zig`.
- The accepted sprint requires one owner for backgrounds, clears, cursor draws, and non-glyph decoration draws before dim policy can honestly converge later.

## Exact Slice

Slice name: `text-scene-owner-convergence`.

## Allowed Files

- `/home/home/personal/projects/howl/howl-render/src/text/scene.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`

## Required Reads

- `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/scene.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs`
- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`

## Required Shape

- Backgrounds, clears, cursor draws, and non-glyph decoration draws must have one owner.
- `direct_scene.zig` must become an adapter or be reduced to data transport; it must not keep a second behavioral implementation of draw construction.
- Clear-color policy must be identical across normal-only and mixed or complex frames.

## Required Assertions

- Assert damage metadata lengths match grid rows at the chosen scene boundary.
- Assert merged scene slices remain sorted by `first_cell`.
- Assert cursor draw count matches cursor shape geometry on both normal-only and mixed frames.

## Required Tests

- `zig build test:unit -- "scene emits background draws from non-continuation cells"`
- `zig build test:unit -- "scene emits explicit clears for transparent default backgrounds on partial damage"`
- `zig build test:unit -- "text preparation direct-renders pure normal cell text inputs"`
- `zig build test:unit -- "text preparation marks curly underline cells complex before shaping"`

Run from:

- `/home/home/personal/projects/howl/howl-render`

## Non-Goals

- No font resolver or shaper redesign.
- No render-surface backend or host changes.

## Stop Conditions

- Stop if the slice needs host renderer ownership changes outside `howl-render`.

## Reviewer Gate

- Reviewer must reject duplicate behavioral draw construction that survives in `direct_scene.zig`.
- Reviewer must reject any split clear-color policy across normal-only and mixed paths.
- Reviewer must reject host/backend drift or shaping redesign in this slice.

## Acceptance Receipts

- Required from coder:
  - files changed
  - concise implementation summary
  - verification run and results
  - blockers or deviations
  - coder session id `coder-2026-06-11-text-scene-owner-convergence-01`
  - commit-hash handoff status
- Required from reviewer:
  - verdict `accept|reject|user needed`
  - findings with exact file references when possible
  - acceptance notes only if accepted
- Required from orchestrator before acceptance:
  - verification result
  - accepted commit hash
  - receipt closure recorded in the active loop artifact
