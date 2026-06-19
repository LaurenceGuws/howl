# Howl Linux Host Event Loop Cuts

Purpose:

- Record the source-backed cut sequence for making `howl-linux-host` match Alacritty's PTY/event/redraw/present cadence more closely.
- Preserve the redundant researcher consensus so future slices do not depend on chat context.
- Execute the cuts sequentially. Do not add compatibility shims, fallback timing, fake managers/controllers, or broad admission buckets.

Reference pressure:

- Primary reference: `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty`.
- Event dispatch: `alacritty/src/event.rs`.
- Per-window dirty/event batching/draw: `alacritty/src/window_context.rs`.
- Display draw/present/frame timer: `alacritty/src/display/mod.rs`.
- Window redraw/frame flags: `alacritty/src/display/window.rs`.
- Timer queue: `alacritty/src/scheduler.rs`.
- PTY I/O thread: `alacritty_terminal/src/event_loop.rs`.

Recent accepted cuts already completed:

- Deleted hidden 60 Hz refresh fallback from `howl-linux-host/src/display/window.zig`.
- `Window.currentRefreshIntervalNs()` now fails explicitly when SDL cannot provide display/mode/rate.
- Expanded normal host PTY read/feed backlog to the ABI normal transport budget, `64 KiB * 16 = 1 MiB`.
- Removed opportunistic PTY feed after the first readable chunk; host PTY pump now drains the bounded read budget before locking once to feed bytes.

Completed event-loop cuts:

- Slice 1a moved bounded PTY progress into the PTY wait thread after transport readiness.
- `pty_wait_thread` no longer waits for host wake acknowledgement before reading more PTY data.
- `pty_wait_thread` drains `pty_pump.driveOnce` while bounded work reports `keep`.
- `pty_pump` marks retained render work directly when VT feed/runtime progress changes terminal state.
- Host wake acknowledgement now only clears coalescing state; wake no longer admits host-side transport pumping.
- Slice 2a collapsed SDL GL present completion to synchronous submit completion.
- `display.State` no longer stores submitted/ready present tokens.
- `present.zig` no longer drains deferred ready completions; terminal frames complete immediately after `SDL_GL_SwapWindow` returns.
- Retained VT source ack remains conditional and owner-local, so stale completed snapshots are ignored instead of crashing.
- Slice 2b deleted the remaining host `pending_terminal_present` state and stale ready-completion test scaffolding.

## Ordered Cuts

### 1. Replace Wait-Only PTY Thread With Alacritty-Style PTY Event Loop

Problem:

- Howl's PTY thread only waits and wakes the host.
- The host main loop still performs PTY read/feed/runtime progress.
- This creates visible sequential catch-up between PTY, VT, render, and present.

Cut target:

- `howl-linux-host/src/terminal/pty_wait_thread.zig`.
- `howl-linux-host/src/terminal/pty_pump.zig`.
- `howl-linux-host/src/event.zig` functions and fields:
  - `driveRuntimeProgress`
  - `driveTerminalProgress`
  - `driveTabRuntimeTurn`
  - `terminal_input_admitted`
  - `LoopRuntimeFacts.runtime_admitted`
  - `LoopRuntimeFacts.runtime_wake_pending`
  - `LoopRuntimeFacts.runtime_wait_ms`

Reference shape:

- Alacritty PTY loop owns channel drain, PTY write, PTY read, parser advance, synchronized-update timeout, child exit, and wakeup emission.
- `alacritty_terminal/src/event_loop.rs` lines 88-101: drains input/resize/shutdown channel.
- `alacritty_terminal/src/event_loop.rs` lines 120-168: reads PTY, locks terminal, parses bytes, sends `Wakeup`.
- `alacritty_terminal/src/event_loop.rs` lines 205-320: PTY reader thread polls PTY/channel/child events and reregisters write interest.
- `alacritty/src/window_context.rs` lines 208-227: creates PTY event loop and spawns the I/O thread.

