# Host Alacritty Gap Scratchpad

Owner: workspace root.

Purpose:

- turn `research.txt` into promotable worker-driving host slices
- record reference-derived answers with exact offending symbols, target symbols, and regression locks
- drive host cleanup toward a clearer Alacritty-like runtime shape

Reference source order used:

1. Ghostty
2. Alacritty
3. TigerBeetle
4. Kitty docs only for behavior facts

## Point 1: Wake, Redraw, And Present Policy Are Too Entangled

Status: ready to promote.

### Current state and offending code

- `howl-linux-host/src/input/input.zig:182-190`
  - `Input.hasPendingLoopWork()` mixes queued input with redraw state.
- `howl-linux-host/src/main.zig:79-102`
  - `LoopPending` and `LoopState.finish()` collapse admission, redraw, render, and present.
- `howl-linux-host/src/main.zig:258-290`
  - `runLoopTurn()` owns too many policy categories in one unnamed blob.
- `howl-linux-host/src/main.zig:394-404`
  - `driveTerminalProgress()` converts `Outcome.keep` into `input.requestRedraw()`.
- `howl-linux-host/src/input/window.zig:57-62`
  - redraw is pushed as a custom SDL event, physically coupling redraw to wake/event plumbing.

### What references say it should be

- Alacritty keeps wake, dirty, frame availability, and redraw request separate.
  - `[A:event.rs:409-449]`
  - `[A:window_context.rs:400-494]`
  - `[A:scheduler.rs:24-33,54-76]`
  - `[A:display/window.rs:103-112,260-264]`
  - `[A:display/mod.rs:1019-1046,1434-1458]`
- Ghostty keeps redraw as an explicit mailbox/render action, not a surrogate wake bit.
  - `[G:App.zig:126-132,237-289]`
  - `[G:renderer/Thread.zig:492-510]`
- TigerBeetle requires explicit control flow and separated state transitions.
  - `[T:TIGER_STYLE.md:166-183]`

### Exactly what must change

- In `howl-linux-host/src/input/input.zig`
  - rename `hasPendingLoopWork()` to `hasPendingOwnerWork()`
  - remove `self.redraw_requested`
  - remove `self.window_state.redrawRequested()`
  - new meaning: queued input, binding actions, geometry change, focus change only
- In `howl-linux-host/src/main.zig`
  - replace `LoopPending` fields with exactly:
    - `owner_work: bool`
    - `runtime_wake: bool`
    - `frame_work: bool`
  - delete current `LoopState.finish()`
  - replace with explicit booleans in `runLoopTurn()`:
    - `host_redraw`
    - `terminal_redraw`
    - `needs_render_turn`
  - `collectLoopPending()` must populate:
    - `owner_work = app.input.hasPendingOwnerWork()`
    - `runtime_wake = tabsHavePendingWake(...) or tabsHavePendingRuntimeObligation(...)`
    - `frame_work = activeTabNeedsRenderTurn(...)`
- In `howl-linux-host/src/main.zig:394-404`
  - change `driveTerminalProgress()` return type from `bool` to a struct:
    - `should_redraw: bool`
    - `keep_running: bool`
  - remove `input.requestRedraw()` from this function
  - runtime keepalive must remain wake/admission only

### How to lock it in

- `input/input.zig` tests:
  - redraw-only pending does not count as `hasPendingOwnerWork()`
  - queued input/focus/geometry/binding does count
- `main.zig` tests:
  - redraw does not participate in wait admission
  - runtime wake does participate in wait admission
  - frame work does participate in wait admission
  - runtime `keep_running` does not synthesize redraw

## Point 2: Present Cadence Is Not First-Class Enough

Status: ready to promote.

### Current state and offending code

- `howl-linux-host/src/main.zig:471-489`
  - `shouldPresent(step, chrome_present)` hides host cadence policy in a helper.
- `howl-linux-host/src/main.zig:85-101`
  - `LoopState.chrome_present` is a loop-local bool, not a host presentation contract.
- `howl-linux-host/src/terminal/terminal_panel.zig:995-1000`
  - terminal render submit starts present state.
