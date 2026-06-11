# Sprint: Text Style Attrs Render Policy Owner

Date: 2026-06-11.

Owner: orchestrator.

Status: active execution slice.

Orchestrator session id: `orch-2026-06-11-text-style-attrs-render-policy-owner-01`.
Planning orchestrator session id: `orch-2026-06-10-test-accountability-01`.
Planning researcher session ids:
- `research-2026-06-10-text-sprint-01`
- `research-2026-06-10-text-sprint-01-c1`
- `research-2026-06-10-text-sprint-01-c2`
- `research-2026-06-10-text-sprint-01-c3`
Execution reviewer session id: `review-2026-06-11-text-style-attrs-render-policy-owner-01`.
Planning reviewer session id: `review-2026-06-10-text-sprint-01`.
Required coder session id: `coder-2026-06-11-text-style-attrs-render-policy-owner-01`.
Required commit-hash receipt: required before slice acceptance.

## User Direction

- Orchestrate autonomously.
- After accepting a slice, commit it and move on.
- Do not stop before the sprint is done or the reviewer returns `user needed`.

## Accepted Planning Inputs

- `sprints/done/2026-06-10-text-sprint-research.md`
- `research/done/2026-06-10-text-sprint-scratchpad.md`
- `loops/done/render-source-cell-model-research.txt`

## Prerequisites Now Satisfied

- `text-scene-owner-convergence` landed in `howl-render` `74db9a4`.
- The publication path now reaches the same shared scene owner in `howl-render` `603c0f1`.
- This unlocks the planned render-time dim-policy owner work.

## Problem

- Dim and invisible are still not preserved as semantic style facts through the text contract seam.
- Mapper-side dim rules remain stale policy owners until this slice moves dim realization to the surviving render-time owner.

## Exact Slice

Slice name: `text-style-attrs-render-policy-owner`.

## Allowed Files

- `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig`
- `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/contract.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/scene.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/buffer.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/owner_test.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter_test.zig`

## Required Reads

- `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig`
- `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/contract.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/scene.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/buffer.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/owner_test.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter_test.zig`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/kitty/docs/misc-protocol.rst`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/kitty/docs/changelog.rst`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/kitty/kitty/options/definition.py`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/kitty/kitty/options/types.py`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/kitty/kitty/cell_vertex.glsl`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs`

## Required Shape

- Preserve dim and invisible as semantic style facts through `text/contract.zig` instead of resolving them inside source or publication mappers.
- `text/scene.zig` is now the planned render-time dim policy owner and must apply Kitty `dim_opacity = 0.4` when constructing draw colors.
- `prepared/buffer.zig` and `prepared/render_surface_emitter.zig` must remain generic alpha consumers of `draw.color.a`; they must not invent dim policy.
- Delete both current mapper-side dim rules (`66%` and `50%`) from the source and publication bridge owners.

## Required Assertions

- Assert invisible does not erase background truth needed by scene clear and background policy.
- Assert dim behavior is entered through one owner only.
- Assert the surviving text draw-construction owner writes draw alpha from Kitty `dim_opacity = 0.4`, leaving RGB unchanged.
- Assert prepared realization consumes `draw.color.a` unchanged rather than recomputing dim in `prepared/buffer.zig` or `prepared/render_surface_emitter.zig`.

## Required Tests

- `zig build test:abi -- "source text input maps publication style attrs dim and invisible"`
- `zig build test:unit -- "text scene applies kitty dim opacity at render-time for sprite draws"`
- `zig build test:unit -- "render surface surface emitter realizes kitty dim alpha sprite equal to full rgba oracle"`
- `zig build test:unit -- "render surface prepared owner surface equals kitty dim rgba oracle"`
- `zig build test:unit -- "publication cell map keeps default background truth through inverse and selection"`

Run from:

- `/home/home/personal/projects/howl/howl-render`

## Non-Goals

- No new faint or dim factor invention.
- No host or backend styling work.

## Stop Conditions

- Stop if `text/contract.zig` still cannot carry a dim semantic fact to the render-policy owner.
- Stop if the slice needs a factor other than Kitty `dim_opacity = 0.4`.
- Stop if the slice cannot move dim realization out of mapper-side RGB mutation without changing shipped source or publication ABI layouts.

## Reviewer Gate

- Reviewer must reject any surviving mapper-side dim policy.
- Reviewer must reject any prepared-layer recomputation of dim.
- Reviewer must reject any factor other than Kitty `dim_opacity = 0.4`.

## Acceptance Receipts

- Required from coder:
  - files changed
  - concise implementation summary
  - verification run and results
  - blockers or deviations
  - coder session id `coder-2026-06-11-text-style-attrs-render-policy-owner-01`
  - commit-hash handoff status
- Required from reviewer:
  - verdict `accept|reject|user needed`
  - findings with exact file references when possible
  - acceptance notes only if accepted
- Required from orchestrator before acceptance:
  - verification result
  - accepted commit hash
  - receipt closure recorded in the active loop artifact
