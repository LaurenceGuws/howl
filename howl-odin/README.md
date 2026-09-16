# howl-odin

Experimental polished desktop client in the Howl module family.

See [`EXPERIENCE.md`](EXPERIENCE.md) for the living user-facing experience
charter. This README remains the narrower ledger of behavior the current client
can actually prove.

The client owns desktop application policy only: windows, tabs, pane layout,
profiles, settings, command palette, keybindings, and OS integration. It must
not duplicate VT, PTY, Session, text shaping, or terminal raster semantics.

The current Linux proof uses Odin + SDL3 for the application/backend shell and
the existing Howl native render owners for terminal presentation. `native/` is
a C-shaped Zig seam over `howl-client`, `howl-render`, and the existing
`SessionProcess` owner. It exports neither wire/client backing structs nor a
copied terminal renderer: Odin receives canonical Canvas resource/command facts
and sends semantic input through `howl-client`. SDL3_ttf remains only for app
chrome and as a fail-soft semantic-text fallback while the Canvas backend is
being hardened.

Current canary:

- native resizable SDL3 window with Windows-familiar tabs, `+`/menu affordance,
  command palette, and Settings surface;
- the `+` action and `Ctrl+T` launch a new canonical local Session through the
  same `SessionProcess` owner used by the native Howl host; each created tab
  owns its own `howl-sessiond`, PTY, observer/control clients, cancellation, and
  teardown while **Attach Home Session** remains a non-owning view of the
  existing `tcp://127.0.0.1:39601` Session;
- tabs have real selection/close semantics plus Ctrl+Tab cycling, and closing a
  created tab retires only that tab's owned child Session;
- one tab may own a real two-pane split: `Alt+Shift+D` creates an independent
  local Session in the secondary pane, `Alt+Left/Right` moves input focus, and
  `Ctrl+Shift+W` closes only the active pane when split; the survivor is
  promoted and reacquires full-pane geometry without restarting its Session;
- Canvas commands are pane-clipped even during the brief resize transition, so
  an old wider frame can never paint across the split into its sibling;
- dropdown and command-palette commands share one application action model;
  Up/Down/Tab move selection, Enter executes the selected action, and commands
  such as new tab, attach Home Session, Settings, and close tab are no longer
  display-only rows;
- Settings is a real navigable application surface rather than one static mock:
  Startup, Interaction, Appearance, Color schemes, Actions, Profile defaults,
  and Home Session pages expose the client's current truthful configuration and
  ownership state;
- Appearance owns the first live presentation setting: terminal font size has
  12/15/18 px presets, adjustable from Settings or the global zoom shortcut,
  and changing it never mutates canonical Session geometry; the accepted
  preset persists across app restarts in a small schema-versioned
  `$XDG_CONFIG_HOME/howl/odin.json` written by temporary-file + rename rather
  than in-place truncation;
- Startup owns the second persisted setting: the default profile can be Home
  Session (attach) or Local shell (create owned Session). Missing fields in the
  earlier schema-1 file retain defaults, and later saves update the existing
  config directory instead of treating its normal `.Exist` result as failure;
- `+`, `Ctrl+T`, startup, and split-pane creation all consume that same default
  profile instead of hard-coding a process type. With Home as default they add
  another observer view and spawn no PTY; with Local shell as default they
  create a new owned Session. The profile dropdown always exposes both choices
  explicitly and marks the current default;
- Home tab observes the existing canonical Howl Session at
  `tcp://127.0.0.1:39601` without taking geometry leadership;
- committed text plus named/control keys round-trip through `howl-client`;
- desktop pointer routing now consults Howl's coherent interaction state instead of
  assuming every mouse belongs to the client. Ordinary shell tracking-off behavior
  remains local selection/history; a child enabling canonical mouse tracking gets
  semantic press/release/move/wheel facts through `howl-client.actions.mouse`, and
  VT alone chooses the child escape encoding. Shift+drag and Shift+wheel are explicit
  local overrides even while tracking is enabled. A controlled SGR button-event
  canary produced exact child mouse reports for click, drag, and wheel, while the
  same Shift overrides produced no additional child RX bytes;
- real desktop focus gain/loss is forwarded as semantic Howl focus input. VT suppresses
  it unless the child requested focus reporting; with DEC focus reporting enabled,
  the managed-KWin canary received canonical focus-out `ESC[O` and focus-in `ESC[I`.
  Focus loss also terminates any terminal-owned mouse capture with semantic releases;
- observation and control use independent client connections: a named worker
  blocks on revision-relative observation while the SDL event/render thread
  owns only control delivery; teardown wakes the blocked observer through
  `howl-client`'s duplicate-socket cancellation primitive;
- Session publication wakes the SDL main thread through one registered user
  event. The desktop loop blocks in `SDL_WaitEvent` between invalidations and
  paints once per drained event burst instead of repainting the complete app at
  compositor cadence when nothing changed;
