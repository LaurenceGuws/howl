# Reference Index

Owner: workspace root.

Purpose: exact, biased reference map.

## Rule

Use the design source order:

1. Ghostty does it.
2. Alacritty does it.
3. TigerBeetle mandates it.

Do not start by browsing random reference trees.

## Ghostty First

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

## Alacritty Second

Root:

- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty`

Use Alacritty second for host runtime shape, event-loop posture, PTY/read pacing, window/runtime control spine, and pragmatic renderer organization.

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

## TigerBeetle Third

Root:

- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle`

Use TigerBeetle third for bounds, assertions, naming, structure, directness, and docs discipline.

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

## Protocol And Spec Truth Only

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
