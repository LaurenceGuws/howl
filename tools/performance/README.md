# Terminal performance track

Open [race.html](race.html) directly from disk for the bird's-eye race overview.
It is one self-contained HTML snapshot: no server, Python runtime, scripts, polling
or focus follower. Update its values and named provenance together after a qualified
race, then refresh the browser. Keep separate builds/cohorts separate; unmeasured
horses and metrics stay explicit. Raw workstream receipts remain authoritative.

## Current DP-1 race and calibration

[DP1.md](DP1.md) is the current four-horse setup: physical 1920×1080, scale 1,
240 Hz, native fullscreen **384×83 cells**, **5×13 pixels per cell** for Howl,
Foot, Kitty and Alacritty. It documents version-matched settings, Alacritty's
warning repair, pacing choices and actual full-grid/corner proofs. The configs
under configs/ contain these choices. New races must verify the whole native
grid and use the full 384×83 producer lattice. The fresh 32-run physical Hyprland
race is recorded in [race.html](race.html#dp1-race-20261021), including every CPU
observation, cold memory peak and producer miss.

## Rain cadence lanes

[RAIN.md](RAIN.md) adds explicit **60 / 120 / 240 fps** rain workloads with the
same full 384×83 native grid and seed across all four horses. Rain accepts
`--fps`, `--duration-ms`, `--frames`, `--seed`, `--cols`, `--rows` and synchronized
output. Requested/achieved producer cadence, missed slots, changed cells,
producer timing, terminal CPU and memory remain separate measurements.
Increasing fps also increases rain's simulation steps and work per second.
Actual presentation timing remains a separate observation requirement.
The [completed 24-run private sweep](race.html#rain-cadence-20261022) records two
fresh 20s trials per horse/rate, every CPU/memory observation, producer work and
miss. Total producer skipped slots: 22; all geometry and raw metrics reconcile.
No product source or installed binary changed.

## Row repaint screen · 22 October

The [row repaint experiment](race.html#row-repaint-20261022) is rejected and fully
withdrawn. An optional bounded row witness passes the complete correctness gates,
18 exact native old/new comparisons and 123 cursor/UI captures. Four fresh 20s
Fast sparse SDL diagnostics still submit effectively identical work:
113,622.106 → 113,623.910 vertices per content target, **+0.001588%**.
All four producers sustain 239.999Hz with zero misses; the diagnostic receipts
have no resource events or throttling. No ordinary CPU improvement is claimed.

The first 3GiB whole correctness build passed but hit memory.max reclaim without
OOM/throttling; that limitation stays in its receipt. Restored-source verification
passes 1,206 reported tests and full check/audit at 4GiB, with zero resource events
or throttling. Current accepted source and
both installed Safe launch binaries are unchanged. Previous row-coalescing and
cell/tile-painter rejections remain relevant; they are linked as distinct older
cohorts rather than described as untried follow-ups. Raw qualification, archived
candidate source/ELFs, failed fixture attempts and every count remain in the
Home workstream's performance/sparse-paint directory.

## Physical Hyprland Fast race · 23 October

[The quick DP-1 race](HYPRLAND_FAST.md) records 32 fresh eight-second trials on
1920×1080/240 Hz Hyprland, all four terminals qualified at 384×83/5×13. Current
LLVM Fast Howl has lowest rain CPU, second-lowest plain CPU, and trails Alacritty
and Kitty on Unicode. Foot leads sparse CPU and anonymous memory. Active-window
CPU analysis excludes warmup/drain; five Foot producer skips and an interrupted
pre-timing launch remain explicit. This is a short physical-track observation,
not actual displayed-frame or input-latency evidence.

## Whole-path timing and design · 22 October

[The system timing review](SYSTEM_TIMING.md) corrects the compiler scope of the
isolated VT result and records matching LLVM costs plus 16 current-path trials.
All 9,097 checked prepared cuts reach acquisition and window submission; coalesced
row repairs drop glyph hints in every measured refresh. Sparse retains about 29,700
commands per cut versus rain's 572. The next complete experiment should connect
fine source evidence through Render to retained painting under the existing pacer.
Observer effects, producer misses and the unmeasured actual display timeline stay
explicit. Product source and installed binaries are unchanged.

## Logical mutation contract · 22 October

The [column-block contract experiment](BLOCK_CONTRACT.md) proves independent observers
can preserve column precision through skipped observations: 332/1,992 changed
blocks despite all 83 rows changing. Both implementations are withdrawn on write
cost. The first adds 7.90% Unicode wall time; the refined version adds 12.56%
plain process CPU, all eight pairs slower. These are VT-only measurements, not
application CPU or presentation timing. A pre-existing overlapping scalar-tail
move panic found by the oracle is fixed and has an exact six-operation proof.
No renderer, host or installed binary changed.

## Current Fast race and accepted scratch reuse · 22 October

The [latest Fast race](race.html#fast-race-20261022) records 48 fresh 20s trials
across Howl, Foot, Kitty and Alacritty at the complete native 384×83 grid.
Howl accepted source is 1e32216, qualified Fast ELF 83259505; daily installed Safe
is 814928a8. Exact upstream binaries, documented profiles, font and producer
are verified against accepted calibration. Keep this private cohort separate
from daily Safe and physical Hyprland results. CPU, producer emission/backpressure
and observed timed Anonymous/PSS peaks remain separate dimensions.

[Current Fast attribution](race.html#fast-attribution-20261022) adds eight separate
30s profiles: 71,756 user leaf samples across all three threads, zero loss or
throttling, and 41 hot source chains agreed by GNU/LLVM addr2line. Inspected hot runtime
PCs resolve to canonical VT parsing/actions. Four separate SDL submission
diagnostics show sparse text changes submit about 89.6–89.7% of plain geometry
vertices despite 1/64 the writes. The current host clears/repaints the full
content texture on changed content revisions; cursor-only motion already reuses
it. The later row repaint screen above rejects the conservative implementation;
complete immutable frames and pixel/resource/recovery guarantees remain preserved. Diagnostics
remain separate from ordinary CPU and displayed cadence.

The [scratch source controls](race.html#context-scratch-20261022) retain all
64 primary and 16 independent Fast observations. Reusing the same bounded arrays
once per projection saves 26.59% Safe Unicode CPU. Explicit costs remain:
Safe plain +0.46%; Fast plain +1.06% primary / +1.42% independent.
Fast Unicode changes direction between cohorts. This is an accepted bounded
tradeoff for the daily Safe gain, not a universal speedup.

Bounds, safety, native shaping, immutable output and retained state remain
unchanged. The independent multirow native raster oracle, complete root gates,
1,200 cursor compositions, 123 UI captures and four exact old/new native RGBA
comparisons at 10/18px in both modes pass. Four separate diagnostic postprofiles
corroborate removal of the repeated scratch-fill hotspot. A nullable on-demand
variant is rejected at code generation because it adds an unconditional clear.
The exact qualified Safe is atomically installed in both launch paths; Fast
remains a benchmark artifact. Raw hashes, source decisions, all adverse results
and sealed containment receipts remain in the Home workstream.

## Private full-grid and cursor controls · 22 October

The [current private cohort](race.html#private-cursor-race-20261022) records 48
four-horse pressure trials and 42 cursor-only trials at the exact 384×83 native
grid. Howl in that cohort is the preceding ReleaseSafe a9eaab2 artifact; keep it separate from
ReleaseFast and physical Hyprland. Private refresh is not exposed. Producer
emission/backpressure, whole-terminal CPU and observed timed Anonymous/PSS peaks
remain separate dimensions.

The [cursor batching candidate](race.html#cursor-batching-20261022) passes its
correctness gates and is withheld after 44 primary and 16 independent controls:
the small trail saving does not repeat at 240 Hz. The original Canvas and
installed cursor checkpoint remain accepted. [Current CPU attribution](race.html#scratch-profile-20261022)
identifies the contextual scratch initialization mechanism; the completed
[source controls](race.html#context-scratch-20261022) record its measured tradeoffs.

The benchmark build helper now targets `hosts/howl-app` and forwards build
arguments. Choose a separate artifact prefix and bounded jobs, for example:

```bash
HORSES_HOWL_FAST_ROOT=/absolute/benchmark-output tools/performance/build-howl-fast.sh -j2
```

## Historical tracks

The historical `horses.sh` harness uses WMIO's retired `--environment`/`launch`
interface and needs migration before reuse. Its recipes and old invocations below
remain evidence context. Current private cohorts run inside kwin-seat under
Walker; WMIO owns observation, placement and close through an exact attachment.

Benchmark profiles are separate from daily terminal settings. Current settings
are documented in [DP1.md](DP1.md). The older KDE recipe used different font sizes
and Kitty input-delay/synchronization choices; its configs remain in Git and raw
cohort evidence. Konsole/WezTerm entries are historical and are outside the current
four-horse calibration.

On Home KDE/KWin Wayland, exact 1920x1036 placement currently probes near 378-384 columns and 74-77 rows across the prepared horses. `tracks/kde.env` therefore fixes the common workload lattice at 378x74 (27,972 cells).

Historical invocation (the runner API needs migration before reuse):

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

Autonomous work uses kwin-seat under Walker's whole-workload containment.
The cohort is an existing workstream-owned executable; it launches its fresh
clients inside the inherited private environment and uses the exact attachment:

```bash
walker run --name howl-lab --cwd "$HOME/personal/howl" \
  --containment delegated_cgroup_v2 -- \
  kwin-seat run --directory /run/user/1000/howl-lab \
  --width 1920 --height 1080 --scale 1 -- /absolute/path/to/cohort
wmio --attachment /run/user/1000/howl-lab/attachment.json desktop
```

The seat directory must be new. The cohort owns copied configurations, exact
binaries, process identities, geometry, workload release and cleanup. kwin-seat
owns private D-Bus/HOME/XDG/input namespaces and retires with the workload.
WMIO attaches; it does not provision the seat or launch clients.
See the kwin-seat owner README for its current contract.

Keep private/physical tracks and actual presentation cadence separate. The old
`tracks/kwin-private-visible.env` geometry and managed-environment API describe
historical receipts and do not qualify the current owner interface.

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


### Shared text ownership, 2026-10-10

The app now shares one native font family and Render Store per matching recipe
and physical pixel size. Instance requires an explicit private/shared choice;
[its embedding contract](../../mods/howl-instance/README.md#presented-text-ownership)
defines reference lifetime, serialization and busy retries. Atlases and immutable
frames remain terminal-local. Shape and atlas pressure reset their own storage;
bounds are unchanged.

Three baseline/shared pairs used the same four-style Latin/CJK fixture and
two tab cycles. Cold first processes remain recorded. The warm fresh-tab costs
were:

| Root app metric | Baseline 172d212 Safe, MiB/tab | Shared Safe, MiB/tab |
| --- | --- | --- |
| RSS | 32.3–36.1 | 12.7–14.8 |
| PSS | 18.3–21.7 | 12.7–14.8 |
| Anonymous | 15.6–17.3 | 9.1–14.8 |
| Font mapping RSS, included above | 15.4 | 0 |

One font family remained mapped across matching tabs. The same baseline ELF
showed a smaller font residency step than the preceding 79–84 MiB capture; these
cohorts are not interchangeable. A zero tick change in each ~3.75-second quiet
cut is limited by CPU accounting resolution. Final screenshots decoded
pixel-identical. Native retention and long-session behavior remain open.

Three baseline/shared pairs per TUI Zoo case used 378×74, 240 Hz and 8 seconds.
All 18 producers emitted 1920 frames with zero skips. Sampled root app CPU,
excluding producer and shell, stayed close:

| Case | Baseline one-core CPU | Shared one-core CPU |
| --- | --- | --- |
| Cursor 16 | 1.875–2.125% | 2.000–2.125% |
| Background cells 16 | 15.750–16.125% | 16.000–16.375% |
| Background cells 4096 | 56.500–58.750% | 56.375–58.375% |

A final retry correction clears stale contention on each canonical service turn,
so a hidden pane or synchronized hold cannot retain a 1 ms retry. Separate native
controls qualify that artifact. The unstripped Safe ELF grew about 73 KiB.
These are process memory/CPU and producer-progress controls, not displayed FPS,
latency, leak freedom or fastest-overall proof. The old 1.6 GiB file-PSS trigger
remains unexplained. Exact source/artifact/config identities, cut-level data,
proof gates and retirement receipts are in the Home workstream at
zig-app-20261008/night-20261010/shared-text-20261010.

## Shared-owner and submission-boundary qualification, 2026-10-10

At parent `2acbde1`, eight fresh native one/two/four-pane controls ran 19
producers through 39,600 Unicode/background frames at 60/240 Hz with zero
skipped slots. The final four-pane fixture exercised a 384-glyph union against
the shared 256-entry glyph store, with each local atlas within its own bound.
Reviewed final captures contained no failure panel. Three one→two→four→two→one
pane cycles and repeated 18→19→18 font transitions preserved equal-recipe
mapping reuse and retired the second size's mapping. Nineteen quiet cuts
recorded zero root CPU ticks at sampler resolution. One-pane anonymous storage
retained about 10 MiB after three cycles; this is not a leak-free claim.

The current reference field is a separate 72-run cohort: nine cases, two fresh
20-second runs each for Howl, Foot 1.28.0, Kitty 0.49.2 and Alacritty 0.17.0,
forward then reverse order. All use a private 1920×1080 KWin output at scale 1,
the common 378×74 payload and verified native Fast producer source `3dbd021`.
Howl is Fast with LLVM codegen/selfhost linking on the pinned Zig compiler.
Measured PTYs are Howl 384×79, Foot/Kitty 384×77 and Alacritty 384×80.

Stable `(PID,start_ticks)` intervals separate terminal components, including
Kitty helpers, from TUI Zoo and shell/marshal costs. The HTML shows terminal
CPU, sampled peak PSS/anonymous memory and producer progress separately.
Root-only and complete-tree folds remain available. Howl leads Foot/Kitty rich
and Rain CPU; Foot still leads RAM and light cells, and Alacritty leads dense
and rich CPU. Foot emits the most saturation frames with more CPU. These are
observed ranges, not confidence intervals; no fastest-overall claim follows.

Both sparse dose-16 Howl reference runs reproduce roughly 1.6 GiB peak PSS,
with anonymous storage near 50–62 MiB. Raw `smaps` locates most growth in
`/dev/nvidiactl`: many distinct mapping sizes above 4 MiB appear as the text
grid fills. This identifies the resident mapping owner, not requested GPU
bytes or NVIDIA alone as the faulty component.

SDL 3.4.18's OpenGL queue merges adjacent same-texture geometry commands.
Its expanded textured vertices cost 192 bytes/quad, so a nearly full grid
passes 4 MiB despite our 2048-quad scratch bound. Local SDL source
`7bbd9d5c2c6925e5824de4288a1ed0bed0c0e5f7` exposes that handoff.
On installed NVIDIA 615.71.09, submitting each existing bounded batch with
`SDL_FlushRenderer` prevents the growing merged upload. It adds no renderer,
cache, allocation or GPU-completion wait.

Twenty interleaved ordinary controls qualify the small change against the
unchanged parent ELF. CPU is percent of one core; PSS is sampled peak MiB;
FPS means emitted native frames/s.

| Canary (n per variant) | Parent CPU / PSS / FPS | Bounded submission CPU / PSS / FPS |
| --- | ---: | ---: |
| small (3) | 18.11–18.92% / 1565.4–1634.4 / 239.999 | 16.15% / 92.9–96.0 / 239.999 |
| dense (2) | 35.59–35.90% / 150.1–158.3 / 239.999 | 35.29–36.30% / 96.0–96.3 / 239.999 |
| rich (2) | 58.73–60.00% / 109.7–118.0 / 239.999 | 55.14–55.64% / 97.8–106.4 / 239.999 |
| cursor240 (1) | 1.87% / 98.4 / 239.999 | 1.97% / 88.5 / 239.999 |
| unbracketed (1) | 36.00% / 155.5 / 239.999 | 33.62% / 99.3 / 239.999 |
| saturation (1) | 104.30% / 122.8 / 115.388 | 103.13% / 96.0 / 117.474 |

Light cells have three runs per variant, dense/rich two, the remaining cases
one. Preserve the cursor pair's small CPU increase explicitly; that single
pair cannot establish a regression or improvement. The sparse PSS reduction
is repeatable across all three controls. This is a submission-boundary fix,
not a new four-horse ranking: reference tables keep the parent artifact.

Final pixels are identical for fixed native ASCII/oracle frames and a full
mixed-style grid, with explicit OpenGL and ordinary SDL renderer selection.
Oracle hashes agree; the renderer name is retained by a temporary external
interposer. Final-frame parity does not prove displayed cadence or latency.
The final ReleaseSafe dogfood artifact also matches both Fast fixture images
exactly and passed app/root proofs, both audits, formatting and diff checks.
Safe ELF: 14,040,993 bytes; matched Fast ELF: 14,687,401 bytes.
No resident-RAM or cross-build binary-size saving is inferred from these lengths.
A fresh matched btop race and end-to-end latency/display measurements remain
open. Captain's running process and settings were preserved.

Exact artifact hashes, stable-identity folds, mapping cuts, native images,
gate logs and zero-process/zero-socket private-environment retirement are in
`zig-app-20261008/night-20261010/shared-race-20261010` under the current Home
workstream. The static `race.html` retains separate parent/reference and
submission A/B cohorts. Temporary probes are retired after qualification.

## Cursor index on demand, 2026-10-10

A 2 ms gprofng clock profile of the current Fast binary places most sampled
CPU in render derivation through the direct VT adapter, not canonical parsing.
Hot PCs include repeated glyph placement and painted-row cursor indexing.
The 30-second producer experiment includes startup/shutdown and is diagnostic;
the timings below are independent ordinary runs without the profiler.

Hidden, beam and underline cursors do not recolor glyph ink. Full content now
builds the painted-row index only for a block cursor. A later cursor-only block
transition builds it once from unchanged content commands. Content revision,
immutable publications, clipped overhang and atlas/shape bounds stay the same.
An interrupted index clears its ready flag before another cursor cut can use it.

Twenty-four interleaved 20-second controls compare unchanged ccb5ac0 Fast with
this change: three pairs for light cells, two for dense/rich/cursor/unbracketed,
one for saturation. Private KWin 1920×1080 at scale 1; common 378×74 payload;
Howl PTY 384×79; 240 emitted Hz, alnum/no backgrounds/synchronized output unless
named. CPU is percent of one core excluding producer and shells, PSS is sampled
terminal peak MiB, FPS measures emitted producer progress.

| Canary (n per variant) | ccb5ac0 CPU / PSS / FPS | Cursor index on demand CPU / PSS / FPS |
| --- | ---: | ---: |
| Light cells (3) | 15.90–16.10% / 96.1–150.8 / 239.999 | 15.19–15.44% / 96.2–97.5 / 239.999 |
| Dense cells (2) | 34.08–34.89% / 96.6–97.9 / 239.999 | 33.57–34.58% / 96.6–96.7 / 239.999 |
| Rich cells (2) | 57.06–57.47% / 97.9–104.1 / 239.999 | 56.20–56.36% / 98.7–106.3 / 239.999 |
| Cursor 240 Hz (2) | 1.92–1.97% / 85.8–90.2 / 239.999 | 1.97% / 85.9–86.2 / 239.999 |
| Unbracketed (2) | 33.11–34.68% / 96.5–96.6 / 239.999 | 32.61–33.37% / 96.5–96.6 / 239.999 |
| Saturation (1) | 103.23% / 96.8 / 118.979 | 103.54% / 96.5 / 119.696 |

Light-cell mean CPU falls 4.12%, from 15.983% to
15.325%. Rich and unbracketed controls also fall; dense ranges
overlap and the first dense pair is higher. Cursor ranges overlap and its
small increase remains recorded. All 22 non-saturation producers emit 4800
frames with no skips. The single saturation pair remains a limited control.
PSS varies, including a 150.8 MiB baseline light-cell outlier; no RAM saving,
displayed-FPS or latency improvement is inferred.

Four preceding forward/reverse controls with the same producer place unchanged
Howl at 15.797–16.050% and Foot 1.28.0 at 3.696% terminal CPU, all at 239.999
emitted fps without skips. Foot PTY is 384×77. Foot still leads light cells.
These fresh controls remain separate from the earlier four-horse cohort,
whose producer artifact differs despite the same TUI Zoo source and build mode.

The retained full-command oracle now covers content mutations with a hidden
cursor followed by hidden movement, beam display and a cursor-only block
transition. Clipped-overhang equivalence and interrupted-index cleanup pass.
App Fast/Safe, affected Render/Instance, root check/test (including protocol,
VT simulation/fuzz), both audits, formatting and diff gates pass.

Fast baseline cc52b5fb02a8a6ef418fcd2e77e19953f66aecca9713b2c31dd41d6eb51eed6e, 14687401 bytes.
Fast candidate c595648fea7fdd7a8822f9f51ddfbc7724493e5a463ddf97c487dcb9f799ccf4, 14688638 bytes.
Safe candidate aa23a5ac761ae46dec6d041da6f2e9d91290c317368af997a6c1bd8ff2df4f01, 14045494 bytes.
Native producer 87ce7c1038f2737493c8f89a14cd386dc27ccb0a958887855e986687a5c48557, 5002344 bytes,
source 3dbd021, Fast on the pinned Zig compiler. Safe qualification is separate
from the Fast timing cohort; binary lengths are not a memory-saving measure.

Raw identity-bound process folds, profiles/PC maps, proof logs and retirement
receipts live at light-cells-20261010 under the current Home workstream.
The static race overview adds this cohort without replacing the parent matrix.

## Native row-reuse prototype rejected, 2026-10-10

Instance compared existing non-consuming VT row generations and supplied bounded
revision-relative repairs to the renderer. Complete immutable publications and
atlas/shape limits stayed unchanged. Render/Instance and app Fast/Safe/pixel
proofs passed. The native full-command oracle demonstrated an actual row patch
and covered cursor, palette/DEC, history, alternate screen, resize, images and
failure recovery.

Fourteen ordinary fresh-process 20-second controls use the same producer ELF as
the preceding cursor-index cohort, private KWin 1920x1080/scale1, common 378x74
payload and 240 emitted Hz. There are two baseline and two candidate runs each
for light/dense/rich in forward/reverse order, plus two Foot light references.
CPU is percent of one core excluding producer and shell.

| Canary (n=2 per variant) | Accepted 538f7b5 Fast | Rejected prototype |
| --- | ---: | ---: |
| Light cells | 14.99–15.19% | 16.35–16.40% |
| Dense cells | 33.16–33.47% | 34.23–35.04% |
| Rich cells | 53.57–54.79% | 56.30–57.37% |

Mean CPU rises 8.56% light, 3.95% dense and 4.91% rich. Fresh Foot light CPU is
3.44–3.65%. All emit 4800 frames/no skips except one rich candidate, 4799/one skip.
Emitted progress is not displayed cadence or latency. Terminal peak PSS remains
separate: baseline light 149–206MiB versus candidate 150–152MiB, dense 150 versus
153–154MiB, rich 158 versus 160–165MiB. The baseline light anonymous/PSS outlier
prevents a memory-saving claim. Howl PTY 384x79, Foot 384x77; payload extents match.

A separate 2ms/30-second native clock profile records 9.60% exclusive sampled CPU
in incremental eligibility scans, 3.39% inclusive in remembering command copies,
and 12.18% exclusive in final frame projection. Glyph placement and shape/atlas
resolution remain hot. These samples include startup/shutdown and do not
completely explain the ordinary CPU regression.

A bounded scalar diagnostic captured 44 repaired rows of 79: the existing
max(1,rows/3) policy admits only 26 and chooses a full baseline. Sparse producer
updates can accumulate between observations and touch many rows. This prototype
pays full-view eligibility and command-cache copies while full rebuilds remain.
One captured cut does not quantify total fallback frequency or prove row reuse
cannot improve. The extra cache requests 114689 Input entries (the maintained full
command envelope), not the older 32768-entry reservation; requested capacity and
touched/resident memory are distinct.

Decision: restore the exact accepted implementation. Before adding native reuse,
measure coalesced changed sets and the break-even cost of retained rows versus
cell/run paint spans. Row identities can narrow discovery; unchanged work should
avoid full eligibility walks and whole-cache reconstruction. Complete immutable
frames and exact clipping/resource/failure proofs remain requirements.

Baseline Fast c595648fea7fdd7a8822f9f51ddfbc7724493e5a463ddf97c487dcb9f799ccf4.
Rejected Fast 80d3890e8ed5962dcdb8e371ea554d5ee2843cadd5be3ed4720d0583c49865c9.
Producer 87ce7c1038f2737493c8f89a14cd386dc27ccb0a958887855e986687a5c48557, source 3dbd021 Fast/stage2_llvm.
Raw folds, rejected/instrumented patches, profile, scalar cut, correctness logs
and retirement receipts live at row-reuse-20261010 under the current Home
workstream. The qualified launch binary is untouched.

## Native row cutoff follow-up, 2026-10-11

The wider limit works for the sparse workload. At 79 viewport rows, changing
max(1, rows/3) from 26 to max(1, rows*2/3), 52, reduces observed sparse mean CPU
10.80% against accepted runtime 538f7b5. Allowing 78 repairs saves 9.33%.
The first experiment's single 44-row cut could not justify jumping to a finer
damage design before testing this cheaper lever.

| Native policy at 79 rows | Light mean CPU | Dense mean CPU | Rich mean CPU |
| --- | ---: | ---: | ---: |
| Accepted build | 15.47% | 34.73% | 58.07% |
| 26 rows | 16.73% | 34.76% | 59.85% |
| 52 rows | 13.80% | 36.10% | 58.68% |
| 78 rows | 14.03% | 35.59% | 55.52% |

Twenty-six ordinary fresh-process 20-second controls: two per build and each of
three workloads, plus two fresh Foot light references 3.90–3.95% CPU.
CPU is percent of one core excluding producer and shell. Exact baseline and
original prototype ELFs reproduce the preceding experiment byte-for-byte.
All three reuse variants differ in their cutoff alone at runtime; new native
oracle cuts are tests only. Cache capacity remains 114689 Input entries, rows 192.
Same producer 87ce7c10, common 378x74 payload, private 1920x1080 KWin scale 1,
OpenGL, 240 emitted Hz/synchronized output. Howl PTY 384x79, Foot 384x77.
Producer skips total 8 across 26 runs:
one dense 78-row trial, two rich 26-row trials, both rich 52-row trials.
Emitted progress is not displayed cadence or latency.

The 52-row dense mean is 3.93% higher; candidate 36.05–36.15% versus
baseline 33.82–35.65%. Dense 26/78 ranges overlap baseline.
Rich ranges overlap substantially: baseline 55.14–61.01%, 52-row 56.40–60.96%,
78-row 54.94–56.10%. Treat rich as inconclusive; its observed means do not
qualify a gain or regression. The earlier cohort remains separate.

Independent instrumented 20-second sparse runs captured cumulative 1024-update
cuts, including startup: 26-row 44 patches/980 baselines; 52-row 1016/8;
78-row 1017/7. All three median repaired-row counts 43, modes 43–44.
This confirms that the policy blocks otherwise useful row reuse. These counters
are diagnostic only, exclude uncaptured end-of-run tails, and are not timing or
display-cadence measurements.

Input is 72 bytes on the pinned native compiler. Each prototype requests 8257608
bytes, 7.875 MiB, for its command cache, plus bounded row/repair metadata.
The cutoffs change admission, not reservation. Touched/resident pages differ
from requested capacity. Light baseline PSS 148.97–206.95 MiB includes the same
cold anonymous outlier pattern as the preceding cohort. 52-row PSS 151.62–151.79,
dense 152.92 versus baseline 149.01–149.90; rich overlaps. No RAM saving qualified.

Native complete-command proofs cover two/three-row edits, bulk clear plus prompt
span, held leases, cursor/style/palette/DEC/history/alternate screen, resize,
images, failed projection and recovery. Instance/Render checks/tests and each
Fast app/pixel proof pass.

Decision: do not promote native row reuse by default from this sweep. Restore
the accepted runtime exactly and keep the evidence. 52 is a useful measured
sparse lever; further work should first reduce unsuitable-path eligibility/cache
maintenance costs and evaluate workload-sensitive admission. This result does
not prove that cell/span granularity is required.

Captain's VT ownership proposal is sound as a design direction: VT owns
non-consuming semantic damage; each consumer owns its baseline; Render owns
font/pixel/resource/paint decisions. Existing VT row identities already supply
the first part. More semantic extent/feature summaries or revision-covered
coalesced spans may prevent rediscovery, but must earn their canonical mutation
costs in VT-only as well as presentation controls. The workstream OWNERSHIP.md records
bounded coverage, multiple observers, bulk-clear semantics and failure requirements.
Additional asynchronous queues have no measured justification from this sweep.

Exact source patches, ordinary folds, diagnostic patches/counters, native
reservation proof and gate logs are retained under cutoff-20261010 in the current
Home workstream. Qualified launch Safe
aa23a5ac remains untouched. Cleanup and final gates are recorded separately.

Artifact provenance:

- Accepted build Fast: c595648fea7fdd7a8822f9f51ddfbc7724493e5a463ddf97c487dcb9f799ccf4.
- 26 rows Fast: 80d3890e8ed5962dcdb8e371ea554d5ee2843cadd5be3ed4720d0583c49865c9.
- 52 rows Fast: c08bad13f7c384a9397bfacc0c5887e607b194571f0632d0bf3c079abb06bb62.
- 78 rows Fast: d823cc8e83edc2e08190f916303c58a032212c75fc7ab4cbacac60a3efaf4782.

## Direct native row work accepted, 2026-10-11

Native presentation now compares existing non-consuming VT row identities once
per observation. Instance offers reuse only within the renderer repair budget:
52 of 79 rows here. Broader changes request direct full projection while still
committing a successful observer baseline. The next small edit can establish
a full retained baseline, and later small edits patch it. VT state is unchanged.

Render validates row eligibility while inspecting required backgrounds, skips
known clean eligible rows, and retains the completed command buffer instead of
copying every glyph back into a second cache. The same two private buffers grow
within their existing limits. Complete owned frames, exact resources/clipping,
and three immutable Instance publication slots keep their contracts.

Four independent cohorts contain 80 fresh 20-second controls, n=2 per Howl build
and workload plus two Foot light references per cohort. CPU is percent of one
core excluding producer and shell; these are observed ranges, not confidence
intervals. Do not pool separate cohorts or infer display FPS/latency.

### Eligibility fusion

| Build | Light CPU mean (range) | Dense | Rich |
| --- | ---: | ---: | ---: |
| accepted | 15.97% (15.59–16.35) | 35.95% (35.29–36.61) | 56.86% (56.71–57.01) |
| old52 | 14.33% (14.18–14.48) | 36.25% (36.20–36.30) | 57.42% (56.96–57.87) |
| fused52 | 13.72% (13.67–13.77) | 37.24% (36.61–37.87) | 57.26% (57.01–57.52) |

### Retain completed output

| Build | Light CPU mean (range) | Dense | Rich |
| --- | ---: | ---: | ---: |
| accepted | 15.52% (15.44–15.59) | 36.10% (36.10–36.10) | 58.05% (57.87–58.23) |
| fused52 | 13.77% (13.72–13.82) | 37.21% (36.76–37.67) | 57.65% (57.22–58.08) |
| cache52 | 13.49% (13.47–13.52) | 36.10% (35.90–36.30) | 58.56% (57.62–59.49) |

### Bounded buffer growth

| Build | Light CPU mean (range) | Dense | Rich |
| --- | ---: | ---: | ---: |
| accepted | 15.44% (15.39–15.49) | 37.90% (35.85–39.95) | 57.54% (57.06–58.02) |
| cache52 | 13.52% (13.37–13.67) | 36.48% (36.20–36.76) | 58.46% (58.18–58.73) |
| grow52 | 13.47% (13.47–13.47) | 36.13% (36.05–36.20) | 58.46% (57.87–59.04) |

### Native repair-budget admission

| Build | Light CPU mean (range) | Dense | Rich |
| --- | ---: | ---: | ---: |
| accepted | 15.75% (15.70–15.80) | 36.48% (35.90–37.06) | 58.18% (57.77–58.58) |
| grow52 | 13.72% (13.52–13.92) | 35.95% (35.54–36.35) | 58.84% (58.38–59.29) |
| admit52 | 13.80% (13.72–13.87) | 36.35% (35.80–36.91) | 58.05% (57.21–58.89) |

Fusion alone saved 4.24% sparse CPU versus old52 but increased dense mean 2.72%.
Retaining output removed the whole-cache glyph copy: sparse -2.02% and dense
-2.99% versus fused52; dense mean then matched accepted. Growth preserved sparse
savings and lowered sampled peaks against the fixed pool. Its dense accepted
39.95% high trial remains beside 35.85%; no dense gain is qualified from that mean.

Final admission saves 12.38% sparse CPU versus accepted in its cohort. Dense
and rich ranges overlap accepted, so neither qualifies a gain or regression.
Final Foot sparse CPU 3.75–3.80% remains far below native candidate 13.72–13.87%.
The earlier growth-rich positive mean signal also overlaps; all raw runs remain.

Total emitted frames 383994, skipped slots 6: two fixed-cache rich slots in the
growth cohort and four grow52 rich slots in the admission cohort. All 80 runners
were eligible; final admit52 trials have zero skips.

Native Input is 72 bytes. Initial requested command storage across both buffers
is 589824 bytes/0.5625 MiB versus 8552520 bytes/~8.1563 MiB for the fixed-cache
prototype. Both retain the same two-buffer maximum 16515216 bytes, plus metadata.
The fixed allocation no longer reserves its maximum at construction. Requested
capacity is distinct from touched/resident memory. Growth sampled PSS means
versus fixed were lower 1.75 MiB sparse, 1.48 MiB dense, 1.81 MiB rich in that cohort.

Final sparse accepted has a cold anonymous outlier 90.38 MiB and a warm 40.83 MiB
cut; candidate 42.17–42.19 MiB is about 1.35 MiB above the warm baseline. Dense
candidate 41.39–42.30 versus 40.78–41.11 MiB also costs memory. Rich ranges overlap.
There is no RAM-saving claim against accepted, and Foot still leads RAM.

The common 378x74 payload leaves five blank rows of Howl 79 clean. An all-row-only
bypass therefore misses this broad workload. One shared rowReuseLimit policy
serves the renderer planner and native caller; no duplicate cutoff or extra
row traversal was added. Source type selection remains comptime; workload
reuse/fallback remains runtime. Source-neutral type names were not the CPU fix.

Native full-command oracles cover sparse/broad edits, clear plus prompt,
bypass/re-prime/patch, cursor, styles/palette/DEC, history/alternate screen,
resize, images, exact command-limit failure/recovery and held leases. Budgets
4/32/512 plus injected presentation allocation failures cover both buffer roles,
cache growth and normal fallback. Two independent row caches sharing a text
store retain pressure, neighbor reset, stalled lease and canonical-progress
proofs. The tiny-cache PTY fixture now echoes known glyphs to remove scheduling
dependence without raising its 4-entry pressure bound. Transported/root and
Fast app/pixel proofs pass; final artifacts/gates recorded below.

Same compiler 0.17.0-dev.1980+e78ea8f2c, Fast LLVM/selfhost linking; private
1920x1080 KWin scale 1/OpenGL, 240 emitted Hz with synchronized output. Howl PTY
384x79, Foot 384x77. Producer source 3dbd021, SHA
87ce7c1038f2737493c8f89a14cd386dc27ccb0a958887855e986687a5c48557.

Final timed Fast SHA 5a6273b04464803683915a550fa9a7ab20bb4f012af0b00811939816e1dcced9
(14731092 bytes). Qualified Safe, final gates and retirement receipts remain
under direct-20261011 in the Home workstream. The launch Safe aa23a5ac remains
unchanged; this source checkpoint does not promote the live canary.

Foot still skips clean cells as well as rows; this change uses row identities.
Further cell/span work must earn its mutation, coverage, observer and lifetime
costs against headless VT and presentation controls. Extra asynchronous queues
have no measured justification. AtlasFull stays the unreproduced watch item.

Final Safe SHA 9d2d44bfc583cff0d5d24bd40604bdbfb34133cf47535bb77151cc5f5d794dad (14084278 bytes) passes app/pixel proofs. The final Fast rebuild is byte-identical to the timed candidate.

## Accepted sparse-cost attribution and rejected glyph bounds, 2026-10-11

Two separate 2 ms/30-second clock profiles sample accepted de75777 Fast,
byte-identical to the final native-row candidate above. Sparse exclusive samples
place 56.49% in native render update and 22.95% in complete frame projection;
font-atlas and shape resolution add 3.97% and 3.80%. Dense canonical
service-boundary parsing is 27.92% and plain ASCII writes 9.76%.
These include startup/shutdown and can alter scheduling/coalescing. They are
attribution, not ordinary CPU, display cadence/latency or driver-internal proofs.

GNU and LLVM addr2line agree on hot inline glyph-placement and frame-validation
locations. gprofng's displayed Zig source-line numbers are distorted. Signed
26.6-to-pixel floor conversion already compiles to an arithmetic shift; the hot
range check uses optional/error-result handling around it.

An explicit equivalent signed guard preserves negative floor rounding, i32 bounds
and exact InvalidPresentationGeometry. Native/render/Instance/transported/Fast
app/pixel proofs pass, including boundary and negative-overhang tests. Separate
ordinary controls compare it with accepted de75777 using the same compiler and
producer, fresh processes and private 1920x1080 KWin/scale 1/OpenGL. Payload 378x74,
Howl PTY 384x79, Foot 384x77, synchronized 240 emitted Hz; each run 20 seconds.
CPU is percent of one core excluding producer and shell. Ranges are observed,
not confidence intervals.

| Build (n=3 per case) | Sparse CPU mean (range) | Dense | Styled |
| --- | ---: | ---: | ---: |
| Accepted de75777 | 13.42% (13.32–13.57) | 32.56% (32.30–32.96) | 54.68% (54.18–55.04) |
| Explicit glyph bounds | 13.08% (13.06–13.11) | 31.78% (31.70–31.90) | 55.04% (54.58–55.54) |

Sparse saves 2.51%, dense 2.38%; all three pairs each improve. Styled mean rises
0.65%, with overlapping ranges and two positive pairs. Two fresh Foot sparse
references are 3.544% each, retaining the gap.

A separate six-run reverse-order styled follow-up gives accepted 54.87%
(54.63–55.04), candidate 55.26% (54.98–55.59): mean +0.71%, all three pairs positive
(+0.09%, +1.76%, +0.28%). Keep these cohorts separate. The repeated direction,
five of six styled pairs, rejects this micro-optimization despite its sparse
and dense gains. Source remains de75777; no glyph-bound change is accepted.

All 26 ordinary runs emit 124800 frames/no skips. The two clock diagnostics emit
14400/no skips separately. Cold anonymous/PSS outliers exist in the initial
accepted run and follow-up candidate; no RAM saving or regression is inferred.
The rejected change adds no allocation/capacity/retained state. Its Fast ELF is
86 bytes smaller, which does not establish a memory or universal speed gain.

Accepted Fast 5a6273b04464803683915a550fa9a7ab20bb4f012af0b00811939816e1dcced9;
rejected b7d902ea7d789a1b7e83bec6f4a4b3cd662e4678d0ad6318e0f6c0890bdaf7f0.
Producer 87ce7c1038f2737493c8f89a14cd386dc27ccb0a958887855e986687a5c48557,
clean source 3dbd021, Zig 0.17.0-dev.1980+e78ea8f2c Fast LLVM/selfhost.
Raw profiles, agreeing PC maps, rejected patch/proofs and both ordinary cohorts
remain under sparse-profile-20261011 in the current Home workstream.

Next investigate reuse of validated final-frame work while preserving exact
resources, clipping, command bounds, error recovery and held-slot lifetimes.
The hot service-boundary function is canonical VT parsing and mutation; it is
not a renderer pre-scan or justification for VT-owned rendering queues.
Clean row translation is smaller; pixel row/span batching needs separate
missed-frame/resource/overhang provenance and display measurements.
After qualification, Captain authorized installing accepted Safe 9d2d44bf at the
existing app launch path. Promotion is atomic, previous aa23a5ac is retained as
rollback, and open sessions are not restarted. The rejected Fast is never installed.

## btop retained memory and EGL discovery, 2026-10-11

Captain reports a fresh btop startup peak near 800 MiB and retained RSS near
333 MiB. Read-only live PID/start and ELF identity confirm installed Safe 9d2d44bf:
about 340 MiB status RSS, 224 MiB rollup PSS and 49 MiB anonymous at baseline.
The live peak counter does not show 800 MiB. RSS/PSS/anonymous, virtual size,
GPU VRAM and whole desktop memory are separate; the original peak remains open.

Twelve fresh lifecycle controls keep exact previous Safe aa23a5ac and installed
Safe 9d2d44bf, copied Iosevka 18 config and btop 1.4.7. Root status/statm sample
about 20 ms, rollup 200 ms; phase maps separate shell, btop and returned shell.
Private KWin 6.7.5 owns D-Bus/HOME/XDG/seat. Physical WMIO queries currently fail
unsupported_environment, so these are matched private controls, not an exact
physical window match. Four 1920x1080/scale 1 runs use SIGTERM btop exit; four
inset 3825x2142/scale 1.7 and four same-ELF vendor controls use normal q exits.
The failed exact fractional maximum placement and its cleanup remain recorded.

Warm previous/installed after-btop RSS is about 326 versus 326–327 MiB at scale 1,
329–330 versus 331 MiB at scale 1.7. No 115 MiB new-build increase is reproduced.
First-context anonymous outliers occur with either build; none is dropped or
attributed exclusively to Howl. All sampled root peaks stay below 398 MiB;
this does not explain Captain's reported 800 MiB reading.

Four separate instrumented identity checks find opengl on NVIDIA RTX 3060
for both builds. Default EGL discovery also maps Mesa libgallium and LLVM.
Selecting only the installed NVIDIA EGL provider removes both libraries while
SDL renderer and GPU remain the same. These diagnostics are separate from the
uninstrumented same-ELF btop controls:

| Same installed Safe, normal btop exit | After RSS | After PSS | After anonymous |
| --- | ---: | ---: | ---: |
| Default discovery, n=2 | 326.83–326.88 MiB | 124.35–124.39 MiB | 43.08–43.09 MiB |
| NVIDIA-only, warm n=1 | 221.96 MiB | 88.62 MiB | 38.70 MiB |
| NVIDIA-only, first cold context | 290.48 MiB | 145.45 MiB | 89.16 MiB |

Only the per-process __EGL_VENDOR_LIBRARY_FILENAMES changes. Warm RSS decreases
104.89 MiB and PSS 35.75 MiB; the cold row remains explicit and cohorts are not
pooled. Map removal supports attribution, not a universal cold/warm or owned-RAM
saving. No CPU, display latency, VRAM or exact-pixel qualification is inferred.

Source, installed launch and user config stay unchanged. This is a concrete
host launch-policy experiment; next qualify CPU and pixels before promotion.
Keep provider selection out of VT/core ownership and retain the SDL submission
bound. Exact artifacts, raw phase samples/maps, the failed probe, diagnostics and
folds live under memory-btop-20261011 in the current Home workstream.

## Colour-glyph queue qualification, 2026-10-19

Against exact baseline `fb9ecb0`, 24 fresh balanced private KWin 60 Hz trials used
the same 378×74 payload, 10px Iosevka Nerd Font and 240 Hz ReleaseFast TUI Zoo
producer. Total application CPU (one-core percent) was 34.43→34.21 for ASCII/FG,
48.34→48.12 for ASCII/FG/BG and 60.70→52.50 for Unicode/FG/BG including emoji.
The Unicode median falls 13.51%, with every pair improving 11.49–15.83%;
plain/colour ASCII remain within observed noise. All 24 trials have zero skipped
producer slots. These rates do not measure displayed 240 Hz or photon latency.

Canvas now bounds the entire SDL content queue to 2048 quads, including RGBA
copies, while preserving painter order and draining final tails. This avoids
forcing an SDL submission for every tiny mixed colour-glyph packet.
VT, Render commands, appearance and presentation pacing are unchanged.

Independent old/new OpenGL queues match 230400 RGBA pixels across 36 fixtures;
queued high water is exactly 2048. Separate 8px colour-only guards exercise
49152 emoji per frame on a 512×192 grid; all frames complete. Candidate anonymous
peaks 60.12/61.07 MiB compare with baseline 133.08/80.71 MiB; the first baseline
outlier remains recorded. This is not a universal RAM or leak claim.

Conditions, exact hashes, all trial ranges, the withdrawn clip-only experiment
and qualification/cleanup receipts are local under
`~/.local/state/workstreams/howl-current/performance-20261019/`:
`RESULTS.md`, `queue-folded.json`, `queue-manifest.json`, `queue-gpu-proof-2.log`
and `rgba8-proof.json`. Keep this cohort separate from historical race tables.

## Independent backgrounds and glyph-row retention, 2026-10-19

Against 149a779, the C3 private KWin 60 Hz cohort has 24 fresh-process trials:
four pairs for plain ASCII and two each for colour ASCII, Unicode and the two
preserved Neovim casts. The root process CPU clock includes all app threads;
producer/coordinator are excluded. Casts run at 320×66 / 12 px, Zoo at 384×77 / 10 px,
with a 378×74 payload, 4096 writes/frame and 240 Hz producer target.

| Case | Baseline CPU, one core | Independent retention |
| --- | ---: | ---: |
| Plain ASCII + FG |43.212%|43.307%, flat within observed variation|
| ASCII + FG/BG |54.159%|53.449%,1.31% lower|
| Unicode + FG/BG |58.511%|58.481%, flat|
| Positive Neovim cast |4.021%|3.943%,1.93% lower|
| Negative Neovim cast |6.509%|6.195%,4.82% lower|

Cell backgrounds no longer disqualify unchanged glyph rows. Render retains the
glyph span with its actual command offset and projects BG runs independently.
The public uniform-background RowScene remains unavailable when BG overrides
exist. Cache-budget overflow and coloured row shifts conservatively fall back.
One packed range replaces the existing native count word. VT, host pacing, wire
and ABI stay unchanged. This does not establish glyph equality within mutated rows.

Narrow VT colour stores and the foreground-resolution cache were withdrawn.
Qualified quiet colour-write controls regress 2.6–4.9%; an earlier apparent gain
overlapped compilation and is explicitly unqualified. C1/C2 and C3 cohorts remain
separate; C2's plain-path regression blocked promotion. Final-source every-release Render update+frame totals fall 23.83% and 25.25% on
the two casts; feeding/painting are excluded, and skipped observations often
lose this opportunity. Complete commands and uploaded pixels match the full
baseline across replay and hostile controls.
Candidate Zoo runs skip no producer slots; controls skip five total. No displayed
240Hz, latency or RAM-saving claim. Cold memory outliers remain in raw results.

Evidence: ~/.local/state/workstreams/howl-current/fg-bg-20261019/
(RESULTS.md, METHOD.md, separate folded cohorts, raw per-process samples,
source hashes, proofs and cleanup receipts). Separate SDL diagnostics qualify
presentation and submitted work; their CPU samples are not pooled above.
