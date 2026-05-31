# Linux Host Alacritty Runtime Boundary Research

## Scope

- Current slice asks for Linux host runtime/wake/render-turn/present ownership research in `current.txt:1-16`.
- Current slice forbids product code, ABI/header changes, render protocol changes, and host behavior changes in `current.txt:34-43`.
- Required output is exact Alacritty lock/frame/wake facts, exact Howl lock/wake/render/present graph, boundary violations, and one implementation slice in `current.txt:45-52`.
- TigerBeetle requires bounded event work and running at the program's pace instead of reacting directly to external events in `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:96-100` and `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:179-183`.
- TigerBeetle requires centralized control flow and state manipulation in `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:168-175`.
- TigerBeetle architecture backs single-threaded execution for simple testing and synchronization avoidance in `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:168-188`.
- Prior render sprint records that hosts own event loops, wake policy, presentation cadence, backend resource realization, and swap in `research/2026-05-31-howl-render-protocol-sprint.md:410-416` and `research/2026-05-31-howl-render-protocol-sprint.md:923-926`.
- Prior Alacritty render research records that `Display::draw()` releases the terminal lock before GL work and present/swap in `research/2026-05-31-howl-render-protocol-sprint.md:659-665`.
- Existing host notes identify wake/redraw/present policy entanglement and weak present-complete ownership in `research.txt:1-13` and `research.txt:31-40`.

## Alacritty Facts

- `PtyEventLoop::new()` receives `Arc<FairMutex<Term<U>>>`, an event proxy, and PTY in `utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs:63-81`.
- Alacritty's PTY loop owns PTY I/O and parser mutation according to `EventLoop` comments in `utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs:42-55`.
- PTY read work is bounded by `READ_BUFFER_SIZE = 0x10_0000` and `MAX_LOCKED_READ = u16::MAX` in `utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs:23-27`.
- `pty_read()` reads from PTY before acquiring the terminal lock in `utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs:120-145`.
- `pty_read()` advances the parser while holding the terminal lock in `utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs:153-160`.
- `pty_read()` emits `Event::Wakeup` only after processed bytes exceed synchronized bytes in `utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs:165-168`.
- `EventLoop::spawn()` runs the PTY reader on a named background thread in `utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs:205-224`.
- The PTY thread waits on poll events, handles synchronized-update timeout, drains channel messages, reads PTY, writes PTY, and updates poll interest in `utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs:227-317`.
- PTY input from the UI is sent through `Notifier::notify()` into the PTY event loop channel in `utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs:333-347`.
- Sending a PTY event loop message also notifies the poller in `utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs:383-393`.
- `WindowContext::new()` creates `Term`, wraps it in `Arc<FairMutex<_>>`, creates the PTY, creates `PtyEventLoop`, stores its channel, and spawns the I/O thread in `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs:188-228`.
- `WindowContext::draw()` processes renderer updates, then locks the terminal only to call `display.draw()` in `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs:365-398`.
- `Display::draw()` explicitly takes `MutexGuard<'_, Term<T>>` in `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:770-782`.
- `Display::draw()` collects renderable content into `grid_cells`, snapshots selection/color/offset/cursor/metrics/size facts, imports terminal damage, resets terminal damage, then drops the terminal lock in `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:783-815`.
- Alacritty performs hint validation, display/UI damage, context make-current, clear, text draw, rect/cursor/UI draw, pre-present notify, swap, optional finish, frame request, and damage swap after dropping the terminal lock in `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:817-879` and `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:881-1047`.
- `Display::process_renderer_update()` performs surface resize, `make_current()`, glyph-cache reset, and renderer resize outside terminal lock from `WindowContext::draw()` before lock acquisition in `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs:373-390` and `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:739-768`.
- `Display::swap_buffers()` uses Wayland `swap_buffers_with_damage()` with shaped damage or plain swap otherwise in `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:607-623`.
- `Window::request_redraw()` coalesces duplicate redraw requests with `requested_redraw` in `utils/dev_references/terminals/alacritty/alacritty/src/display/window.rs:100-112` and `utils/dev_references/terminals/alacritty/alacritty/src/display/window.rs:259-265`.
- `Processor::window_event()` draws only on `WindowEvent::RedrawRequested` after event handling in `utils/dev_references/terminals/alacritty/alacritty/src/event.rs:249-283`.
- Frame timer events bypass batching to reduce input latency and set `has_frame` before requesting redraw if dirty in `utils/dev_references/terminals/alacritty/alacritty/src/event.rs:442-450`.
- `about_to_wait()` dispatches staged events to all windows, updates scheduler, and sets `ControlFlow::WaitUntil` or `ControlFlow::Wait` in `utils/dev_references/terminals/alacritty/alacritty/src/event.rs:466-490`.
- Scheduler topics include `Frame`, and `Scheduler::update()` emits due timer events and returns the nearest deadline in `utils/dev_references/terminals/alacritty/alacritty/src/scheduler.rs:24-32` and `utils/dev_references/terminals/alacritty/alacritty/src/scheduler.rs:54-73`.
- `Display::request_frame()` marks `has_frame = false`, computes monitor-vblank timeout, and schedules an `EventType::Frame` in `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:1434-1458`.
- Damage tracker owns two `FrameDamage` slots and swaps/reset frames in `utils/dev_references/terminals/alacritty/alacritty/src/display/damage.rs:12-28` and `utils/dev_references/terminals/alacritty/alacritty/src/display/damage.rs:56-63`.
- Shaped damage returns a full surface rect for full damage or line/viewport rects for partial damage in `utils/dev_references/terminals/alacritty/alacritty/src/display/damage.rs:92-103`.
- Damage shaping overdamages around cells and clamps to viewport bounds in `utils/dev_references/terminals/alacritty/alacritty/src/display/damage.rs:236-251`.
- Adjacent overlapping damage rects are merged in `utils/dev_references/terminals/alacritty/alacritty/src/display/damage.rs:257-273`.
- `Renderer::draw_cells()` dispatches to the selected text renderer in `utils/dev_references/terminals/alacritty/alacritty/src/renderer/mod.rs:177-190`.
- `TextRenderer::draw_cells()` iterates cells and calls `api.draw_cell()` in `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:57-69`.
- `TextRenderApi::add_render_item()` flushes when texture changes and when the batch is full in `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:118-132`.
- GLSL3 text batch capacity is `BATCH_MAX = 0x1_0000` and the batch allocates with that capacity in `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glsl3.rs:27` and `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glsl3.rs:378-392`.
- GLES2 text batch capacity is derived from the `u16` index range and allocated with that capacity in `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/gles2.rs:221-245`.
- `GlyphCache` owns the glyph `HashMap`, rasterizer, font keys, font size, offsets, metrics, and built-in box drawing flag in `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs:42-79`.
- `LoadGlyph` is the seam from rasterized glyph to graphics memory in `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs:17-26`.
- `GlyphCache::get()` checks cache, rasterizes missing glyphs, handles fallback, loads glyphs, and inserts into cache in `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs:200-245`.
- `Atlas` is GL-coupled through `GLuint`, `gl::TexImage2D()`, and `gl::TexSubImage2D()` in `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/atlas.rs:32-61`, `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/atlas.rs:73-99`, and `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/atlas.rs:154-196`.
- `Atlas::load_glyph()` creates and pushes a new atlas when the current atlas is full in `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/atlas.rs:247-273`.

