# Howl-Only Event Loop Inventory

## Receipt Header

- Artifact owner: `research/2026-06-15-howl-only-event-loop-inventory.md`
- Researcher role: active researcher for the cursor Kitty amended sprint
- Session id: no internal session identifier exposed beyond this task session
- Scope: inventory only; no code edits, no git, no rescope

## Summary

Howl currently carries several event-loop and control-spine ideas that do not map directly to the Alacritty reference shape. The main non-mapping areas are:

- merged wait/admission policy in `event.zig`
- frame-permit retry state in `frame_timer.zig`
- terminal present token ownership in `event.zig`
- PTY/runtime continuation state carried through `surface.zig`
- test-only control-spine helpers that encode the Howl shape rather than the reference shape
- startup redraw seeding in `main.zig` through input-owned persistence

The Alacritty reference instead centralizes follow-up timing in `display/mod.rs::FrameTimer`, processes scheduled wakeups through `scheduler.rs`, and consumes them from `event.rs` after event processing.

## Inventory

### 1. Merged wait/admission policy is Howl-only

- Howl shape:
  - `howl-linux-host/src/event.zig:67-89` (`LoopWaitAdmission`, `waitMsMerge3`)
  - `howl-linux-host/src/event.zig:91-94` (`LoopAdmission`)
  - `howl-linux-host/src/event.zig:217-250` (`computeLoopAdmission`, `loopWaitAdmission`, `computeLoopAdmissionWithOwnerWork`, `loopWaitAdmissionWithOwnerWork`)
  - `howl-linux-host/src/event.zig:295-300` (`pumpWindowEvents` consumes `wait_for_window` + `wait_ms`)
  - `howl-linux-host/src/event_loop.zig:67-107` (`pumpInput`, `waitAndDrainInputWith`, `drainPendingInputWith`)
- Alacritty counterpart:
  - `utils/dev_references/terminals/alacritty/alacritty/src/event.rs:471-489` updates control flow after event processing
  - `utils/dev_references/terminals/alacritty/alacritty/src/scheduler.rs:54-73` returns the next deadline or none
  - `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:1435-1457` schedules the next frame deadline
- Mapping verdict:
  - no direct Alacritty shape for a separate `LoopWaitAdmission` merge object or `waitMsMerge3`
  - Alacritty keeps one scheduler deadline source and one event-loop control-flow decision
- Removal vs retention:
  - remove or collapse the merged admission object; keep only a single wait deadline flowing from the frame/scheduler owner into the event loop
- User-facing risk if removed incorrectly:
  - can lose either PTY/runtime wake handling or frame follow-up wakeups and reintroduce starvation or busy polling
- Target owner boundary after removal:
  - `frame_timer.zig` owns finite follow-up wait truth
  - `event.zig` consumes that truth
  - `event_loop.zig` only blocks or polls on the already-computed deadline

### 2. Frame-permit retry state is Howl-only

- Howl shape:
  - `howl-linux-host/src/display/frame_timer.zig:17-26` (`FrameTimer` state)
  - `howl-linux-host/src/display/frame_timer.zig:46-78` (`refreshFramePermit`, `framePermitWaitMs`)
  - `howl-linux-host/src/display/frame_timer.zig:85-112` (`notePresentComplete`, `shouldWaitForWindow`, `renderPermission`, `terminalKeepWakePermission`)
  - `howl-linux-host/src/display/frame_timer.zig:114-145` (`admitPresentReason`, `notePresentSubmittedAtWithInterval`)
  - `howl-linux-host/src/display/frame_timer.zig:147-165` (`nextFrameDeadlineNs`)
- Alacritty counterpart:
  - `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:1556-1600` `FrameTimer::compute_timeout`
  - `utils/dev_references/terminals/alacritty/alacritty/src/window.rs:104-125` `Window::has_frame` / `requested_redraw`
  - `utils/dev_references/terminals/alacritty/alacritty/src/window.rs:259-264` `request_redraw`
- Mapping verdict:
  - Alacritty has a frame timer and redraw request state, but not Howl's pending-completion retry state (`frame_deadline_reached_while_pending`) or separate `terminalKeepWakePermission`
- Removal vs retention:
  - remove the extra retry state if it is only serving to mask the starvation case
  - retain the minimal deadline computation itself
- User-facing risk if removed incorrectly:
  - could drop the finite follow-up wake needed after a submitted terminal frame, causing the real repro to stall again
- Target owner boundary after removal:
  - `frame_timer.zig` owns the single finite follow-up deadline
  - `present.zig` only reports submit/complete consequences
  - `event.zig` only consumes `wait_ms`

### 3. Terminal present token ownership in `event.zig` is Howl-only

- Howl shape:
  - `howl-linux-host/src/event.zig:29-31` (`pending_terminal_present` on the processor)
  - `howl-linux-host/src/event.zig:472-484` (`submitPresent` calls present lifecycle and returns submission)
  - `howl-linux-host/src/display/present.zig:93-142` (`recordSubmissionFor`, `drainReadyCompletion`)
  - `howl-linux-host/src/display/present.zig:148-164` (`noteFramePacingPresentComplete`, `noteFramePacingRenderSubmitted`)
- Alacritty counterpart:
  - no direct terminal-present token ownership in the reference event loop
  - closest surface-level mapping is `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:803-827` (terminal damage becomes frame damage) and `:1435-1457` (frame request scheduling)
- Mapping verdict:
  - no direct Alacritty equivalent for a processor-owned `pending_terminal_present` token and matched completion drain path
  - the token lifecycle is a Howl host-present concept, not an event-loop concept in the reference
- Removal vs retention:
  - remove duplicated ownership from `event.zig` if the token can live only in `present.zig`/`display.zig`
  - retain the lifecycle concept, but keep it at the present/display owner boundary
