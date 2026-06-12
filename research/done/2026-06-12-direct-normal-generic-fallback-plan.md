Direct-normal generic fallback plan

Date: 2026-06-12.
Status: active researcher target.
Role owner: researcher.
Orchestrator session id: `orch-2026-06-11-ascii-rain-honest-performance-02`.
Researcher session id: `research-2026-06-12-direct-normal-generic-fallback-01`.
Reviewer session id: pending.
Planning commit-hash receipt: pending.

Preload receipt:

- Role: researcher
- Active sprint:
  - `/home/home/personal/projects/howl/sprints/2026-06-11-ascii-rain-honest-performance-sprint.md`
- Active loop:
  - `/home/home/personal/projects/howl/loops/ascii-rain-live-loop.txt`
- Active research:
  - `/home/home/personal/projects/howl/research/2026-06-12-direct-normal-generic-fallback-plan.md`
- Ranking-only proof receipts:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-025154-ascii/summary.json`
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-025340-ascii/summary.json`
  - `/tmp/opencode/howl-render-debug-control.log`
- Accepted product baseline receipts:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-021917-ascii/summary.json`
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-021928-ascii/summary.json`
- Execution authorized:
  - research and planning only; no implementation from this pass

Problem statement:

- The proof-only child-cost slice removed all temporary instrumentation before handoff and is ranking-only because per-cell timers inflated product timing.
- The largest ranked child cost was `scan_generic_candidate_avg_us=767`, owned by `direct_normal.sourceCandidate` generic fallback/classification.
- The accepted product baseline remains root `ad7195f` plus `howl-render` `98bb85a`, with Howl `60.26 fps` vs Alacritty `981.84 fps` and accepted `direct_normal_scan_avg_us=811`.
- The next research task is to decide whether `scan_generic_candidate` can be reduced by a reviewer-safe worker slice, or whether the timer perturbation is too large and another proof method is needed first.

Research requirements:

- Read the live workflow, active loop, current sprint index, this file, TigerBeetle readings, and source/reference anchors before writing a plan.
- Treat the child-cost proof as ranking evidence only, not additive absolute timing truth.
- Produce one reviewer-acceptable worker slice with exact allowed files, shape, tests, non-goals, stop conditions, assertions, receipt paths, and timing proof expectations, or explicitly require another proof slice if the ranking is too perturbed.
- Do not drift into host, GL, benchmark-wrapper, PTY, VT, ABI, owner-create, sprite cache, fresh rollback, payload initialization, or unbounded instrumentation unless current source proves it is required.
- Stop and report if the truthful next step exposes a big correctness issue or vague bucket.

Readiness judgment:

- Ready for reviewer gate as a proof-only worker slice.
- Not ready for an optimization worker slice.

Researcher pass receipt:

- Session id:
  - `research-2026-06-12-direct-normal-generic-fallback-01`
- Sources read in required order:
  - `/home/home/personal/projects/howl/loop/flow.md`
  - `/home/home/personal/projects/howl/loop/orcestrator.md`
  - `/home/home/personal/projects/howl/loop/researcher.md`
  - `/home/home/personal/projects/howl/loop/reviewer.md`
  - `/home/home/personal/projects/howl/loop/coder.md`
  - `/home/home/personal/projects/howl/sprints/current.txt`
  - `/home/home/personal/projects/howl/loops/ascii-rain-live-loop.txt`
  - `/home/home/personal/projects/howl/research/2026-06-12-direct-normal-generic-fallback-plan.md`
  - `/home/home/personal/projects/howl/reference-index.md`
  - `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
  - `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
  - current source and proof receipts listed below

Current proof receipts:

- Accepted product baseline:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-021917-ascii/summary.json`
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-021928-ascii/summary.json`
  - Howl `60.26 fps`, Alacritty `981.84 fps`, accepted `direct_normal_scan_avg_us=811`
- Ranking-only child proof:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-025154-ascii/summary.json`
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-025340-ascii/summary.json`
  - `/tmp/opencode/howl-render-debug-control.log`
- Ranking-only timing lines:
  - `/tmp/opencode/howl-render-debug-control.log:19`: `direct_normal_scan_avg_us=2909`
  - `/tmp/opencode/howl-render-debug-control.log:20`: `scan_publication_candidate_avg_us=276 scan_generic_candidate_avg_us=767 scan_damage_avg_us=236 scan_append_face_avg_us=249 scan_glyph_lookup_avg_us=84 scan_atlas_reserve_avg_us=57 scan_raster_request_avg_us=0 scan_sprite_draw_avg_us=35 scan_lane_avg_us=32`
- Ranking limitation:
  - The proof-only child timers inflated the product scan bucket from the accepted `811` to `2909`; use this as relative child ranking only, not as additive or absolute product truth.
  - The proof receipts' Howl FPS values of `8.88` and `8.93` are instrumentation artifacts, not product baselines.

