# howl-app

Local-only Zig/SDL3 desktop terminal beside Odin. Each pane owns one in-process
Instance on an exclusive terminal worker. SDL consumes immutable Render leases;
presentation delay cannot throttle canonical PTY/VT progress. The app has no
client transport, Server/Session identity, endpoint, attachment, detach operation
or internal C ABI. Application allocations use Zig's SMP allocator.

The shell supports eight tabs and nested panes, duplicate/new window, tab order,
divider drag, directional focus/resize/swap, zoom, leaf collapse and restart.
One bounded mapping registry supplies shortcuts and the searchable command
palette. Physical key ownership fences repeats/releases across focus changes.

Canonical Canvas commands/resources, text, images, cursor, semantic keys/paste,
negotiated mouse/focus, history anchors, stable selection/word/row/copy, literal
Find and the frame-derived scrollbar use the same worker and immutable facts.
Find bounds queries to 255 UTF-8 bytes, retains 512 stable matches and scans four
rows per service turn. Reflow/eviction/bank changes remain explicit failures.

Seven settings pages edit Local shell/command/cwd/environment recipes, mappings,
themes and exact font paths. A bounded installed-font chooser supplies preview
and cancellation. Font updates are transactional: failed saves restore
presentation against the unchanged canonical grid/history. Child environment
overlays are owned and copied before caller retirement; parent state is unchanged.

Configuration is a strict Local schema at XDG_CONFIG_HOME/howl/app.json, or
~/.config/howl/app.json. Missing files choose Local shell. It owns one built-in
Local recipe and up to six custom recipes. Unknown fields and invalid saved data
fail explicitly. No route migration or Odin compatibility parser is retained;
odin.json stays independent.

The worker applies bounded FIFO desktop replies and copied attention without
stealing focus. Canonical OSC8 Ctrl-click copies owned HTTP(S) URIs. File drops
use bounded POSIX quoting and text events use exact semantic paste. SDL Wayland
splits multiline drop text before delivery, matching the existing platform path.

Bounded SDL IME preedit remains UI-local, follows the copied caret/frame lattice
and clears on ownership changes. Its event/render/commit path is proved; an
external native input-method control remains unqualified. Startup high DPI and
live font/display-scale changes are supported. Odin remains daily until Local
qualification and a daily-driver trial complete.

Build with the repository's exact compiler pin:
zig build install check test -Doptimize=ReleaseSafe
