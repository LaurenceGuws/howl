# Terminal performance track

`horses.sh` runs deterministic TUI Zoo workloads through fresh terminal processes while WMIO owns graphical identity, placement, focus and close.

The benchmark configs under `configs/` are intentionally separate from Captain's daily terminal settings. The optimized KDE track uses the same IosevkaTerm Nerd Font family, opaque backgrounds, no blur, no cursor animation, minimal/no window chrome and padding, and ordinary 4096-row scrollback policy where a terminal exposes line-count history.

Performance-specific choices are documented product knobs:

- **Howl**: isolated `XDG_CONFIG_HOME`, 10 px terminal font, ordinary 4096-row Local history retained by the product.
- **Kitty**: 8 pt, `repaint_delay 4`, `input_delay 0`, `sync_to_monitor no`; cursor trail/blink, blur and shell integration disabled; ligatures disabled for the benchmark font path.
- **Alacritty**: 7 pt, auto renderer, no decoration/padding/blur, cursor blink off, 1 px vertical font offset for a comparable line lattice, 4096 history rows.
- **Ghostty**: 8 pt, no decoration/padding/blur, cursor blink off, common ligature features disabled, 32 MiB lazy scrollback budget, single-instance/cgroup indirection disabled for fresh-process trials.
- **Konsole**: built-in profile in an isolated config root, 7 pt Iosevka, chrome/transparency off, fixed 4096-line history, blink/animation/bidi/semantic hints disabled, one unit of line spacing for comparable vertical metrics.
- **WezTerm**: 7 pt, benchmark-only Lua config, tab/chrome/animation/blur-like extras removed, 4096 history rows, common ligatures disabled. Renderer front-end is OpenGL, selected from measured A/B evidence: WebGPU missed 240 Hz at the high-density dose-4096 canary while OpenGL sustained it with lower CPU and far lower RSS.

On Home KDE/KWin Wayland, exact 1920x1036 placement currently probes near 378-384 columns and 74-77 rows across the prepared horses. `tracks/kde.env` therefore fixes the common workload lattice at 378x74 (27,972 cells).

Before a race:

```bash
set -a; source tools/performance/tracks/kde.env; set +a
./tools/performance/horses.sh doctor
./tools/performance/horses.sh calibrate
```

Raw receipts remain authoritative. Any later scalar index must preserve cadence survival, CPU, memory and topology as separate visible dimensions.

## Benchmark Howl build

`build-howl-fast.sh` creates a self-contained race binary under `~/.local/state/howl-performance-index/howl-fast`: native Zig bridge/dependency graph in ReleaseFast and Odin `-o:speed` without the daily `-debug` safety instrumentation. The normal dogfood binary is not modified.

The poison workload accepts doses through 65,536 at TUI Zoo head `5ed9964`; the default sweep now extends through 8,192, 16,384, 32,768 and 65,536 to find real saturation knees.