## Howl Facts

- `main.zig` centralizes the app turn: compute admission, pump window events, apply host mutations, drain present completion, drive runtime progress, derive render intent, gate pacing, render, derive present plan, submit present in `howl-linux-host/src/main.zig:230-287`.
- Loop admission combines owner work, runtime wake, runtime obligation, terminal input admission, frame pacing, and wait deadline in `howl-linux-host/src/main.zig:290-319`.
- Background PTY wake state is surfaced through `tabsHavePendingWake()` and `tabsPendingWakeCount()` in `howl-linux-host/src/main.zig:370-385`.
- Runtime obligations are included in pending work and wait deadlines in `howl-linux-host/src/main.zig:387-410` and `howl-linux-host/src/main.zig:463-489`.
- Host-owned mutations run before runtime progress and render: focus, bindings, terminal input, and window resize in `howl-linux-host/src/main.zig:426-433`.
- Text input drains before pointer/UI input, and published PTY input sets `terminal_input_admitted` in `howl-linux-host/src/main.zig:504-518`.
- Runtime progress drives every tab, marks redraw when transport/runtime changes, and returns keep-running when work remains in `howl-linux-host/src/main.zig:538-558`.
- `render()` calls `tab.renderTurn()`, then `tab.noteRenderTurn()`, title sync, and snapshot creation in `howl-linux-host/src/main.zig:572-580`.
- Present planning maps host redraw and terminal render step to a reason in `howl-linux-host/src/main.zig:607-616`.
- Present submission is gated by frame pacing and delegates to `AppPresent.submitWith()` in `howl-linux-host/src/main.zig:618-647`.
- Present completion is drained before render and can short-circuit the turn in `howl-linux-host/src/main.zig:246-270` and `howl-linux-host/src/main.zig:649-657`.
- `Context.startRuntime()` starts the PTY session, initializes wake state, and spawns `progressThreadMain` on `howl-term-host` in `howl-linux-host/src/terminal/context.zig:449-461`.
- `wait_thread.State` owns `stop`, `wake_pending`, wake ack semaphore, thread, and wake input in `howl-linux-host/src/terminal/pty/wait_thread.zig:9-29`.
- `progressThreadMainWith()` waits for wake acknowledgement, waits for transport readiness, signals owner wake, and stops when dead in `howl-linux-host/src/terminal/pty/wait_thread.zig:45-54`.
- Wake handoff is coalesced by `wake_pending.swap(true)` and calls `input.wakeWindow()` in `howl-linux-host/src/terminal/pty/wait_thread.zig:91-119`.
- Owner acknowledgement clears `wake_pending` and signals the wake ack semaphore in `howl-linux-host/src/terminal/pty/wait_thread.zig:39-43` and `howl-linux-host/src/terminal/pty/wait_thread.zig:97-100`.
- PTY pump uses bounded transport constants and compile-time assertions in `howl-linux-host/src/terminal/pty/pump.zig:9-21`.
- `driveOnce()` composes transport pump, runtime progress, outbound backlog, liveness, keep flag, and redraw flag in `howl-linux-host/src/terminal/pty/pump.zig:43-55`.
- Runtime progress locks `term.mutex`, queries/progresses runtime obligation, drains terminal reply, then unlocks in `howl-linux-host/src/terminal/pty/pump.zig:75-90`.
- Transport pumping leases the terminal mutex, pumps outbound, reads into bounded scratch, opportunistically locks, force-locks at threshold, feeds under lock, and returns bounded progress in `howl-linux-host/src/terminal/pty/pump.zig:103-193`.
- `Context.driveProgress()` skips inactive tabs without pending wake/runtime obligation, calls `pty_pump.driveOnce()`, publishes source on active redraw, applies clipboard writes, and acks wake in `howl-linux-host/src/terminal/context.zig:366-379`.
- `Context.renderTurn()` locks `term.mutex` at entry and defers unlock across source publication, work-state checks, prepare, submit, V0 realization, full RGBA upload, and render submit via `driveRenderLocked()` in `howl-linux-host/src/terminal/context.zig:381-406`.
- `driveRenderLocked()` calls `self.term.render.prepare()` and then `self.submitPreparedLocked()` while the caller still holds `term.mutex` in `howl-linux-host/src/terminal/context.zig:515-527`.
- `submitPreparedLocked()` takes prepared upload, realizes V0 frame through `protocol_v0_textures.realizeFrame()`, ensures host surface, uploads full RGBA through `term_texture.uploadPreparedBuffer()`, samples GL state, logs diagnostics, then calls `self.term.render.submit()` in `howl-linux-host/src/terminal/context.zig:567-617`.
- `notePresentSubmitted()` locks `term.mutex` to record the render-side present token in `howl-linux-host/src/terminal/context.zig:408-412`.
- `completePresent()` locks `term.mutex` to complete the matching present in `howl-linux-host/src/terminal/context.zig:414-418`.
- `window/present.zig` owns SDL GL context creation and vsync swap interval in `howl-linux-host/src/window/present.zig:88-113`.
- `submitPresent()` asserts no in-flight submitted/completed present, allocates a nonzero token, records readiness, updates tab cache, clears framebuffer, draws tab bar, draws terminal texture, draws scrollbar, swaps, records diagnostics, marks completed token, and returns token in `howl-linux-host/src/window/present.zig:126-170`.
- `drainPresentComplete()` consumes exactly one completed token after submitted-present is null in `howl-linux-host/src/window/present.zig:173-179`.
- `AppPresent.deriveReason()` maps `.rendered` to `.terminal_frame`, `.blocked_present` to `.terminal_retire`, and idle/failed steps to host damage or none in `howl-linux-host/src/app/present.zig:29-35`.
- `AppPresent.submitWith()` calls `window.submitPresent()` only for `.host_damage` and `.terminal_frame` in `howl-linux-host/src/app/present.zig:37-52`.
- `AppPresent.recordSubmissionFor()` records terminal present tokens only for `.terminal_frame`, asserts `.blocked_present` for `.terminal_retire`, and leaves pending terminal present unchanged for retire in `howl-linux-host/src/app/present.zig:54-75`.
- `AppPresent.drainComplete()` drains a window token, notes frame pacing completion, matches the pending terminal token, completes terminal present on all tabs, and clears `pending_terminal_present` in `howl-linux-host/src/app/present.zig:77-94`.