Compact anchor map:

- Workflow authority:
  - `loop/flow.md:22-41` requires complete slice boundaries, exact files, tests, non-goals, stop conditions, and planning receipts before execution.
  - `loop/researcher.md:60-75` requires sources, line references, current-code facts, reference facts, owner shape, assertions, tests, risks, proof gaps, and readiness judgment in the research file.
  - `sprints/current.txt:20-31` says the active step is direct-normal generic fallback planning and archived planning is navigation only.
  - `loops/ascii-rain-live-loop.txt:740-745` records the accepted child-cost proof and explicitly marks it ranking-only because per-cell timers inflated aggregate scan timing.
- TigerBeetle discipline:
  - `TIGER_STYLE.md:96-100` requires bounded loops and explicit limits.
  - `TIGER_STYLE.md:104-140` requires assertions for preconditions, invariants, positive space, and negative space.
  - `TIGER_STYLE.md:221-229` requires decisions to say why and avoid implicit defaults.
  - `TIGER_STYLE.md:256-264` prefers predictable hot loops and extracting hot work into direct primitive-owner shapes only when the mental model is clear.
  - `TIGER_STYLE.md:381-387` prefers in-place construction for larger structs, but this is not authorization to rewrite the render shape in this step.
  - `ARCHITECTURE.md:408-423` separates control-plane classification from data-plane loops; classification belongs at the direct owner seam and must not become unbounded instrumentation.
- Alacritty render pressure:
  - `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:153-183` iterates renderable content and skips empty/wide-spacer cells in one owner-owned iterator.
  - `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:208-299` constructs renderable cell facts at the display-content seam, including color/selection/extra state.
  - `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:57-69` consumes already-renderable cells in a tight render loop.
  - Relevance: Howl's `direct_normal.sourceCandidate` is the current owner seam for publication-cell-to-renderable classification; do not move this decision into host, GL, ABI, PTY, VT, or benchmark code.
- Howl owner seams:
  - `howl-render/src/text/direct_normal.zig:195-240` owns the direct-normal visible scan, rollback on rejection, and no-partial-scratch invariant.
  - `howl-render/src/text/direct_normal.zig:249-261` owns `sourceCandidate`; publication sources first try `publicationCandidate`, then unsupported cells fall through to generic `sourceItem` plus `lane.classifyRenderableCell`.
  - `howl-render/src/text/direct_normal.zig:263-274` owns the existing publication fast candidate and asserts the fast candidate is normal.
  - `howl-render/src/text/direct_normal.zig:276-290` currently treats many publication cells as unsupported: spaces, combining, continuations, multi-cell spans, links, RGB colors, selection, invisible text, strikethrough, underline colors, and non-straight underline styles.
  - `howl-render/src/text/direct_normal.zig:292-331` directly builds a renderable text for supported printable indexed/default ASCII publication cells.
  - `howl-render/src/text/direct_normal.zig:333-357` supports only default and indexed colors in the current fast candidate.
  - `howl-render/src/text/direct_normal.zig:412-461` appends a renderable cell and then performs face lookup, glyph lookup, atlas reserve, raster request, and sprite draw work.
  - `howl-render/src/text/shape/cluster.zig:549-555` is the generic publication fallback; it maps a `SourceCell` through `publication_cell_map.mapPublicationCellInput`, infers span, and builds a renderable text.
  - `howl-render/src/source/publication_cell_map.zig:33-65` owns full publication cell mapping semantics, including inverse and selection.
  - `howl-render/src/source/publication_cell_map.zig:81-91` defines publication semantic-empty truth.
  - `howl-render/src/text/classify/lane.zig:223-228` owns generic renderable classification.
  - `howl-render/src/text/classify/lane.zig:260-280` classifies normal text versus special, icon, emoji, and multi-codepoint cases.
  - `howl-render/src/text/frame_preparer.zig:1115-1132` proves unsupported space and RGB currently reach generic fallback cleanly.
  - `howl-render/src/text/frame_preparer.zig:1170-1184` proves unsupported link currently reaches generic fallback cleanly.
  - `utils/tools/rain-bench/ascii_rain_stress.zig:197-219` emits dense randomized cursor moves, erases, scrolls, and long lines.
  - `utils/tools/rain-bench/ascii_rain_stress.zig:221-226` emits random indexed foreground/background and SGR style `0...7` in ASCII mode.
  - `utils/tools/rain-bench/ascii_rain_stress.zig:241-245` emits printable ASCII glyphs, while erase/scroll operations can create generic fallback cells that are not emitted glyphs.

Current-code facts:

