# Linux Host Lock Wake Graph Research

## Scope

This research maps the current Linux host owner loop, terminal mutex hold sites,
PTY wake handoff, render prepared upload lifetime, and present completion path.

TigerBeetle pressure applied:

- Keep owner-thread control flow explicit and bounded.
- Do not hold contended terminal state while doing host/backend work.
- Do not invent a second runtime owner.
- Preserve C ABI ownership: render owns prepared frame/span lifetimes; host owns GL
  realization and present.

Inspected files:

- `howl-linux-host/src/main.zig`
- `howl-linux-host/src/terminal/context.zig`
- `howl-linux-host/src/terminal/pty/pump.zig`
- `howl-linux-host/src/terminal/pty/wait_thread.zig`
- `howl-linux-host/src/terminal/render/retained.zig`
- `howl-linux-host/src/window/term_texture.zig`
- `howl-linux-host/src/window/present.zig`
- `howl-linux-host/src/app/present.zig`

## Main Loop Graph

The main owner loop is centralized in `howl-linux-host/src/main.zig`:

- `runLoop()` repeatedly calls `runLoopTurn()` until `.quit` at
  `howl-linux-host/src/main.zig:221-228`.
- Each turn computes admission before pumping SDL/window events at
  `howl-linux-host/src/main.zig:235-243`.
- Host-owned mutations run before terminal runtime progress at
  `howl-linux-host/src/main.zig:245-247`.
- Present completion is drained before render permission is checked at
  `howl-linux-host/src/main.zig:246-274`.
- Render and present are one owner-thread sequence: `render(app)` at
  `howl-linux-host/src/main.zig:276`, `derivePresentPlan()` at
  `howl-linux-host/src/main.zig:278`, and `submitPresent()` at
  `howl-linux-host/src/main.zig:279`.
- `render(app)` calls `tab.renderTurn()`, then snapshots host presentation state at
  `howl-linux-host/src/main.zig:572-580`.
- `submitPresent()` checks pacing, calls `AppPresent.submitWith()`, records retained
  present state, and updates frame pacing at `howl-linux-host/src/main.zig:618-630`.

Admission and wake facts:

- `computeLoopAdmission()` refreshes frame permission and folds owner work,
  runtime wake, present completion, redraw, and render work into wait policy at
  `howl-linux-host/src/main.zig:290-319`.
- Runtime wake is derived from `pty_wait_thread.wakePending(tab)` and runtime
  obligations at `howl-linux-host/src/main.zig:348-354`.
- PTY publication admission prevents sleeping on the next turn after input is
  published to PTY at `howl-linux-host/src/main.zig:504-510` and
  `howl-linux-host/src/main.zig:525-529`.
- If terminal runtime progress says `keep_running`, the owner thread requests a
  window wake only when frame pacing permits terminal keepalive wakes at
  `howl-linux-host/src/main.zig:264-266`.

Present graph:

- `AppPresent.deriveReason()` maps `Context.TurnStep.rendered` to terminal frame,
  `blocked_present` to terminal retire, and idle/failed steps to host damage only
  when host redraw exists at `howl-linux-host/src/app/present.zig:29-35`.
- `AppPresent.submitWith()` calls `window.submitPresent()` only for `.host_damage`
  and `.terminal_frame` at `howl-linux-host/src/app/present.zig:37-52`.
- Terminal frame submission records the render snapshot sequence and present token
  under the terminal through `tab.notePresentSubmitted()` at
  `howl-linux-host/src/app/present.zig:54-66`.
- Present completion drains one window token, notes frame pacing completion, and
  completes retained terminal present only for the matching pending terminal token
  at `howl-linux-host/src/app/present.zig:77-85`.
- The window present backend performs GL draw and `SDL_GL_SwapWindow` synchronously
  inside `submitPresent()` at `howl-linux-host/src/window/present.zig:126-170`.

## Terminal Mutex Hold Sites

Direct terminal mutex hold sites in inspected source:

- `Context.renderTurn()` holds `term.mutex` across source publication,
  `term.render.prepare()`, prepared upload extraction, V0 realization, full RGBA GL
  upload, diagnostics, and `term.render.submit()` through `driveRenderLocked()` and
  `submitPreparedLocked()` at `howl-linux-host/src/terminal/context.zig:381-406`,
  `howl-linux-host/src/terminal/context.zig:515-528`, and
  `howl-linux-host/src/terminal/context.zig:567-617`.
