# howl-app

Direct Zig/SDL3 desktop application replacing the Odin shell. SDL3 and SDL3_ttf
remain platform dependencies; Howl owns terminal semantics and text/rendering.
The new app calls typed Zig modules directly. It has no internal C ABI, shared
bridge library, handle catalogue, ABI signatures or serialized Local route.

Each Local pane has one terminal worker owning one canonical Instance. SDL
consumes immutable Render leases and reports exact backend residency.
Presentation credits only control projection; hidden or stalled presentation
cannot throttle PTY/VT service. Application-owned allocations use Zig's SMP
allocator. C dependencies retain their own allocators.

## Daily capability contract

The existing Odin daily remains available until all of these are qualified:

- Local shell/command/cwd profiles; explicit Direct and exact Server attachments;
  close Local retires its child, close attached view leaves the remote alive.
- Eight tabs, reorder/select/duplicate/new window; eight nested panes, divider
  drag, directional focus/resize/swap, zoom and leaf collapse.
- Canonical text, paste, named/Kitty key lifecycle, mouse/focus routing, Shift
  overrides, IME, hyperlinks and bounded desktop consequences.
- Stable history anchors, scrollbar/seek, selection/word/line/copy and pane-local
  retained-history search with explicit stale/incomplete/error results.
- Strict compatible saved profiles, Server endpoints, mappings, theme and exact
  font recipes; atomic saves, bounded editors, settings search and command palette.
- Canonical Canvas clipping/resources/images/cursor, live font changes, high DPI,
  truthful lifecycle errors/recovery and sleeping idle behavior.

Odin's deferred charter features (accessibility, tab transfer between windows,
regex/logical-line search, unsupported launch environment overrides and other
unimplemented platform contracts) are not invented as rewrite prerequisites.

This is a replacement implementation beside Odin, not yet its daily replacement.
The current implementation has real Local shells, eight tabs, eight nested panes,
tab reorder/duplicate/new window, divider dragging, directional focus/resize/swap,
zoom and leaf collapse. One bounded mapping registry supplies dispatch and the
searchable command palette; the fifty existing defaults and deliberately unbound
directions are preserved. Physical key ownership prevents app chords from
leaking repeats or releases to a terminal after focus or modifiers change.

SDL consumes canonical Canvas commands/resources. Named/control keys, committed
text, paste, focus and stable history anchors are connected. Mouse capture binds
press/move/release to the original pane; wheel routing preserves Shift/history
overrides and negotiated terminal mouse/alternate scrolling. Bounded IME preedit
stays UI-local, uses the copied canonical caret and accepted frame lattice, and
clears when input ownership changes. Unicode UI/preedit fonts have explicit
Arabic and CJK fallbacks. Pane-local font
changes and moving display scale use serialized transactional presentation
updates. Hidden presentation and projection failure cannot stop canonical input/output. A rendering failure
can be retried independently; a stopped Local child can be restarted. A new
window executes the exact running Linux image even after on-disk replacement.

Startup reads the existing schema-1..4 odin.json through bounded owned parsing.
Saved mappings, exact font paths, default profile and per-profile font sizes are
applied. The searchable profile menu opens built-in or saved recipes. Launches
preserve shell, command and cwd; new tabs and splits use the configured default,
and duplicate retains the original tab recipe. Each tab/pane owns its recipe,
so config replacement cannot invalidate a live launch or a later restart.
An unavailable attachment or failed constructor remains an explicitly failed
pane; retry uses that same recipe and never falls back to Local. Missing config
preserves the Home default. Eight bounded settings pages edit profiles, ordered
environment rows, labelled Server endpoints, mappings, themes and exact font
recipes, with global search and a physical shortcut recorder. Saves replace the
owned configuration atomically. Live font changes stage against the existing
canonical grid; failed saves restore presentation without resetting history.
Only an accepted save permits the next ordinary layout resize. Existing children
keep running; future launches and retries use the current saved recipe.

This remains an experimental capability cut. A font chooser, selection/search/
scrollbar, rich desktop consequences and explicit attachments still need
qualification. Exact font paths can already be edited and reset in settings.
IME's SDL event/render/candidate-area path is proved; an external input method's
platform integration still needs a live control. Startup high DPI is supported.
Unsupported commands report their exact gap.

Fifty-two package proofs cover worker independence/failure cleanup, immutable
publication/transfer stalls, exact lease ownership, failed backend recovery,
font rollback, visibility credits, key ownership, mapping conflicts, bounded
pane topology, exact PTY mouse reports, fractional wheel/pointer bounds, SDL
preedit ownership/caret/commit behavior and compatible saved-config ownership,
bounds, migration, mapping swaps, bounded settings edits, catalogue mutation,
shortcut recording and live-font save rollback with held frames/history. A successful
font reset fences unread publications from the previous generation while
preserving already accepted immutable leases. The active workstream records private GUI controls and remaining
gaps. Build with the repository's exact Zig pin:
zig build -Doptimize=ReleaseSafe.
