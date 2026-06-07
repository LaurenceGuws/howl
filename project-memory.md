# Project Memory

Owner: workspace root.

Purpose: canonical, timestamped index for durable scratchpad facts. Older root
scratchpads may remain as archive pointers when their durable facts have been
moved here.

Rules:

- Read `AGENTS.md`, `loop.txt`, and the TigerBeetle references before non-trivial work.
- Preserve source-backed facts, accepted decisions, proof gaps, and follow-up slices.
- Treat stale slice specs as historical unless this file marks them active.

## 2026-06-04 Useless LOC Sprint

- Scope doc: `loc-debt-sprint-scope.md`.
- User direction for this sprint is binding: full sweep, sequential, planned, auditable work; no opportunistic isolated cleanups; accountability first.

### 2026-06-06 Sprint Refocus

- The primary sprint metric is now materially smaller `prod`, not generic hygiene progress.
- Production code must become smaller, more pragmatic, and more intentional.
- Files, folders, and owners should be as shallow as possible while still surviving TigerBeetle law and idiomatic Zig naming.
- Casts should happen at the true source boundary, then datatypes should stay stable through the pipeline; repeated downstream casts are presumed waste and should be targeted as debt.
- Local mirrors of dependent-repo datatypes are presumed debt when owner-direct types can flow without violating the ABI/product boundary.
- Zig module shaping is presumed debt when only the C ABI product boundary is actually needed.
- Updated sprint rule:
  - do not skip a cut only because it is small
  - take any real dead-code, aliasing, owner-false, cast-churn, or local-datatype-mirror reduction that survives TigerBeetle gates
  - keep preferring larger reductions first, but do not close real low-hanging fruit just for being low-yield
- Immediate remaining top unresolved pressure after latest accepted cuts:
  - `howl-render/src/text/raster/special.zig`
  - `howl-linux-host/src/display/renderer/render_surface.zig`
  - `howl-render/src/benchmark_main.zig`
  - `howl-render/src/text/font/ft_hb/special_sprite.zig`
  - `howl-render/src/render/render_surface_realizer.zig`
  - `howl-vt/src/parser/string_control.zig`

Reopened previously skipped low-yield avenues:

- Any prior rejection based only on "below the refocused bar" is no longer binding.
- Re-audit small real cuts again if they remove actual dead code, wrappers, aliasing, repeated casts, or local datatype mirrors.
- Keeper verdicts should now mean either:
  - no real debt was found, or
  - the remaining work broadens into redesign rather than a narrow cleanup.

### Slice 1 Completed

- Dead host wrappers and dead re-export layers were deleted from `howl-linux-host`:
  - `src/terminal/texture.zig`
  - `src/window_chrome.zig`
  - `src/display.zig`
  - `src/display/renderer.zig`
- Verification before deletion showed no live import-path users of those wrapper files in the current tree.
- Verification after deletion:
  - wrapper import-path grep returned no matches workspace-wide
  - `howl-linux-host`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`
- Dirty-state note preserved for later slices: `howl-linux-host/src/display/frame_timer.zig` already had a local pacing cleanup before this slice and was not edited as part of the wrapper deletion.

### Slice 2 Completed

- Deleted `howl-linux-host/build_support/host_tests.zig`.
- Folded host test-root module creation directly into `howl-linux-host/build.zig`.
- Attempted direct rooting of `src/terminal/context.zig` and `src/main.zig`, then rejected it with current-source proof:
  - `src/terminal/context.zig` as a root fails because its `../...` imports escape the module root.
  - `src/main.zig` as the integration root changes imported-test compilation behavior and broke current host proofs.
- Keeper verdict for now:
  - `howl-linux-host/src/host_test_root.zig`
  - `howl-linux-host/src/integration_test_root.zig`
- Verification after the accepted cut:
  - `howl-linux-host`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`
  - one transient `howl-pty` integration failure occurred during a workspace `zig build test` run and passed on immediate rerun; final workspace gates were clean

### Slice 3 Completed

- Removed render benchmark ownership from `src/test`:
  - moved `howl-render/src/test/benchmark.zig` to `howl-render/src/benchmark_main.zig`
  - deleted the old trampoline-only `howl-render/src/benchmark_main.zig`
- Grep verification confirmed no remaining `src/test/benchmark.zig` or `test/benchmark.zig` references.
- Verification after the cut:
  - `howl-render`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

### Slice 4 Completed

- Removed duplicated VT unit-test aggregation from `howl-vt/src/howl_vt.zig`.
- Deleted overlapping explicit imports for:
  - `action/route_test.zig`
  - `screen_test.zig`
  - `terminal_end_to_end_test.zig`
  - `terminal_modes_test.zig`
  - `terminal_osc_test.zig`
  - `terminal_snapshot_test.zig`
  - `terminal_surface_test.zig`
- Kept the terminal-owner test aggregation in `howl-vt/src/terminal.zig`.
- Verification after the cut:
  - `howl-vt`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

### Slice 5 In Progress

Accepted production/test separation cuts completed so far:

- `howl-pty/src/pty/posix.zig`
  - deleted two inline production-owner tests
  - added sibling owner test file: `howl-pty/src/pty/posix_test.zig`
  - added only one narrow test hook in production owner: `posix.testing.waitReadablePollResult`
  - test root wiring updated in `howl-pty/src/test_unit.zig`
  - verification after the cut:
    - `howl-pty`: `zig build test && zig build check`
    - workspace root: `zig build test && zig build check`

- `howl-render/src/session/text.zig`
  - deleted six inline production-owner tests
  - added sibling owner test file: `howl-render/src/session/text_test.zig`
  - added only two narrow test hooks in production owner:
    - `testing.ftHbCapacity`
    - `testing.ensureCellInputScratchCapacity`
  - test root wiring updated in `howl-render/src/test/unit/root.zig`
  - verification after the cut:
    - `howl-render`: `zig build test && zig build check`
    - workspace root: `zig build test && zig build check`

- `howl-render/src/prepared/owner.zig`
  - deleted ten inline production-owner tests
  - moved local test-only prepared-surface builders and RGBA/draw helpers out of the production owner
  - added sibling owner test file: `howl-render/src/prepared/owner_test.zig`
  - added only two narrow test hooks in production owner:
    - `testing.executionMatchesPrepared`
    - `testing.renderSurfaceEmissionFailureFromError`
  - test root wiring updated in `howl-render/src/test/unit/root.zig`
  - verification after the cut:
    - `howl-render`: `zig build test && zig build check`
    - workspace root: `zig build test && zig build check`

- `howl-render/src/prepared/render_surface_emitter.zig`
  - deleted inline production-owner tests
  - moved test-only fixture/build helper code to `howl-render/src/prepared/render_surface_emitter_test.zig`
  - added a minimal production `testing` hook surface because sibling tests cannot call private owner methods across module boundaries
  - kept the hook narrow to extracted sibling-test needs only
  - test root wiring updated in `howl-render/src/test/unit/root.zig`
  - verification after the cut:
    - `howl-render`: `zig build test && zig build check`
    - workspace root: `zig build test && zig build check`
  - grep receipt: `^test ` no longer matches in `howl-render/src/prepared/render_surface_emitter.zig`

- `howl-linux-host/src/display/renderer/render_surface.zig`
  - deleted inline production-owner tests
  - moved local test helpers and proofs to `howl-linux-host/src/display/renderer/render_surface_test.zig`
  - added a narrow production `testing` namespace because sibling tests needed access to private owner behavior and a private nested slot type
  - test root wiring updated in `howl-linux-host/src/host_test_root.zig`
  - verification after the cut:
    - `howl-linux-host`: `zig build test && zig build check`
    - workspace root: `zig build test && zig build check`
  - grep receipt: `^test ` no longer matches in `howl-linux-host/src/display/renderer/render_surface.zig`

- `howl-linux-host/src/terminal/context.zig`
  - deleted inline production-owner tests
  - moved local test helpers and proofs to `howl-linux-host/src/terminal/context_test.zig`
  - added a narrow production `testing` namespace because sibling tests needed access to private owner behavior and result types across module boundaries
  - test root wiring updated in `howl-linux-host/src/host_test_root.zig`
  - verification after the cut:
    - `howl-linux-host`: `zig build test && zig build check`
    - workspace root: `zig build test && zig build check`
  - grep receipt: `^test ` no longer matches in `howl-linux-host/src/terminal/context.zig`

