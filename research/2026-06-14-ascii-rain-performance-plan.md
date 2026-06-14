# ASCII Rain Performance Plan

Status:

- Active research artifact for the ASCII rain runtime-proof-first performance sprint.
- Orchestrator session id: `orch-2026-06-14-ascii-rain-performance-01`.
- Researcher session id: `research-2026-06-14-ascii-rain-performance-01`.
- Reviewer session id: `review-2026-06-14-ascii-rain-performance-01`.
- Iteration 1 optimization execution was rejected after benchmark and hotspot regression.
- Optimization slice 6 is accepted and cleanup slice 7 is accepted.
- Optimization slice 10 is accepted.
- Cleanup slice 11 is accepted.
- Proof-only slice 12 is complete and re-proved the cleaned post-slice-10 bottleneck, with `append_renderable(...)` now the largest named inner cost on the same direct-normal workload path.
- Proof-only slice 15 hit its stop condition honestly; the blocker was the proof method for attributing remaining `append_renderable_ms`, not a structural product wall.
- Proof-only slice 16 completed and identified `renderable_append` as the dominant cleaned-code `appendRenderable(...)` subphase.
- Proof-only slice 19 completed and identified `decoration_geometry` as the dominant named moved inline-decoration subphase.
- Optimization slice 20 is accepted.
- Cleanup slice 21 is accepted.
- Proof-only slice 22 completed and re-proved the current cleaned-code inner costs after accepted slice 20.
- Cleanup slice 23 is accepted and removed the mixed `appendRenderable(...)` owner into one rect-side child owner and one sprite/text child owner.
- Proof-only slice 24 completed and ranked the cleaned `appendRenderable(...)` owner shape.
- Slice-24 proof is ranking-only unless a later receipt proves comparability against earlier pre-cleanup or pre-rerun proof runs.
- Correction: for this bucket, the user's original sprint instruction requires mixed hot owners to be resolved structurally once proved hot, rather than split indefinitely into finer proof subphases.
- Slice-24 ranking proof is accepted as historical/current context only.
- Accepted slice-24 ranking result: `direct_normal.renderableAppend(...)` became the accountable hot child seam and authorized cleanup slice 25.
- Cleanup slice 25 is accepted and removed the mixed `renderableAppend(...)` owner into exact local child owners while preserving behavior.
- Proof-only slice 25 is complete on the accepted `renderableAppend(...)` owner shape.
- Slice-25 proof is ranking-only/current-shape proof unless a later receipt proves comparability against earlier runs.
- Proof-only slice 26 is complete on the further-cleaned `renderableAppend(...)` owner shape.
- Slice-26 proof is ranking-only/current-shape proof unless a later receipt proves comparability against earlier runs.
- Accepted slice-26 interpretation promoted cleanup at `direct_normal.appendResolvedGlyph(...)`.
- Cleanup slice 27 is accepted and reduced `appendResolvedGlyph(...)` to exact local children while preserving behavior.
- Proof-only slice 27 is complete on the further-cleaned `renderableAppend(...)` owner shape.
- Slice-27 proof is ranking-only/current-shape proof unless a later receipt proves comparability against earlier runs.
- The active current step is post-proof interpretation of slice 27 at `direct_normal.renderableAppend(...)` before any further optimization planning.
- Accepted slice-27 interpretation: no named child target is honestly authorized from the current receipt because `renderable_append_ms` still materially dominates every named inner timer on the current owner shape.
- The next honest move is one more local proof step at `direct_normal.renderableAppend(...)`, not a cleanup slice and not an optimization slice.
- Proof-only slice 28 is complete on the further-cleaned `renderableAppend(...)` owner shape.
- Slice-28 proof is same-run current-shape child-comparison proof only; comparability against slice 27 or earlier runs is not claimed.
- Substantive slice-28 interpretation: same-run normalized child-owner cost at the `renderableAppend(...)` seam points to `direct_normal.appendResolvedGlyph(...)` as the honest next local target because it is costlier per call than both sibling child owners on the same receipt.
- Accountability correction is closed by the rerun receipt `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-28-rerun.log:155-157` with the correct slice-28 session id.
- Proof-only slice 29 is complete on the accepted `appendResolvedGlyph(...)` owner shape.
- Slice-29 proof is ranking-only/current-shape proof unless a later receipt proves comparability against earlier runs.
- The active current step is post-proof interpretation of slice 29 at `direct_normal.appendResolvedGlyph(...)` before any further optimization planning.
- Corrected slice-29 rerun receipt: `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-29-rerun.log:121-157`.
- The next honest move is to interpret the slice-29 receipt and authorize only the next exact local move it supports.

User override receipt:

- Exact user decision: "this sprint starts with coder hotspot proof before researcher hotspot planning" and "research only. do not implement. do not commit. do not touch git. update the active research artifact in place."
- Exact workflow being overridden: the default planning order in `loop/flow.md:16-19` where researcher planning normally precedes coder execution.
- Reason for override: this sprint is runtime-proof-first; each iteration must prove the dominant bottleneck before planning the next optimization slice.
- Orchestrator session id: `orch-2026-06-14-ascii-rain-performance-01`.
- Researcher session id: `research-2026-06-14-ascii-rain-performance-01`.
- Reviewer session id: `review-2026-06-14-ascii-rain-performance-01`.
- User approval receipt location: `sprints/current.txt:22-27` and `loops/ascii-rain-performance-live-loop.txt:22-33`.

Active measured receipts now in scope:

- benchmark command: `python3 utils/tools/rain-bench/benchmark_terminals.py --build`
- baseline benchmark summary: `utils/tools/rain-bench/artifacts/stress/20260614-034739-ascii/summary.json`
- proof benchmark summary before iteration 1 fix: `utils/tools/rain-bench/artifacts/stress/20260614-035834-ascii/summary.json`
- benchmark summary after rejected iteration 1 fix: `utils/tools/rain-bench/artifacts/stress/20260614-042656-ascii/summary.json`
- benchmark summary after proof-only slice 2: `utils/tools/rain-bench/artifacts/stress/20260614-105248-ascii/summary.json`
- benchmark summary after proof-only slice 3: `utils/tools/rain-bench/artifacts/stress/20260614-110424-ascii/summary.json`
- benchmark summary after proof-only slice 4: `utils/tools/rain-bench/artifacts/stress/20260614-111512-ascii/summary.json`
- benchmark summary after proof-only slice 5: `utils/tools/rain-bench/artifacts/stress/20260614-113347-ascii/summary.json`
- benchmark summary after optimization slice 6 confirmatory rerun: `utils/tools/rain-bench/artifacts/stress/20260614-114801-ascii/summary.json`
- benchmark summary after cleaned-code proof-only slice 8: `utils/tools/rain-bench/artifacts/stress/20260614-121754-ascii/summary.json`
- benchmark summary after proof-only slice 9: `utils/tools/rain-bench/artifacts/stress/20260614-123522-ascii/summary.json`
- benchmark summary after proof-only slice 12: `utils/tools/rain-bench/artifacts/stress/20260614-131225-ascii/summary.json`
- benchmark summary after proof-only slice 13: `utils/tools/rain-bench/artifacts/stress/20260614-132443-ascii/summary.json`
- benchmark summary after proof-only slice 15: `utils/tools/rain-bench/artifacts/stress/20260614-140305-ascii/summary.json`
- benchmark summary after proof-only slice 19: `utils/tools/rain-bench/artifacts/stress/20260614-153152-ascii/summary.json`
- benchmark summary after optimization slice 20: `utils/tools/rain-bench/artifacts/stress/20260614-154427-ascii/summary.json`
- proof log artifact containing before/after checkpoints: `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log`
- proof artifact for slice-15 stop-condition receipt: `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-15.log`
- authoritative slice-16 proof artifact set:
  - `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-16-renderable_append.log`
  - `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-16-blank_fast_return.log`
  - `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-16-resolve_face.log`
  - `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-16-lookup_glyph.log`
  - `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-16-key_derivation.log`
  - `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-16-atlas_reserve.log`
  - `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-16-raster_enqueue.log`
  - `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-16-sprite_append.log`
  - `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-16-lane_report_update.log`
- authoritative slice-19 proof artifact: `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-19-renderable_append.log`
- authoritative slice-20 proof before receipt: `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-19-renderable_append.log:79-80`
- authoritative slice-20 proof after receipt: `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-fix-20-renderable_append.log:87-88`
- exact hotspot seam still under study: `howl-linux-host/src/terminal/surface.zig:575-600`, with dominant call `self.term.render.prepare(render_visible)` at `howl-linux-host/src/terminal/surface.zig:587`
- exact temporary instrumentation files and line references from the active proof surface:
  - `howl-linux-host/src/terminal/surface.zig:51-98`
  - `howl-linux-host/src/terminal/surface.zig:575-600`
  - `howl-render/src/text/ft_hb/support.zig:128-201`
  - `howl-render/src/text/ft_hb/support.zig:248-288`
  - `howl-render/src/text/shape/cluster.zig:156-200`
  - `howl-render/src/text/shape/cluster.zig:307-352`
- measured benchmark sequence:
  - baseline Howl: `147.74 fps`, `p50 6673 us`, `p95 9335 us`
  - proof-run Howl before iteration 1 fix: `181.02 fps`, `p50 5038 us`, `p95 7512 us`
  - after rejected iteration 1 fix: `175.28 fps`, `p50 5104 us`, `p95 7681 us`
  - after proof-only slice 2: `148.22 fps`, `p50 6350 us`, `p95 10404 us`
  - after proof-only slice 3: `115.77 fps`, `p50 8224 us`, `p95 12463 us`
  - after proof-only slice 4: `166.55 fps`, `p50 5375 us`, `p95 8345 us`
  - after proof-only slice 5: `92.48 fps`, `p50 9019 us`, `p95 16948 us`
  - after optimization slice 6 confirmatory rerun: `125.66 fps`, `p50 7890 us`, `p95 11568 us`
  - after cleaned-code proof-only slice 8: `97.29 fps`, `p50 8914 us`, `p95 16165 us`
  - after proof-only slice 9: `13.62 fps`, `p50 69425 us`, `p95 123925 us`
  - after proof-only slice 12: `62.09 fps`, `p50 12681 us`, `p95 33157 us`
  - after proof-only slice 13: `71.17 fps`, `p50 6416 us`, `p95 46124 us`
  - after proof-only slice 15: `7.10 fps`, `p50 138970 us`, `p95 163999 us`
  - after proof-only slice 19: `4.56 fps`, `p50 219304 us`, `p95 243587 us`
  - after optimization slice 20: `4.95 fps`, `p50 204000 us`, `p95 225529 us`
  - slice-16 one-at-a-time runs were used only as supporting benchmark context; owner-path proof logs are the authoritative promoted receipt surface for that step
- active interpretation verdict:
  - temporary deeper probes in `support.zig` and `cluster.zig` stayed cold on this workload path
  - render prepare remains the dominant measured phase in the host surface render turn
  - the rejected two-slot retained ingress/queue fix made the same hotspot worse rather than removing it
  - the active proved workload path is now `direct_normal.prepare(...)` on the publication fast path with zero fallback rejects
  - accepted slice 6 improved the proved `source_candidate(...)` and `append_visible(...)` owner path materially, then cleanup removed temporary proof scaffolding
  - the cleaned-code re-proof still shows `append_visible(...)` as the dominant real-work subphase
  - proof-only slice 9 isolated `publication_renderable_text(...)` as the prior dominant cleaned-code inner cost inside `source_candidate(...)`
  - accepted optimization slice 10 materially improved `publication_renderable_text(...)` on the proved hot path
  - the cleaned post-slice-10 re-proof now shows `append_renderable(...)` as the largest named inner cost on the same direct-normal workload path
  - proof-only slice 13 shows `lookup_glyph(...)` as the largest named measured `append_renderable(...)` subphase, but most of `append_renderable_ms` remains unattributed
  - proof-only slice 15 hit its stop condition honestly: even with more local splits, most of `append_renderable_ms` remained unattributed
  - proof-only slice 16 solved that proof-method blocker with one-at-a-time mode runs and identified `renderable_append` as the dominant named cleaned-code `appendRenderable(...)` subphase
  - slice 17 was directionally right but changed the owner enough that a corrective proof was required before more optimization
  - proof-only slice 18 showed moved inline rect work dominates the new mixed `appendRenderable(...)` owner
  - proof-only slice 19 showed `decoration_geometry` is the dominant named moved inline-decoration subphase
  - optimization slice 20 reduced normalized `decoration_geometry`, `inline_decoration`, `append_scene_rects`, and `direct_normal_prepare` cost while preserving `fallback_reject_calls == 0`
  - benchmark variance under proof remains noisy, but the current review step is now judging the focused slice-20 receipt set on its merits

## Post-Proof-Slice-9 Interpretation

Status:

- Proof-only slice 9 completed.
- The newly proved dominant cleaned-code inner cost inside `source_candidate(...)` is `publication_renderable_text(...)`.
- A new local optimization slice is now justified.

Sources read in order for this pass:

1. `loop/flow.md`
2. `loop/orcestrator.md`
3. `loop/researcher.md`
4. `loop/reviewer.md`
5. `loop/coder.md`
6. `loop/researcher.md` again as active role contract
7. `sprints/current.txt`
8. `loops/ascii-rain-performance-live-loop.txt`
9. `research/2026-06-14-ascii-rain-performance-plan.md`
10. proof receipt `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log:2745`
11. `reference-index.md`
12. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
13. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
14. `howl-render/src/text/direct_normal.zig:198-273`
15. `howl-render/src/text/direct_normal.zig:305-336`
16. `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:41-88`
17. `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:783-879`
18. `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:57-69`

Exact files and line references:

- Proof receipt for this pass: `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log:2745`.
- Benchmark receipt for this pass: `utils/tools/rain-bench/artifacts/stress/20260614-123522-ascii/summary.json:47-82`.
- Cleaned-code source-candidate hot path: `howl-render/src/text/direct_normal.zig:305-336`.
- Supported publication hot path setup and direct-normal owner entry: `howl-render/src/text/direct_normal.zig:198-273`.

Measured subphase interpretation:

- The slice-9 proof is sharp enough to isolate `publication_renderable_text(...)` as the dominant cleaned-code inner cost inside `source_candidate(...)`.
- Receipt at `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log:2745` shows:
- `source_candidate_ms=4994.438`
- `publication_cell_supported_ms=550.566`
- `publication_renderable_text_ms=1663.237`
- `publication_damage_include_ms=556.879`
- `append_renderable_ms=982.064`
- `fallback_reject_calls=0`
- `publication_renderable_text_ms` is well above support checks and damage include filtering.
- The benchmark on this proof-heavy run is badly distorted, but the owner-path verdict remains stable and accountable.

Current-code facts for `publication_renderable_text`:

- The supported publication fast path now avoids `PublicationCandidate` / `Candidate` wrappers, but it still constructs renderable/text facts per cell before damage include and append (`howl-render/src/text/direct_normal.zig:311-316`).
- That construction remains inside `direct_normal.zig`; no broader owner or ABI seam is required for the next move.
- `fallback_reject_calls=0` remains true, so unsupported-cell fallback semantics are not the active hot path on this workload.

Relevant reference facts:

- Alacritty still prepares borrowed terminal content with minimal per-cell packaging before draw (`display/content.rs:41-88`, `display/mod.rs:783-879`, `renderer/text/mod.rs:57-69`).
- The matching pressure here is still to cut per-cell construction work on the hot path before rendering, not to broaden architecture.

Exact next-step recommendation:

- Continue locally with one optimization slice.
- The best next local move is to specialize `publicationRenderableText(...)` on the supported publication hot path and reduce repeated per-cell construction/conversion work there.

One exact next slice:

- Slice type: optimization.
- Allowed files:
- `howl-render/src/text/direct_normal.zig`

- Exact required shape:
- Keep all changes inside `direct_normal.zig`.
- Optimize the supported publication hot path by specializing `publicationRenderableText(...)`.
- Reduce repeated per-cell construction/conversion work there.
- Keep supported output bytes and semantics identical.
- Preserve unsupported-cell fallback behavior exactly.
- Do not change `appendRenderable(...)`, glyph lookup, atlas reserve, damage filtering, or non-publication paths.

- Exact tests:
- from `howl-render`, run `zig build test:abi`
- from `howl-render`, run `zig build test:unit`
- keep existing direct-normal owner tests green:
- `howl-render/src/text/direct_normal.zig`: `test "direct normal publication zero codepoint is a fast candidate"`
- `howl-render/src/text/direct_normal.zig`: `test "direct normal publication keeps unsupported non-printables on generic fallback"`
- keep existing publication direct-path tests green:
- `howl-render/src/text/surface_preparer.zig`: `test "text preparation publication ascii stays on direct normal path"`
- `howl-render/src/text/surface_preparer.zig`: `test "text preparation publication styled indexed ascii stays on direct normal path"`
- `howl-render/src/text/surface_preparer.zig`: `test "text preparation publication non inverse indexed ascii stays on direct normal path"`
- `howl-render/src/text/surface_preparer.zig`: `test "text preparation publication zero codepoint stays on direct normal path without sprite draw"`
- `howl-render/src/text/surface_preparer.zig`: `test "text preparation publication unsupported space and rgb keep fallback scratch clean"`
- `howl-render/src/text/surface_preparer.zig`: `test "text preparation publication tab stays on generic fallback without partial direct scratch"`
- `howl-render/src/text/surface_preparer.zig`: `test "text preparation publication other control stays on generic fallback without partial direct scratch"`

- Exact benchmark/proof requirements:
- rerun `python3 utils/tools/rain-bench/benchmark_terminals.py --build`
- rerun the current proof-only receipts sufficiently to compare before/after at the same owner path
- required measured outputs:
- `publication_renderable_text_ms`
- `source_candidate_ms`
- `append_visible_ms`
- total `prepare_ms`
- Howl FPS / p50 / p95

- Exact non-goals:
- no changes outside `direct_normal.zig`
- no glyph lookup optimization yet
- no atlas/raster optimization yet
- no fallback/publication ABI expansion
- cleanup is handled by the separate cleanup slice, not this optimization contract itself

- Exact stop conditions:
- stop if preserving supported output bytes or unsupported-cell fallback semantics requires edits outside `direct_normal.zig`
- stop if benchmark and proof both fail to improve the proved `publication_renderable_text` / `source_candidate` hot path

- Exact receipt fields needed for acceptance:
- orchestrator session id: `orch-2026-06-14-ascii-rain-performance-01`
- researcher session id: `research-2026-06-14-ascii-rain-performance-01`
- reviewer session id: `review-2026-06-14-ascii-rain-performance-01`
- coder session id
- exact changed files and line references
- verification command list and results
- benchmark command
- benchmark artifact path
- proof log artifact path
- exact proof location lines
- measured before
- measured after
- verdict on `publication_renderable_text_ms`, `source_candidate_ms`, `append_visible_ms`, and total `prepare_ms`
- commit-hash receipt status

Risks:

- A win here may quickly expose either `publication_cell_supported(...)` or `appendRenderable(...)` next.
- Benchmark variance remains noisy, so proof-path movement must remain the primary acceptance signal.

Proof gaps:

- We do not yet know the best follow-up after this slice until we see the post-change proof.

Readiness judgment:

- Ready for a local optimization slice.
- This remains a local runtime-proof-first sprint, not a structural blocker.

## Post-Slice-10 Cleaned Reproof Interpretation

Status:

- Optimization slice 10 is accepted and cleanup slice 11 is accepted.
- Cleaned-code proof slice 12 re-proved the current direct-normal bottleneck after accepted slice 10 and cleanup.
- The accountable next move changes from `source_candidate(...)` to `append_renderable(...)`, but one more proof split is still required before another optimization is honest.

Sources read in order for this pass:

1. `loop/flow.md`
2. `loop/orcestrator.md`
3. `loop/researcher.md`
4. `loop/reviewer.md`
5. `loop/coder.md`
6. `loop/researcher.md` again as active role contract
7. `sprints/current.txt`
8. `loops/ascii-rain-performance-live-loop.txt`
9. `research/2026-06-14-ascii-rain-performance-plan.md`
10. proof receipts at `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log:2774,2848`
11. `reference-index.md`
12. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
13. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
14. `howl-render/src/text/direct_normal.zig:280-355`
15. `howl-render/src/text/direct_normal.zig:433-527`
16. `howl-render/src/text/direct_normal.zig:613-665`
17. `howl-render/src/text/session.zig:56-115`
18. `howl-render/src/text/raster/atlas.zig:47-76`
19. `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:41-88`
20. `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:783-879`
21. `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:57-69`

Exact files and line references:

- Cleaned-code proof receipts: `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log:2774`, `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log:2848`.
- Current supported publication fast path in `appendVisible(...)`: `howl-render/src/text/direct_normal.zig:296-319`.
- Current `publicationRenderableText(...)` owner: `howl-render/src/text/direct_normal.zig:433-527`.
- Current `appendRenderable(...)` owner: `howl-render/src/text/direct_normal.zig:613-665`.
- Current face resolution owner callsite: `howl-render/src/text/direct_normal.zig:631-634`, with owner logic in `howl-render/src/text/session.zig:62-115`.
- Current glyph lookup owner callsite: `howl-render/src/text/direct_normal.zig:636-638`, with owner API in `howl-render/src/text/provider.zig:15-21`.
- Current atlas reservation owner callsite: `howl-render/src/text/direct_normal.zig:638-640`, with owner logic in `howl-render/src/text/raster/atlas.zig:54-66`.

Proof interpretation:

- The cleaned-code re-proof changes the next target.
- At receipt line `2774`, before cleanup removed the old aggregate path entirely, the supported publication path still showed `publication_renderable_text_ms=384.292` and `append_renderable_ms=343.813`, with `source_candidate_ms=1561.866` still reflecting mixed earlier accounting.
- At cleaned-code receipt line `2848`, the supported publication fast path no longer attributes meaningful time to aggregate `source_candidate_ms` (`0.000`), and the named inner costs become:
- `publication_cell_supported_ms=579.089`
- `publication_renderable_text_ms=608.930`
- `publication_damage_include_ms=553.032`
- `append_renderable_ms=830.109`
- `append_visible_ms=5169.908`
- `append_scene_rects_ms=186.023`
- `finish_scene_ms=95.414`
- `fallback_reject_calls=0`
- `append_renderable_calls=29413736`
- `raster_req_count_total=2203`
- Therefore, on cleaned post-slice-10 code, `append_renderable(...)` is now the largest named inner cost on the hot path.
- Benchmark variance does not require a different accountability move here; the proof receipts are stable on the same owner path and remain the governing evidence.

Current-code facts for `append_renderable`:

- `appendRenderable(...)` is now the next local hot owner, but it still mixes several materially different costs (`howl-render/src/text/direct_normal.zig:613-665`):
- `resolveFace(...)` (`631-634`)
- `lookupGlyph(...)` (`636`)
- `atlas.reserve(...)` (`638-640`)
- optional raster-request enqueue (`640-648`)
- sprite draw append and placement math (`650-664`)
- The cleaned-code proof also shows `raster_req_count_total=2203`, so raster misses remain active enough that `appendRenderable(...)` is not just a trivial face/lookup wrapper.
- Because these costs are still mixed together inside one owner, another optimization directly in `appendRenderable(...)` would still require design discretion without one more proof split.

Relevant Alacritty/reference facts:

- Alacritty still streams borrowed renderable cells directly into text drawing (`display/content.rs:41-88`, `display/mod.rs:783-879`, `renderer/text/mod.rs:57-69`).
- The closest reference pressure here is to reduce per-cell render append work on the hot path, but not by guessing whether the real cost is face selection, glyph lookup, atlas residency, or sprite append.

Exact next-step recommendation:

- Continue locally.
- `append_renderable(...)` is now the right next local target.
- One more proof split is required before another optimization would be honest.

One exact next slice:

- Slice type: proof only, no optimization.
- Allowed files:
- `howl-render/src/text/direct_normal.zig`

- Exact required shape:
- Keep the proof local to `direct_normal.zig` only.
- Add temporary narrow timing logs that split `append_renderable_ns` into:
- `resolve_face_ns`
- `lookup_glyph_ns`
- `atlas_reserve_ns`
- `sprite_append_ns`
- Keep the existing counters for:
- `append_renderable_calls`
- `raster_req_count_total`
- `visible_cells_scanned`
- `included_normal_cells`
- `direct_success_calls`
- `fallback_reject_calls`
- Do not change behavior.

