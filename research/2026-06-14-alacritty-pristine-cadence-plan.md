# Alacritty Pristine Cadence Plan

Status:

- Active research artifact for the active benchmark sprint.
- Orchestrator session id: `orch-2026-06-14-ascii-rain-performance-01`.
- Researcher session id: `research-2026-06-14-ascii-rain-performance-01`.
- Reviewer session id: `review-2026-06-14-ascii-rain-performance-01`.

Current live section:

- Host/runtime present cadence and cursor truth inside the main benchmark sprint.
- This is not a sprint replacement.
- The previous ASCII-rain `direct_normal` proof ledger is historical navigation only unless explicitly re-promoted.

Current constraints:

- Micro-optimization is banned until the codebase is pristine and much more pragmatic and idiomatic than Alacritty.
- Fake narrow cuts are banned.
- Planning must produce big cuts on the real owner boundary, not tiny progress theater.

Sources read in order:

1. `loop/flow.md`
2. `loop/orcestrator.md`
3. `loop/researcher.md`
4. `loop/reviewer.md`
5. `loop/coder.md`
6. `sprints/current.txt`
7. `sprints/2026-06-14-alacritty-pristine-cadence-sprint.md`
8. `loops/alacritty-pristine-cadence-live-loop.txt`
9. `research/2026-06-14-alacritty-pristine-cadence-plan.md`
10. `reference-index.md`
11. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
12. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
13. `howl-linux-host/src/event.zig`
14. `howl-linux-host/src/terminal/surface.zig`
15. `howl-linux-host/src/terminal/cursor_blink.zig`
16. `howl-linux-host/src/display/present.zig`
17. `howl-linux-host/src/display/frame_timer.zig`
18. `howl-linux-host/src/display/display.zig`
19. `howl-linux-host/src/display/window.zig`
20. `howl-linux-host/src/event_loop.zig`
21. `howl-linux-host/src/terminal/pty_wait_thread.zig`
22. `howl-linux-host/src/terminal/pty_pump.zig`
23. `howl-linux-host/src/terminal/render_retained.zig`
24. `howl-linux-host/src/terminal/vt_retained.zig`
25. `howl-linux-host/src/terminal/surface_test.zig`
26. `utils/dev_references/terminals/alacritty/alacritty/src/event.rs`
27. `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs`
28. `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs`
29. `utils/dev_references/terminals/alacritty/alacritty/src/scheduler.rs`

Current-code facts:

- `howl-linux-host/src/event.zig:156-214` and `:330-489` mix wait admission, runtime drive, blink cadence, render turn, present submission, and present completion in one loop turn.
- `howl-linux-host/src/terminal/surface.zig:369-392` mixes wake admission, VT progress, cursor activity reset, clipboard write drain, and wake acknowledgement in one function.
- `howl-linux-host/src/terminal/surface.zig:394-420` and `:519-680` split the retained render/present state machine across implicit booleans instead of one explicit owner.
- `howl-linux-host/src/display/present.zig:56-87` and `howl-linux-host/src/display/display.zig:122-156` model present completion as if it were deferred, while the current SDL host completes synchronously on the same turn.
- `howl-linux-host/src/display/frame_timer.zig:68-70` leaves `notePresentComplete` as a no-op, so frame cadence is submission-timed rather than completion-truth-timed.
- `howl-linux-host/src/terminal/surface.zig:415-420` is the only place that ACKs a rendered snapshot back to VT, so stale replay risk sits at the retained-present boundary.
- `howl-linux-host/src/terminal/surface.zig:383-387` resets cursor blink activity using a fresh `EventLoop.nowNs()` instead of the turn time already passed in.
- Existing tests prove local mechanics, but not latest-state cadence across wake, render, present, complete, and cursor visibility.

Reference facts:

- `alacritty/src/event.rs:430-490` batches event handling and drains work at the event-processor level instead of mixing redraw/present logic through every event edge.
- `alacritty/src/window_context.rs:401-494` keeps dirty/draw ownership in the per-window owner instead of splitting it across the top loop and leaf owners.
- `alacritty/src/display/mod.rs:1451-1458` and `:1557-1600` separate draw completion from frame scheduling.
- `alacritty/src/event.rs:1621-1670` and `:1843-1860` treat cursor blink as scheduled dirty state, not as a bolted-on loop side effect.
- TigerBeetle pressure requires one clear control spine, explicit owner truth, bounded work, and assertion-heavy state transitions.

Compact anchor map:

- `howl-linux-host/src/event.zig:156-214,330-489`: host control-spine owner seam
- `howl-linux-host/src/terminal/surface.zig:394-420,519-680`: retained render/present seam
- `howl-linux-host/src/terminal/render_retained.zig:95-123,178-239`: retained present truth
- `howl-linux-host/src/display/present.zig:30-97`: host present token lifecycle
- `howl-linux-host/src/display/frame_timer.zig:16-141`: frame cadence owner
- `howl-linux-host/src/terminal/cursor_blink.zig:6-54`: local blink timing owner
- `utils/dev_references/terminals/alacritty/alacritty/src/event.rs:430-490`: reference event spine
- `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs:401-494`: reference dirty/draw owner

Ordered worker-ready cuts:

1. Cut 1: Make present lifecycle explicit and single-owned.
Allowed files:
- `howl-linux-host/src/display/present.zig`
- `howl-linux-host/src/display/frame_timer.zig`
- `howl-linux-host/src/event.zig`
- `howl-linux-host/src/display/display.zig`
Required shape:
- Replace the split submit/drain flow with one explicit host-present lifecycle API in `display/present.zig`.
- Name synchronous completion truth for the current SDL backend instead of pretending completion is deferred.
Exact tests:
- extend `display/present.zig` tests for terminal-frame, host-damage, and terminal-retire under synchronous completion
- extend `frame_timer.zig` tests for completion consequences
- add or update `display/display.zig` tests proving one completion token per submit
Non-goals:
- no benchmark tuning
- no renderer algorithm changes
- no VT behavior changes
Stop conditions:
- `event.zig` no longer owns present-token lifecycle branching
- same-turn synchronous completion is asserted and tested explicitly