## Boundary Violations

- Violation: Howl performs backend resource realization under `term.mutex`; `renderTurn()` locks at `howl-linux-host/src/terminal/context.zig:381-383`, `driveRenderLocked()` reaches submit at `howl-linux-host/src/terminal/context.zig:515-527`, and `submitPreparedLocked()` performs V0 texture realization plus full RGBA GL upload at `howl-linux-host/src/terminal/context.zig:573-590`.
- Alacritty counterfact: terminal lock is dropped before context activation, clear, draw, present, swap, finish, frame scheduling, and damage swap in `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:803-815` and `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:835-1047`.
- Violation: Howl's render-turn lock covers diagnostics and GL state sampling in `submitPreparedLocked()` at `howl-linux-host/src/terminal/context.zig:583-600`; Alacritty keeps GL/backend diagnostics and swap outside the terminal lock through `Display::draw()` after `drop(terminal)` in `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:814-838` and `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:1019-1047`.
- Violation: Howl's lock hold can block PTY feed/runtime progress because PTY pump needs `term.mutex` for runtime progress and transport feed in `howl-linux-host/src/terminal/pty/pump.zig:75-90` and `howl-linux-host/src/terminal/pty/pump.zig:152-180`.
- Alacritty counterfact: PTY thread reserves/tries the terminal lock and bounds locked parsing with `MAX_LOCKED_READ` in `utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs:116-167`.
- Violation: Howl's `Context.renderTurn()` couples terminal-state ownership, render ABI prepare/submit, host GL realization, and full RGBA upload in one critical section in `howl-linux-host/src/terminal/context.zig:381-406` and `howl-linux-host/src/terminal/context.zig:567-617`.
- Source-backed non-violation: Howl's actual window present/swap is host-owned in `window/present.zig`, not render-owned, because `AppPresent.submitWith()` calls `window.submitPresent()` only from host present reasons in `howl-linux-host/src/app/present.zig:37-52` and `window.submitPresent()` owns GL swap in `howl-linux-host/src/window/present.zig:126-170`.
- Source-backed non-violation: Howl's background PTY wait thread wakes the owner thread but does not feed VT or render; it only waits and calls `input.wakeWindow()` in `howl-linux-host/src/terminal/pty/wait_thread.zig:45-54` and `howl-linux-host/src/terminal/pty/wait_thread.zig:91-119`.
- Source-backed risk: `AppPresent.drainComplete()` completes present on all tabs in `howl-linux-host/src/app/present.zig:92-94`; each tab then locks in `Context.completePresent()` at `howl-linux-host/src/terminal/context.zig:414-418`, so present-complete processing can queue behind a long render/upload lock.

