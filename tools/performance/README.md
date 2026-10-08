# Terminal performance track

`horses.sh` runs deterministic TUI Zoo workloads through fresh terminal processes while WMIO owns graphical identity, placement, focus and close.

The benchmark configs under `configs/` are intentionally separate from Captain's daily terminal settings. The optimized KDE track uses the same IosevkaTerm Nerd Font family, opaque backgrounds, no blur, no cursor animation, minimal/no window chrome and padding, and ordinary 4096-row scrollback policy where a terminal exposes line-count history.

Performance-specific choices are documented product knobs:

- **Howl**: isolated `XDG_CONFIG_HOME`, 10 px terminal font, ordinary 4096-row Local history retained by the product.
- **Foot**: 7.90 pt IosevkaTerm Nerd Font (nearest size that qualifies for the common 378x74 lattice), exact-frame resizing instead of cell-multiple snapping, no decoration/padding, 4096 scrollback lines, scrollback indicator hidden, cursor blink off. Renderer worker policy remains Foot's product default.
- **Kitty**: 8 pt, `repaint_delay 4`, `input_delay 0`, `sync_to_monitor no`; cursor trail/blink, blur and shell integration disabled; ligatures disabled for the benchmark font path.
- **Alacritty**: 7 pt, auto renderer, no decoration/padding/blur, cursor blink off, 1 px vertical font offset for a comparable line lattice, 4096 history rows.
- **Konsole**: built-in profile in an isolated config root, 7 pt Iosevka, chrome/transparency off, fixed 4096-line history, hidden scrollbar, blink/animation/bidi/semantic hints disabled, one unit of line spacing for comparable vertical metrics.
- **WezTerm**: 7 pt, benchmark-only Lua config, tab/chrome/animation/blur-like extras removed, 4096 history rows, common ligatures disabled. Renderer front-end is OpenGL, selected from measured A/B evidence: WebGPU missed 240 Hz at the high-density dose-4096 canary while OpenGL sustained it with lower CPU and far lower RSS.

On Home KDE/KWin Wayland, exact 1920x1036 placement currently probes near 378-384 columns and 74-77 rows across the prepared horses. `tracks/kde.env` therefore fixes the common workload lattice at 378x74 (27,972 cells).

Before a race:

```bash
set -a; source tools/performance/tracks/kde.env; set +a
./tools/performance/horses.sh doctor
./tools/performance/horses.sh calibrate
```

Raw receipts remain authoritative. Any later scalar index must preserve cadence survival, CPU, memory and topology as separate visible dimensions.

CPU summaries cover the complete terminal process tree, including TUI Zoo.
Intervals in which the process set changes have no CPU sample: subtracting
lifetime ticks across producer exit would create a negative interval. Older
captures can contain that error; recalculate stable intervals or rerun before
comparing their average CPU.

Each race and calibration probe retains cleanup for its fresh window and process
identities as soon as they are known. Placement/metadata failures and interrupts
release the runner, stop the sampler, and clean up only that owned process tree.
Version output is drained before selecting its first line, so extra diagnostics
do not introduce a SIGPIPE failure; genuine version-command failures still fail
the run.


## Isolated visual KWin lab

Autonomous Howl work should not consume Captain's physical desktop. WMIO can
route the same marshal through a managed KWin compositor with its own Wayland,
D-Bus/XDG roots, and private EIS seat.

The persistent visual lab is created outside the repository:

```bash
wmio create-environment private-howl-lab --width 1920 --height 1080 --scale 1 --visible
```

`--visible` keeps the managed compositor isolated while nesting its output as
one host window so Captain can watch or intervene. Input issued with
`wmio --environment private-howl-lab ...` stays on the private seat and does
not use Home's physical keyboard/mouse path.

Source `tracks/kwin-private-visible.env` for this lane:

```bash
set -a; source tools/performance/tracks/kwin-private-visible.env; set +a
./tools/performance/horses.sh doctor
./tools/performance/horses.sh probe howl
./tools/performance/horses.sh run howl 16
```

