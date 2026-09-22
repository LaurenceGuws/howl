# howl-odin

Experimental polished desktop client in the Howl module family.

See [`EXPERIENCE.md`](EXPERIENCE.md) for the living user-facing experience
charter. This README remains the narrower ledger of behavior the current client
can actually prove.

The client owns desktop application policy only: windows, tabs, pane layout,
profiles, settings, command palette, keybindings, and OS integration. It must
not duplicate VT, PTY, Instance, text shaping, or terminal raster semantics.

The current Linux proof uses Odin + SDL3 for the application/backend shell and
the existing Howl native render owners for terminal presentation. `native/` is
a C-shaped Zig seam over `howl-client`, `server-client`, `howl-render`, and the
existing explicit Instance client transport. It exports neither wire/client backing structs nor a
copied terminal renderer: Odin receives canonical Canvas resource/command facts
and sends semantic input through `howl-client`. SDL3_ttf remains only for app
chrome and as a fail-soft semantic-text fallback while the Canvas backend is
being hardened.

Direct local/attached observation keeps the existing lossless raw-snapshot policy on
validated Unix sockets; TCP attachments retain compression, including loopback. The
transient `--server SERVER_ENDPOINT SERVER_ID SESSION_ID INSTANCE_ID` startup route connects to
one Server, consumes exact attach, and then every Odin observer/control/render/
consequence worker continues over ordinary HWLS on that selected Instance. The bridge
keeps cancellation active through Server connect, attach, HWLS handshake, and blocked
worker I/O. No per-Instance listener or byte proxy is introduced. The daily Odin build keeps
debug symbols, assertions and bounds checks while explicitly selecting `-o:speed`.
Contained texture quads share a pane clip; actual clipped/overhanging content keeps
its exact requested clip. These are host-side cost reductions, not a new protocol,
cache, frame-rate limit, or application-specific path.

Current canary:

- Settings, the profile menu, and Command Palette accept pointer input without
  passing those clicks to the terminal behind them. Profile management has visible
  New/Duplicate/Delete, View/Edit, Set default, Save/Cancel, and environment controls;
  default-profile, size, mode, and theme values have clickable selectors. Read-only
  information and built-in templates are visibly distinct. Long settings forms
  scroll while toolbar/footer controls stay reachable, with keyboard selection
  automatically revealed. Font-family selection is still not an in-app setting;

- native resizable SDL3 window with Windows-familiar tabs, `+`/menu affordance,
  command palette, and Settings surface;
- local Launch profiles remain configuration for future in-process Instance embedding;
  they currently report an explicit unavailable state rather than spawning a helper
  daemon. Direct Attach profiles own observer/control clients, cancellation, and teardown;
  **Attach Home Instance** remains the existing direct `tcp://127.0.0.1:39601` route.
  Separately, `--server` opens one non-owning Server-managed Instance as the initial tab;
  closing Odin leaves that Instance alive under Server ownership;
- tabs use canonical terminal titles with profile-name fallback, Ctrl+Tab/reverse cycling, direct
  Ctrl+1…8 selection, keyboard reorder with Ctrl+Shift+PageUp/PageDown, and pointer
  drag reorder through one shared ordering owner. A held chip gets an immediate
  outline, follows the original pointer grab, and leaves an outlined destination
  slot. Updates are input-driven; no tween timer or extra terminal texture exists.
  Keyboard interruption retires local tab/scrollbar dragging and consumes only
  that canceled gesture's pending left release before tab/overlay routing. TUI
  mouse-reporting captures keep their own release path. `Ctrl+Shift+D` duplicates the
  active profile recipe into a fresh Instance/view; closing a created tab retires
  only that tab's owned child Instance, and closing the final single-pane tab closes
  the window;
- `Ctrl+Shift+N` / Command Palette opens a new independent Odin OS window through
  the same executable and inherited config. The parent uses a self-cleaning process
  reaper only; live tab tear-out/cross-window Instance transfer is deliberately not
  implemented until UI state has an explicit transfer owner;
