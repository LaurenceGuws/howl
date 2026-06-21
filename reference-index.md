# Reference Index

Owner: workspace root.

Purpose: exact reference weight, curated entrypoints, and preload/cache order.

## Rule

- Use this file during preload and research work instead of browsing reference trees ad hoc.
- Grep accepted research caches first for likely paths, symbols, and prior proof gaps.
- Then read references in the real project order below.
- Old caches are navigation only until re-proved from current source or accepted references.

## Real Weight

1. References.
2. User.

Reference order:

1. Alacritty for host runtime, event loop, display, window, input, presentation, and most renderer organization.
2. Ghostty for VT shape, embedding seams, and C-facing VT surface shape.
3. TigerBeetle for Zig discipline, ownership proof, bounds, assertions, directness, and tests.
4. Kitty for UX and protocol maturity only.
5. Official docs for protocol, platform, ABI, and OS facts only.

Rules:

- Existing Howl code is presumed wrong until proven otherwise by the references.
- Do not use existing Howl structure as authority by default.
- If references conflict with each other, stop and escalate for explicit review.
- If a user wants to override the reference lessons, that override must be:
  - explicit for that exact case
  - reviewed with the orchestrator
  - recorded with receipts in the active planning artifact
- Without that recorded user override receipt, the references win.

## Preload Order

For non-trivial work, preload in this order:

1. `AGENTS.md`
2. `loop/flow.md`
3. This `reference-index.md`
4. `sprints/current.txt`
5. active `loops/*.txt` file
6. accepted research caches for the slice
7. only then current source and external references

## Cache Locations

- active sprint index: `sprints/current.txt`
- active loop contracts: direct contents of `loops/`
- archived loop contracts: `loops/done/`, `loops/defered/`
- active research caches: direct contents of `research/`
- archived research caches: `research/done/`, `research/defered/`
- active sprint planning artifacts: direct contents of `sprints/`
- archived sprint planning artifacts: `sprints/done/`, `sprints/defered/`

## Alacritty First For Host

Use Alacritty first for host/runtime disputes unless the user's C ABI or embeddable render boundary directly fights it.

Host/runtime questions to ask before accepting any Howl shape:

1. Does Alacritty have this concept?
2. Does Alacritty have this folder boundary?
3. Does Alacritty have this file boundary?
4. Does Alacritty have this symbol or data-shape pattern?

## Ghostty First For VT

Root:

- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty`

Use Ghostty first for VT-core shape, terminal owner split, embedding seams, and C-facing VT surface shape.

Start here:

- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/lib_vt.zig`
  - curated VT entrypoint
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/main.zig`
  - curated terminal root
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/Terminal.zig`
  - terminal aggregate owner
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/Screen.zig`
  - screen truth
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/ScreenSet.zig`
  - multi-screen truth and switching
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/Parser.zig`
  - parser owner shape
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/stream.zig`
  - byte stream handling
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/stream_terminal.zig`
  - stream -> terminal mutation path
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/csi.zig`
  - CSI handling shape
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/osc.zig`
  - OSC owner split
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/dcs.zig`
  - DCS handling shape
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/Selection.zig`
  - selection owner shape
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/point.zig`
  - typed coordinate/value ABI shape

C-facing VT surface:

- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/c`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/include/ghostty/vt`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/c/main.zig`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/c/terminal.zig`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/c/result.zig`

PTY and host/runtime seam:

- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/pty.zig`
  - PTY boundary shape
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/termio/Termio.zig`
  - term I/O owner
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/termio/stream_handler.zig`
  - central stream/control spine
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/termio/Exec.zig`
  - process/exec/PTTY lifecycle constraints
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/termio/Thread.zig`
  - owner thread shape
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/termio/mailbox.zig`
  - wake/message handoff
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/apprt.zig`
  - app/runtime boundary
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/App.zig`
  - app owner shape
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/Surface.zig`
  - surface/runtime seam

Render/text seam:

- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/renderer.zig`
  - renderer root shape
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/font/Atlas.zig`
  - explicit atlas capacity and ownership
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/font/shaper/run.zig`
  - shaping run ownership
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/font/sprite/draw/special.zig`
  - special glyph/sprite ownership

## Alacritty Host Curated

Root:

- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty`

Use Alacritty for host runtime shape, event-loop posture, PTY/read pacing, window/runtime control spine, and pragmatic renderer organization.

Terminal core and PTY loop:

- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/lib.rs`
  - terminal crate root
- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs`
  - bounded PTY/read loop and control spine
- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/event.rs`
  - terminal event surface
- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/tty/mod.rs`
  - PTY abstraction seam
- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/tty/unix.rs`
  - Unix PTY lifecycle and wake behavior
- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/term/mod.rs`
  - terminal owner shape
- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/term/cell.rs`
  - cell model
- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/grid/mod.rs`
  - grid owner shape
- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/grid/resize.rs`
  - resize policy
- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/grid/storage.rs`
  - backing storage shape
- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/selection.rs`
  - selection shape

Host runtime and presentation:

- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/main.rs`
  - startup and top-level runtime spine
- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/event.rs`
  - event processor and control spine
- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs`
  - per-window owner shape
- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/scheduler.rs`
  - wake/scheduling policy
- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs`
  - display owner root
- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs`
  - renderable content preparation
- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/damage.rs`
  - damage tracking shape
- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/window.rs`
  - window presentation seam
- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/input/mod.rs`
  - input owner split

Renderer/text:

- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/mod.rs`
  - renderer root
- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs`
  - text renderer split
- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/atlas.rs`
  - atlas ownership
- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs`
  - glyph cache ownership

## TigerBeetle Curated

Root:

- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle`

Use TigerBeetle for bounds, assertions, naming, structure, directness, and docs discipline.

When researching build, benchmark, profiler, or simulation entrypoints, read these first in addition to the style docs:

- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/internals/vopr.md`
  - deterministic proof surface separation
- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/internals/HACKING.md`
  - build/benchmark workflow posture

Start here:

- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
  - style law and bounds/assertions rules
- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
  - architecture/process discipline
- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/src`

Important code references:

- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/src/io.zig`
  - explicit I/O owner seam
- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/src/io/linux.zig`
  - Linux evented I/O posture
- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/src/list.zig`
  - small direct container style
- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/src/stdx/bounded_array.zig`
  - bounded storage posture
- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/src/stdx/ring_buffer.zig`
  - bounded queue posture
- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/src/state_machine.zig`
  - explicit state-machine style
- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/src/constants.zig`
  - explicit constants and invariants

## Multiplexer References For Tabs, Panes, And Splits

Use these when Howl host layout needs terminal-multiplexer nouns, split/pane/tab
boundaries, focus movement, layout persistence, or resize action shape. These do
not override Ghostty's terminal `Surface` pressure or Alacritty host/runtime
pressure; they exist to keep split and pane vocabulary source-backed.

tmux:

- `/home/home/personal/projects/howl/utils/dev_references/terminals/tmux`
  - mature session/window/pane terminology and command surface
- `/home/home/personal/projects/howl/utils/dev_references/terminals/tmux/session.c`
  - session ownership
- `/home/home/personal/projects/howl/utils/dev_references/terminals/tmux/window.c`
  - window and pane ownership
- `/home/home/personal/projects/howl/utils/dev_references/terminals/tmux/layout.c`
  - pane layout tree
- `/home/home/personal/projects/howl/utils/dev_references/terminals/tmux/layout-set.c`
  - named layouts
- `/home/home/personal/projects/howl/utils/dev_references/terminals/tmux/layout-custom.c`
  - serialized/custom layouts
- `/home/home/personal/projects/howl/utils/dev_references/terminals/tmux/cmd-split-window.c`
  - split command semantics
- `/home/home/personal/projects/howl/utils/dev_references/terminals/tmux/cmd-resize-pane.c`
  - pane resize command semantics
- `/home/home/personal/projects/howl/utils/dev_references/terminals/tmux/cmd-select-pane.c`
  - pane focus/selection command semantics

Zellij:

- `/home/home/personal/projects/howl/utils/dev_references/terminals/zellij`
  - modern tab/pane/layout terminology and UX pressure
- `/home/home/personal/projects/howl/utils/dev_references/terminals/zellij/zellij-server/src/panes`
  - pane ownership and terminal-pane behavior
- `/home/home/personal/projects/howl/utils/dev_references/terminals/zellij/zellij-server/src/pane_groups.rs`
  - pane grouping pressure
- `/home/home/personal/projects/howl/utils/dev_references/terminals/zellij/example/layouts`
  - layout file vocabulary
- `/home/home/personal/projects/howl/utils/dev_references/terminals/zellij/zellij-integration-tests/tests/panes.rs`
  - pane UX behavior tests
- `/home/home/personal/projects/howl/utils/dev_references/terminals/zellij/zellij-integration-tests/tests/tabs.rs`
  - tab UX behavior tests

WezTerm:

- `/home/home/personal/projects/howl/utils/dev_references/terminals/wezterm`
  - existing mux/window/tab/pane/split API vocabulary
- `/home/home/personal/projects/howl/utils/dev_references/terminals/wezterm/wezterm-gui/src/termwindow/render/pane.rs`
  - pane rendering
- `/home/home/personal/projects/howl/utils/dev_references/terminals/wezterm/wezterm-gui/src/termwindow/render/split.rs`
  - split rendering
- `/home/home/personal/projects/howl/utils/dev_references/terminals/wezterm/lua-api-crates/mux/src/pane.rs`
  - mux pane API
- `/home/home/personal/projects/howl/utils/dev_references/terminals/wezterm/lua-api-crates/mux/src/tab.rs`
  - mux tab API
- `/home/home/personal/projects/howl/utils/dev_references/terminals/wezterm/lua-api-crates/mux/src/window.rs`
  - mux window API

## Kitty And Spec Truth Only

Use these only for protocol/spec facts, not architecture shape:

- Kitty protocol docs:
  - `/home/home/personal/projects/howl/utils/official_docs/kitty/`
- Xterm control sequences:
  - `/home/home/personal/projects/howl/utils/official_docs/xterm/ctlseqs.html.md`
  - `/home/home/personal/projects/howl/utils/official_docs/xterm/ctlseqs-contents.md`
- Zig release notes:
  - `/home/home/personal/projects/howl/utils/official_docs/ziglang.org/download/0.16.0/release-notes.html`
- Android official docs:
  - `/home/home/personal/projects/howl/utils/official_docs/developer.android.com/`

## Search Caveat

The parent repo ignores child repos in `.gitignore`.

Root-level discovery can lie by omission. Point tools at explicit child repo paths.