- Exact tests:
- from `howl-render`, run `zig build test:abi`
- from `howl-render`, run `zig build test:unit`

- Exact benchmark/proof requirements:
- rerun `python3 utils/tools/rain-bench/benchmark_terminals.py --build`
- append one fresh proof section to `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log` or write one exact new proof log path and record it
- the proof output must identify which of these dominates current cleaned-code `append_renderable` work on ASCII rain:
- `resolve_face`
- `lookup_glyph`
- `atlas_reserve`
- `sprite_append`

- Exact non-goals:
- no optimization yet
- no instrumentation cleanup yet
- no edits outside `howl-render/src/text/direct_normal.zig`
- no ABI changes
- no benchmark harness changes

- Exact stop conditions:
- stop if splitting cleaned-code `append_renderable` requires edits outside `howl-render/src/text/direct_normal.zig`
- stop if the new proof fails to isolate one dominant `append_renderable` subphase
- stop if the counters cease to describe the same workload path, for example if `fallback_reject_calls` stops being zero on the cleaned-code run

- Exact receipt fields needed for acceptance:
- orchestrator session id: `orch-2026-06-14-ascii-rain-performance-01`
- researcher session id: `research-2026-06-14-ascii-rain-performance-01`
- reviewer session id: `review-2026-06-14-ascii-rain-performance-01`
- coder session id
- exact changed files and line references
- verification command list and results
- benchmark command
- benchmark artifact path
- proof log artifact path
- exact proof location lines
- measured before
- measured after
- dominant cleaned-code `append_renderable` subphase verdict
- commit-hash receipt status

Risks:

- The next proof slice may reveal that `append_renderable(...)` is split relatively evenly, which would mean smaller gains per micro-optimization.
- If `atlas_reserve_ns` dominates, the next optimization may need tighter coordination with cache behavior even though the slice remains local.
- Benchmark variance remains noisy and must not outrank proof-path movement in acceptance.

Proof gaps:

- We do not yet know whether cleaned-code `append_renderable(...)` is mostly face resolution, glyph lookup, atlas reserve, or sprite append.
- We do not yet know whether the best follow-up after that split stays inside `direct_normal.zig` or will need a second owner under the same hot path.

Readiness judgment:

- Ready for one more local proof-only slice.
- Not ready for another optimization slice yet.
- This remains a local runtime-proof-first sprint, not a structural blocker.

## Post-Proof-Slice-18 Interpretation

Status:

- Proof-only slice 18 succeeded.
- The new mixed post-slice-17 `appendRenderable(...)` owner is now re-accounted enough to identify the next hotspot class honestly.
- Moved inline rect work dominates the post-slice-17 owner overall.
- But the largest named subphase is still a mixed helper owner, so another proof split is still required before the next optimization.

Sources read in order for this pass:

1. `loop/flow.md`
2. `loop/orcestrator.md`
3. `loop/researcher.md`
4. `loop/reviewer.md`
5. `loop/coder.md`
6. `loop/researcher.md` again as active role contract
7. `sprints/current.txt`
8. `loops/ascii-rain-performance-live-loop.txt`
9. `research/2026-06-14-ascii-rain-performance-plan.md`
10. proof receipt `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-18-renderable_append-v2.log:46-51`
11. benchmark receipt `utils/tools/rain-bench/artifacts/stress/20260614-151809-ascii/summary.json`
12. `reference-index.md`
13. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
14. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
15. `howl-render/src/text/direct_normal.zig:51-101`
16. `howl-render/src/text/direct_normal.zig:143-152`
17. `howl-render/src/text/direct_normal.zig:689-770`
18. `howl-render/src/text/direct_scene.zig:37-76`
19. `howl-render/src/text/scene_rects.zig:164-204`
20. `howl-render/src/text/scene_rects.zig:248-283`
21. `howl-render/src/text/scene_rects.zig:345-356`
22. `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:49-87`
23. `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:783-879`
24. `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:57-69`

Exact files and line references:

- Slice-18 proof receipt: `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-18-renderable_append-v2.log:46-51`.
- Slice-18 benchmark receipt: `utils/tools/rain-bench/artifacts/stress/20260614-151809-ascii/summary.json:47-80`.
- Current scratch owner after slice 17/18: `howl-render/src/text/direct_normal.zig:51-101`.
- Current end-of-prepare residual rect seam: `howl-render/src/text/direct_normal.zig:143-152`.
- Current mixed `appendRenderable(...)` owner: `howl-render/src/text/direct_normal.zig:689-770`.
- Current inline background helper seam: `howl-render/src/text/direct_scene.zig:37-47`, `howl-render/src/text/scene_rects.zig:164-204`.
- Current inline clear-note helper seam: `howl-render/src/text/direct_scene.zig:64-66`, `howl-render/src/text/scene_rects.zig:248-283`.
- Current inline decoration helper seam: `howl-render/src/text/direct_scene.zig:68-75`, `howl-render/src/text/scene_rects.zig:345-356`.

Compact anchor map:

- Alacritty borrowed renderable-content seam: `display/content.rs:49-87`.
- Alacritty collect-and-stream render path: `display/mod.rs:783-879`.
- Alacritty direct per-cell draw loop: `renderer/text/mod.rs:57-69`.
- Howl current mixed inline rect owner inside `appendRenderable(...)`: `direct_normal.zig:701-710`.
- Howl current per-cell decoration helper owner: `scene_rects.zig:345-356`.

Proof interpretation:

- Slice 18 answered the post-slice-17 accountability question.
- Receipt at `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-18-renderable_append-v2.log:46` shows:
- `append_renderable_ms=4610.427`
- `renderable_append_ms=2584.747`
- `inline_background_ms=398.590`
- `inline_clear_note_ms=357.387`
- `inline_decoration_ms=426.224`
- `blank_fast_return_ms=357.341`
- `resolve_face_ms=40.900`
- `lookup_glyph_ms=113.807`
- `key_derivation_ms=85.998`
- `atlas_reserve_ms=73.562`
- `raster_enqueue_ms=0.048`
- `sprite_append_ms=43.093`
- `lane_report_update_ms=38.690`
- `append_scene_rects_ms=0.499`
- `fallback_reject_calls=0`

- This is enough to conclude:
- moved inline rect work dominates the current mixed owner overall
- `inline_decoration` is the single largest named current subphase
- glyph lookup, key derivation, atlas reserve, sprite append, and lane bookkeeping are all clearly below the moved inline rect work and are not the next honest targets

- But this is still not yet optimization-ready at the final target level.
- `inline_decoration` names `scene_rects.appendRectDecorationCellDrawsUnmanaged(...)`, and that helper still mixes multiple costs in one owner:
- damage/classification gate
- cell geometry derivation
- underline path
- strikethrough path
- possible underline draw fanout underneath `appendUnderlineDrawsUnmanaged(...)`

- So the next honest move is not yet a direct optimization.
- Another proof split is still required, but now it is sharply local and owner-true.

Current-code facts:

- The retained `RenderableCell` list remains removed; slice 17's owner shift still stands.
- Inline rect work now happens before the blank fast return in `appendRenderable(...)` (`direct_normal.zig:701-710`).
- `append_scene_rects_ms` is effectively gone, so the sprint should stay on the moved inline rect work rather than backtracking to the old retained-list seam.
- The benchmark receipt for slice 18 is clearly instrumentation-perturbed (`5.29 fps` at `summary.json:47-80`), so it is not a product regression signal; the proof receipt remains the authority for this pass.

Reference facts:

- Alacritty pressure still favors doing only the necessary per-cell work close to draw/content handling (`display/content.rs:49-87`, `display/mod.rs:783-879`, `renderer/text/mod.rs:57-69`).
- Alacritty also updates line/decoration state as cells are streamed (`display/mod.rs:873-881`), which increases pressure against expensive per-cell decoration draw fanout in the hot path.
- That pressure supports staying on the moved inline rect work, especially the decoration path, but does not yet justify optimizing a mixed helper without one more proof split.

Exact next-step recommendation:

- Continue locally on the moved inline rect work.
- Do not optimize yet.
- Run one more proof-only slice splitting `inline_decoration` inside the owner-true decoration helper seam.

One exact next slice:

- Slice type: proof only.
- Allowed files:
- `howl-render/src/text/direct_normal.zig`
- `howl-render/src/text/scene_rects.zig`

- Exact required shape:
- keep `HOWL_APPEND_RENDERABLE_PROOF_MODE=renderable_append` as the outer focused mode
- keep current slice-18 timers intact
- add owner-true narrow timing for `inline_decoration` so the proof identifies which of these dominates inside current per-cell decoration work:
- `decoration_classify_ns`
- `decoration_geometry_ns`
- `decoration_underline_ns`
- `decoration_strikethrough_ns`
- if underline fanout is itself still mixed inside current source, split it only one level further if needed and only inside `scene_rects.zig`
- do not change behavior
- do not reintroduce retained full-cell publication

- Exact tests:
- from `howl-render`, run `zig build test:abi`
- from `howl-render`, run `zig build test:unit`

- Exact benchmark/proof requirements:
- rerun `HOWL_APPEND_RENDERABLE_PROOF_MODE=renderable_append python3 utils/tools/rain-bench/benchmark_terminals.py --build`
- record one exact fresh proof log path or one clearly separated fresh section
- the proof package must end with one verdict naming the dominant `inline_decoration` subphase on current code
- keep reporting:
- `append_renderable_ms`
- `renderable_append_ms`
- `inline_background_ms`
- `inline_clear_note_ms`
- `inline_decoration_ms`
- `append_scene_rects_ms`
- `direct_normal_prepare_ms`
- `append_renderable_calls`
- `fallback_reject_calls`

- Exact non-goals:
- no optimization yet
- no ABI changes
- no benchmark harness changes
- no host/runtime changes
- no glyph/atlas/raster changes
- no retained-list reintroduction

- Exact stop conditions:
- stop if splitting `inline_decoration` honestly requires edits outside `howl-render/src/text/direct_normal.zig` and `howl-render/src/text/scene_rects.zig`
- stop if the proof still cannot isolate one dominant decoration subphase
- stop if `fallback_reject_calls` becomes non-zero

- Exact receipt fields needed for acceptance:
- orchestrator session id: `orch-2026-06-14-ascii-rain-performance-01`
- researcher session id: `research-2026-06-14-ascii-rain-performance-01`
- reviewer session id: `review-2026-06-14-ascii-rain-performance-01`
- coder session id
- exact changed files and line references
- verification command list and results
- benchmark command
- benchmark artifact path
- proof log artifact path
- exact proof location lines
- measured before
- measured after
- verdict on dominant `inline_decoration` subphase
- commit-hash receipt status

Risks:

- The current proof run is instrumentation-heavy enough that benchmark FPS is not decision-grade for this pass.
- If underline fanout dominates, the best next optimization may require a more structural decoration accumulation shape, and that must stay reference-pressured rather than invented casually.

Proof gaps:

- We still do not know whether the current decoration cost is mostly classification, geometry, underline fanout, or strikethrough emission.
- We therefore still do not know the smallest honest optimization inside the moved inline rect work.

Readiness judgment:

- Ready for one more sharp local proof-only slice.
- Not ready for an optimization slice yet.
- This remains a local render-owner sprint, not a structural blocker.

## Post-Proof-Slice-19 Interpretation

Status:

- Proof-only slice 19 succeeded.
- The moved inline-decoration owner is now split enough to name one dominant owner-true target.
- `decoration_geometry` is now optimization-ready.
- Another proof split is not required before the next optimization slice.

Sources read in order for this pass:

1. `loop/flow.md`
2. `loop/orcestrator.md`
3. `loop/researcher.md`
4. `loop/reviewer.md`
5. `loop/coder.md`
6. `loop/researcher.md` again as active role contract
7. `sprints/current.txt`
8. `loops/ascii-rain-performance-live-loop.txt`
9. `research/2026-06-14-ascii-rain-performance-plan.md`
10. proof receipt `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-19-renderable_append.log:79-85`
11. benchmark receipt `utils/tools/rain-bench/artifacts/stress/20260614-153152-ascii/summary.json`
12. `reference-index.md`
13. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
14. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
15. `howl-render/src/text/direct_normal.zig:704-732`
16. `howl-render/src/text/scene_rects.zig:340-401`
17. `howl-render/src/text/scene_rects.zig:525-553`
18. `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:49-87`
19. `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:845-882`
20. `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:57-69`

Exact files and line references:

- Slice-19 proof receipt: `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-19-renderable_append.log:79-85`.
- Slice-19 benchmark receipt: `utils/tools/rain-bench/artifacts/stress/20260614-153152-ascii/summary.json:47-80`.
- Current mixed inline-rect owner in `appendRenderable(...)`: `howl-render/src/text/direct_normal.zig:704-732`.
- Current decoration split owner: `howl-render/src/text/scene_rects.zig:374-401`.
- Current underline helper owner: `howl-render/src/text/scene_rects.zig:525-553`.

Compact anchor map:

- Alacritty borrowed renderable-content seam: `display/content.rs:49-87`.
- Alacritty updates line/decoration state while streaming cells: `display/mod.rs:858-881`.
- Alacritty direct per-cell draw loop: `renderer/text/mod.rs:57-69`.
- Howl current per-cell decoration geometry owner: `scene_rects.zig:374-390`.
- Howl current per-cell underline draw owner: `scene_rects.zig:391-399`, `scene_rects.zig:525-553`.

Proof interpretation:

- Slice 19 resolved the remaining proof gap inside `inline_decoration`.
- Receipt at `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-19-renderable_append.log:79-80` shows:
- `inline_decoration_ms=1837.585`
- `decoration_classify_ms=301.430`
- `decoration_geometry_ms=913.653`
- `decoration_underline_ms=156.731`
- `decoration_strikethrough_ms=0.000`
- `inline_background_ms=340.088`
- `inline_clear_note_ms=306.754`
- `blank_fast_return_ms=306.526`
- `lookup_glyph_ms=94.152`
- `key_derivation_ms=73.631`
- `atlas_reserve_ms=64.873`
- `append_scene_rects_ms=0.390`
- `fallback_reject_calls=0`

- That is enough to make two honest decisions:
- moved inline rect work remains the right local path
- `decoration_geometry` is the dominant named moved inline-decoration subphase and is now the next optimization target

- Another proof split is not required because:
- `decoration_strikethrough` is effectively zero on this workload
- `decoration_underline` is materially smaller than `decoration_geometry`
- `decoration_classify` is also materially smaller than `decoration_geometry`
- the remaining geometry timer is already owner-true enough to optimize: it covers per-cell decoration geometry setup in `appendRectDecorationCellDrawsUnmanaged(...)`

Current-code facts:

- `decoration_geometry_ns` currently covers:
- `decorationGeometryForCellMetrics(cell_metrics)`
- `cols = max(grid_metrics.cols, 1)`
- per-cell `col`/`row` derivation
- per-cell `base_x`/`base_y` derivation
- per-cell `width_px` derivation
- all of that happens before underline/strikethrough fanout in `scene_rects.zig:374-390`
- Several of those inputs are invariant for the whole prepare or whole row/metrics context, especially `decorationGeometryForCellMetrics(cell_metrics)` and `cols`
- That creates clear local optimization pressure to hoist or precompute stable geometry inputs rather than recomputing them per cell.

Reference facts:

- Alacritty pressure still favors per-cell work that stays lean near the draw/content path and line-update path (`display/mod.rs:858-881`, `renderer/text/mod.rs:57-69`).
- That supports removing repeated geometry recomputation from the hot per-cell decoration path before considering broader changes.

Exact next-step recommendation:

- Continue locally.
- Authorize an optimization slice on `decoration_geometry`.

One exact next slice:

- Slice type: optimization.
- Allowed files:
- `howl-render/src/text/direct_normal.zig`
- `howl-render/src/text/direct_scene.zig`
- `howl-render/src/text/scene_rects.zig`

- Exact required shape:
- reduce the proved `decoration_geometry` cost inside the moved inline-decoration path
- prefer hoisting stable geometry facts out of the per-cell decoration helper, especially values derived only from `cell_metrics` and `grid_metrics`
- keep underline and strikethrough behavior unchanged
- keep damage gating unchanged
- keep `fallback_reject_calls == 0`
- do not reintroduce retained `RenderableCell` publication

- Exact tests:
- from `howl-render`, run `zig build test:abi`
- from `howl-render`, run `zig build test:unit`

- Exact benchmark/proof requirements:
- rerun `HOWL_APPEND_RENDERABLE_PROOF_MODE=renderable_append python3 utils/tools/rain-bench/benchmark_terminals.py --build`
- record one exact fresh proof log path or one clearly separated fresh proof section
- the proof package must report:
- `append_renderable_ms`
- `inline_decoration_ms`
- `decoration_classify_ms`
- `decoration_geometry_ms`
- `decoration_underline_ms`
- `decoration_strikethrough_ms`
- `append_scene_rects_ms`
- `direct_normal_prepare_ms`
- `append_renderable_calls`
- `fallback_reject_calls`
- acceptance requires a real drop in normalized `decoration_geometry` cost and no regression to the workload path

- Exact non-goals:
- no proof-only refactor without performance intent
- no ABI changes
- no benchmark harness changes
- no host/runtime changes
- no glyph/atlas/raster optimization
- no retained-list reintroduction

- Exact stop conditions:
- stop if reducing `decoration_geometry` honestly requires edits outside `howl-render/src/text/direct_normal.zig`, `howl-render/src/text/direct_scene.zig`, and `howl-render/src/text/scene_rects.zig`
- stop if the optimization merely moves the same geometry recomputation under a different local name without reducing normalized cost
- stop if `fallback_reject_calls` becomes non-zero

- Exact receipt fields needed for acceptance:
- orchestrator session id: `orch-2026-06-14-ascii-rain-performance-01`
- researcher session id: `research-2026-06-14-ascii-rain-performance-01`
- reviewer session id: `review-2026-06-14-ascii-rain-performance-01`
- coder session id
- exact changed files and line references
- verification command list and results
- benchmark command
- benchmark artifact path
- proof log artifact path
- exact proof location lines
- measured before
- measured after
- verdict on `decoration_geometry_ms`, `inline_decoration_ms`, and `direct_normal_prepare_ms`
- commit-hash receipt status

Risks:

- The benchmark receipt is still instrumentation-perturbed, so proof-path movement remains more trustworthy than FPS.
- If geometry hoisting is smaller than expected, underline fanout may become the next owner immediately.

Proof gaps:

- We still do not know whether the best geometry optimization is pure hoisting, caching in scratch, or a narrower helper-shape change.
- We do not yet know whether the next post-optimization hotspot will stay in decorations or shift back to backgrounds/clear-note or sprite-path work.

Readiness judgment:

- Ready for a local optimization slice.
- Not blocked on another proof split.
- This remains a local render-owner sprint, not a structural blocker.

## Post-Slice-20 Cleaned-Code Reproof Interpretation

Status:

- Accepted optimization slice 20 and accepted cleanup slice 21 changed the moved decoration geometry owner.
- Cleaned-code proof slice 22 re-proved the current direct-normal inner costs on current code.
- The next honest move is not yet an optimization on broad `renderable_append` or on moved inline background work.
- One more proof split is still required.

Sources read in order for this pass:

1. `loop/flow.md`
2. `loop/orcestrator.md`
3. `loop/researcher.md`
4. `loop/reviewer.md`
5. `loop/coder.md`
6. `loop/researcher.md` again as active role contract
7. `sprints/current.txt`
8. `loops/ascii-rain-performance-live-loop.txt`
9. `research/2026-06-14-ascii-rain-performance-plan.md`
10. proof receipt `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-22-renderable_append.log:146-148`
11. benchmark receipt `utils/tools/rain-bench/artifacts/stress/20260614-155956-ascii/summary.json`
12. `reference-index.md`
13. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
14. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
15. `howl-render/src/text/direct_normal.zig:720-743`
16. `howl-render/src/text/direct_scene.zig:37-75`
17. `howl-render/src/text/scene_rects.zig:186-226`
18. `howl-render/src/text/scene_rects.zig:270-304`
19. `howl-render/src/text/scene_rects.zig:372-379`
20. `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:49-87`
21. `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:845-882`
22. `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:57-69`

Exact files and line references:

- Cleaned-code proof receipt: `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-22-renderable_append.log:146-148`.
- Cleaned-code benchmark receipt: `utils/tools/rain-bench/artifacts/stress/20260614-155956-ascii/summary.json:47-80`.
- Current mixed `appendRenderable(...)` inner block: `howl-render/src/text/direct_normal.zig:733-743`.
- Current moved inline background owner: `howl-render/src/text/direct_scene.zig:37-47`, `howl-render/src/text/scene_rects.zig:186-226`.
- Current moved inline clear-note owner: `howl-render/src/text/direct_scene.zig:64-65`, `howl-render/src/text/scene_rects.zig:270-304`.
- Current moved inline decoration owner after accepted slice 20: `howl-render/src/text/direct_scene.zig:68-74`, `howl-render/src/text/scene_rects.zig:372-379`.

Compact anchor map:

- Alacritty borrowed renderable-content seam: `display/content.rs:49-87`.
- Alacritty streams cells while line/decoration state is updated in the same walk: `display/mod.rs:858-881`.
- Alacritty direct per-cell draw loop: `renderer/text/mod.rs:57-69`.
- Howl current mixed inline rect owner in `appendRenderable(...)`: `direct_normal.zig:733-743`.
- Howl current background helper owner: `scene_rects.zig:186-226`.
- Howl current clear-note helper owner: `scene_rects.zig:270-304`.

Proof interpretation:

- Receipt at `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-22-renderable_append.log:146-148` shows:
- `append_renderable_ms=4862.156`
- `renderable_append_ms=2718.942`
- `inline_background_ns=426760228`
- `inline_clear_note_ns=378686568`
- `inline_decoration_ns=425972365`
- `blank_fast_return_ms=378.893`
- `append_scene_rects_ms=0.526`
- `direct_normal_prepare_ms=7941.276`
- `append_renderable_calls=19417936`
- `fallback_reject_calls=0`

- This proves three things.

- First: accepted slice 20 held. The current cleaned path still keeps `append_scene_rects_ms` near zero, so the sprint should not move back toward the old retained-list or moved-decoration-geometry target.

- Second: broad `renderable_append` is still the largest measured current inner owner, but it is still too mixed to optimize honestly.
- Its current block in `direct_normal.zig:733-743` still aggregates:
- moved inline background work
- moved inline clear-note work
- moved inline decoration work
- plus any remaining local control/timing overhead in that same block

- Third: among the named current moved inline subphases, `inline_background` is only trivially larger than `inline_decoration` and very close to `inline_clear_note`.
- The gap is too small to justify an optimization choice directly:
- `inline_background_ms=426.760`
- `inline_decoration_ms=425.972`
- `inline_clear_note_ms=378.687`
- With those values this close, the next optimization target is not yet proven sharply enough.

- Therefore:
- do not optimize broad `renderable_append` yet
- do not optimize moved inline background yet
- run one more proof split on the moved inline background/clear-note side so the current cleaned-code winner is named honestly

Current-code facts:

- `appendRenderable(...)` still enters one mixed inline-rect block before the blank fast return (`direct_normal.zig:733-743`).
- Decoration geometry has already been hoisted into `RectDecorationLayout`, so the remaining decoration helper is not the only or clearly dominant current owner anymore.
- Background and clear-note helpers still recompute per-cell row/col/span/damage-related facts in their own owners (`scene_rects.zig:186-226`, `270-304`).

Reference facts:

- Alacritty pressure still favors lean per-cell work near the streaming path, but not guessing among nearly tied hot helpers.
- The right next move under that pressure is to split the current near-tied inline-rect owners until one real current winner is proved.

Exact next-step recommendation:

- Continue locally.
- Authorize one more proof-only slice.

One exact next slice:

- Slice type: proof only.
- Allowed files:
- `howl-render/src/text/direct_normal.zig`
- `howl-render/src/text/scene_rects.zig`

