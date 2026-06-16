# Alacritty Event Loop Port Plan

## Receipt Header

- Artifact owner: `research/2026-06-15-alacritty-event-loop-tigerbeetle-port-plan.md`
- Researcher role: active researcher for the cursor Kitty amended sprint
- Session id: no internal session identifier exposed beyond this task session
- Scope: research/planning only; no code edits, no git

## What The Port Must Do

- Remove the Howl-only event-loop shape that does not map directly to Alacritty.
- Clone the Alacritty event-loop shape directly, but keep TigerBeetle discipline: explicit owners, bounded state, narrow functions, assertions, no hidden policy layers.
- Do not create a new `scheduler` owner file in Howl. The cloned shape must live in the existing owners.

## Inventory-Backed Removal List

### 1. Remove merged wait/admission policy from `event.zig`

- Howl-only shape:
  - `howl-linux-host/src/event.zig:67-89` (`LoopWaitAdmission`, `waitMsMerge3`)
  - `howl-linux-host/src/event.zig:91-94` (`LoopAdmission`)
  - `howl-linux-host/src/event.zig:217-250` (`computeLoopAdmission`, `loopWaitAdmission`, `computeLoopAdmissionWithOwnerWork`, `loopWaitAdmissionWithOwnerWork`)
- Alacritty mapping:
  - `utils/dev_references/terminals/alacritty/alacritty/src/event.rs:471-489` updates control flow after event processing
  - `utils/dev_references/terminals/alacritty/alacritty/src/scheduler.rs:54-73` returns the next deadline or none
  - `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:1435-1457` schedules the next frame deadline
- Remove vs clone:
  - remove the merge object and the three-way wait combiner
  - clone the single-deadline control shape: event processing first, then one owner-derived wait decision
- User-facing risk:
  - if this is removed without replacing it with a single deadline source, PTY wakes or frame follow-up wakes can be lost and the real repro stalls again

### 2. Remove frame-permit retry state from `frame_timer.zig`

- Howl-only shape:
  - `howl-linux-host/src/display/frame_timer.zig:17-26` (`FrameTimer` fields)
  - `howl-linux-host/src/display/frame_timer.zig:46-78` (`refreshFramePermit`, `framePermitWaitMs`)
  - `howl-linux-host/src/display/frame_timer.zig:85-145` (`notePresentComplete`, `shouldWaitForWindow`, `renderPermission`, `terminalKeepWakePermission`, `admitPresentReason`, `notePresentSubmittedAtWithInterval`)
  - `howl-linux-host/src/display/frame_timer.zig:147-165` (`nextFrameDeadlineNs`)
- Alacritty mapping:
  - `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:1556-1600` `FrameTimer::compute_timeout`
  - `utils/dev_references/terminals/alacritty/alacritty/src/display/window.rs:104-125` `has_frame`
  - `utils/dev_references/terminals/alacritty/alacritty/src/display/window.rs:259-264` `request_redraw`
- Remove vs clone:
  - remove the extra retry state used to mask starvation (`frame_deadline_reached_while_pending`, `terminalKeepWakePermission`)
  - clone the simple finite deadline computation and keep it owner-local
- User-facing risk:
  - removing the retry state too aggressively can restore the timeout stall; the replacement must still produce a finite follow-up wake

### 3. Remove processor-owned terminal-present token state from `event.zig`

- Howl-only shape:
  - `howl-linux-host/src/event.zig:29-31` (`pending_terminal_present`)
  - `howl-linux-host/src/event.zig:472-484` (`submitPresent`)
- Alacritty mapping:
  - no direct event-loop owner for a pending terminal present token
  - closest pressure is the display/window owner pairing in `display/mod.rs:803-827`, `display/window.rs:104-125`, and `window_context.rs:365-398`
- Remove vs clone:
  - remove duplicated ownership from the processor
  - keep present token lifecycle in `display/present.zig` / display owner boundary only
- User-facing risk:
  - if token ownership is removed without preserving lifecycle ownership, stale-completion retirement breaks

### 4. Remove surface-owned continuation state from `surface.zig`

- Howl-only shape:
  - `howl-linux-host/src/terminal/surface.zig:445-457` (`progressContinuationPending`, `runtimeFacts`)
  - `howl-linux-host/src/terminal/surface.zig:460-474` (`driveProgress`, `driveProgressWithFacts`)
  - `howl-linux-host/src/terminal/surface.zig:491-508` (`notePresentSubmitted`, `completePresent`, `noteRenderTurn`)
  - `howl-linux-host/src/terminal/surface.zig:693-728` (`wakePendingHooked`, `runtimeObligationDueNowHooked`, `driveOnceHooked`, `driveProgressBounded`, `driveProgressConsequences`)
