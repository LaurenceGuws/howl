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
text, paste, focus and stable history anchors are connected. Pane-local font
changes and moving display scale use serialized transactional presentation
updates. Hidden presentation and projection failure cannot stop canonical input/output. A rendering failure
can be retried independently; a stopped Local child can be restarted. A new
window executes the exact running Linux image even after on-disk replacement.

This remains an experimental capability cut. Saved launch recipes/configuration,
settings, selection/search, IME presentation, terminal mouse and alternate
scroll routing, rich desktop consequences and explicit attachments still need
qualification. Duplicate currently opens another copy of
the default Local launch recipe. Startup high DPI is supported. Unsupported
commands report their exact gap instead of silently taking another route.

Twenty-five package proofs cover worker independence/failure cleanup, immutable
publication/transfer stalls, exact lease ownership, failed backend recovery,
font rollback, visibility credits, key ownership, mapping conflicts and bounded
pane topology. The active workstream records private GUI controls and remaining
gaps. Build with the repository's exact Zig pin:
zig build -Doptimize=ReleaseSafe.
