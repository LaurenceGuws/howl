# howl-odin

Experimental polished desktop client in the Howl module family.

The client owns desktop application policy only: windows, tabs, pane layout,
profiles, settings, command palette, keybindings, and OS integration. It must
not duplicate VT, PTY, Session, text shaping, or terminal raster semantics.

Current proof: Odin + SDL3 + SDL3_ttf application shell on Home. The terminal
surface is intentionally a placeholder until the shell/event/layout foundation
is accepted.

Tested with `odin version dev-2026-09:a2fb372b7`. This experiment does not yet
own or install an Odin toolchain; the compiler remains host input while the
client architecture is being proven.

Current shell proof includes dynamic tabs, a command palette, a Windows-familiar
settings layout, `Ctrl+T`, `Ctrl+Shift+P`, and `Ctrl+,`. None of those actions
create or mutate terminal semantics yet.

Build:

```sh
odin build . -out:zig-out/bin/howl-odin -debug
```
