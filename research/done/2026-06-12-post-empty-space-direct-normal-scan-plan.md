Post-empty-space direct-normal scan plan

Date: 2026-06-12.
Status: active researcher target.
Role owner: researcher.
Orchestrator session id: `orch-2026-06-11-ascii-rain-honest-performance-02`.
Researcher session id: `research-2026-06-12-post-empty-space-direct-normal-scan-01`.
Reviewer session id: pending.
Planning commit-hash receipt: pending.

Preload receipt:

- Role: researcher
- Active sprint:
  - `/home/home/personal/projects/howl/sprints/2026-06-11-ascii-rain-honest-performance-sprint.md`
- Active loop:
  - `/home/home/personal/projects/howl/loops/ascii-rain-live-loop.txt`
- Active research:
  - `/home/home/personal/projects/howl/research/2026-06-12-post-empty-space-direct-normal-scan-plan.md`
- Current failed-slice proof receipts:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-023806-ascii/summary.json`
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-023930-ascii/summary.json`
  - `/tmp/opencode/howl-render-debug-control.log`
- Accepted baseline receipts:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-021917-ascii/summary.json`
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-021928-ascii/summary.json`
- Execution authorized:
  - research and planning only; no implementation from this pass

Problem statement:

- The semantic-empty space fast-candidate slice passed correctness/build checks but hit the accepted timing stop and was not committed.
- The final failed timing proof reported `direct_normal_scan_avg_us=890`, worse than the accepted styled-ASCII baseline `811`.
- The current accepted tree remains root `ad7195f` plus `howl-render` `98bb85a`, with Howl `60.26 fps` vs Alacritty `981.84 fps`.
- The next research task is to source-pin remaining direct-normal scan debt without re-promoting the failed empty-space idea.

Research requirements:

- Read the live workflow, active loop, current sprint index, this file, TigerBeetle readings, and source/reference anchors before writing a plan.
- Explain what remains expensive in direct-normal scan after styled ASCII fast-candidate and after the failed semantic-empty experiment.
- Produce one reviewer-acceptable worker slice with exact allowed files, shape, tests, non-goals, stop conditions, assertions, receipt paths, and timing proof expectations.
- Do not drift into host, GL, benchmark-wrapper, PTY, VT, ABI, owner-create, sprite cache, fresh rollback, payload initialization, or temporary instrumentation unless current source proves it is required.
- Stop and report if the truthful next step exposes a big correctness issue or vague bucket.

Sources read in order:

- `/home/home/personal/projects/howl/loop/flow.md`
- `/home/home/personal/projects/howl/loop/orcestrator.md`
- `/home/home/personal/projects/howl/loop/researcher.md`
- `/home/home/personal/projects/howl/loop/reviewer.md`
- `/home/home/personal/projects/howl/loop/coder.md`
- `/home/home/personal/projects/howl/sprints/current.txt`
- `/home/home/personal/projects/howl/loops/ascii-rain-live-loop.txt`
- `/home/home/personal/projects/howl/research/2026-06-12-post-empty-space-direct-normal-scan-plan.md`
- `/home/home/personal/projects/howl/reference-index.md`
- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
- Adjacent source required to explain the current proof seam:
  - `/home/home/personal/projects/howl/howl-render/src/session/text.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/vt.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/raster/cache.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/font/session.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/font/provider.zig`

Compact anchor map:

- Workflow authority: `loop/flow.md:22-41` requires accepted planning artifacts to carry exact files, shape, tests, non-goals, stop conditions, session ids, and receipts; `loop/researcher.md:60-75` requires source-backed evidence, anchor map, risks, proof gaps, and readiness judgment.
- TigerBeetle proof pressure: `TIGER_STYLE.md:96-113` requires bounded loops and assertions; `TIGER_STYLE.md:136-140` requires positive and negative-space proof; `TIGER_STYLE.md:161-175` requires central control flow and small leaf helpers; `TIGER_STYLE.md:231-257` requires back-of-envelope performance sketches before guessing.
- Current Howl owner seam: `direct_normal.prepare` owns the direct-normal scan timing, scratch reset, direct-scene child passes, and product return in `howl-render/src/text/direct_normal.zig:110-151`.
- Current publication scan seam: `appendVisible` walks every source cell and calls `sourceCandidate` once per index in `direct_normal.zig:195-240`; `sourceCandidate` first attempts the publication fast candidate and falls back to generic source mapping on unsupported publication cells in `direct_normal.zig:249-260`.
- Accepted fast candidate seam: `publicationCandidate` maps supported styled printable ASCII directly to a normal lane candidate in `direct_normal.zig:263-274`; `publicationCellSupported` currently excludes spaces, controls, continuations, spans, links, RGB, selected, invisible, strikethrough, underline color, and non-straight underline in `direct_normal.zig:276-290`.
- Remaining child work inside the scan: `appendRenderable` still resolves the face, performs glyph lookup, reserves the atlas sprite, appends raster requests on misses, computes cell geometry, appends sprite draws, and records direct-normal draws inside the timed scan in `direct_normal.zig:412-461`.
- Adjacent owner proof: `OwnedAtlasCache.reserve` still calls linear `get` over all live entries in `text/raster/cache.zig:47-55`; `FontSession.primary`, style, and fallback lookup paths are in `text/font/session.zig:62-115`; the glyph lookup call is an indirect provider call in `text/font/provider.zig:13-21`.
- Existing debug seam: `HOWL_RENDER_DEBUG_TIMING` is already owned by `session/text.zig:46-114`, but it exposes only aggregate `direct_normal_scan_avg_us`, not child costs inside the scan.

