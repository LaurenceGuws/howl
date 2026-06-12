Direct-normal publication scan post-zero-codepoint plan

Date: 2026-06-12.
Status: active researcher package ready for reviewer.
Role owner: researcher.
Orchestrator session id: `orch-2026-06-11-ascii-rain-honest-performance-02`.
Researcher session id: `research-2026-06-12-direct-normal-publication-scan-post-zero-codepoint-01`.
Reviewer session id: pending.
Planning commit-hash receipt: pending; documentation-only planning artifact on this pass.

Preload receipt:

- Role: researcher.
- Active sprint:
  - `/home/home/personal/projects/howl/sprints/2026-06-11-ascii-rain-honest-performance-sprint.md`.
- Active loop:
  - `/home/home/personal/projects/howl/loops/ascii-rain-live-loop.txt`.
- Active research:
  - `/home/home/personal/projects/howl/research/2026-06-12-direct-normal-publication-scan-post-zero-codepoint-plan.md`.
- Current proof receipts:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-084336-ascii/summary.json`.
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-084355-ascii/summary.json`.
  - `/tmp/opencode/howl-render-debug-control.log`.
- Execution authorized:
  - research and planning only; no implementation from this pass.

Problem statement:

- The accepted zero-codepoint slice landed in render commit `e391d92` and lifted the live 10-second Howl receipt to `120.3 fps`, but Alacritty remains `1003.65 fps` on the same workload (`20260612-084355-ascii/summary.json:45-123`).
- The fresh built-in timing proof still ranks `direct_normal_scan_avg_us=311` above `owner_create_avg_us=216`, with `direct_normal_avg_us=396` and `emit_prepared sprites_avg_us=205` (`/tmp/opencode/howl-render-debug-control.log:13-15`).
- The next research task is to explain what still makes the publication scan hot after the printable styled ASCII and zero-codepoint fast-candidate slices, then cut one reviewer-acceptable worker slice inside the true owner seam.

Sources read in order:

1. `/home/home/personal/projects/howl/loop/flow.md:1-137`.
2. `/home/home/personal/projects/howl/loop/orcestrator.md:1-61`.
3. `/home/home/personal/projects/howl/loop/researcher.md:1-86`.
4. `/home/home/personal/projects/howl/loop/reviewer.md:1-57`.
5. `/home/home/personal/projects/howl/loop/coder.md:1-60`.
6. `/home/home/personal/projects/howl/sprints/current.txt:1-36`.
7. `/home/home/personal/projects/howl/loops/ascii-rain-live-loop.txt:1-837`.
8. `/home/home/personal/projects/howl/research/2026-06-12-direct-normal-publication-scan-post-zero-codepoint-plan.md:1-44`.
9. `/home/home/personal/projects/howl/reference-index.md:1-273`.
10. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:1-260`.
11. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:1-260`.
12. Current proof receipts:
   - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-084336-ascii/summary.json:1-85`.
   - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-084355-ascii/summary.json:1-123`.
   - `/tmp/opencode/howl-render-debug-control.log:1-15`.