## Proposed Slice

- Implementation slice: split `Context.renderTurn()` so `term.mutex` covers only terminal/render state mutation needed to publish source, prepare, take the prepared upload, and submit/retire render state; V0 realization, GL state sampling, `term_texture.ensureSurface()`, and `term_texture.uploadPreparedBuffer()` must execute after unlocking `term.mutex`.
- Allowed product file for the slice: `howl-linux-host/src/terminal/context.zig`.
- Allowed test files for the slice: existing unit tests in `howl-linux-host/src/terminal/context.zig`; add only targeted fake-op tests that prove host upload/realization is outside the locked region.
- Keep `howl-linux-host/src/main.zig`, `howl-linux-host/src/terminal/pty/pump.zig`, `howl-linux-host/src/terminal/pty/wait_thread.zig`, `howl-linux-host/src/window/present.zig`, and `howl-linux-host/src/app/present.zig` behavior unchanged in this slice.
- Do not change render ABI, render protocol V0 structs, prepared-surface ABI, present cadence, PTY pump limits, wake semantics, or full-surface fallback behavior in this slice.
- Required shape: take or retain a prepared upload under lock, release lock, realize/upload host resources, relock only to call render submit and update render-owned submit state.
- Required proof before editing: confirm `render_retained.PreparedUpload` owns enough lifetime to survive unlock until `upload.deinit()`; if not, stop and promote a narrower lifetime-contract slice.

## Invariants