- `howl-linux-host/src/main.zig` and `src/app/processor.zig`
  - extracted a concrete top-level processor owner in `src/app/processor.zig`
  - moved loop/present/input/tab coordination out of `src/main.zig`
  - reduced `src/main.zig` to bootstrap/entry and one bootstrap-owned `TERM` environment policy proof
  - removed the remaining top-level host `anytype` seams from the processor owner:
    - `collectLoopDebugFactsWith`
    - `forwardTerminalInputFlow`
    - `syncActiveWindowTitle`
    - `submitPresentWith`
    - `recordPresentSubmission`
    - `recordPresentSubmissionFor`
    - `drainPresentComplete`
    - `tabBarRevision`
    - `tabIndexInRange`
  - replaced those seams with concrete owner methods and explicit data helpers
  - deleted fake-seam processor tests instead of preserving a non-Alacritty generic test seam
  - verification after the cut:
    - `howl-linux-host`: `zig build test && zig build check`
    - workspace root: `zig build test && zig build check`
  - grep receipts:
    - `howl-linux-host/src/app/processor.zig`: no `anytype`
    - `howl-linux-host/src/main.zig`: only one remaining inline test, the bootstrap-owned `TERM` policy proof

### Slice 6 Completed

- Deleted `howl-render/src/text/text.zig`.
- Rewrote `howl-render` call sites to import direct text owners instead of the umbrella.
- Direct imports now point at smallest owner-true files such as:
  - `text/frame_preparer.zig`
  - `text/font/session.zig`
  - `text/font/provider.zig`
  - `text/font/ft_hb/provider.zig`
  - `text/shape/cluster.zig`
  - `text/shape/run.zig`
  - `text/raster/cache.zig`
  - `text/raster/rasterizer.zig`
  - `text/raster/fallback.zig`