- Exact required shape:
- keep `HOWL_APPEND_RENDERABLE_PROOF_MODE=renderable_append`
- keep current cleaned-code timers intact
- split current moved inline background/clear-note work enough to choose the next target honestly
- add owner-true timers for exactly these current helper owners:
- `background_classify_ns`
- `background_merge_ns`
- `background_emit_ns`
- `clear_note_guard_ns`
- `clear_note_row_scan_ns`
- if one of those remains materially mixed after current-source inspection, split only one level deeper and only inside `scene_rects.zig`
- do not change behavior
- do not reintroduce retained `RenderableCell` publication

- Exact tests:
- from `howl-render`, run `zig build test:abi`
- from `howl-render`, run `zig build test:unit`

- Exact benchmark/proof requirements:
- rerun `HOWL_APPEND_RENDERABLE_PROOF_MODE=renderable_append python3 utils/tools/rain-bench/benchmark_terminals.py --build`
- record one exact fresh proof log path or one clearly separated fresh section
- the proof package must report:
- `append_renderable_ms`
- `renderable_append_ms`
- `inline_background_ns`
- `inline_clear_note_ns`
- `inline_decoration_ns`
- `background_classify_ns`
- `background_merge_ns`
- `background_emit_ns`
- `clear_note_guard_ns`
- `clear_note_row_scan_ns`
- `append_scene_rects_ms`
- `direct_normal_prepare_ms`
- `append_renderable_calls`
- `fallback_reject_calls`
- the proof package must end with one verdict naming the dominant current cleaned-code inner cost among moved inline background, clear-note, and decoration work

- Exact non-goals:
- no optimization yet
- no ABI changes
- no benchmark harness changes
- no host/runtime changes
- no glyph/atlas/raster changes

- Exact stop conditions:
- stop if proving the current background/clear-note winner requires edits outside `howl-render/src/text/direct_normal.zig` and `howl-render/src/text/scene_rects.zig`
- stop if the proof still fails to isolate one dominant current cleaned-code inner cost among those near-tied moved inline helpers
- stop if `fallback_reject_calls` becomes non-zero

- Exact receipt fields needed for acceptance:
- orchestrator session id: `orch-2026-06-14-ascii-rain-performance-01`
- researcher session id: `research-2026-06-14-ascii-rain-performance-01`
- reviewer session id: `review-2026-06-14-ascii-rain-performance-01`
- coder session id
- exact changed files and line references
- verification command list and results
- benchmark command
- benchmark artifact path
- proof log artifact path
- exact proof location lines
- measured before
- measured after
- verdict on the dominant cleaned-code moved-inline helper owner
- commit-hash receipt status

Risks:

- The benchmark remains instrumentation-perturbed and cannot decide between these near-tied helpers.
- If the next proof still leaves background and decoration essentially tied, the sprint may be approaching a measurement-method wall rather than a product wall.

Proof gaps:

- We still do not know whether the real current winner is moved inline background, moved inline clear-note, or residual mixed work left inside broad `renderable_append`.
- We do not yet know whether a future optimization should hoist background facts, tighten clear-row scanning, or revisit broader inline batching.

Readiness judgment:

- Ready for one more local proof-only slice.
- Not ready for another optimization slice yet.
- This remains a local render-owner sprint, not a structural blocker.

## User-Directed Style-First Reset For Mixed `appendRenderable(...)`

Status:

- The controlling user instruction for this bucket overrides the prior proof-only recommendation.
- Broad `appendRenderable(...)` is the focus.
- If that owner is mixed, the mixed owner itself is the debt and must be removed before more optimization targeting.
- Repeated finer proof-only splits on this mixed owner were the wrong move for this bucket.

Sources read in order for this pass:

1. `loop/flow.md`
2. `loop/orcestrator.md`
3. `loop/researcher.md`
4. `loop/reviewer.md`
5. `loop/coder.md`
6. `loop/researcher.md` again as active role contract
7. `sprints/current.txt`
8. `loops/ascii-rain-performance-live-loop.txt`
9. `research/2026-06-14-ascii-rain-performance-plan.md`
10. current proof receipts around the mixed post-slice-20 owner, especially `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-22-renderable_append.log:146-148`
11. `reference-index.md`
12. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
13. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
14. `howl-render/src/text/direct_normal.zig:720-802`
15. `howl-render/src/text/direct_scene.zig:37-75`
16. `howl-render/src/text/scene_rects.zig:186-226`
17. `howl-render/src/text/scene_rects.zig:270-304`
18. `howl-render/src/text/scene_rects.zig:372-381`
19. `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:858-881`
20. `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:57-69`

Exact files and line references:

- Current mixed owner receipt: `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-22-renderable_append.log:146-148`.
- Current mixed owner function: `howl-render/src/text/direct_normal.zig:720-802`.
- Mixed inline-rect block inside current owner: `howl-render/src/text/direct_normal.zig:733-743`.
- Current background owner seam: `howl-render/src/text/direct_scene.zig:37-47`, `howl-render/src/text/scene_rects.zig:186-226`.
- Current clear-note owner seam: `howl-render/src/text/direct_scene.zig:64-65`, `howl-render/src/text/scene_rects.zig:270-304`.
- Current decoration owner seam: `howl-render/src/text/direct_scene.zig:68-74`, `howl-render/src/text/scene_rects.zig:372-381`.

Compact anchor map:

- Alacritty streams cells and updates line/decoration state during that same walk: `display/mod.rs:858-881`.
- Alacritty keeps the text renderer on a direct per-cell draw loop: `renderer/text/mod.rs:57-69`.
- Howl currently collapses three different inline rect responsibilities plus sprite/text work into `appendRenderable(...)`: `direct_normal.zig:733-802`.

Style-first interpretation:

- Current cleaned-code proof still shows broad `appendRenderable(...)` as a mixed owner.
- The current function mixes at least four distinct responsibilities:
- inline background work
- inline clear-note work
- inline decoration work
- sprite/text draw path work
- That mixed ownership is visible directly in current source at `direct_normal.zig:733-802`.
- Even when proof can rank subphases, the code shape itself is still style debt under TigerBeetle pressure because one owner is carrying unrelated mutation paths and obscuring what should be optimized next.

- Alacritty pressure supports reducing this mixedness, not preserving it.
- Alacritty streams cells and updates decoration/line state in the content walk, while the text renderer stays a clean direct draw loop.
- That is not a license for a broad rewrite, but it is enough source pressure to justify splitting the current mixed Howl owner into smaller owner-true pieces before more optimization.

- Therefore the next honest move is a style-first cleanup/restructure slice, not another proof-only split and not another optimization slice on the still-mixed owner.

Exact cleanup slice recommendation:

- Slice type: cleanup/restructure, no new optimization target claims.
- Allowed files:
- `howl-render/src/text/direct_normal.zig`
- `howl-render/src/text/direct_scene.zig`
- `howl-render/src/text/scene_rects.zig`

- Exact required shape:
- keep `howl-render/src/text/direct_normal.zig: appendRenderable(...)` as the hot parent control-flow owner and future proof seam
- remove the mixed `appendRenderable(...)` owner structurally so it does not own both inline rect mutation and sprite/text draw mutation in one body
- `appendRenderable(...)` must reduce to one rect-side child call followed by one sprite/text child call with explicit responsibilities at the call site
- add one exact rect-side child owner in `howl-render/src/text/direct_scene.zig`: `appendRenderableRects(...)`
- `appendRenderableRects(...)` owns the moved inline rect side effects only:
- background
- clear-note
- decoration
- `appendRenderableRects(...)` must call the existing rect-side direct-scene owners rather than moving their ownership upward:
- `appendBackground(...)`
- `noteClearColor(...)`
- `appendDecorations(...)`
- keep geometry/mutation leaves in `howl-render/src/text/scene_rects.zig`
- add one exact sprite/text child owner in `howl-render/src/text/direct_normal.zig`: `renderableAppend(...)`
- `renderableAppend(...)` owns the sprite/text path work only:
- blank fast return
- face resolution
- glyph lookup
- key derivation
- atlas reserve
- raster enqueue
- sprite append
- lane report draw increment
- do not keep three sibling rect-side calls in `appendRenderable(...)`; that would leave rect sequencing owned by the mixed hot parent
- do not move the hot proof seam to `scene_rects.zig`; the accountable post-cleanup parent seam remains `direct_normal.appendRenderable(...)`
- keep the parent control flow explicit and small, consistent with TigerBeetle source-order pressure
- preserve current accepted slice-20 behavior exactly
- do not change semantics for damage gating, underline/strikethrough emission, background merge, clear-row tracking, cursor path, or sprite path
- do not reintroduce retained `RenderableCell` publication
- do not claim a new bottleneck in this cleanup slice

- Exact tests:
- from `howl-render`, run `zig build test:abi`
- from `howl-render`, run `zig build test:unit`
- keep these existing direct-normal tests green in `howl-render/src/text/direct_normal.zig`:
- `test "direct normal publication zero codepoint is a fast candidate"`
- `test "direct normal publication keeps unsupported non-printables on generic fallback"`
- keep these existing direct-path behavior tests green in `howl-render/src/text/surface_preparer.zig`:
- `test "text preparation publication ascii stays on direct normal path"`
- `test "text preparation publication styled indexed ascii stays on direct normal path"`
- `test "text preparation publication non inverse indexed ascii stays on direct normal path"`
- `test "text preparation publication zero codepoint stays on direct normal path without sprite draw"`
- `test "text preparation publication styled indexed zero codepoint stays on direct normal path"`
- `test "text preparation publication unsupported space and rgb keep fallback scratch clean"`
- `test "text preparation publication tab stays on generic fallback without partial direct scratch"`
- `test "text preparation publication other control stays on generic fallback without partial direct scratch"`
- keep these existing rect-behavior tests green in `howl-render/src/text/scene.zig`:
- `test "scene emits background draws from non-continuation cells"`
- `test "scene merges adjacent same-color background cells on one row"`
- `test "scene keeps distinct background spans across color changes"`
- `test "scene emits explicit clears for transparent default backgrounds on partial damage"`
- `test "scene cursor draws emit shared cursor geometry"`
- `test "scene build options include cursor draws"`
- `test "scene damage filters clean rows"`
- `test "scene emits shared-geometry decoration draws from cells"`
- `test "scene merges contiguous straight underline spans"`
- `test "scene double underline count and geometry stay aligned"`
- `test "scene dotted underline geometry stays aligned with counted capacity"`
- `test "scene dashed underline geometry stays aligned with counted capacity"`
- `test "scene merges contiguous strikethrough spans"`
- receipt must state explicitly that the same behavior stayed intact for background merge, clear-row tracking, non-curly decoration emission, direct-normal fast-path admission/fallback behavior, and zero-codepoint no-sprite behavior

- Exact non-goals:
- no new optimization yet
- no new proof-only targeting yet
- no ABI changes
- no benchmark harness changes
- no host/runtime changes
- no glyph/atlas/raster behavior changes beyond refactoring for owner split
- no broad renderer architecture rewrite

- Exact stop conditions:
- stop if resolving the mixed owner honestly requires edits outside `howl-render/src/text/direct_normal.zig`, `howl-render/src/text/direct_scene.zig`, and `howl-render/src/text/scene_rects.zig`
- stop if the cleanup would require changing product behavior rather than only owner boundaries and source order
- stop if `direct_normal.appendRenderable(...)` cannot remain the hot parent seam with exactly one rect-side child owner and one sprite/text child owner inside the allowed files
- stop if the split cannot be made owner-true without inventing vague new bucket owners or convenience layers

- Exact receipt fields needed for acceptance:
- orchestrator session id: `orch-2026-06-14-ascii-rain-performance-01`
- researcher session id: `research-2026-06-14-ascii-rain-performance-01`
- reviewer session id: `review-2026-06-14-ascii-rain-performance-01`
- coder session id
- exact changed files and line references
- verification command list and results
- concise cleanup/restructure summary
- explicit note that no benchmark verdict or new optimization claim is part of this slice
- blockers or deviations
- commit-hash receipt status

Owner roles and proposed shape:

- `direct_normal.zig` remains the control-flow owner for the direct-normal scan and append path.
- `direct_normal.appendRenderable(...)` remains the accountable hot parent seam after cleanup.
- `direct_normal.renderableAppend(...)` becomes the sprite/text child owner under that parent seam.
- `direct_scene.zig` becomes the single rect-side child owner entrypoint for this parent seam through `appendRenderableRects(...)`.
- `direct_scene.appendRenderableRects(...)` aggregates only the existing rect-side owners `appendBackground(...)`, `noteClearColor(...)`, and `appendDecorations(...)`.
- `scene_rects.zig` remains the rect geometry/mutation leaf owner.
- The cleanup should sharpen those roles by preventing `appendRenderable(...)` from being a mixed owner bucket.

Risks:

- A cleanup-only slice can still accidentally smuggle in optimization or behavioral change if the owner split is not reviewed harshly.
- If the current helper boundaries in `direct_scene.zig` are themselves too muddy to support an owner-true split, the slice may expose a slightly larger local cleanup need inside the same allowed files.

Proof gaps:

- After the mixed owner is removed, we will need one fresh cleaned-code proof pass at `direct_normal.appendRenderable(...)` before authorizing the next optimization target.
- We do not yet know whether that future cleaned-code winner will be moved inline background, moved inline clear-note, moved inline decoration, or sprite/text path work.

Readiness judgment:

- Ready for one exact style-first cleanup/restructure slice.
- No further proof-only split is authorized for this mixed-owner bucket before the cleanup lands.
- This remains a local render-owner sprint, not a structural blocker.

## Post-Slice-17 Interpretation

Status:

- Slice 17 produced a real total-path win.
- Slice 17 also failed its focused acceptance metric as written.
- The mixed result does not show that retained-list removal was the wrong direction.
- It shows the focused metric became the wrong comparison target after the owner work moved.

Sources read in order for this pass:

1. `loop/flow.md`
2. `loop/orcestrator.md`
3. `loop/researcher.md`
4. `loop/reviewer.md`
5. `loop/coder.md`
6. `loop/researcher.md` again as active role contract
7. `sprints/current.txt`
8. `loops/ascii-rain-performance-live-loop.txt`
9. `research/2026-06-14-ascii-rain-performance-plan.md`
10. slice-17 proof receipts at `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-16-renderable_append.log:65` and `/home/home/.local/share/opencode/tool-output/tool_ec6313575001MnisJb35u39Ym5:66`
11. benchmark receipt `utils/tools/rain-bench/artifacts/stress/20260614-145245-ascii/summary.json`
12. `reference-index.md`
13. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
14. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
15. `howl-render/src/text/direct_normal.zig:51-101`
16. `howl-render/src/text/direct_normal.zig:123-153`
17. `howl-render/src/text/direct_normal.zig:324-427`
18. `howl-render/src/text/direct_normal.zig:677-793`
19. `howl-render/src/text/direct_scene.zig:37-75`
20. `howl-render/src/text/scene_rects.zig:164-204`
21. `howl-render/src/text/scene_rects.zig:248-283`
22. `howl-render/src/text/scene_rects.zig:345-356`
23. `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:49-87`
24. `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:783-879`
25. `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:57-69`

Exact files and line references:

- Pre-slice focused proof receipt: `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-16-renderable_append.log:65`.
- Post-slice focused proof receipt: `/home/home/.local/share/opencode/tool-output/tool_ec6313575001MnisJb35u39Ym5:66`.
- Slice-17 benchmark receipt: `utils/tools/rain-bench/artifacts/stress/20260614-145245-ascii/summary.json:47-80`.
- Current scratch owner after slice 17: `howl-render/src/text/direct_normal.zig:51-101`.
- Current end-of-prepare rect seam after slice 17: `howl-render/src/text/direct_normal.zig:143-152`.
- Current publication fast path after slice 17: `howl-render/src/text/direct_normal.zig:341-358`.
- Current mixed `appendRenderable(...)` owner after slice 17: `howl-render/src/text/direct_normal.zig:677-752`.
- Current inline direct-scene helpers used inside `appendRenderable(...)`: `howl-render/src/text/direct_scene.zig:37-75`.
- Current inline background helper: `howl-render/src/text/scene_rects.zig:164-204`.
- Current inline clear-color tracker: `howl-render/src/text/scene_rects.zig:248-283`.
- Current inline decoration helper: `howl-render/src/text/scene_rects.zig:345-356`.

Compact anchor map:

- Alacritty borrowed renderable-content seam: `display/content.rs:49-87`.
- Alacritty collect-then-draw content path: `display/mod.rs:783-879`.
- Alacritty direct per-cell draw loop: `renderer/text/mod.rs:57-69`.
- Howl current direct-normal scratch owner after slice 17: `direct_normal.zig:51-101`.
- Howl moved inline rect-derivation seam: `direct_normal.zig:677-693`.
- Howl remaining end-of-prepare rect work: `direct_normal.zig:143-152`.

Mixed-result interpretation:

- Slice 17 was directionally right.
- It removed the retained `scratch.renderable` list and collapsed `append_scene_rects_ms` from `172.766 ms` to `0.397 ms`.
- It also dropped total `direct_normal_prepare_ms` from `5948.548 ms` to `3613.184 ms`.
- The benchmark receipt moved in the same direction: Howl improved from the earlier proof-run baseline to `109.64 fps`, `p50 8383 us`, and `p95 13572 us` at `utils/tools/rain-bench/artifacts/stress/20260614-145245-ascii/summary.json:47-80`.
- So the product-path result is plainly better.

- But the slice was judged on normalized `renderable_append` cost, and that specific comparison became invalid when the code moved background merge, clear-color capture, and decoration derivation into the timed `renderable_append` region (`direct_normal.zig:689-693`).
- Before slice 17, `renderable_append_ms` mostly meant retained-list publication.
- After slice 17, `renderable_append_ms` means a different mixed owner: inline background derivation, inline clear-row note, inline decoration derivation, and no longer the old retained-list append.
- Therefore the measured regression from about `21.10 ns/call` to about `25.91 ns/call` is a real receipt, but it is not comparing the same thing across the seam change.

- The right interpretation is option `1`:
- the retained-list removal was directionally right
- but the focused acceptance target was the wrong one after the owner work moved

- This does not authorize accepting slice 17 as-is without more proof.
- It means the next step must be a corrective proof-only pass inside the same local seam so the new mixed `appendRenderable(...)` owner is re-accounted honestly.

Current-code facts:

- The retained `scratch.renderable` list is gone from `Scratch` and from the direct-normal finish path (`direct_normal.zig:51-101`, `143-152`).
- Backgrounds, clear colors, and decorations are now derived inline inside `appendRenderable(...)` before the blank fast return (`direct_normal.zig:689-693`).
- That moved work from the former batch `append_scene_rects` owner into the currently timed `renderable_append` owner.
- The proof receipt therefore mixes different work under the same measurement label before vs after slice 17.

Reference facts:

- Alacritty pressure still favors reducing extra retained per-cell packaging and keeping work close to the draw/content path (`display/content.rs:49-87`, `display/mod.rs:783-879`, `renderer/text/mod.rs:57-69`).
- Slice 17 moved closer to that pressure, not farther away.

Exact next-step recommendation:

- Stay in the same local seam.
- Do not optimize again yet.
- First run one corrective proof-only slice that re-splits the new mixed `appendRenderable(...)` owner on current code.

One exact next slice:

- Slice type: proof only.
- Allowed files:
- `howl-render/src/text/direct_normal.zig`

- Exact required shape:
- keep proof local to `direct_normal.zig` only
- keep `HOWL_APPEND_RENDERABLE_PROOF_MODE=renderable_append` as the outer focused mode
- add temporary narrow inner proof accounting for the new moved work inside `appendRenderable(...)` with exactly these subphases:
- `inline_background_ns`
- `inline_clear_note_ns`
- `inline_decoration_ns`
- keep the existing post-move inner phases:
- `blank_fast_return_ns`
- `resolve_face_ns`
- `lookup_glyph_ns`
- `key_derivation_ns`
- `atlas_reserve_ns`
- `raster_enqueue_ns`
- `sprite_append_ns`
- `lane_report_update_ns`
- do not change behavior
- do not reintroduce any retained full-cell list

- Exact tests:
- from `howl-render`, run `zig build test:abi`
- from `howl-render`, run `zig build test:unit`

- Exact benchmark/proof requirements:
- rerun `HOWL_APPEND_RENDERABLE_PROOF_MODE=renderable_append python3 utils/tools/rain-bench/benchmark_terminals.py --build`
- record one exact fresh proof log path or one clearly separated fresh section
- the proof package must end with one verdict that names which current post-slice-17 `appendRenderable(...)` subphase now dominates
- the proof package must report:
- `append_renderable_ms`
- `append_scene_rects_ms`
- `direct_normal_prepare_ms`
- `append_renderable_calls`
- `fallback_reject_calls`
- the new inline subphase timers listed above

- Exact non-goals:
- no optimization yet
- no ABI changes
- no benchmark harness changes
- no host/runtime changes
- no glyph/atlas/raster changes
- no reintroduction of retained `RenderableCell` publication

- Exact stop conditions:
- stop if re-accounting the new mixed owner requires edits outside `howl-render/src/text/direct_normal.zig`
- stop if the proof cannot isolate whether moved inline rect work or remaining sprite-path work dominates the new `appendRenderable(...)` owner
- stop if `fallback_reject_calls` becomes non-zero

- Exact receipt fields needed for acceptance:
- orchestrator session id: `orch-2026-06-14-ascii-rain-performance-01`
- researcher session id: `research-2026-06-14-ascii-rain-performance-01`
- reviewer session id: `review-2026-06-14-ascii-rain-performance-01`
- coder session id
- exact changed files and line references
- verification command list and results
- benchmark command
- benchmark artifact path
- proof log artifact path
- exact proof location lines
- measured before
- measured after
- verdict on which post-slice-17 `appendRenderable(...)` subphase dominates
- commit-hash receipt status

Risks:

- Because slice 17 moved owner work, the next proof may reveal that the dominant remaining cost is now inline background/decor/clear derivation rather than sprite-path work.
- The benchmark result is excellent, but if the proof shows the remaining mixed owner is still poorly accounted, another optimization would risk fake progress.

Proof gaps:

- We do not yet know whether the post-slice-17 hot owner is dominated by the new inline rect work or by the remaining sprite/text path.
- We do not yet know whether the best follow-up after that proof will be another local direct-normal tightening or a smaller helper reshape between `direct_normal.zig` and `scene_rects.zig`.

Readiness judgment:

- Ready for one corrective local proof-only slice.
- Not ready for another optimization slice yet.
- This remains a local render-owner sprint, not a structural blocker.

## Post-Proof-Slice-16 Interpretation

Status:

- Proof-only slice 16 succeeded.
- The one-at-a-time proof method removed the main slice-15 accountability gap.
- `renderable_append` is now optimization-ready.
- Another proof split is not required before the next optimization slice.

Sources read in order for this pass:

1. `loop/flow.md`
2. `loop/orcestrator.md`
3. `loop/researcher.md`
4. `loop/reviewer.md`
5. `loop/coder.md`
6. `loop/researcher.md` again as active role contract
7. `sprints/current.txt`
8. `loops/ascii-rain-performance-live-loop.txt`
9. `research/2026-06-14-ascii-rain-performance-plan.md`
10. mode-specific proof receipts under `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-16-*.log`
11. matching benchmark artifacts under `utils/tools/rain-bench/artifacts/stress/20260614-142311-ascii` through `20260614-142800-ascii`
12. `reference-index.md`
13. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
14. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
15. `howl-render/src/text/direct_normal.zig:51-80`
16. `howl-render/src/text/direct_normal.zig:133-136`
17. `howl-render/src/text/direct_normal.zig:663-735`
18. `howl-render/src/text/direct_scene.zig:37-68`
19. `howl-render/src/text/scene_rects.zig:123-204`
20. `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:49-87`
21. `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:783-879`
22. `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:57-69`

Exact files and line references:

- Renderable-append proof receipt: `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-16-renderable_append.log:63-66`.
- Blank-fast-return proof receipt: `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-16-blank_fast_return.log:63-66`.
- Resolve-face proof receipt: `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-16-resolve_face.log:63-66`.
- Lookup-glyph proof receipt: `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-16-lookup_glyph.log:63-66`.
- Key-derivation proof receipt: `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-16-key_derivation.log:63-66`.
- Atlas-reserve proof receipt: `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-16-atlas_reserve.log:63-66`.
- Raster-enqueue proof receipt: `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-16-raster_enqueue.log:63-66`.
- Sprite-append proof receipt: `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-16-sprite_append.log:63-66`.
- Lane-report-update proof receipt: `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-16-lane_report_update.log:63-66`.
- Current scratch owner: `howl-render/src/text/direct_normal.zig:51-80`.
- Current direct-scene retained-list seam: `howl-render/src/text/direct_normal.zig:133-136`.
- Current `appendRenderable(...)` hot statement: `howl-render/src/text/direct_normal.zig:671-676`.
- Current blank fast return: `howl-render/src/text/direct_normal.zig:678-684`.
- Current direct-scene retained consumers: `howl-render/src/text/direct_scene.zig:37-68`.
- Current batch rect builders consuming retained cells: `howl-render/src/text/scene_rects.zig:123-204`.
- Slice-16 used multiple benchmark reruns across proof modes; those runs were supportive context only and are not promoted as the primary receipt surface for this interpretation.

Compact anchor map:

- Alacritty borrowed renderable-content seam: `display/content.rs:49-87`.
- Alacritty content collection and direct draw handoff: `display/mod.rs:783-879`.
- Alacritty direct draw-cell loop: `renderer/text/mod.rs:57-69`.
- Howl retained renderable scratch owner: `direct_normal.zig:51-80`.
- Howl current retained renderable append hotspot: `direct_normal.zig:671-676`.
- Howl current retained-list consumers for backgrounds, clears, and decorations: `direct_normal.zig:133-136`, `direct_scene.zig:37-68`, `scene_rects.zig:123-204`.

Proof interpretation:

- The one-at-a-time runs solved the slice-15 proof-method problem.
- The outer `append_renderable_ms` remains larger than any single named subphase in every run, but the named inner timings are now credible enough to rank after normalizing by `append_renderable_calls`.
- At the late stable checkpoints, the normalized ordering is:
- `renderable_append` first
- `blank_fast_return` second and very close, but still smaller per call
- then `lookup_glyph`, `key_derivation`, `atlas_reserve`, `resolve_face`, `sprite_append`, `lane_report_update`, and effectively-zero `raster_enqueue`
- Evidence at the comparable late checkpoints:
- `renderable_append` at `...renderable_append.log:65` is `426.781 ms / 20,225,637 calls`.
- `blank_fast_return` at `...blank_fast_return.log:65` is `499.901 ms / 25,739,900 calls`.
- `lookup_glyph` at `...lookup_glyph.log:65` is `158.421 ms / 25,742,113 calls`.
- `key_derivation` at `...key_derivation.log:65` is `131.128 ms / 25,746,454 calls`.
- `atlas_reserve` at `...atlas_reserve.log:65` is `107.934 ms / 24,690,142 calls`.
- `resolve_face` at `...resolve_face.log:65` is `74.242 ms / 25,748,267 calls`.
- `sprite_append` at `...sprite_append.log:65` is `68.493 ms / 25,773,041 calls`.
- `lane_report_update` at `...lane_report_update.log:65` is `60.634 ms / 25,722,437 calls`.
- `raster_enqueue` at `...raster_enqueue.log:65` is `0.051 ms / 25,754,216 calls`.
- So the next optimization should not target glyph lookup, key derivation, atlas reserve, or lane bookkeeping.
- It should target the retained renderable append itself.

Current-code facts:

- The proved hot statement is now exact: `driver.scratch.renderable.appendAssumeCapacity(renderable);` at `direct_normal.zig:675`.
- That append happens before the blank fast return, so the product pays this retained-cell publication cost even for cells that do not emit a sprite draw (`direct_normal.zig:678-684`).
- The retained list is then consumed later only to synthesize backgrounds, clears, and decorations (`direct_normal.zig:133-136`).
- Those consumers are pure batch passes over `[]const contract.RenderableCell` in `direct_scene.zig` and `scene_rects.zig`.
- This means the proved hotspot is not glyph lookup anymore; it is the cost of retaining a full `RenderableCell` list for downstream scene-rect generation.

Reference facts:

- Alacritty takes renderable terminal content by borrow and then streams cells directly into rendering (`display/content.rs:49-87`, `display/mod.rs:783-879`, `renderer/text/mod.rs:57-69`).
- That does not authorize a redesign on taste, but it does apply pressure against retaining an extra full per-cell owner when the renderer can derive what it needs closer to the scan/draw path.

Decision:

- `renderable_append` is optimization-ready.
- Another proof split is not required.
- The next honest move is an optimization slice that attacks retained renderable publication cost and the downstream need for that retained list.

Exact next-step recommendation:

- Continue locally inside the render owner, but broaden from one function to the direct-normal/direct-scene seam.

One exact next slice:

- Slice type: optimization.
- Allowed files:
- `howl-render/src/text/direct_normal.zig`
- `howl-render/src/text/direct_scene.zig`
- `howl-render/src/text/scene_rects.zig`

- Exact required shape:
- remove or materially reduce the hot per-cell retained `scratch.renderable.appendAssumeCapacity(renderable)` cost on the direct-normal fast path
- do this by moving background/clear/decoration rect derivation closer to the direct-normal owner so the hot path no longer retains a second full `RenderableCell` publication list solely for later batch rect synthesis
- preserve current output semantics for:
- backgrounds
- clears
- decorations
- cursor draws
- sprite draws
- preserve damage semantics and row/column span behavior currently enforced by `scene_rects.zig`
- keep glyph lookup, raster enqueue, and atlas behavior unchanged unless strictly required by the retained-list removal
- keep `fallback_reject_calls == 0` on the ASCII rain proof workload

- Exact tests:
- from `howl-render`, run `zig build test:abi`
- from `howl-render`, run `zig build test:unit`

- Exact benchmark/proof requirements:
- rerun `python3 utils/tools/rain-bench/benchmark_terminals.py --build`
- rerun one focused proof pass with `HOWL_APPEND_RENDERABLE_PROOF_MODE=renderable_append`
- record one exact fresh proof log path or append one clearly separated fresh proof section
- the proof package must report:
- `append_renderable_ms`
- `renderable_append_ms`
- `append_scene_rects_ms`
- total `direct_normal_prepare_ms`
- `append_renderable_calls`
- `fallback_reject_calls`
- acceptance requires a real drop in normalized `renderable_append` cost and no proof-path regression to a new unmeasured owner

- Exact non-goals:
- no ABI changes
- no benchmark harness changes
- no host/runtime changes
- no glyph-lookup optimization
- no atlas/raster optimization
- no fallback/publication policy changes

- Exact stop conditions:
- stop if removing the retained renderable publication cost honestly requires edits outside `howl-render/src/text/direct_normal.zig`, `howl-render/src/text/direct_scene.zig`, and `howl-render/src/text/scene_rects.zig`
- stop if preserving current background/clear/decoration semantics requires reintroducing an equivalent full retained-cell owner elsewhere in the same path
- stop if the optimization changes the proved workload path, for example `fallback_reject_calls` becomes non-zero
- stop if the proof after the optimization merely shifts the same retained publication cost under a new name without reducing normalized per-call work

- Exact receipt fields needed for acceptance:
- orchestrator session id: `orch-2026-06-14-ascii-rain-performance-01`
- researcher session id: `research-2026-06-14-ascii-rain-performance-01`
- reviewer session id: `review-2026-06-14-ascii-rain-performance-01`
- coder session id
- exact changed files and line references
- verification command list and results
- benchmark command
- benchmark artifact path
- proof log artifact path
- exact proof location lines
- measured before
- measured after
- verdict on normalized `renderable_append` cost, `append_renderable_ms`, `append_scene_rects_ms`, and total `direct_normal_prepare_ms`
- commit-hash receipt status

Risks:

- The proved hotspot is a retained-owner cost, so the next slice may be the first one that meaningfully reshapes the direct-normal/direct-scene seam.
- Benchmark FPS remains noisy across the slice-16 reruns, so owner-path proof must stay authoritative over raw FPS movement.
- If batch rect generation implicitly relies on the retained renderable list in more subtle ways than the current files show, the optimization could become larger than this slice allows.

Proof gaps:

- We have proved the hot statement, but we have not yet proved which minimal retained-list-removal shape preserves the current rect semantics best.
- We have not yet measured whether the win comes more from removing the append itself or from avoiding later batch traversal over the same retained list.

Readiness judgment:

- Ready for an optimization slice.
- Not blocked on another proof split.
- This remains a local render-owner sprint, not a product-structure blocker.

## Post-Proof-Slice-15 Interpretation

Status:

- Proof-only slice 15 hit its own stop condition honestly.
- The remaining large unattributed `append_renderable_ms` remainder is not yet a structural product blocker.
- It is a local proof-method blocker inside `howl-render/src/text/direct_normal.zig`.

Sources read in order for this pass:

1. `loop/flow.md`
2. `loop/orcestrator.md`
3. `loop/researcher.md`
4. `loop/reviewer.md`
5. `loop/coder.md`
6. `loop/researcher.md` again as active role contract
7. `sprints/current.txt`
8. `loops/ascii-rain-performance-live-loop.txt`
9. `research/2026-06-14-ascii-rain-performance-plan.md`
10. proof receipts at `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-15.log:63-67`
11. `reference-index.md`
12. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
13. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
14. `howl-render/src/text/direct_normal.zig:621-703`
15. `howl-render/src/text/session.zig:62-115`
16. `howl-render/src/text/raster/atlas.zig:54-66`
17. `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:41-88`
18. `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:783-879`
19. `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:57-69`

Exact files and line references:

- Stop-condition proof receipt: `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-15.log:63`.
- Run receipt lines: `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-15.log:64-67`.
- Current `appendRenderable(...)` owner: `howl-render/src/text/direct_normal.zig:621-703`.
- Current `renderable_append_ns` site: `howl-render/src/text/direct_normal.zig:642-644`.
- Current `blank_fast_return_ns` site: `howl-render/src/text/direct_normal.zig:646-652`.
- Current `resolve_face_ns` site: `howl-render/src/text/direct_normal.zig:654-660`.
- Current `lookup_glyph_ns` site: `howl-render/src/text/direct_normal.zig:662-664`.
- Current `key_derivation_ns` site: `howl-render/src/text/direct_normal.zig:665-668`.
- Current `atlas_reserve_ns` site: `howl-render/src/text/direct_normal.zig:669-671`.
- Current `raster_enqueue_ns` site: `howl-render/src/text/direct_normal.zig:672-682`.
- Current `sprite_append_ns` site: `howl-render/src/text/direct_normal.zig:684-699`.
- Current `lane_report_update_ns` site: `howl-render/src/text/direct_normal.zig:700-702`.

Stop-condition interpretation:

- Slice 15 did exactly what it was supposed to do: it tested whether the remaining `append_renderable_ms` remainder was locally attributable with more timers.
- It failed that test.
- Receipt at line `63` shows:
- `append_renderable_ms=3156.878`
- named measured subphases:
- `renderable_append_ms=479.863`
- `blank_fast_return_ms=467.413`
- `resolve_face_ms=53.200`
- `lookup_glyph_ms=139.733`
- `key_derivation_ms=106.354`
- `atlas_reserve_ms=90.337`
- `raster_enqueue_ms=0.041`
- `sprite_append_ms=54.498`
- `lane_report_update_ms=50.423`
- Those named subphases still account for less than half of `append_renderable_ms`.
- So the stop condition in the slice contract was correctly hit: the proof still leaves a large unattributed remainder inside `append_renderable_ms`.
- Because all of that unattributed time is still inside one current owner function in one file, this is not yet a structural debt wall under the sprint definition.
- It is a sign that stacked always-on per-call timers are now perturbing or obscuring the local truth too much to support another optimization choice.

Current-code facts:

- The unexplained remainder is still trapped inside `appendRenderable(...)` in `direct_normal.zig`.
- No current source evidence pushes the bottleneck across an owner boundary into a different subsystem.
- The current measured subphases are all local statements in the same function, and the gap is therefore more plausibly proof-overhead or unmeasured local work than a broader product wall.

Relevant Alacritty/reference facts:

- Alacritty pressure still favors reducing hot per-cell render work close to draw (`display/content.rs:41-88`, `display/mod.rs:783-879`, `renderer/text/mod.rs:57-69`).
- Nothing in the reference pressure says we need a broader architectural sprint yet.
- The references instead push us to prove the local owner more cleanly before optimizing it again.

Exact next-step recommendation:

- Continue locally, but change the proof method.
- Do not add another all-subphases-at-once timing layer.
- The next honest move is one more proof-only slice in `direct_normal.zig` that measures one `appendRenderable(...)` inner subphase at a time across separate reruns, so timer overhead does not swamp the owner.

One exact next slice:

- Slice type: proof only, no optimization.
- Allowed files:
- `howl-render/src/text/direct_normal.zig`

- Exact required shape:
- Keep proof local to `direct_normal.zig` only.
- Replace the current simultaneous inner-subphase proof with one exact local proof mode selector inside `appendRenderable(...)`.
- The selector must support exactly these modes:
- `renderable_append`
- `blank_fast_return`
- `resolve_face`
- `lookup_glyph`
- `key_derivation`
- `atlas_reserve`
- `raster_enqueue`
- `sprite_append`
- `lane_report_update`
- In any single proof run, time only one selected subphase plus the outer `append_renderable_ns` and keep existing counters.
- Use separate reruns to cover the different modes.
- Do not change behavior.

- Exact tests:
- from `howl-render`, run `zig build test:abi`
- from `howl-render`, run `zig build test:unit`

- Exact benchmark/proof requirements:
- rerun `python3 utils/tools/rain-bench/benchmark_terminals.py --build` once per proof mode actually used
- record one exact proof artifact path per mode, or one exact shared proof log with clearly separated mode sections
- the proof package must end with one comparison table or section that identifies the dominant cleaned-code `appendRenderable(...)` subphase across those one-at-a-time runs

- Exact non-goals:
- no optimization yet
- no instrumentation cleanup yet
- no edits outside `howl-render/src/text/direct_normal.zig`
- no ABI changes
- no benchmark harness changes

- Exact stop conditions:
- stop if one-at-a-time local proof still cannot reduce the unattributed `append_renderable_ms` remainder enough to name one dominant subphase
- stop if proving the remaining cost requires edits outside `howl-render/src/text/direct_normal.zig`
- stop if the workload path changes, for example `fallback_reject_calls` becomes non-zero during the proof runs

- Exact receipt fields needed for acceptance:
- orchestrator session id: `orch-2026-06-14-ascii-rain-performance-01`
- researcher session id: `research-2026-06-14-ascii-rain-performance-01`
- reviewer session id: `review-2026-06-14-ascii-rain-performance-01`
- coder session id
- exact changed files and line references
- verification command list and results
- benchmark command(s)
- benchmark artifact path(s)
- proof artifact path(s)
- exact proof location lines
- measured before
- measured after
- dominant cleaned-code `appendRenderable(...)` subphase verdict
- commit-hash receipt status

Risks:

- The next proof slice may reveal that timer overhead itself dominates any single very small inner operation.
- Multiple reruns increase benchmark-noise pressure, so the acceptance decision must stay proof-first.

Proof gaps:

- We still do not have one fully trusted, low-overhead attribution of cleaned-code `append_renderable_ms`.
- We still do not know whether the eventual next optimization will target local append storage, lookup, atlas reserve, or control-flow overhead.

Readiness judgment:

- Ready for one more local proof-only slice with a different proof method.
- Not ready for another optimization slice yet.
- This remains a local runtime-proof-first sprint, not a structural blocker.

Sources read in order for this pass:

1. `loop/flow.md`
2. `loop/orcestrator.md`
3. `loop/researcher.md`
4. `loop/reviewer.md`
5. `loop/coder.md`
6. `loop/researcher.md` again as active role contract
7. `sprints/current.txt`
8. `loops/ascii-rain-performance-live-loop.txt`
9. `research/2026-06-14-ascii-rain-performance-plan.md`
10. proof receipts at `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log:2854-2857`
11. `reference-index.md`
12. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
13. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
14. `howl-render/src/text/direct_normal.zig:621-688`
15. `howl-render/src/text/session.zig:62-115`
16. `howl-render/src/text/raster/atlas.zig:54-66`
17. `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:41-88`
18. `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:783-879`
19. `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:57-69`

Exact files and line references:

- Proof receipts: `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log:2854-2857`.
- Current `appendRenderable(...)` owner: `howl-render/src/text/direct_normal.zig:621-688`.
- Current `renderable.appendAssumeCapacity(...)` measurement site: `howl-render/src/text/direct_normal.zig:636-638`.
- Current face-resolution measurement site: `howl-render/src/text/direct_normal.zig:645-651`.
- Current glyph-lookup measurement site: `howl-render/src/text/direct_normal.zig:653-655`.
- Current atlas-reserve measurement site: `howl-render/src/text/direct_normal.zig:658-660`.
- Current raster-enqueue measurement site: `howl-render/src/text/direct_normal.zig:661-670`.
- Current sprite-append measurement site: `howl-render/src/text/direct_normal.zig:673-688`.

Proof interpretation:

- Slice-14 isolates more of `append_renderable(...)`, but not enough to authorize a `lookup_glyph` optimization.
- Proof receipt at `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log:2856` shows:
- `append_renderable_ms=1215.841`
- `renderable_append_ms=523.616`
- `lookup_glyph_ms=151.550`
- `atlas_reserve_ms=113.369`
- `resolve_face_ms=70.429`
- `sprite_append_ms=70.825`
- `raster_enqueue_ms=0.047`
- The largest named measured inner subphase is `renderable_append`, not `lookup_glyph`.
- Also, the named measured subphases still sum to far less than total `append_renderable_ms`, so a large portion of `append_renderable(...)` remains unattributed by the current proof.
- Therefore `lookup_glyph` is not the next honest optimization target yet.

Current-code facts for `append_renderable`:

- `appendRenderable(...)` still mixes several costs in one owner (`direct_normal.zig:621-688`):
- append to `scratch.renderable`
- blank-cell early return branch
- face resolution
- glyph lookup
- glyph-key/span math between lookup and atlas reserve
- atlas reserve
- raster enqueue when pending
- sprite placement math and append
- direct-normal draw counter update
- Slice-14 added `renderable_append_ns` and `raster_enqueue_ns`, but there is still unattributed work between these existing probes, especially around branch/control, key/span derivation, and placement/counter overhead.

Relevant Alacritty/reference facts:

- Alacritty still streams borrowed renderable cells directly to text drawing (`display/content.rs:41-88`, `display/mod.rs:783-879`, `renderer/text/mod.rs:57-69`).
- The relevant reference pressure is still to reduce per-cell append work on the hot path, but not by guessing whether the real remaining cost is lookup, append, or unmeasured local arithmetic/branch work.

Exact next-step recommendation:

- Continue locally.
- One more proof split is required before any `append_renderable(...)` optimization is honest.

One exact next slice:

- Slice type: proof only, no optimization.
- Allowed files:
- `howl-render/src/text/direct_normal.zig`

- Exact required shape:
- Keep the proof local to `direct_normal.zig` only.
- Extend the current `appendRenderable(...)` proof to account for the remaining unattributed work explicitly by adding:
- `blank_fast_return_ns`
- `key_derivation_ns`
- `lane_report_update_ns`
- Keep existing measured fields:
- `renderable_append_ns`
- `resolve_face_ns`
- `lookup_glyph_ns`
- `atlas_reserve_ns`
- `raster_enqueue_ns`
- `sprite_append_ns`
- Keep existing counters:
- `append_renderable_calls`
- `raster_req_count_total`
- `visible_cells_scanned`
- `included_normal_cells`
- `direct_success_calls`
- `fallback_reject_calls`
- Do not change behavior.

- Exact tests:
- from `howl-render`, run `zig build test:abi`
- from `howl-render`, run `zig build test:unit`

- Exact benchmark/proof requirements:
- rerun `python3 utils/tools/rain-bench/benchmark_terminals.py --build`
- append one fresh proof section to `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log` or write one exact new proof log path and record it
- the proof output must identify which of these dominates current cleaned-code `append_renderable` work on ASCII rain:
- `renderable_append`
- `blank_fast_return`
- `resolve_face`
- `lookup_glyph`
- `key_derivation`
- `atlas_reserve`
- `raster_enqueue`
- `sprite_append`
- `lane_report_update`

- Exact non-goals:
- no optimization yet
- no instrumentation cleanup yet
- no edits outside `howl-render/src/text/direct_normal.zig`
- no ABI changes
- no benchmark harness changes

- Exact stop conditions:
- stop if splitting cleaned-code `append_renderable` requires edits outside `howl-render/src/text/direct_normal.zig`
- stop if the new proof still leaves a large unattributed remainder inside `append_renderable_ms`
- stop if the new proof fails to isolate one dominant cleaned-code `append_renderable` subphase

- Exact receipt fields needed for acceptance:
- orchestrator session id: `orch-2026-06-14-ascii-rain-performance-01`
- researcher session id: `research-2026-06-14-ascii-rain-performance-01`
- reviewer session id: `review-2026-06-14-ascii-rain-performance-01`
- coder session id
- exact changed files and line references
- verification command list and results
- benchmark command
- benchmark artifact path
- proof log artifact path
- exact proof location lines
- measured before
- measured after
- dominant cleaned-code `append_renderable` subphase verdict
- commit-hash receipt status

Risks:

- The next proof slice may show that the hot cost is spread across several small local operations rather than one sharp inner owner.
- Benchmark variance remains noisy and must not outrank proof-path movement in acceptance.

Proof gaps:

- We still do not have a fully attributed breakdown of cleaned-code `append_renderable_ms`.
- We still do not know whether the best next optimization after that split will be local append storage, glyph lookup, atlas reserve, or branch/control work.

Readiness judgment:

- Ready for one more local proof-only slice.
- Not ready for a `lookup_glyph` optimization slice yet.
- This remains a local runtime-proof-first sprint, not a structural blocker.

## Post-Proof-Slice-13 Interpretation

Status:

- Proof-only slice 13 completed.
- The cleaned-code direct-normal bottleneck remains inside `append_renderable(...)`.
- `lookup_glyph` is the largest named measured inner subphase, but it is not yet optimization-ready because most of `append_renderable_ms` is still unattributed.

Sources read in order for this pass:

1. `loop/flow.md`
2. `loop/orcestrator.md`
3. `loop/researcher.md`
4. `loop/reviewer.md`
5. `loop/coder.md`
6. `loop/researcher.md` again as active role contract
7. `sprints/current.txt`
8. `loops/ascii-rain-performance-live-loop.txt`
9. `research/2026-06-14-ascii-rain-performance-plan.md`
10. proof receipts at `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log:2854-2857`
11. `reference-index.md`
12. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
13. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
14. `howl-render/src/text/direct_normal.zig:621-682`
15. `howl-render/src/text/session.zig:62-115`
16. `howl-render/src/text/raster/atlas.zig:54-66`
17. `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:41-88`
18. `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:783-879`
19. `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:57-69`

Exact files and line references:

- Proof receipts: `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log:2854-2857`.
- Current `appendRenderable(...)` owner: `howl-render/src/text/direct_normal.zig:621-682`.
- Current face resolution owner callsite: `howl-render/src/text/direct_normal.zig:639-645`, with face-selection logic in `howl-render/src/text/session.zig:62-115`.
- Current glyph lookup callsite: `howl-render/src/text/direct_normal.zig:647-649`.
- Current atlas reserve callsite: `howl-render/src/text/direct_normal.zig:652-654`, with owner logic in `howl-render/src/text/raster/atlas.zig:54-66`.
- Current sprite append callsite: `howl-render/src/text/direct_normal.zig:665-680`.

Proof interpretation:

- Slice-13 proves that `append_renderable(...)` remains the largest cleaned-code inner owner on the direct-normal fast path.
- Proof receipt lines:
- `append_renderable_ms=1215.841` (`surface.log:2856`).
- Named inner subphases:
- `resolve_face_ms=70.429`
- `lookup_glyph_ms=151.550`
- `atlas_reserve_ms=113.369`
- `sprite_append_ms=70.825`
- `append_visible_ms=4845.621`
- `source_candidate_ms=0.000`
- The largest named measured inner subphase is `lookup_glyph_ms`.
- But the named measured inner subphases sum to only about `406 ms`, leaving about `810 ms` of `append_renderable_ms` unattributed.
- Therefore the proof is not yet honest enough to authorize a `lookup_glyph` optimization, because most of the measured `append_renderable(...)` time still sits in unseparated work.

