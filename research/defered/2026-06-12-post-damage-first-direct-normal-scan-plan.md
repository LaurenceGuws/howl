Post-damage-first direct-normal scan plan

Historical authority: this file was the active direct-normal planning artifact until superseded by the renderer-shape sprint pivot on 2026-06-12.
Why superseded: user direction changed from ASCII-rain micro-bottleneck work to shrinking `howl-render` and porting Alacritty render/API shape into Zig.
Must not be used for: current worker seeding, current reviewer gate, or current render API planning.

Date: 2026-06-12.
Status: active researcher target.
Role owner: researcher.
Orchestrator session id: `orch-2026-06-11-ascii-rain-honest-performance-02`.
Researcher session id: `research-2026-06-12-post-damage-first-direct-normal-scan-01`.
Reviewer session id: `review-2026-06-12-post-damage-first-direct-normal-scan-01`.
Planning commit-hash receipt: pending.
Deferred status: not accepted as the next live plan; deferred because user direction changed, not because the research was completed.

Preload receipt:

- Role: researcher.
- Sources read in order:
  - `/home/home/personal/projects/howl/loop/flow.md`
  - `/home/home/personal/projects/howl/loop/orcestrator.md`
  - `/home/home/personal/projects/howl/loop/researcher.md`
  - `/home/home/personal/projects/howl/loop/reviewer.md`
  - `/home/home/personal/projects/howl/loop/coder.md`
  - `/home/home/personal/projects/howl/sprints/defered/2026-06-11-ascii-rain-honest-performance-sprint.md` at defer time this was superseded active authority
  - `/home/home/personal/projects/howl/loops/defered/ascii-rain-live-loop.txt`
  - `/home/home/personal/projects/howl/research/defered/2026-06-12-post-damage-first-direct-normal-scan-plan.md`
  - `/home/home/personal/projects/howl/reference-index.md`
  - `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
  - `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- Current proof receipts:
  - failed slice summary: `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-090917-ascii/summary.json`
  - failed slice timing log: `/tmp/opencode/howl-render-debug-control.log`
  - accepted 3-second baseline: `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-084336-ascii/summary.json`
  - accepted 10-second baseline: `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-084355-ascii/summary.json`
  - ranking-only child-cost receipt retained as navigation: `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-025340-ascii/summary.json`
- Execution authorized:
  - research and planning only; no implementation from this pass.

Problem statement:

- The damage-first publication fast-candidate slice passed correctness but failed timing and was not committed.
- The final failed timing proof reported `direct_normal_scan_avg_us=509`, worse than the accepted baseline `311`.
- The accepted product baseline remains root `7bd26ba` plus `howl-render` `e391d92`, with Howl `120.3 fps` vs Alacritty `1003.65 fps`.
- The next research task is to explain the remaining direct-normal scan cost without re-promoting the failed damage-first ordering idea.

Compact anchor map:

- TigerBeetle style pressure:
  - `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:90-113` requires explicit control flow, bounded work, and assertions on preconditions/invariants.
  - `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:249-264` requires control-plane/data-plane separation and hot-loop extraction with primitive arguments.
  - `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:96-100` says experiments confirm or disprove a mental model rather than invent the model after the fact.
- Alacritty renderable-content pressure:
  - `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:24-28` keeps one owner over renderable content preparation.
  - `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:156-183` folds scan, filtering, and renderable-cell construction into one iterator instead of a separate pre-damage planning layer.
  - `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:187-207` keeps the hot renderable cell shape direct and explicit.
- Current Howl owner seam:
  - `howl-render/src/session/text.zig:220-270` proves publication prepare stays inside `TextSession.prepareSurface` and first tries `preparePublicationWithSessionOptions` before generic fallback.
  - `howl-render/src/text/frame_preparer.zig:155-178` proves publication direct-normal is the owner seam for the fast path and that generic fallback remains the shared shaped-scene owner.
  - `howl-render/src/text/direct_normal.zig:110-150` proves `direct_normal_scan_us` measures `appendVisible` only.
  - `howl-render/src/text/direct_normal.zig:195-240` proves the scan bucket is the `appendVisible` loop, not just damage rejection.
  - `howl-render/src/text/direct_normal.zig:263-336` proves supported publication cells already build direct-normal renderables without generic cluster classification.
  - `howl-render/src/text/direct_normal.zig:422-470` proves the same scan bucket still pays renderable append, face resolution, glyph lookup, atlas reserve, and sprite-draw append per visible cell.
  - `howl-render/src/text/shape/cluster.zig:576-657` proves damage inclusion is a small boolean filter and goes full-include when damage is full.

