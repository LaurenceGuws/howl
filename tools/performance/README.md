# Terminal performance track

Open [race.html](race.html) directly from disk for the bird's-eye race overview.
It is one self-contained HTML snapshot: no server, Python runtime, scripts, polling
or focus follower. Update its values and named provenance together after a qualified
race, then refresh the browser. Keep separate builds/cohorts separate; unmeasured
horses and metrics stay explicit. Raw workstream receipts remain authoritative.

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
remain separate. Both16-cell Howl trials show PSS growing during the20-second
run from157–217MiB to1.62–1.67GiB, predominantly in Pss_File, with large
Private_Dirty growth. Anonymous peaks are56–105MiB. Almost all PSS belongs to
howl-app itself. Exact mapping/allocator attribution is unresolved; this is
repeated growth, not merely a cold-start spike. Anonymous memory is not a
complete RAM total. Later backend controls did not reproduce the large PSS.
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

The app Canvas now shares immutable quad indices instead of rebuilding them
for each draw. Eight 20-second A/B/B/A cursor/Unicode controls preserved producer
cadence and passed the existing Fast/Safe pixel, clipping and residency proofs.
Cursor terminal CPU measured 21.62–21.82% before and 21.32–21.47% after.
Unicode/background measured 55.54–58.68% before and 54.99–55.54% after; baseline
variance prevents a headline Unicode improvement. This is a small draw cleanup,
not a displayed-frame-rate or latency claim.

Writable Geometry scratch decreases by 48KiB per window; one 48KiB read-only
table replaces it. The linked Safe ELF grows by 130,987bytes, with read-only
data increasing 49,152bytes and text decreasing 64bytes. No resident-RAM saving
is inferred from startup peaks. All eight owned process trees and the private
compositor retired cleanly. `QUAD_INDICES_RESULT.md`, raw/folded controls, ELF
section sizes and artifact hashes are retained in the night workstream.
## SDL backend boundary control, 2026-10-10

At runtime `63a0f96`, twelve ordinary 20-second OpenGL/Vulkan/Vulkan/OpenGL
controls used the same private geometry and verified Fast producer as above.
Only SDL's installed `SDL_RENDER_DRIVER` hint changed; no product source changed.
Terminal CPU excludes producer and shell, with stable PID intervals reconciled
against the tree.

| Canary | OpenGL terminal CPU | Vulkan terminal CPU | OpenGL / Vulkan producer fps |
|---|---:|---:|---:|
| cursor 60Hz | 22.13–22.33% | 32.91–36.00% | 60.0 / 60.0 |
| Unicode/background 4096 | 59.14–61.32% | 80.86–81.22% | 240.0 / 239.8–239.9 |
| alnum 65536 | 104.30–104.51% | 114.28–115.75% | 113.1–114.3 / 102.3–103.9 |

These are same-session backend controls, not a new reference matrix or an
attribution of change since the overnight measurements. Producer progress is not
displayed FPS. Six separate instrumented diagnostics found roughly 104k vertices
per cursor presentation with either backend; full content projection, publication
and Canvas geometry remain. Block cursor publication scans the content command
list both to count overlap and to append recoloured glyphs.

Warm `smaps` cuts distinguish font files, driver libraries/device mappings and
anonymous storage. OpenGL loaded a runtime LLVM library here; Vulkan did not.
Lower Vulkan PSS does not establish lower owned RAM: rich/heavy peak anonymous
memory increased. Anonymous mappings alone do not identify the allocating
module. The current default renderer stays; direct native presentation remains
an experiment requiring mixed-workload and memory controls.

All 18 owned process trees and both private environments retired cleanly;
temporary interposers/binaries/launchers were deleted. Exact stage counts, warm
maps, artifacts, ordinary CPU folds and cleanup are in
`night-20261010/sdl-boundary-20261010/RESULT.md` under the current workstream.


## Cursor/content separation, 2026-10-10

