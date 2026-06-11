Test accountability sprint research

Date: 2026-06-10.
Status: archived planning input for completed test-accountability sprint.
Role: researcher.
Orchestrator session id: `orch-2026-06-10-test-accountability-01`.

Problem statement:

- The repo currently fails its own exposed validation surface.
- One `howl-render` test is skipped by default because render test fonts are not repo-owned.
- `howl-render` test execution currently has real failures and crashes.
- `howl-vt` simulation currently fails canonical preservation.
- Performance work is deferred until these proofs are honest and passing.

Sources read in order:

1. `/home/home/personal/projects/howl/loop/flow.md`
2. `/home/home/personal/projects/howl/sprints/current.txt`
3. prior active/accountability artifacts needed for transition truth
4. `/home/home/personal/projects/howl/howl-render/build.zig`
5. `/home/home/personal/projects/howl/howl-render/src/text/font/ft_hb/support_test.zig`
6. `/home/home/personal/projects/howl/howl-render/src/prepared/handle.zig`
7. `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig`
8. `/home/home/personal/projects/howl/howl-vt/src/simulation/scrollback.zig`
9. `/home/home/personal/projects/howl/howl-render/build.zig.zon`
10. local tracked/untracked font asset paths under `/home/home/personal/projects/howl/howl-render/`

Current proof receipts:

1. Exposed validation runs executed:
- `cd howl-pty && zig build test`
- `cd howl-vt && zig build test`
- `cd howl-vt && zig build simulate`
- `cd howl-vt && zig build benchmark:m7_baseline`
- `cd howl-render && zig build test`
- `cd howl-render && zig build benchmark:render`
- `cd howl-linux-host && zig build test`

2. `howl-render` current failures:
- `zig build test` fails in `test:abi`
- crashes:
  - `ffi.prepared_surface_test.test.render surface prepared ffi borrowed surface realizes explicit rgba oracle`
  - `ffi.prepared_surface_test.test.render ffi prepared render-surface retrieval reports emission failure`
- failing mappings:
  - `source text input converts VT source to text scene input`
  - `source text input maps publication style attrs dim and invisible`
  - `source text input marks Alacritty-empty cells before color mapping`
  - `source text input keeps fg-colored blanks empty`

3. `howl-render` skipped proof:
- `support_test.zig` imports `test_font_options`
- it returns `error.SkipZigTest` when either configured font path is empty
- `build.zig` defaults both `test-font-*` options to empty strings
- this means default repo test execution accepts a skip that should be repo-owned instead

Exact references:

- skipped font gate:
  - `/home/home/personal/projects/howl/howl-render/src/text/font/ft_hb/support_test.zig:3-18`
  - `/home/home/personal/projects/howl/howl-render/build.zig:11-26`
  - `/home/home/personal/projects/howl/howl-render/build.zig:45`
  - `/home/home/personal/projects/howl/howl-render/build.zig:61`
  - `/home/home/personal/projects/howl/howl-render/build.zig:115`
- crashing teardown owner:
  - `/home/home/personal/projects/howl/howl-render/src/prepared/handle.zig:160`
- current mapping regressions:
  - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:487`
  - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:783`
  - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:880`
  - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:901`
- failing simulation surface:
  - `/home/home/personal/projects/howl/howl-vt/src/simulation/scrollback.zig:124`

Readiness judgment:

- The first coding slice is ready.
- It should target only render test fixture accountability first.
- That slice must end by proving the skip is gone from default repo test execution.

Risks:

- repo-owned fonts may require explicit licensing review
- a fixture change may expose more render failures once the skipped test actually runs
- render and VT failures should stay separate slices so test accountability remains attributable

Fixture accountability correction:

- local font-like assets found under `howl-render/zig-pkg/` and `howl-render/vendor/` are not accountable repo-owned fixtures for default repo validation
- `howl-render/build.zig.zon` ships only `build.zig`, `build.zig.zon`, `include`, and `src`, so the accountable smallest shape is to add tracked fixture files under `howl-render/src/text/font/ft_hb/testdata/`
- accepted fixture target paths for slice 1 are:
  - `/home/home/personal/projects/howl/howl-render/src/text/font/ft_hb/testdata/primary.ttf`
  - `/home/home/personal/projects/howl/howl-render/src/text/font/ft_hb/testdata/symbols.ttf`
  - `/home/home/personal/projects/howl/howl-render/src/text/font/ft_hb/testdata/LICENSE.txt`