Receipt evidence:

- Accepted baseline tree receipts:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-021917-ascii/summary.json`: Howl-only 3-second receipt, final `59.32 fps`.
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-021928-ascii/summary.json`: 10-second comparison receipt, Howl `60.26 fps`, Alacritty `981.84 fps`.
  - Accepted timing from live loop: `direct_normal_scan_avg_us=811`, owner-create below it.
- Failed semantic-empty receipts:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-023806-ascii/summary.json`: first failed 3-second Howl receipt, final `54.81 fps`.
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-023930-ascii/summary.json`: final failed 3-second Howl receipt, final `48.49 fps`.
  - `/tmp/opencode/howl-render-debug-control.log:15`: final failed timing line reports `direct_normal_scan_avg_us=890`, `direct_normal_raster_avg_us=32`, `owner_create_avg_us=343`, and `emit_prepared sprites_avg_us=324`.

Current-code facts:

- The styled ASCII fast candidate already avoids generic publication mapping for printable non-space ASCII cells with supported indexed/default colors and simple style bits. It does not cover space, tab, RGB color, selected, invisible, strikethrough, underline-color, non-straight underline, links, continuations, combining marks, or multi-cell spans (`direct_normal.zig:263-290`).
- The failed semantic-empty fast candidate is not acceptable to re-promote. It passed correctness/build proof but missed the timing gate, ending at `direct_normal_scan_avg_us=890` against the accepted `811` baseline.
- The residual `direct_normal_scan` bucket is not a pure scan counter. It includes publication support checks, optional generic mapping/classification, damage inclusion, scratch append, face selection, glyph lookup, atlas reserve, raster request append, sprite draw append, coordinate math, and lane report mutation (`direct_normal.zig:195-240`, `direct_normal.zig:249-260`, `direct_normal.zig:412-461`).
- `direct_normal_raster_avg_us=32` in the failed final receipt means post-scan rasterization is no longer the residual explanation. The expensive work is before `finishScene`'s raster pass, inside the scan body.
- Current source exposes plausible child costs but not measured ownership: `atlas.reserve` is linear over live entries (`cache.zig:47-55`), `resolveFace` still checks primary/style/fallback paths (`direct_normal.zig:427-440`, `font/session.zig:62-115`), and `glyph_lookup.lookupGlyph` is an indirect call (`provider.zig:13-21`). These are candidates, not yet accepted optimization targets.
- Another semantic-cell fast path would be a guess. The last semantic guess made timing worse, and current aggregate timing cannot distinguish whether the remaining cost is publication support branching, generic fallback frequency, face lookup, glyph lookup, atlas lookup, or sprite append.

Reference facts:

- TigerBeetle rejects broad guessing: `TIGER_STYLE.md:236-257` requires mechanical sympathy and sketches before optimizing; `TIGER_STYLE.md:136-140` requires testing both positive and negative space.
- TigerBeetle also requires bounded loops and assertions (`TIGER_STYLE.md:96-113`). The current direct-normal scan is bounded by `sourceLen(source)` (`direct_normal.zig:210-212`), but the cost inside each cell is not line-owned by the active receipt.
- TigerBeetle's architecture discipline favors explicit proof over empirical flailing: `ARCHITECTURE.md:94-100` says to reason from first principles and then use experiments to confirm or disprove the model.

What remains expensive after styled ASCII and failed empty-space:

- The accepted styled ASCII candidate removed one class of generic publication mapping for live printable ASCII cells, but each supported glyph still pays the direct-normal append path: face resolve, glyph lookup, atlas reserve, sprite draw construction, and lane mutation.
- The empty-space experiment proved that adding a semantic-empty publication special case is not the next safe performance move. It did not reduce the scan enough and final timing regressed to `890`.
- The remaining direct-normal debt is therefore not source-pinned to another semantic subset. It is a broad child-cost bucket hidden under `direct_normal_scan_avg_us`, with source-backed candidates in publication support checks, generic fallback frequency, face/glyph lookup, atlas lookup, and sprite append.
- Because `OwnedAtlasCache.get` is linear and called through `reserve` from the hot append path, atlas lookup is a serious source-backed candidate. Because no child timing currently isolates it, optimizing it now would still be a guess and would violate the post-empty-space lesson.

Owner roles and proposed shape:

- `direct_normal.zig` owns the scan child instrumentation points because the residual bucket is recorded around `appendVisible` and all child operations are inside or immediately below that owner.
- `frame_preparer.zig` owns the public `PrepareTimings` handoff shape between direct-normal preparation and the existing debug emitter.
- `session/text.zig` owns the existing `HOWL_RENDER_DEBUG_TIMING` stderr emission seam and should be touched only to print the temporary child totals.
- No host, GL, PTY, VT, ABI, prepared owner-create, prepared sprite resource store, payload initialization, benchmark wrapper, or semantic-empty optimization is part of the next slice.

Readiness judgment:

- Ready for one proof-only worker slice.
- Not ready for another optimization slice.
- The next worker must line-own the residual `direct_normal_scan` cost, remove all temporary instrumentation before handoff, and return receipts. If the proof shows one clear child owner, the following research cycle can plan an optimization against that owner. If the proof shows the bucket is diffuse or contradictory, planning must stop and report that instead of inventing a fix.

Worker slice: `direct-normal-scan-child-cost-proof`

- Worker session id:
  - pending orchestrator assignment
- Researcher session id:
  - `research-2026-06-12-post-empty-space-direct-normal-scan-01`
- Purpose:
  - temporarily split `direct_normal_scan_avg_us` into child timings inside the direct-normal scan, prove which source-owned child dominates after the failed semantic-empty experiment, then remove every temporary source edit before handoff.
- Allowed files for temporary source edits only:
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
  - `/home/home/personal/projects/howl/howl-render/src/session/text.zig`
- Allowed non-source receipt output:
  - `/tmp/opencode/howl-render-debug-control.log`
  - new benchmark artifact directories under `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/<timestamp>-ascii/`
- Not allowed:
  - any committed or handed-off source change
  - `/home/home/personal/projects/howl/howl-render/src/text/raster/cache.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/font/session.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/font/provider.zig`
  - prepared owner-create files
  - prepared sprite resource store files
  - host, GL, benchmark wrapper, PTY, VT, ABI, payload initialization, or fresh rollback files

Exact required temporary shape:

- In `direct_normal.zig`, add temporary child counters to `Timings` for the scan only. The temporary fields must be explicit child names, not vague buckets:
  - `scan_publication_candidate_us`
  - `scan_generic_candidate_us`
  - `scan_damage_us`
  - `scan_append_face_us`
  - `scan_glyph_lookup_us`
  - `scan_atlas_reserve_us`
  - `scan_raster_request_us`
  - `scan_sprite_draw_us`
  - `scan_lane_us`
- In `direct_normal.zig`, measure only inside the existing `appendVisible`, `sourceCandidate`, `publicationCandidate`, and `appendRenderable` control spine. Do not add new behavior, new fast paths, new cache structures, or semantic decisions.
- In `frame_preparer.zig`, mirror the temporary child fields in `PrepareTimings` only so the existing session debug owner can print them.
- In `session/text.zig`, extend the existing `HOWL_RENDER_DEBUG_TIMING` output with one temporary `direct_normal_scan_children` line emitted at the same 128-frame cadence. The line must include `count` plus all child averages named above.
- After the proof run, remove every temporary source edit. The worker handoff must show that these files have no remaining diff:
  - `howl-render/src/text/direct_normal.zig`
  - `howl-render/src/text/frame_preparer.zig`
  - `howl-render/src/session/text.zig`

Required assertions:

- Preserve existing `lane_report.assertValid()` and scratch rollback assertions in `direct_normal.zig:127-133`, `direct_normal.zig:221-239`, and `direct_normal.zig:463-500`.
- The temporary timing fields must not change candidate decisions, scratch lengths, lane counts, raster requests, or product ownership.
- Any temporary child sum may exceed aggregate scan time because instrumentation overhead and timer nesting can distort totals; the worker must not claim additive exactness. The proof target is ranking and source ownership, not exact accounting arithmetic.

Required tests and verification:

- Before proof run, build current render tests with instrumentation present:
  - workdir `/home/home/personal/projects/howl/howl-render`: `zig build test:unit`