`HORSES_ENVIRONMENT` defaults to `physical`; changing it routes all WMIO
observation/mutation and process launch through that managed environment.
Managed clients are launched with `wmio --environment ID launch`, never by
inheriting the caller's physical Wayland session. `HORSES_HOME_DIR` preserves
the real workspace/evidence root inside managed environments whose own `HOME`
is intentionally private.

The visual nested client area is presently 1912x1047, with Howl probing at
380x76, so the track retains the established 378x74 cell lattice. Treat its
numbers as a separate KWin-private track; do not splice them into the earlier
physical 1920x1036 KDE index without an explicit cross-track qualification.

## Benchmark Howl build

`build-howl-fast.sh` creates a self-contained race binary under `~/.local/state/howl-performance-index/howl-fast`: native Zig bridge/dependency graph in ReleaseFast and Odin `-o:speed` without the daily `-debug` safety instrumentation. The normal dogfood binary is not modified.

The `cells` workload accepts doses through 65,536; the default sweep now extends through 8,192, 16,384, 32,768 and 65,536 to find real saturation knees.

Select background and Unicode performance canaries without changing the track:

    HORSES_GLYPH_SET=alnum HORSES_BACKGROUND=1 ./tools/performance/horses.sh run howl 4096
    HORSES_GLYPH_SET=unicode HORSES_BACKGROUND=1 ./tools/performance/horses.sh run howl 4096

The run metadata records both selectors. Producer FPS measures emitted frames
and stdout backpressure; it does not establish displayed FPS or Unicode rendering
correctness. Keep each configuration in its own dose curve.


## Private native qualification (2026-10-08)

The overnight comparison used a private 1920x1080 compositor, the same
378x74 alnum payload, synchronized output, a 240 fps producer target and
20-second ABFFBA ordering. Original Howl was product source fc0f339; the
presentation-credit checkpoint was 713a21e, with harness cleanup at 2641889.
Howl exposed 381x78 PTY cells and Foot 384x77; the common payload fits both.

These CPU values separate terminal processes from TUI Zoo using the raw
per-PID samples, excluding intervals with process-set changes. They differ
from the harness's complete-tree CPU summary. Percentages refer to one CPU core.

| Dose | Original Howl producer fps / terminal CPU | Scheduled Howl | Foot |
| --- | --- | --- | --- |
|4096|239.849 /87.45%|239.999 /37.18%|239.999 /30.91%|
|8192|164.690 /81.11%|180.921 /43.37%|196.374 /42.15%|

The scheduled checkpoint used about 57.5% less terminal CPU at 4096 and
46.5% less at 8192, with about 9.9% more producer throughput at 8192. Both scheduled
Howl 4096 runs had zero skipped slots; original Howl had 6 and 0. Foot still led
the 8192 producer comparison. Raw receipts and per-PID folds are retained in
the Home workstream gait-20261008/night-direct-controls files.

Producer fps describes emission and stdout backpressure. A separate
scratch-only frontend counter measured about 60 successful SDL presents and
60 new frame ingests per second in warm 4096/8192 runs; producer fps must not
be presented as displayed fps.

A subsequent static inlining refinement at the generated-glyph classifier
call site retained its ordinary public function type and classification
behavior. Independent 12-second ABBA comparisons against 713a21e gave:

| Case | Terminal CPU before / after | Producer fps before / after |
| --- | --- | --- |
|4096 alnum|38.04% /37.17%|239.957 /239.998|
|8192 alnum|43.17% /42.47%|181.086 /181.025|
|4096 Unicode/background|60.85% /60.47%|226.206 /226.088|

The small 8192 and Unicode producer decreases are retained explicitly.
Warm frozen projection comparisons also favored the inlined call, but baseline
variance prevents a single headline stage percentage. These later comparisons
are separate measurements and must not be added to the whole-night ratios.

End-to-end ownership checks used scratch-only frontend logs over the accepted
native bridge. A hidden tab processed 1,048,576 cell writes with no frame
ingests while hidden, then resumed at its exact canonical revision with
27,975 immutable Render commands. A quiet synchronized-output hold retained
the older frame and caught up after about one second without further child
output. The hidden fixture uses TUI Zoo oracle mode to preserve final glyphs;
ordinary producer cleanup would otherwise clear the frozen view.