- if lawful provenance for those exact tracked paths cannot be established, slice 1 must stop and record the licensing blocker instead of inventing a different fixture mechanism

Remaining sprint plan after slice 1:

1. `render-prepared-handle-teardown-repair`
- exact current-code facts:
  - both crashing ABI tests live in `/home/home/personal/projects/howl/howl-render/src/ffi/prepared_surface_test.zig:72` and `/home/home/personal/projects/howl/howl-render/src/ffi/prepared_surface_test.zig:91`
  - both tests create a `PreparedHandle` and then defer `prepared.destroy()` at `/home/home/personal/projects/howl/howl-render/src/ffi/prepared_surface_test.zig:81` and `/home/home/personal/projects/howl/howl-render/src/ffi/prepared_surface_test.zig:101`
  - the owner crash path is the state-sensitive teardown gate in `/home/home/personal/projects/howl/howl-render/src/prepared/handle.zig:101` and `/home/home/personal/projects/howl/howl-render/src/prepared/handle.zig:159`
- allowed files:
  - `/home/home/personal/projects/howl/howl-render/src/prepared/handle.zig`
  - `/home/home/personal/projects/howl/howl-render/src/ffi/prepared_surface_test.zig`
- required shape:
  - repair `PreparedHandle` teardown so the ABI tests no longer crash when a prepared handle emitted a payload or recorded an emission failure
  - keep ownership in the `PreparedHandle` state machine; do not move teardown policy into FFI or test helpers
  - add owner-true assertions around live/released/consumed teardown transitions instead of weakening lifecycle checks