- `howl-linux-host/src/main.zig:471-481`
  - `window.present(...)` and `tab.finishPresent()` are collapsed into one call site.

### What references say it should be

- Alacritty has explicit host frame cadence primitives.
  - `[A:scheduler.rs:24-33,54-76]`
  - `[A:event.rs:442-449]`
  - `[A:display/window.rs:103-112,260-264]`
  - `[A:display/mod.rs:1019-1046,1434-1458,1557-1600]`
- Ghostty separates render from present actions.
  - `[G:renderer/Thread.zig:19-20,54-72,492-510]`
  - `[G:App.zig:237-289]`
- TigerBeetle wants explicit state machines, not booleans carrying hidden lifecycle policy.
  - `[T:TIGER_STYLE.md:96-124,166-183]`

### Exactly what must change

- In `howl-linux-host/src/main.zig`
  - delete `LoopState.chrome_present`
  - delete `shouldPresent`
  - add exactly:
    - `const PresentReason = enum { none, host_damage, terminal_frame, terminal_retire };`
    - `const PresentPlan = struct { reason: PresentReason, needs_render_turn: bool };`
  - add `fn derivePresentReason(host_redraw: bool, step: TerminalPanel.TurnStep) PresentReason`
  - `presentRenderFrame(...)` must switch on `PresentReason`
    - `.none`: no present, no terminal completion
    - `.host_damage`: present, no `tab.finishPresent()`
    - `.terminal_frame`: present, then `tab.finishPresent()`
    - `.terminal_retire`: present, then `tab.finishPresent()`
- `TerminalPanel.TurnStep` remains terminal/render-owned fact
- host must own present cadence policy in `main.zig`, not in `TerminalPanel` or `window/present.zig`

### How to lock it in

- `main.zig` tests for `derivePresentReason()` matrix
- fake-window/fake-tab test proving:
  - `.host_damage` does not call `finishPresent()`
  - `.terminal_frame` does
  - `.terminal_retire` does
  - `.none` does neither
- retained/present state tests ensuring host-only redraw does not consume terminal present state

## Point 3: runLoopTurn Carries Too Much Implicit Policy

Status: ready to promote.

### Current state and offending code

- `howl-linux-host/src/main.zig:258-289`
  - `runLoopTurn()` mixes admission, host mutation, runtime progress, render, present, and present completion.
- `howl-linux-host/src/main.zig:394-404`
  - runtime keepalive becomes redraw request.
- `howl-linux-host/src/main.zig:98-101`
  - one drained redraw bit stands in for host damage, non-blocking turn, render decision, and present intent.

### What references say it should be

- Ghostty app tick drains explicit mailbox kinds and maps them to explicit runtime actions.
  - `[G:App.zig:126-132,237-289]`
  - `[G:termio/stream_handler.zig:101-106,125-172]`
- Alacritty keeps PTY wakeup, dirtying, redraw request, and draw separate.
  - `[A:event_loop.rs:165-168,244-247,265-270]`
  - `[A:event.rs:409-415,442-449]`
  - `[A:window_context.rs:400-493]`
- TigerBeetle says control flow should be explicit and centralized.
  - `[T:TIGER_STYLE.md:90-100,161-184,249-254]`

### Exactly what must change

- In `howl-linux-host/src/main.zig`
  - split `runLoopTurn()` into explicit internal phases:
    - compute admission
    - pump window events
    - apply host-owned mutations
    - drive runtime progress
    - derive redraw/render intent
    - render
    - derive present intent
    - complete present
- `driveTerminalProgress()` must return:
  - `should_redraw: bool`
  - `keep_running: bool`
- `keep_running` must suppress blocking only
- `app.input.drainRedrawRequested()` must feed only host redraw intent
- present completion must be named explicitly in host code, not buried in generic render flow

### How to lock it in

- `main.zig` tests proving:
  - `keep_running=true, should_redraw=false` keeps host non-blocking without redraw/present
  - `host_redraw_requested=true` can produce host-only present
  - `render_work_pending=true` produces render without host redraw bit
  - present completion only happens after present submission

