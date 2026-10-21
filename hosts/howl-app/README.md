# howl-app

Local-only Zig/SDL3 desktop terminal beside Odin. Each pane owns one in-process
Instance on an exclusive terminal worker. SDL consumes immutable Render leases;
presentation delay cannot throttle canonical PTY/VT progress. The app has no
client transport, Server/Session identity, endpoint, attachment, detach operation
or internal C ABI. Application allocations use Zig's SMP allocator.

The shell supports eight tabs and nested panes, duplicate/new window, tab order,
divider drag, directional focus/resize/swap, pane cycling, balanced splits, zoom,
leaf collapse and restart. Hovering a pane divider highlights its grab surface and
shows its horizontal/vertical resize cursor. At an aligned four-way junction,
drag either divider half independently, or grab the junction to move both axes.
Staggered crossings keep the uninterrupted border shared; returning a half within
8 logical pixels of its neighbor snaps them together and lets either axis detach
again. Pointer and keyboard resizing use the same geometry-aware border choice.
The move cursor and highlights show all borders captured by a junction grab.
A neutral light tint serves header
controls, list/category chips and scrollbars. Tab bodies and their close buttons
have independent hover rectangles shared with pointer hit geometry.
One bounded mapping registry supplies shortcuts; the command palette exposes
every mappable command, including directional focus/resize/swap; Ctrl+Shift+Space opens the profile menu. The compact
`>` button beside `+` opens the profile menu; `⋯` opens Settings, and
Ctrl+Shift+P opens Command Palette. Appearance → “Hide top bar with one tab”
reclaims the whole header for a single terminal (saved as `hide_single_tab`,
default `false`). Appearance → “Tab chip width” switches between Fixed (the default)
and Fit available space, persisted as tab_width="fixed" or "fit". Fit divides the
available tab area equally: two tabs each get half, three each get a third.
The header buttons keep their reserved space; paint, close,
reorder and native caption hits use the same rectangles. Ctrl+T, Ctrl+Shift+Space and Ctrl+, remain available
when the bar is hidden. SDL
client chrome owns caption controls, native drag/resize regions and the wider
pointer-following tab chips without an idle timer. Physical key ownership fences
repeats/releases across focus changes. Programs requesting Kitty report-all get
plain-letter press/repeat/release with owned SDL committed text; ordinary shell
and IME text keep their text-input path.