- tests/proof:
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:abi -- "render surface prepared ffi borrowed surface realizes explicit rgba oracle"`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:abi -- "render ffi prepared render-surface retrieval reports emission failure"`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:abi` may still fail only on the already-queued `source text input` mapping regressions until slice 3 lands
- non-goals:
  - no text-input fixes
  - no fixture-path work
  - no render-surface contract redesign
- stop conditions:
  - if the crash is proved to originate outside `PreparedHandle` teardown ownership, stop and record the exact conflicting owner path before broadening files
  - if a fix requires changing shipped ABI status values or C layout, stop and escalate instead of mutating contracts inside this slice
- owner/risk notes:
  - owner is `howl-render` prepared-handle lifecycle, not FFI convenience code
  - risk is double-destroy or deinit-after-state-transition if teardown does not match `released` and `consumed` semantics exactly

2. `render-text-input-default-background-model`
- exact current-code facts:
  - the remaining failures reproduce only on the ABI surface:
    - `cd /home/home/personal/projects/howl/howl-render && zig build test:abi`
  - current failing ABI proofs are still:
    - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:470`
    - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:734`
    - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:863`
    - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:887`
  - `source/cell.zig` already carries semantic source color identity as `default|indexed|rgb` for fg/bg/underline:
    - `/home/home/personal/projects/howl/howl-render/src/source/cell.zig:1-49`
  - the publication ABI mirror preserves the same distinction and ships default color state separately in `SourceColors`:
    - `/home/home/personal/projects/howl/howl-render/src/source/vt.zig:13-26`
    - `/home/home/personal/projects/howl/howl-render/src/source/vt.zig:48-65`
  - `text_input.zig` and `publication_cell_map.zig` immediately resolve semantic colors to `contract.Rgba8` and then infer emptiness from alpha:
    - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:72-87`
    - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:116-123`
    - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:224-245`
    - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig:24-45`
    - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig:67-83`
    - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig:136-149`
  - `contract.CellInput` has only resolved RGBA plus `empty`; it has no field that preserves "default background" as a semantic fact:
    - `/home/home/personal/projects/howl/howl-render/src/text/contract.zig:81-95`
  - direct consumers use `empty` and `bg.a == 0` as render policy:
    - `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig:291`
    - `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig:82-124`
- reference-backed finding:
  - Ghostty keeps semantic cell content and style separate instead of flattening default background into RGB:
    - `utils/dev_references/terminals/ghostty/src/terminal/c/cell.zig:40-47`
    - `utils/dev_references/terminals/ghostty/src/terminal/style.zig:102-125`
  - Kitty treats default foreground/background as distinct semantic colors and keeps reverse-video behavior explicit:
    - `utils/official_docs/kitty/color-stack.md:27-29`
    - `utils/official_docs/kitty/color-stack.md:60-63`
    - `utils/official_docs/kitty/underlines.md:59-60`
    - `utils/official_docs/kitty/misc-protocol.md:33-36`
  - Alacritty preserves semantic named background in the terminal cell model and computes render-time background alpha later:
    - `utils/dev_references/terminals/alacritty/alacritty_terminal/src/term/cell.rs:134-151`
    - `utils/dev_references/terminals/alacritty/alacritty_terminal/src/term/cell.rs:224-239`
    - `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:158-183`
    - `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:214-219`
    - `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:301-307`
    - `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:388-395`
- owner roles and proposed shape:
  - `source/cell.zig` and `source/vt.zig` are already sufficient owners for semantic source-cell truth
  - the missing owner-true distinction is at the text-input contract seam, not the source-cell seam
  - the next slice should add an explicit contract-level way to preserve default-background semantics through `contract.CellInput` and then make `text_input.zig`, `publication_cell_map.zig`, `cluster.zig`, and `direct_scene.zig` consume that field owner-truly
  - publication dim/invisible behavior is not a model gap; it is a mapper inconsistency that should be corrected while aligning both paths to the shared source-cell model
- allowed files:
  - `/home/home/personal/projects/howl/howl-render/src/text/contract.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig`
  - `/home/home/personal/projects/howl/research/2026-06-10-test-accountability-research.md`
  - `/home/home/personal/projects/howl/sprints/2026-06-10-test-accountability-sprint.md`
- required shape:
  - preserve semantic default-background truth through the text-input contract seam instead of resolving it away inside local mappers
  - keep source-cell semantic facts in the source owners and render policy in render-text owners
  - correct publication dim/invisible mapping to match the shared source-cell semantics, not a publication-only shortcut
  - remove or rewrite stale opaque-default-background tests once the contract carries the semantic distinction explicitly
- tests/proof:
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:abi -- "source text input converts VT source to text scene input"`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:abi -- "source text input maps publication style attrs dim and invisible"`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:abi -- "source text input marks Alacritty-empty cells before color mapping"`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:abi -- "source text input keeps fg-colored blanks empty"`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:abi`
- non-goals:
  - no prepared-handle teardown work
  - no font fixture work
  - no shipped C ABI changes in `include/howl_render.h` or `source/vt.zig`
  - no broad renderer architecture rewrite beyond the contract seam and its direct consumers
- stop conditions:
  - if preserving semantic default background requires changing the shipped `HowlRenderSourceCell` / publication ABI layout, stop and escalate
  - if references prove Howl must keep resolving default background to opaque RGBA inside `text_input.zig`, stop and convert this to an explicit test-correction slice with the conflicting references recorded
- owner/risk notes:
  - the current blocker is `howl-render/src/text/contract.zig`, not `howl-render/src/source/cell.zig`
  - risk is fixing the ABI proofs by another local alpha hack while leaving publication/direct-normal/damage consumers with contradictory semantics

3. `vt-simulate-canonical-repair`
- exact current-code facts:
  - the simulation failure is raised at `/home/home/personal/projects/howl/howl-vt/src/simulation/scrollback.zig:124` and `/home/home/personal/projects/howl/howl-vt/src/simulation/scrollback.zig:142`
  - canonical proof compares a pre-churn and post-churn logical stream in `/home/home/personal/projects/howl/howl-vt/src/simulation/scrollback.zig:302`
  - the churn mutates the terminal through resize paths rooted at `/home/home/personal/projects/howl/howl-vt/src/simulation/scrollback.zig:196`, `/home/home/personal/projects/howl/howl-vt/src/terminal.zig:131`, `/home/home/personal/projects/howl/howl-vt/src/screen_set.zig:117`, `/home/home/personal/projects/howl/howl-vt/src/screen.zig:248`, `/home/home/personal/projects/howl/howl-vt/src/screen/resize.zig:57`, and `/home/home/personal/projects/howl/howl-vt/src/screen/history.zig:317`
  - existing targeted resize/history proofs already live in `/home/home/personal/projects/howl/howl-vt/src/screen/resize_test.zig:8`, `/home/home/personal/projects/howl/howl-vt/src/terminal_surface_test.zig:158`, and `/home/home/personal/projects/howl/howl-vt/src/terminal_snapshot_test.zig:135`