- Alacritty mapping:
  - `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs:365-398` draw path
  - `utils/dev_references/terminals/alacritty/alacritty/src/event.rs:471-489` event processing and next-turn control flow
- Remove vs clone:
  - remove surface-owned scheduler imitation
  - keep surface as the PTY/terminal owner, not an event-loop owner
- User-facing risk:
  - if surface continuation is removed without preserving PTY progress ownership, terminal output can stop advancing entirely

### 5. Remove input-owned redraw persistence and move it to the window owner

- Howl-only shape:
  - `howl-linux-host/src/main.zig:124-128` (`initInput` seeds redraw via `input.requestRedraw()`)
  - `howl-linux-host/src/input/input.zig:97-97` (`redraw_requested` field)
  - `howl-linux-host/src/input/input.zig:148-150` (`drainRedrawRequested`)
  - `howl-linux-host/src/input/input.zig:202-204` (`requestRedraw`)
  - `howl-linux-host/src/input/input.zig:214-223` (`processEvent` sets the same bit for focus/expose)
- Alacritty mapping:
  - `utils/dev_references/terminals/alacritty/alacritty/src/display/window.rs:104-125` `requested_redraw` lives on `Window`
  - `utils/dev_references/terminals/alacritty/alacritty/src/display/window.rs:259-264` `request_redraw()` is a window-owned mutation
  - `utils/dev_references/terminals/alacritty/alacritty/src/event.rs:409-415` and `:443-449` set dirty/frame state and request redraw from the window owner
- Remove vs clone:
  - remove redraw persistence from `input`
  - remove the bootstrap seed from `main.zig`
  - clone the persistent redraw bit into `display/window.zig`, not into a new scheduler layer
- User-facing risk:
  - moving redraw ownership incorrectly can drop expose/focus redraws or create duplicate redraw churn

## Exact Alacritty Concepts To Clone

- Clone the ordering rule: process events first, then update scheduling, then derive control flow.
- Clone the single future-deadline rule: one owner computes the next timeout, and the event loop consumes it.
- Clone the window-owned redraw bit: redraw request state belongs to the window/display owner, not to input or the event processor.
- Clone the draw-path discipline: display draw handles renderer updates and requests redraws when animation or pending visual work still exists.

Reference pressure:

- `utils/dev_references/terminals/alacritty/alacritty/src/event.rs:471-489`
- `utils/dev_references/terminals/alacritty/alacritty/src/scheduler.rs:54-73`
- `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:1435-1457`
- `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:1556-1600`
- `utils/dev_references/terminals/alacritty/alacritty/src/display/window.rs:104-125`
- `utils/dev_references/terminals/alacritty/alacritty/src/display/window.rs:259-264`
- `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs:365-398`

## Exact Howl Owner Boundary After Removal

- `howl-linux-host/src/display/frame_timer.zig`
  - owns the finite next wake deadline and the admit/non-admit frame timing truth
- `howl-linux-host/src/event.zig`
  - owns the one-turn control spine and consumes the deadline through existing wait admission only
- `howl-linux-host/src/display/present.zig`
  - remains lifecycle-only for submit/complete consequences
- `howl-linux-host/src/display/window.zig`
  - should own persistent redraw-request state if that bit remains needed after the port
- `howl-linux-host/src/input/input.zig`
  - becomes input parsing and ephemeral intent only; it should not own redraw policy state
- `howl-linux-host/src/terminal/surface.zig`
  - remains the PTY/terminal owner; it must not carry event-loop continuation policy
- `howl-linux-host/src/event_loop.zig`
  - remains an SDL wait/poll adapter only; no policy layer should be added here

## Exact Files To Change In The Next Subsprint

- `howl-linux-host/src/display/frame_timer.zig`
- `howl-linux-host/src/event.zig`
- `howl-linux-host/src/display/present.zig`
- `howl-linux-host/src/display/window.zig`
- `howl-linux-host/src/input/input.zig`
- `howl-linux-host/src/main.zig`
- `howl-linux-host/src/terminal/surface.zig`
- `howl-linux-host/src/terminal/surface_test.zig`

Retention-only files for this subsprint:

- `howl-linux-host/src/event_loop.zig`
- `howl-linux-host/src/main.zig` (bootstrap-only proof root for redraw seed removal)

## Exact Code-Shape Constraints Under TigerBeetle Discipline

- Do not introduce a new `scheduler`, `manager`, `controller`, or `utils` owner.
- Keep the control spine explicit and single-owner.
- Use simple control flow and explicit assertions at the state boundaries.
- Keep deadlines in explicit `u64`/`u32` fields and avoid hidden `usize`-based timing state.
- Keep functions small and direct; split branches upward, keep leaf helpers pure.
- Pair assertions on positive and negative space:
  - if the loop waits, there must be a concrete owner-derived deadline
  - if the loop does not wait, the reason must be explicit
- Keep `present.zig` lifecycle-only; it may report completion consequences, but it must not own policy.
- Keep `event_loop.zig` as a dumb SDL adapter: no merged scheduling logic, no redraw policy, no present policy.

## Exact Proof Roots

- `howl-linux-host/src/display/frame_timer.zig`
- `howl-linux-host/src/event.zig`
- `howl-linux-host/src/display/present.zig`
- `howl-linux-host/src/display/window.zig`
- `howl-linux-host/src/input/input.zig`
- `howl-linux-host/src/main.zig`
- `howl-linux-host/src/terminal/surface.zig`
- `howl-linux-host/src/terminal/surface_test.zig`
- `howl-linux-host/src/event_loop.zig` (retention-only proof root)

## Verification Commands

- Build first, then run the real repro directly under timeout:
  - `zig build -Doptimize=ReleaseFast`
  - `timeout 0.8 zig build run -Doptimize=ReleaseFast -- --command rain`
- Host unit tests:
  - `timeout 300s zig build test:unit` in `howl-linux-host`

## Exact Stop Conditions

- Stop if the fix requires a new scheduler/manager layer.
- Stop if the fix requires `surface.zig` to become an event-loop policy owner.
- Stop if the fix requires `event_loop.zig` to become more than an SDL wait/poll adapter.
- Stop if cursor-only redraw ownership reappears.
- Stop if the real repro is still being addressed only by rewriting tests.
- Stop if the worker cannot prove the exact wake-to-follow-up-to-next-turn sequence on the real repro.

## Smallest Worker-Ready Slice Wording

- Slice name: `host-alacritty-event-loop-clone`
- Slice class: narrow host control-spine port inside the current cursor sprint
- Exact goal:
  - Port the Alacritty event-loop shape into Howl with TigerBeetle discipline: event processing first, one owner-derived deadline, window-owned redraw request state, and lifecycle-only present handling.
  - Remove Howl-only merged wait/admission logic, surface continuation ownership, and input-owned redraw persistence.
- Exact files allowed:
  - `howl-linux-host/src/display/frame_timer.zig`
  - `howl-linux-host/src/event.zig`
  - `howl-linux-host/src/display/present.zig`
  - `howl-linux-host/src/display/window.zig`
  - `howl-linux-host/src/input/input.zig`
  - `howl-linux-host/src/terminal/surface.zig`
  - `howl-linux-host/src/terminal/surface_test.zig`
- Exact required shape:
  - clone Alacritty's post-event scheduling order instead of keeping Howl's merged wait/admission policy
  - move persistent redraw request ownership to the window owner
  - keep present handling lifecycle-only
  - keep the event loop adapter thin and policy-free
  - do not add a new owner layer
- Exact proof roots:
  - `howl-linux-host/src/display/frame_timer.zig`
  - `howl-linux-host/src/event.zig`
  - `howl-linux-host/src/display/present.zig`
  - `howl-linux-host/src/display/window.zig`
  - `howl-linux-host/src/input/input.zig`
  - `howl-linux-host/src/terminal/surface.zig`
  - `howl-linux-host/src/terminal/surface_test.zig`
- Verification commands:
  - `zig build -Doptimize=ReleaseFast`
  - `timeout 0.8 zig build run -Doptimize=ReleaseFast -- --command rain`
  - `timeout 300s zig build test:unit` in `howl-linux-host`
- Exact stop conditions:
  - stop if the worker invents a Howl-only scheduler/manager layer
  - stop if `present.zig` starts owning policy
  - stop if `surface.zig` becomes the event-loop owner
  - stop if redraw request ownership stays in `input`
  - stop if the real repro still needs test rewriting instead of the ported runtime shape