2. Cut 2: Rebuild frame cadence around one explicit frame owner.
Allowed files:
- `howl-linux-host/src/display/frame_timer.zig`
- `howl-linux-host/src/event.zig`
- `howl-linux-host/src/display/present.zig`
Required shape:
- Turn `FrameTimer` into the sole frame-admission owner for wait, render permission, present permission, post-submit, and post-complete semantics.
Exact tests:
- host-damage submit
- terminal-frame submit
- terminal-retire no-submit
- completion before next deadline
- deadline release without completion
- redraw persistence across blocked permit
Non-goals:
- no terminal surface refactor yet
- no cursor policy change yet
Stop conditions:
- no frame-pacing policy branching remains in `event.zig` beyond calls into `FrameTimer`

3. Cut 3: Separate runtime admission from runtime drive for terminal surfaces.
Allowed files:
- `howl-linux-host/src/terminal/surface.zig`
- `howl-linux-host/src/event.zig`
- `howl-linux-host/src/terminal/pty_pump.zig`
- `howl-linux-host/src/terminal/vt_retained.zig`
Required shape:
- Split `Surface.driveProgress` into admission facts, bounded drive, and post-drive consequences.
Exact tests:
- inactive tab with no admission does not drive
- active tab with admitted input does drive
- continuation drives without new wake
- runtime due drives without new input
- cursor activity reset uses the passed `now_ns`
Non-goals:
- no render-turn changes yet
- no tab-management cleanup
Stop conditions:
- `event.zig` stops inferring drive policy from mixed booleans

4. Cut 4: Make retained render/present state explicit in `surface.zig`.
Allowed files:
- `howl-linux-host/src/terminal/surface.zig`
- `howl-linux-host/src/terminal/render_retained.zig`
- `howl-linux-host/src/terminal/surface_test.zig`
Required shape:
- Name the retained render state machine explicitly: idle, prepare-needed, submit-ready, present-in-flight, failed.
Exact tests:
- blocked present
- submit ready
- stale/failed upload
- rendered to in-flight to complete
Non-goals:
- no host event-loop redesign beyond adapting call sites
- no render ABI changes
Stop conditions:
- the retained state machine reads from one owner path without reconstructing it from scattered booleans

5. Cut 5: Restore cursor truth as a cadence concern.
Allowed files:
- `howl-linux-host/src/terminal/cursor_blink.zig`
- `howl-linux-host/src/terminal/surface.zig`
- `howl-linux-host/src/event.zig`
Required shape:
- Make the loop consume cursor wait/dirty facts instead of directly carrying cursor policy.
Exact tests:
- disabled animation forces visible
- deadline initialization without flicker
- focus loss disables animation and restores visible
- activity reset restores visible and refreshes deadline
Non-goals:
- no IME feature work
- no scheduler framework invention
Stop conditions:
- `event.zig` stops treating `syncCursorBlinkCadence` as policy logic

6. Cut 6: Unify loop wait admission over explicit owner facts.
Allowed files:
- `howl-linux-host/src/event.zig`
- `howl-linux-host/src/display/frame_timer.zig`
- `howl-linux-host/src/terminal/surface.zig`
- `howl-linux-host/src/event_loop.zig`
Required shape:
- Replace mixed `LoopDebugFacts` and manual min-wait merging with one explicit admission struct for owner work, runtime wake, cursor wait, runtime wait, and frame wait.
Exact tests:
- owner work prevents waiting
- runtime wake prevents waiting without granting render
- frame wait participates only through frame owner
- cursor wait participates in minimum wait
- terminal input admission clears only on successful drive
Non-goals:
- no generic manager type
- no thread model redesign
Stop conditions:
- loop wait policy is explainable from one struct and one function family

7. Cut 7: Add end-to-end stale-state latest-snapshot tests.
Allowed files:
- `howl-linux-host/src/event.zig`
- `howl-linux-host/src/display/present.zig`
- `howl-linux-host/src/terminal/surface_test.zig`
- `howl-linux-host/src/display/frame_timer.zig`
Required shape:
- Add tests proving that the control spine presents the latest available terminal snapshot and does not ACK or re-present stale state after a newer one exists.
- Include cursor visibility change in the proof surface.
Exact tests:
- rendered snapshot N submitted
- runtime advances to N+1 before next frame permit
- completion/retire path does not incorrectly ACK or re-present stale N as current truth
- cursor visibility change under cadence pressure lands in the latest rendered state
Non-goals:
- no benchmark harness work yet
- no micro-optimization
Stop conditions:
- at least one end-to-end proof covers wake, drive, render, present, complete, snapshot, token, and cursor assertions

Risks:

- The current SDL host is effectively synchronous present completion, so the API must name present truth without inventing fake async generality.
- `surface.zig` is already large, so refactoring must sharpen owners instead of merely moving code.
- Cleaning up same-turn completion handling can expose hidden assumptions in existing tests.

Proof gaps:

- No current test proves stale intermediate snapshot replay across multiple runtime updates before the next frame permit.
- No current test proves cursor visibility truth through retained render/present completion.
- Benchmark receipts for this section still need to be generated after planning.

Readiness judgment:

- Ready for reviewer pressure.
- This is a 7-cut section plan sized to the real owner boundary, not a fake narrow-cut queue.
