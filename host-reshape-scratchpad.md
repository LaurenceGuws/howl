# Host Reshape Scratchpad

Owner: workspace root.

Purpose:

- Record the accepted host reshaping direction before deleting ambiguous host shapes.
- Pair with `render-host-boundary-scratchpad.md` so render and host are reshaped from one
  consistent boundary.

## Banned Shapes

The following shapes are not allowed to survive:

- `howl-linux-host/src/terminal/runtime/`
- `howl-linux-host/src/terminal/host/`
- `howl-linux-host/src/terminal/terminal_panel.zig`

Do not recreate them under softer names such as `manager`, `controller`, `runtime2`,
`host2`, `panel`, or other vague umbrella owners.

## Reference Pressure

- TigerBeetle pressure requires true owners, explicit bounds, direct structure, and no
  fake-small renames that preserve bad ownership.
- Alacritty is the primary host-shape reference:
  - top-level event processor owns event-loop dispatch and scheduler;
  - per-window/per-terminal context owns one terminal aggregate;
  - PTY event loop owns bounded PTY I/O and wakes the owner loop;
  - terminal state owns terminal truth;
  - display/window owners own presentation and backend realization.

## Current Problems

- `terminal/runtime/` is a false bucket:
  - `thread.zig` is a PTY wait/wake bridge, not runtime;
  - `progress.zig` is bounded terminal progress over PTY/VT obligations, not runtime;
  - `fonts_linux.zig` is render font path resolution, not runtime.
- `terminal/host/` is a false bucket:
  - everything in `howl-linux-host` is host-side;
  - `input.zig` is VT input encoding plus PTY publication;
  - `geometry.zig` is render frame-layout synchronization plus PTY/VT resize effects;
  - `font_size.zig` is render font-size mutation;
  - `scroll.zig` is VT viewport/scrollback mutation;
  - `scrollbar.zig` is a presentation overlay model.
- `terminal_panel.zig` is a god object. It mixes PTY lifetime, VT state, render ABI
  lifecycle, input routing, scroll/selection/link hover UI, cursor blink, render
  prepare/submit/upload, present acknowledgement, clipboard, and title state.

## Target Shape

```text
howl-linux-host/src/
  main.zig

  terminal/
    context.zig
    term.zig
    c.zig

    pty/
      session.zig
      retained.zig
      feed_record.zig
      wait_thread.zig
      pump.zig

    vt/
      abi.zig
      retained.zig
      surface.zig
      input.zig
      viewport.zig

    render/
      abi.zig
      retained.zig
      fonts_linux.zig
      font_size.zig
      frame_layout.zig

  window/
    window.zig
    present.zig
    layout.zig
    draw.zig
    texture.zig
    term_texture.zig
    scrollbar.zig
```

## Ownership Rules

- `main.zig` remains the top-level app/event-loop owner for now.
- `terminal/context.zig` is the per-terminal aggregate, analogous to Alacritty's
  `WindowContext`. It composes true child owners; it must not become a new god object.
- PTY wait and PTY pumping belong under `terminal/pty/`.
- VT input encoding, visible-surface publication, and viewport/scrollback mutation belong
  under `terminal/vt/`.
- Render font resolution, font-size mutation, frame-layout derivation, and render ABI
  retained state belong under `terminal/render/`.
- Presentation, OpenGL texture realization, present tokens, tab bar drawing, and pure
  overlay layout belong under `window/`.

## Migration Direction

1. Move `terminal/runtime/fonts_linux.zig` to `terminal/render/fonts_linux.zig`.
2. Move `terminal/runtime/thread.zig` to `terminal/pty/wait_thread.zig`.
3. Split or move `terminal/runtime/progress.zig` into PTY pump ownership and VT obligation
   composition.
4. Move `terminal/host/input.zig` to `terminal/vt/input.zig`.
5. Move `terminal/host/font_size.zig` to `terminal/render/font_size.zig`.
6. Move `terminal/host/geometry.zig` to `terminal/render/frame_layout.zig`.
7. Move `terminal/host/scroll.zig` to `terminal/vt/viewport.zig`.
8. Move `terminal/host/scrollbar.zig` to `window/scrollbar.zig` if it remains pure
   presentation overlay.
9. Replace `terminal_panel.zig` with `terminal/context.zig` and remove `Panel` vocabulary.
10. Delete the banned directories and verify no imports reference them.

## Proof Gates

- No paths or imports under `terminal/runtime/`.
- No paths or imports under `terminal/host/`.
- No `terminal_panel.zig` and no `TerminalPanel` type.
- No replacement umbrella names.
- Host continues to consume PTY, VT, and render only through shipped C ABI headers and
  libraries.
- Root, render, and host build/test gates pass after each accepted slice.