## Point 4: Input-To-Redraw Ownership Is Weakly Expressed

Status: ready to promote.

### Current state and offending code

- `howl-linux-host/src/input/input.zig`
  - many SDL handlers set `redraw_requested` before PTY publication outcome is known
- `howl-linux-host/src/terminal/terminal_panel.zig:362-403,1056-1079`
  - publish helpers return only `bool`
  - publish success does not produce an explicit host-owned admission/redraw intent object

### What references say it should be

- Alacritty gives input publication and redraw separate verbs.
  - `[A:event.rs:690-699]`
  - `[A:event.rs:1358-1409]`
- Ghostty keeps publication and redraw as separate explicit messages/wakes.
  - `[G:termio/stream_handler.zig:125-172]`
  - `[G:termio/Thread.zig:304-361]`
- TigerBeetle requires explicit control-plane/data-plane seams.
  - `[T:TIGER_STYLE.md:179-184,249-254]`

### Exactly what must change

- In `howl-linux-host/src/input/input.zig`
  - stop setting `redraw_requested` in terminal-bound mouse/key publication paths:
    - `processMouseMotion`
    - `maybeQueueModifierMouseMove`
    - `processMouseButtonDown`
    - `processMouseButtonUp`
    - `processMouseWheel`
  - keep redraw requests only for host/window-owned visual mutations
- In `howl-linux-host/src/terminal/terminal_panel.zig`
  - change `drainInput(...) void` to return:
    - `published_to_pty: bool`
    - `host_visual_changed: bool`
  - `publishTerminalBytes/Key/Mouse` stay publication-only helpers
- In `howl-linux-host/src/main.zig`
  - `forwardTerminalInput(app)` must return that outcome
  - `host_visual_changed` feeds host redraw intent
  - `published_to_pty` feeds admission intent only, not redraw/present intent

### How to lock it in

- `input/input.zig` tests proving terminal-bound mouse/key queueing does not set redraw by itself
- `terminal_panel.zig` tests proving PTY publication and host visual mutation produce distinct outcomes
- `main.zig` tests proving `published_to_pty` keeps next turn non-blocking but does not itself trigger present

## Point 5: Host Frame Pacing Is Under-Shaped

Status: ready to promote.

### Current state and offending code

- `howl-linux-host/src/main.zig:79-102,258-351`
  - no host-owned frame permit/token/pacing concept
  - waits derive only from SDL/input, blink, and runtime obligations
- `howl-linux-host/src/main.zig:471-490`
  - `shouldPresent(...)` bolted onto present, not a central pacing model
- `howl-linux-host/src/input/window.zig`
  - wake and redraw events exist, but no frame permit state

### What references say it should be

- Alacritty owns frame pacing through host scheduler/frame tokens.
  - `[A:event.rs:409-449]`
  - `[A:display/mod.rs:512-515,1000-1046,1434-1457]`
  - `[A:window_context.rs:365-398]`
- Ghostty keeps render and present runtime actions separate.
  - `[G:App.zig:126-132,237-289]`
  - `[G:Surface.zig:6238-6245]`
- TigerBeetle requires explicit bounded host-side pacing state.
  - `[T:TIGER_STYLE.md:90-100,104-147,179-184]`

### Exactly what must change

- In `howl-linux-host/src/main.zig`
  - add `FramePacingState` with exactly:
    - `redraw_requested: bool`
    - `render_work_pending: bool`
    - `frame_permit_ready: bool`
    - `present_in_flight: bool`
    - `present_complete_pending: bool`
  - `FramePacingState` must be the only owner of:
    - blocking decision
    - render permission
    - present submission permission
- `collectLoopPending()` must stop treating terminal render desire as pacing state
- `loopWaitMs(...)` must grow a frame-pacer deadline input

### How to lock it in

- `main.zig` tests proving:
  - runtime wake != frame permit
  - redraw request != frame permit
  - terminal render work != frame permit
  - frame deadlines participate in wait calculation
- assertions that render/present submission respect frame permit and in-flight state

## Point 6: “Present Complete” Is Not A Strong Host Concept Yet

Status: ready to promote.

