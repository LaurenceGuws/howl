# Terminal Non-PTY Non-Surface Inventory

Date: 2026-06-01.

Role: Researcher. Current-code inventory only. No product code edited.

## Sources Read

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md` lines 1-511.
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md` lines 1-710.
- `AGENTS.md` lines 1-259.
- `loop.txt` lines 1-278.
- `current.txt` lines 1-96.
- `howl-linux-host/src/terminal/context.zig` lines 1-2040.
- `howl-linux-host/src/terminal/scrollbar.zig` lines 1-353.
- `howl-linux-host/src/terminal/links.zig` lines 1-128.
- `howl-linux-host/src/terminal/selection.zig` lines 1-76.
- `howl-linux-host/src/terminal/cursor_blink.zig` lines 1-62.
- `howl-linux-host/src/terminal/vt/input.zig` lines 1-228.
- `howl-linux-host/src/terminal/vt/surface.zig` lines 1-599.
- `howl-linux-host/src/terminal/render/surface_layout.zig` lines 1-202.
- `howl-linux-host/src/display/layout.zig` lines 1-90.
- `howl-linux-host/src/main.zig` lines 1-1150.
- `howl-linux-host/src/app/present.zig` lines 1-469.

## Context Fields Not PTY And Not Render-Surface Ownership

- `conf: *const TerminalConfig` is host terminal configuration used by title fallback, link policy, cursor style, clipboard policy, and launch/render init; field at `context.zig:92`, title fallback at `context.zig:305`, link policy at `links.zig:21`, `links.zig:49`, cursor defaults at `context.zig:1074-1078`, clipboard policy at `context.zig:476-480`.
- `input: *HostInput` is host input/redraw conduit; field at `context.zig:93`, redraw requested on focus/link clear at `context.zig:313`, `context.zig:321`, input drains at `context.zig:219-255`.
- `event_loop: *EventLoop.State` is used by runtime/wake thread and timestamps; field at `context.zig:94`, progress init at `context.zig:469`, timestamps at `context.zig:216`, `context.zig:350`, `context.zig:596`, `context.zig:763`.
- `title_buf: [128]u8` and `title_len: u8` are cached host-visible title state; fields at `context.zig:95-96`, initialized at `context.zig:158-159`, refreshed at `context.zig:297-308`, used for render diagnostic label at `context.zig:880-883` and active window title in `main.zig:614-616`.
- `geometry: surface_layout.State` holds render/logical/grid dimensions and resize timing; field at `context.zig:97`, initialized at `context.zig:160`, state fields at `surface_layout.zig:14-25`, resize mutation at `surface_layout.zig:56-78`.
- `font_size_px` and `default_font_size_px` are host-side font-size controls, not PTY lifecycle or render-surface resource ownership; fields at `context.zig:98-99`, initialized at `context.zig:161-162`, adjusted through bindings at `main.zig:853-856` and context methods at `context.zig:330-343`.
- `window_focused` and `widget_focused` are host focus/chrome state; fields at `context.zig:100-101`, initialized at `context.zig:163-164`, mutated at `context.zig:310-324`, combined for VT focus publication at `context.zig:326-328`, and used by cursor blink at `context.zig:489-496`.
- `scrollbar: terminal_scrollbar.State` is interior terminal overlay/chrome state; field at `context.zig:102`, initialized at `context.zig:165`, state shape at `scrollbar.zig:33-43`, layout at `scrollbar.zig:62-89`, mouse mutation at `scrollbar.zig:91-138`.
- `link_cursor_active` and `hovered_link_cell` are link-hover/cursor chrome state; fields at `context.zig:103-104`, initialized at `context.zig:166-167`, cursor reset in deinit at `context.zig:174-176`, hovered cell mutation at `links.zig:32-36`, `links.zig:67-80`, cursor mutation at `links.zig:85-98`.
- `selection_anchor` and `selection_drag_active` are host selection gesture state while VT owns selection truth; fields at `context.zig:105-106`, initialized at `context.zig:168-169`, press/move/release state machine at `selection.zig:14-67`, VT selection calls at `selection.zig:37-44`, `selection.zig:55-59`.
- `hover_publish_pending` is host overlay-to-render-source pending state for link decoration publication; field at `context.zig:107`, initialized at `context.zig:170`, set by links at `links.zig:51`, `links.zig:61`, `links.zig:79`, consumed in source publication at `context.zig:557-562`.
- `cursor_blink: cursor_blink.State` is blink cadence state; field at `context.zig:108`, initialized at `context.zig:171`, state fields at `cursor_blink.zig:6-9`, plan/reset/wait logic at `cursor_blink.zig:10-43`.

