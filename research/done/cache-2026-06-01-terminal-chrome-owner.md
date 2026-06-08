# Terminal Chrome Owner Research Cache

## Date

2026-06-01

## Sources Read

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `AGENTS.md`
- `loop.txt`
- `current.txt`
- `howl-linux-host/src/terminal/context.zig`
- `howl-linux-host/src/terminal/scrollbar.zig`
- `howl-linux-host/src/terminal/links.zig`
- `howl-linux-host/src/terminal/selection.zig`
- `howl-linux-host/src/terminal/cursor_blink.zig`
- `howl-linux-host/src/terminal/vt/input.zig`
- `howl-linux-host/src/terminal/vt/surface.zig`
- `howl-linux-host/src/display/layout.zig`
- `howl-linux-host/src/app/present.zig`
- `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/event.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/input/mod.rs`
- `utils/dev_references/terminals/alacritty/alacritty_terminal/src/selection.rs`

Ghostty was not read for this cache because Alacritty supplied the host/display/window/input/presentation boundary requested by source order. Ghostty may be useful later for VT-core selection or embedding surface questions, but not for naming a Linux host terminal UI owner.

## Question

User direction: create an interior terminal chrome owner for things that are not render surfaces and not PTY. Interpret this as terminal/UI-adjacent host behavior such as title/focus/link hover/selection/scrollbar/cursor blink/overlays/input adaptation only if source-backed. Do not implement.

## TigerBeetle Gates

- `TIGER_STYLE.md:90-100` requires simple bounded control flow and explicit limits.
- `TIGER_STYLE.md:104-140` requires assertions on arguments, preconditions, postconditions, invariants, and positive/negative space.
- `TIGER_STYLE.md:158-175` requires small variable scope and centralized state mutation.
- `TIGER_STYLE.md:179-183` says the program runs at its own pace rather than doing arbitrary work directly in reaction to external events.
- `AGENTS.md:138-156` rejects fake owners, generic buckets, `manager`, `engine`, `controller`, `utils`, `types.zig`, and bucket structs named `Context`, `State`, `Options`, `Config`, `Info`, `Data`, `Result`, or `Diagnostics` unless source-backed and owner-true.
- `AGENTS.md:185-213` and `loop.txt:22-50` make Alacritty the source of truth for host runtime, display, window, input, presentation, and most renderer organization unless it fights the C ABI/product boundary.

## Current Slice Interaction

- `current.txt:1-18` is an active display/renderer/window chrome integration slice, not this terminal interior UI split.
- `current.txt:41-56` already moves render-surface consumption to `display/renderer/*` and restricts `window_chrome/*` to window wrapper/chrome behavior.
- `current.txt:58-65` forbids public C ABI changes, compatibility aliases, renderer modernization, test weakening, and generic bucket owners.
- This cache should not be promoted directly while that slice is active unless the orchestrator rewrites `current.txt`; it is research evidence for a later cut.

## Alacritty Match For Interior Terminal Chrome