- Build host and stress harness:
  - workdir `/home/home/personal/projects/howl/howl-linux-host`: `zig build install -Doptimize=ReleaseFast`
  - workdir `/home/home/personal/projects/howl/utils/tools/rain-bench`: `zig build --release=fast stress:rain:build`
- Run the 3-second Howl-only proof with existing env seam:
  - workdir `/home/home/personal/projects/howl`: `env HOWL_RENDER_DEBUG_TIMING=1 python3 utils/tools/rain-bench/benchmark_terminals.py --duration 3 --mode ascii --terminals howl 2> /tmp/opencode/howl-render-debug-control.log`
- After removing temporary instrumentation, rerun the unit gate on the clean source:
  - workdir `/home/home/personal/projects/howl/howl-render`: `zig build test:unit`
- Confirm cleanup:
  - workdir `/home/home/personal/projects/howl`: `git diff -- howl-render/src/text/direct_normal.zig howl-render/src/text/frame_preparer.zig howl-render/src/session/text.zig`
  - workdir `/home/home/personal/projects/howl`: `git status --short howl-render/src/text/direct_normal.zig howl-render/src/text/frame_preparer.zig howl-render/src/session/text.zig`

Required receipt fields from the worker:

- coder/worker session id
- exact commands run and pass/fail status
- exact 3-second summary path under `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/<timestamp>-ascii/summary.json`
- exact stderr timing log path `/tmp/opencode/howl-render-debug-control.log`
- quoted final `prepare_handle` line at count `640` or the last available count if fewer frames complete
- quoted final `direct_normal_scan_children` line at the matching count
- explicit child ranking naming the largest measured child and its owner file/symbol
- explicit cleanup proof from `git diff -- ...` and `git status --short ...`
- commit-hash handoff status: no implementation commit expected from this proof-only slice; orchestrator still owns receipt closure

Timing proof expectations:

- The proof must keep the accepted baseline in view: accepted styled ASCII `direct_normal_scan_avg_us=811`, failed empty-space final `direct_normal_scan_avg_us=890`, current Howl `60.26 fps`, Alacritty `981.84 fps`.
- The proof is accepted if it identifies a single largest child or a clear top pair inside `direct_normal_scan` with exact source ownership.
- If `scan_atlas_reserve_us` dominates, the next research cycle may consider the atlas cache owner, but this worker must not touch `text/raster/cache.zig`.
- If `scan_glyph_lookup_us` or `scan_append_face_us` dominates, the next research cycle must read the font owner files before planning; this worker must not touch them.
- If `scan_publication_candidate_us` or `scan_generic_candidate_us` dominates, the next research cycle may stay inside `direct_normal.zig`, but it must not re-promote semantic-empty space.
- If no child stands out or the instrumentation materially changes the aggregate timing shape, stop and report the proof gap rather than inventing an optimization.

Non-goals:

- no optimization
- no empty-space fast path
- no styled ASCII broadening
- no RGB, selected, underline, link, tab, combining, continuation, wide-span, or invisible-cell support changes
- no atlas cache, glyph cache, font provider, host, GL, PTY, VT, ABI, prepared owner-create, prepared sprite resource store, payload initialization, fresh rollback, or benchmark-wrapper edits
- no 10-second Howl vs Alacritty comparison unless the orchestrator separately asks after a future optimization slice

Stop conditions:

- stop if child timing requires touching files outside the three allowed temporary files
- stop if unit tests fail for reasons unrelated to temporary timing and cannot be explained without an implementation fix
- stop if the proof run does not emit both the existing `prepare_handle` line and the new temporary `direct_normal_scan_children` line
- stop if temporary instrumentation cannot be fully removed before handoff
- stop if the proof exposes a correctness issue, scratch rollback leak, lane count mismatch, or vague bucket that cannot be assigned to a true owner
- stop if the worker is tempted to optimize atlas, glyph, publication semantics, or fallback mapping in the same pass

Risks:

- Timer overhead inside the per-cell hot path will perturb absolute timing. The slice must use the child timings only for ranking and ownership, not for exact additive accounting.
- The active loop contains older owner-create reviewer-gate prose from prior steps. For this pass, the explicit user seed and this active research artifact define the current post-empty-space direct-normal planning step.
- If the child proof points outside `direct_normal.zig`, the next optimization may require a new research/reviewer planning pass for that owner; this is accountability, not scope failure.

Proof gaps:

- No accepted source currently line-owns the residual `direct_normal_scan` bucket after the failed semantic-empty experiment.
- No accepted receipt currently measures atlas reserve, glyph lookup, face resolve, publication support, or generic fallback frequency separately.
- Therefore optimization is blocked until the proof-only child-cost slice completes.