- tabs use a bounded recursive pane tree rather than a fixed primary/secondary
  pair. Side-by-side and top/bottom actions may nest up to eight pane slots;
  `Alt+Arrow` performs spatial four-way focus, `Alt+Shift+Arrow` resizes the nearest
  matching divider, pointer drag owns a forgiving divider hit lane, `Ctrl+Shift+Z`
  zooms/unzooms the active pane without destroying topology, `Ctrl+Alt+Arrow` swaps
  neighboring Instance views without restart, and `Ctrl+Shift+W` collapses only the
  active leaf while promoting the sibling subtree;
- Canvas commands are pane-clipped even during the brief resize transition, so
  an old wider frame can never paint across the split into its sibling;
- one bounded action registry now owns stable action ids, labels, default shortcut
  strings, category, context-enabled state, and execution. Command Palette,
  Settings → Actions, and profile-menu action hints consume that same registry;
  impossible actions such as zoom on a single pane render disabled rather than
  failing silently. Up/Down/Tab move palette selection and Enter executes the
  selected enabled action;
- Settings is a real navigable application surface rather than one static mock:
  Startup, Interaction, Appearance, Color schemes, Actions, Profiles, and Profile
  pages expose the client's current truthful configuration and ownership state.
  Actions can be rebound from the keyboard, unbound, or reset; conflicts are rejected
  without mutating either action and the conflicting action is named in the UI.
  Profiles can be created, duplicated, edited, and deleted with built-in vs user-owned
  boundaries kept explicit; active profile text editing owns SDL composition input.
  `Ctrl+F` inside Settings searches pages, registry actions, and live profiles and
  navigates to typed destinations; outside Settings the same chord remains terminal input;
- Appearance owns the first live presentation setting: terminal font size has
  12/15/18 px presets, adjustable from Settings or the global zoom shortcut,
  and changing it never mutates canonical Instance geometry; the accepted
  preset persists across app restarts in a small schema-versioned
  `$XDG_CONFIG_HOME/howl/odin.json` written by temporary-file + rename rather
  than in-place truncation;
- Color schemes now owns the first live application-chrome themes: Howl Dark,
  Slate, and High Contrast cycle with Left/Right and persist by stable id. The
  theme changes desktop shell chrome only; terminal Canvas colors remain canonical
  Howl output. A managed-KWin A/B kept sampled terminal pixels identical across all
  three themes, and High Contrast survived a full process restart;
- Startup owns the second persisted setting: the default profile can be Home
  Instance (attach) or Local shell (future local Instance embed). Schema 2 also persists
  custom shortcuts by stable action id; schema-1 files remain readable and upgrade
  only on save. Missing/invalid independent fields retain their accepted defaults,
  and later saves update the existing config directory instead of treating its
  normal `.Exist` result as failure;
- `+`, `Ctrl+T`, startup, and split-pane creation all consume that same default
  profile instead of hard-coding a process type. The runtime catalogue now includes
  bounded schema-3 user recipes beside Home/Local; each recipe names attach-vs-launch
  ownership, shell/command/cwd, inherited-environment overrides, endpoint, and an
  optional font-size presentation default. The profile dropdown enumerates the real
  catalogue and marks the stable-id default;
- Launch-profile shell/command/cwd/environment fields are retained as future direct
  local-Instance recipe state. They no longer imply or package a standalone Instance
  daemon. The current managed Server route is intentionally separate from that future
  local embedding work;
- Home tab observes the existing canonical Howl Instance at
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
- Ctrl+left-click is the deliberate desktop hyperlink override. The app resolves the
  exact displayed stable cell through `howl-client.view` OSC 8 metadata, accepts only
  valid UTF-8 `http://` / `https://` targets, and delegates opening to SDL. Ordinary
  unlinked Ctrl-clicks fall through to the existing mouse/selection router; unsupported
  canonical schemes such as `file://` are never handed to the platform;