Cursor shapes follow application DECSCUSR requests: block, bar and underline.
Appearance → “Cursor blink” selects Off (the conservative default), Application
(follow the program's blink intent) or Always (blink any visible cursor).
A focused live pane uses a 500ms on/off phase; movement, focus and presentation
changes restart it visibly. Hidden/history/inactive panes and modal fields do not
schedule cursor blink work. The host only includes or omits the retained cursor
suffix; no text shaping, frame publication or content texture rebuild runs for a
blink tick. Off/steady presentation has no cursor timer. Terminal color overrides
include independent cursor and cursor_text colors; blank inherits the preset.
The text color recolors clipped monochrome glyph ink under a block; color glyphs
keep their colors.

Appearance → “Cursor shape” selects Block (default), Bar or Underline, persisted as
cursor_shape="block", "bar" or "underline". The baseline applies to new and existing
panes on both screen banks. Application style overrides survive a preference
change; DECSCUSR 0, DECSTR and RIS reveal the configured default according to their
normal screen/reset scope. Changing the default does not unhide a program-hidden
cursor or invalidate terminal content.

Inactive panes and unfocused terminals show a steady hollow cell in the effective
cursor color. It uses one physical pixel per edge at every scale, preserves the
original glyph underneath, and stays absent when the program hides its cursor.
Focus changes compose this outline from the same immutable frame and retained
content texture. Unicode wide glyphs use one complete two-cell cursor rectangle,
including when an application positions the cursor on the continuation. Bars stay
thin at that rectangle's leading edge; underlines and hollow outlines span it.
DEC row scaling is applied afterward; OSC66 multirow and non-semantic allocations
keep the existing single-grid-cell cursor.

Unset cursor colors use the resolved cell foreground/background, including SGR
inverse and global reverse. Implicit colors remain opaque under faint text and
use black or white only to resolve exact collisions with the cell background or
unset block ink. Explicit theme,
configuration and application colors stay exact. Block replay preserves intrinsic
color-glyph ink. Selection is composed above retained content and below the cursor,
so it cannot tint the cursor or its recolored ink. Stroke/accessibility refinements,
blink timing policy and motion/trails remain future cursor increments.

Canonical Canvas commands/resources, text, images, cursor, semantic keys/paste,
negotiated mouse/focus, history anchors, stable selection/word/row/copy, literal
Find and the frame-derived scrollbar use the same worker and immutable facts.
Primary-screen selection anchors drags from unused space at the end of visible text;
drags and clipboard extraction stop there while preserving interior blank rows,
soft wraps and complete wide glyphs. It uses text content rather than cursor
position. Command/profile search fields show a steady caret without an idle
blink timer. Left/Right move through the UTF-8 query; Home/End move to its ends,
typing inserts at the caret, and Backspace/Delete edit around it. Up/Down still
select results. Selecting Profile Menu from Command Palette switches overlays.
Find bounds queries to 255 UTF-8 bytes, retains 512 stable matches and scans four
rows per service turn. Reflow/eviction/bank changes remain explicit failures.

Canvas draws canonical physical-pixel commands at SDL scale one, then restores
the UI scale. The centred origin splits sub-cell slack above/below and left/right
while aligning to the physical grid; generated blocks
and box rules retain their raster coverage at fractional desktop scales.

The right-side Settings panel retains sidebar/content focus, pointer selectors,
profile New/Duplicate/Delete, View/Edit, Set default and inline Save/Cancel.
Rows select on one click; Enter or double-click begins an edit. Finite profile,
theme and toggle choices use arrows and ignore typed text. Enter/Save commits;
Escape cancels the edit, then search, then content focus before closing Settings.
Tab moves between sidebar/content, or field/Save/Cancel during an edit.
Interaction exposes the existing copy/paste/find/history shortcut settings.
Search preserves normal row geometry. Settings, installed fonts and both palettes
share text editing, list viewports, row hit geometry and selection/hover styling.
The same UTF-8 caret editor also serves terminal Find; Ctrl+A selects the field,
Ctrl+V pastes, Home/End and Left/Right move the caret, and Delete/Backspace edit
either side. Shift+arrows/Home/End extends a UTF-8 selection; typing replaces it,
and Ctrl+C/X copies/cuts the exact selected range. Selected ink contrasts with the
theme accent and is clipped inside the field border. The font chooser retains explicit Preview/Save/Cancel and samples Latin letters,
ambiguous glyphs, operators, box drawing, blocks, Nerd Font icons, accented text,
Greek/Cyrillic, Arabic/Hebrew and CJK. Missing family glyphs remain visible.
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

Startup has two independent, opt-in discovery switches: installed shells/REPLs
and SSH config hosts. Opening the profile menu rebuilds a read-only snapshot;
typing ranks exact/prefix matches before substrings and abbreviations. The wheel
scrolls a retained viewport; arrows and PageUp/PageDown/Home/End keep selection
visible. All/Saved/Shell/REPL/Remote chips filter profiles; Tab and Shift+Tab
cycle them without clearing the query. Saved commands stay in Saved rather than
having their runtime category guessed; the built-in Local profile is also a Shell. Discovery never starts candidates or makes connections.
Saved profiles remain separate; selecting a discovered entry copies its complete
launch recipe before the snapshot can retire. New tabs use the saved default.

Shell discovery checks PATH for a curated shell/REPL list and reads /etc/shells.
SSH discovery enumerates concrete Host aliases in ~/.ssh/config and
/etc/ssh/ssh_config, including sorted Include patterns and their nested files.
Wildcard/negated Host patterns are not destinations. Match conditions and command
directives are never evaluated during discovery; aliases are candidates and
OpenSSH decides the effective configuration at launch. Includes support current
HOME, environment-variable expansion and the %d/%% tokens; target-dependent
expansions and other-user tilde paths fail explicitly. Discovery reads no keys,
writes no SSH configuration, and installs nothing remotely.

A snapshot holds at most 512 entries. Configuration input is bounded to 64 files,
eight include levels, 256 KiB per file and 2 MiB total; Include expansion inspects
at most 8,192 directory entries and 32 path components. A failed census reports
its error and leaves saved profiles usable. Discovered entries are not persisted
and are not added to the saved-default selector.

Profiles may specify an explicit argument array (at most 16 arguments and 2 KiB
of argument bytes), mutually exclusive with Command. Edit it as JSON in the
profile's Arguments field; blank retains ordinary interactive-shell mode,
while [] launches the executable without extra arguments. Arguments pass literally
through the existing Instance program launch, without shell interpolation.

Colour schemes separates **App palette** from **Terminal palette**. App chrome
keeps the existing howl_dark/slate/high_contrast presets with nine optional role
overrides in app_colors. The terminal has independent howl_dark/howl_light
presets. Both selectors also offer Catppuccin (four flavours), Dracula, Nord,
Gruvbox Dark/Light, Solarized Dark/Light and Tokyo Night (Night, Storm, Moon and Day);
[THEMES.md](THEMES.md) lists exact ids, source pins and adaptation scope.
The terminal_colors overrides cover foreground, background, cursor, cursor text and a
16-entry ansi array. Every override is exactly #RRGGBB; blank inherits the preset.
Settings shows resolved swatches and a terminal sample. Editing a role provides
RGB sliders, a live swatch, constrained hex input and Preset inheritance; the
candidate stays local until Save. Each group has its own
reset-overrides action; changing a preset retains explicit overrides.

Successful terminal palette changes apply to live panes and future launches.
They replace current terminal colours; subsequent program OSC changes still
apply, and OSC/Kitty/iTerm resets return to the configured baseline. Indexed
cells resolve through that palette; explicit RGB cells retain their colour.
Application-only changes leave terminal state untouched. Color-preference
queries/opt-in notifications follow the configured terminal background.

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
