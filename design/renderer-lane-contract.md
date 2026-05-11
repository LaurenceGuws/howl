# Renderer Lane Contract

Purpose:
- lock the renderer-foundation lane split so Milestone 2 replaces the right path instead of preserving the old universal one.

Scope owner:
- `howl-render-core` owns lane policy, lane predicates, and lane-proof surfaces.
- `howl-term` may feed the renderer better cell text, but does not own lane policy.
- `howl-linux-host` remains a proof surface only.

## Normal Lane

The default normal lane is the only target for ordinary monospace text.

The unit of work is:
- one renderable cell head
- one resolved glyph identity
- one atlas-backed glyph draw submission

`howl-render-core/src/text/text_lane.zig` defines the exact positive predicate.

A cell is in the normal lane only when all of the following are true:
- `text.codepoints.len == 1`
- `presentation != .emoji`
- `symbol_map.builtinRoute(text.first_cp) == null`

Normal-lane implications:
- lane entry is decided before shaping/grouping machinery.
- normal text must not depend on full-run text hashes.
- normal text must not depend on row-wide run shaping as the default methodology.
- wide single-codepoint cells remain normal-lane work.

## Complex Lane

The complex lane is explicit and exceptional.

`howl-render-core/src/text/text_lane.zig` defines the exact positive predicates.

A cell is in the complex lane only for one of these reasons:
- `multi_codepoint`: `text.codepoints.len != 1`
- `emoji_presentation`: `presentation == .emoji`
- `special_sprite`: `symbol_map.builtinRoute(text.first_cp) != null`

Lane choice invariants:
- lane choice is assertion-checked.
- exactly one lane must match every classified cell or cluster.
- there is no fallback auto-routing based on downstream misses, cache state, or shaping side effects.
- the live text engine records all legacy-path work against this classifier before benchmark code sees the result.

## Current Wrong Path

The current implementation still leaks normal-lane text into the old universal path.

That leakage is now a measured defect, not an architecture choice:
- normal-lane cells still enter resolved-run construction
- resolved runs still enter shaping
- shaped runs still enter grouping and sprite-scene preparation

`howl-render-core/src/text/engine.zig` now records this leakage directly in the live owner path through `lane_report`.

Milestone 2 exists to delete that leakage path for normal text.

## Benchmark Proof Surface

Primary proof command:

```sh
zig build render-core-benchmark -- --text --runs 3
```

The scorecard must report, per workload:
- visible cell capacity (`grid_cols`, `grid_rows`, `visible_cells`)
- normal-lane cell count
- complex-lane cell count
- complex-lane reason counts
- normal-cluster and complex-cluster counts
- normal and complex clusters that still entered resolved-run construction
- normal and complex clusters that still entered shaping
- normal and complex glyph groups that still entered legacy grouping
- normal and complex sprite draws that still entered legacy scene preparation
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
- `howl-render-core`

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
