# howl-app

Local-only Zig/SDL3 desktop terminal beside Odin. Each pane owns one in-process
Instance on an exclusive terminal worker. SDL consumes immutable Render leases;
presentation delay cannot throttle canonical PTY/VT progress. The app has no
client transport, Server/Session identity, endpoint, attachment, detach operation
or internal C ABI. Application allocations use Zig's SMP allocator.

The shell supports eight tabs and nested panes, duplicate/new window, tab order,
divider drag, directional focus/resize/swap, zoom, leaf collapse and restart.
One bounded mapping registry supplies shortcuts; the command palette exposes
context-enabled actions; Ctrl+Shift+Space opens the profile menu. The compact
`⋯` header button opens Settings, and Ctrl+Shift+P opens Command Palette. SDL
client chrome owns caption controls, native drag/resize regions and the wider
pointer-following tab chips without an idle timer. Physical key ownership fences
repeats/releases across focus changes.

Canonical Canvas commands/resources, text, images, cursor, semantic keys/paste,
negotiated mouse/focus, history anchors, stable selection/word/row/copy, literal
Find and the frame-derived scrollbar use the same worker and immutable facts.
Find bounds queries to 255 UTF-8 bytes, retains 512 stable matches and scans four
rows per service turn. Reflow/eviction/bank changes remain explicit failures.

The right-side Settings panel retains sidebar/content focus, pointer selectors,
profile New/Duplicate/Delete, View/Edit, Set default and inline Save/Cancel.
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

The desktop artifact and its proofs use LLVM code generation with the selfhost
linker. On Zig 0.17.0-dev.1980+e78ea8f2c, matched live btop work reproduced similar
publication/presentation counts in app and Odin; switching app code generation
reduced worker CPU substantially. Standalone core package build policies remain
unchanged. ReleaseSafe retains bounds and safety checks.

Build with the repository's exact compiler pin:
zig build install check test -Doptimize=ReleaseSafe