- `Context.notePresentSubmitted()` holds the mutex only to record retained present
  state at `howl-linux-host/src/terminal/context.zig:408-412`.
- `Context.completePresent()` holds the mutex only to complete retained present and
  acknowledge the VT source snapshot at `howl-linux-host/src/terminal/context.zig:414-418`
  and `howl-linux-host/src/terminal/context.zig:1125-1129`.
- `Context.workState()` holds the mutex while querying render work state at
  `howl-linux-host/src/terminal/context.zig:469-474`.
- `Context.cursorBlinkShouldAnimate()` holds the mutex while reading VT cursor flags
  at `howl-linux-host/src/terminal/context.zig:476-483`.
- `setRenderCursorBlinkVisible()` holds the mutex while calling render cursor blink
  state at `howl-linux-host/src/terminal/context.zig:1062-1066`.
- `applyPendingClipboardWrite()` holds the mutex while draining pending OSC 52
  clipboard text and also calls host clipboard setter before unlocking at
  `howl-linux-host/src/terminal/context.zig:1212-1220`.
- PTY runtime progress holds the mutex while querying and applying VT runtime
  obligations at `howl-linux-host/src/terminal/pty/pump.zig:75-90`.
- PTY transport feed uses a lease while pumping outbound and reading PTY bytes, then
  holds the mutex only for bounded feed/record/pending-input work at
  `howl-linux-host/src/terminal/pty/pump.zig:131-180`.

The largest violation is render submission: GL and protocol V0 host resource work
are backend-owned, but currently run under `term.mutex` at
`howl-linux-host/src/terminal/context.zig:573-600`.

## PTY Wake And Feed Graph

PTY wait thread:

- `progressThreadMain()` loops until stop, waits for owner ack, waits for transport,
  signals owner wake, and exits if the PTY is no longer alive at
  `howl-linux-host/src/terminal/pty/wait_thread.zig:45-54`.
- Wake handoff is single-bit and coalesced by `wake_pending`; duplicate wakes do not
  call `wakeWindow()` again at `howl-linux-host/src/terminal/pty/wait_thread.zig:91-95`.
- The wait thread blocks while `wake_pending` remains true until owner ack or stop at
  `howl-linux-host/src/terminal/pty/wait_thread.zig:56-60`.
- Owner ack clears `wake_pending` and signals the wake-ack semaphore at
  `howl-linux-host/src/terminal/pty/wait_thread.zig:39-43`.
- `Context.driveProgress()` acks the wake after PTY/VT progress and clipboard handling
  at `howl-linux-host/src/terminal/context.zig:366-379`.

PTY feed:

- `pty_pump.driveOnce()` performs transport pump, runtime progress, outbound backlog
  check, liveness check, and returns bounded keep/redraw facts at
  `howl-linux-host/src/terminal/pty/pump.zig:43-55`.
- Transport pump bounds reads and bytes with compile-time constants at
  `howl-linux-host/src/terminal/pty/pump.zig:9-21`.
- It reads PTY bytes without holding the terminal data lock, then opportunistically
  locks or force-locks at the threshold at `howl-linux-host/src/terminal/pty/pump.zig:131-162`.
- When locked, it records feed data, feeds VT, drains terminal replies, and samples
  pending input bytes at `howl-linux-host/src/terminal/pty/pump.zig:168-180` and
  `howl-linux-host/src/terminal/pty/pump.zig:268-284`.
- Runtime obligations are progressed under the same terminal mutex at
  `howl-linux-host/src/terminal/pty/pump.zig:75-90`.

The wake thread does not own terminal mutation. It wakes the owner thread and waits
for ack. The owner turn performs bounded PTY/VT work.

## Prepared Upload Lifetime

Current lifetime facts:

- `render_retained.State` owns `prepared_surface` as a retained
  `HowlRenderPreparedSurfaceHandle` at `howl-linux-host/src/terminal/render/retained.zig:524-530`.
- `acceptPrepared()` publishes a prepared handle, releases the previous handle,
  asserts the new handle, and stores it at
  `howl-linux-host/src/terminal/render/retained.zig:816-831`.
- `preparedUpload()` fills `PreparedUpload` with prepared info, prepared buffer, V0
  probe/resource-plan data, and a borrowed `protocol_v0_frame` pointer at
  `howl-linux-host/src/terminal/render/retained.zig:708-724`.
- `preparedBuffer()` obtains `HowlRenderPreparedSurfaceBuffer` from the retained
  prepared handle at `howl-linux-host/src/terminal/render/retained.zig:703-706`.