Current-code facts:

- The accepted baseline receipt still uses the same dense ASCII harness shape as the failed slice: `320x120`, `flush_every=1`, `metrics_every=100` (`20260612-084336-ascii/summary.json:32-43`, `20260612-090917-ascii/summary.json:32-43`).
- The accepted product baseline is Howl `120.3 fps` vs Alacritty `1003.65 fps` (`20260612-084355-ascii/summary.json:70-118`).
- The failed damage-first slice only reached Howl `70.4 fps` in the 3-second gate (`20260612-090917-ascii/summary.json:70-82`).
- The failed timing log shows the regression stayed in the scan bucket, not the later buckets: `direct_normal_scan_avg_us=509`, `direct_normal_backgrounds_avg_us=27`, `direct_normal_decorations_avg_us=44`, `direct_normal_raster_avg_us=39`, `owner_create_avg_us=297` (`/tmp/opencode/howl-render-debug-control.log:13-15`).
- `direct_normal.prepare` measures `scan_us` only around `appendVisible` (`howl-render/src/text/direct_normal.zig:121-150`). That means the remaining debt is everything inside `appendVisible`, not just candidate gating.
- `appendVisible` still iterates every source cell, calls `sourceCandidate`, and for included candidates calls `appendRenderable` (`howl-render/src/text/direct_normal.zig:210-239`).
- For publication input, `sourceCandidate` already has a specialized publication path. It does not fall through to generic publication mapping unless the cell is unsupported (`howl-render/src/text/direct_normal.zig:249-274`).
- `publicationCandidate` already proves the supported subset is single-cell, non-combining, no continuation, no links, no selection, no strikethrough, no custom underline color, and default or indexed colors only (`howl-render/src/text/direct_normal.zig:276-289`).
- Even on that specialized path, the scan bucket still builds a full `cluster.RenderableText` and full `contract.RenderableCell` metadata before it does any draw work (`howl-render/src/text/direct_normal.zig:292-336`).
- The hot scan bucket then still pays, per included cell, for:
  - appending a `RenderableCell` (`howl-render/src/text/direct_normal.zig:430`)
  - face resolution (`howl-render/src/text/direct_normal.zig:437-440`, `548-560`)
  - glyph lookup (`howl-render/src/text/direct_normal.zig:442`)
  - sprite-key hashing and atlas reserve (`howl-render/src/text/direct_normal.zig:443-454`)
  - row/col coordinate math and sprite-draw append (`howl-render/src/text/direct_normal.zig:456-469`).
- Damage-first cannot remove those costs on dirty cells; it only tries to avoid candidate work for skipped cells. The failed slice proves that is not the winning lever on the live workload because the bucket regressed instead of shrinking.
- `cluster.includeDamage` is only a boolean `DamageFilter.includeSpan` check (`howl-render/src/text/shape/cluster.zig:576-578`). It is not source-backed as the dominant residual cost.
- The earlier ranking-only child-cost proof also pointed at candidate and append work inside scan rather than post-scan passes: `scan_generic_candidate_avg_us=767`, `scan_publication_candidate_avg_us=276`, `scan_append_face_avg_us=249`, `scan_damage_avg_us=236` (`loops/ascii-rain-live-loop.txt:770-772`). That receipt is navigation only, but the current source still matches the same owner split.

Reference facts:

- Alacritty keeps renderable-content scan and cell conversion inside one owner iterator and skips only obviously empty or spacer cells in that hot owner (`utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:156-183`).
- Alacritty does not introduce a separate damage-first publication owner ahead of renderable-cell construction in this seam; the same owner computes renderable facts directly (`utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:24-28`, `187-207`).
- TigerBeetle pressure rejects a speculative redesign when the current hot loop can be sharpened directly in its true owner and proved with assertions/tests (`utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:90-113`, `249-264`).