- allowed files:
  - `/home/home/personal/projects/howl/howl-vt/src/simulation/scrollback.zig`
  - `/home/home/personal/projects/howl/howl-vt/src/terminal.zig`
  - `/home/home/personal/projects/howl/howl-vt/src/screen_set.zig`
  - `/home/home/personal/projects/howl/howl-vt/src/screen.zig`
  - `/home/home/personal/projects/howl/howl-vt/src/screen/resize.zig`
  - `/home/home/personal/projects/howl/howl-vt/src/screen/history.zig`
  - `/home/home/personal/projects/howl/howl-vt/src/screen/resize_test.zig`
  - `/home/home/personal/projects/howl/howl-vt/src/terminal_surface_test.zig`
  - `/home/home/personal/projects/howl/howl-vt/src/terminal_snapshot_test.zig`
- required shape:
  - repair canonical logical preservation across resize and zoom-jitter churn without weakening the simulation claim in `scrollback.zig`
  - keep mutation ownership in VT resize/history owners, not in simulation-only normalization
  - add or sharpen deterministic unit proofs at the resize/history owners for the exact preservation rule that the simulation is enforcing
- tests/proof:
  - `cd /home/home/personal/projects/howl/howl-vt && zig build simulate -- scrollback`
  - `cd /home/home/personal/projects/howl/howl-vt && zig build test:unit -- "screen resize"`
  - `cd /home/home/personal/projects/howl/howl-vt && zig build test:unit -- "resize keeps history enabled state"`
  - `cd /home/home/personal/projects/howl/howl-vt && zig build test:unit -- "snapshot: historyRowAt matches terminal after wraparound"`
  - `cd /home/home/personal/projects/howl/howl-vt && zig build test:unit`
- non-goals:
  - no protocol simulation work
  - no host/FFI surface changes
  - no benchmark work
- stop conditions:
  - if the canonical mismatch cannot be reproduced with `zig build simulate -- scrollback`, stop and record the exact missing seed or smoke-path-only condition before changing owners
  - if the required fix crosses outside resize/history ownership into unrelated parser/protocol paths, stop and record the proof before broadening scope
- owner/risk notes:
  - the likely mutation owners are resize/reflow/history retention, not the simulation harness itself
  - risk is preserving visible rows while corrupting logical-line authority or history wrap truth; the slice must prove both simulation and owner-local tests

4. `workspace-validation-rebaseline`
- allowed files:
  - `/home/home/personal/projects/howl/research/2026-06-10-test-accountability-research.md`
  - `/home/home/personal/projects/howl/sprints/2026-06-10-test-accountability-sprint.md`
- required shape:
  - rerun the exposed validation surfaces after slices 1-4 land
  - record the result honestly in the active research and sprint artifacts
  - if every surface passes, record the clean baseline and sprint completion receipts
  - if any surface still fails, record the exact remaining blocker and stop instead of hand-waving a clean baseline
