# Host Owner Next Scratchpad

Owner: workspace root.

Purpose:

- Record the next host ownership path from current source, not from inference.
- Use source order: Ghostty, Alacritty, TigerBeetle.
- Promote one worker-ready slice at a time to `current.txt`.

## Current Source Facts

- `howl-linux-host/src/main.zig` currently owns process bootstrap, `TabSlots`, frame pacing,
  event-loop admission, terminal input forwarding, tab lifecycle, present submission/completion,
  and many tests.
- `howl-linux-host/src/terminal/context.zig` currently owns one terminal surface/session, including
  PTY/VT/render lifecycle, text and pointer input dispatch, link hover/open, host selection gesture
  adaptation, cursor blink cadence, clipboard OSC 52 writes, render prepare/submit/upload, title
  refresh, scrollbar adaptation, and tests.
- `howl-linux-host/src/window/window.zig` still owns the production SDL/OpenGL `@cImport` bucket and
  exports it as `c_win`.
- `howl-linux-host/src/window/term_texture.zig`, `terminal/context.zig`,
  `terminal/render/surface_layout.zig`, and `input/window.zig` consume `window.c_win`.
- `howl-linux-host/src/input/input.zig` currently owns SDL event pumping, input queues, binding
  queueing, text chunking, key translation, mouse translation, redraw request bit, geometry/focus
  pending bits, and tests.
- Prior host cadence work is already present in current code:
  - `main.zig` has `FramePacingState`.
  - `main.zig` has `PresentReason`, `PresentPlan`, and separate present completion.
  - `terminal/context.zig` has `DrainInputOutcome`, `drainTextInputFastPath`, and
    `drainPointerAndUiInput`.
  - `input/window.zig` no longer has the old redraw SDL event mechanism.
  - `terminal/c.zig` has been deleted; Howl PTY/VT/render C imports are build-owned modules.

## Reference Findings

### Ghostty

- `utils/dev_references/terminals/ghostty/src/App.zig:1-3` documents `App` as the primary GUI
  application whose run loop is started by `run`.
- `Ghostty App.zig:126-132` keeps app ticking as mailbox draining.
- `Ghostty App.zig:237-260` drains explicit app mailbox messages such as open config, new window,
  close, surface message, redraw surface, and quit. The top-level app owns dispatch, not terminal
  widget behavior.
- `utils/dev_references/terminals/ghostty/src/Surface.zig:1-11` defines `Surface` as a single
  terminal widget that owns drawing, events, and PTY session while the higher runtime decides whether
  it is a window, tab, split, or preview pane.
- `Ghostty Surface.zig:126-129` stores `io: termio.Termio`, `io_thread`, and `io_thr` in the surface,
  keeping one terminal widget/session aggregate explicit.
- `utils/dev_references/terminals/ghostty/src/termio/Termio.zig:1-4` defines term I/O as owning
  terminal state, PTY, subprocess, and byte input/output.
- `Ghostty termio/mailbox.zig:10-14` uses an explicitly bounded queue for cross-thread messages.

### Alacritty

- `utils/dev_references/terminals/alacritty/alacritty/src/main.rs:132-136` says startup creates the
  window, terminal state, PTY, I/O event loop, input processor, config monitor, and runs the main
  display loop.
- `Alacritty event.rs:83-101` defines `Processor` as the event processor owning clipboard,
  scheduler, windows map, proxy, GL config, CLI options, and config monitor.
- `Alacritty event.rs:249-282` sends window events to the matching `WindowContext` and calls
  `window_context.draw` only on redraw events.
- `Alacritty window_context.rs:47-70` defines `WindowContext` as one terminal window context owning
  display, terminal, notifier, mouse, search, modifiers, dirty state, and config.
- `Alacritty window_context.rs:365-398` makes `WindowContext.draw` process renderer updates, lock the
  terminal, and draw through display.
- `Alacritty window_context.rs:400-494` makes `WindowContext.handle_event` queue events, create an
  input processor context, process queued events, submit display updates, and request redraw when
  dirty and frame-ready.
- `Alacritty scheduler.rs:24-32` names timer topics directly: selection scrolling, delayed search,
  blink cursor, blink timeout, frame.
- `Alacritty scheduler.rs:43-72` owns sorted pending timers and returns the next deadline.
- `Alacritty display/mod.rs:647-648` states renderer updates must not run in display update handling;
  they are processed right before drawing.
- `Alacritty display/mod.rs:713-724` couples terminal grid resize, PTY resize, and damage tracker
  resize in display update handling.
- `Alacritty display/mod.rs:775-815` collects renderable content while holding terminal lock, then
  drops the lock before drawing.
- `Alacritty display/mod.rs:1019-1046` calls pre-present notify, swaps buffers, then requests the
  next frame through scheduler.

### TigerBeetle