- `sourceCandidate` is no longer a single clear optimization target. It is a dispatch point for at least three distinct costs:
  - fast publication candidate construction for supported printable indexed/default ASCII cells
  - generic publication mapping through `cluster.sourceRenderableTextFromPublication`
  - generic lane classification through `lane.classifyRenderableCell`
- The child proof says the combined generic path is the largest child bucket, but it does not say which unsupported publication classes dominate that path.
- The source-supported unsupported classes are materially different in consequence:
  - semantic-empty/default spaces may be normal but often avoid sprite work
  - RGB and link cells can remain normal under current generic tests
  - combining cells, curly underline, icons, emoji presentation, and multi-codepoint cells can become complex and must preserve fallback
  - continuations and multi-cell spans affect ownership and damage span logic
  - selected/inverse/underline color semantics are owned by `publication_cell_map`, not by a loose direct-normal shortcut
- A previous semantic-empty space fast-candidate worker passed correctness tests but failed the timing gate and was removed, recorded at `loops/ascii-rain-live-loop.txt:691-703` and `loops/ascii-rain-live-loop.txt:726-731`.
- Therefore a new optimization slice aimed at generic fallback would be guessing unless it first knows the live generic fallback mix and whether generic-normal or generic-complex cells dominate.

Decision:

- Do not authorize an optimization worker yet.
- Require one more proof-only worker slice.
- Reason:
  - The timer perturbation is too large for additive cost math.
  - The ranking is still useful enough to target `direct_normal.sourceCandidate`, but the bucket is too broad for a reviewer-safe product change.
  - The current source exposes a vague bucket, not a single owner-true optimization: `scan_generic_candidate` conflates fallback reason classification, publication cell mapping, damage inclusion, and lane classification.

Proposed next worker slice: `direct-normal-generic-fallback-mix-proof`

- Purpose:
  - Add temporary count-only instrumentation inside the current direct-normal source-candidate owner to classify the live publication generic fallback mix without per-cell timers.
  - Remove all temporary instrumentation before handoff.
  - Produce a reviewer-usable proof of whether the next optimization should target a specific fallback class, or whether the ranking was timer-noise dominated.
- Coder session id:
  - pending, suggested `worker-2026-06-12-direct-normal-generic-fallback-mix-proof-01`
- Allowed files for temporary source edits:
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
- Allowed files for final handoff state:
  - no source files changed
- Not allowed:
  - host, GL, benchmark wrapper, PTY, VT, ABI, owner-create, sprite cache, fresh rollback, payload initialization, source publication ownership changes, new owner files, persistent instrumentation, or optimization edits
  - changes to `howl-render/src/text/frame_preparer.zig` unless reviewer explicitly rejects this plan and asks for owner-local unit-test changes; this proof slice is temporary and should leave source clean

Required temporary shape:

- Keep the existing `HOWL_RENDER_DEBUG_TIMING` guard.
- Add count-only counters, not timers, in `direct_normal.zig` around `sourceCandidate` and publication fallback.
- Counters must be monotonically accumulated per prepare-debug report and printed as a new temporary line such as `howl-render-debug direct_normal_generic_fallback_mix count=...`.
- The temporary line must include at least these fields:
  - `publication_cells`
  - `publication_fast_candidate`
  - `publication_fast_skip_damage`
  - `publication_generic_entered`
  - `publication_generic_skip_damage`
  - `publication_generic_normal`
  - `publication_generic_complex`
  - `publication_generic_null`
  - `unsupported_space`
  - `unsupported_tab`
  - `unsupported_non_printable`
  - `unsupported_non_ascii`
  - `unsupported_combining`
  - `unsupported_continuation`
  - `unsupported_multi_cell_span`
  - `unsupported_link`
  - `unsupported_rgb_fg`
  - `unsupported_rgb_bg`
  - `unsupported_selected`
  - `unsupported_invisible`
  - `unsupported_strikethrough`
  - `unsupported_underline_color`
  - `unsupported_underline_style`
- `publication_generic_entered` means the number of publication cells that fell through the fast candidate and entered the generic publication path before consequence classification.
- `publication_generic_skip_damage`, `publication_generic_normal`, `publication_generic_complex`, and `publication_generic_null` are the four mutually exclusive consequence classes for those entered generic publication cells.
- If one cell has multiple unsupported reasons, count every true reason, and also count exactly one generic consequence class. The proof needs both reason density and consequence density.
- Keep control flow direct and bounded inside the existing scan loop. No allocation, no maps, no string buckets, no dynamic logging per cell.
- The temporary code may add a small local debug counter struct only if it stays in `direct_normal.zig`, has exact field names, and is removed before handoff.
- Remove the temporary counter struct, fields, print line, and call sites before handoff.

Required assertions while instrumented:

- Assert publication-source indices are in range before reading cells, matching `direct_normal.zig:263-265` and `direct_normal.zig:552-555` style.
- Assert the count-only path does not change `PublicationCandidate` decisions.
- Assert `publication_generic_entered == publication_generic_skip_damage + publication_generic_normal + publication_generic_complex + publication_generic_null` at report time.
- Assert all aggregate counters fit in `u64` and source lengths fit existing `u32` bounds.
- Preserve existing no-partial-scratch assertions in `direct_normal.zig:221-238` and `direct_normal.zig:463-501`.

Required commands:

- From `/home/home/personal/projects/howl/howl-render` before temporary edits if the worker wants a clean baseline:
  - `zig build test:unit`
- From `/home/home/personal/projects/howl/howl-linux-host` after temporary edits:
  - `zig build install -Doptimize=ReleaseFast`
- From `/home/home/personal/projects/howl/utils/tools/rain-bench` after temporary edits:
  - `zig build --release=fast stress:rain:build`
- From `/home/home/personal/projects/howl` after temporary edits:
  - `env HOWL_RENDER_DEBUG_TIMING=1 python3 utils/tools/rain-bench/benchmark_terminals.py --duration 3 --mode ascii --terminals howl 2> /tmp/opencode/howl-render-debug-control.log`
- After capturing proof, remove all temporary source instrumentation.
- From `/home/home/personal/projects/howl/howl-render` after cleanup:
  - `zig build test:unit`
- From `/home/home/personal/projects/howl` after cleanup:
  - `git diff -- howl-render/src/text/direct_normal.zig`
  - `git status --short -- howl-render/src/text/direct_normal.zig`

Required proof receipts:

- Exact 3-second proof summary path under:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/<timestamp>-ascii/summary.json`
- Exact stderr proof log path:
  - `/tmp/opencode/howl-render-debug-control.log`
- Quoted final `howl-render-debug prepare_handle` line from the proof log.
- Quoted final `howl-render-debug direct_normal_scan_children` line from the proof log if still present during the proof run.
- Quoted final temporary `howl-render-debug direct_normal_generic_fallback_mix` line.
- Explicit worker conclusion naming:
  - the dominant unsupported reason by count
  - the dominant generic consequence by count
  - whether the next step should be optimization planning for a specific class or another proof slice
- Exact cleanup proof:
  - `zig build test:unit` passes after cleanup
  - `git diff -- howl-render/src/text/direct_normal.zig` is empty after cleanup
  - `git status --short -- howl-render/src/text/direct_normal.zig` is empty after cleanup

Timing proof expectations:

- The proof run is not a product baseline and does not need to improve FPS.
- The proof must not be used as additive absolute timing truth.
- The proof is acceptable if it identifies the largest generic fallback class by count and consequence at the final reported `count=640` or latest emitted debug count.
- If the count-only proof still inflates `direct_normal_scan_avg_us`, that is acceptable only if source cleanup is complete and the mix counts are coherent.

Stop conditions:

- Stop if the instrumentation needs any file outside `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`.
- Stop if the worker cannot produce a coherent final mix line with both reason counts and normal/complex/skip consequences.
- Stop if count-only instrumentation changes render output, tests, or fallback decisions.
- Stop if the proof exposes a correctness issue in publication mapping, damage inclusion, lane classification, semantic empty truth, or fallback scratch rollback.
- Stop if source cleanup cannot be proven with empty `git diff` and empty path-scoped `git status` for `direct_normal.zig`.
- Stop if the largest generic fallback class is semantic-empty space again and the worker is tempted to reattempt the failed empty-space optimization without new reviewer planning.

Non-goals:

- No optimization.
- No persistent debug API.
- No benchmark harness edits.
- No 10-second Howl vs Alacritty comparison.
- No C ABI changes.
- No host/GL/runtime changes.
- No new owner or helper files.
- No changes to `publication_cell_map`, `cluster`, `lane`, or `frame_preparer` in this proof slice.

Reviewer gate for this plan:

- Accept only if the reviewer agrees that `scan_generic_candidate` is currently a vague bucket and that a count-only mix proof is the smallest accountable next step.
- Reject if the reviewer believes the ranking-only proof already authorizes a specific optimization class; in that case the reviewer must name the exact class and source lines that make it non-guesswork.
- Reject if the reviewer requires persistent owner-local tests in this proof slice; tests belong to a subsequent optimization slice after the generic fallback class is known.

Open proof gaps:

- The live mix of `scan_generic_candidate` is unknown.
- The ranking-only child timers do not identify whether generic fallback cost is dominated by semantic-empty spaces, RGB/link normal fallback, complex fallback, damage skips, or mapping overhead shared across several classes.
- The prior empty-space optimization failure means semantic-empty space is not automatically an acceptable next optimization even if it is numerous.
