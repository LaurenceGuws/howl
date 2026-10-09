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
preserve shell, command, cwd and child-only environment overrides; new tabs and splits use the configured default,
and duplicate retains the original tab recipe. Each tab/pane owns its recipe,
so config replacement cannot invalidate a live launch or a later restart.
Nonempty environment recipes clone the inherited map, apply validated rows and
materialize one owned POSIX block; the PTY copies it before caller retirement.
Empty recipes retain the direct inherited lane. Parent state is unchanged, empty
and Unicode values stay literal, and terminal-owned TERM/COLORTERM remain canonical.
Partial construction frees completed strings and the full pointer allocation.
An unavailable attachment or failed constructor remains an explicitly failed
pane; retry uses that same recipe and never falls back to Local. Missing config
preserves the Home default. Eight bounded settings pages edit profiles, ordered
environment rows, labelled Server endpoints, mappings, themes and exact font
recipes, with global search and a physical shortcut recorder. Saves replace the
owned configuration atomically. Live font changes stage against the existing
canonical grid; failed saves restore presentation without resetting history.
Only an accepted save permits the next ordinary layout resize. The installed
terminal-family chooser has bounded substring/fuzzy search, exact face recipes,
a sample font, live preview, original-font restoration and atomic Save. Existing children
keep running; future launches and retries use the current saved recipe.

Pointer selection, word/visual-row expansion and Copy are connected through the
sole terminal worker. Copied stable coordinates survive scrolling and ordinary
output; eviction, column reflow and bank changes fail explicitly. Copied spans
travel with the matching immutable lease. Edge scrolling wakes only during an
active gesture; negotiated terminal mouse reports keep their route and Shift
selects text. FIFO Copy returns bounded owned UTF-8, including complete wide
characters and combining sequences, without exposing canonical rows to SDL.

Pane-local Find edits bounded UTF-8 literals without sending query keys, paste or
preedit to the child. The worker scans four canonical visual rows per service turn
and retains at most 512 stable matches for a 255-byte query. Exact Unicode and
conceal filtering preserve canonical columns. Changed canonical revisions report
stale; Enter refreshes. The match cap reports incomplete results explicitly.
Enter/Shift+Enter navigate known matches through the same range/paint/seek path.
The scrollbar derives its thumb from the accepted immutable frame and captures
seek gestures on their original pane without changing the canonical grid.

The sole worker drains retained desktop consequences in canonical FIFO order:
clipboard queries receive empty replies, pointer queries default, color preference
dark, and screen-cell queries the canonical grid. Other unsupported consequences
are consumed. BEL and explicit attention requests coalesce into a copied fact;
SDL briefly flashes only an unfocused window and never requests focus.
Ctrl+left copies a canonical OSC 8 URI through the existing bounded FIFO and
opens only valid HTTP(S); matching releases stay application-owned even when
terminal mouse reporting is active. File drops use bounded POSIX quoting plus
a trailing separator; each SDL text-drop event is pasted byte-for-byte through
the same owned semantic path. Modals and unavailable panes refuse drops.
SDL's Wayland backend splits multiline text on CR/LF before delivering these
events, matching Odin's existing backend behavior; source separators are not
preserved by that platform path.

This remains an experimental capability cut. Explicit attachments still need
qualification. Exact
font paths can also be edited and reset in settings.
IME's SDL event/render/candidate-area path is proved; an external input method's
platform integration still needs a live control. Startup high DPI is supported.
Unsupported commands report their exact gap.

Seventy-four package proofs cover worker independence/failure cleanup, immutable
publication/transfer stalls, exact lease ownership, failed backend recovery,
font rollback, visibility credits, key ownership, mapping conflicts, bounded
pane topology, exact PTY mouse reports, fractional wheel/pointer bounds, SDL
preedit ownership/caret/commit behavior and compatible saved-config ownership,
bounds, migration, mapping swaps, bounded settings edits, catalogue mutation,
shortcut recording, live-font save rollback with held frames/history, and
font-catalogue bounds, exact face ownership, allocation cleanup and chooser IME,
stable selection/Unicode/soft-wrap semantics, hidden FIFO copy, copy bounds and
fault cleanup, plus selection paint/lease coherence under transfer stalls,
exact literal matching/Unicode/conceal bounds, incremental scan caps/staleness,
hidden retained-history navigation and refresh, later pointer ownership,
hostile-query failure, canonical progress during active find, and fractional
scrollbar seek bounds, exact hidden desktop replies/attention independence,
canonical hyperlink ownership/domain refusal, HTTP policy and drop bounds,
caller-retired bracketed paste, modal SDL drop isolation, and profile environment
allocation cleanup/parent isolation/caller retirement. A successful
font reset fences unread publications from the previous generation while
preserving already accepted immutable leases. The active workstream records private GUI controls and remaining
gaps. Build with the repository's exact Zig pin:
zig build -Doptimize=ReleaseSafe.
