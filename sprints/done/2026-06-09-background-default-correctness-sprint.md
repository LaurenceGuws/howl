Background default-color correctness sprint

Date: 2026-06-09.
Status: active.
Orchestrator session id: `orch-2026-06-09-background-default-01`.

User direction:

- Performance work is paused.
- The live priority is the correctness regression where ordinary cells render with transparent backgrounds and the window background shines through.
- Do not drop code probes silently. Every dropped probe must be recorded with receipts, result, and a short hypothesis before the code is reverted or abandoned.

Problem statement:

- Howl currently fails to render default cell backgrounds correctly for ordinary TUIs and scrollback.
- The visible symptom is that only applications that paint explicit non-default backgrounds look correct, while ordinary text and scrollback appear transparent against the host window background.
- The sprint is complete only when default background truth is restored on the real host path and the live accountability files reflect the exact accepted and rejected work.

Dropped-probe recording rule:

- Any rejected or dropped code probe for this sprint must be recorded in the active loop or active research artifact before the code is dropped.
- The record must include:
  - exact files touched
  - exact receipts or tests run
  - measured or observed result
  - short hypothesis for why the probe failed
  - whether the failure was planning premise, owner seam, or implementation mechanics
  - the restart point for the next accountable stage

Known current-code facts:

- `howl-render/src/source/publication_cell_map.zig` currently maps publication default background to RGBA with `a = 0`.
- `howl-render/src/source/text_input.zig` currently maps default background to transparent alpha in the generic source path too.
- `howl-render/src/text/direct_scene.zig` skips background draws when `cell.bg.a == 0`.
- Existing scene behavior for transparent default backgrounds on partial damage is already explicit and tested. This sprint must not accidentally erase that contract unless the references and tests prove it wrong.

Reference-backed shape:

- Alacritty computes cell background RGB and background alpha at content preparation time.
- Empty-cell skipping depends on background alpha truth for the cell, not on an unconditional source-mapping rewrite to transparency.
- The named default background is only transparent in Alacritty when render policy says so; ordinary content does not broadly erase default background truth during source mapping.

Sequential slice queue:

1. `publication-default-background-truth`
- prove the exact owner path and reference shape for default background handling
- pin the smallest accountable correction slice
- record tests and stop conditions

2. `publication-default-background-fix`
- implement the accepted mapping correction in the source owner seam only
- preserve partial-damage transparent-clear behavior where still required
- verify against unit tests and real host rendering

3. `post-fix-correctness-verification`
- rerun the real host scenarios that exposed the regression
- record any remaining gaps before performance work is allowed to resume

Completion gate:

- Default backgrounds render correctly for ordinary cells on the real host path.
- The accepted verification receipts and tests are recorded in the live artifacts.
- No stale performance sprint artifacts remain in the active folders.