13. Current owner/source paths required to explain the remaining cost:
   - `/home/home/personal/projects/howl/howl-render/src/session/text.zig:220-270`.
   - `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig:155-177`.
   - `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig:415-454`.
   - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig:110-151`.
   - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig:195-336`.
   - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig:422-471`.
   - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig:574-613`.
   - `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig:568-578`.
   - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig:22-66`.
   - `/home/home/personal/projects/howl/utils/tools/rain-bench/ascii_rain_stress.zig:197-276`.
14. Stable reference anchors needed for the owner/seam decision:
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:24-39`.
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:49-75`.

Reference facts:

- References win over existing Howl structure until current source re-proves it (`reference-index.md:14-36`).
- TigerBeetle pressure requires explicit owner truth, explicit bounds, and assertions for both positive and negative space; a hot loop should not hide vague buckets or waste work before it knows a case matters (`TIGER_STYLE.md:96-149`, `TIGER_STYLE.md:231-259`).
- TigerBeetle architecture pressure says the mental model should be proved first, then the implementation should cut the real hot work directly instead of experimenting across owners (`ARCHITECTURE.md:92-100`).
- Alacritty keeps renderable-content preparation and text drawing in the text/display owners rather than host/runtime owners, which supports staying inside `howl-render` text preparation for this slice (`display/content.rs:24-39`, `renderer/text/mod.rs:49-75`).

Current-code facts:

- Publication rendering enters `preparePublicationWithSessionOptions` first and only falls back to borrowed `CellInput` mapping if direct-normal cannot finish the publication source honestly (`session/text.zig:226-261`, `frame_preparer.zig:155-177`).
- The built-in timing seam reports the current clean-tree ranking at `count=640`: `direct_normal_avg_us=396`, `direct_normal_scan_avg_us=311`, `owner_create_avg_us=216`, `sprites_avg_us=205`, and `atlas_resource_avg_us=91` (`/tmp/opencode/howl-render-debug-control.log:13-15`).
- The accepted 3-second and 10-second product receipts are clean and final, with Howl `108.29 fps` for the 3-second proof run and Howl `120.3 fps` vs Alacritty `1003.65 fps` for the 10-second comparison run (`20260612-084336-ascii/summary.json:45-84`, `20260612-084355-ascii/summary.json:45-123`).
- `prepareDirectNormal` measures `direct_normal_scan_us` directly from `direct_normal.prepare`, so the hot bucket is owned by `howl-render/src/text/direct_normal.zig`, not by host, GL, VT, or emitter code (`frame_preparer.zig:415-454`).
- `appendVisible` is still the direct-normal scan spine; every visible source cell passes through `sourceCandidate`, then `candidateDecision`, then `appendRenderable` if included (`direct_normal.zig:195-240`).
- The publication fast path no longer spends the generic fallback on printable styled ASCII or `codepoint == 0` blanks. Instead, publication cells that fit the accepted subset go through `publicationCandidate`, which validates support, builds a full `RenderableText`, and only then checks damage (`direct_normal.zig:249-274`).
- `publicationCandidate` currently calls `publicationRenderableText(theme, idx, cell)` before `cluster.includeDamage(...)`, even though the damage filter depends only on `first_cell` and `cell_span` (`direct_normal.zig:268-269`, `cluster.zig:576-578`).
- The fast-path support predicate is still wide enough to cover the live ASCII-rain subset: single-cell publication cells with `codepoint == 0` or printable ASCII, no combining, no continuation, no link, no selection, no invisible, no strikethrough, no underline color, straight underline only, and default or indexed colors only (`direct_normal.zig:276-341`).
- `publicationRenderableText` is where the fast path still pays per-cell style and color mapping work: default/indexed color conversion, semantic color construction, inverse swapping, font-style mapping, and inline text construction (`direct_normal.zig:292-336`).
- `appendRenderable` already has the correct blank-route behavior after candidate admission: it appends the renderable cell, then exits before glyph lookup and sprite draw when `text.first_cp == 0 or text.first_cp == '\t'` (`direct_normal.zig:430-435`).
- The ASCII-rain workload writes into a `320 x 120` grid (`summary.json:32-44`), but each dense-frame cursor loop emits only `cols * min(rows, 32)` positioned writes before the long-line tail, so a substantial share of scanned cells can be outside the dirty span and should be cheap skips (`ascii_rain_stress.zig:202-215`, `20260612-084355-ascii/summary.json:32-44`).
- In ASCII mode the stress tool emits only printable bytes `33...126` for glyph writes, indexed fg/bg colors via `38;5` and `48;5`, and style values `0...7`; it does not emit RGB, links, combining marks, or wide glyphs in this mode (`ascii_rain_stress.zig:221-245`, `ascii_rain_stress.zig:268-276`).

What remains expensive:

- The truthful hot residual is no longer a vague generic-fallback class.
- The truthful hot residual is the direct-normal publication fast path doing too much per-cell work before it knows whether the cell is even in damage.
- On the current tree, accepted printable styled ASCII and zero-codepoint cells already bypass generic publication mapping, but `publicationCandidate` still performs support checks plus full `RenderableText` materialization for every supported cell before the damage filter can skip it (`direct_normal.zig:263-274`).
- That means scan time now burns inside admitted cells on color/style/text construction rather than on unsupported-cell fallback.
- Because `cluster.includeDamage` needs only `first_cell` and `cell_span` (`cluster.zig:576-578`), the current source order is doing unnecessary work on supported-but-undamaged cells.
- The current workload shape makes that cost believable: a `320 x 120` publication surface is rescanned, while dense mode updates only part of it per frame and the long-line tail does not make the whole surface uniformly dirty (`ascii_rain_stress.zig:202-215`, `ascii_rain_stress.zig:268-276`, `20260612-084355-ascii/summary.json:32-44`).
- The next honest optimization is therefore not another new semantic subset, not new instrumentation, and not a host/renderer redesign. It is a damage-first fast candidate inside `direct_normal.zig` that preserves the already-proved subset and avoids full renderable mapping when the damage filter would skip the cell anyway.

Compact anchor map:

- Stable references:
  - `reference-index.md:14-36` for reference precedence.
  - `TIGER_STYLE.md:96-149` for assertion density and negative-space proof.
  - `TIGER_STYLE.md:231-259` for explicit hot-loop mechanics.
  - `ARCHITECTURE.md:92-100` for prove-the-model-first pressure.
  - `display/content.rs:24-39`, `renderer/text/mod.rs:49-75` for keeping this work in the text/render owner seam.
- Current owner seams:
  - Publication enters direct-normal first: `session/text.zig:226-261`, `frame_preparer.zig:155-177`.
  - Direct-normal owns the scan bucket: `frame_preparer.zig:415-454`, `direct_normal.zig:110-151`.
  - Current hot source order lives in `direct_normal.zig:249-336`.
  - Damage truth lives in `cluster.zig:576-578`.
  - Workload shape that justifies damage-first skip lives in `ascii_rain_stress.zig:202-215`, `ascii_rain_stress.zig:268-276`, and the `320 x 120` receipt config (`20260612-084355-ascii/summary.json:32-44`).

Owner roles and proposed shape:

- True owner seam: `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`.
- Supporting proof root only: `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig` because the publication path tests already live there (`frame_preparer.zig:1008-1265`).
- No host, GL, benchmark-wrapper, PTY, VT, ABI, owner-create, or emitter owner change is required.

Proposed next worker slice:

- Slice name: `direct-normal-publication-damage-first-fast-candidate`.
- Goal: keep the already-proved printable styled ASCII plus zero-codepoint publication subset, but make damage rejection happen before full fast-path style/color/text materialization.

Exact allowed files:

- `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`.
- `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`.

Not allowed:

- Any other file.
- No `publication_cell_map.zig` edits.
- No host, GL, benchmark-wrapper, PTY, VT, ABI, owner-create, sprite cache, fresh rollback, payload initialization, or temporary instrumentation edits.

Exact required shape:

- Keep `appendVisible` as the parent scan loop and keep `sourceCandidate` as the single publication-vs-generic branch owner.
- Refactor the publication fast path so it splits publication admission into two owner-local stages:
  - Stage 1: decide whether the cell is inside the already-accepted fast subset and determine the exact span needed for damage filtering.
  - Stage 2: only if Stage 1 says supported and the damage filter includes the span, build the full `RenderableText` and `Candidate`.
- Do not widen the accepted publication subset beyond what current source already supports:
  - `codepoint == 0` or printable ASCII `0x21...0x7e`.
  - `combining_len == 0`.
  - `flags.continuation == 0` and inferred span exactly `1`.
  - `link_id == 0`.
  - fg/bg color kinds limited to default or indexed.
  - `selected == 0`, `invisible == 0`, `strikethrough == 0`, `underline_color_set == 0`.
  - straight underline only.
- Preserve the existing publication fast-path semantics for supported damaged cells: inverse swap, dim alpha, semantic colors, underline truth, and zero-codepoint blank-route behavior must stay identical to the current direct-normal fast path.
- Preserve generic fallback for every unsupported publication cell.
- Preserve the current `candidate|skip|unsupported` behavior. A supported but undamaged cell must still become `.skip`, not `.unsupported`.
- Preserve `appendRenderable` as the only owner of glyph lookup, atlas reservation, raster request append, and blank-route sprite suppression.

Required assertions:

- Assert source index bounds before reading the publication cell.
- Assert the supported-damage-first branch never reports a span other than `1` for an accepted fast candidate.
- Assert supported damaged candidates still classify `normal` after construction.
- Assert the constructed text remains a single inline codepoint slice and preserves `0` exactly for zero-codepoint cells.
- Assert unsupported publication cases do not mutate scratch state beyond the existing fallback/rollback contract.
- Preserve existing `scratchEmpty`, `lane_report.assertValid`, and rejected-complex assertions.

Required owner-local tests:

- Keep the existing direct-normal publication candidate tests in `direct_normal.zig` green:
  - `direct normal publication zero codepoint is a fast candidate`.
  - `direct normal publication keeps unsupported non-printables on generic fallback`.
- Keep the existing publication path tests in `frame_preparer.zig` green because they already prove the live subset and negative space:
  - `text preparation publication styled indexed ascii stays on direct normal path`.
  - `text preparation publication zero codepoint stays on direct normal path without sprite draw`.
  - `text preparation publication styled indexed zero codepoint stays on direct normal path`.
  - `text preparation publication unsupported space and rgb keep fallback scratch clean`.
  - `text preparation publication tab stays on generic fallback without partial direct scratch`.
  - `text preparation publication other control stays on generic fallback without partial direct scratch`.
- Add one new owner-local `frame_preparer.zig` test proving a supported publication cell outside the dirty span still completes through direct-normal without shaped fallback and does not produce visible draws for the skipped cell. The test must exercise the supported subset, not a fallback case.

Required commands and verification:

- `/home/home/personal/projects/howl/howl-render`: `zig build test:unit`.
- `/home/home/personal/projects/howl/howl-linux-host`: `zig build install -Doptimize=ReleaseFast`.
- `/home/home/personal/projects/howl/utils/tools/rain-bench`: `zig build --release=fast stress:rain:build`.
- `/home/home/personal/projects/howl`: `env HOWL_RENDER_DEBUG_TIMING=1 python3 utils/tools/rain-bench/benchmark_terminals.py --duration 3 --mode ascii --terminals howl 2> /tmp/opencode/howl-render-debug-control.log`.
- `/home/home/personal/projects/howl`: `python3 utils/tools/rain-bench/benchmark_terminals.py --duration 10 --mode ascii --terminals howl alacritty` only if the 3-second timing gate passes.

Timing proof expectations:

- Required 3-second receipt path: `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/<timestamp>-ascii/summary.json`.
- Required timing log path: `/tmp/opencode/howl-render-debug-control.log`.
- Baseline timing to beat from the accepted zero-codepoint tree:
  - `direct_normal_avg_us=396`.
  - `direct_normal_scan_avg_us=311`.
  - `owner_create_avg_us=216`.
- Required 3-second gate: `direct_normal_scan_avg_us < 311`.
- Expected supporting signal: `direct_normal_avg_us` should also fall below `396`; if scan improves but total direct-normal does not, the worker must stop and report that mismatch.
- Required 10-second receipt path if the gate passes: `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/<timestamp>-ascii/summary.json`.
- Expected product proof if the gate passes: Howl should beat the accepted `120.3 fps` baseline while Alacritty remains a completion control. If micro timing improves but the 10-second product receipt does not improve, the worker must stop and report that mismatch instead of broadening scope.

Exact non-goals:

- No new semantic subset expansion.
- No RGB, links, selection, invisible, strikethrough, underline-color, curly underline, combining, continuation, multi-cell-span, tabs, spaces, or other control-code fast paths.
- No changes to generic publication truth in `publication_cell_map.zig`.
- No host, GL, PTY, VT, ABI, benchmark-wrapper, owner-create, sprite cache, fresh rollback, payload initialization, or emitter work.
- No temporary instrumentation beyond the existing `HOWL_RENDER_DEBUG_TIMING` seam.

Exact stop conditions:

- Stop if truthful damage-first publication skipping requires touching any file outside the two allowed files.
- Stop if the worker cannot preserve the current `candidate|skip|unsupported` distinction without weakening fallback semantics.
- Stop if implementing the skip-first shape requires widening the accepted publication subset beyond the currently-supported ASCII plus zero-codepoint shape.
- Stop if unit tests expose a correctness mismatch between the damage-first fast path and the current direct-normal render consequences.
- Stop if the 3-second rerun does not beat `direct_normal_scan_avg_us=311`.
- Stop if the 3-second timing gate passes but the 10-second product rerun does not beat `120.3 fps`; report the mismatch instead of broadening the slice.

Receipt fields required from the worker:

- coder session id.
- files changed.
- exact tests run.
- exact updated receipt paths.
- quoted timing lines from `/tmp/opencode/howl-render-debug-control.log`.
- exact before/after `direct_normal_avg_us`, `direct_normal_scan_avg_us`, and `owner_create_avg_us`.
- exact before/after Howl FPS and Alacritty FPS if the 10-second rerun is reached.
- commit-hash handoff status pending orchestrator closure.

Risks:

- If the dirty region is effectively full more often than expected, moving damage ahead of materialization may help less than the source-order cost suggests.
- The supported publication subset is already narrow; any accidental widening would create correctness risk immediately.
- A micro-timing win may still be too small to move the 10-second FPS receipt materially.

Proof gaps:

- The current clean-tree proof ranks the bucket honestly but does not split the remaining `311` into support-check cost versus materialization cost versus damage-skip opportunity without new temporary timers.
- That proof gap does not block this slice because current source already shows the exact wasteful order: full `publicationRenderableText` construction before damage filtering (`direct_normal.zig:268-269`).

Readiness judgment:

- Ready.
- The remaining expensive work is line-owned in `direct_normal.zig` and no longer a vague bucket.
- The next reviewer-acceptable worker slice is a narrow damage-first publication fast-candidate refactor in `direct_normal.zig`, with path proof kept in the existing `frame_preparer.zig` publication tests.