## Context Functions That Are Chrome-Adjacent

- Title: `titleSlice` refreshes and returns the cached title at `context.zig:297-300`; `refreshTitle` copies current VT title or falls back to configured command/shell at `context.zig:302-308`; `renderSurfaceLabel` reuses title for diagnostics at `context.zig:880-883`; `main.zig` applies the title to the active window at `main.zig:603-616`, `main.zig:895`, `main.zig:910`, `main.zig:927`.
- Focus: `setWindowFocused` and `setWidgetFocused` update focus fields, clear hovered links, invalidate scrollbar, and sync input focus at `context.zig:310-324`; `syncInputFocus` publishes combined window/widget focus at `context.zig:326-328`; `main.zig` drains window focus and syncs all tabs at `main.zig:522-525`, `main.zig:930-935`.
- Selection: `terminal_selection.handleMouse` owns host mouse gesture routing at `selection.zig:14-67`; `ContextOps.handleHostSelectionMouse` delegates to it at `context.zig:1034-1036`; pointer/UI drain orders selection before links and terminal mouse publication at `context.zig:1258-1274`.
- Links: `wantsLinkHover` exposes link hover policy at `context.zig:265-268`; `terminal_links.handleMouse` handles hover/open events at `links.zig:14-30`; `clearHoveredLink`, `hoverDecoration`, and `syncLinkCursor` manage hover decoration/cursor effects at `links.zig:32-46`, `links.zig:85-98`; `ContextOps.handleHostLinkMouse` delegates at `context.zig:1038-1040`.
- Scrollbar: `handleScrollInput` delegates page scrolling at `context.zig:257-259`; `wantsPassiveHoverWake` delegates hover/drag wake at `context.zig:261-263`; `overlaySnapshot` exposes scrollbar layout at `context.zig:275-279`; `ContextOps.handleScrollMouse` captures visual state before/after scrollbar mouse handling at `context.zig:998-1003`; scrollbar wrappers and state mutation are in `scrollbar.zig:278-339`.
- Cursor blink: `syncCursorBlinkCadence`, `resetCursorBlinkActivity`, and `nextCursorBlinkWaitMs` are at `context.zig:349-364`; `cursorBlinkShouldAnimate` depends on focus and VT cursor facts at `context.zig:489-496`; render cursor visibility is applied through `setRenderCursorBlinkVisible` at `context.zig:1137-1141`.
- Input/UI overlay routing: `paste` publishes paste and resets blink at `context.zig:214-217`; `drainTextInputFastPath` and `drainPointerAndUiInput` are public drains at `context.zig:219-255`; `handleTextInputFastPathEvent` and `handlePointerAndUiInputEvent` separate PTY publication from host visual mutation at `context.zig:1206-1283`; `main.zig` calls these in `forwardTerminalInputFlow` at `main.zig:544-549`.
- Host clipboard overlay/OSC 52 bridge: `applyPendingClipboardWrites` reads configured policy at `context.zig:476-480`; `WindowClipboardOps` bridges VT pending clipboard to window clipboard at `context.zig:1285-1293`; `applyPendingClipboardWrite` enforces policy at `context.zig:1295-1304`.
- Pixel/cell coordinate helpers used by selection, links, and terminal mouse input: public wrappers at `context.zig:950-956`; implementation clamps via render layout at `context.zig:1143-1158`; selection uses them at `selection.zig:69-75`; links use them at `links.zig:107-112`; terminal mouse publication uses them at `context.zig:924-935`, `context.zig:937-948`.