- User-facing risk if removed incorrectly:
  - can break completion matching for in-flight terminal presents and lose the ability to retire stale terminal frames
- Target owner boundary after removal:
  - `display/present.zig` and `display/display.zig` own present token lifecycle
  - `event.zig` should only observe the result and continue the loop

### 4. PTY/runtime continuation state in `surface.zig` is Howl-only

- Howl shape:
  - `howl-linux-host/src/terminal/surface.zig:445-457` (`progressContinuationPending`, `runtimeFacts`)
  - `howl-linux-host/src/terminal/surface.zig:460-474` (`driveProgress`, `driveProgressWithFacts`)
  - `howl-linux-host/src/terminal/surface.zig:491-508` (`notePresentSubmitted`, `completePresent`, `noteRenderTurn`)
  - `howl-linux-host/src/terminal/surface.zig:693-728` (`wakePendingHooked`, `runtimeObligationDueNowHooked`, `driveOnceHooked`, `driveProgressBounded`, `driveProgressConsequences`)
- Alacritty counterpart:
  - `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs:365-398` redraws the window and processes display updates
  - `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs:400-479` handles event processing and staged updates
  - `utils/dev_references/terminals/alacritty/alacritty/src/event.rs:471-489` schedules the next loop turn after event handling
- Mapping verdict:
  - there is no direct Alacritty equivalent to a surface-owned `progress_continuation_pending` bit or the `runtimeFacts`/`driveProgress` split
  - Alacritty keeps terminal update handling inside event processing and display draw, not as a surface-owned wake contract
- Removal vs retention:
  - remove or narrow any Howl-only continuation state that is only being used to imitate a scheduler
  - retain surface ownership of terminal runtime work only if it remains the true PTY/terminal owner, not the event-loop owner
- User-facing risk if removed incorrectly:
  - can drop PTY progress or input-admission behavior and stop terminal output from advancing at all
- Target owner boundary after removal:
  - terminal progress stays in the terminal/PTY owner (`surface.zig` / PTY owner)
  - event-loop code should only observe a wake/wait deadline and render admission

### 5. Test-only control-spine helpers are Howl-only proof shape

- Howl shape:
  - `howl-linux-host/src/event.zig:610-651` (`testing.ControlSpineRuntimeFacts`, `testing.PresentPlanningInput`, `computeLoopAdmissionThroughControlSpine`, `derivePresentReasonThroughControlSpine`)
  - `howl-linux-host/src/event.zig:789-865` and `howl-linux-host/src/display/frame_timer.zig:386-443` control-spine tests that encode the current policy
  - `howl-linux-host/src/terminal/surface_test.zig:1467-1518` host wake / frame resync test shape
- Alacritty counterpart:
  - no direct counterpart; Alacritty does not expose these helper seams in its runtime architecture
- Mapping verdict:
  - proof-only, not product architecture
- Removal vs retention:
  - retain as proof surfaces until the worker has replaced the underlying runtime shape
  - do not promote them into runtime architecture
- User-facing risk if removed incorrectly:
  - only proof loss, but that can hide regressions while the runtime shape is still wrong
- Target owner boundary after removal:
  - runtime code stays in `event.zig`, `frame_timer.zig`, `present.zig`, and the terminal owner
  - tests remain in their curated host test roots

### 6. Startup redraw seeding in `main.zig` is Howl-only

- Howl shape:
  - `howl-linux-host/src/main.zig:124-128` (`initInput` calls `input.requestRedraw()` during bootstrap)
  - `howl-linux-host/src/input/input.zig:97-104` (`redraw_requested` lives on `Input`)
  - `howl-linux-host/src/input/input.zig:148-152` (`drainRedrawRequested` consumes the bit)
  - `howl-linux-host/src/input/input.zig:202-204` (`requestRedraw` mutates the input-owned bit)
  - `howl-linux-host/src/input/input.zig:214-223` (`processEvent` sets the same bit for focus/expose)
- Alacritty counterpart:
  - `utils/dev_references/terminals/alacritty/alacritty/src/display/window.rs:104-125` keeps redraw-request state on the window owner
  - `utils/dev_references/terminals/alacritty/alacritty/src/display/window.rs:259-264` exposes `request_redraw()` on the window owner
  - `utils/dev_references/terminals/alacritty/alacritty/src/event.rs:409-415` and `:443-449` set dirty/frame state, then request redraw from the window owner
- Mapping verdict:
  - no direct Alacritty equivalent for seeding startup redraw through `Input`
  - the reference keeps redraw ownership at the window/display owner boundary, not in bootstrap input initialization
- Removal vs retention:
  - remove the startup call from `main.zig`
  - if the application still needs a first redraw, seed it through the window owner or through the first event-driven draw path, not through input persistence
- User-facing risk if removed incorrectly:
  - the app may boot without an initial draw if no replacement redraw seed exists
- Target owner boundary after removal:
  - persistent redraw request state belongs to `display/window.zig`
  - `main.zig` should only bootstrap owners, not own redraw policy

## Exact Alacritty Shape To Keep

The reference shape to preserve is:

- event processing finishes first
- the scheduler is updated after event handling
- the next control-flow wait is derived from the scheduler deadline
- redraw request state lives in the window/display owner, not in the event processor

Source pressure:

- `utils/dev_references/terminals/alacritty/alacritty/src/event.rs:471-489`
- `utils/dev_references/terminals/alacritty/alacritty/src/scheduler.rs:54-73`
- `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:1435-1457`
- `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:1556-1600`
- `utils/dev_references/terminals/alacritty/alacritty/src/display/window.rs:104-125`
- `utils/dev_references/terminals/alacritty/alacritty/src/display/window.rs:259-264`
