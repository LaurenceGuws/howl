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

Raw samples also retain per-PID CPU and memory so terminal costs can be separated
from TUI Zoo and the shell/marshal. Complete-tree summaries remain unchanged.

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

`build-howl-fast.sh` builds the Local-only Zig app and its proofs in ReleaseFast under `~/.local/state/howl-performance-index/howl-fast`. The app retains its tracked LLVM codegen/selfhost-linker policy. `horses.sh` uses the independent benchmark `app.json`; the normal dogfood binary and user settings are not modified. `HORSES_HOWL_FAST_ROOT` selects a workstream-owned artifact directory.

The `cells` workload accepts doses through 65,536; the default sweep now extends through 8,192, 16,384, 32,768 and 65,536 to find real saturation knees.

Select background and Unicode performance canaries without changing the track:

    HORSES_GLYPH_SET=alnum HORSES_BACKGROUND=1 ./tools/performance/horses.sh run howl 4096
    HORSES_GLYPH_SET=unicode HORSES_BACKGROUND=1 ./tools/performance/horses.sh run howl 4096

`HORSES_WORKLOAD=rain` selects the diffed Rain canary with the same geometry,
cadence and duration. The explicit workload selector reaches the terminal-side
runner even in managed environments.

The run metadata records the workload and both selectors. Producer FPS measures emitted frames
and stdout backpressure; it does not establish displayed FPS or Unicode rendering
correctness. Keep each configuration in its own dose curve.


## Private native qualification (2026-10-08)

The overnight comparison used a private 1920x1080 compositor, the same
378x74 alnum payload, synchronized output, a 240 fps producer target and
20-second ABFFBA ordering. Original Howl was product source fc0f339; the
presentation-credit checkpoint was 713a21e, with harness cleanup at 2641889.
Howl exposed 381x78 PTY cells and Foot 384x77; the common payload fits both.

These historical Odin CPU values separate terminal processes from TUI Zoo using the raw
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

A separate 12-second ABFFBA saturation run compared the same original source,
the classifier-inline refinement at 080fb7f, and Foot on the same track and
payload lattice:

| Dose | Original Howl producer fps / terminal CPU | Refined Howl | Foot |
| --- | --- | --- | --- |
|32768|42.276 /61.46%|46.403 /40.92%|48.554 /76.55%|
|65536|21.308 /56.92%|23.288 /37.01%|24.399 /57.00%|

At these doses, refined Howl emitted about 10% more frames than the original
while using about 33–35% less terminal CPU. Foot emitted about 4–5% more than
refined Howl and used more terminal CPU. These remain separate dimensions.
Raw receipts and per-PID folds are retained in the workstream
saturation-direct-controls files.

A separate scratch frontend counter over the refined native bridge retained
about 60 SDL presents per second. New frame ingests followed the producer:
about 46.2/s at 32768 and 21.2–21.6/s at 65536. These instrumented cadence
probes emitted 46.210 and 21.438 producer fps respectively; their throughput
must not be substituted for the uninstrumented control table above.

Eight final-source native oracle cases covered 32768/65536 writes, alnum/
printable glyphs, synchronized output, and stalled/demanding observers.
Every final foreground scalar hash matched the independent TUI Zoo oracle,
and every requested quiet immutable frame reached its canonical revision.
This establishes terminal-state agreement separately from SDL cadence.

End-to-end ownership checks used scratch-only frontend logs over the accepted
native bridge. A hidden tab processed 1,048,576 cell writes with no frame
ingests while hidden, then resumed at its exact canonical revision with
27,975 immutable Render commands. A quiet synchronized-output hold retained
the older frame and caught up after about one second without further child
output. The hidden fixture uses TUI Zoo oracle mode to preserve final glyphs;
ordinary producer cleanup would otherwise clear the frozen view.

## Local app reference control, 2026-10-10

At `5704b4b`, the new app was measured in ReleaseFast against Foot, Kitty and Alacritty in a private 1920×1080 KWin environment at scale 1, with Howl at 10px and Iosevka reference recipes calibrated to 384 PTY columns, the same 378×74 TUI Zoo payload, 240 Hz target and 20-second trials. There were 40 successful fresh-process trials; the 4096/8192/65536 alnum doses were repeated in reverse horse order. Values below are producer fps / terminal CPU percent of one core, excluding TUI Zoo and the shell.

Producer correction: the original TUI Zoo artifact generated only about27Hz
at dose65536 even to `/dev/null`. Rebuilding its old source with explicit
ReleaseFast holds240Hz to that sink. This table measures a pipeline near the
original producer ceiling at heavy doses; maximum terminal consumption is not
established. The8192 knee interpretation needs optimized-producer controls too.
Raw trials and separated terminal CPU/RAM remain useful. Future receipts record
`tui_zoo_build` (compiler, optimization, backend) from the actual executable's
`build-info`, plus its path/hash. Unsupported older binaries record null.
See `PRODUCER_CEILING_RESULT.md` in the night workstream. No Howl throughput
improvement is attributed to changing the producer.

