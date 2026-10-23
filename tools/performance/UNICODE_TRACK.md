# Unicode track qualification — 23 October 2026

Follow-up: [font coverage and fallback cost](FONT_COVERAGE.md) separates host
recipe gaps from the corrected unsupported-selector behavior.

TUI Zoo 0fb82f8b65efca33e6e8607b5062fd75da07b6c6 adds independent
ASCII, UTF-8, combining, wide, emoji, scripts, presentation, churn and mixed
cases. Every operation targets a nominal two-cell slot. Text, positions,
foreground and background use independent streams. This replaces neither the
old Cells producer nor its published race cohorts.

The first qualification found a desktop correctness defect before timing:
VT retains 24 scalars per cell, but howl-app's font recipe admitted only 16
to the shape cache. A valid long combining cluster produced
ShapeSequenceLimit and the application displayed an error banner instead of
content. All 66 cursor-width probes still succeeded, and stderr was empty.
The previous nine-case runtime smoke did not establish successful painting.

The desktop recipe now uses instance.maximum_cell_scalars, the existing
canonical bound. No parser, generic shaping policy, scheduler, allocator,
cache eviction or ABI changed. An actual PTY-to-frame regression exercises
16-, 17- and 24-scalar cells using the production desktop recipe and a
redistributed font fixture. It fails with the old bound (152/153 tests pass)
and passes with the correction (153/153).

## Scope and observations

Four fresh native clients ran on a private KWin seat at 1920×1080, scale 1.
The race recipes produced 384×83 cells with a 5×13 pixel lattice.
All four exact corner markers occupied 65 pixels. The producer was the
installed LLVM Fast build d77b4eb982872ce02bffe0cff83dea66d00a8f1231c7eec6c7edc334ee238b91.

The harness extracted all eight samples for each fixed corpus from actual
producer bytes. It queried cursor position before and after each sample.
Eight generated CJK samples plus two CJK boundary samples brought the total
to 66 per client. This is a terminal-reported occupancy probe, not a cell,
glyph, clipping or pixel oracle.

| Client | Width differences from the nominal two cells |
| --- | --- |
| Howl before and after correction | None in 66 probes |
| Foot | None in 66 probes |
| Kitty | South African flag: four cells |
| Alacritty | Nine samples: five emoji sequences and four emoji selectors |

Alacritty reported keycap 1 as one cell; rainbow flag as three; skin-tone
thumb and woman-technologist as four; family as eight. Copyright, sun,
heart and airplane with emoji selectors each remained one cell. Kitty's
flag pair occupied four cells. These observations describe the exact installed
clients and recipes, not every version or Unicode mode.

Captures were inspected. Corrected Howl paints the corpus instead of its
error banner. Several script and text-selector samples still show replacement
glyphs; supplementary CJK coverage also differs. Passing cursor widths does
not prove complete font coverage or equivalent visible output. These cases
must remain explicit capability/coverage pressure, rather than being blended
into a score claiming equal painted work.

Kitty logged private-seat systemd-scope and notification-service warnings.
The whole workload remained inside its delegated cgroup; no resource-limit
events, CPU throttling or captured-output loss occurred.

## Validation and next comparisons

The final LLVM Fast desktop check/test/audit/install graph passed all 14 steps
and 153 tests. The full root check/test/consumer/protocol/audit graph passed
341 steps and 1,263 reported tests, including cached work. Formatting and
git diff checks pass. The corrected native capture and cursor probes pass.

No performance ranking, displayed-frame cadence, frame deadline or physical
Hyprland result is claimed here. Start fresh matched ASCII/UTF-8 comparisons
with identical seed, geometry, pattern, slot dose and cadence; toggle background
separately. Keep byte, codepoint and nominal-cell doses visible. Broader emoji
and font-coverage cases require their own interpretation.

Raw bytes, per-sample replies, recipes, binary/font hashes, screenshots,
red/green proofs and sealed whole-workload receipts are retained under:

    ~/.local/state/workstreams/howl-current/day-20261023/unicode-qualification/

