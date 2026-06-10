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