Current-code facts for `append_renderable`:

- `appendRenderable(...)` currently mixes at least these distinct costs in one owner (`direct_normal.zig:621-682`):
- renderable append into scratch (`624`)
- early blank/zero return path (`625-628`)
- face resolution (`639-645`)
- glyph lookup (`647-649`)
- atlas reserve (`652-654`)
- raster-request enqueue when pending (`655-663`)
- sprite draw placement and append (`665-680`)
- lane counter update (`681`)
- The current proof names only face resolution, lookup, atlas reserve, and sprite append.
- It does not separately measure renderable append storage cost or raster-request enqueue cost, so the majority of `append_renderable_ms` is still opaque.

Relevant Alacritty/reference facts:

- Alacritty still streams borrowed renderable cells directly into text drawing (`display/content.rs:41-88`, `display/mod.rs:783-879`, `renderer/text/mod.rs:57-69`).
- The strongest reference pressure here is still to reduce per-cell hot-path render append work, but not by guessing whether the real cost is lookup, cache reserve, or local append/enqueue overhead.

Exact next-step recommendation:

- Continue locally.
- One more proof split is required before any `append_renderable(...)` optimization would be honest.

One exact next slice:

- Slice type: proof only, no optimization.
- Allowed files:
- `howl-render/src/text/direct_normal.zig`

- Exact required shape:
- Keep the proof local to `direct_normal.zig` only.
- Extend the current `append_renderable(...)` proof split to measure the missing unattributed work explicitly:
- `renderable_append_ns`
- `raster_enqueue_ns`
- keep existing measured fields:
- `resolve_face_ns`
- `lookup_glyph_ns`
- `atlas_reserve_ns`
- `sprite_append_ns`
- keep existing counters:
- `append_renderable_calls`
- `raster_req_count_total`
- `visible_cells_scanned`
- `included_normal_cells`
- `direct_success_calls`
- `fallback_reject_calls`
- Do not change behavior.

- Exact tests:
- from `howl-render`, run `zig build test:abi`
- from `howl-render`, run `zig build test:unit`

- Exact benchmark/proof requirements:
- rerun `python3 utils/tools/rain-bench/benchmark_terminals.py --build`
- append one fresh proof section to `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log` or write one exact new proof log path and record it
- the proof output must identify which of these dominates current cleaned-code `append_renderable` work on ASCII rain:
- `renderable_append`
- `resolve_face`
- `lookup_glyph`
- `atlas_reserve`
- `raster_enqueue`
- `sprite_append`

- Exact non-goals:
- no optimization yet
- no instrumentation cleanup yet
- no edits outside `howl-render/src/text/direct_normal.zig`
- no ABI changes
- no benchmark harness changes

- Exact stop conditions:
- stop if splitting cleaned-code `append_renderable` requires edits outside `howl-render/src/text/direct_normal.zig`
- stop if the new proof still leaves a large unattributed majority inside `append_renderable_ms`
- stop if the new proof fails to isolate one dominant `append_renderable` subphase

- Exact receipt fields needed for acceptance:
- orchestrator session id: `orch-2026-06-14-ascii-rain-performance-01`
- researcher session id: `research-2026-06-14-ascii-rain-performance-01`
- reviewer session id: `review-2026-06-14-ascii-rain-performance-01`
- coder session id
- exact changed files and line references
- verification command list and results
- benchmark command
- benchmark artifact path
- proof log artifact path
- exact proof location lines
- measured before
- measured after
- dominant cleaned-code `append_renderable` subphase verdict
- commit-hash receipt status

Risks:

- The next proof slice may show that `append_renderable(...)` is dominated by local append/enqueue overhead rather than lookup or atlas, changing the intuitive next optimization target.
- Benchmark variance remains noisy and must not outrank owner-path proof.

Proof gaps:

- We do not yet know whether cleaned-code `append_renderable(...)` is mostly lookup, atlas reserve, local append, or raster enqueue work.
- We do not yet have a fully attributed breakdown of `append_renderable_ms`.

Readiness judgment:

- Ready for one more local proof-only slice.
- Not ready for another optimization slice yet.
- This remains a local runtime-proof-first sprint, not a structural blocker.

Sources read in order:

1. `loop/flow.md`
2. `loop/orcestrator.md`
3. `loop/researcher.md`
4. `loop/reviewer.md`
5. `loop/coder.md`
6. `loop/researcher.md` again as active role contract
7. `sprints/current.txt`
8. `loops/ascii-rain-performance-live-loop.txt`
9. `research/2026-06-14-ascii-rain-performance-plan.md`
10. reviewer rejection recorded in `loops/ascii-rain-performance-live-loop.txt:125-128`
11. `reference-index.md`
12. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
13. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
14. `howl-linux-host/src/terminal/surface.zig:568-670`
15. `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log:1-74`
16. `utils/tools/rain-bench/artifacts/stress/20260614-034739-ascii/summary.json:45-121`
17. `utils/tools/rain-bench/artifacts/stress/20260614-035834-ascii/summary.json:45-121`
18. `howl-linux-host/src/terminal/render_retained.zig:148-255`
19. `howl-linux-host/src/terminal/vt_surface.zig:46-184`
20. `howl-linux-host/src/terminal/term.zig:35-100`
21. `howl-render/src/c/prepare_request.zig:7-31`
22. `howl-render/src/vt_publication/publication.zig:18-145`
23. `howl-render/src/vt_publication/source_slot.zig:6-233`
24. `howl-render/src/vt_publication/source_slot.zig:259-437`
25. `howl-render/src/vt_publication/prepare_queue.zig:37-214`
26. `howl-render/src/vt_publication/prepare_queue.zig:216-330`
27. `howl-render/src/vt_publication/damage.zig:25-106`
28. `howl-render/src/render_session.zig:1-140`
29. `howl-render/src/render_session.zig:162-205`
30. `howl-render/src/render_session.zig:461-559`
31. `howl-render/src/render_session.zig:727-781`
32. `howl-render/src/tokens.zig:21-50`
33. `howl-render/src/text/surface_preparer.zig:123-143`
34. `howl-render/src/text/direct_normal.zig:101-130`
35. `howl-render/src/text/direct_normal.zig:229-254`
36. `howl-render/src/text/shape/cluster.zig:307-357`
37. `howl-render/src/text/shape/cluster.zig:484-596`
38. `howl-render/src/text/scene_damage.zig:55-119`
39. `howl-render/src/vt_publication/text_input.zig:198-235`
40. `howl-render/src/surface/handle.zig:20-38`
41. `howl-render/src/surface/handle.zig:128-138`
42. `howl-render/src/surface/emitter.zig:120-152`
43. `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:24-185`
44. `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:775-879`
45. `utils/dev_references/terminals/alacritty/alacritty/src/display/damage.rs:16-103`
46. `utils/dev_references/terminals/alacritty/alacritty/src/renderer/mod.rs:177-191`
47. `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:57-69`
48. `utils/dev_references/terminals/alacritty/alacritty_terminal/src/term/mod.rs:137-214`
49. `utils/dev_references/terminals/alacritty/alacritty_terminal/src/term/mod.rs:458-490`
50. `howl-render/src/c/prepare_request_test.zig:1-45`
51. `howl-render/src/c/test_support.zig:82-110`
52. `howl-render/src/test_abi.zig:4-10`
53. `howl-render/src/test_unit.zig:1-12`

Exact files and line references:

- Hot proof seam: `howl-linux-host/src/terminal/surface.zig:575-603`.
- Hot host/render wrapper: `howl-linux-host/src/terminal/render_retained.zig:148-174`.
- VT visible capture owner: `howl-linux-host/src/terminal/vt_surface.zig:56-184`.
- Host scratch storage: `howl-linux-host/src/terminal/term.zig:41-100`.
- Render C prepare entrypoint: `howl-render/src/c/prepare_request.zig:7-16`.
- Full publication heap-copy owner: `howl-render/src/vt_publication/publication.zig:106-145`.
- Retained slot owner and single-slot storage truth: `howl-render/src/vt_publication/source_slot.zig:13-65`, `68-88`, `90-129`, `184-232`.
- Existing source-slot owner tests: `howl-render/src/vt_publication/source_slot.zig:259-437`.
- Prepare queue admission and clone owner: `howl-render/src/vt_publication/prepare_queue.zig:37-77`, `208-214`.
- Prepare queue damage classification owner: `howl-render/src/vt_publication/prepare_queue.zig:37-99`, `147-150`, `167-195`.
- Existing prepare-queue owner tests: `howl-render/src/vt_publication/prepare_queue.zig:216-330`.
- Dirty metadata classification: `howl-render/src/vt_publication/damage.zig:25-40`, `86-106`.
- Text-session source-slot / prepare-queue aggregation owner: `howl-render/src/render_session.zig:384-385`, `522-529`, `533-542`, `545-559`.
- Text-session prepare owner: `howl-render/src/render_session.zig:162-205`, `461-479`, `545-559`.
- Publication fast path: `howl-render/src/text/surface_preparer.zig:123-143`, `howl-render/src/text/direct_normal.zig:101-130`, `229-254`.
- Residual full-scan sparse path: `howl-render/src/text/shape/cluster.zig:307-357`, `484-596`.
- Damage normalization owner: `howl-render/src/text/scene_damage.zig:55-119`.
- Borrowed partial-map helper: `howl-render/src/vt_publication/text_input.zig:198-235`.
- Prepared-handle eager emission owner: `howl-render/src/surface/handle.zig:20-38`, `128-138`.
- Render-surface full-damage emission: `howl-render/src/surface/emitter.zig:143-152`, `211-243`.
- Alacritty terminal damage owner: `utils/dev_references/terminals/alacritty/alacritty_terminal/src/term/mod.rs:137-214`, `458-490`.
- Alacritty renderable-content borrow/iterator owner: `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:27-50`, `153-185`, `208-299`.
- Alacritty draw spine: `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:783-879`.
- Alacritty compositor-damage owner: `utils/dev_references/terminals/alacritty/alacritty/src/display/damage.rs:16-103`.
- Alacritty renderer streaming owner: `utils/dev_references/terminals/alacritty/alacritty/src/renderer/mod.rs:177-191`, `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:57-69`.

Current-code hotspot facts:

- The measured hotspot is real and local: `surface.zig:577-599` times capture, prepare, and submit separately around one render turn, and the proof log shows `prepare_ms` dominating both `capture_ms` and `submit_ms` across the run.
- The proof log ends at `prepare_calls=2368` with cumulative `capture_ms=258.969`, `prepare_ms=2054.274`, and `submit_ms=1038.582` (`/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log:1-74`). Prepare is about 7.9x capture and about 2.0x submit on the proved path.
- The benchmark gap remains extreme even in the proof run: Howl `181.02 fps`, `p50 5038 us`, `p95 7512 us` versus Alacritty `1012.43 fps`, `p50 962 us`, `p95 1218 us` (`utils/tools/rain-bench/artifacts/stress/20260614-035834-ascii/summary.json:45-121`).
- The host already performs one full visible-surface copy before prepare: `vt_surface.captureVisibleLockedWith` copies VT cells plus dirty metadata into host scratch arrays via `howl_vt_terminal_copy_surface` (`howl-linux-host/src/terminal/vt_surface.zig:56-71`, `147-183`).
- The render prepare entrypoint immediately performs a second full ownership copy plus fresh allocations: `takePrepareRequest` calls `ownedSourceFromSurfaceResult(...)` (`howl-render/src/c/prepare_request.zig:7-16`), and that helper allocates and duplicates the full cell slice and all dirty arrays (`howl-render/src/vt_publication/publication.zig:106-145`).
- `PrepareRequests.admitSource` does not currently preserve retained source ownership. It calls `takeOwnedActiveSource(...)`, which clones any retained source back into heap-owned arrays and clears `retained_storage` (`howl-render/src/vt_publication/prepare_queue.zig:37-77`, `208-214`).
- The queue clone means the prior plan was false-small. Any honest retained-ingress optimization must include `prepare_queue.zig`, not just `c/prepare_request.zig` and `source_slot.zig`.
- `SourceSlot` currently has one retained storage owner, `retained_slot`, and every retained publication source view is just a projection over those arrays (`howl-render/src/vt_publication/source_slot.zig:13-65`, `184-203`).
- `copyPublishedSource(...)` always writes the next visible surface into that same retained slot via `@memcpy` (`howl-render/src/vt_publication/source_slot.zig:90-129`).
- `PrepareRequests.classify(...)` needs a stable prior source when deciding dedupe, full/partial classification, cursor/color presentation changes, and geometry/scroll truth (`howl-render/src/vt_publication/prepare_queue.zig:167-195`).
- Therefore, if queue ownership were changed from heap-owned to retained without another lifecycle/storage change, the next `copyPublishedSource(...)` call would overwrite the prior active source before `classify(...)` reads it. Current code proves that a single retained slot is insufficient for retained active-queue ownership.
- `refreshRetainedSlotViews(...)` only repairs pointers after slot-capacity refresh when an already-retained active source exists (`howl-render/src/vt_publication/prepare_queue.zig:147-150`, `howl-render/src/vt_publication/source_slot.zig:206-232`). It does not provide separate prior/current retained storage.
- The exact owner debt is now explicit: the current code needs two retained publication lifetimes, not one. One retained slot must hold the newly copied staged publication, and a second retained slot must hold the stable active/prior publication that `PrepareRequests.classify(...)` compares against.
- For ASCII rain, the dirty metadata classifies as `.full` whenever every row is dirty across full width (`howl-render/src/vt_publication/damage.zig:86-106`). On a 320x120 rain workload with full-frame flushes, the current retained partial-damage machinery does not buy the first-order win.
- The deeper shaped-text owners were already re-proved cold for this workload by the existing instrumentation receipts in `support.zig` and `cluster.zig`, so the first fix should not start in shaping.
- The text prepare owner already has a direct publication fast path for all-normal cells (`howl-render/src/text/surface_preparer.zig:123-143`, `howl-render/src/text/direct_normal.zig:101-130`, `229-254`). The hotspot therefore reaches prepare even when it avoids complex shaping.
- The prepared handle eagerly emits a render surface at create time (`howl-render/src/surface/handle.zig:20-38`, `128-138`), and the emitter always appends full damage before commands (`howl-render/src/surface/emitter.zig:143-152`, `211-243`). That is real work, but the first avoidable debt visible from current source is the extra publication ownership copy and allocation in front of it.

Reference facts:

- Alacritty borrows terminal render content instead of cloning the visible grid into a second owner before draw: `RenderableContent::new` stores `terminal_content = term.renderable_content()` and then iterates it directly (`utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:41-88`, `153-185`).
- Alacritty’s draw spine drains borrowed renderable cells and immediately streams them into the renderer (`utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:783-879`).
- Alacritty’s text renderer consumes an iterator and draws cells directly inside the renderer API loop (`utils/dev_references/terminals/alacritty/alacritty/src/renderer/mod.rs:177-191`, `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:57-69`).
- Alacritty keeps damage as terminal-owned metadata and display/compositor policy, not as a second full-surface ownership hop before every draw (`utils/dev_references/terminals/alacritty/alacritty_terminal/src/term/mod.rs:458-490`, `utils/dev_references/terminals/alacritty/alacritty/src/display/damage.rs:16-103`).
- The matching reference lesson is not "invent a new profiler-driven renderer architecture". The lesson is "do not allocate and duplicate the full visible surface on the hot draw path when an owner-true borrowed or retained handoff already exists."

Compact anchor map:

- Howl host hot turn: `howl-linux-host/src/terminal/surface.zig:575-603`.
- Howl extra copy boundary: `howl-render/src/c/prepare_request.zig:7-16` -> `howl-render/src/vt_publication/publication.zig:106-145`.
- Howl single retained slot seam: `howl-render/src/vt_publication/source_slot.zig:13-65`, `90-129`, `184-232`.
- Howl queue clone seam: `howl-render/src/vt_publication/prepare_queue.zig:37-77`, `208-214`.
- Howl prior-source classification seam: `howl-render/src/vt_publication/prepare_queue.zig:167-195`.
- Howl direct-normal publication fast path: `howl-render/src/text/surface_preparer.zig:123-143` and `howl-render/src/text/direct_normal.zig:229-254`.
- Alacritty borrowed render-content seam: `alacritty/src/display/content.rs:41-88`, `153-185`.
- Alacritty draw spine: `alacritty/src/display/mod.rs:783-879`.
- Alacritty terminal damage seam: `alacritty_terminal/src/term/mod.rs:458-490`.

Owner roles and proposed fix shape:

- `howl-linux-host/src/terminal/vt_surface.zig` owns the first VT-visible copy into host scratch. That copy is currently unavoidable at the host/ABI seam for this sprint slice.
- `howl-render/src/c/prepare_request.zig` owns the render ABI translation from visible VT surface into render-session prepare input. This owner is currently doing avoidable extra work by forcing `ownedSourceFromSurfaceResult` heap duplication.
- `howl-render/src/vt_publication/source_slot.zig` owns retained publication storage, but today it owns only one retained slot. That owner seam is insufficient on its own for stable prior/current queue comparisons.
- `howl-render/src/vt_publication/prepare_queue.zig` owns admitted-source lifecycle and prior/current classification truth. Because it currently clones retained sources, this file is part of the real hot-path owner seam.
- Proposed fix shape: `SourceSlot` must own two retained storage owners, `staged_slot` and `active_slot`. `PrepareRequests` must keep `active_source` pointed at `active_slot`, while incoming visible surfaces are copied into `staged_slot`. Admission rotates staged -> active only after classification. No other retained lifetime design is authorized for iteration 1.
- Honest minimum scope is no longer "ingress only". Honest minimum scope is the queue/source-slot seam.

Exact retained-lifecycle design:

- Current staged retained publication:
- Owner: `howl-render/src/vt_publication/source_slot.zig`.
- Exact storage: a new retained storage field alongside the current one, named for staged/current ingress ownership.
- Exact use: `copyPublishedSource(...)` writes every new visible VT surface into `staged_slot` only.
- Stable prior retained publication used by `PrepareRequests.classify(...)`:
- Owner: `howl-render/src/vt_publication/source_slot.zig`.
- Exact storage: a second retained storage field, named for active/prior queue ownership.
- Exact use: `PrepareRequests.active_source` must point at `active_slot` whenever it is retained-backed.
- Exact handoff/rotation point:
- In `howl-render/src/vt_publication/prepare_queue.zig:37-77`, `classify(...)` must read the incoming source from `staged_slot` and the prior source from `active_slot`.
- Only after `damage_kind != .none` is decided, `admitSource(...)` must ask `SourceSlot` to copy the staged publication into `active_slot`, retarget the admitted `PublicationSource` slices to `active_slot`, and then replace `self.active_source`.
- Rotation must happen before `self.active_source` is overwritten and after classification completes.
- Exact deinit/drop rules:
- `staged_slot` memory is owned only by `SourceSlot`; it is overwritten by the next `copyPublishedSource(...)`, resized by `syncReservedSlotCapacity(...)`, and freed only by `SourceSlot.deinit()`.
- `active_slot` memory is owned only by `SourceSlot`; it is overwritten only by the staged->active promotion step after an admitted source, resized by `syncReservedSlotCapacity(...)`, and freed only by `SourceSlot.deinit()`.
- A retained-backed `PublicationSource.deinit(...)` remains a no-op for slot storage; dropping duplicate/rejected staged sources must not free either retained slot.
- `PrepareRequests.dropActive()` may drop the `PublicationSource` wrapper state, but must not free `active_slot` storage when the source is retained-backed.

Sprint scratchpad for iteration 1:

- Goal: remove the extra full-surface heap duplication in render prepare ingress and queue admission while preserving current prepare token, dedupe, damage classification, and retained-surface validation behavior.
- Expected mechanism: route prepare-request ingress through `SourceSlot` retained storage and keep the queue-admitted active source retained without letting the next ingress overwrite prior-source truth.
- Expected win class: lower per-frame CPU and allocator pressure in the already-proved prepare hotspot; no ABI change; no shaping redesign.
- Proof target after implementation: ASCII rain benchmark plus fresh local hotspot proof must show lower `prepare_ms` share at the same `surface.zig:587` seam.

Explicit next fix slice:

- Exact allowed files:
- `howl-render/src/c/prepare_request.zig`
- `howl-render/src/render_session.zig`
- `howl-render/src/vt_publication/source_slot.zig`
- `howl-render/src/vt_publication/prepare_queue.zig`
- `howl-render/src/c/prepare_request_test.zig`
- `howl-render/src/render_session.zig` owner-local tests
- `howl-render/src/vt_publication/source_slot.zig` owner-local tests
- `howl-render/src/vt_publication/prepare_queue.zig` owner-local tests

- Exact required shape:
- Replace the `ownedSourceFromSurfaceResult` prepare ingress in `howl-render/src/c/prepare_request.zig:12-13` with `SourceSlot.copyPublishedSource(...)` so visible-source ingress lands in `staged_slot`.
- Change `SourceSlot` to own exactly two retained slots: `staged_slot` and `active_slot`.
- Add one exact `SourceSlot` promotion operation that copies the current staged publication into `active_slot` and retargets one `PublicationSource` wrapper to `active_slot`.
- Change `PrepareRequests.admitSource(...)` to accept `slot_owner: *publication_storage.SourceSlot` and use that exact promotion operation after classification and before replacing `self.active_source`.
- Delete the retained-to-owned clone path in `takeOwnedActiveSource(...)`; retained sources must remain retained-backed under the two-slot design.
- Keep `render_session.zig` as the owner that wires geometry refresh into both source-slot and prepare-queue retained views (`howl-render/src/render_session.zig:522-529`).
- Keep all current C ABI entrypoints and structs unchanged.
- Reuse existing retained slot storage; do not add a new manager/runtime/helper owner.
- No alternate retained lifetime design is allowed. The coder must implement the two-slot staged/active design exactly.

- Exact tests and benchmark reruns:
- Run render ABI tests covering prepare ingress: `zig build test-abi`.
- Run render unit tests covering retained/source owners: `zig build test-unit`.
- Keep existing source-slot owner tests green:
- `howl-render/src/vt_publication/source_slot.zig`: `test "source slot copy in preserves snapshot and dirty metadata"`
- `howl-render/src/vt_publication/source_slot.zig`: `test "source slot refresh preserves snapshot and dirty metadata"`
- Keep existing queue owner tests green:
- `howl-render/src/vt_publication/prepare_queue.zig`: `test "prepare requests ignore duplicate admitted source"`
- `howl-render/src/vt_publication/prepare_queue.zig`: `test "prepare requests admit full retained-safe source when geometry changes"`
- `howl-render/src/vt_publication/prepare_queue.zig`: `test "prepare requests force full when partial source has stale submitted base"`
- Add exact queue/source-slot ownership tests:
- Exact retained prior/current seam proof owner: `howl-render/src/vt_publication/source_slot.zig`.
- `howl-render/src/vt_publication/source_slot.zig`: add one exact owner-local test proving the two-slot seam, with this shape:
- stage publication A into `staged_slot`
- promote A into `active_slot`
- stage publication B into `staged_slot`
- prove `active_slot` still contains publication A while `staged_slot` now contains publication B
- prove the two retained publications do not alias the same cell/dirty buffers
- `howl-render/src/vt_publication/prepare_queue.zig`: add a test proving retained admission stays retained after `admitSource(slot_owner, ...)` by checking `requests.active_source.?.retained_storage` and `active_slot`-backed pointers after admission.
- `howl-render/src/vt_publication/prepare_queue.zig`: add a test proving the second retained admission classifies against stable prior contents by staging A, admitting A, staging B, and verifying duplicate/full/partial classification before rotation overwrites the active source.
- `howl-render/src/vt_publication/prepare_queue.zig`: add a test proving duplicate/rejected staged sources do not disturb `active_slot` contents.
- Geometry-refresh proof is required exactly in `howl-render/src/vt_publication/source_slot.zig` by extending `test "source slot refresh preserves snapshot and dirty metadata"` to cover both `staged_slot` and `active_slot` pointer refresh after capacity growth.
- `howl-render/src/c/prepare_request_test.zig`: add a test proving `takePrepareRequest(...)` leaves the admitted active source retained-backed rather than heap-owned, while preserving shipped prepare-request token semantics.
- No additional geometry-refresh proof in `render_session.zig` is authorized for this slice.
- Rerun `python3 utils/tools/rain-bench/benchmark_terminals.py --build`.
- Re-run narrow hotspot proof at `howl-linux-host/src/terminal/surface.zig:575-603` and record a fresh proof log artifact.

