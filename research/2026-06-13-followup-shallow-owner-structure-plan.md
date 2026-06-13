# Followup Shallow Owner Structure Plan

Date: 2026-06-13.

Status: repaired planning artifact; reviewer re-gate required.

Role owner: researcher.

Orchestrator session id: `orch-2026-06-13-followup-shallow-structure-01`.

Researcher session id: `research-2026-06-13-followup-shallow-structure-01`.

Reviewer session id: `review-2026-06-13-followup-shallow-structure-01`.

Planning seed commit-hash receipt: root `66927e2`.

Planning package commit-hash receipt: root `04aa1b2`.

Question:

- What source-backed follow-up sprint should run next to delete any remaining fake abstractions or needless depth under current package `src/` trees after the completed all-src flattening pass, while preserving only true owner subdomains and exact proof obligations?

## Required Research Output

- Sources read in order.
- Exact files and line references.
- Current-code facts.
- Reference facts.
- Compact anchor map.
- Owner roles and proposed folder/file shape.
- Sprint scratchpad.
- Explicit ordered slice plan.
- Required assertions.
- Required tests.
- Risks.
- Proof gaps.
- Readiness judgment.

## Mandatory Research Pressure

- Current post-sprint `src/` trees in all workspace packages.
- Current build/test roots and any lingering wrapper/folder seams.
- `reference-index.md` pressure.
- TigerBeetle ownership/directness/test discipline.
- The prior all-src flattening sprint is historical navigation only; every reused fact must be re-proved.

## Planning Constraints

- No implementation in research.
- No compatibility shims.
- No fake wrapper folders.
- No broad globs where exact files are knowable.
- No ABI/export renames.
- If nothing meaningful remains, say so explicitly with proof.

## Reviewer Gate

- Reviewer must reject stale-history reasoning, vague remaining debt claims, fake cleanup for its own sake, missing exact files/tests, or any plan that leaves coder invention about what survived the first sprint.

## Sources Read In Order

