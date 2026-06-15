# Host Wake Present Starvation Frame Resync

## Receipt Header

- Artifact owner: `research/2026-06-15-host-wake-present-starvation-frame-resync.md`
- Researcher role: active researcher for the cursor Kitty amended sprint
- Session id: no internal session identifier exposed beyond this task session
- Scope: narrow host regression fix for the real repro; no product rescope

## Exact Bug Statement

- Real repro command: `timeout 0.8 zig build run -Doptimize=ReleaseFast -- --command rain`
- The binary must be built first, then run directly under timeout.
- The workspace successfully used the installed harness artifact from `howl-linux-host/build.zig`.
- The real repro still shows repeated `wake_push_ns=... event_type=32768`, a `host_damage` present with `matched_terminal_present=false`, and terminal frames that stop advancing autonomously.
- The first terminal frame submits and matches correctly, then a follow-up `host_damage` submit appears unmatched, PTY wakes continue, and terminal progress still stalls before timeout expires.

## Exact Classification Receipt

- Classification: `frame-permit policy bug`
- Mixed rationale:
  - introduced receipt:
    - the host already had a frame-permit/present-followup policy defect before the current repair attempt.
    - evidence:
      - `howl-linux-host/src/display/frame_timer.zig:46-77`
      - `howl-linux-host/src/display/frame_timer.zig:85-92`
      - `howl-linux-host/src/display/frame_timer.zig:114-145`
  - uncovered receipt:
    - the current host scheduling attempt removed a masking cursor-driven redraw path, which exposed the existing frame-resync failure under the real repro.
    - evidence:
      - `howl-linux-host/src/event.zig:187-218`
      - `howl-linux-host/src/event.zig:472-484`
      - `howl-linux-host/src/display/present.zig:53-63`
      - `howl-linux-host/src/display/present.zig:124-143`

## Exact Real Repro Proof Obligation

- Build first.
- Run the built harness directly under timeout.
- Observe the first terminal frame submit and match correctly.
- Observe a follow-up `host_damage` completion that is unmatched.
- Observe repeated PTY wakes continue.
- Observe terminal frames still do not advance autonomously through the rest of the timeout.

## Exact Alacritty Source Pressure

- Winning pressure point: `utils/dev_references/terminals/alacritty/alacritty/src/event.rs`
- Supporting pressure point: `utils/dev_references/terminals/alacritty/alacritty/src/scheduler.rs`
- Secondary supporting pressure: `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs`
- Supporting display pressure: `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs`
- Supporting window pressure: `utils/dev_references/terminals/alacritty/alacritty/src/display/window.rs`
- Why `event.rs` wins:
  - the failure is a control-spine scheduling problem, not a renderer primitive problem.
  - Alacritty centralizes terminal progress, redraw admission, and timed follow-up wakeups in the event/scheduler spine.
  - `scheduler.rs` provides the timed follow-up shape, while `event.rs` owns the loop policy that consumes it.
  - the real repro needs that same event/scheduler shape, not a cursor-local workaround and not a new Howl runtime layer.
  - the unmatched `host_damage` path points to a missing frame-resync policy around follow-up scheduling, not to a `surface.zig` consumer fix.

## Exact Owner Map For The Fix

- `howl-linux-host/src/display/frame_timer.zig`
  - owner of frame-permit truth and finite follow-up policy.
  - exact contract change:
    - once a terminal frame or terminal-present consequence still requires another owner-centralized loop turn, `framePermitWaitMs(now_ns)` must return a finite delay.
    - `frame_timer.zig` must own the rule that prevents `wait_for_window = true` from degenerating into an indefinite sleep during the real repro.
    - the follow-up policy must stay in frame pacing, not in cursor logic.
  - exact methods in scope:
    - `refreshFramePermit`
    - `framePermitWaitMs`
    - `notePresentSubmittedAtWithInterval`
    - `notePresentComplete`
- `howl-linux-host/src/event.zig`
  - owner of loop admission and wait-vs-poll choice.
  - exact contract change:
    - consume the repaired finite follow-up wait through the existing `LoopAdmission.wait_ms` path only.
    - keep the event processor as the consumer of frame-timer truth; do not add a new wake source or cursor-owned redraw state.
  - exact methods in scope:
    - `computeLoopAdmission`
    - `loopWaitAdmission`
    - `runLoopTurn`
    - `submitPresent`
- `howl-linux-host/src/display/present.zig`
  - owner of terminal-present submission/completion lifecycle.
  - exact contract constraint:
    - remain lifecycle-only.
    - translate submit/complete consequences back into frame pacing only; do not add independent retry or wake policy.
  - exact methods in scope:
    - `submit`
    - `drain`
    - `noteFramePacingRenderSubmitted`
    - `noteFramePacingPresentComplete`