- scrollback is pane-local and uses Howl's canonical retained-history window:
  physical mouse-wheel input and Shift+PageUp/PageDown request exact history
  offsets. High-resolution fractional wheel input accumulates canonical row
  intent instead of turning every tiny delta into a whole wheel notch. An
  absolute retained-row anchor keeps a scrolled viewport stationary
  while newer PTY output arrives, alternate-screen observations reset the pane
  to LIVE, and committed terminal input returns only the active pane to LIVE
  before delivery;
- retained history also exposes a thin per-pane position scrollbar: the thumb
  stays quiet at LIVE, becomes accent-colored while scrolled, tracks the
  accepted canonical history offset, and owns a forgiving pointer lane for
  direct seek/drag without colliding with terminal text selection. SDL pointer
  capture keeps a drag coherent outside the window, while button release,
  focus loss, and window close terminate capture so later pointer motion cannot
  keep scrolling accidentally.
  `Ctrl+Shift+Home/End` jump directly to the oldest retained window or back to
  LIVE without stealing ordinary terminal Home/End. Vertical-only geometry
  changes preserve the absolute retained-row anchor; an owned horizontal reflow
  deliberately returns to LIVE because the same numeric row can name different
  text after reflow;
- retained-history Find is pane-local and keyboard-first: `Ctrl+Shift+F` opens a
  compact query bar, Enter walks older matches, Shift+Enter walks newer matches,
  and matches are canonical projected row/column facts rather than scraped glyphs.
  The full retained ring is scanned on a lazily-created read-only worker connection,
  so SDL never waits for a 4,096-row search. A found match recenters through the
  same absolute history anchor used by manual scrollback and remains stationary
  while newer PTY output arrives. Reflow/eviction expires stale matches explicitly;
  a hot ring that evicts rows before they can be scanned reports an incomplete
  result instead of a false authoritative no-match. Search is currently exact,
  case-sensitive UTF-8 within one projected row; cross-wrap logical-line search,
  regex/case modes, and richer search options are deliberately not faked yet;
- desktop selection is pane-local and stores stable canonical row/column
  endpoints rather than viewport-relative rows. Left-drag paints only the
  visible intersection of that stable range; wheel/PageUp/scrollbar navigation
  and live output may move the viewport without destroying the selection, and
  an offscreen range can still be copied exactly through `howl-client.selection`
  plus Session `text_extract`. Holding a selection drag in the top/bottom two-row
  edge band autoscrolls one retained row every 100 ms and updates the same stable
  focus endpoint; the SDL loop gains that timeout only while the edge gesture is
  armed and returns to indefinite sleep on release or at oldest/LIVE. `Ctrl+Shift+V`
  uses semantic paste so bracketed-paste behavior remains VT-owned. Input
  deliberately clears selection while returning to LIVE; row eviction,
  screen-bank change, or column reflow invalidates the range instead of
  retargeting it. Double-click expands through `howl-client.selection.word` to
  the contiguous non-space canonical word and may cross a soft-wrap boundary;
  triple-click deliberately selects only the current projected visual row's
  text-shaped extent, trimming untouched trailing blank cells rather than
  pretending a wrapped logical line has one stable desktop identity. VT itself
  normalizes wide-cell continuation endpoints during canonical text extraction;
- terminal content is now projected by the real `howl-render` terminal Content
  and Canvas Composer; the Odin bridge exposes fixed C resource/removal/command
  records, while SDL caches Canvas resources and paints ordered solid,
  alpha-mask, and RGBA commands without parsing terminal cells itself;
- Canvas residency survives unchanged revisions, so the first frame uploads the
  glyph atlas and later frames reuse it instead of re-uploading presentation
  resources; terminal-image resources remain an explicit not-yet-admitted
  boundary in this first backend canary;
- created Local-shell tabs own Session geometry leadership: the client derives
  rows/columns from the actual Howl Canvas cell metrics and current pane extent,
  while attached Home Session views remain observer-only and never resize the
  canonical Session merely because their desktop window is larger;
- SDL rendering uses the window-logical coordinate space and lets the renderer
  scale to high-density output, keeping chrome, cursor placement, and converted
  pointer coordinates on one geometry contract;
- the current created-session profile inherits the desktop client's process
  environment and launches the configured shell; richer profile persistence and
  environment editing remain deliberately deferred rather than faked.

## Toolchain

This experiment deliberately pins both compilers used by its build:

- Zig follows the repository root `.zigversion`;
- Odin follows `.odinversion` in this module.

## Build

```sh
./howl-odin/build.sh
```

The script runs the native bridge tests plus Odin's retained-history unit tests,
builds the bridge ReleaseSafe, builds the exact matching `howl-sessiond`, checks
and builds the Odin client, then
atomically places the bridge and Session daemon beside the executable so live
created Sessions do not make rebuilds fail with `ETXTBSY`.
The result is:

```text
howl-odin/zig-out/bin/howl-odin
```