- Alacritty does not have a file, module, or symbol named `chrome`, `terminal_chrome`, `ui`, or `overlay` for this boundary in the assigned sources.
- The closest source-backed concept is Alacritty `Display`, whose module doc says it includes window management, font rasterization, and GPU drawing at `display/mod.rs:1-2`, and whose struct owns terminal-adjacent UI state such as highlighted hints, cursor hidden state, visual bell, colors, hint state, IME, frame timer, damage tracker, font size, and hint mouse point at `display/mod.rs:341-400`.
- `Display::draw` consumes terminal content and draws terminal-adjacent UI consequences: renderable content at `display/mod.rs:775-793`, terminal damage and selection damage at `display/mod.rs:803-834`, hint underline overlay at `display/mod.rs:841-879`, vi/search line indicators at `display/mod.rs:883-893`, cursor rects at `display/mod.rs:895-897`, visual bell at `display/mod.rs:898-910`, search bar at `display/mod.rs:912-949`, IME preview at `display/mod.rs:951-962`, message bar at `display/mod.rs:964-1009`, hyperlink preview at `display/mod.rs:1013-1017`, frame request at `display/mod.rs:1040-1047`, and helper drawing for hyperlink preview/search/line indicator at `display/mod.rs:1242-1377`.
- Alacritty input/UI event adaptation is not in `Display`; it is split through `WindowContext` and `ActionContext`. `WindowContext` stores display, terminal, cursor blink timeout, modifiers, search state, notifier, mouse, touch, occlusion, preserve-title, PTY fd/pid, config, and dirty state at `window_context.rs:47-70`.
- `WindowContext::handle_event` batches queued events, builds `ActionContext`, processes input events, handles pending display update, updates highlighted hints, and requests redraw only when dirty and frame-eligible at `window_context.rs:400-493`.
- `event.rs` defines `ActionContext` as the host adapter over terminal, clipboard, mouse/touch/modifiers, display, message buffer, config, cursor blink timeout, scheduler, search states, dirty, occlusion, title preservation, and PTY identity at `event.rs:663-688`.
- Alacritty `input/mod.rs` defines `ActionContext` trait methods for PTY writes, dirty marking, size info, selection, mouse/touch/modifiers, scroll, window, display, terminal, font size, messages, search, hints, terminal input start, paste, and spawning at `input/mod.rs:82-147`.
- Alacritty mouse state is a separate host-input state shape: button states, click state, accumulated scroll, cell side, hint launcher block, hint highlight dirty flag, inside-text-area flag, and x/y at `event.rs:1766-1800`, with pixel-to-grid conversion at `event.rs:1804-1818`.
- Alacritty terminal-core selection remains in `alacritty_terminal/src/selection.rs`: selection state management is documented at `selection.rs:1-7`, `SelectionRange` is at `selection.rs:31-47`, and `Selection` owns typed range state at `selection.rs:91-130`. Host mouse adaptation into selection lives in `input/mod.rs:617-723` and `event.rs:760-809`, not in the selection core file.

## Name Decision

- Reject `terminal/chrome.zig`: no Alacritty concept/file/symbol uses `chrome` for terminal interior UI. Howl already has `window_chrome`, and `current.txt:50-51` confines it to chrome/window-wrapper/icon behavior. Reusing `chrome` for terminal interior behavior would blur the accepted window-chrome boundary.
- Reject `terminal/display.zig`: Alacritty's `Display` is not terminal-only chrome; it wraps the window, renderer, GL surface/context, glyph cache, frame timer, damage tracker, IME, hints, visual bell, and actual drawing at `display/mod.rs:341-400`. In Howl, render-surface consumption and presentation are already moving to `src/display/*` by `current.txt:43-49`. A `terminal/display.zig` would fight the display owner and likely become a fake parallel display.
- Reject `terminal/ui.zig`: Alacritty has UI config (`UiConfig`) but no `ui` owner for this boundary in the assigned files. `ui` is too broad and would invite a bucket for title/focus/link/selection/scrollbar/cursor blink/overlays/input.
- Reject `terminal/overlay.zig`: Alacritty draws multiple overlays/effects inside `Display::draw` (`message_bar`, `search`, hyperlink preview, visual bell, line indicator), but does not name a general overlay owner. In Howl, `Context.OverlaySnapshot` currently only wraps scrollbar layout at `terminal/context.zig:60-62` and `overlaySnapshot` delegates to `terminal_scrollbar.layout` at `terminal/context.zig:275-278`; a general `overlay` file would be broader than current facts.
- Source-backed closest name for the first cut is not a new umbrella owner. Use existing exact owners and, if a unifying adapter must be cut later, prefer `terminal/input.zig` only for terminal host input adaptation because Alacritty has `input/mod.rs` and `ActionContext` for this behavior at `input/mod.rs:1-7`, `input/mod.rs:73-80`, and `input/mod.rs:82-147`.
- If the orchestrator insists on one interior terminal chrome owner, stop: sources do not establish a non-bucket name that can own title, focus, link hover, selection, scrollbar, cursor blink, overlays, and input adaptation together. The source-backed shape is a split: `display` owns drawing/UI presentation state; `input`/`ActionContext` owns event adaptation; terminal-core selection remains terminal-owned; small Howl owner files keep `links`, `selection`, `scrollbar`, and `cursor_blink` separate.

