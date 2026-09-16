# Howl Odin desktop experience charter

This is the living user-experience map for the experimental Odin desktop client.
It is deliberately not a release schedule and not a second architecture document.

`README.md` says what the client can prove **today**. Cairn records bounded work
and receipts. This file says what kind of desktop terminal application we are
trying to make and what experiences are worth pressure-testing next.

## North star

Build a polished, Windows-familiar desktop terminal shell that disappears into
ordinary work while keeping Howl's terminal truth singular.

A Windows Terminal user should understand the application immediately: tabs,
panes, profiles, a profile menu, command palette, settings, familiar keyboard
navigation, and restrained desktop chrome. Familiarity is a UX reference, not a
requirement to clone Microsoft's pixels, configuration format, internals, or
limitations.

Howl remains the terminal. Odin owns the desktop application around it.

## Status vocabulary

- **PROVEN** — exercised through the real Howl path with durable tests or a
  physical/nested desktop canary.
- **ACTIVE** — implemented enough to dogfood, but still under deliberate
  pressure or missing important edge behavior.
- **WANTED** — part of the intended ordinary desktop experience; implementation
  order is deliberately flexible.
- **EXPLORE** — potentially valuable, but should earn its complexity through use.

These labels are descriptive, not priority scores.

## Product rules

1. **One terminal truth.** Odin does not parse VT, generate escape sequences,
   own terminal history, shape terminal text, or invent terminal image rules.
   Those stay in the existing Howl owners.
2. **Desktop policy stays local.** Windows, tabs, panes, profile recipes,
   selection chrome, clipboard policy, settings, keybindings, and OS integration
   belong to the desktop client.
3. **Familiar before clever.** Common terminal gestures should behave the way an
   experienced desktop-terminal user expects unless Howl has a concrete reason
   to differ.
4. **Idle means idle.** An unchanged terminal should sleep. Work should be driven
   by Session revisions, UI events, or real timers that own visible behavior.
5. **No fake settings.** A setting appears when it changes a real client contract.
   Unsupported options are named honestly instead of being decorative toggles.
6. **Pane-local by default.** History, selection, focus, geometry leadership,
   mouse ownership, and process lifetime should not leak between sibling panes.
7. **Failures should explain themselves.** Exited shells, lost Sessions, missing
   resources, unsupported terminal images, or invalid configuration should have
   a visible, recoverable desktop story.
8. **Dependencies must buy something.** Prefer Odin, SDL3, Howl's existing
   modules, and small native seams over a general UI framework unless a concrete
   experience earns the larger dependency.

## Experience inventory

### 1. Launch, window, and first-run behavior

**PROVEN**

- Opens as a normal resizable high-DPI desktop window.
- Startup profile is persistent and may either attach Home Session or create a
  client-owned Local shell Session.
- Window rendering and pointer geometry share one logical coordinate system.
- Maximizing/resizing drives owned PTY geometry without resizing attached
  observer-only Sessions.

**WANTED**

- Remember useful window geometry without restoring a broken/off-screen layout.
- Proper maximize, fullscreen, minimize, multi-monitor, DPI-change, and
  display-hotplug dogfood coverage.
- Explicit startup choices: default profile, attach a named Session, or restore
  an accepted previous application layout.
- Graceful second-instance behavior and a deliberate multi-window policy.
- Native app identity/icon/package metadata instead of permanent “canary” chrome.

**EXPLORE**

- Quake/drop-down summon mode.
- Tab tear-out into another window and cross-window tab movement.

### 2. Tabs

**PROVEN**

- Create, select, close, and cycle tabs.
- `+` and `Ctrl+T` use the configured default profile.
- Explicit profile menu can always choose Local shell or Home Session.
- Closing a client-owned tab retires its owned Session; closing an attached view
  only disconnects that view.

**WANTED**

- Reorder tabs with mouse and keyboard.
- Direct numeric tab shortcuts and MRU switching behavior.
- Titles derived from profile/session/application title with sane truncation.
- Activity/bell/attention indication that does not become a flashing dashboard.
- Duplicate tab/profile recipe.
- Reopen recently closed client-owned tab when its Session still exists or the
  launch recipe is safely repeatable.
