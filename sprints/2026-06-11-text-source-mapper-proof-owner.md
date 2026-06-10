# Sprint: Text Source Mapper Proof Owner

Date: 2026-06-11.

Owner: orchestrator.

Status: active execution slice.

Orchestrator session id: `orch-2026-06-11-text-source-mapper-proof-owner-01`.
Planning orchestrator session id: `orch-2026-06-10-test-accountability-01`.
Planning researcher session ids:
- `research-2026-06-10-text-sprint-01`
- `research-2026-06-10-text-sprint-01-c1`
Execution reviewer session id: `review-2026-06-11-text-source-mapper-proof-owner-01`.
Planning reviewer session id: `review-2026-06-10-text-sprint-01`.
Required coder session id: `coder-2026-06-11-text-source-mapper-proof-owner-01`.
Required commit-hash receipt: required before slice acceptance.

## User Direction

- The accepted planning package is complete.
- The next orchestration step is execution, not more research.
- Accepted work must stay maintained by the orchestrator.
- Accepted work must carry worker ids and commit hashes as workflow receipts.

## Accepted Planning Inputs

- `sprints/done/2026-06-10-text-sprint-research.md`
- `research/done/2026-06-10-text-sprint-scratchpad.md`
- `loops/done/render-source-cell-model-research.txt`

## Problem

- Current source-to-text mapping still duplicates authority for default-background truth, inverse/selection background preservation, and empty-cell classification.
- Existing mapper proofs still encode stale local truth instead of the accepted source truth for the text sprint.
- The first execution slice must repair that owner seam without changing shipped ABI layouts and without pulling dim policy into this slice.

## Exact Slice

Slice name: `text-source-mapper-proof-owner`.

## Allowed Files

- `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig`
- `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`

Do not edit:

- `/home/home/personal/projects/howl/howl-render/src/source/vt.zig`
- `/home/home/personal/projects/howl/howl-render/include/howl_render.h`

## Required Reads

- `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig`
- `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`
- `/home/home/personal/projects/howl/howl-render/src/source/cell.zig`
- `/home/home/personal/projects/howl/howl-render/src/source/vt.zig`
- `/home/home/personal/projects/howl/utils/official_docs/kitty/color-stack.md`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/term/cell.rs`
- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`

## Required Shape

- Make one owner authoritative for default-background truth, inverse/selection background preservation, and empty-cell classification at the source-to-text mapping seam.
- Rewrite mapper proof so opaque default background and Alacritty-empty semantics are the only accepted truths for source mapping.
- Do not choose or encode a new faint or dim factor in this slice.
- Preserve source ABI owners unchanged.

Required shape targets inside the allowed files:

- `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:470-492`
- `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:518-653`
- `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:863-903`
- `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig:159-206`

## Required Assertions

- Assert `combining_len <= combining.len` at each VT and publication mapper entry.
- Assert inverse and selection transforms do not erase semantic default-background provenance.
- Assert empty-cell classification runs on semantic cell truth before any color-resolution shortcut.

## Required Tests

- `zig build test:abi -- "source text input converts VT source to text scene input"`
- `zig build test:abi -- "source text input keeps opaque default background for blank VT cell"`
- `zig build test:abi -- "source text input keeps opaque default background for blank publication cell"`
- `zig build test:abi -- "source text input keeps default background truth through inverse VT cell"`
- `zig build test:abi -- "source text input keeps default background truth through publication selection"`
- `zig build test:abi -- "source text input marks Alacritty-empty cells before color mapping"`
- `zig build test:abi -- "source text input treats foreground-colored blanks as non-empty"`

Run from:

- `/home/home/personal/projects/howl/howl-render`

## Non-Goals

- No semantic contract-shape migration.
- No scene owner changes.
- No frame-preparer control-flow changes.
- No dim or invisible factor choice.
- No source or publication C ABI changes.

## Stop Conditions

- Stop if the slice requires changing `SourceCell`, `SourceColor`, or any exported C ABI layout.
- Stop if fixing the stale mapper proofs requires choosing a numeric dim or faint factor.
- Stop if empty-cell truth cannot be expressed without contradicting Alacritty empty-cell semantics at `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/term/cell.rs:224-239`.

## Reviewer Gate

- Reviewer must be the planning reviewer lineage carried into execution.
- Reviewer must reject any file outside the allowed set.
- Reviewer must reject proof rewrites that leave mapper authority split across both allowed files.
- Reviewer must reject any ABI or dim-policy broadening.

## Acceptance Receipts

- Required from coder:
  - files changed
  - concise implementation summary
  - verification run and results
  - blockers or deviations
  - coder session id `coder-2026-06-11-text-source-mapper-proof-owner-01`
  - commit-hash handoff status
- Required from reviewer:
  - verdict `accept|reject|user needed`
  - findings with exact file references when possible
  - acceptance notes only if accepted
- Required from orchestrator before acceptance:
  - verification result
  - accepted commit hash
  - receipt closure recorded in the active loop artifact
