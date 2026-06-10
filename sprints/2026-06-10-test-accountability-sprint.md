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

2. `render-test-regression-repair`
- goal:
  - repair the current `howl-render` failing/crashing test surfaces after the font fixture slice
- required proof surface:
  - prepared handle teardown crashes
  - `source/text_input.zig` mapping regressions

3. `vt-simulate-canonical-repair`
- goal:
  - repair the current `howl-vt` simulation mismatch on canonical scrollback preservation

4. `workspace-validation-rebaseline`
- goal:
  - rerun the exposed repo validation surfaces and record a clean baseline
- required surfaces:
  - `howl-pty`: `zig build test`
  - `howl-vt`: `zig build test`, `zig build simulate`, `zig build benchmark:m7_baseline`
  - `howl-render`: `zig build test`, `zig build benchmark:render`
  - `howl-linux-host`: `zig build test`

Completion gate:

- no unjustified skipped tests in the active exposed validation surfaces
- `howl-render` test aggregate passes
- `howl-vt` simulate passes
- the repo validation baseline is rerun from current code and recorded honestly
