# Renderer Lane Contract

Purpose:
- lock the renderer-foundation lane split so Milestone 2 replaces the right path instead of preserving the old universal one.

Scope owner:
- `howl-render` owns lane policy, lane predicates, and lane-proof surfaces.
- `howl-term` may feed the renderer better cell text, but does not own lane policy.
- `howl-linux-host` remains a proof surface only.

## Normal Lane

The default normal lane is the only target for ordinary monospace text.

The unit of work is:
- one renderable cell head
- one resolved glyph identity
- one atlas-backed glyph draw submission

`howl-render/src/text/text_lane.zig` defines the exact positive predicate.

A cell is in the normal lane only when all of the following are true:
- `text.codepoints.len == 1`
- `presentation != .emoji`
- `symbol_map.builtinRoute(text.first_cp) == null` or `.blank`
- the cell is not using `underline_style == .curly`

Normal-lane implications:
- lane entry is decided before shaping/grouping machinery.
- normal text must not depend on full-run text hashes.
- normal text must not depend on row-wide run shaping as the default methodology.
- wide single-codepoint cells remain normal-lane work.

## Complex Lane

The complex lane is explicit and exceptional.

`howl-render/src/text/text_lane.zig` defines the exact positive predicates.

A cell is in the complex lane only for one of these reasons:
- `multi_codepoint`: `text.codepoints.len != 1`
- `emoji_presentation`: `presentation == .emoji`
- `special_sprite`: `symbol_map.builtinRoute(text.first_cp) != null` and not `.blank`
- `icon_codepoint`: `symbol_map.isIconCodepoint(text.first_cp)`
- `curly_underline`: `underline and underline_style == .curly`

Lane choice invariants:
- lane choice is assertion-checked.
- exactly one lane must match every classified cell or cluster.
- there is no fallback auto-routing based on downstream misses, cache state, or shaping side effects.
- the live text engine records all legacy-path work against this classifier before benchmark code sees the result.

## Current Lane Ownership

The live engine now classifies cells before any shaping/grouping work starts.

- normal-lane cells build direct cell/glyph work only
- complex-lane cells are selected explicitly before resolve/shape/group/scene work runs
- resolve, shape, grouping, and scene sprite preparation run only on that explicit complex selection

`howl-render/src/text/engine.zig` records lane counts and any legacy-stage usage through `lane_report`.

This keeps the normal lane as the controlling default path and the complex lane as the exceptional path.

## Benchmark Proof Surface

Primary proof command:

```sh
zig build render-benchmark -- --text --runs 3
```

The scorecard must report, per workload:
- visible cell capacity (`grid_cols`, `grid_rows`, `visible_cells`)
- normal-lane cell count
- complex-lane cell count
- complex-lane reason counts
- explicit counts for icon, special-sprite, curly-underline, emoji, and multi-codepoint regressions
- normal-cluster and complex-cluster counts
- normal and complex clusters that still entered resolved-run construction
- normal and complex clusters that still entered shaping
- normal and complex glyph groups that still entered legacy grouping
- normal and complex sprite draws that still entered legacy scene preparation
- cold-path timings and cold miss counts, reported separately from warm steady-state timings and misses
- resolve/shape/group/scene timing so complex-lane cost remains measurable separately from the normal lane
- whether the frame was fully normal input
- whether the frame actually stayed out of the full legacy path

Interpretation rule:
- `frame_fully_normal_input=true` and `frame_stayed_out_of_legacy_path=false` means ordinary text is still leaking into the old architecture.

## Linux Host Gate Surface

Milestone gates use the existing sequential artifact-backed Linux-host surface.

Canonical command shape:

```sh
python3 howl-hosts/howl-linux-host/tools/benchmark_terminals.py --build --duration 10 --mode ascii --terminals howl
```

Artifact rule:
- use the run directory written under `howl-hosts/howl-linux-host/artifacts/stress/`
- do not replace this with ad hoc host profiling code for milestone proof

## Hot-Path Memory Contract

This is the locked ownership/bounds target for the final normal lane.

Owner:
- `howl-render`

Steady-state normal-lane buffers after initialization:
- visible normal-cell buffer: capacity `grid.rows * grid.cols`
- visible normal-glyph-key buffer: capacity `grid.rows * grid.cols`
- visible normal-draw buffer: capacity `grid.rows * grid.cols`
- normal-glyph cold-miss queue: capacity `grid.rows * grid.cols`
- atlas residency table: capacity bounded by backend `max_atlas_slots`

Rules:
- no per-frame heap allocation in the final normal lane
- no silent growth beyond the fixed capacities
- debug builds hard-fail on capacity overflow
- complex-lane storage stays separate from the normal-lane data plane

This contract is intentionally stricter than the current implementation so the next milestone can delete the wrong common path instead of renaming it.