- `TIGER_STYLE.md:90-100` requires simple explicit bounded control flow.
- `TIGER_STYLE.md:96-100` requires a limit on loops/queues and assertions for non-terminating loops.
- `TIGER_STYLE.md:104-147` requires assertions for function arguments, invariants, and positive and
  negative space.
- `TIGER_STYLE.md:161-176` requires small functions and centralized control/state mutation.
- `TIGER_STYLE.md:179-184` says external events should be batched and processed at the program's own
  pace.
- `TIGER_STYLE.md:249-254` separates control plane and data plane through batching.

## Direction From References

- The host should continue toward an Alacritty/Ghostty split:
  - top-level app/event processor owns event-loop dispatch, tab/window list, scheduler/pacing, and
    routing;
  - per-terminal surface/context owns one embedded terminal widget/session and exposes exact effects
    to the app;
  - window/display/present owners own backend realization and presentation;
  - input owner translates SDL events into host input events but should not own terminal widget
    policy;
  - cross-thread/wake paths must stay bounded and explicit.
- Do not infer a giant target tree. Promote only reference-backed slices that remove one broad seam
  at a time.

## Candidate Slices

### Slice A: Move Tab Slots Out Of Main

Status: worker-ready.

Current offending source:

- `howl-linux-host/src/main.zig:21-82` defines `TabSlots` inside the app loop owner.
- `main.zig` also owns `activeTab`, `activeContext`, `tabIndexInRange`, `openTab`, `closeActiveTab`,
  `selectRelative`, `selectTab`, `syncTerminalFocus`, and `tabTitles`.

Reference pressure:

- Ghostty `App` owns the list of surfaces separately from surface behavior (`App.zig:21-27`,
  `App.zig:164-217`).
- Alacritty `Processor` owns the windows map, and `WindowContext` owns per-window terminal state
  (`event.rs:83-101`, `window_context.rs:47-70`).
- TigerBeetle wants direct owners and explicit bounded storage.

Required shape:

- Add `howl-linux-host/src/tab_bar/slots.zig` or `howl-linux-host/src/terminal/tabs.zig` only if the
  chosen file name is owner-true.
- Move bounded tab slot storage and ordering operations out of `main.zig`.
- Preserve `TabBar.TabIndex` and `TabBar.max_tabs` as the tab index/capacity source unless research
  proves otherwise.
- The moved owner must expose operations needed by `main.zig` without accepting `*App`.
- Keep terminal creation/destruction orchestration in `main.zig` for this slice unless moving a small
  helper is necessary for the tab owner to own slot release invariants.
- Keep behavior equivalent.

Verification:

- `howl-linux-host`: `zig build check`, `zig build test`, `git diff --check`.
- root: `zig build check`, `zig build test`, `git diff --check`.

Grep gates:

- `main.zig` must not contain `const TabSlots = struct`.
- New tab slots owner must contain assertions for active/free counts and index bounds.

### Slice B: Move Frame Pacing Out Of Main

Status: worker-ready.

Current offending source:

- `howl-linux-host/src/main.zig:134-200` defines `FramePacingState` inside `main.zig`.

Reference pressure:

- Alacritty has a scheduler owner with explicit `Topic::Frame` and pending deadlines
  (`scheduler.rs:24-72`).
- Alacritty display requests the next frame after swap (`display/mod.rs:1019-1046`).
- TigerBeetle wants explicit state machines and bounded control.

Required next research:

- Research verdict: move current `FramePacingState` to `howl-linux-host/src/window/pacing.zig` as
  `pub const State`.
- Move `PresentReason` to the same owner because it is the reason consumed by present-submission
  permission.
- Move `LoopPending` shape to the same owner as `pub const Pending` because it is the exact input to
  the pacing wait decision.
- Do not implement a real frame deadline yet. Current `loopWaitMs` has a frame-pacer hook, but a real
  deadline needs an Alacritty-like scheduler owner and post-swap scheduling. Adding a fake deadline
  now would be fake progress.

Required shape:

- Add `howl-linux-host/src/window/pacing.zig`.
- Move pure pacing state and tests out of `main.zig`.
- Keep `derivePresentReason` in `main.zig` unless moving it would not couple `window/pacing.zig` to
  `TerminalContext.TurnStep`.
- Keep `PresentPlan`, `PresentSubmission`, `RenderFrame`, submit/record/drain present orchestration
  in `main.zig` for this slice.
- `main.zig` imports `const FramePacing = @import("window/pacing.zig");` and aliases
  `const PresentReason = FramePacing.PresentReason;`.

Required invariants:

- `present_complete_pending` implies `present_in_flight`.
- `frame_permit_ready == false` after submitted present.
- `frame_permit_ready == true` after present completion.
- `present_in_flight == false` after present completion.
- Redraw/render work records intent, not frame permission.
- Runtime wake prevents blocking, but does not grant render permission.
- `.none` and `.terminal_retire` are never submit-permitted.
- `.host_damage` and `.terminal_frame` require frame permit and no in-flight present.