- Verification after the cut:
  - `howl-render`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`
- Grep receipt: no remaining `text/text.zig` imports in `howl-render/src`.

### Slice 7 Started

- Accepted first direct-ABI collapse cut on the host terminal owner boundary.

- `howl-linux-host/src/terminal/pty/retained.zig`
  - treated as stale bucket/alias debt
  - moved PTY launch/lifecycle/feed-record state into `howl-linux-host/src/terminal/term.zig`
  - rewrote direct users in:
    - `howl-linux-host/src/terminal/context.zig`
    - `howl-linux-host/src/terminal/pty/session.zig`
  - deleted `howl-linux-host/src/terminal/pty/retained.zig`
  - verification after the cut:
    - `howl-linux-host`: `zig build test && zig build check && zig build run -Doptimize=ReleaseFast`
    - workspace root: `zig build test && zig build check`
  - grep receipt: no remaining `pty/retained.zig` or `pty_retained` references under `howl-linux-host/src`

- `howl-linux-host/src/terminal/vt/retained.zig`
  - kept the VT ABI helper owner for now, but deleted its stale retained-state bucket
  - moved VT title/scratch/scrollback/cursor retained state into `howl-linux-host/src/terminal/term.zig`
  - rewrote `vt/retained.zig` to use `term` as the state owner instead of exporting `State`
  - verification after the cut:
    - `howl-linux-host`: `zig build test && zig build check && zig build run -Doptimize=ReleaseFast`
    - workspace root: `zig build test && zig build check`
  - grep receipt: no remaining `vt_retained.State` references under `howl-linux-host/src/terminal`

- VT title ownership follow-up cut:
  - moved launch-title fallback, cached title copy, title generation, and VT title refresh from `howl-linux-host/src/terminal/vt/retained.zig` into `howl-linux-host/src/terminal/term.zig`
  - rewrote direct users in:
    - `howl-linux-host/src/terminal/context.zig`
    - `howl-linux-host/src/terminal/pty/pump.zig`
  - kept `vt/retained.zig` for the remaining VT runtime, selection, scrollback, and bounded-output helper surface
  - verification after the cut:
    - `howl-linux-host`: `zig build test && zig build check && zig build run -Doptimize=ReleaseFast`
    - workspace root: `zig build test && zig build check`
  - grep receipt: no remaining `vt_retained.resetTitleFromLaunch`, `copyCurrentTitle`, `titleGeneration`, or `copyTitleLocked` references under `howl-linux-host/src/terminal`

- VT selection/link ownership follow-up cut:
  - moved VT selection mutation into `howl-linux-host/src/terminal/selection.zig`
  - moved VT visible hyperlink lookup into `howl-linux-host/src/terminal/links.zig`
  - removed `vt_retained.startSelection`, `updateSelection`, `finishSelection`, and `copyVisibleHyperlinkAt`
  - verification after the cut:
    - `howl-linux-host`: `zig build test && zig build check && zig build run -Doptimize=ReleaseFast`
  - grep receipt: no remaining `vt_retained.copyVisibleHyperlinkAt`, `startSelection`, `updateSelection`, or `finishSelection` references under `howl-linux-host/src/terminal`

- VT layout ownership follow-up cut:
  - moved VT resize and cell-pixel-size mutation into `howl-linux-host/src/terminal/render/surface_layout.zig`
  - rewrote direct users in:
    - `howl-linux-host/src/terminal/context.zig`
    - `howl-linux-host/src/terminal/render/surface_layout.zig`
  - removed `vt_retained.resize`, `resizeLocked`, `setCellPixelSize`, and `setCellPixelSizeLocked`
  - follow-up fix:
    - `surface_layout.resizeTermVtLocked()` now clamps scrollback using `vt_surface.vtVisibleInfo(...)` directly
    - avoids recursive term mutex acquisition through `vt_retained.scrollState(...)`
  - verification after the cut:
    - `howl-linux-host`: `zig build test && zig build check && zig build run -Doptimize=ReleaseFast`
    - workspace root: `zig build test && zig build check`
  - grep receipt: no remaining `vt_retained.resize*` or `setCellPixelSize*` references under `howl-linux-host/src/terminal`

- VT scrollback ownership follow-up cut:
  - moved the public host scrollback subgroup into `howl-linux-host/src/terminal/scrollbar.zig`
  - moved:
    - `ScrollState`
    - `scrollState`
    - `scrollStateLocked`
    - `setScrollbackOffset`
    - `setScrollbackOffsetLocked`
    - `followLiveBottom`
  - rewrote direct users in:
    - `howl-linux-host/src/terminal/scrollbar.zig`
    - `howl-linux-host/src/terminal/context.zig`
  - kept `vt_retained.followLiveBottomLocked` in place because `howl-linux-host/src/terminal/vt/input.zig` still uses the locked helper directly
  - verification after the cut:
    - `howl-linux-host`: `zig build test && zig build check && zig build run -Doptimize=ReleaseFast`
    - workspace root: `zig build test && zig build check`
  - grep receipt: no remaining `vt_retained.scrollState`, `setScrollbackOffset`, or `followLiveBottom` references under `howl-linux-host/src/terminal`

- Final pure VT-state helper peel:
  - moved pure field helpers from `howl-linux-host/src/terminal/vt/retained.zig` into `howl-linux-host/src/terminal/term.zig`
  - moved:
    - `inputScratch`
    - `followLiveBottomLocked`
    - `setFocused`
  - rewrote direct users in:
    - `howl-linux-host/src/terminal/vt/input.zig`
    - `howl-linux-host/src/terminal/scrollbar.zig`
  - left `vt/retained.zig` as the keeper helper owner for VT runtime/feed/output/clipboard/selection behavior
  - verification after the cut:
    - grep receipt: no `retained.inputScratch`, `retained.followLiveBottomLocked`, or `retained.setFocused` references remain under `howl-linux-host/src/terminal`
    - `howl-linux-host`: `zig build test && zig build check`
    - workspace root: `zig build test && zig build check`

- Terminal input-owner follow-up cut:
  - moved the remaining concrete input-adapter leaf surface from `howl-linux-host/src/terminal/context.zig` into `howl-linux-host/src/terminal/input.zig`
  - moved:
    - `publishTerminalBytes`
    - `publishTerminalKey`
    - `publishTerminalMouse`
    - `ScrollVisualState`
    - `ContextOps`
    - `pixelToCol`
    - `pixelToRow`
  - kept `context.zig` thin wrappers for input drain, mouse ownership, and terminal pixel conversion
  - kept `vt/retained.zig` unchanged as a keeper helper owner
  - verification after the cut:
    - grep receipt: `context.zig` no longer defines `ContextOps`, `ScrollVisualState`, `publishTerminalBytes`, `publishTerminalKey`, `publishTerminalMouse`, `pixelToCol`, or `pixelToRow`
    - grep receipt: `context.zig` still defines `drainTextInputFastPath`, `drainPointerAndUiInput`, `terminalOwnsMouse`, `pixelToTerminalCol`, and `pixelToTerminalRow`
    - `howl-linux-host`: `zig build test && zig build check && zig build run -Doptimize=ReleaseFast`
    - workspace root: `zig build test && zig build check`

- Item 7 closure verdict:
  - reviewed one further tiny-cut idea: deleting `Context.terminalOwnsMouse`, `pixelToTerminalCol`, and `pixelToTerminalRow`
  - reviewer rejected that cut because it would create an import cycle between `terminal/input.zig` and `selection.zig` / `links.zig`
  - conclusion: item 7 is complete enough on the current boundary path
  - any further host input ownership work is a new broader researched slice, not item 7 cleanup

### Item 8 Completed

- Deduplicated repeated constructor-family assembly locally in `howl-vt`.
- `howl-vt/src/screen.zig`
  - added one file-local helper for repeated base `Screen` field assembly
  - preserved:
    - allocation-free cursor-only init
    - owned cells/wrap/dirty/tab-stop allocation path
    - zero-length history allocation behavior
    - `history_capacity = if (cells != null) history_capacity else 0`
- `howl-vt/src/terminal.zig`
  - added one file-local helper for repeated final `Terminal` assembly after screen creation
  - preserved the primary-only history asymmetry in `initWithCellsHistoryAndOptions()`
- Verification after the cut:
  - `howl-vt`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

### Item 9a Completed

- Deduplicated repeated test-artifact plumbing locally inside `howl-pty/build.zig`.
- Added one file-local helper for repeated `b.addTest(...)` setup while preserving:
  - `filters = b.args orelse &.{}`
  - `use_llvm = true`
- Added one file-local helper for repeated `b.addRunArtifact(...)` setup while preserving conditional `has_side_effects`.
- Kept ABI-specific include/import setup explicit and unchanged.
- Verification after the cut:
  - `howl-pty`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

### Item 9b Completed

- Deduplicated unit/ABI test-artifact plumbing locally in `howl-vt/build.zig`.
- Added one file-local helper for repeated `b.addTest(...)` setup while preserving:
  - `filters = b.args orelse &.{}`
  - `use_llvm = true`
- Added one file-local helper for repeated `b.addRunArtifact(...)` setup while preserving conditional `has_side_effects`.
- Kept VT-specific module setup explicit and unchanged:
  - internal module and `vt_options` wiring
  - ABI module, include path, `ffi` import, and `ffi_options` wiring
  - simulation wiring
  - benchmark wiring
- Verification after the cut:
  - `howl-vt`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

### Item 9c Completed

- Deduplicated unit/ABI test-artifact plumbing locally in `howl-render/build.zig`.
- Added one file-local helper for repeated `b.addTest(...)` setup while preserving:
  - `filters = b.args orelse &.{}`
  - `use_llvm = true`
- Added one file-local helper for repeated `b.addRunArtifact(...)` setup while preserving conditional `has_side_effects`.
- Kept render-specific module setup explicit and unchanged:
  - unit/ABI root setup
  - benchmark wiring
  - FFI/install wiring
- Verification after the cut:
  - `howl-render`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

### Item 9d Completed

- Deduplicated repeated test run-artifact plumbing locally in `howl-linux-host/build.zig`.
- Added one file-local helper for repeated `b.addRunArtifact(...)` plus conditional `has_side_effects`.
- Kept all `b.addTest(...)`, module-root creation, linking/configuration, and step-graph wiring explicit.
- Verification after the cut:
  - `howl-linux-host`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

### Item 9 Closure Verdict

- Item 9 is complete enough on the current path.
- The small local repetition cuts in `howl-pty/build.zig`, `howl-vt/build.zig`, `howl-render/build.zig`, and the remaining run-artifact-only cut in `howl-linux-host/build.zig` are now done.
- Further host-build dedup would require broader abstraction over module creation, linking differences, or test graph policy and is no longer a small local plumbing slice.

### Item 10 Started

- First accepted top prod-LOC reduction cut landed in `howl-render/src/prepared/render_surface_emitter.zig`.
- Deduplicated the repeated prepared fill-pass helpers with one file-local helper while preserving:
  - `emitPrepared()` pass ordering
  - `appendPreparedFullRedrawClear()` separation
  - `appendPreparedFillCommand()` behavior
  - `tryMergePreparedFillCommand()` behavior
- Verification after the cut:
  - `howl-render`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

- Second accepted top prod-LOC reduction cut landed in `howl-render/src/text/scene.zig`.
- Deduplicated the repeated scene-assembly population block with one file-local helper while preserving:
  - owned-vs-borrowed setup/teardown separation
  - public builder APIs
  - append order
  - atlas-cache and damage behavior
- Verification after the cut:
  - `howl-render`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

- Third accepted top prod-LOC reduction cut landed in `howl-render/src/text/font/ft_hb/special_sprite.zig`.
- Pruned only the redundant classic generated-special fallback arms already covered by `howl-render/src/text/raster/special.zig`.
- Kept all residual fallback families intact.
- Verification after the cut:
  - `howl-render`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

- Fourth accepted top prod-LOC reduction cut landed in `howl-vt/src/parser/events.zig`.
- Reduced `parser/events.zig` to the live event vocabulary only.
- Moved the stale `ParsedEvents` queue/materializer surface and its proofs to `howl-vt/src/parser/events_test.zig`.
- Verification after the cut:
  - grep receipt: `ParsedEvents` references remain only in `howl-vt/src/parser/events_test.zig`
  - `howl-vt`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

- Fifth accepted prod-reduction cut landed in `howl-render/src/benchmark_main.zig`.
- Deduplicated repeated benchmark workload assembly and repeated damage-literal construction with file-local helpers.
- Kept workload contents, full-vs-sparse distinctions, and benchmark output/build behavior unchanged.
- Verification after the cut:
  - `howl-render`: `zig build benchmark:render:build`
  - `howl-render`: `zig build test && zig build check`

- Sixth accepted prod-reduction cut landed in `howl-render/src/render/render_surface_realizer.zig`.
- Moved the inline proof lane and test-only scaffolding out of the production owner into `howl-render/src/render/render_surface_realizer_test.zig`.
- Rewired `howl-render/src/test/unit/root.zig` to import the sibling test file instead of the production owner directly.
- Kept production logic unchanged and added no production hooks.
- Verification after the cut:
  - grep receipt: `^test ` no longer matches `howl-render/src/render/render_surface_realizer.zig`
  - grep receipt: `src/test/unit/root.zig` imports `../../render/render_surface_realizer_test.zig`
  - `howl-render`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

- Seventh accepted prod-reduction cut landed in `howl-render/src/text/raster/special.zig`.
- Moved the inline proof lane and test-only helpers out of the production owner into `howl-render/src/text/raster/special_test.zig`.
- Rewired `howl-render/src/test/unit/root.zig` to import the sibling test file.
- Kept raster production logic unchanged and added no production hooks.
- Verification after the cut:
  - grep receipt: `^test ` no longer matches `howl-render/src/text/raster/special.zig`
  - grep receipt: `src/test/unit/root.zig` imports `../../text/raster/special_test.zig`
  - `howl-render`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

- Eighth accepted prod-reduction cut landed in the VT parser owners.
- Moved the remaining inline parser proof lanes out of:
  - `howl-vt/src/parser/string_control.zig`
  - `howl-vt/src/parser/main.zig`
- Rehomed those proofs into the existing sibling test files:
  - `howl-vt/src/parser/string_control_test.zig`
  - `howl-vt/src/parser/main_test.zig`
- Kept parser production logic unchanged and added no production hooks.
- Verification after the cut:
  - grep receipt: `^test ` no longer matches `howl-vt/src/parser/string_control.zig`
  - grep receipt: `^test ` no longer matches `howl-vt/src/parser/main.zig`
  - `howl-vt`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

- Ninth accepted prod-reduction cut landed in `howl-render/src/text/font/ft_hb/support.zig`.
- Moved the remaining FT/HB support proofs out of the production owner into `howl-render/src/text/font/ft_hb/support_test.zig`.
- Removed the test-only import and test-only font-path helper from production.
- Kept production behavior unchanged and used only one narrow testing hook for the bounded-buffer proof.
- Verification after the cut:
  - grep receipt: `support.zig` has no `^test ` matches
  - grep receipt: `support.zig` no longer references `test_font_options`, `InjectedTestFontPaths`, or `injectedTestFontPaths`
  - grep receipt: `src/test/unit/root.zig` imports `../../text/font/ft_hb/support_test.zig`
  - `howl-render`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

- Tenth accepted prod-reduction cut landed in `howl-linux-host/src/terminal/context.zig`.
- Purged dead private wrappers `driveRender`, `prepare`, `takePreparedUpload`, `submit`, and the dead private alias `ScrollMouseOutcome`.
- Kept the live render/submit/testing owner surface unchanged.
- Verification after the cut:
  - `howl-linux-host`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

- Eleventh accepted prod-reduction cut landed in `howl-linux-host/src/display/renderer/render_surface.zig`.
- Purged dead private helpers `findCreate` and `retireForResource`.
- Kept live render-surface classification, upload, and draw behavior unchanged.
- Verification after the cut:
  - grep receipt: no `findCreate` or `retireForResource` references remain under `howl-linux-host/src/display/renderer`
  - `howl-linux-host`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

- Twelfth accepted prod-reduction cut landed in `howl-linux-host/src/display/renderer/render_surface.zig`.
- Purged the dead untextured draw seam by deleting the dead optional texture-rect parameter from `drawQuad` and removing the dead textured-branch locals.
- Kept fill and textured draw behavior unchanged.
- Verification after the cut:
  - grep receipt: `drawQuad(` has one call site and one definition, both in `howl-linux-host/src/display/renderer/render_surface.zig`
  - `howl-linux-host`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

- Thirteenth accepted prod-reduction cut landed in `howl-linux-host/src/display/renderer/render_surface.zig`.
- Deleted the dead `GlStateSample` carrier and `sampleGlState()` helper.
- Replaced the three phase-end sample checks with a direct GL error helper while keeping exact failure messages and render behavior unchanged.
- Verification after the cut:
  - grep receipt: no `GlStateSample` or `sampleGlState` references remain in `howl-linux-host/src/display/renderer/render_surface.zig`
  - `howl-linux-host`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

- Fourteenth accepted prod-reduction cut landed in `howl-render/src/text/font/ft_hb/special_sprite.zig`.
- Deleted dead private declarations `AlphaSegment`, `drawAlphaH()`, `drawAlphaV()`, `fillAlphaChecker()`, and `drawAlphaRoundedCorner()`.
- Deleted unreachable `0x1fb9a` / `0x1fb9b` arms only from `drawAlphaHalfTriangleCodepoint()` while preserving the live top-level dispatch for those codepoints.
- Removed the identical no-op branch in `drawAlphaBranchNode()` and the dead `steps` local in `drawAlphaSpinner()`.
- Verification after the cut:
  - grep receipt: no `AlphaSegment`, `drawAlphaH`, `drawAlphaV`, `fillAlphaChecker`, or `drawAlphaRoundedCorner` references remain in `special_sprite.zig`
  - `howl-render`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

- Fifteenth accepted prod-reduction cut landed in `howl-render/src/text/raster/special.zig`.
- Deduplicated the repeated 8-way range partition algorithm shared by `eightRange()` and `eighthRange()` with one file-local helper.
- Kept `fourthRange()` separate and preserved the exact oversize clamp path, redistribution order, and accumulated-position behavior.
- Verification after the cut:
  - `howl-render`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

- Sixteenth accepted prod-reduction cut landed in `howl-render/src/text/scene.zig`.
- Deduplicated the repeated cursor rectangle emission logic shared by `SceneAssembly.appendCursorDraws(...)` and public `cursorDraws(...)` with one private file-local helper.
- Kept the public API, allocation behavior, output order, and rectangle counts unchanged.
- Verification after the cut:
  - `howl-render`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

- Accepted keeper verdict for `howl-render/src/benchmark_main.zig`.
- Item 10e already removed the narrow repeated workload-assembly seam through `workloadDamage(...)` and `buildWorkload(...)`.
- Remaining workload builders are live benchmark payload truth, not duplicate scaffolding.
- Remaining execution plumbing and the two output formats are live owner behavior for this benchmark surface.

- Seventeenth accepted prod-reduction cut landed in `howl-render/src/prepared/render_surface_emitter.zig`.
- Removed the remaining testing-only emission pipeline, exported fixture/types, and `testing.emit` from the production owner and rehomed them into `howl-render/src/prepared/render_surface_emitter_test.zig`.
- Kept only `testing.appendGlyphRef` and `testing.publishSurface` in production.
- Verification after the cut:
  - grep receipt: `render_surface_emitter.zig` no longer contains `ColorMode`, `emitTesting`, `resetTesting`, `appendTestingFillPass`, `appendTestingSprites`, `appendTestingCreate`, `appendTestingUpload`, `spriteResource`, `uploadFormat`, `Fixture`, `Fill`, `Sprite`, or `testing.emit`
  - `howl-render`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

- Eighteenth accepted prod-reduction cut landed in `howl-render/src/render/render_surface_realizer.zig`.
- Removed the dead glyph-atlas branch from `validateSpriteCommand()` and deleted the now-unused `isGlyphAtlas()` helper.
- Kept validation behavior otherwise unchanged.
- Verification after the cut:
  - `howl-render`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

- Nineteenth accepted prod-reduction cut landed in `howl-render/src/text/raster/special.zig`.
- Deduplicated the braille 4x4 supersample loop by routing braille dot coverage through the existing supersample helper with file-local braille coverage helpers.
- Kept braille layout, fast paths, clipped `w`/`h`, and alpha accumulation semantics unchanged.
- Verification after the cut:
  - `howl-render`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

- Twentieth accepted prod-reduction cut landed in `howl-linux-host/src/display/renderer/render_surface.zig`.
- Deleted the private single-use validation wrappers `validateCreates`, `validateUploads`, and `validateRetires` and inlined their loops into `validateSurfaceTransition()`.
- Kept validation behavior and the testing hook surface unchanged.
- Verification after the cut:
  - `howl-linux-host`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

- Twenty-first accepted prod-reduction cut landed in `howl-render/src/text/font/ft_hb/special_sprite.zig`.
- Deleted the dead private helpers `drawAlphaQuadraticStroke()`, `count32()`, and `pixelCount()`.
- Kept nearby live pixel-index helpers unchanged.
- Verification after the cut:
  - `howl-render`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

- Twenty-second accepted prod-reduction cut landed in `howl-render/src/text/scene.zig`.
- Made dotted/dashed underline cadence arithmetic a single private source of truth for both count and emission and shared the stepped underline append path locally.
- Added narrow inline tests proving counted capacity stays aligned with emitted dotted/dashed geometry.
- Verification after the cut:
  - `howl-render`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

- Twenty-third accepted prod-reduction cut landed in `howl-render/src/text/shape/cluster.zig`.
- Deduplicated the shared `contract.RenderableCell` literal assembly with one private file-local helper.
- Kept `renderableFromCellInput(...)` and `renderableFromInput(...)` as thin adapters and preserved the `CellInput`-local underline-style policy.
- Verification after the cut:
  - `howl-render`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

- Twenty-fourth accepted prod-reduction cut landed in `howl-vt/src/simulation/protocol.zig`.
- Kept `appendAssetText()` and `appendAssetPayload()` as distinct wrappers while deduplicating their shared asset-sampling loop and adding an explicit payload sanitizer alongside `sanitizeTextByte()`.
- Kept protocol roles and asset-end short-write behavior unchanged.
- Verification after the cut:
  - `howl-vt`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

- Twenty-fifth accepted prod-reduction cut landed in `howl-vt/src/screen.zig`.
- Added one private file-local helper for the shared owned visible-grid allocation/setup lane used by `initWithCellsAndDefaultCursorStyle(...)` and `initWithCellsHistoryAndDefaultCursorStyle(...)`.
- Kept history-specific zero-length allocations and the `history_capacity` asymmetry local to the history constructor and preserved cleanup behavior and public constructor semantics.
- Verification after the cut:
  - `howl-vt`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

- Twenty-sixth accepted prod-reduction cut landed in `howl-render/src/text/raster/special.zig`.
- Deduplicated the contiguous block-element ladders in `rasterizeBlockElementAlpha()` for:
  - `0x2581...0x2587` bottom-eighth block fills
  - `0x2589...0x258f` left-eighth block fills
- Kept explicit singleton, shade, quadrant, box-line, octant, and braille owner behavior unchanged.
- Added focused proofs in `howl-render/src/text/raster/special_test.zig` for:
  - `0x2580` top-half geometry
  - `0x2589` left-seven-eighths geometry
- Delegated reviewer acceptance:
  - reviewer session `ses_161a5ff2cffewXTHzxtWmLumNr`
  - verdict: `No findings.` Accept.
- Verification after the cut:
  - focused proof: `howl-render`: `zig build test -- "generated special raster draws top half block"`
  - focused proof: `howl-render`: `zig build test -- "generated special raster draws left seven eighths block"`
  - `howl-render`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

- Twenty-seventh accepted prod-reduction cut landed in `howl-linux-host/src/display/renderer/render_surface.zig`.
- Collapsed dead always-true result seams in the host render-surface owner by converting these panic-or-success helpers from `bool` to `void`:
  - `realizeSurface`
  - `realizeSurfaceLocked`
  - `validateSurface`
  - `createTexture`
  - `uploadTexture`
  - `retireTexture`
  - `ensureSurface`
  - `uploadRenderSurfaceCommands`
- Deleted the dead rollback/result machinery made unreachable by those signature collapses:
  - `CreatedResources`
  - `rollbackCreates(...)`
  - `invalidateUploads(...)`
  - the false-branch control flow in `realizeSurfaceLocked(...)`
- Preserved the real recoverable host-upload boundary at `uploadRenderSurface(...) -> bool`.
- Preserved `uploadFillCommands(...)` / `uploadFillCommand(...)` as the only live recoverable `bool` leaves in this owner.
- Updated the sibling proof in `howl-linux-host/src/display/renderer/render_surface_test.zig` for the `validateSurface(...)` signature change.
- Research authority:
  - `ses_1619d8350ffeMaAuBKhwEcP7zS`
- Review path:
  - initial review rejection in session `ses_161724c6dffedjVpU1T4zU2q51` correctly caught the remaining `ensureSurface(...) -> bool` seam
  - worker follow-up fixed that rejection in session `ses_161751f17ffevXtSOzQDDafkPK`
  - final acceptance in session `ses_161724c6dffedjVpU1T4zU2q51`: `No findings.`
- Verification after the cut:
  - scoped diff receipt: `git diff -- src/display/renderer/render_surface.zig src/display/renderer/render_surface_test.zig` in `howl-linux-host`
  - `howl-linux-host`: `zig build test && zig build check && zig build run -Doptimize=ReleaseFast`
  - workspace root: `zig build test && zig build check`

- Twenty-eighth accepted prod-reduction cut landed in `howl-render/src/text/scene.zig`.
- Removed the identity route layer by deleting:
  - `UnderlineRoute`
  - `underline_routes`
  - `CursorRoute`
  - `cursorRoute()`
  - `underlineRoute()`
- Switched the local scene owner dispatch directly on the real owner enums already in use:
  - `contract.UnderlineStyle`
  - `CursorShape`
- Kept cursor and underline geometry policy unchanged.
- Added focused inline proof `scene double underline count and geometry stay aligned` proving:
  - `.double` underline count stays `2`
  - built scene output emits exactly two `.underline` draws in top-then-bottom geometry order
- Research authority:
  - `ses_16169d6b3ffeS2zcfZObPZPY92`
- Review path:
  - initial reviewer session `ses_16166769bffe8r679vNuuXaw7Q` rejected worker-readiness until the `.double` underline proof was explicitly required
  - adjusted contract then accepted in reviewer session `ses_16166769bffe8r679vNuuXaw7Q`
  - final diff acceptance in reviewer session `ses_161610c44ffeV6TzWIVqLi2yK4`: `No findings.`
- Verification after the cut:
  - `howl-render`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

- Twenty-ninth accepted prod-reduction cut landed across:
  - `howl-render/src/text/font/ft_hb/special_sprite.zig`
  - `howl-render/src/text/font/ft_hb/glyph_raster.zig`
- Removed the owner-false deterministic fallback trampoline by deleting:
  - `special_sprite.rasterizeFallbackGlyph(...)`
  - the dead `fallback` import from `special_sprite.zig`
- Rerouted both closed deterministic fallback callsites in `glyph_raster.zig` directly to `fallback.rasterAsciiOrPlaceholder(...)`.
- Added focused inline proof in `glyph_raster.zig` covering both provider-owned deterministic fallback entry points:
  - `rasterizeProviderGlyph(...)`
  - `providerRasterizeSprite(...)` through `tryRasterizeProviderSpecialCase(...)`
- The proof forces the deterministic fallback gate and asserts produced pixels match the placeholder raster path.
- Research authority:
  - `ses_16158e639ffeiD7Th7LpdjXN0U`
- Review path:
  - worker-ready acceptance in reviewer session `ses_161555d16ffeauznZS20tqxQkO`
  - final diff acceptance in reviewer session `ses_1614ed064ffeXv3iS24h7xBh5T`: `No findings.`
- Verification after the cut:
  - scoped diff receipt: `git diff -- src/text/font/ft_hb/special_sprite.zig src/text/font/ft_hb/glyph_raster.zig` in `howl-render`
  - `howl-render`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

- Thirtieth accepted prod-reduction cut landed in `howl-vt/src/parser/string_control.zig`.
- Deleted the dead exported buffered string-control owner:
  - `pub const StringControl`
- Deleted dead private helper:
  - `isDigit`
- Kept all live `OscControl` and `PassthroughControl` behavior unchanged.
- Research authority:
  - `ses_161403342ffeRzUg5LCMjPAp2E`
- Review path:
  - worker-ready acceptance in reviewer session `ses_1613d54adffeZowxGp87dkTZPj`
  - final diff acceptance in reviewer session `ses_16123878cffeTsibrhVRzkoYg5`: `No findings.`
- Verification after the cut:
  - scoped diff receipt: `git diff -- src/parser/string_control.zig` in `howl-vt`
  - grep gate: no code hits for `\bStringControl\b`; remaining root hit during verification was only the active contract text before receipt
  - grep gate: no code hits for `isDigit\(`
  - `howl-vt`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

- Thirty-first accepted prod-reduction cut landed across:
  - `howl-vt/src/howl_vt.zig`
  - `howl-vt/src/input/tokens.zig` (deleted)
  - `libs.yaml`
- Deleted the dead input-token owner file `howl-vt/src/input/tokens.zig`.
- Removed its dead unit-root import/test touchpoint from `howl-vt/src/howl_vt.zig`.
- Removed the stale owner-map entry from `libs.yaml` so repository metadata no longer advertises the deleted owner.
- Research authority:
  - `ses_1610ded9effeEP0ncqQ5cMEcgI`
- Review path:
  - worker-ready acceptance in reviewer session `ses_1610c16b8ffenvxSNcjyzbyp2D`
  - initial diff rejection in reviewer session `ses_160ca5586ffeNb14NL5LLre9BS` caught the stale `libs.yaml` owner-map path
  - final acceptance in reviewer session `ses_160ca5586ffeNb14NL5LLre9BS`: `No findings.`
- Verification after the cut:
  - grep gate: no code hits for `input/tokens\.zig`, `\bparseKeyToken\b`, `\bparseModifierBits\b`, or `KEYCODE_`
  - `howl-vt`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

- Thirty-second accepted prod-reduction cut landed across:
  - `howl-vt/src/screen/tabs.zig`
  - `howl-vt/src/screen/tabs_test.zig`
- Removed the redundant destination re-default from `copyTabStops(...)`.
- Kept `copyTabStops(...)` as a copy-only helper.
- Preserved the live resize caller invariant that destination tab stops are allocated through `tabs.allocTabStops(...)` immediately before copying.
- Added focused proof `screen tabs: resize wider preserves custom and default stops` proving:
  - custom stop at `5` survives growth from width `20` to `25`
  - cleared default stop at `8` stays cleared in the copied prefix
  - old default stop at `16` survives
  - newly added default stop at `24` is still present
- Research authority:
  - `ses_160c3d27cffeQveW8CeVUuNKdQ`
- Review path:
  - worker-ready acceptance in reviewer session `ses_160c0ce3affe1AEIdbR8GtNnGf`
  - final diff acceptance in reviewer session `ses_160bcc1f5ffefjHwk46U5ugUUa`: `No findings.`
- Verification after the cut:
  - `howl-vt`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

- Thirty-third accepted prod-reduction cut landed across:
  - `howl-vt/src/screen/cursor.zig`
  - `howl-vt/src/screen/apply.zig`
- Removed the local cursor-style datatype mirror by aliasing screen cursor types directly to the action-owner cursor types.
- Replaced the manual cursor-style remap in `screen/apply.zig` with direct assignment.
- Kept `Screen.CursorShape`, `Screen.CursorStyle`, and `Screen.default_cursor_style` as the curated screen exports.
- Kept FFI cursor-style translation behavior unchanged.
- Research authority:
  - `ses_160b9c4b0ffelzR1kQPdPFgqz7`
- Review path:
  - worker-ready acceptance in reviewer session `ses_160b7e467ffeLXLP20ObWk40Ty`
  - final diff acceptance in reviewer session `ses_160b3a4beffeFWiWa5l9MRGPuJ`: `No findings.`
- Verification after the cut:
  - `git diff --check -- src/screen/cursor.zig src/screen/apply.zig src/screen.zig` in `howl-vt`
  - `howl-vt`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

- Thirty-fourth accepted prod-reduction cut landed across:
  - `howl-vt/src/xterm/csi/params.zig`
  - `howl-vt/src/xterm/csi/leader.zig`
  - `howl-vt/src/xterm/csi/private.zig`
  - `howl-vt/src/action/route_test.zig`
- Centralized the repeated key-format `u8` saturation parse into one narrow CSI parameter helper.
- Rerouted only the repeated key-format parse sites:
  - `leader.zig` key-format resource parse
  - `private.zig` key-format query parse
- Left unrelated leader/private parameter domains unchanged.
- Added focused route proofs for:
  - `CSI > f` resource saturation above `255`
  - `CSI ? g` query saturation above `255`
  - non-positive normalization to `0`
- Research authority:
  - `ses_160b0cbe5ffeU1TC2M3yYs9i7D`
- Review path:
  - worker-ready acceptance in reviewer session `ses_160ae8e33ffebtMsfrVszjc7PP`
  - final diff acceptance in reviewer session `ses_160a9d8f7ffeEUo1W1IPmsolQr`: `No findings.`
- Verification after the cut:
  - `howl-vt`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

- Thirty-fifth accepted prod-reduction cut landed in `howl-vt/src/parser/utf8.zig`.
- Removed the unreachable non-ASCII one-byte path from `Utf8Decoder.feed(...)`.
- Added `std.debug.assert(seq_len > 1);` immediately after `utf8ByteSequenceLength(...)` in the non-ASCII path to make the dead-branch proof explicit.
- Removed the redundant cast on the remaining `utf8Decode(...)` success return.
- Added owner-local reset proofs for:
  - invalid start leaves the decoder clear
  - invalid continuation resets the partial sequence
- Research authority:
  - `ses_160a6e765ffe6zO7JiAPRqVf8R`
- Review path:
  - worker-ready acceptance in reviewer session `ses_160a45454ffe8Xsd2HHzOLMrKM`
  - final diff acceptance in reviewer session `ses_160a03eeaffef03i2SEj7fR2FR`: `No findings.`
- Verification after the cut:
  - `howl-vt`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

### Host Render-Surface Runtime Fix Accepted

- Accepted a narrow host correctness fix in:
  - `howl-linux-host/src/display/renderer/render_surface.zig`
  - `howl-linux-host/src/display/renderer/render_surface_test.zig`
- Runtime symptom:
  - `zig build run -Doptimize=ReleaseFast` could panic with `trusted render surface has unsupported shape` from `uploadRenderSurface(...)`
- Accepted root cause:
  - classifier gaps allowed prepared patch surfaces to reach no recognized host upload shape even though the upload paths could handle them
  - `renderSurfaceGlyphPatch()` rejected bounded `DRAW_SPRITE` commands mixed with glyph patch commands
  - `renderSurfaceFillPatch()` rejected bounded resource-free patch surfaces containing `CLEAR_RECT` plus `FILL_RECT`
- Accepted fix shape:
  - `renderSurfaceGlyphPatch()` now accepts bounded `HOWL_RENDER_SURFACE_COMMAND_DRAW_SPRITE` with sprite-command validation and patch-bounds checks
  - `renderSurfaceFillPatch()` now accepts bounded resource-free `CLEAR_RECT` and `FILL_RECT` patch commands by validating the existing fill command shape plus positive area and patch bounds
  - `uploadFillCommands()` now asserts the exact accepted upload shapes: fill-only or fill-patch
- Added focused regression proofs:
  - `render surface fill patch accepts bounded clear and fill commands`
  - `render surface glyph patch accepts bounded sprite and glyph commands`
- Delegated reviewer acceptance:
  - reviewer session `ses_161d2316dffe8ECpz3EvKuMzKl`
  - verdict: `No findings.` Accept.
- Verification after the fix:
  - `howl-linux-host`: `zig build test && zig build check && zig build run -Doptimize=ReleaseFast`
  - workspace root: `zig build test && zig build check`

- Keeper pressure noted during slice 7b audit:
  - `howl-linux-host/src/terminal/render/retained.zig` currently reads as a real owner of render-session retained state and ABI mutation, not an alias bucket like the old PTY/VT retained-state structs
  - do not collapse that file mechanically without stronger source-backed proof

### Gate Fix 1 Completed

- Replaced the flaky owned-PTY interrupt proof with a deterministic integration proof in `howl-pty/src/pty_integration_test.zig`.
- New proof shape:
  - runs a foreground child shell that installs its own `INT` trap and prints `child`
  - asserts the trap output arrives after `transport.control(.interrupt)`
  - then asserts the transport reaches `NotStarted`
- This proof failed consistently before the implementation fix.

- Fixed PTY control routing in `howl-pty/src/pty/posix.zig`.
  - `controlPty()` now sends the signal to the child process group instead of only the shell pid

- Verification after the fix:
  - deterministic proof passed twice:
    - `zig build test:integration -- "owned unix pty interrupt reaches the child group"`
    - `zig build test:integration -- "owned unix pty interrupt reaches the child group"`
  - `howl-pty`: `zig build test && zig build check`
  - workspace root: `zig build test && zig build check`

Rejected non-accepted attempt during slice 5:

- A host `main.zig` test extraction attempt was explored and then reverted before acceptance.
- Reason: Zig private/generic visibility and root-module behavior made that cut brittle on the current host test architecture.
- No part of that attempted extraction remains on the tree.

### Next Sequential Slice

- Remove inline test and fake scaffolding from the largest polluted production owners listed in `loc-debt-sprint-scope.md`.

## 2026-05-30 Workflow And Boundary Law

- Product boundary: Howl is a C ABI embeddable terminal.
- Hosts embed `howl-pty`, `howl-vt`, `howl-render`, and `howl-hosts/vendor/*` contracts.
- Hosts own platform UX, event loops, wake policy, presentation cadence, runtime
  orchestration, and backend resource realization.
- `howl-pty` owns PTY variants, child I/O, resize delivery, control signals, and
  transport state.
- `howl-vt` owns parser state, terminal state, selection, input encoding,
  host-facing protocol consequences, and VT-surface truth.
- `howl-render` owns render contracts, geometry policy, retained-frame state,
  prepare/submit scheduling, render-surface contracts, and text shaping.
- Public roots curate exports only. Namespace wrappers aggregate owners only. FFI
  translates contracts only. Owner files own state and mutation.
- Banned owner vocabulary remains banned unless a later accepted scratchpad says
  otherwise: `manager`, `engine`, `controller`, `utils`, `runtime`, `pipeline`,
  `queue`, ownerless `types.zig`, and broad compatibility aliases.
- Design source order: Ghostty, Alacritty, TigerBeetle, official docs, then the
  smallest Howl-specific invention.

## 2026-05-30 Host Canonical Memory

Canonical source scratchpads archived into this section:

- `host-owner-next-scratchpad.md`
- `host-reshape-scratchpad.md`
- `host-alacritty-gap-scratchpad.md`
- `cleanupscratchpad.md` host portions

### Current Host Facts

- `howl-linux-host/src/main.zig` currently owns process bootstrap,
  event-loop admission, terminal input forwarding, tab lifecycle, present
  submission/completion, and tests.
- `howl-linux-host/src/tab_bar/slots.zig` owns bounded tab slot storage/order.
- `howl-linux-host/src/window/pacing.zig` owns frame-pacing state, pending-loop
  input, and present-permission reasons.
- `howl-linux-host/src/terminal/context.zig` currently owns one terminal
  surface/session aggregate: PTY/VT/render lifecycle, text and pointer event
  routing, cursor blink cadence, clipboard OSC 52 writes, render
  prepare/submit/upload, title refresh, scrollbar adaptation, and tests.
- `howl-linux-host/src/terminal/selection.zig` owns host selection gesture
  adaptation over context-owned selection fields.
- `howl-linux-host/src/terminal/links.zig` owns visible-link hover/open behavior
  over context-owned link fields.
- `howl-linux-host/src/input/input.zig` owns SDL event pumping, input queues,
  binding queueing, text chunking, key and mouse translation, redraw request bit,
  geometry/focus pending bits, and tests.
- Production SDL/OpenGL translation is build-owned through `sdl_c` and `gl_c`.
- `window.c_win` has been deleted. Remaining direct `@cImport` sites are explicit
  non-goals from that slice: `window/icon.zig`, `utils/tools/ascii_rain_stress.zig`,
  and `utils/tools/visual_rain_stress.zig`.
- Historical host reshapes are already reflected in current code: old
  `terminal/runtime`, old `terminal/host`, and `terminal_panel.zig` vocabulary
  were superseded by `terminal/context.zig` and owner subfolders.
- Prior host cadence work is already present: `FramePacing.State`,
  `FramePacing.PresentReason`, `PresentPlan`, separate present completion,
  `DrainInputOutcome`, `drainTextInputFastPath`, and `drainPointerAndUiInput`.
- `terminal/c.zig` has been deleted; Howl PTY/VT/render C imports are
  build-owned modules.

### Host Reference Facts

- Ghostty `App` owns the primary GUI run loop and dispatches explicit mailbox
  actions; `Surface` is one terminal widget/session aggregate; `Termio` owns
  terminal state, PTY, subprocess, and byte I/O; its mailbox is explicitly
  bounded.
- Alacritty startup creates window, terminal state, PTY, I/O loop, input
  processor, config monitor, and runs a display loop. `Processor` owns event
  dispatch and windows map. `WindowContext` owns one terminal window aggregate.
  Scheduler topics include selection scrolling, delayed search, blink cursor,
  blink timeout, and frame.
- Alacritty processes renderer updates right before drawing, couples grid resize
  with PTY resize and damage tracker resize, collects renderable content while
  holding the terminal lock, then drops the lock before drawing.
- TigerBeetle pressure: explicit bounded control flow, assertions for invariants,
  central control/state mutation, and processing external events at the program's
  own pace.

### Accepted Host Direction

- Keep moving toward an Alacritty/Ghostty split:
- Top-level app/event processor owns event-loop dispatch, tab/window list,
  scheduler/pacing, and routing.
- Per-terminal context owns one embedded terminal widget/session and exposes exact
  effects to the app.
- Window/display/present owners own backend realization and presentation.
- Input owner translates SDL events into host input events but must not own
  terminal widget policy.
- Cross-thread/wake paths must stay bounded and explicit.
- Do not infer a giant target tree. Promote one reference-backed seam at a time.

### Completed Host Slices On 2026-05-30

- `dfa66b5 host: move tab slots owner` and root `2181e7e`.
- `11b21eb host: move frame pacing owner` and root `8beb52d`.
- `742ef69 host: delete window c bucket` and root `313526a`.
- `6477dcb host: split terminal pointer owners` and root `ce87dfb`.

### Active Host Follow-Up Slices

- No promoted host follow-up slice is active after the 2026-05-30 owner cleanup.
- Future work should start from fresh research against current source, not the
  archived pre-cleanup slice specs.
- `howl-linux-host/src/main.zig` still contains app-owner tests. Do not extract
  them by making private app helpers public or by inventing a test taxonomy. Test
  relocation is blocked on the build/test architecture plan unless a future
  source-backed host slice moves a helper to its exact true owner with behavior
  tests in the same owner file.

### Host Verification Gates

- Host package: `zig build check`, `zig build test`.
- Root: `zig build check`, `zig build test`, `git diff --check`.
- Preserve ABI boundary: host code consumes PTY, VT, and render only through
  shipped C ABI contracts and build-owned translated modules.

## 2026-05-30 Render And VT ABI Canonical Memory

Canonical source scratchpads archived into this section:

- `render-host-boundary-scratchpad.md`
- `render-vt-abi-decoupling-scratchpad.md`
- `render-ownership-restart-scratchpad.md`
- `cleanupscratchpad2.md`
- `cleanupscratchpad3.md`
- `cleanupscratchpad.md` render portions

### Fixed Render/Host Boundary

- Backend independence is the first priority of the render ABI.
- `howl-render` must never own publication to a backend.
- Hosts own event loops, wake policy, redraw request policy, presentation cadence,
  runtime orchestration, backend resource realization, scheduling, and backend
  publication.
- `howl-render` exposes a C ABI state engine: host-owned data and calls in,
  prepared render data and explicit consequences out.
- `howl-render` must not hide a runtime loop, scheduler, presentation queue,
  swapchain, or backend frame lifecycle.
- `submit` means the host consumed a prepared output and render may update
  retained render-owned state. It must not mean publish or present to a backend.

### Render/VT ABI Decoupling Facts

- `howl-render/include/howl_render.h` previously included `howl_vt.h` and exposed
  VT-owned cell/color/selection/cursor types through render public ABI. This is
  an ownership violation.
- Source-backed verdict: VT owns terminal state truth; render owns render source
  ABI structs, retained prepare state, shaping, caching, prepared surfaces, and
  submit contracts; a boundary adapts VT truth into render source/draw data.
- Ghostty supports VT-owned render-state/surface APIs under VT-facing headers, not
  a renderer backend public ABI importing terminal state structs.
- Alacritty adapts terminal cells into `RenderableCell`; renderer consumes
  renderable cells, glyphs, batches, vertices, rectangles, and atlas state. It
  does not expose raw terminal `Cell` as a renderer public API.
- Kitty is monolithic and private; it does not justify a public renderer ABI
  importing terminal structs.

### Current Render Facts

- `howl-render/src/source/vt.zig`, `source/cell.zig`, `source/slot.zig`,
  `source/damage.zig`, `source/prepare_request.zig`, `render/geometry.zig`,
  and `session/submitted.zig` are the accepted direction after the `flow.zig`
  restart.
- `SurfaceTextOwner` should compose explicit owners: geometry, source slot,
  prepare requests, submitted state, source dirty epoch, and cursor blink phase.
- `source/*` owns VT-derived input snapshots, publication storage, dirty/source
  metadata, source validation, and source publication to text-scene/frame-input
  adaptation.
- `prepared/*` owns prepared render output and prepared-handle lifecycle only.
- `session/*` composes the public render object behind the C handle and owns
  submitted/retained token state and submit mailbox decisions.
- `render/*` owns text rendering and render geometry, not VT source slot storage.
- `surface` is a product term at the ABI boundary, not an umbrella source folder.
- `howl-render/src/source/text_input.zig` owns the final source-to-text adapter
  formerly stored at `surface/input.zig`; do not recreate `howl-render/src/surface/`.
- The render C translator lane is complete in current source: `libhowl_render.zig`
  is an export table importing `ffi/*` translator nouns, with `ffi.zig` as the
  shared C import/boundary entry. Do not promote old roadmap slices that move
  root translator files unless fresh source shows root translators returned.
- The render text `pipeline.zig` proof gap is complete in current source:
  `howl-render/src/text/pipeline.zig` no longer exists and no render Zig source
  contains `pipeline`, `text_pipeline`, or `text_flow` owner vocabulary.
- Render ABI layout assertions live beside the translator noun that proves the C
  layout. Current source keeps VT source publication layout assertions in
  `howl-render/src/ffi/vt_surface.zig`; `howl-render/src/ffi.zig` remains only the
  shared C import boundary. Do not move layout assertions into a generic
  ownerless bucket.

### Accepted Render Direction

- No `howl-render/src/surface/flow.zig` and no `Flow` owner.
- No generic mixed `surface/types.zig` by the end of the restart.
- No new umbrella `screen`, `surface`, `pipeline`, `queue`, `manager`,
  `controller`, or `runtime` bucket.
- Input/source and output/prepared/submitted owners must be separate files and
  separate fields in the session owner.
- Render still does not own backend presentation or host cadence.
- Host continues through the shipped C ABI.

### Render ABI Vocabulary Decisions

- ABI breakage is allowed and preferred over preserving wrong vocabulary.
- No compatibility shims or old-name aliases.
- Suspicious/wrong nouns from prior research:
  `HowlRenderSurfaceFeedback`, `surface_feedback.zig`, frame vocabulary,
  vague object wrappers, `SurfaceText`, `PreparedFrame`, `PendingState`, and broad
  `surface/*` bucket names.
- Owner-true replacement direction:
  `HowlRenderTextSession`, `HowlRenderTextSessionHandle`,
  `HowlRenderPreparedSurface`, `HowlRenderPreparedSurfaceHandle`,
  `HowlRenderLayoutResult`, `HowlRenderVtSurfaceSlot`,
  `HowlRenderVtSurfaceCommit`, `HowlRenderVtSurfacePublishResult`,
  `HowlRenderPreparedSurfaceToken`, `HowlRenderSubmittedSurfaceToken`,
  `HowlRenderSubmitExecution`, `HowlRenderSubmitResult`,
  `HowlRenderHostSurface`, `HowlRenderMetrics`, and
  `HowlRenderSessionWorkState`.
- First ABI vocabulary slice from research remains worker-ready if chosen:
  replace submit feedback/execution/surface handle vocabulary.
  Header renames: `HowlRenderSurfaceMetrics -> HowlRenderMetrics`,
  `HowlRenderSurfaceHandle -> HowlRenderHostSurface`,
  `HowlRenderSurfaceExecutionInput -> HowlRenderSubmitExecution`,
  `HowlRenderSurfaceFeedback -> HowlRenderSubmitResult`. Update render boundary
  translators and host call sites in `terminal/context.zig`,
  `terminal/render/retained.zig`, `terminal/render/abi.zig`, and
  `window/term_texture.zig`. No old typedefs or aliases.

### Render Source Publication Slice

Accepted no-header-change shape from `cleanupscratchpad2.md`:

- Source owner stores the writable publication cell span directly. FFI casts and
  returns the stable C span, then delegates commit/validation/cancel policy to
  source/session owners.
- `source/vt.zig` owns `SourceCell`, `SourceCellFlags`, `SourceCellAttrs`,
  `SourceColor`, `SourceColors`, `SourceSelection`, and `SourceSelectionPoint`;
  it validates source cells, colors, underline style, and `ReservedSourceMeta`.
- `source/slot.zig` owns retained `[]source_vt.SourceCell`, reserves the source
  span, validates source cells and dirty metadata during commit, and preserves
  retained storage behavior.
- `ffi.zig` must not own global publication scratch or source policy. It owns only
  C pointer casts, span translation, C status mapping, and layout assertions.
- Grep gates in `ffi.zig`: no `PublishScratch`, `ScratchMutex`, `publish_scratch`,
  `reservePublishScratch`, `copyPublishScratch`, `removePublishScratch`,
  `validatePublicationCellValue`, `reservedSource`, or `owner.source_slot`.

### Render Verification Gates

- Root: `zig build check`, `zig build test`, `git diff --check`.
- If root taxonomy blocks package-specific verification, run in `howl-render`:
  `zig build check`, `zig build test`.
- ABI gates: `howl-render/include/howl_render.h` must not expose `HowlVt*` types
  from the render public ABI after the decoupling slice; render source must not
  layout-assert against `c.HowlVt*` except at explicit FFI translation seams.

## 2026-05-30 Feature Gap Backlog

## 2026-06-04 Test Architecture Accountability Completion

- The test architecture accountability sprint is complete on the current tree.
- `howl-vt` generic bucket files under `src/test/` were reduced to explicit ABI, benchmark, helper, and small special-purpose surfaces; broad parser/action/screen/terminal buckets were moved to owner-true sibling test files under `src/`.
- `howl-pty` public roots no longer import unit or integration tests; dedicated curated roots now live at `src/test_unit.zig` and `src/test_integration.zig`, with owner-true sibling files `src/session_test.zig`, `src/session_integration_test.zig`, `src/pty_test.zig`, and `src/pty_integration_test.zig`.
- `howl-render` remaining generic test side-entry files were reduced to curated roots and sibling owner paths: `src/ffi_test.zig` and `src/render/geometry_test.zig`.
- `howl-linux-host` old `src/test/` aggregate roots were removed and replaced by curated `src/host_test_root.zig` and `src/integration_test_root.zig`; build wiring now points small smoke proofs directly at owner files such as `src/cli/args.zig`, `src/config/env.zig`, and `src/tab_bar/tab_bar.zig`.
- Verification after the cleanup passed at package and workspace scope: `howl-vt`, `howl-pty`, `howl-render`, `howl-linux-host`, workspace `zig build test`, and workspace `zig build check`.

Canonical source scratchpad archived into this section:

- `feature-gap-scratchpad.md`

Active gaps to preserve:

1. Hyperlink targets stop at `link_id`.
   VT interns OSC 8 URIs and stamps visible cells with `link_id`, but the product
   ABI needs a lookup/lifetime contract so host hover/open can resolve IDs to URIs.
   Important paths: `howl-vt/src/host/state.zig`, `howl-vt/src/ffi.zig`,
   `howl-vt/include/howl_vt.h`, `howl-render/include/howl_render.h`,
   `howl-linux-host/src/terminal/context.zig`.
2. VT-owned selection has no complete product boundary above VT.
   Need a C ABI selection contract across viewport/history coordinates and
   render/host presentation/copy behavior, or an explicit out-of-scope decision.
   Important paths: `howl-vt/src/selection.zig`, `howl-vt/src/selection/state.zig`,
   `howl-vt/include/howl_vt.h`, `howl-render/include/howl_render.h`,
   `howl-linux-host/src/terminal/context.zig`.
3. OSC 52 clipboard requests need host-owned policy completion.
   VT exposes pending clipboard drain; host must drain after VT feed and apply
   platform clipboard policy. Clipboard read/query still needs request/reply ABI
   if supported.
4. Dynamic terminal color state must become render truth.
   VT implements OSC 4/10-19 dynamic colors. Render must consume ABI-visible
   color state instead of fixed render-local defaults.
5. Kitty graphics export is closed.
   VT graphics truth is now exportable above VT through shipped ABI and consumed
   by host/render.
6. PTY child exit/transport-stop truth is closed.
   PTY ABI now carries typed lifecycle/result truth, including active-tab
   exit/failure distinctions used by host.
7. PTY resize success does not prove child-visible size was applied.
   Need ABI-visible applied-vs-requested resize state or typed resize result/error.
8. PTY control-signal ABI lacks foreground-process identity truth.
   Need process identity or foreground-group truth and explicit signal-target semantics.
9. VT cell style and visibility attrs must survive render scene prep.
   Render intake sees style/visibility/link attributes; scene prep must preserve
   bold, dim, italic, inverse, invisible, and link metadata.
10. Dynamic VT title should reach SDL window title if host policy wants active-tab
    title ownership.
11. Cursor blink state is lost at VT surface/render seam.
    Carry VT cursor `blink` truth through ABI while keeping cadence host-owned;
    host config should seed default/reset policy without overriding DECSCUSR truth.

## 2026-05-30 VT Hygiene Decisions

Canonical source scratchpads archived into this section:

- `research/2026-05-30-hygiene-audit/vt-host-consequence-capacity.md`
- `research/2026-05-30-hygiene-audit/vt-screen-owner-seams.md`
- `research/2026-05-30-hygiene-audit/vt-runtime-obligation-vocabulary.md`

Accepted decisions:

- `runtime` is accepted ABI and host scheduling vocabulary when it names a VT
  scheduling obligation or host wake/admission fact.
- `runtime` remains banned as an owner or module name. Do not add `runtime.zig`,
  `RuntimeManager`, or a VT runtime owner.
- VT host consequence storage is bounded but heap-backed today. Pending output,
  retained payloads, retained metadata, titles, hyperlink target count, and parser
  event count have explicit owner constants; static storage conversion still needs
  product capacity proof.
- Screen dirty state is the first accepted deeper screen seam. History authority,
  resize temporary storage, cursor, margins, and tabs require later scratchpads or
  promoted slices before movement.
- VT protocol scalar vocabulary Slice A is complete in current source for its
  originally promoted scope: `xterm/c0.zig` has a typed `C0` enum and
  `action/vocabulary.zig` carries erase operations as `EraseMode`, not raw `u2`.
  Future scalar work must start from fresh source-backed research, not the stale
  Slice A checklist.

## 2026-05-30 Build/Test Architecture Blocker

Canonical source scratchpad archived into this section:

- `build-test-architecture-blocker-scratchpad.md`
- `research/2026-05-30-hygiene-audit/build-test-architecture-plan.md`

Blocker:

- Repo-wide verification surface and build/entrypoint contracts are fragmented.
- There is no clearly documented strategy for test taxonomy, build-step taxonomy,
  install/default-step behavior, package ownership of verification surfaces, or
  auditability of what each step proves.

Consequence:

- Adding more tests, tools, fuzzers, harnesses, and run/build entrypoints without
  a governing plan increases confusion and review cost.

Research goal:

- Produce a comprehensive repo-wide plan covering current inventory,
  classification, gaps, normalization targets, migration order, and acceptance
  criteria.

Constraint:

- Planning only until a follow-up review loop accepts a code/build change slice.

Accepted plan:

- Root build orchestration aggregates package-owned steps only and must not
  import package internals.
- Normal deterministic package steps are `check`, `test`, `test:unit`,
  `test:unit:build`, `test:abi`, and `test:abi:build`, plus
  `test:integration` and `test:integration:build` when a package owns that
  class.
- Package tests are organized by curated roots per test class rather than one
  universal module-wide test entrypoint.
- `test:unit` owns owner-local invariant and behavior tests.
- `test:abi` owns shipped C header, exported symbol, layout, value, handle,
  status, and FFI translation proofs.
- `test:integration` owns explicit cross-package embedding behavior through
  shipped ABIs.
- Owner-local tests may be inline in owner files or in sibling owner-true test
  files, but must be reached through exactly one curated root for their class.
- `simulate`, `stress`, `benchmark`, and similar named non-proof surfaces stay
  explicit and are not substitutes for deterministic `check` or `test`.
- First accepted implementation slice normalized render `test:unit` and
  `test:abi` categories without product-code or test assertion changes.
- Accepted execution queue after render category normalization:

## 2026-06-04 Test Architecture Accountability Sprint

- Governing test law no longer claims one universal module-wide test entrypoint.
  Active law is curated package roots by test class, owner-local tests reached
  through exactly one curated root for their class, and explicit non-proof
  surfaces.
- `howl-render` no longer multiplexes unit, ABI, and benchmark wiring through
  one root. Current dedicated roots are:
  - `src/test_unit.zig`
  - `src/test_abi.zig`
  - `src/benchmark_main.zig`
- `howl-vt/src/howl_vt.zig` no longer imports `ffi.zig` in the unit-class root.
- Workspace `test:integration` wording now reflects explicit package-owned
  integration surfaces instead of claiming host-only ownership.
- `build-test-verification-ledger.md` has been corrected to match the current
  host, render, VT, and PTY root map.
- Verification receipts:
  - `howl-render`: `zig build test`
  - `howl-render`: `zig build benchmark:render:build`
  - `howl-vt`: `zig build test`
  - workspace: `zig build test:integration`
  - workspace: `zig build check`
  - workspace: `zig build test`
- Residual risk: PTY integration has a timeout-flake surface in
  `howl-pty/src/test/session_integration.zig`; one workspace `zig build test`
  run timed out before succeeding on package rerun and final workspace rerun.
  1. Decide VT regression gate policy from current regression roots and bounds.
  2. Normalize render `test:build`/`check` compile-only category coverage.
  3. Inventory host `main.zig` app-owner tests before moving any helper/test pair.
  4. Decide the owner for durable audit/grep gates before adding executable checks.
- VT regression bucket decision: `test:regression` is deleted. Snapshot behavior
  tests remain ordinary unit tests; seeded protocol and scrollback churn now live
  under the explicit `simulate` surface.
- Test-war correction: VT simulation naming is fixed, but `zig build simulate`
  currently exposes a parser assertion failure. Treat `simulate:build` as the
  compile gate and the failing run as the next simulation accountability bug.
- Render `test:build` now aggregates `test:unit:build` and `test:abi:build`; render `check` keeps
  depending on `test:build` for compile-only deterministic test coverage.