Against a fresh b2c67af Fast baseline, sixteen final 20-second controls used the
same OpenGL renderer, private geometry, common payload and verified Fast TUI Zoo.
Cursor60 terminal CPU falls from 21.87–22.08% to 2.23–2.38% of one core (89.5%).
Same-session Kitty measures 1.82–1.92%, Foot 1.32%; both still lead this control.
Unicode/background 4096 averages 56.79% before and 56.73% after at 240 producer fps.
Heavy 65536 remains around 119 producer fps; no throughput win is claimed.
CPU excludes producer/shell and reconciles duration-weighted stable PID intervals.

VT now retains canonical content mutation identity separately from cursor facts.
Render retains one content command list and indexes clipped cursor ink by physical
row. Instance reuses unchanged prefixes in its existing three immutable frame
slots; growth, aborted preparation or presentation changes invalidate reuse.
Canvas retains physical content pixels beneath the cursor overlay and releases
them when hidden. Cursor movement no longer rebuilds cells, shaping, full frame
prefixes or full content geometry after warmup. No canonical observer authority
or cursor animation clock was added.

The cost is roughly 5–7 MiB more anonymous storage in paired warmed samples;
cold memory outliers remain recorded. No owned-RAM or fastest-overall claim.
Root, Safe/Fast, full-projection/slot/overhang/pixel/fractional proofs pass.
Six fzf and six nvim cycles also return correctly in a private 1.25-scale GUI.
All 32 experimental controls retired cleanly. Source diffs, hashes, stable CPU
folds, memory samples and cleanup are retained at
night-20261010/cursor-pristine-20261010/RESULT.md in the current workstream.


## Static header presentation, 2026-10-10

On the accepted cursor/content architecture (a2930ed), the two unchanged header
symbols were still rendered into new SDL textures on every presentation. Five
small rectangles now paint them through the existing caption lane; no retained
text cache, owner or allocation was added. Cursor/content machinery is unchanged.

Sixteen fresh-process controls use the same private geometry, font recipes,
OpenGL hint and verified Fast producer as above. Cursor60 terminal CPU falls
from 2.58–2.73% to 2.13–2.28% of one core (17.1%). Unicode/background maintains
240Hz without a consistent CPU regression. Saturated heavy progress varies:
121.1–123.7 producer fps before and117.6–122.4 after; no throughput equivalence
or win is claimed. Four fixed-work heavy20Hz controls complete exactly400 frames
each, with terminal CPU22.68–22.94% before and22.38–22.53% after.
Same-session Kitty overlaps the new cursor range; Foot still leads.

The sampler now reads each process name, start epoch and counters from one stat
record, reports vanished facts as null and rejects reused/negative deltas.
Tree CPU sums valid per-PID deltas. The previous accepted fold already rejected
its bad producer-exit cut; earlier pristine results are unaffected. Five
deterministic sampler fault cases and the fixed-work live controls pass.

No general RAM, displayed-FPS or latency claim. App code adds14 lines and
replaces2; the sampler replaces16 lines. Fast ELF grows4864 bytes, with writable
data/bss unchanged. Root/Safe/Fast/audits and private fractional-scale
Settings/New Tab GUI pass. Artifacts, raw stable CPU folds, memory samples,
fault receipts and cleanup are in
night-20261010/cursor-iterate-20261010/RESULT.md under the current workstream.

### Projection failure recovery, 2026-10-10

A controlled 128-glyph CJK page at 48 px exceeds howl-app's fixed 512×512 atlas.
Both builds report AtlasFull and retain the prior successful pixels. After the
child clears to fitting text, fbab07e stays frozen; the successor presents the
new page and clears the error. The worker now blocks only the failed canonical
contentSequence and history viewport. Cursor-only changes retain the block and
observer credit. New content or a changed viewport can attempt; successful
publication clears the failure. Atlas bounds and cursor ownership stay fixed.

Captain's separate late second-buffer nvim report remains unresolved. Nine
isolated scratch/server.go buffer switches at 1.25, 1.75, 2.0 scale with Captain's
four Iosevka faces and size 18 showed no visible failure; this does not reproduce
the unknown previous artifact, plugins or transient frame.