## Existing Tests Covering These Functions

- `context.zig` tests clipboard policy in `test "pending VT clipboard write follows OSC 52 policy"` at `context.zig:1325-1372`.
- `context.zig` tests cursor activity in `test "cursor activity pushes blink deadline while visible"` at `context.zig:1374-1403`; `cursor_blink.zig` has the same named owner-local test at `cursor_blink.zig:56-62`.
- `context.zig` tests text input fast-path publication and no pointer/UI calls at `context.zig:1423-1549`.
- `context.zig` tests mixed input compaction and text-before-pointer order at `context.zig:1551-1648`.
- `context.zig` tests pointer/UI host visual mutation separation from PTY publication at `context.zig:1650-1705`.
- `scrollbar.zig` tests thumb bottom/top geometry at `scrollbar.zig:266-276`.
- `vt/surface.zig` tests hover decoration underlining and dirty range at `vt/surface.zig:462-489`.
- `main.zig` tests active window title sync at `main.zig:780-801`.
- `main.zig` tests forward terminal input ordering and no present intent at `main.zig:984-1029`.
- `main.zig` tests host visual change can trigger present without PTY publication at `main.zig:1031-1041`.
- `main.zig` tests host redraw/render/present reason facts at `main.zig:1099-1150`.
- `app/present.zig` tests host/terminal present reason and completion behavior at `app/present.zig:96-469`; these are present/display ownership tests, not interior chrome owner tests, but they cover snapshots containing scrollbar/tab labels at `app/present.zig:11-16`, `app/present.zig:37-52`.
- No direct tests were observed in `links.zig` or `selection.zig`; their behavior is only indirectly covered through context/input and VT-surface hover decoration tests.

## Imports And Likely Allowed Files For First Extraction

- `context.zig` imports chrome-adjacent owners already split out: `links.zig`, `cursor_blink.zig`, `scrollbar.zig`, and `selection.zig` at `context.zig:29-33`.
- `links.zig` depends on host selection outcome, VT retained hyperlink lookup, VT-surface hover decoration type, window cursor/URL operations, host input, and terminal link config at `links.zig:1-7`.
- `selection.zig` depends on VT retained selection operations and host input at `selection.zig:1-2`.
- `scrollbar.zig` depends on `std`, `EventLoop`, display layout, host input, and VT retained scroll state at `scrollbar.zig:1-5`.
- `cursor_blink.zig` depends only on `std` at `cursor_blink.zig:1-4`.
- `vt/input.zig` owns VT input encoding and PTY publication bridge with imports at `vt/input.zig:1-6`; this is input consequence code, not interior chrome state.
- `vt/surface.zig` owns VT-to-render source publication and hover decoration application with imports at `vt/surface.zig:1-4`; this is VT-surface truth/render-source bridge, not host chrome state.
- `render/surface_layout.zig` imports PTY session, render retained, VT retained, and terminal scrollbar at `surface_layout.zig:1-7`; resize invalidates scrollbar at `surface_layout.zig:77`.
- `display/layout.zig` defines `Rect`, `ScrollbarLayout`, `Frame`, content rect/size helpers, and content-relative event conversion at `display/layout.zig:3-32`, `display/layout.zig:34-78`.
- A first extraction, if implemented later, would likely be limited by current imports to `terminal/context.zig`, `terminal/scrollbar.zig`, `terminal/links.zig`, `terminal/selection.zig`, `terminal/cursor_blink.zig`, `terminal/vt/surface.zig` only for `HyperlinkHover` type use, `terminal/render/surface_layout.zig` only for scrollbar invalidation call, `display/layout.zig` only for existing layout types and content-relative event helper, `main.zig` only where active title/focus/input/overlay entrypoints are called, and `app/present.zig` only if snapshot type wiring changes. This is an observed dependency boundary, not an architecture proposal.