### Current state and offending code

- `howl-linux-host/src/terminal/render/retained.zig:46-52,106-120`
  - present in flight is just a render-side `snapshot_seq`
- `howl-linux-host/src/main.zig:471-482`
  - `window.present(...)` immediately followed by `tab.finishPresent()`
- `howl-linux-host/src/window/window.zig:113-123`
  - window API has no submit token or completion API
- `howl-linux-host/src/window/present.zig:43-57,100-136`
  - backend present path records proof/debug only, not host submission/completion state

### What references say it should be

- Ghostty separates render and present at host/runtime seam.
  - `[G:App.zig:277-289]`
  - `[G:Surface.zig:6238-6245]`
- Alacritty separates swap from next-frame admission.
  - `[A:display/mod.rs:1019-1046,1434-1457]`
  - `[A:event.rs:442-449]`
- TigerBeetle requires explicit state transitions.
  - `[T:TIGER_STYLE.md:104-147]`

### Exactly what must change

- In `howl-linux-host/src/window/present.zig`
  - add `pub const PresentToken = u64`
  - extend `Present.State(c)` with:
    - `next_present_token`
    - `submitted_present`
    - `completed_present`
  - replace `present(...) void` with:
    - `submitPresent(...) PresentToken`
    - `drainPresentComplete(...) ?PresentToken`
- In `howl-linux-host/src/window/window.zig`
  - replace `State.present(frame)` with:
    - `State.submitPresent(frame) PresentToken`
    - `State.drainPresentComplete() ?PresentToken`
- In `howl-linux-host/src/terminal/render/retained.zig`
  - replace `present_in_flight: ?u64` with a struct carrying:
    - `snapshot_seq`
    - `token`
  - replace:
    - `beginPresent(snapshot_seq)`
    - `finishPresent() ?u64`
  - with:
    - `notePresentSubmitted(snapshot_seq, token)`
    - `completePresent(token) ?u64`
- In `howl-linux-host/src/main.zig`
  - separate submit and completion paths
  - host must never call terminal completion in the same statement block as submit

### How to lock it in

- retained/present tests for submit token storage, matching completion, mismatched completion rejection, and pending-state lifetime
- `main.zig` fake-window tests proving submit and completion are distinct host actions
- assertions in `window/present.zig` for single in-flight token and drain-before-overwrite

## Point 7: Redraw Is Too Event-Shaped Instead Of Policy-Shaped

Status: ready to promote.

### Current state and offending code

- `howl-linux-host/src/input/window.zig:21-23,57-78`
  - redraw has its own SDL event type and pending bit
- `howl-linux-host/src/input/input.zig:182-190,261-268`
  - redraw event is folded back into `Input.redraw_requested`
- `howl-linux-host/src/main.zig:394-404`
  - runtime keepalive gets expressed as redraw event

### What references say it should be

- Alacritty separates PTY wake, dirty, redraw request, and frame availability.
  - `[A:event_loop.rs:165-169,244-249]`
  - `[A:event.rs:409-415,442-449]`
  - `[A:window_context.rs:400-494]`
- Ghostty queues render work explicitly after output processing and drains redraw on the app side.
  - `[G:termio/Termio.zig:651-655]`
  - `[G:App.zig:237-289]`
- TigerBeetle wants explicit policy, not event-shaped hidden contracts.
  - `[T:TIGER_STYLE.md:179-184]`

### Exactly what must change

- In `howl-linux-host/src/input/window.zig`
  - remove redraw event mechanism entirely:
    - `redraw_event_type`
    - `redraw_event_pending`
    - `requestRedraw`
    - `redrawRequested`
    - `isRedrawEventType`
    - `ackRedrawEvent`
- In `howl-linux-host/src/input/input.zig`
  - `requestRedraw()` must only set `self.redraw_requested = true`
  - remove `window_state.redrawRequested()` from `hasPendingLoopWork()`/successor
  - remove synthetic redraw-event branch from `processEvent`
- In `howl-linux-host/src/main.zig`
  - replace runtime `input.requestRedraw()` keepalive with `input.wakeWindow()`
  - rename `chrome_present` to `host_dirty`
  - keep present policy driven by host dirty + terminal frame facts, not redraw event plumbing