## Current Howl Facts

- `terminal/context.zig` currently aggregates PTY, VT, render, display, input, title, focus, scrollbar, link hover, selection, hover publish, and cursor blink state in `Context` at `terminal/context.zig:85-108`.
- Title cache is host-side terminal title adaptation: `title_buf` and `title_len` live at `terminal/context.zig:95-96`, `titleSlice` refreshes and returns it at `terminal/context.zig:297-300`, and `refreshTitle` copies current VT title or falls back to command/shell at `terminal/context.zig:302-307`.
- Focus adaptation is host-side terminal/UI behavior: `window_focused` and `widget_focused` live at `terminal/context.zig:100-101`; `setWindowFocused` clears hover, updates scrollbar focus, and publishes input focus at `terminal/context.zig:310-316`; `setWidgetFocused` does the same for widget focus at `terminal/context.zig:318-324`; `syncInputFocus` publishes `window_focused and widget_focused` to VT input at `terminal/context.zig:326-328`.
- Link hover state is currently split but mostly in `terminal/links.zig`: `link_cursor_active`, `hovered_link_cell`, and `hover_publish_pending` are in `Context` at `terminal/context.zig:103-107`; `links.zig` owns `HoveredLinkCell` at `links.zig:9-12`, mouse handling at `links.zig:14-30`, clearing hover/cursor at `links.zig:32-36`, hover decoration at `links.zig:38-46`, cursor sync at `links.zig:85-98`, and opening links at `links.zig:100-105`.
- Selection host mouse adaptation is already a separate owner: `selection_anchor` and `selection_drag_active` are in `Context` at `terminal/context.zig:105-106`; `selection.zig` owns `MouseHandlingOutcome` at `selection.zig:4-7`, `SelectionCell` at `selection.zig:9-12`, mouse selection behavior at `selection.zig:14-67`, and pixel-to-cell conversion for selection at `selection.zig:69-76`.
- Scrollbar is already a separate terminal UI owner: `scrollbar.State` is in `Context` at `terminal/context.zig:102`; `scrollbar.zig` owns model/view/result/state at `scrollbar.zig:14-43`, focus invalidation at `scrollbar.zig:44-54`, passive hover wake at `scrollbar.zig:56-60`, cached layout at `scrollbar.zig:62-89`, mouse handling at `scrollbar.zig:91-138`, geometry at `scrollbar.zig:171-193`, track/thumb helpers at `scrollbar.zig:195-225`, and focus hover calculation at `scrollbar.zig:227-240`.
- Cursor blink is already a separate timing owner: `cursor_blink.State` is in `Context` at `terminal/context.zig:108`; `cursor_blink.zig` defines interval constants at `cursor_blink.zig:3-4`, state at `cursor_blink.zig:6-44`, plan result at `cursor_blink.zig:46-50`, deadline calculation at `cursor_blink.zig:52-54`, and an owner-local test at `cursor_blink.zig:56-62`.
- VT input publication remains separate from host UI adaptation: `vt/input.zig` maps keys/modifiers/mouse kinds/buttons at `vt/input.zig:27-93`, publishes paste/key/mouse/focus at `vt/input.zig:95-126`, probes unpressed motion and mouse reporting at `vt/input.zig:128-172`, and encodes bytes via the VT C ABI at `vt/input.zig:174-228`.
- VT surface publication is render-source/VT boundary, not interior chrome. It accepts optional hyperlink hover decoration at `vt/surface.zig:58-66`, applies it while acquiring visible content at `vt/surface.zig:68-82`, writes cursor visibility/blink truth back into retained VT state at `vt/surface.zig:82-86`, and commits through `howl_render_text_session_commit_vt_surface` at `vt/surface.zig:127-148`.
- `display/layout.zig` owns generic display layout structs and functions, including `ScrollbarLayout` at `display/layout.zig:15-23`, `Frame` at `display/layout.zig:25-32`, content rect/size at `display/layout.zig:34-56`, and content-relative event scaling at `display/layout.zig:68-78`. This is display geometry, not terminal interior UI state.
- `app/present.zig` owns app/display presentation reason and submission plumbing, not terminal chrome. `Snapshot` includes `scrollbar` as part of display frame input at `app/present.zig:11-16`; `submitWith` forwards frame data to display at `app/present.zig:37-52`; tests cover present reason/submission behavior at `app/present.zig:96-232`.