- DEC alternate-scroll is routed through canonical named-key cycles, never client
  escape strings. In a controlled alternate-screen canary with mouse tracking off,
  DEC alternate-scroll on, and application-cursor mode on, wheel-up/down arrived as
  VT-owned `ESC OA` / `ESC OB`. Shift+wheel remained the explicit local override and
  produced no child bytes. The same canary, with focus reporting off, also proved
  semantic focus transitions are suppressed by VT when the child did not request them;
- desktop text composition owns SDL `TEXT_EDITING` as bounded client-local preedit
  state. Candidate placement follows the active terminal cursor or Find field, UTF-8
  preedit caret indices are measured into pixel offsets, transient composition is cleared
  when input ownership changes, and only final `TEXT_INPUT` crosses into Howl. A private
  XWayland `us(intl)` dead-key canary composed dead-acute + `e` into exactly one `é`;
  that backend did not emit a visible preedit event, so a true runtime `TEXT_EDITING`
  producer remains a future platform canary rather than a claimed proof;
- named physical-key coverage includes F1-F12, lock keys, and the numeric keypad.
  F5, F12, and Shift+F5 were pressure-tested through VT-owned encoding; standalone
  modifier-key transitions remain deliberately withheld until shortcut arbitration can
  guarantee app-owned shortcuts never leak half a modifier chord to the child;
- Kitty all-event key semantics are pressure-tested end-to-end: a 700 ms F5 hold
  produced one press (`ESC[15~`), four repeat events (`ESC[15;1:2~`), and one release
  (`ESC[15;1:3~`). SDL produced the physical lifecycle, Odin sent semantic actions, and
  VT alone chose the terminal encoding;
- managed-KWin interaction dogfood now includes real Neovim, btop, tmux, and less paths: Neovim accepted click/wheel while Shift+drag stayed local, btop's actual menu and process-list wheel worked, a mouse-enabled two-pane tmux instance changed pane focus from a click and accepted input only in that pane, and less correctly ignored wheel with tracking/alternate-scroll off while PageDown navigated normally;
- observation and control use independent client connections: a named worker
  blocks on revision-relative observation while the SDL event/render thread
  owns only control delivery; teardown wakes the blocked observer through
  `howl-client`'s duplicate-socket cancellation primitive;