- `howl-linux-host/src/terminal/surface_test.zig`
  - proof-only root for the real repro sequence.
  - must prove the wake/present progression without cursor masking.

## Exact Files For The Subsprint

- `howl-linux-host/src/display/frame_timer.zig`
- `howl-linux-host/src/event.zig`
- `howl-linux-host/src/display/present.zig`
- `howl-linux-host/src/terminal/surface_test.zig`

Forbidden file changes for this subsprint:

- `howl-linux-host/src/terminal/surface.zig`
- `howl-linux-host/src/event_loop.zig`

## Exact Code-Shape Constraints

- `frame_timer.zig` owns the finite follow-up policy.
- `event.zig` consumes it through the existing `wait_ms` admission only.
- `present.zig` remains lifecycle-only.
- No cursor-mask workaround.
- No new runtime, scheduler, manager, controller, or umbrella owner.
- No `surface.zig` changes.
- No `event_loop.zig` changes.
- The fix must preserve the real repro shape: a submitted terminal frame, then unmatched `host_damage`, then continued PTY wakes, then autonomous terminal progression without external input.

## Exact Proof Roots

- `howl-linux-host/src/display/frame_timer.zig`
- `howl-linux-host/src/event.zig`
- `howl-linux-host/src/display/present.zig`
- `howl-linux-host/src/terminal/surface_test.zig`

## Verification Commands

- Build first, then run the built harness directly under timeout:
  - `zig build -Doptimize=ReleaseFast`
  - `timeout 0.8 zig build run -Doptimize=ReleaseFast -- --command rain`
- Host unit tests after the real repro:
  - `timeout 300s zig build test:unit` in `howl-linux-host`

## Exact Stop Conditions

- Stop if the fix requires `surface.zig`.
- Stop if the fix requires `event_loop.zig`.
- Stop if the real repro is still being addressed by test rewriting instead of the host scheduling contract.
- Stop if cursor-only redraw ownership reappears.
- Stop if the loop can still stall terminal-frame progression until unrelated external input.

## Smallest Worker-Ready Slice Wording

- Slice name: `host-wake-present-starvation-frame-resync`
- Slice class: narrow host regression fix for the real repro inside the current cursor sprint
- Exact goal:
  - Fix the host wake/present frame-resync regression where the real repro shows a first matched terminal frame, then an unmatched `host_damage`, continued PTY wakes, and no autonomous terminal progression through the rest of the timeout.
  - Repair the centralized frame-pacing and loop-admission seam without reintroducing deleted cursor-event ownership.
- Exact files allowed:
  - `howl-linux-host/src/display/frame_timer.zig`
  - `howl-linux-host/src/event.zig`
  - `howl-linux-host/src/display/present.zig`
  - `howl-linux-host/src/terminal/surface_test.zig`
- Exact required shape:
  - make `frame_timer.zig` return a finite follow-up wait through the existing `wait_ms` seam whenever terminal or present progression still requires another loop turn
  - keep `event.zig` as the consumer of that wait policy only
  - keep `present.zig` lifecycle-only
  - do not change `surface.zig`
  - do not change `event_loop.zig`
  - do not restore cursor-driven redraw state to the event processor
- Exact proof roots:
  - `howl-linux-host/src/display/frame_timer.zig`
  - `howl-linux-host/src/event.zig`
  - `howl-linux-host/src/display/present.zig`
  - `howl-linux-host/src/terminal/surface_test.zig`
- Verification command:
  - `timeout 300s zig build test:unit` in `howl-linux-host`
- Exact stop conditions:
  - stop if the fix masks the issue through cursor-only redraw ownership
  - stop if the real repro still stalls terminal progress until user input
  - stop if the diff invents a Howl-only runtime layer instead of following Alacritty event/scheduler pressure
  - stop if the diff changes `surface.zig`
  - stop if the diff changes `event_loop.zig`

## Open Risks

- The existing frame-timer tests may encode the pre-fix blocked contract and need careful revision.
- The real repro includes an unmatched `host_damage` present, so proof must cover both follow-up timing and present-state consequences.

## Proof Gaps

- The current test suite still needs an explicit end-to-end proof of the real repro sequence:
  1. build first
  2. run the built harness under timeout
  3. first terminal frame submits and matches correctly
  4. follow-up `host_damage` completion appears unmatched
  5. repeated PTY wakes continue
  6. terminal frames still do not advance autonomously through the rest of the timeout