## Must Not Move In A Chrome Extraction

- PTY lifecycle and transport stay with PTY/session/runtime paths: `init` starts runtime after term init at `context.zig:120-144`; `deinit` stops wait thread/session/feed/render/vt handles at `context.zig:174-196`; `startRuntime` starts feed record, PTY session, wait thread, and focus sync at `context.zig:462-474`; `driveProgress` calls `pty_pump.driveOnce`, wake ack, and clipboard writes at `context.zig:379-391`.
- PTY input publication and VT input encoding are not chrome ownership: `publishTerminalBytes`, `publishTerminalKey`, and `publishTerminalMouse` are at `context.zig:908-935`; VT input publish/encode functions are at `vt/input.zig:95-228`; `publishFocus` is VT focus consequence at `vt/input.zig:120-126`.
- Render-surface submit and host resource realization must not move into interior chrome: `renderTurn`, present submit accounting, and render work state are at `context.zig:394-437`; backend upload/realize/texture ensure/upload commands are at `context.zig:591-760`; submit protocol is at `context.zig:762-854`; current slice explicitly says display/renderer owns render-surface host resource realization and presentation, not window chrome, at `current.txt:41-56`, non-goals at `current.txt:58-64`, grep gates at `current.txt:80-87`.
- Display renderer ownership must not move: `main.zig` owns `Display.State` in app state at `main.zig:80-89`, initializes it at `main.zig:142-149`, and present submission goes through `AppPresent.submitWith`/display at `main.zig:649-670`; `app/present.zig` submits display frames at `app/present.zig:37-52`.
- VT core truth must not move: VT owns title source via `vt_retained.copyCurrentTitle` at `context.zig:302-303`, scroll state via `vt_retained.scrollState` at `scrollbar.zig:298`, `scrollbar.zig:324`, selection truth via `vt_retained.startSelection/updateSelection/finishSelection` at `selection.zig:37-59`, hyperlink lookup via `vt_retained.copyVisibleHyperlinkAt` at `links.zig:58`, `links.zig:101`, VT source publication and ack via `vt/surface.zig:58-111`, `vt/surface.zig:150-157`.

## Stop Conditions And Readiness

- Stop if an extraction needs a public C ABI change; AGENTS says C ABI only is non-negotiable at `AGENTS.md:9-18`, and `current.txt` non-goals forbid public C ABI changes at `current.txt:58-61`.
- Stop if extraction would move PTY lifecycle, child I/O, resize delivery, control signals, or transport state out of PTY ownership; owner rules list PTY ownership at `AGENTS.md:128-136`.
- Stop if extraction would move VT parser/state/selection/input encoding/protocol consequences/VT-surface truth out of VT ownership; owner rules list VT ownership at `AGENTS.md:130-132`.
- Stop if extraction would move render contracts, geometry policy, retained-frame state, prepare/submit scheduling, render-surface contracts, or text shaping out of render ownership; owner rules list render ownership at `AGENTS.md:132-134`.
- Stop if extraction creates a generic bucket owner or `Context`/`State` wrapper without owner proof; AGENTS rejects generic buckets and fake owner names at `AGENTS.md:138-156`, and loop hard-stops generic aliases/umbrella owners at `loop.txt:243-258`.
- Stop if tests would be weakened, duplicated, filtered, or moved to a second entrypoint; test rules are at `AGENTS.md:158-164`, and current slice stop conditions include test weakening/moving at `current.txt:89-96`.
- Readiness: current code has enough line-backed inventory to identify non-PTY/non-render-surface terminal chrome-adjacent state and methods, but this cache intentionally does not choose a new owner name or architecture. A worker would still need an orchestrator-promoted current slice with exact owner name, allowed files, required shape, tests, and grep gates before product-code edits.