- Tab context menu with the same action registry as the command palette.

### 3. Panes and layout

**PROVEN**

- One real two-pane split with independent Session/view ownership.
- Pane-local focus, close/promote behavior, clipping, history, selection, and
  geometry leadership.
- Surviving pane reacquires full-tab geometry without restarting its Session.

**WANTED**

- Horizontal and vertical split actions.
- Recursive pane tree rather than the current fixed primary/secondary pair.
- Keyboard and pointer pane-resize handles.
- Focus movement in four directions.
- Zoom/maximize active pane without destroying layout.
- Swap/move panes and preserve their Session identities.
- Split with a chosen profile instead of only the current default.
- Layout persistence only after lifecycle semantics are boring and exact.

### 4. Profiles

**PROVEN**

- Local shell means “create and own a sibling `howl-sessiond` + PTY”.
- Home Session means “attach another non-owning client view”.
- One persisted default profile drives startup, `+`, `Ctrl+T`, and split creation.
- Owned Local shells inherit the real desktop process environment.

**WANTED**

- Named user profiles with command/shell, working directory, environment edits,
  icon, optional color accent, and attach-vs-create policy.
- Profile defaults plus per-profile overrides.
- Duplicate/edit/delete flows with explicit built-in vs user-owned distinction.
- Launch profile from command palette and profile menu.
- Working-directory inheritance when splitting or duplicating where the canonical
  child/session contract can support it honestly.
- Import/export of user profile configuration without inventing compatibility
  with Windows Terminal's JSON format.

**EXPLORE**

- Platform/profile discovery such as installed shells, WSL, SSH recipes, or
  containers. Discovery should not become implicit remote/network policy.

### 5. Ordinary terminal input

**PROVEN**

- Committed UTF-8 text.
- Named and Unicode physical keys.
- Enter, Backspace, Delete, arrows, Tab, modifier chords, and ordinary control
  input through `howl-client.actions`.
- Semantic paste preserves VT-owned bracketed-paste behavior.
- Neovim and btop alt-screen open/input/exit canaries.

**WANTED**

- Full desktop IME/composition path, not only committed text.
- Focus in/out reporting through canonical interaction state.
- Repeat/key-up behavior dogfood under applications that request it.
- Keyboard-layout and dead-key coverage.
- Explicit handling of application shortcuts versus terminal shortcuts, with no
  modifier-only keypress side effects.

### 6. Mouse and pointer arbitration

**ACTIVE**

- With terminal mouse tracking absent, primary drag belongs to local selection
  and the wheel belongs to local scrollback.
- Scrollbar owns only its narrow hit lane; terminal text selection owns the rest.

**WANTED**

- Observe canonical interaction state and route click/move/drag/wheel to
  applications when mouse tracking is enabled.
- Preserve local selection as an explicit Shift+drag override.
- Preserve local scrollback as an explicit Shift+wheel override where terminal
  mouse/alternate-scroll modes would otherwise consume the wheel.
- DEC alternate-scroll behavior through semantic keys, not client escape bytes.
- Pointer shape/visibility policy from canonical pointer mode where supported.
- Focus reporting on actual desktop focus changes.
- Neovim, btop, tmux, less, and mouse-aware TUI pressure canaries.

### 7. Scrollback and history

**PROVEN**

- Pane-local canonical retained-history observation.
- Physical wheel scrolling.
- Shift+PageUp/PageDown page navigation.
- Ctrl+Shift+Home to oldest retained row and Ctrl+Shift+End to LIVE.
- Absolute retained-row anchor keeps an old viewport stationary while new PTY
  output arrives.
- Bounded-ring eviction advances only when the anchored rows actually leave the
  retained ring.
- Alternate-screen entry and terminal input return the affected pane to LIVE.
- Thin per-pane scrollbar indicates retained position.
- Scrollbar supports direct seek and thumb drag with a forgiving invisible hit
  lane while preserving quiet visual chrome.
- Scrollbar drag owns SDL pointer capture, including outside-window motion; a
  release, focus loss, or window close ends the gesture so later pointer motion
  cannot strand the pane in drag state.