- Exact non-goals:
- No cleanup/removal of temporary instrumentation yet.
- No render-surface emitter redesign.
- No shaping/cluster/FreeType/HarfBuzz work.
- No ABI expansion.
- No benchmark harness changes.
- No attempt to beat Alacritty in one leap by redesigning the whole retained renderer.

- Exact stop conditions:
- Stop if removing the extra publication allocation requires changing the C ABI or host/render boundary.
- Stop if queue ownership cannot remain retained without a broader lifecycle change than `SourceSlot` + `PrepareRequests` can truthfully own inside this slice.
- Stop if keeping a stable prior source requires adding a third cross-owner runtime concept, host-side state, or any manager/helper abstraction outside `SourceSlot`, `PrepareRequests`, and `TextSessionOwner`.
- Stop if the two-slot staged/active design cannot satisfy `PrepareRequests.classify(...)` without another retained lifetime beyond `staged_slot` and `active_slot`.
- Stop if fresh source proof shows the copied publication storage is not materially affecting `prepare_ms` after the local fix.
- Stop if the change broadens beyond the allowed files.

- Exact receipt fields needed for acceptance:
- orchestrator session id: `orch-2026-06-14-ascii-rain-performance-01`
- researcher session id: `research-2026-06-14-ascii-rain-performance-01`
- reviewer session id: `review-2026-06-14-ascii-rain-performance-01`
- coder/worker session id
- commit-hash receipt status
- benchmark command
- benchmark artifact path
- hotspot proof location
- exact changed files and line references
- measured before
- measured after
- verification command list and results
- explicit note that instrumentation cleanup remains open for the later cleanup slice

Required assertions:

- Assert retained slot capacity matches incoming `cols`/`rows` before writing cells.
- Assert reserved-slot source lengths still match `rows` and `cols * rows` after commit.
- Assert retained-slot-backed prepare ingress preserves non-zero `snapshot_seq`, `dirty_epoch`, and `geometry_epoch` before emitting a request.
- Assert a retained source handed to `prepare_requests.admitSource(...)` stays `retained_storage == true` after admission in the repaired slice.
- Assert prior-source classification reads stable source contents that were not overwritten by staging the next retained publication.
- Assert `staged_slot` and `active_slot` never alias each other for the same publication lifetime.
- Assert retained-source pointer refresh after geometry capacity change still leaves both `staged_slot` and `active_slot` metadata and slices valid.
- Assert duplicate-source dedupe and partial/full classification outcomes are unchanged versus current tests.

Risks:

- The queue/source-slot fix removes avoidable ingress and admission allocation cost, but eager prepared-handle emission plus full-damage surface commands may still remain the next dominant prepare cost.
- Full-frame ASCII rain means damage classification stays `.full`; partial-damage machinery will not rescue this workload until the benchmark or renderer strategy changes.
- The repaired slice is larger than the original proposal because current source proves that single-slot retained ingress and queue-retained prior-source truth are coupled.
- The exact two-slot design may still reveal that the remaining prepare cost shifts quickly into prepared-handle emission once ingress and queue allocation are removed.

Proof gaps:

- Current runtime proof isolates `self.term.render.prepare(...)` but does not yet subdivide prepare between publication ingress copy, direct-normal scene build, and prepared-handle emission.
- The existing deeper probes proved only that `support.zig` and `cluster.zig` were cold enough not to dominate; they did not separately measure `prepare_queue.zig` clone cost versus prepared-handle emission cost.
- We do not yet have a post-fix proof showing whether the next hotspot becomes emitter work or direct-normal iteration.

Readiness judgment:

- The original ingress-only slice is rejected and not ready.
- The repaired honest-minimum slice is ready only with the exact two-slot `SourceSlot` staged/active design, exact `SourceSlot` owner-local seam proof, and geometry-refresh proof kept in `source_slot.zig` only.
- The best next fix is still inside the proved hot path, but it is now an exact queue/source-slot retained-lifecycle slice with no coder design authority left.

## Post-Iteration Interpretation

Status:

- Iteration 1 execution is rejected after benchmark and hotspot regression.
- This section supersedes the prior execution recommendation and is now the active interpretation surface for the next decision.

Sources read in order for this pass:

1. `loop/flow.md`
2. `loop/orcestrator.md`
3. `loop/researcher.md`
4. `loop/reviewer.md`
5. `loop/coder.md`
6. `loop/researcher.md` again as active role contract
7. `sprints/current.txt`
8. `loops/ascii-rain-performance-live-loop.txt`
9. `research/2026-06-14-ascii-rain-performance-plan.md`
10. latest reviewer rejection for iteration 1 execution in `loops/ascii-rain-performance-live-loop.txt:264-267`
11. `reference-index.md`
12. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
13. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
14. `utils/tools/rain-bench/artifacts/stress/20260614-035834-ascii/summary.json:45-121`
15. `utils/tools/rain-bench/artifacts/stress/20260614-042656-ascii/summary.json:45-121`
16. `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log:1-148`
17. `howl-linux-host/src/terminal/surface.zig:568-603`
18. `howl-linux-host/src/terminal/render_retained.zig:148-174`
19. `howl-render/src/c/prepare_request.zig:6-17`
20. `howl-render/src/vt_publication/source_slot.zig:93-132`
21. `howl-render/src/vt_publication/source_slot.zig:183-224`
22. `howl-render/src/vt_publication/prepare_queue.zig:38-80`
23. `howl-render/src/render_session.zig:162-205`
24. `howl-render/src/render_session.zig:461-479`
25. `howl-render/src/render_session.zig:522-529`
26. `howl-render/src/surface/handle.zig:20-38`
27. `howl-render/src/surface/handle.zig:128-138`
28. `howl-render/src/surface/emitter.zig:133-151`
29. `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:41-88`
30. `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:783-879`
31. `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:57-69`

Exact files and line references:

- Execution rejection receipt: `loops/ascii-rain-performance-live-loop.txt:264-267`.
- Before benchmark: `utils/tools/rain-bench/artifacts/stress/20260614-035834-ascii/summary.json:45-121`.
- After benchmark: `utils/tools/rain-bench/artifacts/stress/20260614-042656-ascii/summary.json:45-121`.
- Before proof checkpoint: `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log:74`.
- After proof checkpoint: `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log:148`.
- Hot surface seam still under study: `howl-linux-host/src/terminal/surface.zig:575-599`.
- Retained wrapper entrypoint: `howl-linux-host/src/terminal/render_retained.zig:148-174`.
- Current retained ingress: `howl-render/src/c/prepare_request.zig:6-17`.
- Current staged copy owner: `howl-render/src/vt_publication/source_slot.zig:102-108`.
- Current staged->active promotion copy owner: `howl-render/src/vt_publication/source_slot.zig:183-224`, especially `190-197`.
- Current admission owner: `howl-render/src/vt_publication/prepare_queue.zig:38-80`.
- Current text prepare owner: `howl-render/src/render_session.zig:162-205`, `461-479`.
- Current eager prepared-handle emission owner: `howl-render/src/surface/handle.zig:20-38`, `128-138`.
- Current render-surface emission spine: `howl-render/src/surface/emitter.zig:133-151`.

Measured outcome interpretation:

- Iteration 1 regressed the benchmark instead of improving it.
- Howl moved from `181.02 fps`, `p50 5038 us`, `p95 7512 us` to `175.28 fps`, `p50 5104 us`, `p95 7681 us` (`summary.json` before at `20260614-035834-ascii`, after at `20260614-042656-ascii`).
- That is a regression of about `-3.2%` FPS, `+1.3%` p50, and `+2.2%` p95.
- The hotspot proof also regressed at the exact same owner seam.
- Before: `prepare_calls=2368`, `capture_ms=258.969`, `prepare_ms=2054.274`, `submit_ms=1038.582` (`surface.log:74`).
- After: `prepare_calls=2368`, `capture_ms=260.329`, `prepare_ms=2245.974`, `submit_ms=1060.747` (`surface.log:148`).
- That is about `+0.5%` capture, `+9.3%` prepare, and `+2.1%` submit. The dominant regression is still inside `prepare(...)`.
- Therefore the iteration 1 change did not expose a new dominant hotspot by making prepare disappear. It made the same hotspot worse.

Current-code facts after the rejected fix:

- The current retained ingress path now performs two full publication copies after the host-side VT copy.
- First copy: `SourceSlot.copyPublishedSource(...)` copies all cells and dirty metadata into `staged_slot` (`howl-render/src/vt_publication/source_slot.zig:102-108`).
- Second copy: `SourceSlot.promoteStagedSource(...)` copies those same cells and dirty arrays again into `active_slot` (`howl-render/src/vt_publication/source_slot.zig:190-197`).
- Admission then promotes the retained publication and stores it as `active_source` (`howl-render/src/vt_publication/prepare_queue.zig:47-71`).
- The pre-fix path paid for one host-side copy plus one heap-owned render publication copy; the rejected fix pays for one host-side copy plus two render publication copies.
- The rejected fix did remove queue heap cloning, but on this measured full-frame ASCII workload that win was outweighed by the added staged->active memcpy.
- The proof does not show `submit(...)` taking over. `prepare(...)` remains the clear bottleneck at `howl-linux-host/src/terminal/surface.zig:587`.
- Inside `prepare(...)`, there are still large unproved owners after retained ingress/admission:
- `TextSession.prepareSurface(...)` builds the prepared text surface (`howl-render/src/render_session.zig:162-205`).
- `PreparedHandle.create(...)` eagerly emits the render surface payload immediately (`howl-render/src/surface/handle.zig:20-38`, `128-138`).
- `emitPreparedFresh(...)` always runs `appendPreparedPass(...)`, which appends full damage, full redraw clear, backgrounds, decorations, sprites, and cursors (`howl-render/src/surface/emitter.zig:133-151`).

Reference facts:

- Alacritty pressure still points away from extra full-surface ownership hops. It borrows terminal render content into `RenderableContent` and streams it into draw iteration (`display/content.rs:41-88`, `display/mod.rs:783-879`, `renderer/text/mod.rs:57-69`).
- The rejected Howl slice moved in the opposite direction for this workload by adding another full copy before the real prepare/render work.
- That does not yet prove a full structural blocker. It proves this specific local target was the wrong first optimization target under measured full-frame ASCII rain.

Exact next step recommendation:

- Continue locally, but do not authorize another optimization yet.
- The next honest move is a proof-only slice that splits `self.term.render.prepare(...)` into its current subphases so the next optimization target is measured instead of inferred.
- The exact proof question is: on current code, which subphase now dominates `prepare(...)`?
- Candidate subphases to measure exactly:
- retained ingress/admission via `howl_render_text_session_take_prepare_request`
- text surface construction via `TextSession.prepareSurface(...)`
- prepared-handle creation and eager render-surface emission via `PreparedHandle.create(...)` / `emitRenderSurfacePayload(...)`

One exact next slice:

- Slice type: proof only, no optimization.
- Allowed files:
- `howl-linux-host/src/terminal/render_retained.zig`
- `howl-render/src/c/prepare_request.zig`
- `howl-render/src/render_session.zig`
- `howl-render/src/surface/handle.zig`

- Exact required shape:
- Add temporary narrow timing logs that split `render_retained.State.prepare(...)` into:
- `take_prepare_request_ns`
- `prepare_handle_ns`
- Add temporary narrow timing logs in `TextSessionOwner.prepareHandle(...)` that split `prepare_handle_ns` into:
- `prepare_surface_ns`
- `prepared_handle_create_ns`
- Add temporary narrow timing logs in `PreparedHandle.create(...)` that split `prepared_handle_create_ns` into:
- allocation/registration overhead
- `emit_render_surface_payload_ns`
- Reuse the existing proof-log workflow and keep all probes local, disposable, and owner-scoped.
- Do not change behavior.

- Exact proof requirements:
- Re-run `python3 utils/tools/rain-bench/benchmark_terminals.py --build`.
- Append one fresh post-iteration proof section to `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log` or write one exact new proof log path and record it.
- The proof output must identify which of these current-code subphases dominates total `prepare_ns` on the ASCII rain workload:
- `take_prepare_request`
- `prepare_surface`
- `prepared_handle_create`
- `emit_render_surface_payload`

- Exact tests:
- from `howl-render`, run `zig build test:abi`
- from `howl-render`, run `zig build test:unit`

- Exact non-goals:
- no optimization yet
- no cleanup/removal of existing instrumentation yet
- no render-surface emitter redesign yet
- no text shaping changes yet
- no ABI changes
- no benchmark harness changes

- Exact stop conditions:
- stop if the probes stop being local and disposable
- stop if proving the subphases requires broad instrumentation across unrelated owners
- stop if the new proof shows no single dominant subphase inside `prepare(...)`
- stop if the dominant subphase lies outside the allowed file set before any edit is made

- Exact receipt fields needed for acceptance:
- orchestrator session id: `orch-2026-06-14-ascii-rain-performance-01`
- researcher session id: `research-2026-06-14-ascii-rain-performance-01`
- reviewer session id: `review-2026-06-14-ascii-rain-performance-01`
- coder session id
- benchmark command
- benchmark artifact path
- proof log artifact path
- exact proof location lines
- exact temporary instrumentation files and lines
- measured before
- measured after
- next dominant hotspot verdict
- commit-hash receipt status

Risks:

- The current two-slot retained ingress design may already have made the queue/source-slot path a dead-end for this workload, even if another subphase dominates more strongly.
- If `emit_render_surface_payload` dominates, the next accepted slice will need to move into `surface/handle.zig` and likely `surface/emitter.zig`, which is still local but different from the rejected target.
- If `prepareSurface` dominates, the next accepted slice must prove whether the remaining cost is direct-normal scene work or a broader render architecture cost.

Proof gaps:

- Current evidence only proves that total `prepare(...)` got worse after the two-slot change.
- It does not yet prove whether the regression is mostly from doubled publication memcpy, from text surface construction, or from eager render-surface emission.
- It also does not yet prove whether reverting the rejected fix would restore the previous measured state cleanly; that is outside this research pass and would require orchestrated execution truth.

Readiness judgment:

- Ready for a local proof-only slice.
- Not ready for another optimization slice.
- This is still a local runtime-proof-first performance sprint, not yet a structural blocker, because the dominant `prepare(...)` owner path remains local and still lacks subphase proof.

## Post-Proof-Slice-2 Interpretation

Status:

- Proof-only slice 2 completed.
- The newly proved dominant current-code subphase is `prepare_surface` inside `TextSessionOwner.prepareHandle(...)`.
- No new optimization is authorized yet because `prepare_surface` itself still spans multiple materially different owners.

Sources read in order for this pass:

1. `loop/flow.md`
2. `loop/orcestrator.md`
3. `loop/researcher.md`
4. `loop/reviewer.md`
5. `loop/coder.md`
6. `loop/researcher.md` again as active role contract
7. `sprints/current.txt`
8. `loops/ascii-rain-performance-live-loop.txt`
9. `research/2026-06-14-ascii-rain-performance-plan.md`
10. current proof receipts from `utils/tools/rain-bench/artifacts/stress/20260614-105248-ascii/summary.json` and `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log:441-444`
11. `reference-index.md`
12. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
13. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
14. `howl-render/src/render_session.zig:162-205`
15. `howl-render/src/render_session.zig:461-479`
16. `howl-render/src/text/surface_preparer.zig:123-143`
17. `howl-render/src/text/surface_preparer.zig:156-247`
18. `howl-render/src/text/direct_normal.zig:101-130`
19. `howl-render/src/text/direct_normal.zig:175-240`
20. `howl-render/src/text/shape/cluster.zig:307-357`
21. `howl-render/src/text/shape/cluster.zig:484-596`
22. `howl-render/src/vt_publication/text_input.zig:198-235`
23. `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:41-88`
24. `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:783-879`
25. `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:57-69`

Exact files and line references:

- Benchmark receipt for this pass: `utils/tools/rain-bench/artifacts/stress/20260614-105248-ascii/summary.json:45-121`.
- Proof receipt for this pass: `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log:441-444`.
- Current dominant subphase owner: `howl-render/src/render_session.zig:461-479`, especially `467-477`.
- Current `prepare_surface` owner: `howl-render/src/render_session.zig:162-205`.
- Current publication fast-path branch: `howl-render/src/text/surface_preparer.zig:123-143`.
- Current direct-normal core: `howl-render/src/text/direct_normal.zig:101-130`, `175-240`.
- Current complex fallback branch: `howl-render/src/text/surface_preparer.zig:156-247`.
- Current sparse publication builder: `howl-render/src/text/shape/cluster.zig:307-357`.
- Current cluster extraction/selection path: `howl-render/src/text/shape/cluster.zig:484-596`.
- Current fallback publication mapping branch: `howl-render/src/vt_publication/text_input.zig:198-235`.

Measured subphase interpretation:

- The new proof identifies `prepare_surface` as the dominant current subphase inside `prepare(...)`.
- Proof receipts:
- `prepared_handle_create split`: `registration_allocation_ms=1.339`, `emit_render_surface_payload_ms=393.063` (`surface.log:441`).
- `prepare_handle split`: `prepare_surface_ms=1692.912`, `prepared_handle_create_ms=396.982` (`surface.log:442`).
- `prepare split`: `take_prepare_request_ms=376.024`, `prepare_handle_ms=2092.528` (`surface.log:443`).
- Full surface proof checkpoint: `prepare_ms=2469.900` (`surface.log:444`).
- Relative reading from the proved run:
- `prepare_surface` is about `68.5%` of total `prepare_ms` (`1692.912 / 2469.900`).
- `prepared_handle_create` is about `16.1%` of total `prepare_ms`.
- `take_prepare_request` is about `15.2%` of total `prepare_ms`.
- Within `prepared_handle_create`, the real work is `emit_render_surface_payload`; registration/allocation is noise (`393.063 ms` vs `1.339 ms`).
- The benchmark also regressed further in this proof-only pass: Howl is now `148.22 fps`, `p50 6350 us`, `p95 10404 us` (`summary.json:45-83`), which reinforces that temporary proof noise is present and no optimization inference should be made from the benchmark movement itself.

Current-code facts for `prepare_surface`:

- `TextSessionOwner.prepareHandle(...)` spends most of its measured time inside `self.session.prepareSurface(...)` before prepared-handle emission begins (`howl-render/src/render_session.zig:461-479`).
- `TextSession.prepareSurface(...)` still contains two materially different rendering paths:
- a publication fast path through `preparer.preparePublicationWithSessionOptions(...)` (`howl-render/src/render_session.zig:179-190`)
- a fallback path that first maps the whole publication into borrowed `CellInput` storage and then calls `prepareCellsWithSessionOptions(...)` (`howl-render/src/render_session.zig:191-204`)
- `preparePublicationWithSessionOptions(...)` itself also has two materially different branches:
- direct-normal success via `prepareDirectNormal(...)` and `finishNormalOnlySurface(...)` (`howl-render/src/text/surface_preparer.zig:131-135`)
- complex fallback through sparse publication building, cluster extraction, grouping, scene build, and raster planning (`howl-render/src/text/surface_preparer.zig:136-143`, `156-247`)
- Earlier runtime proof already showed `cluster.zig` stayed cold enough not to dominate the original hotspot path, but the new subphase proof did not measure whether `prepare_surface` is dominated by direct-normal work, by the publication fast-path rejection logic, or by the fallback mapping branch.
- Therefore `prepare_surface` is still too broad to optimize honestly as one owner decision.

Relevant reference facts:

- Alacritty still prepares renderable content by borrowing terminal content and iterating it directly (`display/content.rs:41-88`, `153-185`).
- Alacritty then streams those cells directly into text rendering (`display/mod.rs:783-879`, `renderer/text/mod.rs:57-69`).
- The relevant reference pressure is still toward reducing unnecessary whole-surface materialization and expensive per-cell work before draw.
- But the current proof does not yet say whether Howl's dominant local loss inside `prepare_surface` is the direct-normal scan itself or some fallback branch inside the same owner.

Exact next-step recommendation:

- Continue locally.
- One more proof split is required before any optimization would be honest.
- The exact proof question is: inside `prepare_surface`, which branch dominates on the ASCII rain workload?
- The exact owners to split are:
- `preparePublicationWithSessionOptions(...)`
- `prepareDirectNormal(...)`
- the fallback publication mapping branch in `render_session.zig` / `vt_publication/text_input.zig`
- the complex fallback branch in `surface_preparer.zig`

One exact next slice:

- Slice type: proof only, no optimization.
- Allowed files:
- `howl-render/src/render_session.zig`
- `howl-render/src/text/surface_preparer.zig`
- `howl-render/src/text/direct_normal.zig`

- Exact required shape:
- Add temporary narrow timing logs in `TextSession.prepareSurface(...)` that split `prepare_surface_ns` into:
- `prepare_publication_fast_path_ns`
- `fallback_publication_map_ns`
- `fallback_prepare_cells_ns`
- Add temporary narrow timing logs in `TextSurfacePreparer.preparePublicationWithSessionOptions(...)` that split `prepare_publication_fast_path_ns` into:
- `prepare_direct_normal_attempt_ns`
- `prepare_publication_complex_fallback_ns`
- Add temporary narrow timing logs in `direct_normal.prepare(...)` that record:
- total `direct_normal_prepare_ns`
- the count of visible cells scanned
- the count of included normal cells
- whether the path returned direct success or rejected into fallback
- Keep the probes local, disposable, and owner-scoped.
- Do not change behavior.

- Exact tests:
- from `howl-render`, run `zig build test:abi`
- from `howl-render`, run `zig build test:unit`

- Exact benchmark/proof requirements:
- rerun `python3 utils/tools/rain-bench/benchmark_terminals.py --build`
- append one fresh proof section to `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log` or write one exact new proof log path and record it
- the proof output must identify which of these current-code subphases dominates `prepare_surface_ns` on ASCII rain:
- `prepare_publication_fast_path`
- `fallback_publication_map`
- `fallback_prepare_cells`
- and, if the fast path dominates, whether that time is mostly:
- `prepare_direct_normal_attempt`
- or `prepare_publication_complex_fallback`

- Exact non-goals:
- no optimization yet
- no instrumentation cleanup yet
- no work in `cluster.zig`, `surface/handle.zig`, or `surface/emitter.zig` for this slice
- no ABI changes
- no benchmark harness changes

- Exact stop conditions:
- stop if the probes stop being local and disposable
- stop if proving `prepare_surface` requires instrumenting files outside the allowed set before any edit is made
- stop if the proof shows `prepare_surface` time is already cleanly dominated by the fallback complex path and that path conflicts with the earlier cold-cluster proof; escalate that contradiction instead of guessing
- stop if the proof still fails to isolate one dominant branch inside `prepare_surface`

- Exact receipt fields needed for acceptance:
- orchestrator session id: `orch-2026-06-14-ascii-rain-performance-01`
- researcher session id: `research-2026-06-14-ascii-rain-performance-01`
- reviewer session id: `review-2026-06-14-ascii-rain-performance-01`
- coder session id
- benchmark command
- benchmark artifact path
- proof log artifact path
- exact proof location lines
- exact temporary instrumentation files and lines
- measured before
- measured after
- dominant `prepare_surface` branch verdict
- commit-hash receipt status

Risks:

- Benchmark numbers under proof-only instrumentation are already noisy enough that only relative subphase shares should drive the next decision.
- If direct-normal dominates, the next slice will likely return to `text/direct_normal.zig`, but only after branch proof closes the remaining ambiguity.
- If the fallback mapping branch dominates, the next slice may need to revisit publication-to-cell mapping rather than direct-normal scan.

Proof gaps:

- We still do not know whether ASCII rain is actually taking the direct-normal success path most of the time or paying for fast-path rejection plus fallback preparation.
- We do not yet have measured counts showing how many cells are scanned versus actually included in direct-normal on this workload.
- We do not yet have a measured contradiction check between the earlier cold-cluster proof and the current broad `prepare_surface` dominance.