- `submit()` may consume the prepared handle through
  `howl_render_text_session_take_submit_handle()` and `submitHandle()` at
  `howl-linux-host/src/terminal/render/retained.zig:654-696` and
  `howl-linux-host/src/terminal/render/retained.zig:834-842`.
- `PreparedUpload.deinit()` only overwrites the local wrapper; it does not release
  the render-owned prepared handle or copied pixels at
  `howl-linux-host/src/terminal/render/retained.zig:46-56`.

Current host usage:

- `submitPreparedLocked()` obtains the prepared upload, borrows the V0 frame pointer
  and RGBA pixel span, performs V0 GL realization, ensures the full RGBA terminal
  texture, uploads full RGBA pixels, then calls render submit at
  `howl-linux-host/src/terminal/context.zig:567-617`.
- V0 realization consumes frame/create/upload/retire spans synchronously in
  `ProtocolV0Textures.realizeFrame()` at `howl-linux-host/src/window/term_texture.zig:88-106`.
- V0 upload byte pointers are consumed synchronously by `uploadTexture()` and
  `glTexSubImage2D()` at `howl-linux-host/src/window/term_texture.zig:395-421`.
- Full RGBA upload consumes the borrowed pixel span synchronously by
  `uploadPreparedBuffer()` and `glTexSubImage2D()` at
  `howl-linux-host/src/window/term_texture.zig:1222-1246`.

Prepared upload borrowed pointers can survive unlock within one owner turn if, and
only if, these invariants are made explicit and asserted:

- The retained prepared handle remains stored in `term.render.prepared_surface` from
  upload extraction until final render submit.
- No call that can release, replace, forget, or submit the prepared handle runs
  between unlock and relock.
- The borrowed `protocol_v0_frame`, V0 upload bytes, and `rgba_pixels` are consumed
  synchronously before render submit.
- The borrowed pointers do not survive across a present submission, a later loop
  turn, or any reentrant owner call.

Within the current owner model this is plausible: the main owner thread is the only
caller of `renderTurn()` and the PTY wait thread only wakes owner work. But this is
not yet encoded. The implementation slice must add assertions around handle
identity/state before and after unlocked backend work, otherwise the unlock would
turn render-owned pointers into an undocumented temporal contract.

## State That Must Stay Locked

These states must stay under `term.mutex`:

- VT state, scrollback, title, pending terminal replies, pending clipboard text, and
  runtime obligations, because PTY feed and host input mutate/query the VT owner at
  `howl-linux-host/src/terminal/pty/pump.zig:75-90`,
  `howl-linux-host/src/terminal/pty/pump.zig:268-284`, and
  `howl-linux-host/src/terminal/context.zig:841-868`.
- PTY retained session state while publishing input, pumping outbound, and updating
  lifecycle state, as seen at `howl-linux-host/src/terminal/pty/pump.zig:247-265`
  and `howl-linux-host/src/terminal/pty/pump.zig:268-284`.
- Render retained state transitions: work state, source publication, prepare,
  prepared handle selection, render submit, present-in-flight recording, and present
  completion at `howl-linux-host/src/terminal/context.zig:381-406`,
  `howl-linux-host/src/terminal/context.zig:515-528`,
  `howl-linux-host/src/terminal/render/retained.zig:637-696`, and
  `howl-linux-host/src/terminal/render/retained.zig:597-610`.
- VT source acknowledgement on present completion at
  `howl-linux-host/src/terminal/context.zig:1125-1129`.

## Work That Must Move Out Of Lock

Backend/host work currently inside `term.mutex` must move out:

- V0 GL realization through `self.protocol_v0_textures.realizeFrame(frame)` at
  `howl-linux-host/src/terminal/context.zig:573-577`; GL creation/upload/delete is
  host backend work in `howl-linux-host/src/window/term_texture.zig:345-421` and
  `howl-linux-host/src/window/term_texture.zig:424-428`.
- Full RGBA texture allocation and upload through `term_texture.ensureSurface()` and
  `term_texture.uploadPreparedBuffer()` at
  `howl-linux-host/src/terminal/context.zig:583-594`; the GL work is in
  `howl-linux-host/src/window/term_texture.zig:1190-1246`.
- GL state sampling around full RGBA upload at
  `howl-linux-host/src/terminal/context.zig:584-596`.