Explanation of the remaining direct-normal scan cost:

- The expensive residual work is not the damage predicate.
- The expensive residual work is the supported-publication per-cell hot loop that still constructs full renderable metadata and then does glyph lookup, atlas reserve, and sprite-draw setup inside `appendVisible`.
- The zero-codepoint and styled-ASCII wins removed some fallback and draw waste, but they did not remove the per-cell publication conversion and append path for the still-dominant printable ASCII cells.
- The failed damage-first attempt targeted the wrong lever for the live workload. It tried to skip more work before candidate construction, but the workload still spends most of its scan bucket on cells that survive damage filtering and continue into `appendRenderable`.
- The truthful next step is to sharpen the supported publication append path itself, not to add another damage-order experiment, not to move owners, and not to touch host or benchmark code.

Owner roles and proposed shape:

- Owner seam:
  - stay inside `howl-render/src/text/direct_normal.zig` with adjacent proof in `howl-render/src/text/frame_preparer.zig` tests only.
- Proposed shape:
  - keep `PublicationCandidate` tri-state semantics exactly as they are now: `candidate|skip|unsupported`.
  - keep the generic fallback path unchanged for unsupported publication cells.
  - add a dedicated supported-publication append helper inside `direct_normal.zig` that reuses the already-proved publication subset invariants and appends the normal renderable/draw state without rebuilding an intermediate `cluster.RenderableText` owner shape.
  - keep glyph lookup and atlas reserve in the same owner; do not move them to host, atlas owner, or a new helper file.
  - keep direct-normal responsible for the draw/no-draw distinction between printable ASCII and zero codepoint.

Exact next worker slice:

- Slice name:
  - `direct-normal-publication-append-fast-path`
- Coder session id:
  - pending orchestrator assignment.