Verification:

- `howl-linux-host`: `zig build check`, `zig build test`, `git diff --check`.
- root: `zig build check`, `zig build test`, `git diff --check`.

Grep gates:

- No `const FramePacingState = struct` in `howl-linux-host/src/main.zig`.
- `howl-linux-host/src/window/pacing.zig` contains `pub const State`, `pub const Pending`, and
  `pub const PresentReason`.

### Slice C: Delete Window C Bucket

Status: worker-ready.

Current offending source:

- `howl-linux-host/src/window/window.zig:6-13` direct `@cImport` and `pub const c_win = c`.
- `window/term_texture.zig`, `terminal/context.zig`, `terminal/render/surface_layout.zig`, and
  `input/window.zig` consume `window.c_win`.

Reference pressure:

- Prior Zig 0.16 research already proved `@cImport` should move to build-system translate-C modules.
- Alacritty keeps GL/window platform integration under display/window and renderer platform owners,
  not as a globally exported C bucket.
- Host boundary law permits SDL/OpenGL in host/window ownership but not broad buckets.

Required next research:

- Research verdict: use two build-owned translated C modules, not one SDL/OpenGL bucket:
  - `sdl_c`: `#include <SDL3/SDL.h>`.
  - `gl_c`: `#include <SDL3/SDL_opengl.h>`.
- Rationale:
  - Zig 0.16 deprecates `@cImport` and moves translation to build-system modules.
  - `build.zig` already owns `translateCModule()` for Howl C imports.
  - A single SDL/OpenGL module would rename the current `window.c_win` bucket instead of splitting
    owner facts.
  - Alacritty separates display/window from renderer/GL platform ownership.
- Current `window.c_win` consumers include:
  - `window/window.zig`
  - `window/term_texture.zig`
  - `input/window.zig`
  - `input/input.zig`
  - `terminal/context.zig`
  - `terminal/render/surface_layout.zig`
  - `terminal/scrollbar.zig`
  - `terminal/pty/wait_thread.zig`

Required shape:

- Add `howl-linux-host/src/window/sdl_c.h`.
- Add `howl-linux-host/src/window/gl_c.h`.
- Add `sdl_c` and `gl_c` translate-C modules in `howl-linux-host/build.zig`.
- Add the imports to host modules and integration host test modules.
- Delete `pub const c_win = c` from `window/window.zig`.
- `window/window.zig` imports `sdl_c` and `gl_c` directly.
- `window/term_texture.zig`, `window/present.zig`, `window/texture.zig`, and `window/draw.zig`
  import `gl_c` where they need OpenGL.
- `input/window.zig` and `input/input.zig` import `sdl_c`.
- Terminal files must not reach through `window.c_win`; prefer `InputWindow.nowNs()` or explicit
  SDL wrapper functions/types from `input/window.zig` where needed.
- Keep `window/icon.zig` and stress tools as non-goals.

Verification:

- `howl-linux-host`: `zig build check`, `zig build test`, `git diff --check`.
- root: `zig build check`, `zig build test`, `git diff --check`.

Grep gates:

- No `window.c_win`.
- No `pub const c_win`.
- No `@import("window.zig").c_win`.
- No `@cImport` in `howl-linux-host/src/window/window.zig`.
- Remaining `@cImport` only in explicit non-goals:
  - `howl-linux-host/src/window/icon.zig`
  - `howl-linux-host/src/stress/ascii_rain_stress.zig`
  - `howl-linux-host/src/stress/visual_rain_stress.zig`

### Slice D: Split Terminal Context Host Selection/Link Owners

Status: research-ready.

Current offending source:

- `terminal/context.zig:683-891` owns host link hover/open and host selection gesture adaptation.

Reference pressure:

- Ghostty `Surface` owns terminal widget input behavior while terminal core owns selection truth.
- Alacritty input processor uses an `ActionContext` trait to mutate terminal/display/window through
  explicit methods (`input/mod.rs:73-147`).

Required next research:

- Decide whether host selection and link hover should be separate files under `terminal/selection.zig`
  and `terminal/links.zig`, or one `terminal/pointer.zig` owner if pointer gesture ordering is the
  true invariant.

## Recommended Promotion

Promote Slice A first.

Why:

- It is directly source-backed by Ghostty `App`/`Surface` and Alacritty `Processor`/`WindowContext`.
- It removes bounded tab storage from the event-loop file without changing ABI, rendering, PTY, VT,
  SDL, or present behavior.
- It creates a clean host-owned aggregate seam before further app-loop refactors.

## Completed Prior Work Referenced

- `host-alacritty-gap-scratchpad.md` points 1-8 are historical and mostly already reflected in
  current code.
- `host-reshape-scratchpad.md` records the accepted first host reshape away from false
  `terminal/runtime`, `terminal/host`, and `terminal_panel` buckets.