- tests/proof:
  - `cd /home/home/personal/projects/howl/howl-pty && zig build test`
  - `cd /home/home/personal/projects/howl/howl-vt && zig build test`
  - `cd /home/home/personal/projects/howl/howl-vt && zig build simulate`
  - `cd /home/home/personal/projects/howl/howl-vt && zig build benchmark:m7_baseline`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test`
  - `cd /home/home/personal/projects/howl/howl-render && zig build benchmark:render`
  - `cd /home/home/personal/projects/howl/howl-linux-host && zig build test`
- non-goals:
  - no new code changes beyond receipt updates unless a prior slice was accepted incorrectly
  - no performance interpretation beyond whether the benchmark commands execute successfully as part of the exposed surface
- stop conditions:
  - any command above fails or skips unexpectedly
  - any accepted earlier slice lacks required receipts or proof output
- owner/risk notes:
  - this slice is verification-only and must not hide unresolved failures behind documentation edits
  - benchmark commands are part of the exposed validation surface for this sprint because the active sprint file already names them

Slice 4 receipt:

- `vt-simulate-canonical-repair` accepted on `howl-vt` commit `ab39fda`
- canonical proof now reads logical authority from history plus visible rows instead of the bounded projected-history view
- canonical hashing now uses deterministic `u32` codepoint values instead of raw `u21` memory bytes
- owner-local resize proof now covers canonical logical preservation when projected history saturates
- measured primary proof:
  - `cd /home/home/personal/projects/howl/howl-vt && time zig build simulate -- scrollback`
  - `real 1m23.989s`

Workspace rebaseline blocker:

- the final workspace rebaseline does not close the sprint yet
- current exposed surfaces passed:
  - `howl-pty`: `zig build test`
  - `howl-vt`: `zig build test`, `zig build simulate`, `zig build benchmark:m7_baseline`
  - `howl-render`: `zig build benchmark:render`
  - `howl-linux-host`: `zig build test`
- current exposed surface still failing:
  - `cd /home/home/personal/projects/howl/howl-render && zig build test`
- failure is confined to `howl-render` `test:abi` and still names the four `source text input` proofs in `src/source/text_input.zig`
- this means slice 3 was only a unit-surface rebaseline, not the full ABI-surface closure needed for workspace completion

Slice 3 receipt:

- superseded by `render-source-cell-model-research`
- `render-text-input-mapping-regressions` closed as an honest no-op on the accepted tree
- current `howl-render` proof surface already passes with zero file changes:
  - `source text input converts VT source to text scene input`
  - `source text input maps publication style attrs dim and invisible`
  - `source text input marks Alacritty-empty cells before color mapping`
  - `source text input keeps fg-colored blanks empty`
  - `publication cell map`
  - aggregate `zig build test:unit`
- no remaining reproducing mapping regression exists inside the allowed owner files on the current accepted tree

Blocked slice receipt:

- `render-text-input-abi-closure` stopped on reviewer-accepted blocker
- blocker accepted by reviewer session `019eb2c1-0991-7d73-9724-463ca0289931`
- coder proved the current allowed mapper owners are insufficient to distinguish at least one failing ABI case
- exact owner-path blocker re-proved as the text-input contract seam rooted at `howl-render/src/text/contract.zig`
- next step is research, not coding

Render source cell model research:

- user-scoped reference-order override receipt:
  - exact user decision:
    - for this sub-sprint only, read references in this order: Ghostty, Kitty, Alacritty
  - exact reference being overridden:
    - `/home/home/personal/projects/howl/reference-index.md` default reference order
  - reason:
    - this sub-sprint is about VT/value-model shape, not host/runtime organization
  - accountable orchestrator session id:
    - `orch-2026-06-10-test-accountability-01`
  - user approval receipt:
    - current user instruction that seeded `loops/render-source-cell-model-research.txt`
- current-code facts:
  - `zig build test:unit` passes because the unit root does not import `src/source/text_input.zig` directly:
    - `/home/home/personal/projects/howl/howl-render/src/test_unit.zig:1-3`
    - `/home/home/personal/projects/howl/howl-render/src/test/unit/root.zig:1-9`
  - `zig build test:abi` imports `libhowl_render.zig` through `refAllDecls`, which executes the inline `source/text_input.zig` tests and reproduces the four failures:
    - `/home/home/personal/projects/howl/howl-render/src/test_abi.zig:1-11`
- what the current source-cell model can represent:
  - semantic fg/bg/underline color identity
  - dim/inverse/invisible/underline/selection/style flags
  - combining truth and continuation truth
  - publication default/palette color state separate from per-cell semantic colors
- what the ABI tests require:
  - default background must remain semantically distinguishable from explicit RGB background through the text-input seam so render-time alpha/emptiness policy can match reference behavior
  - publication mapping must apply the same dim/invisible semantics as VT mapping
- stale-test judgment:
  - the stale expectations are the recently-added opaque-default-background proofs in `text_input.zig` and `publication_cell_map.zig`, not the four remaining ABI failures
  - the four failing ABI tests align with the upstream distinction between semantic default background and render-time background alpha
- readiness judgment:
  - the repo is ready for one explicit model-change slice
  - a pure test-correction slice would be dishonest because it would codify the same flattened model the references reject