Twelve matched 20-second ReleaseSafe A/B/B/A controls used the same Fast TUI Zoo
producer and private 1920×1080 OpenGL environment. Duration-weighted terminal CPU
excludes the producer and shell, using valid stable process identities:

| Case | fbab07e CPU, one core | Successor CPU, one core |
| --- | --- | --- |
| Cursor 60 Hz | 2.13–2.18% | 1.98–2.28% |
| Unicode/background 4096 cells, 20 Hz | 13.67–13.72% | 13.52–13.67% |
| Heavy 65536 cells, 20 Hz | 28.56–28.96% | 28.51–28.56% |

All producer slots completed (cursor 1200, other cases 400 each); no missed slots.
This qualifies healthy fixed-work behavior, not a speed or RAM improvement.
The first baseline memory peak was cold; remaining anonymous-memory ranges
overlap. No atlas or content-target budget grew. Safe ELF bytes decreased 9493.

A separate instrumented Safe profile excludes initial placement and producer
shutdown, observing seconds 5–20 after the first presentation. Warm cursor:
899 presentations, zero texture creation/destruction, zero TTF raster calls and
zero content-target changes. GUI-thread CPU 1.60%; inclusive SDL_RenderPresent
1.07%. Rich output still rebuilds content and flushes target changes. These
inclusive call clocks guide the next boundary investigation; they are not an
uninstrumented whole-process comparison or proof of driver-internal attribution.

Evidence and replay recipes remain in Home's active Howl workstream under
zig-app-20261008/night-20261010/cursor-atlas-20261010. Temporary probes are retired
after qualification. The maintained child-barrier proof covers failed projection,
unchanged cursor-only credit, canonical service, and successful content recovery.

### Tab memory attribution, 2026-10-10

Captain reported about 585 MB after two hours of nvim/btop with three tabs and
roughly 80 MB more per new tab. The pre-shutdown root app snapshot was 553.7 MiB
RSS, 248.5 MiB PSS and 125.4 MiB anonymous. Its loaded ELF was fbab07e Safe;
the current repo artifact is the 172d212 Safe runtime. These process metrics
exclude child applications, and the reported display's unit was not confirmed.

Three fresh private 1920×1080 OpenGL runs used Captain's four Iosevka faces at
18 px, a small four-style Latin/CJK fixture, and the tab sequence
1→2→3→2→1→2→3→2→1. Each state retained 16 snapshots over four seconds.
The two warm runs' first openings showed these increments per tab:

| Root app metric | Increment, MiB |
| --- | --- |
| RSS | 79.4–83.7 |
| Font mapping RSS, included above | 61.0–64.9 |
| PSS | 18.9–23.0 |
| Anonymous | 13.8–18.3 |

Every pane opens four independent native style font sets, each with the same
Arabic/CJK fallback files. The three-tab live capture contained 12 CJK mappings:
98.2 MiB summed RSS but 6.3 MiB PSS. Repeated mappings explain much of the visible
RSS step; it is not an equivalent increase in private RAM. Mutable native faces
remain exclusively owned by their workers.

Closing tabs removes the added font mappings and about 9 MiB anonymous per tab.
The warm runs still retained about 14.1 MiB anonymous after the first cycle and
another 2.27 MiB after the second. Most of that residual was in [heap]; its
consumer is not yet identified. A separate native allocator probe repeated all
27 states: after the first cycle, the warm runs retained 6.3–8.6 MiB more in free
native chunks and 3.21 MiB more in chunks reported in-use. The second cycle added
only 80 KiB to native arena capacity and 28–29 KiB to reported in-use chunks,
while process anonymous residency changed more. Allocator caches and the live
consumer remain to be attributed. Cold runs stay recorded. Two cycles do not
establish leak freedom, long-session behavior or a RAM improvement; neither
control reproduces the historical 1.6 GiB file-PSS growth. No runtime code changed.

Raw mapping cuts, recipes, artifact identities, lifecycle checks and cleanup
receipts are in the active Home workstream at
zig-app-20261008/night-20261010/live-memory-20261010. The final private GUI shows
all four styles and CJK without an error; all owned processes/environment retired.
