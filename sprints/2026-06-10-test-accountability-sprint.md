Test accountability before more performance work

Date: 2026-06-10.
Status: active.
Orchestrator session id: `orch-2026-06-10-test-accountability-01`.

Problem statement:

- Performance work is deferred.
- ASCII rain boundary cleanup is no longer an active sprint concern.
- The active repo-wide problem is test accountability:
  - `howl-render` has a skipped font-dependent test that should be repo-owned and non-skipping by default
  - `howl-render` has real failing/crashing test surfaces
  - `howl-vt` has a failing simulation surface
- The sprint is complete only when the exposed validation surfaces are accountable and pass cleanly.

Planning rule:

- No performance slice is authorized while this sprint is active.
- No benchmark-client or host-doc cleanup is part of this sprint unless required by test accountability.
- A skipped test caused by missing repo-owned fixtures is treated as a sprint failure, not an acceptable environment outcome.

Sequential slice queue:

1. `render-test-fixture-accountability`
- goal:
  - remove the unjustified skipped render font test by making its fonts repo-owned and wired by default
- allowed files:
  - `/home/home/personal/projects/howl/howl-render/build.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/font/ft_hb/support_test.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/font/ft_hb/testdata/primary.ttf`
  - `/home/home/personal/projects/howl/howl-render/src/text/font/ft_hb/testdata/symbols.ttf`
  - `/home/home/personal/projects/howl/howl-render/src/text/font/ft_hb/testdata/LICENSE.txt`
  - `/home/home/personal/projects/howl/loops/render-test-fixture-accountability.txt`
  - `/home/home/personal/projects/howl/research/2026-06-10-test-accountability-research.md`
- required shape:
  - render tests must no longer rely on external ad hoc font path injection to avoid skipping
  - repo test defaults must supply deterministic font fixtures
  - override flags may remain optional, but not required for normal repo validation
- required tests:
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "provider loads fallback face for symbol glyph with primary present"`
  - proof that the command above runs the named test under repo-default build options without `error.SkipZigTest`
- non-goals:
  - no render behavior fixes yet unless needed to keep the font proof runnable
  - no performance changes
- stop conditions:
  - repo-owned fixtures cannot be added at the exact `src/text/font/ft_hb/testdata/` paths with explicit license text
  - if a reference-backed alternative to local tracked font fixtures is required, stop after recording the blocking reference and do not invent a different mechanism inside this slice

2. `render-prepared-handle-teardown-repair`
- goal:
  - repair the current `howl-render` ABI-test teardown crashes in the prepared-handle owner path
- allowed files:
  - `/home/home/personal/projects/howl/howl-render/src/prepared/handle.zig`
  - `/home/home/personal/projects/howl/howl-render/src/ffi/prepared_surface_test.zig`
  - `/home/home/personal/projects/howl/research/2026-06-10-test-accountability-research.md`
  - `/home/home/personal/projects/howl/sprints/2026-06-10-test-accountability-sprint.md`
- required shape:
  - the `PreparedHandle` lifecycle must tear down emitted payload and prepared state without crashing when the ABI tests destroy a borrowed prepared handle
  - lifecycle policy stays in the prepared-handle owner, with explicit assertions for valid state transitions
  - no ABI contract value or layout changes
- required tests:
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:abi -- "render surface prepared ffi borrowed surface realizes explicit rgba oracle"`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:abi -- "render ffi prepared render-surface retrieval reports emission failure"`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:abi`
- non-goals:
  - no text-input mapping fixes
  - no fixture-path work
  - no render-surface contract redesign
- stop conditions:
  - if the crash is proved to originate outside prepared-handle teardown ownership, stop and record the exact owner path before broadening files
  - if a fix requires changing shipped ABI status values or C layout, stop and escalate instead of mutating contracts inside this slice

3. `render-text-input-mapping-regressions`
- goal:
  - repair the current `howl-render` VT-source and publication-source text-input mapping regressions
- allowed files:
  - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`
  - `/home/home/personal/projects/howl/research/2026-06-10-test-accountability-research.md`
  - `/home/home/personal/projects/howl/sprints/2026-06-10-test-accountability-sprint.md`
- required shape:
  - restore owner-true mapping for VT-source cells in `text_input.zig`
  - restore owner-true publication mapping in `publication_cell_map.zig`
  - preserve explicit semantics for empty-cell detection, inverse, dim, invisible, and default-background truth
  - do not add alternate mappers or compatibility shims
- required tests:
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "source text input converts VT source to text scene input"`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "source text input maps publication style attrs dim and invisible"`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "source text input marks Alacritty-empty cells before color mapping"`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "source text input keeps fg-colored blanks empty"`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "publication cell map"`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:unit`
- non-goals:
  - no prepared-handle teardown work
  - no font fixture work
  - no broad render scene contract changes
- stop conditions:
  - if any failing expectation is proved to belong to a different owner than `text_input.zig` or `publication_cell_map.zig`, stop and record the exact owner path before broadening
  - if making the tests pass requires changing `contract.CellInput` shape or render ABI contracts, stop and escalate instead of expanding this slice

4. `vt-simulate-canonical-repair`
- goal:
  - repair the current `howl-vt` canonical scrollback mismatch across resize and zoom-jitter churn
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
  - `/home/home/personal/projects/howl/research/2026-06-10-test-accountability-research.md`
  - `/home/home/personal/projects/howl/sprints/2026-06-10-test-accountability-sprint.md`
- required shape:
  - preserve canonical logical content through resize and zoom-jitter churn without weakening the simulation claim
  - keep mutation fixes in the resize/history owners, not in simulation-only normalization
  - add or sharpen owner-local resize/history proofs for the preservation rule enforced by the simulation
- required tests:
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
  - if the mismatch cannot be reproduced with `zig build simulate -- scrollback`, stop and record the exact missing seed or smoke-only condition before changing owners
  - if the required fix crosses outside resize/history ownership into unrelated parser/protocol paths, stop and record the proof before broadening scope

5. `workspace-validation-rebaseline`
- goal:
  - rerun the exposed repo validation surfaces and record a clean baseline after slices 1-4 land
- allowed files:
  - `/home/home/personal/projects/howl/research/2026-06-10-test-accountability-research.md`
  - `/home/home/personal/projects/howl/sprints/2026-06-10-test-accountability-sprint.md`
- required shape:
  - verification-only slice
  - rerun every exposed command in the sprint surface
  - record a clean baseline only if the commands actually pass without unjustified skips
  - if any command still fails, record the exact blocker and stop
- required tests:
  - `cd /home/home/personal/projects/howl/howl-pty && zig build test`
  - `cd /home/home/personal/projects/howl/howl-vt && zig build test`
  - `cd /home/home/personal/projects/howl/howl-vt && zig build simulate`
  - `cd /home/home/personal/projects/howl/howl-vt && zig build benchmark:m7_baseline`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test`
  - `cd /home/home/personal/projects/howl/howl-render && zig build benchmark:render`
  - `cd /home/home/personal/projects/howl/howl-linux-host && zig build test`
- non-goals:
  - no new code changes beyond receipt updates unless an earlier slice was accepted incorrectly
  - no benchmark interpretation beyond whether the exposed commands run cleanly
- stop conditions:
  - any command above fails or skips unexpectedly
  - any accepted earlier slice lacks required receipts or proof output

Completion gate:

- no unjustified skipped tests in the active exposed validation surfaces
- `howl-render` test aggregate passes
- `howl-vt` simulate passes
- the repo validation baseline is rerun from current code and recorded honestly
