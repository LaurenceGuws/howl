# U30 physical Hyprland Unicode race · 15 November 2026

This is a completed **40-trial terminal CPU, process-memory and producer-cadence
comparison**, not a displayed-FPS benchmark or a claim of equal Unicode pixels.
No Howl application binary, installed Howl, or product implementation was
changed for the race.

## Track and immutable inputs

- Home's physical Hyprland 0.57.2, Dell DP-1 at 1920×1080, scale 1, 240 Hz.
- Four independently launched fullscreen terminals, each verified at 384×83
  cells with a 5×13-pixel lattice and all four exact corner markers.
- Current Howl U29 (the accepted Fontconfig-fallback source at `faf979e`),
  previous Howl U28, Kitty 0.50.0, and Alacritty 0.17.0.
- Immutable U29 TUI Zoo Unicode producer, sequential pattern, seed 20261115,
  4,096 nominal two-cell slots per frame, synchronized output, no background
  colour load, 240 requested frames/s for six seconds.
- Five independent cases: ASCII, world scripts, emoji ZWJ, Indic conjuncts and
  mixed Unicode. Two fresh opposite-order trials per terminal/case.
- Terminal process-tree CPU excludes the producer, benchmark controller and
  compositor. The means below use CPU samples within the producer-active window,
  after the first second. PSS is observed process-tree proportional set size.

The workstream's `manifest8.json` and `manifest9.json` pin all four executable
SHA-256 digests, the producer, inherited runner and presentation configurations.
Both manifests agree on every binary, producer, configuration and workload pin;
only the disposable coordinator source differs because its read-only
seat-observation recovery was extended between batches.

## CPU and missed producer deadlines

Each cell reports **mean percent of one logical CPU core / total skipped
producer slots** over two six-second trials. Lower CPU is better only when
delivered work is also considered.

| Unicode case | Howl U29 | Howl U28 | Kitty | Alacritty |
| --- | ---: | ---: | ---: | ---: |
| ASCII | 26.75% / 0 | 26.72% / 0 | 61.82% / 0 | 51.87% / 1 |
| World scripts | 41.25% / 0 | 37.35% / 1 | **35.00% / 0** | 67.71% / 0 |
| Emoji ZWJ | **59.68% / 0** | 57.29% / 0 | 100.97% / 346 | 73.11% / 0 |
| Indic conjuncts | 46.40% / 0 | 45.98% / 0 | **40.58% / 0** | 77.61% / 0 |
| Mixed Unicode | **70.06% / 13** | 70.37% / 10 | 87.78% / 52 | 77.86% / 0 |

Bold identifies the lowest CPU among the three current external-competition
horses (Howl U29, Kitty, Alacritty), not the lowest in all four columns.
The older Howl is a historical control, not an independent competitor.

The observed mean producer rates on the two challenging loads were:

| Case | Howl U29 | Howl U28 | Kitty | Alacritty |
| --- | ---: | ---: | ---: | ---: |
| Emoji ZWJ | 240.00 Hz | 240.00 Hz | **211.12 Hz** | 240.00 Hz |
| Mixed Unicode | 238.91 Hz | 239.16 Hz | **235.66 Hz** | 240.00 Hz |

In the emoji case, Kitty delivered 2,536 frames against 2,880 for Howl
and Alacritty, while spending approximately one core of terminal CPU.
Kitty missed 170 and 176 producer slots in the opposite-order trials,
respectively. This reproducible, workload-specific producer ceiling is a race
result, not a reason to exclude Kitty by enforcing a zero-miss admission gate.

On world scripts and Indic conjuncts, Kitty completed all 2,880 frames and
used less CPU than U29 Howl. Howl U29 was particularly efficient on ASCII and
emoji. Compared with U28 Howl, U29 used approximately 10.4% more CPU for world
scripts and 4.2% more for emoji in this small cohort, while the accepted
fallback work has a separate font-coverage objective. No general U29 speedup
is claimed.

For memory context, mean observed PSS on mixed Unicode was approximately
270.6 MiB for Howl U29, 270.4 MiB for U28, 313.5 MiB for Kitty and 254.7 MiB
for Alacritty. These are process PSS samples, not a GPU-residency or total
system-memory accounting.

## Qualification, incidents and evidence

The early U30 runner was stopped by WMIO physical-seat failures before any
accepted race. WMIO's environment-map ownership repair was promoted at
`9aa9292`. A later intermittent HostIO availability preflight was removed
from the physical mutation path and promoted at `d440629`, with all WMIO
build/test/audit/CLI/install-bundle gates passing and the previous version
retained for rollback.

WMIO continued to return occasional `graphical_seat_changed` during
**read-only** window observations without a Hyprland process replacement. The
disposable coordinator was therefore permitted one fresh retry of a read-only
desktop/workspace/window inspection. Physical keyboard, focus, close and
window-move actions were **never** replayed after an ambiguous result.

The first longer race attempt aborted after six persisted trial summaries; a
later chunk aborted with seven complete summaries when a read-only exact-window
inspection hit the same guard. Neither incomplete attempt is silently
presented as a finished batch. The qualified final sample consists of:

| Immutable stage | Completed measurement trials |
| --- | ---: |
| `race8a` | 10 |
| `race8b` | 10 |
| `race8c` | 7 |
| `resume9a` | 3 |
| `resume9b` | 10 |
| **Total** | **40** |

Both coordinator versions independently passed four-horse exact fullscreen
qualification. Their stage records preserve the run order, per-trial CPU
samples, app diagnostics, producer receipts, process PSS and desktop
before/after snapshots. A final consistency check verified 20 terminal/case
pairs with exactly two trials each, all valid producer write counts, correct
geometry and zero application diagnostics. No race job or test window remains;
the four original user-window stable IDs and PIDs were preserved.

Raw manifests, failed attempts, driver versions and final evidence:

`/home/home/.local/state/workstreams/howl-current/day-20261115/hyprland-u30/`

## Interpretation and next pressure

This is one physical-Hyprland machine and a small two-trial cohort. Skipped
producer slots and actual output bytes are retained because a terminal that
falls behind receives less work; CPU alone cannot award the race. Producer
cadence is not independently measured presented-frame cadence, responsiveness,
latency or visual smoothness. Matching geometry and input bytes do not establish
pixel-equivalent shaping, font fallback, colour or emoji rendering. Different
fallback coverage is especially relevant after U29's demand-driven Fontconfig
improvement.

The next Howl-specific question is whether U29's increased world-script/emoji
CPU represents fallback-resolution overhead or legitimately more glyph work.
Resolve visible coverage and shape-cache evidence before changing the
fast path. No benchmark probes, trace hooks or compatibility adapters are
promoted into Howl's product source from this result.