- Instance publication wakes the SDL main thread through one registered user
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
  direct seek/drag without colliding with terminal text selection. A delivered
  button press owns the gesture even when explicit SDL capture is unsupported;
  normal held-button delivery (including Wayland's implicit grab) handles dragging.
  Release, focus loss, and window close terminate the gesture so later movement
  cannot keep scrolling. Private KWin tests cover thumb/track dragging, release
  outside the window, focus cancellation, and pane-local nested splits at 1x;
  single/split thumb dragging also passes at 1.7x.
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
  plus Instance `text_extract`. Holding a selection drag in the top/bottom two-row
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
- terminal content is projected by the shared `howl-render` Terminal Canvas;
  the Odin bridge exposes fixed C resource/removal/command
  records, while SDL caches Canvas resources and paints ordered solid,
  alpha-mask, and RGBA commands without parsing terminal cells itself;
- Canvas residency survives unchanged revisions, so the first frame uploads only
  missing presentation resources. Terminal images now use Canvas external-resource
  residency too: exact Instance image generations are demand-fetched through
  `howl-client.images`, exposed to SDL through the same RGBA upload API, and then
  reused without further transfer. Kitty replacement preserves logical Canvas
  resource identity while advancing generation; crop/z-order and exact removal are
  renderer-owned, and a Sixel canary proved the path is protocol-independent;
- terminal font selection now supplies ordered `howl-text` fallbacks rather than
  accepting replacement diamonds as desktop policy. On Linux, explicit `HOWL_FONT`,
  `HOWL_FALLBACK_FONT`, and `HOWL_SECONDARY_FALLBACK_FONT` files win; otherwise
  fontconfig must resolve JetBrainsMono Nerd Font, Noto Sans Arabic, and Noto Sans
  CJK JP exactly. A live corpus proved combining marks, CJK wide cells, Arabic
  fallback/shaping, ligatures, box drawing, all supported underline styles/colors,
  truecolor, and final-column wide-cell clipping. Color emoji remains explicit debt:
  the current `howl-text` raster contract accepts mono/gray masks, not BGRA glyphs;
- created Local-shell tabs acquire Instance size control once, then submit only
  owned resizes from actual Canvas cell metrics and pane extent. Attached views
  preserve the Instance size until the user chooses Take Instance size control;
  merely attaching, focusing, or opening a larger window never claims it;
- pane lifecycle is explicit and ownership-aware. Canonical Instance `stream_closed` /
  `child_exited` facts preserve the final frame behind a small recovery bar; an owned
  Local shell becomes `Process exited` with Restart, while an unavailable/closed attached
  view offers Reconnect to the same endpoint. Restart replaces only that pane with a new
  owned Instance identity; Reconnect never launches a shell. `Ctrl+Shift+R` invokes the
  appropriate recovery, and dead panes remain locally scrollable/selectable but stop
  forwarding terminal input;
- SDL rendering uses the window-logical coordinate space and lets the renderer
  scale to high-density output, keeping chrome, cursor placement, and converted
  pointer coordinates on one geometry contract;
- the current created-instance profile inherits the desktop client's process
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

The script runs the native bridge tests plus Odin's desktop unit tests, builds the
bridge ReleaseSafe, checks and builds the Odin client, then atomically publishes the
executable, matching bridge library, and window icon. No Instance daemon is packaged.
The result is:

```text
howl-odin/zig-out/bin/howl-odin
```

Managed Server startup is explicit and transient:

```text
howl-odin --server SERVER_ENDPOINT SERVER_ID SESSION_ID INSTANCE_ID
```

The normal no-argument launch still uses the configured profile catalogue. Persistent
Server profile editing is not yet claimed by this checkpoint.


## Terminal-owned tab properties

Each pane observes its own canonical title and retained OSC9;4 progress. The tab
uses the active pane's title, falling back to its profile label when absent or
empty. The saved profile name is never overwritten. Title bytes are untrusted:
invalid UTF-8 falls back to the profile, and controls/bidi formatting are replaced
with spaces in desktop labels only. The native window title remains Howl.

A thin tab progress strip displays normal, failure, paused and indeterminate
states. Indeterminate is a stationary segment rather than a timer-driven pulse;
all changes use existing Instance observer wakeups. Clearing the canonical state
removes the strip. Directory/remote-host/shell-mark properties also survive the
shared transport but have no automatic desktop execution behavior or new UI yet.

This uses the matching framing-v10 client/Instance bundle. Rebuilding source does
not update an independently running remote, mobile or browser Instance service.


## Compact desktop frame

The tab strip and window controls share one 46-logical-pixel header. The spare
header region delegates window movement to SDL's native hit-test API; the outer
four-pixel rim delegates resizing. Minimize, maximize/restore and close use SDL
window operations; close follows the existing Instance/gesture cleanup path.
Right-clicking spare header space requests the native system window menu. Do not
assume native titlebar double-click behavior is available on every SDL backend.
If hit testing or border removal is unavailable, the host reports that failure
and keeps native decorations instead of leaving an immovable borderless window.

There is no outer terminal mat. Paint, input, selection, search, IME and owned
PTY sizing share one content rectangle: six logical pixels at left/top/bottom,
and sixteen at right for the scrollbar's independent hit lane plus resize rim.
Gutters and sub-cell remainder use the accepted Canvas snapshot's default
background (foreground under screen reverse), not the application chrome theme.
This changes no terminal cells, image bytes, protocol or saved profile settings.

The 640x320 minimum and bounded eight-tab layout reserve window controls,
Settings, new/profile buttons and at least 28 pixels of native drag space.
Crowded tabs shrink; below 96 pixels their close target is removed, and below
64 pixels a numbered chip keeps each tab reachable. The existing close action,
keyboard navigation and palette still work. No installer or rollout is implied
by rebuilding the development bundle.


Private KWin qualification also exercises header drag, rim resize, native
maximize/restore, minimize/restore, F11 fullscreen, the system menu, and caption
close with exact teardown of three owned Instances. These are scoped native
controls proofs, not double-click-titlebar or mixed-monitor/hotplug acceptance.


## Asynchronous Instance I/O

One application-owned I/O runtime outlives all attached Instance workers. Connection setup, protocol requests/acknowledgements, search, selection/clipboard/link queries, image fetching, and host-policy I/O execute on workers. SDL windowing, drawing, resource submission, clipboard and browser opening remain on the graphical thread. Native transport is explicit Unix or numeric-IPv4 TCP; Odin owns no SSH subprocess, bridge executable, PTY, Session or Server.

## Instance size control

Command Palette (`Ctrl+Shift+P`) and Settings > Actions expose two rebindable,
initially unbound actions:

- **Take Instance size control** fits the active pane once, then follows that
  pane's window/split/zoom/font changes while its control connection remains
  the Instance's geometry leader. This is an explicit takeover, not discovery.
- **Stop resizing Instance** disables this pane's future automatic size requests.
  The last accepted size stays in place unless another client changes it.

Local launches acquire once automatically as part of owning their new Instance.
Attachments, duplicates of attachment recipes, and reconnects begin fixed; they
never inherit another pane's authority or silently claim it on focus. Subsequent
automatic resizes use only the existing resize request, not assign-leader. A
not-leader reply stops auto-sizing and leaves ordinary terminal input usable.
There is no ownership polling timer and no automatic attempt to take it back.

The shared client preserves NotGeometryLeader separately from transport failure.
Odin allows one queued/in-flight size transaction per pane, remembers only ACKed
geometry, and uses an intent generation so a queued old request is retired or a
late completion cannot re-enable stopped/newly requested auto-sizing. A resize
already transmitted may still complete after Stop; Stop is not an unsend promise.

Stop deliberately does not send the protocol's unconditional clear-leader
operation: a delayed clear could evict a different client's newer ownership.
Another client may explicitly take control at any time; closing the owning
connection releases its leadership naturally. No new wire operation, Instance
service update, route policy, profile conversion, or default shortcut is needed.


## Reusing an observed live view

An image-free live observation now transfers its existing immutable `howl-client`
view to rendering instead of fetching and projecting the screen a second time.
The pane owns at most one newest offer; a render request may own one transferred
view. Replacement, failure and teardown destroy their own allocations. There is
no reference counting, second terminal model, row replay, or unbounded backlog.
An incoming observation still has its ordinary bounded transient decode storage.

The renderer borrows that view for CPU preparation only; shared view storage is
freed before the ready frame is published. SDL acceptance and stable front facts
keep the same asynchronous lifetime as before. A stale offer cannot roll back a
renderer that has already observed farther ahead on its own connection.

This eligibility rule is independent of transport: Unix, TCP and native SSH use
it equally. Existing lossless representation choices are unchanged. **External
image-bearing snapshots and historical viewports retain renderer-owned full
observation**. Their image generations are pinned by that connection and are not
borrowed from a different observer. Clearing the last image can return to live
view reuse. This is partial elimination of redundant work, not a claim that all
observations or connection lifetimes have been merged.

The two worker channels remain independent. A stalled external image fetch does
not block the graphical thread, input worker, or newer observer metadata. Native
text/image transition and stopped-carrier proofs remain required alongside the
pixel and CPU controls. The improvement is in Odin's use of the existing shared
model, not an implicit mobile/Web rollout or a new public client ABI.

Managed target identity includes the expected `SERVER_ID` from Server status/tree
(or the run receipt), before Session and Instance IDs. All three are nonzero decimal
u64 values. A reused endpoint with a different Server incarnation fails closed as
stale; explicitly browse/select the new Server instead of silently reconnecting to
its reused Session/Instance numbers. This is target identity, not authentication.

The native `create`, `render_create`, and `consequence_create` ABI now takes
`server_id` before Session/Instance IDs (zero for direct targets). Rebuild the Odin
caller and native bridge together; no legacy endpoint-plus-pair fallback is kept.