- Protocol diagnostics printing at `howl-linux-host/src/terminal/context.zig:600`
  and `howl-linux-host/src/terminal/context.zig:648-817`; diagnostic counters belong
  to the host context, not terminal VT/render mutation.

Separate possible future cleanup, not part of the proposed slice:

- `applyPendingClipboardWrite()` currently calls host clipboard setter while holding
  `term.mutex` at `howl-linux-host/src/terminal/context.zig:1212-1220`. This is
  host I/O under the terminal lock, but it is unrelated to the render/GL bottleneck
  and should not be mixed into the first render lock slice.

## Proposed Slice

One implementation slice only: move prepared-surface host/backend upload work out
of `term.mutex` while preserving prepared handle lifetime inside one owner turn.

Allowed product files for that slice:

- `howl-linux-host/src/terminal/context.zig`
- `howl-linux-host/src/terminal/render/retained.zig` only if a minimal prepared
  handle identity/assert helper is needed.

Required shape:

- Keep source publication, prepare, prepared upload extraction, and render submit as
  terminal-render locked state transitions.
- Extract `PreparedUpload` while locked, retain the prepared handle unchanged, then
  release `term.mutex` before V0 realization, GL state sampling, texture ensure,
  full RGBA upload, and diagnostics.
- Relock only to submit the same prepared handle with the same snapshot sequence and
  host surface execution facts.
- Assert positive lifetime facts before unlocked work and again after relock:
  snapshot sequence nonzero, prepared upload came from a stored prepared handle,
  prepared handle still matches, and no present is pending before submit.
- Do not add a new runtime owner, queue, manager, or compatibility path.
- Do not change render ABI, V0 protocol, present policy, PTY wake policy, or full
  RGBA fallback semantics.

Why this is the first slice:

- It attacks the exact boundary violation: backend/GL work under terminal lock.
- It keeps the owner-thread model unchanged.
- It does not mix V0 resource semantics with runtime/present reshaping.
- It creates the proof point needed before replacing the full-surface path.

## Tests

Required tests for the proposed slice:

- Unit test that a prepared upload can be extracted, backend upload callback can run
  without the terminal mutex held, and submit relocks before calling render submit.
- Unit test that a mismatched or missing retained prepared handle after unlocked
  backend work fails/stops before submit.
- Unit test that backend failure does not call render submit and does not mark
  terminal present in flight.
- Existing host gates must continue passing: `zig build test --summary all` from
  `howl-linux-host`, `zig build -Doptimize=ReleaseFast` from `howl-linux-host`, and
  `git diff --check`.
- Root gates should continue passing if the slice touches shared build boundaries:
  `zig build check`, `zig build test`, and `git diff --check`.

Existing related tests already lock surrounding behavior:

- PTY wake coalescing and ack behavior at
  `howl-linux-host/src/terminal/pty/wait_thread.zig:122-189`.
- Transport pump bounded lock/feed behavior at
  `howl-linux-host/src/terminal/pty/pump.zig:436-519`.
- Present token and completion behavior at
  `howl-linux-host/src/window/present.zig:600-639`.
- App present terminal-token completion behavior at
  `howl-linux-host/src/app/present.zig:121-469`.

## Stop Conditions

Stop the implementation slice if any of these occur:

- The prepared V0 frame pointer or RGBA pixel span is not owned by the retained
  prepared handle for the whole unlocked backend window.
- There is no narrow way to assert retained prepared handle identity across unlock.
- Moving GL upload out of lock requires changing render ABI or V0 protocol.
- The slice starts changing PTY wake policy, present cadence, frame pacing, or V0
  resource semantics.
- The implementation needs a new queue, runtime owner, manager, or background
  backend thread.
- Tests cannot prove backend work runs without the terminal mutex held.

## Proof Gaps

- The exact C ABI owner for `HowlRenderPreparedSurfaceBuffer.rgba_pixels` and
  `HowlRenderV0Frame` spans was inferred from host retained-wrapper behavior, not
  re-read from `howl-render` in this pass.
- `terminal_term.Mutex` internals were not inspected in this pass; tests may need a
  small fake seam instead of direct lock-state inspection.
- `pty_session.waitTransport()` internals were not inspected; this pass only proves
  the wait thread wake/ack graph at the host layer.
- No current test proves `submitPreparedLocked()` holds `term.mutex` during GL work;
  source inspection proves it through call nesting, but the implementation slice
  should add executable proof for the new boundary.
- Clipboard host work under terminal lock is a known separate issue, but not proved
  as a performance bottleneck here.