## Map From `terminal/context.zig` To True Owners

- Keep PTY/session/progress fields out of this chrome question: `term`, `progress`, `live`, PTY session snapshots, lifecycle, and `driveProgress` are PTY/per-terminal integration concerns at `terminal/context.zig:85-87`, `terminal/context.zig:281-295`, and `terminal/context.zig:379-392`.
- Keep render-surface fields out of this chrome question: `term_texture`, `render_surface_textures`, render-surface debugging, `wantsRenderTurn`, `renderTurn`, submit/upload, present submitted/complete, and `termTextureId` are render/display integration concerns at `terminal/context.zig:88-91`, `terminal/context.zig:345-347`, `terminal/context.zig:394-439`, and `terminal/context.zig:587-804`.
- `conf`, `input`, and `event_loop` are dependencies injected into the per-terminal integration owner at `terminal/context.zig:92-94`; they should not move into a chrome bucket.
- `title_buf` and `title_len` at `terminal/context.zig:95-96` need a narrow title adapter if moved. Source-backed behavior is Alacritty terminal title event handling in `event.rs:1867-1878`, not a broad chrome owner.
- `window_focused` and `widget_focused` at `terminal/context.zig:100-101` need narrow focus adaptation if moved. Source-backed behavior is Alacritty focus handling and cursor blink/focus report in `event.rs:1985-2003` and `input/mod.rs:830-837`.
- `scrollbar` at `terminal/context.zig:102` should remain owned by `terminal/scrollbar.zig`; only the field currently sits in `Context` because it is per-terminal state.
- `link_cursor_active`, `hovered_link_cell`, and `hover_publish_pending` at `terminal/context.zig:103-107` should be moved toward `terminal/links.zig` and/or a VT-source publication adapter, not a new umbrella. Alacritty source-backed analogue is hint/highlight state in `Display` at `display/mod.rs:347-355`, hover update at `display/mod.rs:1056-1125`, and cursor state/input updates at `input/mod.rs:969-1113`.
- `selection_anchor` and `selection_drag_active` at `terminal/context.zig:105-106` should remain owned by `terminal/selection.zig` host selection adaptation. The terminal-core selection truth remains in `howl-vt`/VT retained paths, matching Alacritty's split between `input/mod.rs:617-723`, `event.rs:760-809`, and `alacritty_terminal/src/selection.rs:1-130`.
- `cursor_blink` at `terminal/context.zig:108` should remain owned by `terminal/cursor_blink.zig`; the `Context` methods `syncCursorBlinkCadence`, `resetCursorBlinkActivity`, `nextCursorBlinkWaitMs`, `cursorBlinkShouldAnimate`, `setCursorBlinkVisible`, and `setRenderCursorBlinkVisible` at `terminal/context.zig:349-364` and `terminal/context.zig:489-507` are the candidate move surface.
- `overlaySnapshot` at `terminal/context.zig:275-278` is currently only a display frame adapter over scrollbar layout. Do not create `terminal/overlay.zig` until there is more than scrollbar and a source-backed owner name.
- `drainTextInputFastPath`, `drainPointerAndUiInput`, `handleTextInputFastPathEvent`, and `handlePointerAndUiInputEvent` at `terminal/context.zig:219-255` and `terminal/context.zig:1206-1278` are the strongest candidate for `terminal/input.zig` because Alacritty has `input/mod.rs` as the event-adaptation owner.

