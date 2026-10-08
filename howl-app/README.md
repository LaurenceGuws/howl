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
The first implementation has a real Local shell, direct SDL Canvas, resize,
semantic named/control keys, text/paste/focus and stable scrollback. It uses
headless consequence policy. Tabs/settings, selection/search, rich desktop
integration and attachments remain to be carried over. Real-PTY proofs cover
hidden/stalled presentation, copied input ownership, synchronized-output timeout
and construction failure. The active Howl workstream records private GUI evidence. Build with the repository's exact Zig pin: zig build -Doptimize=ReleaseSafe.