- Allowed files:
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig` for owner-local tests only
- Required shape:
  - keep the publication fast-candidate boundary inside `direct_normal.Source.publication` only.
  - do not touch raw-cell, prepared-cell, input, host, GL, VT, ABI, owner-create, sprite cache, or benchmark owners.
  - replace the current supported-publication include path with a direct append helper that:
    - asserts the publication cell still satisfies the supported subset.
    - appends the equivalent `RenderableCell` facts needed by backgrounds/decorations.
    - uses the already-known publication codepoint and style facts to avoid rebuilding a temporary `cluster.RenderableText` wrapper for the supported subset.
    - keeps zero-codepoint as background-only and printable ASCII as sprite-producing.
    - is infallible for the already-supported subset; unsupported publication cells must never enter the helper.
    - preserves identical fallback behavior by leaving unsupported publication cells on the existing generic path before the helper is called.
  - keep all behavior in one owner file unless a helper is required to stay under the function-shape and assertion pressure.
- Required assertions:
  - assert the direct helper only receives publication cells that satisfy `publicationCellSupported`.
  - assert non-zero direct-helper codepoints remain printable ASCII.
  - assert zero codepoint produces no sprite draw append.
  - assert supported publication renderables stay single-cell and normal-class equivalent.
  - assert the direct helper has no unsupported/decline path; unsupported publication cells must remain outside the helper and continue through the existing generic fallback owner.
- Required tests:
  - `/home/home/personal/projects/howl/howl-render`: `zig build test:unit`
  - `/home/home/personal/projects/howl/howl-linux-host`: `zig build install -Doptimize=ReleaseFast`
  - `/home/home/personal/projects/howl/utils/tools/rain-bench`: `zig build --release=fast stress:rain:build`
  - `/home/home/personal/projects/howl`: `env HOWL_RENDER_DEBUG_TIMING=1 python3 utils/tools/rain-bench/benchmark_terminals.py --duration 3 --mode ascii --terminals howl 2> /tmp/opencode/howl-render-debug-control.log`
  - `/home/home/personal/projects/howl`: `python3 utils/tools/rain-bench/benchmark_terminals.py --duration 10 --mode ascii --terminals howl alacritty`
  - owner-local proof that must stay green in `frame_preparer.zig` / `direct_normal.zig`:
    - `text preparation publication ascii stays on direct normal path`
    - `text preparation publication styled indexed ascii stays on direct normal path`
    - `text preparation publication zero codepoint stays on direct normal path without sprite draw`
    - `text preparation publication unsupported space and rgb keep fallback scratch clean`
    - `text preparation publication tab stays on generic fallback without partial direct scratch`
    - `direct normal publication zero codepoint is a fast candidate`
    - `direct normal publication keeps unsupported non-printables on generic fallback`
  - required new owner-local tests:
    - supported printable ASCII publication cell produces the same asserted facts as before: one sprite draw, one raster output, zero shaped/resolved runs, identical `first_cell`, identical sprite RGBA, and identical background RGBA for a fixed indexed/inverse fixture.
    - supported styled indexed zero-codepoint publication cell still produces no sprite draw, zero raster outputs, one background draw, one decoration draw when underlined, zero shaped/resolved runs, identical background RGBA, and identical decoration RGBA/style facts for the fixed indexed fixture.
- Non-goals:
  - no damage-first reorder retry.
  - no temporary instrumentation.
  - no host/runtime/event-loop changes.
  - no benchmark-wrapper or workload edits.
  - no owner-create, atlas cache, rasterizer, or sprite-emitter work.
  - no broad publication-source redesign.
- Stop conditions:
  - stop if the truthful change needs any file outside the two allowed files.
  - stop if preserving `candidate|skip|unsupported` requires a new owner or bucket struct.
  - stop if supported publication cells cannot keep exact fallback/no-partial-scratch guarantees.
  - stop if the 3-second rerun does not beat `direct_normal_scan_avg_us < 311`.
  - stop if the rerun improves scan time but exposes a correctness regression in background, decoration, or zero-codepoint behavior.
- Receipt fields required from worker:
  - coder session id.
  - files changed.
  - exact commands run.
  - exact receipt paths.
  - quoted timing lines from `/tmp/opencode/howl-render-debug-control.log`.
  - before/after `direct_normal_scan_avg_us`, `direct_normal_avg_us`, `direct_normal_raster_avg_us`, and `owner_create_avg_us`.
  - commit-hash handoff status pending orchestrator closure.
- Timing proof expectations:
  - minimum gate: 3-second `direct_normal_scan_avg_us < 311`.
  - if that gate passes, required product gate: 10-second Howl FPS must beat `120.3` while Alacritty remains a comparison run, not a target to modify.

Sprint scratchpad:

- The failed damage-first slice falsified the idea that dirty rejection order is the main remaining lever.
- The next slice must attack supported-publication append work inside the already-proved direct-normal owner.
- The worker should not spend the slice budget re-measuring with new timers or broadening into render-surface emission because the current receipts already isolate the loser: scan stays above raster and owner-create even in the failure log.

Risks:

- The scan bucket name is broad. The worker must avoid claiming the entire `311` gap is from one sub-step without proof.
- The direct helper can accidentally diverge from generic fallback semantics for inverse, dim alpha, indexed colors, or zero-codepoint blank handling if assertions/tests are weak.
- If the performance win depends mostly on eliminating `glyph_lookup` or `atlas.reserve`, the direct append refactor may improve clarity more than timing.

Proof gaps:

- No current non-perturbing child-cost split exists inside the accepted `311` baseline. The next slice is still source-backed because the code proves where the scan bucket lives, but the exact share between metadata construction and glyph/atlas work remains approximate.
- If the direct append fast path misses the timing gate, the next planning step will need a new proof surface focused specifically on `glyph_lookup` and atlas reserve inside `appendRenderable`, not another damage-order experiment.

Readiness judgment:

- Ready.
- No correctness blocker or vague owner bucket was found that would justify stopping the sprint now.
- The reviewer-acceptable next slice is to optimize supported-publication append work inside `direct_normal`, with no owner drift and with the explicit stop conditions above.