- Host/backend GL work is not performed while `term.mutex` is held; this follows Alacritty's `drop(terminal)` before `make_current()`, draw, and swap in `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:814-838` and `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:1019-1047`.
- Render-side state mutation remains serialized by `term.mutex`; current mutation entry points are `renderTurn()`, `notePresentSubmitted()`, `completePresent()`, and `submit()` lock sites in `howl-linux-host/src/terminal/context.zig:381-418` and `howl-linux-host/src/terminal/context.zig:624-628`.
- PTY feed/runtime progress remains bounded by existing pump constants and assertions in `howl-linux-host/src/terminal/pty/pump.zig:9-21` and `howl-linux-host/src/terminal/pty/pump.zig:119-193`.
- Background thread continues to wake owner only and must not feed VT/render directly; current wake-only behavior is in `howl-linux-host/src/terminal/pty/wait_thread.zig:45-54` and `howl-linux-host/src/terminal/pty/wait_thread.zig:91-119`.
- Present token ordering remains host-owned: window creates token in `howl-linux-host/src/window/present.zig:126-170`, app records terminal-frame token in `howl-linux-host/src/app/present.zig:54-75`, and app drains completion in `howl-linux-host/src/app/present.zig:77-94`.
- Full RGBA upload remains behaviorally present until a separate render-protocol replacement slice removes it; current full upload path is `howl-linux-host/src/terminal/context.zig:579-590`.
- V0 realization remains diagnostic/non-replacement in this slice; current code still performs full RGBA upload after V0 realization in `howl-linux-host/src/terminal/context.zig:573-590`.
- No GL/SDL/window object crosses into `howl-render`; prior contract says backend objects are forbidden in Howl ABI in `research/2026-05-31-howl-render-protocol-sprint.md:921-935`.

## Tests

- Add a `Context` unit test or extracted helper test proving fake host realization/upload callbacks observe `term.mutex` unlocked before they run; source target is `howl-linux-host/src/terminal/context.zig:567-617`.
- Add a test proving render submit still happens under lock after upload, matching the current locked `self.term.render.submit()` ownership in `howl-linux-host/src/terminal/context.zig:602-617`.
- Add a test proving failure in host surface ensure/upload returns failed submit result without leaving prepared upload lifetime un-deinitialized; current failure exits are `howl-linux-host/src/terminal/context.zig:585-594`.
- Preserve existing present tests covering blocked present, matching completion, and mismatched completion in `howl-linux-host/src/terminal/context.zig:1657-1763`.
- Preserve existing app present tests covering reason matrix, present completion, terminal retire, and token routing in `howl-linux-host/src/app/present.zig:96-260`.
- Run from `howl-linux-host`: `zig build test --summary all`.
- Run from `howl-linux-host`: `zig build -Doptimize=ReleaseFast`.
- Run from `howl-linux-host`: `git diff --check`.
- Run from workspace root if the submodule pointer or root-visible files change: `zig build check` and `zig build test`.

## Stop Conditions

- Stop if `PreparedUpload` borrows render-owned storage that is invalid once `term.mutex` is released; record the lifetime gap instead of implementing the split.
- Stop if moving GL work out of the lock requires changing `howl-render/include/howl_render.h` or render protocol V0 ABI.
- Stop if the slice requires changing PTY pump/read limits, wake semaphore semantics, frame pacing policy, or present token protocol.
- Stop if the implementation would remove full RGBA fallback or make V0 protocol the normal path; that is a separate render-protocol slice.
- Stop if tests cannot prove the host upload callback runs outside `term.mutex`.
- Stop if present completion can race with unlocked upload and invalidate the prepared snapshot without an explicit render-owned state assertion.

## Proof Gaps

- `render_retained.PreparedUpload` lifetime was not inspected in this pass; proposed split depends on whether prepared upload buffers/frame spans are stable outside `term.mutex` until `upload.deinit()`.
- `term_texture.ProtocolV0Textures.realizeFrame()` internals were not inspected in this pass; the boundary violation is proved by call location under `term.mutex`, not by its internal GL operations.
- `term_texture.ensureSurface()` and `term_texture.uploadPreparedBuffer()` internals were not inspected in this pass; the boundary violation is proved by host GL upload call location under `term.mutex` in `howl-linux-host/src/terminal/context.zig:583-590`.
- No current test proves `term.mutex` is unlocked during host texture realization/upload.
- No current test proves PTY pump latency is protected from render/upload lock hold time.
- Alacritty provides a Rust internal boundary, not a C ABI boundary; prior sprint records this gap in `research/2026-05-31-howl-render-protocol-sprint.md:724-730`.
- Alacritty damage does not prove damage-limited draw work because it still iterates renderable cells; prior sprint records this in `research/2026-05-31-howl-render-protocol-sprint.md:625-628` and `research/2026-05-31-howl-render-protocol-sprint.md:706-707`.