1. `/home/home/personal/projects/howl/loop/flow.md`
2. `/home/home/personal/projects/howl/loop/orcestrator.md`
3. `/home/home/personal/projects/howl/loop/researcher.md`
4. `/home/home/personal/projects/howl/loop/reviewer.md`
5. `/home/home/personal/projects/howl/loop/coder.md`
6. `/home/home/personal/projects/howl/loop/researcher.md` reread as the active role contract
7. `/home/home/personal/projects/howl/sprints/current.txt`
8. `/home/home/personal/projects/howl/loops/followup-shallow-owner-structure-live-loop.txt`
9. `/home/home/personal/projects/howl/research/2026-06-13-followup-shallow-owner-structure-plan.md`
10. `/home/home/personal/projects/howl/reference-index.md`
11. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
12. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
13. Current package source and build/test roots:
   - `/home/home/personal/projects/howl/howl-pty/build.zig`
   - `/home/home/personal/projects/howl/howl-vt/build.zig`
   - `/home/home/personal/projects/howl/howl-render/build.zig`
   - `/home/home/personal/projects/howl/howl-linux-host/build.zig`
   - `/home/home/personal/projects/howl/howl-pty/src/libhowl_pty.zig`
   - `/home/home/personal/projects/howl/howl-vt/src/libhowl_vt.zig`
   - `/home/home/personal/projects/howl/howl-vt/src/howl_vt.zig`
    - `/home/home/personal/projects/howl/howl-vt/src/parser.zig`
    - `/home/home/personal/projects/howl/howl-vt/src/parser/owned_actions.zig`
    - `/home/home/personal/projects/howl/howl-vt/src/parser/string_control.zig`
    - `/home/home/personal/projects/howl/howl-vt/src/parser/events.zig`
   - `/home/home/personal/projects/howl/howl-vt/src/ffi/main.zig`
   - `/home/home/personal/projects/howl/howl-vt/src/screen.zig`
   - `/home/home/personal/projects/howl/howl-vt/src/terminal.zig`
   - `/home/home/personal/projects/howl/howl-vt/src/publication.zig`
   - `/home/home/personal/projects/howl/howl-vt/src/kitty/protocol.zig`
   - `/home/home/personal/projects/howl/howl-vt/src/vocabulary.zig`
   - `/home/home/personal/projects/howl/howl-vt/test_unit.zig`
   - `/home/home/personal/projects/howl/howl-vt/test_ffi.zig`
   - `/home/home/personal/projects/howl/howl-vt/simulation/protocol.zig`
   - `/home/home/personal/projects/howl/howl-vt/simulation/scrollback.zig`
   - `/home/home/personal/projects/howl/howl-render/src/libhowl_render.zig`
   - `/home/home/personal/projects/howl/howl-render/src/test_unit.zig`
   - `/home/home/personal/projects/howl/howl-render/src/test/unit/root.zig`
   - `/home/home/personal/projects/howl/howl-render/src/test_abi.zig`
   - `/home/home/personal/projects/howl/howl-render/src/text/session.zig`
   - `/home/home/personal/projects/howl/howl-render/src/text/shape/run.zig`
   - `/home/home/personal/projects/howl/howl-render/src/surface/handle.zig`
   - `/home/home/personal/projects/howl/howl-render/src/vt_publication/publication.zig`
   - `/home/home/personal/projects/howl/howl-linux-host/src/main.zig`
   - `/home/home/personal/projects/howl/howl-linux-host/src/config/config.zig`
   - `/home/home/personal/projects/howl/howl-linux-host/src/display/display.zig`
   - `/home/home/personal/projects/howl/howl-linux-host/src/input/input.zig`
   - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/term.zig`
14. Reference anchors for the remaining seam decisions:
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/config/mod.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/input/mod.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/Parser.zig`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/c/main.zig`

## Current-Code Facts

### Compact package scan

- `howl-pty/src/` is already shallow. The current tree contains only top-level owner files: `unix.zig`, `libhowl_pty.zig`, `pty.zig`, `posix.zig`, `ffi.zig`, and `session.zig`. Its shipped export root stays direct through `src/libhowl_pty.zig:1-19` and does not hide behind an extra source folder wrapper.
- `howl-vt/src/` no longer has a current parser owner file at `src/parser/main.zig`. The owner body now lives at `src/parser.zig:1-658`, while `src/ffi/main.zig` remains the one still-existing nested `main.zig` seam under current product source.
- `howl-render/src/` still has one pure unit-test wrapper chain: `build.zig:53-68` points the unit root at `src/test_unit.zig`, and `src/test_unit.zig:1-3` immediately forwards into `src/test/unit/root.zig:1-12`.
- `howl-linux-host/src/` still contains same-name folder/file seams at `src/config/config.zig`, `src/display/display.zig`, and `src/input/input.zig`, but each one is a substantial owner file rather than a pass-through wrapper: `config/config.zig:13-74`, `display/display.zig:57-225`, and `input/input.zig:68-260`.

### Remaining debt that is still meaningful

1. The VT parser root flattening is only partially complete in the current tree.
   - The parser owner body now lives at `howl-vt/src/parser.zig:1-658`.
   - Current source proves the prior nineteen external importer retargets are already in place at the shallow owner root:
     - Product-source importers:
       - `howl-vt/src/vocabulary.zig:1`
       - `howl-vt/src/stream_terminal.zig:4`
       - `howl-vt/src/terminal.zig:6`
       - `howl-vt/src/host_state.zig:6`
       - `howl-vt/src/osc.zig:3`
       - `howl-vt/src/howl_vt.zig:8`
       - `howl-vt/src/csi_params.zig:3`
       - `howl-vt/src/screen.zig:4`
       - `howl-vt/src/screen/style.zig:2`
     - Unit-test importers reached by `howl-vt/test/unit.zig:5-20` through `howl-vt/test_unit.zig:1-4`:
       - `howl-vt/test/unit/csi_mapping_test.zig:4`
       - `howl-vt/test/unit/terminal_surface_test.zig:2`
       - `howl-vt/test/unit/screen_test.zig:4`
       - `howl-vt/test/unit/report_test.zig:3`
       - `howl-vt/test/unit/route_test.zig:4`
       - `howl-vt/test/unit/screen/write_test.zig:4`
       - `howl-vt/test/unit/parser/csi_test.zig:3`
       - `howl-vt/test/unit/parser/events_test.zig:3`
       - `howl-vt/test/unit/parser/main_test.zig:3`
       - `howl-vt/test/unit/parser/string_control_test.zig:3`
   - `howl-vt/src/parser/main.zig` is absent in current source, but three internal parser helpers still import the deleted path today:
     - `howl-vt/src/parser/owned_actions.zig:2`
     - `howl-vt/src/parser/string_control.zig:2`
     - `howl-vt/src/parser/events.zig:1`
   - Those stale helper imports are still live proof roots rather than dead files:
     - `howl-vt/src/parser.zig:3` imports `parser/string_control.zig`
     - `howl-vt/src/stream_terminal.zig:2` imports `parser/events.zig`
     - `howl-vt/src/route.zig:6` imports `parser/events.zig`
     - `howl-vt/src/dcs.zig:1` imports `parser/events.zig`
     - `howl-vt/src/howl_vt.zig:9` imports `parser/owned_actions.zig`
     - `howl-vt/test/unit/parser/main_test.zig:2` imports `parser/owned_actions.zig`
     - `howl-vt/test/unit/parser/string_control_test.zig:2` and `:4` import `parser/owned_actions.zig` and `parser/string_control.zig`
     - `howl-vt/test/unit/parser/events_test.zig:2` imports `parser/events.zig`
   - The rest of the VT owner roots already use the shallower pattern in the same package, for example `screen.zig:1-320`, `terminal.zig:1-272`, and `publication.zig:1-39` keep the owner file at `src/<owner>.zig` and leave the helper files in `src/<owner>/`.

2. Render unit-test wiring still spends one fake wrapper file plus one fake wrapper folder level on a curated proof root.
    - `howl-render/build.zig:53-68` chooses `src/test_unit.zig` as the unit root.
    - `howl-render/src/test_unit.zig:1-3` does nothing except import `test/unit/root.zig`.
    - `howl-render/src/test/unit/root.zig:1-12` is the real curated list of unit proofs:
      - `howl-render/src/surface/realizer_test.zig:1`
      - `howl-render/src/surface/emitter_test.zig:1`
      - `howl-render/src/surface/handle_test.zig:1`
      - `howl-render/src/geometry_test.zig:1`
      - `howl-render/src/render_session.zig:1`
      - `howl-render/src/submitted_surface.zig:1`
      - `howl-render/src/c/text_session_test.zig:1`
      - `howl-render/src/c/submission_test.zig:1`
      - `howl-render/src/text/ft_hb/support_test.zig:1`
      - `howl-render/src/text/raster/special_test.zig:1`
    - This is current-source proof of an avoidable two-step wrapper chain under `src/` with no product owner behind it.

### Current seams that looked suspicious but did not survive source-backed pressure

1. `howl-vt/src/ffi/main.zig` is not currently meaningful fake-abstraction debt.
   - `howl-vt/src/libhowl_vt.zig:1-32` imports `ffi/main.zig` once and exports the shipped C ABI from there.
   - `howl-vt/src/ffi/main.zig:1-101` is a real C-surface aggregator for many contract translation files, not a no-op wrapper.
   - `howl-vt/test_ffi.zig:1-24` also uses that same FFI aggregation seam.

2. `howl-linux-host/src/config/config.zig`, `src/display/display.zig`, and `src/input/input.zig` are not current-source proof of fake wrappers.
   - They own real host logic today rather than only forwarding imports: `config/config.zig:13-74`, `display/display.zig:57-225`, `input/input.zig:68-260`.
   - The host also does not route all terminal code through a fake folder root. `src/terminal/term.zig:17-233` is one specific owner among many peers under `src/terminal/`, not a deleted-wrapper regression.

3. The remaining render subfolders are owner-true by current source, not thin folders.
   - `src/surface/handle.zig:62-240` owns prepared-handle lifecycle.
   - `src/text/session.zig:1-188` owns font-face selection and provider rules.
   - `src/text/shape/run.zig:1-220` owns shape-run data and shaping flow.
   - `src/vt_publication/publication.zig:18-235` owns retained VT publication copies and validation.

## Reference Facts

1. TigerBeetle requires a minimum of excellent abstractions and rejects extra abstraction layers that do not earn their keep. `TIGER_STYLE.md:90-99` says to use only very simple explicit control flow and only a minimum of excellent abstractions.
2. TigerBeetle says naming and structure must carry crisp domain truth instead of convenience wrappers. `TIGER_STYLE.md:273-281` and `315-335` pressure exact nouns and top-down owner order.
3. Ghostty keeps the parser owner as a direct named owner file, not a nested `main.zig` wrapper. `utils/dev_references/terminals/ghostty/src/terminal/Parser.zig:1-10` shows the parser owner living directly at the owner name.
4. Ghostty keeps the C-facing VT aggregation seam under a dedicated `c/main.zig` owner surface. `utils/dev_references/terminals/ghostty/src/terminal/c/main.zig:4-44` and `45-60` show the C API aggregator pattern that supports keeping Howl's `ffi/main.zig` until stronger contradictory pressure exists.
5. Alacritty keeps host display, input, and config as real folder owners with a root module file plus owner children.
   - `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:45-68`
   - `utils/dev_references/terminals/alacritty/alacritty/src/input/mod.rs:41-54`
   - `utils/dev_references/terminals/alacritty/alacritty/src/config/mod.rs:13-37`
   Those references justify keeping current host folder boundaries where the file is a real owner, instead of flattening host source just for depth reduction.

## Compact Anchor Map

- TigerBeetle abstraction pressure: `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:90-99`, `273-281`, `315-335`
- Ghostty VT parser owner seam: `utils/dev_references/terminals/ghostty/src/terminal/Parser.zig:1-10`
- Ghostty C-facing VT aggregator seam: `utils/dev_references/terminals/ghostty/src/terminal/c/main.zig:4-60`
- Alacritty host folder-owner seams:
  - `utils/dev_references/terminals/alacritty/alacritty/src/config/mod.rs:13-37`
  - `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:45-68`
  - `utils/dev_references/terminals/alacritty/alacritty/src/input/mod.rs:41-54`
- Current Howl shallow-owner seams that already match the desired shape:
  - `howl-vt/src/screen.zig:1-320`
  - `howl-vt/src/terminal.zig:1-272`
  - `howl-vt/src/publication.zig:1-39`
  - `howl-pty/src/libhowl_pty.zig:1-19`
- Current Howl remaining debt anchors:
  - `howl-vt/src/parser.zig:1-658`
  - `howl-vt/src/parser/owned_actions.zig:2`
  - `howl-vt/src/parser/string_control.zig:2`
  - `howl-vt/src/parser/events.zig:1`
  - `howl-vt/src/vocabulary.zig:1`
  - `howl-vt/src/stream_terminal.zig:2` and `:4`
  - `howl-vt/src/terminal.zig:6`
  - `howl-vt/src/host_state.zig:6`
  - `howl-vt/src/osc.zig:3`
  - `howl-vt/src/howl_vt.zig:8-9`
  - `howl-vt/src/csi_params.zig:3`
  - `howl-vt/src/screen.zig:4`
  - `howl-vt/src/screen/style.zig:2`
  - `howl-vt/src/route.zig:6`
  - `howl-vt/src/dcs.zig:1`
  - `howl-vt/test_unit.zig:1-4`
  - `howl-vt/test/unit.zig:5-20`
  - `howl-vt/test/unit/csi_mapping_test.zig:4-5`
  - `howl-vt/test/unit/terminal_surface_test.zig:2`
  - `howl-vt/test/unit/screen_test.zig:4`
  - `howl-vt/test/unit/report_test.zig:3-4`
  - `howl-vt/test/unit/route_test.zig:4-5`
  - `howl-vt/test/unit/screen/write_test.zig:4`
  - `howl-vt/test/unit/parser/csi_test.zig:2-3`
  - `howl-vt/test/unit/parser/events_test.zig:2-3`
  - `howl-vt/test/unit/parser/main_test.zig:2-3`
  - `howl-vt/test/unit/parser/string_control_test.zig:2-4`
  - `howl-render/build.zig:53-68`
  - `howl-render/src/test_unit.zig:1-3`
  - `howl-render/src/test/unit/root.zig:1-12`

## Owner Roles And Proposed Shape

### VT parser owner

- Owner role: parser state machine owner for VT input parsing.
- Current shape debt: the owner body already lives at `src/parser.zig`, but three internal helper files still import deleted `src/parser/main.zig` while the rest of the package already uses the shallower `src/<owner>.zig` pattern.
- Required shape:
  - keep `howl-vt/src/parser.zig` as the parser owner file
  - keep helper files under `howl-vt/src/parser/`
  - do not recreate `howl-vt/src/parser/main.zig`
  - update the three stale internal helper imports to use `@import("../parser.zig")`
- Explicit non-shape: do not flatten helper files like `parse_table.zig`, `owned_actions.zig`, `string_control.zig`, or `utf8.zig` unless the slice proves they are wrappers too. Current source does not prove that.

### Render unit proof root

- Owner role: curated unit-test root only.
- Current shape debt: `src/test_unit.zig` is a wrapper and `src/test/unit/root.zig` is the real root.
- Required shape:
  - make `howl-render/src/test_unit.zig` the sole curated unit-test root by importing the concrete tests directly there
  - delete `howl-render/src/test/unit/root.zig`
  - remove the now-empty `src/test/unit/` path from the current source tree as a consequence of deleting the file
- Explicit non-shape: do not move ABI tests, benchmark roots, or product owners.

## Sprint Scratchpad

- Full problem statement: re-prove the current post-all-src tree and queue only the remaining meaningful shallow-depth and fake-abstraction debt under package `src/` trees.
- User direction preserved:
  - continue
  - keep deleting fake abstractions
  - keep `src/` directories as shallow as possible
  - use the deleted terminal wrapper as the model
- Re-proved outcome:
  - There is still meaningful debt.
  - It is small and exact.
  - The debt is not broad host-folder flattening.
  - The current active VT debt is no longer the owner move itself. The owner already sits at `src/parser.zig`; the remaining blocker is three stale internal parser helper imports that still target deleted `src/parser/main.zig`.
  - The render debt is still one unit-test wrapper chain under `src/test/unit/root.zig`.
- Slice-boundary update from fresh current-source proof:
  - The original accepted Slice 1 boundary is no longer the right execution boundary for the live tree.
  - The executable Slice 1 is now the narrow completion slice that fixes the three remaining internal parser helper imports without reopening the already-completed external importer retargets.
- Things explicitly not promoted:
  - `howl-vt/src/ffi/main.zig`
  - `howl-linux-host/src/config/config.zig`
  - `howl-linux-host/src/display/display.zig`
  - `howl-linux-host/src/input/input.zig`
  - render `surface/`, `text/`, `vt_publication/`, and `c/` owner folders

## Explicit Ordered Slice Plan

### Slice 1

- Name: Finish VT parser root flattening.
- Session ids:
  - orchestrator: `orch-2026-06-13-followup-shallow-structure-01`
  - researcher: `research-2026-06-13-followup-shallow-structure-01`
  - reviewer: `review-2026-06-13-followup-shallow-structure-01`
- Allowed files:
  - `/home/home/personal/projects/howl/howl-vt/src/parser/owned_actions.zig`
  - `/home/home/personal/projects/howl/howl-vt/src/parser/string_control.zig`
  - `/home/home/personal/projects/howl/howl-vt/src/parser/events.zig`
- Required shape:
  - retarget these exact current internal helper imports from `@import("main.zig")` to `@import("../parser.zig")`:
    - `howl-vt/src/parser/owned_actions.zig:2`
    - `howl-vt/src/parser/string_control.zig:2`
    - `howl-vt/src/parser/events.zig:1`
  - keep the parser owner at `src/parser.zig`
  - do not recreate `src/parser/main.zig`
  - leave the nineteen already-retargeted external `src/parser.zig` imports unchanged
  - keep exported parser names, behavior, constants, and tests unchanged
- Required tests:
  - in `/home/home/personal/projects/howl/howl-vt`: `zig build test:unit`
  - in `/home/home/personal/projects/howl/howl-vt`: `zig build simulate`
- Required assertions:
  - no new runtime behavior assertions are required by this slice
  - existing parser compile-time and runtime assertions must survive unchanged
- Exact non-goals:
  - no ABI/export renames
  - no parser behavior changes
  - no helper-file flattening under `src/parser/`
  - no external importer churn outside the three helper files above
  - no `ffi/main.zig` changes
  - no simulation redesign
- Stop conditions:
  - stop if current source reveals any additional importer of deleted `src/parser/main.zig` beyond `howl-vt/src/parser/owned_actions.zig:2`, `howl-vt/src/parser/string_control.zig:2`, and `howl-vt/src/parser/events.zig:1`
  - stop if any required fix pressures recreating `src/parser/main.zig`
  - stop if fixing the three helper imports pressures broader parser-helper or module-root redesign

### Slice 2

- Name: Delete render unit-test wrapper chain.
- Session ids:
  - orchestrator: `orch-2026-06-13-followup-shallow-structure-01`
  - researcher: `research-2026-06-13-followup-shallow-structure-01`
  - reviewer: `review-2026-06-13-followup-shallow-structure-01`
- Allowed files:
  - `/home/home/personal/projects/howl/howl-render/src/test_unit.zig`
  - `/home/home/personal/projects/howl/howl-render/src/test/unit/root.zig`
- Required shape:
  - make `src/test_unit.zig` import these exact current unit proof files directly and no others:
    - `src/surface/realizer_test.zig`
    - `src/surface/emitter_test.zig`
    - `src/surface/handle_test.zig`
    - `src/geometry_test.zig`
    - `src/render_session.zig`
    - `src/submitted_surface.zig`
    - `src/c/text_session_test.zig`
    - `src/c/submission_test.zig`
    - `src/text/ft_hb/support_test.zig`
    - `src/text/raster/special_test.zig`
  - delete `src/test/unit/root.zig`
  - leave `build.zig:53-68` unchanged because it already points at the correct curated top-level root
- Required tests:
  - in `/home/home/personal/projects/howl/howl-render`: `zig build test:unit`
- Required assertions:
  - preserve the current proof set exactly; no test omission is allowed
- Exact non-goals:
  - no product code changes
  - no ABI test root changes
  - no benchmark root changes
  - no extra `src/test/` tree cleanup beyond the exact wrapper file deletion
- Stop conditions:
  - stop if any current unit proof cannot be imported directly from `src/test_unit.zig`
  - stop if this slice starts pulling non-unit proof surfaces into the unit root

## Required Tests Summary

- `howl-vt`: `zig build test:unit`
- `howl-vt`: `zig build simulate`
- `howl-render`: `zig build test:unit`

## Risks

1. Slice 1 now touches only three files, but they sit on live product and unit-test paths. The risk is no longer missed external importer churn; it is missing one remaining internal self-import and leaving the build blocked.
2. Slice 1 could still expose another stale `main.zig` dependency outside the three re-proved helper imports. The stop condition above exists for that case.
3. Slice 2 is structurally tiny, but it can silently drop proofs if the direct import list is not copied exactly.

## Proof Gaps

- No blocker-level proof gap remains for reviewer gate.
- I did not find current-source proof that more host-folder flattening is reference-safe, so that work is intentionally not promoted.
- I did not find current-source proof that `howl-vt/src/ffi/main.zig` is fake debt rather than a reference-backed C-surface aggregator, so that work is intentionally not promoted.

## Readiness Judgment

- Ready for reviewer gate: yes.
- Research verdict: meaningful shallow-depth debt remains, but the live Slice 1 execution boundary is now the three-file internal-import repair above, followed by the unchanged render wrapper deletion slice.
- Commit-hash receipt status: this artifact has been repaired after root `04aa1b2`; reviewer re-gate is required before any new execution or receipt closure.