Howl evidence:

- `howl-linux-host/src/terminal/pty_wait_thread.zig` lines 44-52: waits for ack, waits transport, signals wake.
- `howl-linux-host/src/terminal/pty_pump.zig` lines 42-53: `driveOnce` is host-called and returns `keep`/`should_redraw`.
- `howl-linux-host/src/event.zig` lines 357-384: host drives terminal progress for tabs.

Execution sequence:

- Make the PTY thread call a bounded PTY drive after transport readiness.
- Wake the host only after VT/runtime state was actually advanced or child exit occurred.
- Remove host-loop PTY driving for the active tab.
- Delete wake-ack choreography once PTY progress no longer depends on host acknowledgement.
- Replace wait-slice polling with a PTY event loop primitive that blocks on PTY readiness and an explicit command/kick channel.

Required proof:

- Burst output test: large PTY output parses before one redraw instead of rendering in visible slices.
- Input publish test: host input reaches PTY writer without waiting for render cadence.
- Resize during output test.
- Child exit with unread bytes test.
- Shutdown without deadlock test.

### 2. Delete Fake Async Present Lifecycle For SDL GL

Problem:

- `SDL_GL_SwapWindow` is synchronous, but Howl wraps it in `PresentToken`, `pending_terminal_present`, `terminal_retire`, `blocked_present`, and completion drain.
- This is host cadence policy pretending to be backend truth.

Cut target:

- `howl-linux-host/src/display/present.zig`.
- `howl-linux-host/src/display/display.zig` submitted/ready completion token state.
- `howl-linux-host/src/event.zig`:
  - `pending_terminal_present`
  - `drainPresentComplete`
  - `submitPresent` lifecycle wrapper
- `howl-linux-host/src/terminal/surface.zig`:
  - `blocked_present`
  - `notePresentSubmitted`
  - `completePresent`

Reference shape:

- Alacritty draws and swaps synchronously inside display draw.
- `alacritty/src/display/mod.rs` lines 1019-1046: pre-present notify, swap buffers, request frame after swap, swap damage.
- `alacritty/src/display/mod.rs` lines 607-623: direct `swap_buffers`.

Howl evidence:

- `howl-linux-host/src/display/display.zig` lines 122-155: synchronous `SDL_GL_SwapWindow` still records completion token.
- `howl-linux-host/src/display/present.zig` lines 7-27: reason/token/submission model.
- `howl-linux-host/src/display/present.zig` lines 78-99: pending-present and retire assertions.
- `howl-linux-host/src/event.zig` lines 452-467: submit/drain lifecycle from host loop.

Execution sequence:

- Prove whether render ABI truly needs source retirement after host consumption.
- If ABI needs an ack, collapse it to immediate synchronous swap acknowledgement in the true backend owner.
- Delete present reason/token lifecycle from host event cadence.

Required proof:

- Swap acknowledges exactly the snapshot that was submitted.
- Rapid resize/output cannot leave retained render in `present_in_flight`.
- No stale snapshot is acknowledged before backend consumption.

### 3. Render Only From An Explicit Redraw Path

Problem:

- Howl renders from the generic loop turn after event pumping and runtime progress.
- Alacritty marks dirty/requested redraw during event processing; actual drawing happens on redraw.

Cut target:

- `howl-linux-host/src/event.zig` `runLoopTurn` render-after-progress sequence.
- `howl-linux-host/src/display/window.zig` `requestRedraw` must become a real redraw request seam, not just a bool consumed by the same loop turn.

Reference shape:

- `alacritty/src/event.rs` lines 269-282: `RedrawRequested` calls `window_context.draw`.
- `alacritty/src/window_context.rs` lines 365-398: draw clears requested redraw/dirty and draws.
- `alacritty/src/window_context.rs` lines 485-493: dirty state requests redraw when not currently handling redraw.
- `alacritty/src/display/window.rs` lines 260-264: `request_redraw` coalesces and calls the platform request.