Readiness judgment:

- Ready for one more local proof-only slice.
- Not ready for another optimization slice yet.
- This remains a local runtime-proof-first sprint, not a structural blocker.

## Post-Proof-Slice-9 Interpretation

Status:

- Proof-only slice 9 completed.
- The newly proved dominant cleaned-code inner cost inside `source_candidate(...)` is `publication_renderable_text(...)`.
- A new local optimization slice is now justified.

Sources read in order for this pass:

1. `loop/flow.md`
2. `loop/orcestrator.md`
3. `loop/researcher.md`
4. `loop/reviewer.md`
5. `loop/coder.md`
6. `loop/researcher.md` again as active role contract
7. `sprints/current.txt`
8. `loops/ascii-rain-performance-live-loop.txt`
9. `research/2026-06-14-ascii-rain-performance-plan.md`
10. proof receipt `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log:2745`
11. `reference-index.md`
12. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
13. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
14. `howl-render/src/text/direct_normal.zig:198-273`
15. `howl-render/src/text/direct_normal.zig:305-336`
16. `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:41-88`
17. `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:783-879`
18. `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:57-69`

Exact files and line references:

- Proof receipt for this pass: `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log:2745`.
- Benchmark receipt for this pass: `utils/tools/rain-bench/artifacts/stress/20260614-123522-ascii/summary.json:47-82`.
- Cleaned-code source-candidate hot path: `howl-render/src/text/direct_normal.zig:305-336`.
- Supported publication hot path setup and direct-normal owner entry: `howl-render/src/text/direct_normal.zig:198-273`.

Measured subphase interpretation:

- The slice-9 proof is sharp enough to isolate `publication_renderable_text(...)` as the dominant cleaned-code inner cost inside `source_candidate(...)`.
- Receipt at `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log:2745` shows:
- `source_candidate_ms=4994.438`
- `publication_cell_supported_ms=550.566`
- `publication_renderable_text_ms=1663.237`
- `publication_damage_include_ms=556.879`
- `append_renderable_ms=982.064`
- `fallback_reject_calls=0`
- `publication_renderable_text_ms` is well above support checks and damage include filtering.
- The benchmark on this proof-heavy run is badly distorted, but the owner-path verdict remains stable and accountable.

Current-code facts for `publication_renderable_text`:

- The supported publication fast path now avoids `PublicationCandidate` / `Candidate` wrappers, but it still constructs renderable/text facts per cell before damage include and append (`howl-render/src/text/direct_normal.zig:311-316`).
- That construction remains inside `direct_normal.zig`; no broader owner or ABI seam is required for the next move.
- `fallback_reject_calls=0` remains true, so unsupported-cell fallback semantics are not the active hot path on this workload.

Relevant reference facts:

- Alacritty still prepares borrowed terminal content with minimal per-cell packaging before draw (`display/content.rs:41-88`, `display/mod.rs:783-879`, `renderer/text/mod.rs:57-69`).
- The matching pressure here is still to cut per-cell construction work on the hot path before rendering, not to broaden architecture.

Exact next-step recommendation:

- Continue locally with one optimization slice.
- The best next local move is to specialize `publicationRenderableText(...)` on the supported publication hot path and reduce repeated per-cell construction/conversion work there.

One exact next slice:

- Slice type: optimization.
- Allowed files:
- `howl-render/src/text/direct_normal.zig`

- Exact required shape:
- Keep all changes inside `direct_normal.zig`.
- Optimize the supported publication hot path by specializing `publicationRenderableText(...)`.
- Reduce repeated per-cell construction/conversion work there.
- Keep supported output bytes and semantics identical.
- Preserve unsupported-cell fallback behavior exactly.
- Do not change `appendRenderable(...)`, glyph lookup, atlas reserve, damage filtering, or non-publication paths.

- Exact tests:
- from `howl-render`, run `zig build test:abi`
- from `howl-render`, run `zig build test:unit`
- keep existing direct-normal owner tests green:
- `howl-render/src/text/direct_normal.zig`: `test "direct normal publication zero codepoint is a fast candidate"`
- `howl-render/src/text/direct_normal.zig`: `test "direct normal publication keeps unsupported non-printables on generic fallback"`
- keep existing publication direct-path tests green:
- `howl-render/src/text/surface_preparer.zig`: `test "text preparation publication ascii stays on direct normal path"`
- `howl-render/src/text/surface_preparer.zig`: `test "text preparation publication styled indexed ascii stays on direct normal path"`
- `howl-render/src/text/surface_preparer.zig`: `test "text preparation publication non inverse indexed ascii stays on direct normal path"`
- `howl-render/src/text/surface_preparer.zig`: `test "text preparation publication zero codepoint stays on direct normal path without sprite draw"`
- `howl-render/src/text/surface_preparer.zig`: `test "text preparation publication unsupported space and rgb keep fallback scratch clean"`
- `howl-render/src/text/surface_preparer.zig`: `test "text preparation publication tab stays on generic fallback without partial direct scratch"`
- `howl-render/src/text/surface_preparer.zig`: `test "text preparation publication other control stays on generic fallback without partial direct scratch"`

- Exact benchmark/proof requirements:
- rerun `python3 utils/tools/rain-bench/benchmark_terminals.py --build`
- rerun the current proof-only receipts sufficiently to compare before/after at the same owner path
- required measured outputs:
- `publication_renderable_text_ms`
- `source_candidate_ms`
- `append_visible_ms`
- total `prepare_ms`
- Howl FPS / p50 / p95

- Exact non-goals:
- no changes outside `direct_normal.zig`
- no glyph lookup optimization yet
- no atlas/raster optimization yet
- no fallback/publication ABI expansion
- no instrumentation cleanup yet

- Exact stop conditions:
- stop if preserving supported output bytes or unsupported-cell fallback semantics requires edits outside `direct_normal.zig`
- stop if benchmark and proof both fail to improve the proved `publication_renderable_text` / `source_candidate` hot path

- Exact receipt fields needed for acceptance:
- orchestrator session id: `orch-2026-06-14-ascii-rain-performance-01`
- researcher session id: `research-2026-06-14-ascii-rain-performance-01`
- reviewer session id: `review-2026-06-14-ascii-rain-performance-01`
- coder session id
- exact changed files and line references
- verification command list and results
- benchmark command
- benchmark artifact path
- proof log artifact path
- exact proof location lines
- measured before
- measured after
- verdict on `publication_renderable_text_ms`, `source_candidate_ms`, `append_visible_ms`, and total `prepare_ms`
- commit-hash receipt status

Risks:

- A win here may quickly expose either `publication_cell_supported(...)` or `appendRenderable(...)` next.
- Benchmark variance remains noisy, so proof-path movement must remain the primary acceptance signal.

Proof gaps:

- We do not yet know the best follow-up after this slice until we see the post-change proof.

Readiness judgment:

- Ready for a local optimization slice.
- This remains a local runtime-proof-first sprint, not a structural blocker.

## Post-Proof-Slice-9 Interpretation

Status:

- Proof-only slice 9 completed.
- The newly proved dominant cleaned-code `source_candidate(...)` subphase is `publication_renderable_text(...)`.
- This is now optimization-ready as a local slice.

Sources read in order for this pass:

1. `loop/flow.md`
2. `loop/orcestrator.md`
3. `loop/researcher.md`
4. `loop/reviewer.md`
5. `loop/coder.md`
6. `loop/researcher.md` again as active role contract
7. `sprints/current.txt`
8. `loops/ascii-rain-performance-live-loop.txt`
9. `research/2026-06-14-ascii-rain-performance-plan.md`
10. proof receipts at `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log:2745`
11. `reference-index.md`
12. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
13. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
14. `howl-render/src/text/direct_normal.zig:429-516`
15. `howl-render/src/text/direct_normal.zig:758-773`
16. `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:41-88`
17. `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:783-879`
18. `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:57-69`

Exact files and line references:

- Proof receipt for this pass: `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log:2745`.
- Current `sourceCandidate(...)` owner: `howl-render/src/text/direct_normal.zig:429-440`.
- Current `publicationCandidate(...)` owner: `howl-render/src/text/direct_normal.zig:443-454`.
- Current `publicationCellSupported(...)` owner: `howl-render/src/text/direct_normal.zig:456-470`.
- Current `publicationRenderableText(...)` owner: `howl-render/src/text/direct_normal.zig:472-516`.
- Current direct-normal owner-local proof roots: `howl-render/src/text/direct_normal.zig:758-773`.

Measured subphase interpretation:

- The new proof isolates `publication_renderable_text(...)` as the largest cleaned-code inner cost inside `source_candidate(...)`.
- Proof receipt:
- `source_candidate_ms=4994.438`
- `publication_cell_supported_ms=550.566`
- `publication_renderable_text_ms=1663.237`
- `publication_damage_include_ms=556.879`
- `append_renderable_ms=982.064`
- `append_visible_ms=7156.743`
- `visible_cells_scanned=29022740`
- `included_normal_cells=28916662`
- `direct_success_calls=2336`
- `fallback_reject_calls=0`
- Relative reading from the proved run:
- `publication_renderable_text_ms` is the largest named inner cost on the supported publication path.
- It is about `3.0x` either `publication_cell_supported_ms` or `publication_damage_include_ms`.
- It is also larger than `append_renderable_ms`.
- The workload remains fully on the direct-normal fast path with zero fallback rejects, so this is the real workload owner path, not an edge branch.
- That is enough proof to optimize `publication_renderable_text(...)` directly without another proof split first.

Current-code facts for `publication_renderable_text(...)`:

- `publicationRenderableText(...)` currently does repeated per-cell construction work (`howl-render/src/text/direct_normal.zig:472-516`):
- computes `fg` and `bg` through `publicationColorRgba(...)`
- conditionally swaps colors for inverse
- computes `style` through `publicationFontStyle(...)`
- computes `semantic_fg` and `semantic_bg` through `publicationSemanticColor(...)`
- constructs a full `cluster.RenderableText` value with many fields set to fixed values for this workload shape
- indexes into the prebuilt `ascii_codepoints` table for the one-codepoint text slice
- The proved workload path has these simplifying facts:
- `fallback_reject_calls=0`, so the supported publication subset is the hot path
- `direct_success_calls=2336`, so the path does not feed complex fallback
- `publicationCellSupported(...)` already guarantees single-cell ASCII-compatible publication facts before `publicationRenderableText(...)` runs (`direct_normal.zig:456-470`)
- That makes `publicationRenderableText(...)` a good candidate for specialization without touching broader render owners.

Relevant Alacritty/reference facts:

- Alacritty still borrows terminal render content and streams per-cell work directly into the renderer (`display/content.rs:41-88`, `display/mod.rs:783-879`, `renderer/text/mod.rs:57-69`).
- The strongest reference pressure here is to reduce unnecessary per-cell object construction and conversions on the hot path.
- Current `publicationRenderableText(...)` is exactly such a per-cell construction hotspot, and current proof says it is now the largest named one.

Exact next-step recommendation:

- Continue locally with one optimization slice.
- `publication_renderable_text(...)` is the right next local target.

One exact next slice:

- Slice type: optimization.
- Allowed files:
- `howl-render/src/text/direct_normal.zig`

- Exact required shape:
- Keep all changes inside `direct_normal.zig`.
- Optimize the supported publication hot path by specializing `publicationRenderableText(...)` for the proved workload shape.
- The slice may:
- reduce repeated field construction for fixed-value fields on the supported publication path
- collapse repeated semantic/color/style derivation work where it is provably redundant under `publicationCellSupported(...)`
- keep output bytes and semantics identical for the supported publication subset
- preserve current unsupported publication fallback behavior exactly
- preserve current tests and assertions
- Do not change `appendRenderable(...)`, glyph lookup, atlas reserve, damage filtering, or non-publication paths.

- Exact tests:
- from `howl-render`, run `zig build test:abi`
- from `howl-render`, run `zig build test:unit`
- keep existing direct-normal owner tests green:
- `howl-render/src/text/direct_normal.zig`: `test "direct normal publication zero codepoint is a fast candidate"`
- `howl-render/src/text/direct_normal.zig`: `test "direct normal publication keeps unsupported non-printables on generic fallback"`
- keep existing publication direct-path tests green:
- `howl-render/src/text/surface_preparer.zig`: `test "text preparation publication ascii stays on direct normal path"`
- `howl-render/src/text/surface_preparer.zig`: `test "text preparation publication styled indexed ascii stays on direct normal path"`
- `howl-render/src/text/surface_preparer.zig`: `test "text preparation publication non inverse indexed ascii stays on direct normal path"`
- `howl-render/src/text/surface_preparer.zig`: `test "text preparation publication zero codepoint stays on direct normal path without sprite draw"`
- `howl-render/src/text/surface_preparer.zig`: `test "text preparation publication unsupported space and rgb keep fallback scratch clean"`
- `howl-render/src/text/surface_preparer.zig`: `test "text preparation publication tab stays on generic fallback without partial direct scratch"`
- `howl-render/src/text/surface_preparer.zig`: `test "text preparation publication other control stays on generic fallback without partial direct scratch"`

- Exact benchmark/proof requirements:
- rerun `python3 utils/tools/rain-bench/benchmark_terminals.py --build`
- rerun the current direct-normal proof receipts sufficiently to compare before/after at the same owner path
- required measured outputs:
- `publication_renderable_text_ms`
- `source_candidate_ms`
- `append_visible_ms`
- total `prepare_ms`
- Howl FPS / p50 / p95

- Exact non-goals:
- no changes outside `direct_normal.zig`
- no support-check optimization yet
- no damage-include optimization yet
- no `appendRenderable(...)` / glyph / atlas optimization yet
- no ABI changes
- no instrumentation cleanup yet

- Exact stop conditions:
- stop if preserving supported publication output bytes and fallback semantics requires edits outside `direct_normal.zig`
- stop if proof after the change does not improve `publication_renderable_text_ms` materially
- stop if proof shows `publication_cell_supported_ms` or `publication_damage_include_ms` becoming larger than `publication_renderable_text_ms` before the benchmark/proof handoff closes

- Exact receipt fields needed for acceptance:
- orchestrator session id: `orch-2026-06-14-ascii-rain-performance-01`
- researcher session id: `research-2026-06-14-ascii-rain-performance-01`
- reviewer session id: `review-2026-06-14-ascii-rain-performance-01`
- coder session id
- exact changed files and line references
- verification command list and results
- benchmark command
- benchmark artifact path
- proof log artifact path
- exact proof location lines
- measured before
- measured after
- verdict on `publication_renderable_text_ms`, `source_candidate_ms`, `append_visible_ms`, and total `prepare_ms`
- commit-hash receipt status

Risks:

- The measured gap from `publication_renderable_text_ms` to the other named inner costs is meaningful but not overwhelming; a win here may quickly expose `publication_cell_supported(...)` or `appendRenderable(...)` next.
- If much of the cost is compiler/codegen resistant struct construction, gains may be moderate rather than dramatic.
- Benchmark variance remains noisy, so proof-path movement must remain primary in acceptance.

Proof gaps:

- We still do not know whether the best follow-up after this slice will be support-check work or `appendRenderable(...)` work.
- We do not yet have a post-optimization measurement for `publication_renderable_text(...)` itself.

Readiness judgment:

- Ready for a local optimization slice.
- This remains a local runtime-proof-first sprint, not a structural blocker.

Sources read in order for this pass:

1. `loop/flow.md`
2. `loop/orcestrator.md`
3. `loop/researcher.md`
4. `loop/reviewer.md`
5. `loop/coder.md`
6. `loop/researcher.md` again as active role contract
7. `sprints/current.txt`
8. `loops/ascii-rain-performance-live-loop.txt`
9. `research/2026-06-14-ascii-rain-performance-plan.md`
10. current proof receipts from `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log:883-888`
11. `reference-index.md`
12. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
13. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
14. `howl-render/src/text/direct_normal.zig:150-201`
15. `howl-render/src/text/direct_normal.zig:458-465`
16. `howl-render/src/text/direct_normal.zig:482-531`
17. `howl-render/src/text/direct_normal.zig:573-593`
18. `howl-render/src/text/surface_preparer.zig:166-185`
19. `howl-render/src/text/direct_scene.zig:24-69`
20. `howl-render/src/text/raster/atlas.zig:54-95`
21. `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:41-88`
22. `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:783-879`
23. `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:57-69`

Exact files and line references:

- Proof receipt for this pass: `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log:883-888`.
- Current `prepare_surface` fast-path wrapper: `howl-render/src/text/surface_preparer.zig:166-185`.
- Current direct-normal owner entry: `howl-render/src/text/direct_normal.zig:150-201`.
- Current proof recount helper: `howl-render/src/text/direct_normal.zig:458-465`.
- Current publication candidate / append loop entry: `howl-render/src/text/direct_normal.zig:175-240`.
- Current append/renderable owner: `howl-render/src/text/direct_normal.zig:482-531`.
- Current finish-scene owner: `howl-render/src/text/direct_normal.zig:573-593`.
- Current scene-rect append owners: `howl-render/src/text/direct_scene.zig:24-69`.
- Current atlas reserve owner: `howl-render/src/text/raster/atlas.zig:54-95`.

Measured branch interpretation:

- The new proof closes the previous branch ambiguity.
- On the ASCII rain workload:
- `prepare_surface` is dominated by `prepare_publication_fast_path` (`surface.log:886`).
- `fallback_publication_map_ms=0.000` and `fallback_prepare_cells_ms=0.000` (`surface.log:886`).
- Inside the fast path, `prepare_publication_complex_fallback_ms=0.000` (`surface.log:884`).
- `direct_success_calls=2368` and `fallback_reject_calls=0` (`surface.log:883`).
- `visible_cells_scanned=29429556` and `included_normal_cells=29429556` (`surface.log:883`), so every scanned cell on this workload was included as a normal direct-normal candidate.
- The direct-normal fast path is therefore the real workload path, and any next local optimization should target `direct_normal.prepare(...)` or a proved subphase within it, not fallback machinery.
- But the current proof is still not clean enough to authorize an optimization inside `direct_normal.prepare(...)`:
- `prepare_direct_normal_attempt_ms=2732.766` (`surface.log:884`) wraps the whole `prepareDirectNormal(...)` call from `surface_preparer.zig:170-175`.
- Inside `direct_normal.prepare(...)`, the proof logger calls `visibleCellsScanned(...)` after timing stops for `direct_normal_prepare_ns` but before the function returns (`direct_normal.zig:161-201`, especially `193-199` and helper `458-465`).
- Also, `direct_normal_prepare_ns` is recorded before `finishScene(...)` runs (`direct_normal.zig:193-201` vs `573-593`).
- Therefore the current receipts prove the fast path branch, but they still blur three separate costs:
- append/classify/include work in `appendVisible(...)`
- scene-rect append work in `direct_scene.append*`
- `finishScene(...)` raster-miss work
- plus proof-only recount overhead from `visibleCellsScanned(...)`

Current-code facts for `direct_normal.prepare(...)`:

- `direct_normal.prepare(...)` first builds `damage`, resets scratch, and runs `appendVisible(...)` over the entire source owner path (`direct_normal.zig:167-171`).
- On the publication fast path, `sourceCandidate(...)` routes through `publicationCandidate(...)` before falling back to generic item construction (`direct_normal.zig:229-254`).
- Each included normal cell then goes through `appendRenderable(...)`, which performs glyph lookup, atlas reservation, raster miss enqueue, and sprite draw append (`direct_normal.zig:482-531`).
- After the visible scan, `direct_normal.prepare(...)` appends backgrounds, clears, decorations, and cursor geometry through `direct_scene` (`direct_normal.zig:189-192`, `direct_scene.zig:37-69`).
- Only after that does `finishScene(...)` allocate raster outputs and rasterize any pending sprite requests (`direct_normal.zig:573-593`).
- Because `visibleCellsScanned(...)` re-walks `sourceCandidate(...)` in proof mode (`direct_normal.zig:458-465`), the current branch-level proof overstates wrapper time and is not a clean basis for choosing scan-vs-finish optimization yet.

Relevant Alacritty/reference facts:

- Alacritty still borrows terminal content and iterates it directly in one draw-preparation stream (`display/content.rs:41-88`, `display/mod.rs:783-879`, `renderer/text/mod.rs:57-69`).
- The strongest reference pressure here is toward minimizing repeated per-cell classification and extra passes over the same visible cells.
- That pressure makes a future direct-normal scan optimization plausible, but the exact scan-vs-finish split must be proved first.

Exact next-step recommendation:

- Continue locally.
- One more proof split is required before any optimization inside `direct_normal.prepare(...)` would be honest.
- The exact proof question is: on this workload, which current-code subphase dominates inside `direct_normal.prepare(...)` once proof-only recount overhead is separated out?

One exact next slice:

- Slice type: proof only, no optimization.
- Allowed files:
- `howl-render/src/text/direct_normal.zig`

- Exact required shape:
- Keep the proof local to `direct_normal.zig` only.
- Replace the current proof recount dependence on `visibleCellsScanned(...)` with in-loop counters recorded during the real `appendVisible(...)` pass so no second scan is needed for the proof.
- Add temporary narrow timing logs in `direct_normal.prepare(...)` that split the real work into:
- `append_visible_ns`
- `append_scene_rects_ns`
- `finish_scene_ns`
- Keep separate counters for:
- `visible_cells_scanned`
- `included_normal_cells`
- `direct_success_calls`
- `fallback_reject_calls`
- `raster_req_count_total`
- Do not change behavior.

- Exact tests:
- from `howl-render`, run `zig build test:abi`
- from `howl-render`, run `zig build test:unit`

- Exact benchmark/proof requirements:
- rerun `python3 utils/tools/rain-bench/benchmark_terminals.py --build`
- append one fresh proof section to `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log` or write one exact new proof log path and record it
- the proof output must identify which of these dominates real direct-normal cost on ASCII rain:
- `append_visible`
- `append_scene_rects`
- `finish_scene`
- and must report `raster_req_count_total` so the next slice can tell whether `finishScene(...)` is materially active or mostly a scan-side problem

- Exact non-goals:
- no optimization yet
- no instrumentation cleanup yet
- no edits outside `howl-render/src/text/direct_normal.zig`
- no ABI changes
- no benchmark harness changes

- Exact stop conditions:
- stop if isolating real direct-normal subphases requires editing files outside `howl-render/src/text/direct_normal.zig`
- stop if the proof still depends on a second recount pass over the source to produce its main verdict
- stop if the new proof fails to isolate one dominant subphase inside `direct_normal.prepare(...)`

- Exact receipt fields needed for acceptance:
- orchestrator session id: `orch-2026-06-14-ascii-rain-performance-01`
- researcher session id: `research-2026-06-14-ascii-rain-performance-01`
- reviewer session id: `review-2026-06-14-ascii-rain-performance-01`
- coder session id
- benchmark command
- benchmark artifact path
- proof log artifact path
- exact proof location lines
- exact temporary instrumentation files and lines
- measured before
- measured after
- dominant direct-normal subphase verdict
- `raster_req_count_total`
- commit-hash receipt status

Risks:

- The current proof-only counters already perturb timing, so the next split must reduce observer cost rather than add another full pass.
- If `append_visible` dominates, the next optimization slice will likely target publication candidate/classification and appendRenderable scan work.
- If `finish_scene` dominates, the next optimization slice will likely target raster miss behavior or atlas pressure instead.

Proof gaps:

- We still do not know whether the direct-normal bottleneck is mostly scan/classification, scene-rect append, or finish-scene raster work.
- We do not yet have measured raster request counts on this workload.
- We do not yet have a proof receipt that separates real product work from the proof-only `visibleCellsScanned(...)` recount overhead.

Readiness judgment:

- Ready for one more local proof-only slice.
- Not ready for an optimization slice inside `direct_normal.prepare(...)` yet.
- This remains a local runtime-proof-first sprint, not a structural blocker.

## Post-Proof-Slice-4 Interpretation

Status:

- Proof-only slice 4 completed.
- The newly proved dominant real-work subphase is `append_visible` inside `direct_normal.prepare(...)`.
- No optimization is authorized yet because `append_visible` still contains two materially different costs and the current proof does not separate them.

Sources read in order for this pass:

1. `loop/flow.md`
2. `loop/orcestrator.md`
3. `loop/researcher.md`
4. `loop/reviewer.md`
5. `loop/coder.md`
6. `loop/researcher.md` again as active role contract
7. `sprints/current.txt`
8. `loops/ascii-rain-performance-live-loop.txt`
9. `research/2026-06-14-ascii-rain-performance-plan.md`
10. current proof receipts from `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log:1327-1332`
11. `reference-index.md`
12. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
13. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
14. `howl-render/src/text/direct_normal.zig:175-233`
15. `howl-render/src/text/direct_normal.zig:297-357`
16. `howl-render/src/text/direct_normal.zig:482-531`
17. `howl-render/src/text/direct_normal.zig:573-593`
18. `howl-render/src/text/session.zig:56-115`
19. `howl-render/src/text/raster/atlas.zig:54-95`
20. `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:41-88`
21. `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:783-879`
22. `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:57-69`

Exact files and line references:

- Proof receipt for this pass: `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log:1327-1332`.
- Current dominant owner entry: `howl-render/src/text/direct_normal.zig:175-233`.
- Current `appendVisible(...)` loop: `howl-render/src/text/direct_normal.zig:286-325`.
- Current publication candidate path: `howl-render/src/text/direct_normal.zig:338-388`.
- Current append/renderable path: `howl-render/src/text/direct_normal.zig:482-531`.
- Current finish-scene tail: `howl-render/src/text/direct_normal.zig:573-593`.
- Current face-resolution owner: `howl-render/src/text/session.zig:56-115`.
- Current atlas reservation owner: `howl-render/src/text/raster/atlas.zig:54-95`.

Measured subphase interpretation:

- The new proof isolates `append_visible` as the dominant real work inside `direct_normal.prepare(...)`.
- Proof receipts:
- `direct_normal_prepare_ms=1674.427`
- `append_visible_ms=1412.901`
- `append_scene_rects_ms=203.392`
- `finish_scene_ms=56.865`
- `visible_cells_scanned=29429556`
- `included_normal_cells=29429556`
- `direct_success_calls=2368`
- `fallback_reject_calls=0`
- `raster_req_count_total=1216`
- Relative reading from the proved run:
- `append_visible` is about `84.4%` of `direct_normal_prepare_ms`.
- `append_scene_rects` is about `12.1%`.
- `finish_scene` is about `3.4%`.
- The workload stays fully on the publication fast path with zero fallback rejects, and every counted scanned cell is included as a normal candidate.
- `raster_req_count_total=1216` across `2368` calls is small relative to `included_normal_cells=29429556`, so the proved bottleneck is not dominated by raster misses.
- That still does not identify whether `append_visible` time is mostly spent in:
- publication candidate/classification work (`sourceCandidate(...)` / `publicationCandidate(...)`)
- or append/renderable work (`appendRenderable(...)`, including face resolution, glyph lookup, and atlas reserve)

Current-code facts for `append_visible`:

- `appendVisible(...)` is the central loop that walks the source and either skips, rejects, or appends one candidate per cell (`howl-render/src/text/direct_normal.zig:286-325`).
- On this workload, the proof says it is never rejecting into fallback, so the hot path is the `.include` arm calling `appendRenderable(...)` over and over.
- For publication sources, `sourceCandidate(...)` first routes through `publicationCandidate(...)` (`howl-render/src/text/direct_normal.zig:338-347`, `352-388`).
- `publicationCandidate(...)` still does per-cell support checks, color conversion, style mapping, and damage filtering before constructing a candidate.
- `appendRenderable(...)` then does per-cell face resolution, glyph lookup, atlas reservation, optional raster-request enqueue, sprite draw append, and lane counter updates (`howl-render/src/text/direct_normal.zig:482-531`).
- `finishScene(...)` is now proved much smaller than `append_visible`, so optimizing `finishScene(...)` next would outrun the receipts.
- Because `visible_cells_scanned == included_normal_cells`, the proof strongly suggests a scan path with almost no negative-space filtering on this workload, but it does not yet prove whether the heavy cost is candidate construction or renderable append work.

Relevant Alacritty/reference facts:

- Alacritty still prepares content by borrowing terminal render data and then streaming cells directly to the text renderer (`display/content.rs:41-88`, `display/mod.rs:783-879`, `renderer/text/mod.rs:57-69`).
- The strongest reference pressure here is toward reducing repeated per-cell work on the hot path.
- Current Howl `append_visible` still performs more per-cell owner work before draw than Alacritty's path, but the exact expensive part inside that owner is not yet proved.

Exact next-step recommendation:

- Continue locally.
- One more proof split is required before any optimization inside `append_visible` would be honest.
- The exact proof question is: on the ASCII rain workload, which current-code subphase dominates `append_visible`?

One exact next slice:

- Slice type: proof only, no optimization.
- Allowed files:
- `howl-render/src/text/direct_normal.zig`

- Exact required shape:
- Keep the proof local to `direct_normal.zig` only.
- Add temporary narrow timing logs that split `append_visible_ns` into:
- `source_candidate_ns`
- `append_renderable_ns`
- Keep the existing counters for:
- `visible_cells_scanned`
- `included_normal_cells`
- `direct_success_calls`
- `fallback_reject_calls`
- `raster_req_count_total`
- Add one more exact count field:
- `append_renderable_calls`
- Do not change behavior.

- Exact tests:
- from `howl-render`, run `zig build test:abi`
- from `howl-render`, run `zig build test:unit`

- Exact benchmark/proof requirements:
- rerun `python3 utils/tools/rain-bench/benchmark_terminals.py --build`
- append one fresh proof section to `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log` or write one exact new proof log path and record it
- the proof output must identify which of these dominates `append_visible` on ASCII rain:
- `source_candidate`
- `append_renderable`
- and must report `append_renderable_calls` and `raster_req_count_total`

- Exact non-goals:
- no optimization yet
- no instrumentation cleanup yet
- no edits outside `howl-render/src/text/direct_normal.zig`
- no ABI changes
- no benchmark harness changes

- Exact stop conditions:
- stop if splitting `append_visible` requires edits outside `howl-render/src/text/direct_normal.zig`
- stop if the new proof fails to isolate one dominant `append_visible` subphase
- stop if the counters cease to describe the same workload path, for example if `fallback_reject_calls` stops being zero on the ASCII rain run

- Exact receipt fields needed for acceptance:
- orchestrator session id: `orch-2026-06-14-ascii-rain-performance-01`
- researcher session id: `research-2026-06-14-ascii-rain-performance-01`
- reviewer session id: `review-2026-06-14-ascii-rain-performance-01`
- coder session id
- benchmark command
- benchmark artifact path
- proof log artifact path
- exact proof location lines
- exact temporary instrumentation files and lines
- measured before
- measured after
- dominant `append_visible` subphase verdict
- `append_renderable_calls`
- `raster_req_count_total`
- commit-hash receipt status

Risks:

- The hot owner is now narrow enough that the next proof slice must not balloon into multi-file instrumentation again.
- If `append_renderable` dominates, the next optimization slice may still need a second planning pass because that helper mixes face resolution, glyph lookup, and atlas reserve.
- If `source_candidate` dominates, the next optimization slice will likely target the publication candidate scan and support checks rather than rendering proper.

Proof gaps:

- We still do not know whether `append_visible` is mostly candidate construction or append/renderable work.
- We still do not know how much of `append_renderable` is face resolution vs glyph lookup vs atlas reserve.
- We do not yet have a measured per-call count for `appendRenderable(...)` on this workload.

Readiness judgment:

- Ready for one more local proof-only slice.
- Not ready for an optimization slice yet.
- This remains a local runtime-proof-first sprint, not a structural blocker.

## Post-Proof-Slice-5 Interpretation

Status:

- Proof-only slice 5 completed.
- The newly proved dominant `append_visible(...)` subphase is `source_candidate(...)` / publication candidate work inside `direct_normal.zig`.
- This is now optimization-ready as a local slice.

Sources read in order for this pass:

1. `loop/flow.md`
2. `loop/orcestrator.md`
3. `loop/researcher.md`
4. `loop/reviewer.md`
5. `loop/coder.md`
6. `loop/researcher.md` again as active role contract
7. `sprints/current.txt`
8. `loops/ascii-rain-performance-live-loop.txt`
9. `research/2026-06-14-ascii-rain-performance-plan.md`
10. current proof receipts from `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log:1771-1775`
11. `reference-index.md`
12. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
13. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
14. `howl-render/src/text/direct_normal.zig:286-380`
15. `howl-render/src/text/direct_normal.zig:482-531`
16. `howl-render/src/text/session.zig:56-115`
17. `howl-render/src/text/raster/atlas.zig:54-95`
18. `howl-render/src/text/surface_preparer.zig:1002-1245`
19. `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:41-88`
20. `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:783-879`
21. `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:57-69`

Exact files and line references:

- Proof receipt for this pass: `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log:1771-1775`.
- Current `appendVisible(...)` loop owner: `howl-render/src/text/direct_normal.zig:290-347`.
- Current `sourceCandidate(...)` owner: `howl-render/src/text/direct_normal.zig:356-368`.
- Current publication candidate path: `howl-render/src/text/direct_normal.zig:370-380`, `383-431`.
- Current append/renderable path: `howl-render/src/text/direct_normal.zig:482-531`.
- Current face-resolution owner: `howl-render/src/text/session.zig:62-115`.
- Current atlas reservation owner: `howl-render/src/text/raster/atlas.zig:54-95`.
- Current publication direct-path proof roots: `howl-render/src/text/surface_preparer.zig:1002-1245`.

Measured subphase interpretation:

- The new proof isolates `source_candidate` as the dominant subphase inside `append_visible`.
- Proof receipts:
- `append_visible_ms=3498.274`
- `source_candidate_ms=1403.958`
- `append_renderable_ms=910.988`
- `append_scene_rects_ms=221.698`
- `finish_scene_ms=56.368`
- `append_renderable_calls=29424087`
- `visible_cells_scanned=29424087`
- `included_normal_cells=29424087`
- `direct_success_calls=2368`
- `fallback_reject_calls=0`
- `raster_req_count_total=1197`
- Relative reading from the proved run:
- `source_candidate` is about `40.1%` of `append_visible_ms`.
- `append_renderable` is about `26.0%` of `append_visible_ms`.
- The remaining gap inside `append_visible` is loop/control overhead, but the single largest measured named subphase is `source_candidate`.
- The workload remains fully on the publication fast path with zero fallback rejects and one included normal cell per scanned cell.
- That is enough proof to target publication candidate work first, because the hot path is now exact, local, and owner-true.

Current-code facts for `source_candidate`:

- On this workload, `appendVisible(...)` never uses the reject path and never falls back out of the publication fast path.
- `sourceCandidate(...)` for publication sources first routes through `publicationCandidate(...)` (`direct_normal.zig:356-364`, `370-380`).
- `publicationCandidate(...)` does all of this per cell on the hot path:
- loads the source cell
- runs `publicationCellSupported(...)` checks (`direct_normal.zig:383-396`)
- builds a full `RenderableText` via `publicationRenderableText(...)` (`direct_normal.zig:399-425`)
- runs `cluster.includeDamage(...)` even though the workload proves every scanned cell is included (`direct_normal.zig:375-376`)
- constructs a `Candidate` wrapper that is immediately consumed by `appendVisible(...)`
- Because `fallback_reject_calls=0` and `included_normal_cells == visible_cells_scanned`, the hot path is not exercising the negative-space branches that justify the generic publication candidate machinery.
- `appendRenderable(...)` is still material, but smaller than `source_candidate`, and it contains its own distinct owners: face resolution, glyph lookup, atlas reserve, raster miss enqueue, and sprite append (`direct_normal.zig:482-531`).
- The best next local move is therefore to remove avoidable candidate-construction/classification work before touching glyph/atlas behavior.

Relevant Alacritty/reference facts:

- Alacritty borrows terminal render content and streams cells directly into rendering (`display/content.rs:41-88`, `display/mod.rs:783-879`, `renderer/text/mod.rs:57-69`).
- The closest reference pressure here is to reduce intermediate per-cell packaging before draw, not to add more wrappers.
- Current Howl publication fast path still constructs a `PublicationCandidate`, then a `Candidate`, then hands that to `appendRenderable(...)`. That is exactly the kind of extra hot-path ceremony Alacritty pressure argues against.

Exact next-step recommendation:

- Continue locally with one optimization slice.
- The best next local move is to specialize the publication fast path inside `appendVisible(...)` so supported publication cells are appended directly, without routing through `sourceCandidate(...)` / `publicationCandidate(...)` / `Candidate` construction on the proved ASCII rain path.

One exact next slice:

- Slice type: optimization.
- Allowed files:
- `howl-render/src/text/direct_normal.zig`

- Exact required shape:
- Keep all changes inside `direct_normal.zig`.
- Add one publication-specific hot-path branch inside `appendVisible(...)` for `source == .publication` with `policy == .require_all_normal`.
- That branch must:
- read the publication cell directly
- preserve the current unsupported/reject behavior from `publicationCellSupported(...)`
- preserve current damage filtering semantics
- append directly into the existing direct-normal scratch/output path without constructing `PublicationCandidate` / `Candidate` wrapper values for supported cells
- keep the current fallback/reject semantics unchanged for unsupported cells
- keep `appendRenderable(...)` as the actual draw-append owner for now
- do not change ABI, renderer contracts, or non-publication sources

- Exact tests:
- from `howl-render`, run `zig build test:abi`
- from `howl-render`, run `zig build test:unit`
- keep existing direct-normal owner tests green:
- `howl-render/src/text/direct_normal.zig`: `test "direct normal publication zero codepoint is a fast candidate"`
- `howl-render/src/text/direct_normal.zig`: `test "direct normal publication keeps unsupported non-printables on generic fallback"`
- keep existing publication direct-path tests green:
- `howl-render/src/text/surface_preparer.zig`: `test "text preparation publication ascii stays on direct normal path"`
- `howl-render/src/text/surface_preparer.zig`: `test "text preparation publication styled indexed ascii stays on direct normal path"`
- `howl-render/src/text/surface_preparer.zig`: `test "text preparation publication non inverse indexed ascii stays on direct normal path"`
- `howl-render/src/text/surface_preparer.zig`: `test "text preparation publication zero codepoint stays on direct normal path without sprite draw"`
- `howl-render/src/text/surface_preparer.zig`: `test "text preparation publication unsupported space and rgb keep fallback scratch clean"`
- `howl-render/src/text/surface_preparer.zig`: `test "text preparation publication tab stays on generic fallback without partial direct scratch"`
- `howl-render/src/text/surface_preparer.zig`: `test "text preparation publication other control stays on generic fallback without partial direct scratch"`

- Exact benchmark/proof requirements:
- rerun `python3 utils/tools/rain-bench/benchmark_terminals.py --build`
- rerun the current proof-only receipts sufficiently to compare before/after at the same owner path
- required measured outputs:
- `source_candidate_ms`
- `append_visible_ms`
- total `prepare_ms`
- Howl FPS / p50 / p95

- Exact non-goals:
- no changes outside `direct_normal.zig`
- no glyph lookup optimization yet
- no atlas/raster optimization yet
- no fallback/publication ABI expansion
- no instrumentation cleanup yet

- Exact stop conditions:
- stop if preserving unsupported publication fallback semantics requires edits outside `direct_normal.zig`
- stop if the specialization weakens current negative-space behavior for unsupported publication cells
- stop if benchmark and proof both fail to improve the proved `source_candidate` / `append_visible` hot path

- Exact receipt fields needed for acceptance:
- orchestrator session id: `orch-2026-06-14-ascii-rain-performance-01`
- researcher session id: `research-2026-06-14-ascii-rain-performance-01`
- reviewer session id: `review-2026-06-14-ascii-rain-performance-01`
- coder session id
- exact changed files and line references
- verification command list and results
- benchmark command
- benchmark artifact path
- proof log artifact path
- exact proof location lines
- measured before
- measured after
- verdict on `source_candidate_ms`, `append_visible_ms`, and total `prepare_ms`
- commit-hash receipt status

Risks:

- The measured gap between `source_candidate_ms` and `append_renderable_ms` is meaningful but not enormous; a win here may expose `append_renderable(...)` next.
- If much of `source_candidate_ms` is compiler-resistant branch/control overhead rather than wrapper construction, the gain may be smaller than hoped.
- Proof instrumentation continues to perturb absolute benchmark numbers, so relative owner-path movement must carry the decision.

Proof gaps:

- We still do not know how much of `source_candidate_ms` is `publicationCellSupported(...)` checks versus `publicationRenderableText(...)` construction.
- We do not yet know whether the best follow-up after this slice would be glyph/atlas work inside `appendRenderable(...)`.
- We now have a post-optimization measurement for this exact owner from slice 6, but cleanup slice 7 is the current active review step before a fresh next-bottleneck proof is authorized.

Readiness judgment:

- Optimization slice 6 is accepted.
- Cleanup slice 7 is the active execution/review step before any next proof or optimization slice.
- This remains a local runtime-proof-first sprint, not a structural blocker.

## Post-Cleanup Reproof Interpretation

Status:

- Optimization slice 6 and cleanup slice 7 are accepted.
- Cleaned-code proof slice 8 re-proved the same direct-normal bottleneck on current code.
- Benchmark variance does not change the accountability move because the cleaned proof remains stable on the same owner path.

Sources read in order for this pass:

1. `loop/flow.md`
2. `loop/orcestrator.md`
3. `loop/researcher.md`
4. `loop/reviewer.md`
5. `loop/coder.md`
6. `loop/researcher.md` again as active role contract
7. `sprints/current.txt`
8. `loops/ascii-rain-performance-live-loop.txt`
9. `research/2026-06-14-ascii-rain-performance-plan.md`
10. current cleaned-code proof receipts from `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log:2593,2672`
11. `reference-index.md`
12. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
13. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
14. `howl-render/src/text/direct_normal.zig:296-355`
15. `howl-render/src/text/direct_normal.zig:413-449`
16. `howl-render/src/text/direct_normal.zig:482-531`
17. `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:41-88`
18. `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:783-879`
19. `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:57-69`

Exact files and line references:

- Cleaned-code proof receipts: `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log:2593`, `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log:2672`.
- Current publication fast-path branch in `appendVisible(...)`: `howl-render/src/text/direct_normal.zig:296-355`.
- Current supported publication hot path statements: `howl-render/src/text/direct_normal.zig:301-315`.
- Current publication support predicate owner: `howl-render/src/text/direct_normal.zig:440-449`.
- Current publication renderable construction owner: `howl-render/src/text/direct_normal.zig:451-479`.
- Current current append/renderable owner: `howl-render/src/text/direct_normal.zig:482-531`.

Measured subphase interpretation:

- The cleaned-code re-proof keeps the same dominant named subphase as before cleanup: `source_candidate(...)` / publication candidate work.
- Receipt at line `2593`:
- `append_visible_ms=3419.669`
- `source_candidate_ms=1286.235`
- `append_renderable_ms=958.277`
- `append_scene_rects_ms=180.991`
- `finish_scene_ms=22.913`
- `raster_req_count_total=522`
- Receipt at line `2672` preserves the same ordering:
- `append_visible_ms=3631.964`
- `source_candidate_ms=1401.937`
- `append_renderable_ms=1031.574`
- `append_scene_rects_ms=193.476`
- `finish_scene_ms=101.068`
- `append_renderable_calls=29420436`
- `visible_cells_scanned=29420436`
- `included_normal_cells=29420436`
- `direct_success_calls=2368`
- `fallback_reject_calls=0`
- Across both cleaned checkpoints, `source_candidate_ms > append_renderable_ms`, and the workload remains fully on the direct-normal fast path with zero fallback rejects.
- That is strong enough to keep `source_candidate(...)` as the right next local target.
- But it is not yet fine-grained enough to choose the next optimization inside that owner honestly, because the current `source_candidate_ms` still mixes three distinct costs on the supported-cell path:
- `publicationCellSupported(...)`
- `publicationRenderableText(...)`
- `cluster.includeDamage(...)`

Current-code facts for `source_candidate`:

- Slice 6 already removed `PublicationCandidate` / `Candidate` wrapper construction from the supported publication hot path.
- The current supported publication path in `appendVisible(...)` now does exactly this per scanned cell (`direct_normal.zig:301-315`):
- load the publication cell
- run `publicationCellSupported(...)`
- build `RenderableText` through `publicationRenderableText(...)`
- run `cluster.includeDamage(...)`
- call `appendRenderable(...)`
- Because `fallback_reject_calls=0` and `included_normal_cells == visible_cells_scanned`, the generic fallback path is cold on this workload.
- Therefore the remaining hot `source_candidate_ms` is no longer wrapper churn; it is the real cost of support checks, renderable construction, and damage acceptance on the proved publication fast path.

Relevant Alacritty/reference facts:

- Alacritty still borrows content and streams cells directly into rendering with minimal intermediate packaging (`display/content.rs:41-88`, `display/mod.rs:783-879`, `renderer/text/mod.rs:57-69`).
- That pressure still favors reducing per-cell hot-path work in `source_candidate(...)`, but the current proof does not yet say whether the best next move is support-check specialization, renderable construction tightening, or damage filtering bypass.

Exact next-step recommendation:

- Continue locally.
- `source_candidate(...)` remains the right next local target.
- One more proof split is still required before another optimization would be honest.

One exact next slice:

- Slice type: proof only, no optimization.
- Allowed files:
- `howl-render/src/text/direct_normal.zig`

- Exact required shape:
- Keep the proof local to `direct_normal.zig` only.
- Add temporary narrow timing logs on the supported publication hot path inside `appendVisible(...)` that split current `source_candidate_ns` into:
- `publication_cell_supported_ns`
- `publication_renderable_text_ns`
- `publication_damage_include_ns`
- Keep the existing counters for:
- `visible_cells_scanned`
- `included_normal_cells`
- `direct_success_calls`
- `fallback_reject_calls`
- `append_renderable_calls`
- `raster_req_count_total`
- Do not change behavior.

- Exact tests:
- from `howl-render`, run `zig build test:abi`
- from `howl-render`, run `zig build test:unit`

- Exact benchmark/proof requirements:
- rerun `python3 utils/tools/rain-bench/benchmark_terminals.py --build`
- append one fresh proof section to `/tmp/opencode/coder-2026-06-14-ascii-rain-performance-proof-01-surface.log` or write one exact new proof log path and record it
- the proof output must identify which of these dominates current cleaned-code `source_candidate` work on ASCII rain:
- `publication_cell_supported`
- `publication_renderable_text`
- `publication_damage_include`

- Exact non-goals:
- no optimization yet
- no instrumentation cleanup yet
- no edits outside `howl-render/src/text/direct_normal.zig`
- no ABI changes
- no benchmark harness changes

- Exact stop conditions:
- stop if splitting cleaned-code `source_candidate` requires edits outside `howl-render/src/text/direct_normal.zig`
- stop if the new proof fails to isolate one dominant `source_candidate` subphase
- stop if the counters cease to describe the same workload path, for example if `fallback_reject_calls` stops being zero on the cleaned-code run

- Exact receipt fields needed for acceptance:
- orchestrator session id: `orch-2026-06-14-ascii-rain-performance-01`
- researcher session id: `research-2026-06-14-ascii-rain-performance-01`
- reviewer session id: `review-2026-06-14-ascii-rain-performance-01`
- coder session id
- exact changed files and line references
- verification command list and results
- benchmark command
- benchmark artifact path
- proof log artifact path
- exact proof location lines
- measured before
- measured after
- dominant cleaned-code `source_candidate` subphase verdict
- commit-hash receipt status

Risks:

- The cleaned proof is stable enough for planning, but benchmark variance remains too noisy to override owner-path proof.
- If `publication_damage_include_ns` dominates, the next optimization may need to question full-damage filtering on this workload instead of support checks or renderable construction.
- If `publication_renderable_text_ns` dominates, the next optimization will likely stay local to publication renderable construction inside `direct_normal.zig`.

Proof gaps:

- We still do not know whether the cleaned-code `source_candidate` bottleneck is mostly support checks, renderable construction, or damage include filtering.
- We do not yet know whether the best follow-up after that split would still be inside `source_candidate(...)` or would shift to `appendRenderable(...)`.

Readiness judgment:

- Ready for one more local proof-only slice.
- Not ready for another optimization slice yet.
- This remains a local runtime-proof-first sprint, not a structural blocker.