## Existing Owners That Should Remain Separate

- `terminal/links.zig` should remain separate. It has a true owner noun and owns link hover/open/cursor consequences at `links.zig:9-128`. Do not merge it into `chrome` or `ui`.
- `terminal/selection.zig` should remain separate. It owns host mouse adaptation for selection at `selection.zig:4-76`, while terminal selection truth remains below the VT boundary.
- `terminal/scrollbar.zig` should remain separate. It owns scrollbar model/state/layout/input at `scrollbar.zig:14-253` and is not just an overlay.
- `terminal/cursor_blink.zig` should remain separate. It owns cursor blink timing/planning at `cursor_blink.zig:3-54` with a local test at `cursor_blink.zig:56-62`.
- `terminal/vt/input.zig` should remain separate. It owns VT input encoding/publication across the C ABI at `vt/input.zig:27-228`; host input adaptation may call it but must not absorb it.
- `terminal/vt/surface.zig` should remain separate. It owns VT visible-source publication into render at `vt/surface.zig:58-148`, not terminal UI/chrome.
- `display/layout.zig` should remain display geometry. `ScrollbarLayout` at `display/layout.zig:15-23` is a display frame data shape, not the terminal scrollbar state owner.
- `app/present.zig` should remain app presentation plumbing; it only carries a snapshot containing scrollbar layout at `app/present.zig:11-16` and submits display frames at `app/present.zig:37-52`.

## First Worker-Ready Cut Proposal

Readiness: conditional. A single `terminal/chrome.zig`/`terminal/ui.zig` owner is not source-backed and must not be promoted. The first worker-ready cut should instead be a source-backed terminal input adapter extraction.

Allowed files:

- `howl-linux-host/src/terminal/context.zig`
- `howl-linux-host/src/terminal/input.zig`
- `howl-linux-host/src/test/host.zig` or the existing single host test entrypoint only if import wiring is required by the module's current test structure.

Required moves:

- Add `terminal/input.zig` as the terminal host input adaptation owner, source-backed by Alacritty `input/mod.rs`.
- Move only pure input-adaptation functions and tiny local data shapes from `terminal/context.zig`: `DrainInputOutcome`, `MouseHandlingOutcome` alias if still needed, `drainTextInputFastPathWith`, `drainPointerAndUiInputWith`, `handleTextInputFastPathEvent`, `handlePointerAndUiInputEvent`, `mergeDrainInputOutcome`, `ScrollMouseOutcome`, `ScrollVisualState`, and `ContextOps` methods that adapt host input to scrollbar/selection/link/VT publication.
- Keep public `Context.drainTextInputFastPath`, `Context.drainPointerAndUiInput`, `Context.handleScrollInput`, `Context.wantsLinkHover`, `Context.wantsTerminalHoverReporting`, and `Context.syncInputFocus` as thin calls only if callers require the current `Context` API for this cut.
- Do not move title, focus fields, link state fields, selection fields, scrollbar field, cursor blink state, or render/PTY behavior in this first cut.
- Do not move `vt/input.zig`; `terminal/input.zig` calls it through existing `Context` methods or a narrow ops table.
- Preserve the current two-phase input drain behavior: text fast path compacts mouse events first at `terminal/context.zig:223-243`, then pointer/UI drain processes mouse events at `terminal/context.zig:249-255`.
- Preserve pointer/UI order from `handlePointerAndUiInputEvent`: scrollbar first, content-relative clipping, wheel VT-or-scroll fallback, selection, link, host-only hover clear, VT mouse publish at `terminal/context.zig:1226-1278`.

Required tests:

- Preserve the existing context tests covering text fast path and pointer UI drain at `terminal/context.zig:1423-1648` and `terminal/context.zig:1650-1705`; move them only if the single module test entrypoint still reaches them.
- Add no duplicate test root. If tests move to `terminal/input.zig`, ensure the existing host test entrypoint imports that owner exactly once.
- Add/keep assertions around bounded queue compaction: read/write indexes stay within `input_events.len` and ring buffer length, matching TigerBeetle assertion requirements.

Verification commands:

- From `howl-linux-host`: `zig build check`
- From `howl-linux-host`: `zig build test --summary all`
- From `howl-linux-host`: `zig build -Doptimize=ReleaseFast`
- From workspace root: `git diff --check`
- From workspace root: tracked `.zig` line scan reports zero lines over 190 chars.

Grep gates:

- No file named `howl-linux-host/src/terminal/chrome.zig`.
- No file named `howl-linux-host/src/terminal/ui.zig`.
- No file named `howl-linux-host/src/terminal/overlay.zig` for this cut.
- No new `manager`, `engine`, `controller`, `utils`, or `types.zig` owner.
- `terminal/input.zig` must not import `howl_pty_c`, `howl_render_c`, `../display/renderer/render_surface.zig`, or `../app/present.zig`.
- `terminal/input.zig` must not call `ensureSurface`, `uploadRenderSurface*`, `submitPrepared*`, `renderTurn`, `driveProgress`, `pty_session.start`, or `pty_session.stop`.
- No public C ABI files change.
- `terminal/links.zig`, `terminal/selection.zig`, `terminal/scrollbar.zig`, `terminal/cursor_blink.zig`, and `terminal/vt/input.zig` remain as separate owner files.

Stop conditions:

- Stop if the worker must choose between `chrome`, `display`, `ui`, `overlay`, or another broad name.
- Stop if the extraction requires a bucket struct that groups title/focus/link/selection/scrollbar/cursor blink/overlays/input.
- Stop if moving input adaptation requires changing PTY, VT, or render C ABI contracts.
- Stop if tests need weakening, filtering, a duplicate root, or import-only coverage.
- Stop if title/focus/cursor blink/overlay movement becomes necessary to make the input extraction compile.
- Stop if render-surface upload, present pacing, GL texture ownership, or PTY lifecycle enters `terminal/input.zig`.

## Risks And Proof Gaps

- Naming proof gap: Alacritty does not support `terminal/chrome.zig`, `terminal/ui.zig`, or `terminal/overlay.zig`. A broad interior chrome owner would be Howl-only invention and likely a bucket owner.
- Source-backed path exists for only a narrower first cut: `terminal/input.zig` as terminal host input adaptation, backed by Alacritty `input/mod.rs` and `ActionContext`.
- Title/focus/cursor blink have Alacritty source-backed behaviors, but not a shared owner name. Title handling is in terminal event processing at `event.rs:1867-1878`; focus handling is in window event/input processing at `event.rs:1985-2003` and `input/mod.rs:830-837`; cursor blink scheduling is in `event.rs:1620-1671` and blink events at `event.rs:1846-1861`.
- Overlay proof gap: Alacritty draws search/message/hyperlink preview/visual bell/line indicator in `Display::draw`, not in an overlay owner. Howl currently has only scrollbar overlay snapshot data at `terminal/context.zig:60-62` and `terminal/context.zig:275-278`.
- Scrollbar proof gap: Alacritty assigned sources do not show a scrollbar owner for terminal scrollback; Howl's scrollbar is product-specific terminal UI. Keeping `terminal/scrollbar.zig` separate is safer than hiding it under a broad owner.
- Test gap: `terminal/links.zig`, `terminal/selection.zig`, and `terminal/scrollbar.zig` have no owner-local tests in the read files; existing coverage is mostly through `terminal/context.zig` input-adapter tests.
- Readiness judgment: ready to plan a narrow `terminal/input.zig` extraction; not ready to create an interior terminal chrome owner named `chrome`, `display`, `ui`, or `overlay`.