- Vertical-only resize preserves the top retained row.
- Horizontal reflow/column change deliberately returns an owned scrolled pane to
  LIVE because projected row identity is not stable across reflow.
- Ten executable Odin history/scrollbar tests run in the owner build.

**ACTIVE**

- Continue resize, font-zoom, split/collapse, live-output, oldest-ring, and
  multi-pane pressure without weakening the reflow safety rule.

**WANTED**

- Search retained history from the desktop UI.
- Next/previous result navigation and visible result highlighting.
- Search while output continues without dragging the viewport unexpectedly.
- Selection edge-autoscroll while dragging beyond the visible top/bottom.
- A future cross-reflow anchor only if Session/VT gains a stable logical-line
  identity that can name the same text after column reflow. Do not fake this
  with row-number heuristics.

### 8. Selection and clipboard

**PROVEN**

- Pane-local primary drag paints selection chrome.
- Ctrl+Shift+C asks `howl-client.selection` and Session `text_extract` for
  canonical UTF-8; it does not scrape rendered glyphs.
- Selection copy works from LIVE and anchored scrollback.
- Ctrl+Shift+V uses semantic paste.
- Geometry, scrolling, and terminal mutation reject stale selection rather than
  silently retargeting it.

**WANTED**

- Double-click canonical word selection.
- Triple-click/hard-line selection if it remains unsurprising with soft wraps.
- Selection edge-autoscroll.
- Drag endpoints across scrollback while keeping canonical stable coordinates.
- Copy action in context menu/command palette and useful disabled-state feedback.
- Linux middle-click/primary-selection behavior only if it remains distinct from
  the normal clipboard and can be implemented without platform confusion.

### 9. Search and navigation

**WANTED**

- `Ctrl+Shift+F` search surface over retained canonical text.
- Plain-text search first; case sensitivity and regex only when their behavior is
  clear and bounded.
- Search results survive normal new output when their retained rows survive.
- Command-palette actions for oldest/LIVE, next/previous result, pane focus,
  profile launch, and layout operations.
- Clickable URL/hyperlink navigation using canonical hyperlink facts rather than
  regex-only guesses when available.

### 10. Alternate-screen and full-screen applications

**PROVEN**

- Neovim alt-screen lifecycle.
- btop full-screen lifecycle and repaint.
- 1049 saved-cursor resize/reflow backend fix exercised through the client.

**WANTED**

- Mouse-aware Neovim and btop.
- tmux and zellij pressure.
- `less`, `man`, `fzf`, `yazi`, interactive Git TUIs, and long-running dashboards.
- Repeated enter/exit with resize, split, font zoom, and focus churn.
- No stale history chrome while the alternate screen owns interaction.

### 11. Renderer and visual correctness

**PROVEN**

- Real `howl-render` terminal Content + Canvas Composer.
- SDL consumes Canvas solids, alpha masks, and RGBA resources without terminal
  cell parsing.
- Canvas residency avoids redundant atlas upload on unchanged generations.
- Nerd/Powerline glyphs, ANSI colors, cursor, background, shaping, and HiDPI
  logical geometry are live in the Odin client.

**WANTED**

- Exact terminal-image resource refill/residency path.
- Kitty/image placement pressure and clipping in panes/history where canonical
  semantics permit it.
- Font family selection and fallback policy through Howl text owners.
- Underline/undercurl/style/color pressure corpus.
- Emoji, combining marks, wide glyphs, ligatures/shaping, bidi policy where Howl
  explicitly supports it.
- Renderer backend telemetry hidden behind diagnostics, not normal chrome.

**EXPLORE**

- Direct Vulkan presentation backend if measurements show SDL's renderer is the
  next meaningful performance/control ceiling.

### 12. Appearance

**PROVEN**

- Dark desktop shell.
- JetBrains Mono Nerd Font canary.
- Persistent 12/15/18 px font-size setting.
- Font zoom never mutates an attached non-owning Session.

**WANTED**

- Font family picker with truthful availability/error state.
- Arbitrary sensible font size or a richer bounded preset model.
- Color schemes with live preview and per-profile override.
- Terminal padding.
- Window opacity/acrylic only if the platform backend can do it without visual or
  performance debt.