Howl evidence:

- `howl-linux-host/src/event.zig` lines 159-195: wait, pump, mutate, drive, render, submit, frame request in one turn.
- `howl-linux-host/src/display/window.zig` lines 74-76: `requestRedraw` only flips a flag.
- `howl-linux-host/src/event.zig` lines 417-426: render clears redraw request and drives terminal render turn.

Execution sequence:

- Add an explicit redraw event/request seam for SDL if no native equivalent exists.
- Event/PTY/timer paths mark dirty and request redraw only.
- Draw/present only when the redraw event is dispatched and `has_frame` is true.

Required proof:

- Multiple PTY/input/resize mutations coalesce into one redraw.
- Redraw is not recursively requested while drawing the current redraw.
- Terminal wake with `has_frame=false` latches dirty and does not draw until frame ready.

### 4. Move Frame Deadline Into Scheduler/Event Shape

Problem:

- The processor owns `frame_deadline_ns` and polls it at the start of every loop turn.
- Alacritty schedules a one-shot `Frame` event after swap; that event restores `has_frame` and requests redraw if dirty.

Cut target:

- `howl-linux-host/src/event.zig`:
  - `frame_deadline_ns`
  - `noteFrameDeadline`
  - `frameDeadlineWaitMs`
- Keep and narrow:
  - `howl-linux-host/src/display/frame_timer.zig`
  - `Window.has_frame`

Reference shape:

- `alacritty/src/event.rs` lines 443-449: `Frame` event sets `has_frame=true`; if dirty, requests redraw.
- `alacritty/src/display/mod.rs` lines 1434-1458: `request_frame` sets `has_frame=false`, computes timeout, schedules `EventType::Frame`.
- `alacritty/src/display/mod.rs` lines 1557-1601: frame timer computes timeout; missed frame returns zero without a catch-up frame loop.

Howl evidence:

- `howl-linux-host/src/event.zig` lines 31-32: processor owns frame timer/deadline.
- `howl-linux-host/src/event.zig` lines 235-249: processor marks frame ready and schedules deadline.

Execution sequence:

- Add explicit frame timer event.
- Move frame-used/frame-ready consequences to display/window event owner.
- Delete frame wait merge from generic loop wait.

Required proof:

- Dirty while frame-blocked does not render.
- Frame event requests redraw if dirty.
- Missed intervals do not create multi-frame catch-up.

### 5. Delete Loop Wait Admission And Runtime Wait Merge

Problem:

- Howl merges pending SDL events, PTY wake, runtime due, cursor wait, frame deadline, and render work into one Howl-only wait calculator.
- Alacritty uses scheduler topics and event-loop wait deadlines.

Cut target:

- `LoopWaitIntent`.
- `LoopWait`.
- `computeLoopWait*`.
- `waitMsMerge3`.
- `runtime_wait_ms`.
- Any host-loop admission flags used only to justify sequential progress.

Reference shape:

- `alacritty/src/scheduler.rs` lines 24-32: timer topics include `Frame`, `BlinkCursor`, `BlinkTimeout`.
- `alacritty/src/scheduler.rs` lines 54-73: due timers emit events and next deadline.
- `alacritty/src/event.rs` lines 466-489: `AboutToWait` updates scheduler and sets event-loop wait.

Howl evidence:

- `howl-linux-host/src/event.zig` lines 68-93: custom wait intent.
- `howl-linux-host/src/event.zig` lines 197-233: wait computed from pending events/runtime/frame facts.
- `howl-linux-host/src/event.zig` lines 406-415: ad-hoc optional wait merge.

Execution sequence:

- Introduce explicit scheduler events for frame, cursor blink, and VT/runtime timeout.
- Event loop waits until next scheduler deadline or OS event.
- Delete admission/wait buckets.

Required proof:

- Closest timer deadline wins.
- Repeating cursor blink timer behaves correctly.
- Runtime/sync timeout emits a real event, not a loop admission fact.

### 6. Delete Present Reason Taxonomy

Problem:

- Howl classifies presentation as `.host_damage`, `.terminal_frame`, `.terminal_retire`, `.none`.
- Alacritty converges all visual causes into dirty/redraw.

Cut target:

- `howl-linux-host/src/display/present.zig` `Reason`, `deriveReason`.
- `howl-linux-host/src/event.zig` `derivePresentReason`.

Reference shape:

- `alacritty/src/window_context.rs` lines 461-493: pending display update, hint damage, and dirty all request redraw.
- `alacritty/src/event.rs` lines 409-415: terminal wake marks dirty and requests redraw if frame is available.

Required proof:

- Host-only tab-bar damage redraws.
- Terminal-only damage redraws.
- Diagnostic cause, if retained, does not control cadence.

### 7. Stop Host Iterating Tabs To Drive PTY/Runtime Progress

Problem:

- Host event loop walks tabs and drives runtime progress.
- Alacritty gives each terminal/window an independent PTY event loop.

Cut target:

- `howl-linux-host/src/event.zig`:
  - `collectLoopRuntimeFacts`
  - `driveTerminalProgress`
  - inactive-tab runtime aggregation

Reference shape:

- `alacritty/src/window_context.rs` lines 47-70: one window context owns terminal/display/notifier.
- `alacritty/src/window_context.rs` lines 208-227: each context creates its PTY event loop.

Execution sequence:

- PTY threads progress independently of active tab render cadence.
- Host renders only active tab's latest parsed state.
- Inactive tab wake marks tab dirty/attention if product needs it, not host runtime catch-up.

Required proof:

- Inactive tab output does not block active tab redraw.
- Switching tabs displays the latest parsed inactive tab state.

### 8. Move Cursor And Runtime Timers Out Of Terminal Facts

Problem:

- Cursor and runtime obligations are folded into `RuntimeFacts` and loop wait.
- Alacritty schedules blink/frame/timeouts as explicit events.

Cut target:

- `howl-linux-host/src/terminal/surface.zig` runtime facts wait fields.
- `howl-linux-host/src/event.zig` runtime wait merge.

Reference shape:

- `alacritty/src/event.rs` lines 1620-1671: cursor blinking schedules/unschedules blink timers.
- `alacritty/src/scheduler.rs` lines 24-32: blink topics are scheduler-owned.

Required proof:

- Cursor blink starts/stops with focus and typing policy.
- Cursor timeout does not redraw after inactivity.

## Cross-Cut Stop Conditions

- Any slice preserves old names as compatibility aliases.
- Any slice introduces `manager`, `controller`, `engine`, broad `Context`, broad `State`, broad `Options`, or broad `RuntimeFacts` replacement buckets.
- Any slice adds hidden fallback timing.
- Any slice makes host render cadence depend on PTY catch-up loops.
- Any slice bypasses the C ABI boundary with Zig-shaped host convenience imports.
- Any slice deletes render ABI source-retirement truth without proving the synchronous backend replacement invariant.

## First Executable Slice

Recommended first slice:

- Move PTY progress into the PTY thread after transport readiness, while leaving host draw/present behavior unchanged.

Exact goal:

- `pty_wait_thread` no longer only waits and wakes.
- It performs a bounded PTY drive after readiness.
- Host wake means terminal state already advanced.
- Host main loop no longer needs to perform PTY transport catch-up before rendering active output.

Why first:

- The recent 1 MiB host PTY pump change already proved that PTY slicing was a visible slowdown.
- This cut attacks the same source at the owner boundary instead of tuning the main-loop workaround.

Proof gates:

- Host package `zig build check`.
- Host package `zig build test`.
- Workspace root `zig build check`.
- Forbidden scan for the deleted first-slice symbols after the slice is complete.
- Manual burst-output observation if interactive host run is available.
