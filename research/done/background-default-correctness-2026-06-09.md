# Background Default Correctness

Date: 2026-06-09.
Role: researcher.
Status: active.
Primary researcher session id: `research-2026-06-09-background-default-truth-01`.
Sprint: `sprints/2026-06-09-background-default-correctness-sprint.md`.
Loop: `loops/publication-default-background-truth.txt`.

## Sources Read In Order

1. `/home/home/personal/projects/howl/AGENTS.md`
2. `/home/home/personal/projects/howl/loop/flow.md`
3. `/home/home/personal/projects/howl/loop/orcestrator.md`
4. `/home/home/personal/projects/howl/reference-index.md`
5. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
6. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
7. `/home/home/personal/projects/howl/sprints/current.txt`
8. Current Howl source:
   - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`
   - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig`
   - `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig`
   - `/home/home/personal/projects/howl/howl-render/src/text/scene.zig`
9. Current Howl tests:
   - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig`
   - `/home/home/personal/projects/howl/howl-render/src/text/scene.zig`
10. Alacritty references:
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/rects.rs`

## Current-Code Facts

- Publication mapping currently forces default background to transparent alpha:
  - `howl-render/src/source/publication_cell_map.zig:81-84`
- Publication emptiness currently treats a blank cell with transparent background as empty:
  - `howl-render/src/source/publication_cell_map.zig:137-149`
- Generic source mapping also forces default background to transparent alpha:
  - `howl-render/src/source/text_input.zig:86-89`
- Generic publication-empty truth also keys on `bg.a == 0`:
  - `howl-render/src/source/text_input.zig:156-162`
- Scene background emission skips any renderable cell whose background alpha is zero:
  - `howl-render/src/text/direct_scene.zig:94-97`
- Scene tests already encode one explicit transparency contract for partial damage clears:
  - `howl-render/src/text/scene.zig:1107-1125`

## Reference Facts

- Alacritty computes per-cell background RGB and alpha in renderable content preparation:
  - `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:211-218`
- Alacritty only treats a cell as empty when background alpha is zero and the cell is otherwise blank:
  - `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:302-307`
- Alacritty computes zero background alpha only for the named default background, with transparency policy handled explicitly in content preparation:
  - `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:388-395`
- Alacritty reduces decoration rect count later in the rect path, not by erasing color truth at the source-mapping seam:
  - `utils/dev_references/terminals/alacritty/alacritty/src/renderer/rects.rs:158-205`

## Findings

- The current regression is most likely not in host GL realization and not in `direct_scene` policy by itself.
- The primary false step is earlier: Howl source mapping is collapsing default background truth into transparent alpha before the scene stage decides what to emit.
- That early collapse explains the observed symptom:
  - apps with explicit non-default backgrounds still paint
  - ordinary cells with default background disappear into window transparency
- The same policy exists in both `publication_cell_map.zig` and `text_input.zig`, so a one-file fix would leave the source seam inconsistent.

## Proposed Shape

- Keep the correction inside the source-mapping seam first.
- Stop forcing default background to transparent alpha for ordinary mapped cells in:
  - `howl-render/src/source/publication_cell_map.zig`
  - `howl-render/src/source/text_input.zig`
- Re-evaluate emptiness truth so blank cells with default background remain skippable only when that matches the intended render policy, not because the source mapper erased the background.
- Do not start in host GL, emitter, session, or benchmark code.
- Do not erase the existing partial-damage clear contract without proof.

## Explicit Next Slice Plan

Slice name: `publication-default-background-fix`

Allowed files:

- `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`
- `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig`
- owner-local tests in those same files only if needed

Required shape:

- restore default background color truth at the source-mapping seam
- keep publication and generic source paths aligned
- preserve current selection/inverse/invisible behavior
- preserve explicit partial-damage clear behavior unless a failing test proves the contract must move

Required tests:

- `cd /home/home/personal/projects/howl/howl-render && zig build test:unit`
- targeted source/text tests must cover:
  - default background mapping truth
  - empty-cell truth for ordinary blanks
  - inverse/selection behavior with default background

Required verification:

- a real host receipt or direct visual proof on the reproducing workload after the code slice lands

## Risks

- The current transparent-default contract may have been hiding a separate partial-damage assumption.
- Publication and generic source paths have parallel logic; correcting only one will leave the seam inconsistent.
- Any emptiness-policy change can affect render cost and must not be smuggled in as a performance slice.

## Proof Gaps

- None for the correctness slice after the accepted source fix and host verification receipts below.

## Readiness Judgment

Ready for acceptance of the source-mapping correction slice and for performance work to resume from corrected behavior only.

## Accepted Verification Receipts

- Unit verification:
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:unit`
- User visual proof on the real host path:
  - main-thread user verification on 2026-06-09: “I tested, bg color is fixed”
- Honest benchmark receipt on the corrected path:
  - `/home/home/personal/projects/howl/artifacts/stress/20260609-131321-ascii/summary.json`
  - result:
    - Howl `33.16 fps`
    - Alacritty `1004.67 fps`
  - this receipt replaces the earlier dishonest performance baseline because default background truth is now restored

## Dropped Probe Logging Rule For This Sprint

- Before any future code probe is dropped, the active loop or research file must record:
  - files touched
  - tests or receipts produced
  - outcome
  - short failure hypothesis
  - restart point