- Cursor presentation preferences only where they do not override canonical
  terminal-requested semantics unexpectedly.

**EXPLORE**

- Background images and decorative effects. These are dessert, not architecture.

### 13. Settings and configuration

**PROVEN**

- Real navigable Settings surface.
- Startup, Interaction, Appearance, Color schemes, Actions, Profile defaults,
  and Home Session pages.
- Atomic schema-versioned XDG config writes.
- Persistent default profile and font size.

**WANTED**

- Settings search.
- Real controls for profiles, keybindings, color schemes, and appearance.
- Reset-to-default with visible scope.
- Import/export user configuration.
- Validation messages that identify the bad field without discarding unrelated
  valid configuration.
- Settings remain usable entirely by keyboard.

### 14. Command palette, actions, and keybindings

**PROVEN**

- One application action registry feeds command palette and shell actions.
- Keyboard navigation and Enter execution.

**WANTED**

- Fuzzy/filterable command palette.
- All user-facing operations represented as actions rather than duplicated UI
  callbacks.
- Custom keybindings with conflict detection and reset.
- Context-aware disabled actions with a reason when useful.
- Discoverable shortcut display in menus/settings.
- Per-profile actions only when the action genuinely belongs to a profile.

### 15. Session and process lifecycle

**PROVEN**

- Client-created Local shell Session ownership and exact child teardown.
- Attached Home views never kill the underlying Session.
- Independent observer/control connections and explicit blocked-observer
  cancellation.

**WANTED**

- Exited-process UI: preserve final terminal frame, show exit status when known,
  and offer Restart/Close without pretending the shell is still interactive.
- Reconnect UI for temporarily unavailable attached Sessions.
- Recent/pinned attach targets where discovery has an explicit owner.
- “Close tab” versus “terminate process/session” remains an explicit distinction.
- Application shutdown explains what will remain alive and what is client-owned.
- Session title/working-directory facts when canonical APIs support them.

### 16. Desktop/OS integration

**PROVEN**

- Native Wayland window on KDE through SDL3.
- System clipboard via SDL3.
- XDG configuration location.

**WANTED**

- Native app icon, desktop file, install/uninstall packaging, and MIME/URL policy
  where relevant.
- Drag-and-drop file paths/text into the active terminal with quoting policy kept
  explicit.
- Open canonical hyperlinks in the platform browser.
- Audible/visual bell policy and desktop notification integration.
- Window title updates and taskbar/dock attention without noisy animation.
- Sensible multi-monitor placement and restore.

**EXPLORE**

- Default-terminal registration on platforms where that concept exists.
- Windows native packaging once the shell is valuable enough to justify the
  platform work. Windows familiarity does not require waiting for Windows.

### 17. Accessibility

**WANTED**

- Complete keyboard navigation for tabs, panes, menus, palette, and Settings.
- Screen-reader projection from canonical semantic text and application chrome.
- Focus indicators that remain visible without shouting.
- High-contrast/system theme accommodation.
- Reduced-motion behavior if animation is introduced later.
- Pointer hit targets larger than the painted affordance where appropriate, as
  already done for the scrollback thumb.

### 18. Diagnostics and recovery

**WANTED**

- Small About/Diagnostics surface with Howl revision, Odin/Zig versions, SDL
  backend, renderer backend, active profile/session identity, and geometry.
- Copy diagnostics action that excludes secrets and irrelevant environment data.
- Optional frame/revision/performance counters for investigation, invisible in
  ordinary use.
- Clear error state for unsupported image resources, bridge mismatch, Session
  attach failure, renderer failure, and invalid config.
- Recovery actions are explicit; the client does not silently spawn a different
  Session when attach fails.

### 19. Performance and resource behavior

**PROVEN**

- Event-driven presentation loop sleeps between invalidations.
- Quiet Home tab measured at effectively 0.00% of one core over a five-second
  interval on Home.
- Active btop measured about 0.25–0.30% of one core in the Odin client after the
  scheduler fix; btop and `howl-sessiond` cost more than the presentation shell.