| Canary | Howl | Foot | Kitty | Alacritty |
|---|---:|---:|---:|---:|
| alnum 16 | 240.0 / 18.5 | 240.0 / 3.5 | 240.0 / 24.6 | 240.0 / 13.6 |
| alnum 4096 | 240.0 / 33.6–33.9 | 240.0 / 30.8–31.1 | 240.0 / 103.3–103.8 | 240.0 / 28.1–29.6 |
| alnum 8192 | 184.4–186.3 / 39.0–39.7 | 200.6 / 41.9–45.2 | 213.0–213.1 / 106.4–107.1 | 211.4–213.6 / 39.7–40.0 |
| alnum 65536 | 23.7–23.8 / 34.0–34.3 | 25.1–25.3 / 58.4–59.5 | 26.8 / 38.4–38.9 | 23.5–23.6 / 25.6–26.1 |
| unicode-bg 4096 | 237.3 / 55.0 | 239.8 / 94.6 | 240.0 / 90.1 | 240.0 / 40.6 |
| plain 4096 | 240.0 / 33.7 | 240.0 / 30.7 | 240.0 / 103.9 | 240.0 / 29.5 |
| rain | 240.0 / 6.2 | 240.0 / 15.5 | 240.0 / 19.0 | 240.0 / 8.9 |

This is a historical baseline. Its heavy-dose cadence is near the original producer ceiling; use the verified optimized-producer controls below for current pressure comparisons. Foot has the smallest anonymous footprint in these controls: approximately 19–27 MiB for its complete process tree, versus 44–67 MiB for Howl, 83–93 MiB for Kitty and 37–43 MiB for Alacritty. Producer cadence measures PTY/backpressure, not displayed fps or photon latency. Full PTY extents differ by three rows (Howl 384×79, Foot/Kitty 384×77, Alacritty 384×80); payload extents are identical. The 16-cell canary progressively fills the viewport, so it also pressures full-frame drawing of retained content.

Raw receipts and CPU reconciliation are in `~/.local/state/workstreams/howl-current/zig-app-20261008/night-20261010/`: `REPORT.md`, `REFS.jsonl`, `FOLDED.json`, `runs/` and `CLEANUP.json`. Every stable interval reconciles per-PID and tree CPU; all 40 owned process trees and the private compositor retired cleanly. PSS is retained separately: the first Howl cold launch has a 1.6 GiB PSS outlier that is not explained by its 67 MiB anonymous footprint, so PSS must not be relabelled as owned host RAM. The normal ReleaseSafe dogfood binary and user settings were not changed during this baseline.

## Empty preedit repaint qualification, 2026-10-10

An app-only SDL feedback path could present old frames: updating the IME caret
could elicit an empty editing acknowledgment, whose unconditional redraw moved
the caret again while canonical output was changing. The app now processes that
event without redrawing when composition was already empty. Active composition,
clearing, input, failures and timer expiry retain their redraws. Worker wake
coalescing and renderer/VT architecture were not changed.

Twenty-three uninstrumented A/B/B/A and reference trials qualified the change.
At 1 Hz with 4096 cells, terminal CPU fell from 0.66–0.81% to 0.46–0.51% of one
core. A capped 65536-cell control completed exactly 400 frames at 20 Hz in every
trial: terminal CPU fell from 25.98–30.84% to 22.95–22.99%. This is an equal-work
CPU saving. One saturating candidate trial had lower producer cadence
(22.77 versus baseline 23.86–24.10 fps), so maximum throughput improvement is not
claimed. Unicode/background remains near 238–239 producer fps without a CPU win.

The raw controls, separated CPU samples, binary hashes and cleanup receipts are
beside the reference baseline in `night-20261010/`: `AB.jsonl`, `CAPPED.jsonl`,
`AB_FOLDED.json`, `EMPTY_PREEDIT_RESULT.md`, `ab-runs/` and `capped-runs/`.
All 23 owned process trees and both private environments retired cleanly.
Root checks/tests/protocol/audits and both app optimization-mode proofs passed.
A per-call probe rejected a header-text cache: rasterization and texture creation
were only about 1–2% of measured app CPU. Temporary instrumentation stays outside
accepted source.

Use `HORSES_WORKLOAD=cursor` with `HORSES_DOSES=1` to pressure cursor movement over
a populated retained viewport. TUI Zoo's `cells --cursor-only` primes ASCII cells
once and then emits cursor moves; its receipt records `cursor_only: true`.
This isolates presentation cost from bulk glyph/PTY production. Priming can
contribute to host startup samples. Unicode/background options are incompatible.
The independent TUI Zoo binary must include the mode; it has no terminal-specific
knowledge or dependency.

At `79fdc75`, 24 fresh-process controls used this canary at 1/60/240Hz,
20 seconds each, in forward/reverse horse order with the same private geometry
and calibrated font recipes as above. All producer frames completed without
skipped slots. Terminal CPU excludes producer and shell:

| Target Hz | Howl | Foot | Kitty | Alacritty |
|---:|---:|---:|---:|---:|
| 1 | 0.41–0.46% | 0.00–0.05% | 0.05% | 0.25% |
| 60 | 21.77% | 1.52–1.77% | 2.13–2.28% | 14.13–14.23% |
| 240 | 21.67–21.87% | 2.03–2.33% | 5.16–5.47% | 15.90–16.41% |

This exposes a retained-content cursor cost; it does not identify its cause.
Howl enables VSync and observer frame credit, so producer cadence is not displayed
frame rate. Excluding the first second leaves the 60Hz gap intact. The 1Hz values
are near scheduler tick resolution. All owned processes and the private
environment retired. Raw per-PID receipts, binary/config hashes and the
full/post-priming fold are in `night-20261010/CURSOR_RESULT.md` and
`CURSOR_FOLDED.json` under the current workstream.

The local app recipe leaves retained-row cache capacities at their zero defaults.
Its direct VT source supplies no revision-relative repair hints, so the previous
32768-command cache and row scratch were never used. Removing that reservation
saves about 2.26MiB of requested buffer storage per pane; resident-memory impact
requires a separate measurement. Transported renderer clients keep their own
row-reuse configuration.

## Verified optimized producer, 2026-10-10

At runtime `ec8a7f4`, 44 fresh-process 20-second trials repeated the same private
geometry, calibrated font recipes, 378×74 payload and 240 Hz target. Every
receipt verifies the actual TUI Zoo executable: source `3dbd021`, compiler
`0.17.0-dev.1980+e78ea8f2c`, optimization `fast`, backend `stage2_llvm`, and
artifact SHA256 `87ce7c1038f2737493c8f89a14cd386dc27ccb0a958887855e986687a5c48557`.
Alnum doses ran in forward/reverse order; the remaining canaries ran once per
horse. Values are producer fps / terminal CPU percent of one core, excluding
producer and shell.

| Canary | Howl | Foot | Kitty | Alacritty |
|---|---:|---:|---:|---:|
| alnum 16 | 240.0 / 18.1 | 240.0 / 3.7 | 240.0 / 25.1 | 240.0 / 13.3–13.9 |
| alnum 4096 | 240.0 / 32.7–33.6 | 240.0 / 30.8–31.5 | 240.0 / 102.4–103.0 | 240.0 / 27.9–28.2 |
| alnum 8192 | 240.0 / 43.4–43.8 | 240.0 / 57.0–57.6 | 240.0 / 107.2–107.8 | 240.0 / 40.1–40.6 |
| alnum 65536 | 126.3–126.7 / 103.9–104.4 | 149.0–149.8 / 174.7–176.0 | 108.9–111.1 / 125.6–127.8 | 101.7–104.2 / 96.4–97.3 |
| unicode-bg 4096 | 240.0 / 55.2 | 239.9 / 94.2 | 240.0 / 74.9 | 240.0 / 37.9 |
| plain 4096 | 240.0 / 33.4 | 240.0 / 31.2 | 240.0 / 104.4 | 240.0 / 28.0 |
| rain | 240.0 / 6.5 | 240.0 / 15.8 | 240.0 / 19.4 | 240.0 / 8.9 |

All four sustain the target through 8192. At 65536, Foot has the greatest
producer progress, followed by Howl, Kitty and Alacritty. Howl uses less terminal
CPU than Foot at that dose, but completes less work; these are separate
dimensions. The changed producer establishes a different pressure control, not
a Howl runtime throughput improvement. Producer cadence does not prove displayed
frame rate or latency.

Peak complete-tree anonymous memory at 65536 was Howl 52.6–53.1 MiB, Foot
17.0 MiB, Kitty 86.5–89.2 MiB and Alacritty 39.9 MiB. PSS and startup peaks
remain separate; the cold Howl PSS outlier persists and is not owned-RAM evidence.
All 44 owned process trees and the private compositor retired cleanly.
Raw receipts, per-PID CPU folds, artifact identities and cleanup are in the
current night workstream: `FAST_REFS_RESULT.md`, `FAST_REFS.jsonl`,
`FAST_REFS_FOLDED.json`, `FAST_REFS_ARTIFACTS.json`, `FAST_REFS_CLEANUP.json`
and `fast-producer-runs/`.

A cursor-only projection experiment reused existing Renderer commands using
Instance-owned live row/color provenance. Three variants passed root and app
Fast/Safe proofs, including complete-frame equivalence, held-lease immutability
and failed-refresh recovery. Across 36 A/B/B/A trials, cursor terminal CPU fell
from about 22% to 14%, but Unicode/background CPU repeatedly increased. The
smallest variant measured 55.85–55.95% before and 56.66–57.77% after at the same
240 Hz producer target. Removing temporary snapshots reduced the penalty without
eliminating it. The source was restored; no provenance cache or cursor-only API
is retained. The cause of the mixed-workload regression is not established.
All 36 owned process trees and three private environments retired cleanly.
`CURSOR_REUSE_REJECTED.md` and the three variant receipts in the night workstream
retain the decision and raw controls.
