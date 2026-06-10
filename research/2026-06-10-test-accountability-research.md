Test accountability sprint research

Date: 2026-06-10.
Status: active planning input.
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
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:abi`
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

2. `render-text-input-mapping-regressions`
- exact current-code facts:
  - failing VT-source expectations are in `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:470`, `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:863`, and `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:887`
  - the failing publication-source expectation is in `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:734`
  - VT cell mapping is owned by `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:224`
  - publication cell mapping is delegated to `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig:24`
- allowed files:
  - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`
- required shape:
  - restore owner-true text-scene mapping for VT-source and publication-source cells without adding compatibility aliases or separate fallback mappers
  - keep VT-source mapping fixes in `text_input.zig`
  - keep publication-source mapping fixes in `publication_cell_map.zig`
  - preserve existing explicit mapping concepts: empty-cell detection, inverse handling, dim handling, invisible handling, and default background truth
- tests/proof:
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "source text input converts VT source to text scene input"`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "source text input maps publication style attrs dim and invisible"`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "source text input marks Alacritty-empty cells before color mapping"`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "source text input keeps fg-colored blanks empty"`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "publication cell map"`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:unit`
- non-goals:
  - no prepared-handle teardown work
  - no font fixture work
  - no broad scene/frame-preparer redesign
- stop conditions:
  - if any failing expectation is proved to belong to a different owner than `text_input.zig` or `publication_cell_map.zig`, stop and record the exact owner path before broadening
  - if making the tests pass requires changing `contract.CellInput` shape or render ABI contracts, stop and escalate instead of expanding this slice
- owner/risk notes:
  - this slice crosses two owners only because `text_input.zig` delegates publication mapping explicitly
  - risk is masking one regression by weakening empty-cell or invisible semantics; fixes must preserve explicit positive/negative-space tests

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