- Warm complete Canvas regeneration measured roughly 0.7 ms on the attached Home
  view and roughly 1.9 ms on the larger Local shell during the first renderer
  canary.

**WANTED**

- Preserve near-zero idle CPU as a regression bar.
- Target compositor-smooth 60 FPS presentation during sufficiently fast terminal
  output without blindly repainting at 60 Hz.
- Coalesce Session bursts to newest useful frame rather than render obsolete
  intermediate revisions.
- Measure frame production, Canvas composition, SDL painting, GPU present, and
  Session costs separately.
- Bound retained resources and memory per pane/tab; no accidental unbounded UI
  logs or frame queues.
- Hidden/minimized windows should perform less work, not more.

### 20. Reliability dogfood matrix

A desktop terminal should be judged by boring repeated use, not only unit tests.
The ongoing canary matrix should include:

- shell typing/editing, Unicode, paste, Ctrl/Alt chords;
- thousands of lines of output and 4,096-row retained-ring eviction;
- wheel, page, oldest/LIVE, thumb seek/drag, and live-output anchoring;
- selection/copy/paste in LIVE and HISTORY;
- resize height-only versus width/reflow while scrolled;
- font zoom while scrolled;
- tab and split creation/close while output is active;
- Neovim, btop, tmux/zellij, less/man, fzf, yazi, and at least one mouse-aware
  application;
- maximize/fullscreen/DPI/display transitions;
- shell/process exit, app close/reopen, Session disconnect/reconnect;
- sustained high-output CPU/memory/frame-time measurement.

Canaries should use the physical desktop when platform behavior matters and the
visible managed KWin lab for autonomous iteration that should not disturb normal
work.

## Dependency posture

The Odin application deliberately has a small **direct** dependency surface:

- Odin core libraries;
- Odin's vendor SDL3 and SDL3_ttf bindings;
- `libSDL3` and `libSDL3_ttf` at runtime;
- one app-private `libhowl_odin_bridge.so`;
- the sibling `howl-sessiond` executable for client-owned Sessions;
- libc/libm from the host platform.

The bridge reuses in-tree `howl-client`, `howl-session`, `howl-render`, and the
existing `SessionProcess` owner. Native text rendering dynamically uses the
system FreeType/HarfBuzz stack, which in turn brings normal font/image support
libraries such as zlib, bzip2, libpng, Brotli, GLib, Graphite2, and PCRE2 on the
current Arch machine.

So “almost no dependencies” is fair at the **application architecture** level,
but not literally at the ELF dependency graph level. The important property is
that there is no GTK/Qt/Electron/web runtime/general retained widget framework
between Odin and the desktop. The app shell is ours; terminal semantics are
Howl's; SDL is the narrow platform/rendering substrate.

## Deliberate non-goals

- Do not clone Windows Terminal internals or configuration format.
- Do not move VT, PTY, shaping, history, image, or escape-sequence semantics into
  Odin for convenience.
- Do not add a generic UI framework merely to make Settings faster to build.
- Do not preserve ambiguous scrollback across horizontal reflow by guessing.
- Do not make attached Session lifecycle implicit.
- Do not spend complexity on animation, translucency, or decorative effects
  while ordinary terminal interactions remain rough.
- Do not optimize from folklore: measure the specific owner that is expensive.

## Current near-term pressure lanes

These are intentionally broad and may be worked in whichever order real use
makes interesting:

1. Finish interaction arbitration: canonical mouse/focus modes, Shift overrides,
   scrollbar capture/cancel, and mouse-aware TUI dogfood.
2. Keep hardening history/selection/search as one coherent navigation surface.
3. Grow the fixed two-pane layout into a small, comprehensible pane tree with
   resize handles and active-pane zoom.
4. Give process exit/restart/disconnect a first-class desktop lifecycle.
5. Turn profiles, Settings, actions, and keybindings from truthful prototypes
   into a pleasant configurable application.
6. Close renderer completeness gaps, especially terminal images, before chasing
   another rendering backend.
7. Keep measuring idle/burst/frame costs and protect the event-driven CPU win.
8. Periodically stop building and simply use the terminal until the next rough
   edge becomes obvious.