### How to lock it in

- `Input` tests proving `requestRedraw()` flips only the internal host-dirty bit
- host-loop tests proving `keep=true, should_redraw=false` yields wake-only continuation
- matrix tests for host dirty / terminal dirty / frame pending behavior

## Point 8: The Simple Text Path Is Not Obviously Collapsed

Status: ready to promote.

### Current state and offending code

- `howl-linux-host/src/input/input.zig:292-297,336-346`
  - text input just joins a generic queue
- `howl-linux-host/src/terminal/terminal_panel.zig:362-400`
  - text input path is buried inside mixed UI/mouse/selection logic
- continuation to PTY/runtime/render/present is spread across multiple files and not readable in one place

### What references say it should be

- Ghostty explicitly queues render immediately after output processing.
  - `[G:termio/Termio.zig:651-655]`
  - `[G:termio/stream_handler.zig:1547-1549]`
- Alacritty’s PTY read emits `Wakeup` after terminal mutation, and frame events bypass batching to minimize input latency.
  - `[A:event_loop.rs:153-169]`
  - `[A:event.rs:442-449]`
- Alacritty content/damage model makes the simple text case visibly primary.
  - `[A:display/content.rs:24-39,153-184]`
  - `[A:display/damage.rs:12-103,138-203]`
- Kitty docs give prompt/readline protocol facts:
  - prompt markers, cursor-shape changes, clean prompt redraw on resize
  - `[K:shell-integration.md:48-60,916-953,1244-1279]`

### Exactly what must change

- In `howl-linux-host/src/terminal/terminal_panel.zig`
  - split `drainInput` into exactly:
    - `drainTextInputFastPath(self: *TerminalPanel, input_events: *HostInput) void`
    - `drainPointerAndUiInput(self: *TerminalPanel, input_events: *HostInput, origin_x: i32, origin_y: i32, logical_width: c_int, logical_height: c_int) void`
- `drainTextInputFastPath` must handle only:
  - `.bytes`
  - `.key`
  - calling only:
    - `publishTerminalBytes`
    - `publishTerminalKey`
    - `resetCursorBlinkActivity`
  - no host redraw, selection, hover, scroll, or window policy
- In `howl-linux-host/src/main.zig`
  - `forwardTerminalInput()` must call text fast path first, pointer/UI second, with no host policy step inserted between text publication and runtime progress
- Outside current host files but required for full readline-grade behavior:
  - VT owner must support `OSC 133` prompt markers and shell-driven cursor shape changes

### How to lock it in

- host unit test proving text fast path:
  - publishes bytes/key
  - resets blink
  - does not touch host hover/selection/redraw directly
- end-to-end host test:
  - `SDL_EVENT_TEXT_INPUT` -> PTY publish -> runtime wake -> `driveTerminalProgress` -> `renderTurn` -> `present`
  - must reach `.rendered` or `.blocked_present` without synthetic redraw admission
- VT/protocol tests for `OSC 133` and `DECSCUSR`

## Promotion Order

Recommended slicing:

1. Point 4: Input-To-Redraw Ownership Is Weakly Expressed
2. Point 7: Redraw Is Too Event-Shaped Instead Of Policy-Shaped
3. Point 1: Wake, Redraw, And Present Policy Are Too Entangled
4. Point 3: runLoopTurn Carries Too Much Implicit Policy
5. Point 2: Present Cadence Is Not First-Class Enough
6. Point 6: “Present Complete” Is Not A Strong Host Concept Yet
7. Point 5: Host Frame Pacing Is Under-Shaped
8. Point 8: The Simple Text Path Is Not Obviously Collapsed

Why this order:

- Point 4 gives the clearest early ownership seam.
- Point 7 removes redraw-as-event debt that pollutes later work.
- Points 1 and 3 clean host control flow once the input/redraw seam is explicit.
- Points 2, 6, and 5 shape host present/frame contracts after the earlier cleanup.
- Point 8 should land after the host control and redraw/present contracts are cleaner.
