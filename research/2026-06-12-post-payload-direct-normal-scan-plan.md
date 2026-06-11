Post-payload direct-normal scan plan

Date: 2026-06-12.
Status: active researcher package, ready for reviewer.
Role owner: researcher.
Orchestrator session id: `orch-2026-06-11-ascii-rain-honest-performance-02`.
Researcher session id: `research-2026-06-12-post-payload-direct-normal-scan-01`.
Reviewer session id: pending.
Planning commit-hash receipt: pending.

Preload receipt:

- Role: researcher.
- Active sprint: `/home/home/personal/projects/howl/sprints/2026-06-11-ascii-rain-honest-performance-sprint.md`.
- Active loop: `/home/home/personal/projects/howl/loops/ascii-rain-live-loop.txt`.
- Active research: `/home/home/personal/projects/howl/research/2026-06-12-post-payload-direct-normal-scan-plan.md`.
- Current proof receipts:
- `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-014446-ascii/summary.json`.
- `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-014500-ascii/summary.json`.
- `/tmp/opencode/howl-render-debug-control.log`.
- Execution authorized: research and planning only; no implementation from this pass.

Sources read in required order:

- `/home/home/personal/projects/howl/loop/flow.md` lines 3-41, 43-69, 70-93, 98-137.
- `/home/home/personal/projects/howl/loop/orcestrator.md` lines 25-53.
- `/home/home/personal/projects/howl/loop/researcher.md` lines 32-47, 48-59, 60-86.
- `/home/home/personal/projects/howl/loop/reviewer.md` lines 27-57.
- `/home/home/personal/projects/howl/loop/coder.md` lines 26-43, 44-60.
- `/home/home/personal/projects/howl/sprints/current.txt` lines 8-18, 20-31.
- `/home/home/personal/projects/howl/loops/ascii-rain-live-loop.txt` lines 578-597.
- `/home/home/personal/projects/howl/research/2026-06-12-post-payload-direct-normal-scan-plan.md` previous seed lines 1-57.
- `/home/home/personal/projects/howl/reference-index.md` lines 19-36, 137-147, 204-214, 215-235.
- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md` lines 90-113, 136-140, 158-176, 231-264, 372-424.
- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md` lines 329-363, 408-423.
- `/home/home/personal/projects/howl/howl-render/src/session/text.zig` lines 46-112, 220-270, 514-535.
- `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig` lines 22-41, 155-178, 415-454, 961-1015, 1136-1251.
- `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig` lines 110-151, 187-232, 241-263, 274-329, 371-418.
- `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig` lines 33-66, 81-91, 123-157, 176-194.
- `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig` lines 549-555, 637-674, 677-790.
- `/home/home/personal/projects/howl/howl-render/src/text/classify/lane.zig` lines 96-175, 218-280.
- `/home/home/personal/projects/howl/howl-render/src/text/contract.zig` lines 92-155, 227-244, 246-291.
- `/home/home/personal/projects/howl/howl-render/src/source/vt.zig` lines 13-65, 103-120, 194-239.

Problem statement:

- The accepted payload initialization slice landed in render commit `01e8bec` and root commit `150b14d`, recorded in the active loop at `/home/home/personal/projects/howl/loops/ascii-rain-live-loop.txt` lines 578-583.
- The fresh 10-second control receipt reports Howl `55.54 fps` and Alacritty `987.81 fps` at `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-014500-ascii/summary.json` lines 70-80 and 108-118.
- The post-payload timing proof ranks `direct_normal` first: `/tmp/opencode/howl-render-debug-control.log` lines 13-15 report `direct_normal_avg_us=991`, `direct_normal_scan_avg_us=883`, `owner_create_avg_us=361`, and `emit_avg_us=360`.
- The current task is not host, GL, VT, PTY, ABI, owner-create, payload, cache, benchmark-wrapper, or temporary instrumentation work. The current task is to plan the next direct-normal owner slice from current source.

Compact anchor map:

- TigerBeetle style requires bounded loops, asserted function contracts, positive and negative space tests, small scope, and hot loops that are direct enough for a human to see redundant work. See `TIGER_STYLE.md` lines 96-113, 136-140, 158-176, 231-264, and 372-424.
- TigerBeetle architecture pressure says control-plane branching must stay outside or minimal inside the data-plane loop; hot sequential CPU work should be straight-line and mechanically sympathetic. See `ARCHITECTURE.md` lines 329-363 and 408-423.
- Current Howl owner seam: `TextSessionOwner.prepareHandle` measures prepare-surface work and owner-create work separately at `session/text.zig` lines 514-535; the direct-normal scan bucket is produced before `PreparedHandle.create` and is not an owner-create bucket.
- Current Howl owner seam: `TextSession.prepareSurface` attempts publication direct-normal first at `session/text.zig` lines 240-252, and only builds borrowed text input plus shared shaped preparation after direct-normal returns null at lines 253-270.
- Current Howl owner seam: `TextFramePreparer.preparePublicationWithSessionOptions` calls `prepareDirectNormal` with `.publication` and `.require_all_normal` at `frame_preparer.zig` lines 155-167; direct-normal owns the current fast publication attempt.
- Current Howl owner seam: `direct_normal.prepare` owns the scan, append, direct-scene draw accumulation, direct raster requests, and timing subdivision at `direct_normal.zig` lines 110-151.

Current-code facts:

- `DebugPrepareTiming.record` prints `direct_normal_scan_avg_us` from `PrepareTimings.direct_normal_scan_us`, proving the hot number is the direct-normal scan subsection, not background, decoration, raster, or owner-create work. See `session/text.zig` lines 73-112 and `frame_preparer.zig` lines 415-454.
- `direct_normal.prepare` always calls `driver.scratch.reset` for `sourceLen(source)` and then times `appendVisible` as `scan_us`. See `direct_normal.zig` lines 121-135.
- For publication input, `appendVisible` currently iterates `idx` from `0` to `sourceLen(source)` and calls `sourceCandidate` for every cell. See `direct_normal.zig` lines 187-232.
- For publication input, `sourceCandidate` reaches `cluster.sourceRenderableTextFromPublication`, which maps a full `SourceCell` through `publication_cell_map.mapPublicationCellInput`, infers publication span, constructs a `RenderableCell`, constructs inline text, and only then classifies the candidate. See `direct_normal.zig` lines 241-263 and `shape/cluster.zig` lines 549-555.
- `mapPublicationCellInput` pays the full semantic/color/style/presentation mapping cost every scanned publication cell: semantic truth, fg/bg/underline colors, style, presentation, inverse, selection, and empty classification. See `publication_cell_map.zig` lines 33-66.
- `publicationCellTruth` already defines the narrow empty/default truth for publication cells without building a full `CellInput`. See `publication_cell_map.zig` lines 81-91.
- `lane.classifyRenderableCell` only marks normal input complex for multi-codepoint text, emoji presentation, special sprite route, icon codepoint, or curly underline. See `classify/lane.zig` lines 218-280.
- For simple ASCII publication cells with default colors, no combining codepoints, no continuation, no inverse/selection, no underline/strike/dim/invisible, no special/icon route, and one-cell span, the generic path computes facts that are already directly readable from `SourceCell`: text is normal, style is regular, presentation is any, semantic colors are default, fg/bg are theme defaults, and span is one.
- The current scan debt remains after the earlier single-pass publication slice because the earlier slice removed duplicated publication scanning on fallback, but the successful all-normal publication path still uses the generic publication mapping/classification machinery for every cell. The current timing proves that generic per-cell scan is now visible again after owner-create and payload costs were reduced.
- Direct-normal tests already prove publication ASCII stays out of the legacy path at `frame_preparer.zig` lines 961-1015, and publication complex fallback behavior at lines 1136-1251. Those are the adjacent text publication tests that own the next proof surface.

Why this is not another owner:

- `session/text.zig` only chooses the direct-normal attempt and records timing. It does not own per-cell scan policy.
- `frame_preparer.zig` routes publication input into direct-normal and collects timings. It does not own the hot per-cell publication mapping.
- `publication_cell_map.zig` owns full source-to-text semantic translation, but the next slice does not need to change that truth. The direct-normal owner can bypass it only for a strictly proven subset whose generic result is mechanically identical and can fall back to the existing mapper for all other cells.
- `shape/cluster.zig` owns shared sparse/fallback construction and generic source candidate helpers. The next slice should not move sparse ownership or rewrite the cluster path; it should keep fallback unchanged.

Proposed next worker slice: `direct-normal-publication-ascii-fast-candidate`

Purpose:

- Remove avoidable generic publication `CellInput` mapping and lane classification from the hot direct-normal scan for simple default-style ASCII publication cells, while preserving the existing generic path for every unsupported, styled, colored, wide, combined, selected, inverse, special, icon, emoji, or complex case.

Allowed files:

- `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`.
- `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`.

Required implementation shape:

- In `direct_normal.zig`, keep `prepare`, `appendVisible`, `appendRenderable`, `finishScene`, and existing fallback flow owned by direct-normal.
- Add a narrow publication candidate helper used only by `sourceCandidate` when `source == .publication`.
- The helper must return a direct `Candidate` only when all of these are true:
- The cell is not a continuation cell.
- The next cell is not a continuation cell, so the fast candidate has `cell_span == 1`.
- Damage includes the one-cell span using the same damage semantics as `cluster.includeDamage`.
- `combining_len == 0`.
- The codepoint is printable ASCII `0x20...0x7e` or tab, with tab treated as blank/no-sprite exactly as the existing direct path does.
- `fg_color.kind == 0`, `bg_color.kind == 0`, and `underline_color.kind == 0`.
- All style/visibility/selection/inverse flags are zero, except no exception is allowed for this first slice.
- `underline_style == 0`.
- `link_id == 0`.
- For a fast candidate, construct the same `RenderableCell` and `CellText` consequences as the existing generic publication path for the allowed subset: default semantic colors, theme default fg/bg, regular style, `.any` presentation, no underline/strike/dim/invisible, `first_cell == idx`, `cell_span == 1`, `text_id.value == 0`, inline one-codepoint text for visible ASCII, and blank text for default semantic empty space/tab.
- For any unsupported cell, fall back to the existing generic `cluster.sourceRenderableTextFromPublication` plus `lane.classifyRenderableCell` path. Do not return null merely because the fast helper does not apply.
- Preserve existing rejection semantics: complex publication input under `.require_all_normal` must still roll back scratch and continue counting rejected complex cells as today at `direct_normal.zig` lines 212-227.
- Do not add a new owner, manager, options bucket, cache, ABI surface, host hook, benchmark hook, or temporary instrumentation.
- Do not alter `publication_cell_map.zig`, `shape/cluster.zig`, owner-create files, prepared-handle files, VT source ABI files, or benchmark files in this slice.

Required assertions:

- Assert the fast helper only emits `cell_span == 1`.
- Assert the fast helper only emits default semantic colors and regular style.
- Assert blank fast candidates have first codepoint `0` and produce no sprite path through `appendRenderable`.
- Assert fallback remains available for unsupported publication cells instead of treating unsupported as complex rejection.
- Keep existing scratch rollback assertions at `direct_normal.zig` lines 131-132, 217-226, and 331-369 intact.
- Keep lane report validity assertions intact at `direct_normal.zig` lines 132, 218, 226, and 230.

Required tests:

- Run `/home/home/personal/projects/howl/howl-render`: `zig build test:unit`.
- Add an owner-local direct-normal unit test in `direct_normal.zig` proving a default-style printable ASCII publication cell takes the fast candidate and produces the same visible sprite/draw consequence as the generic path would: one sprite draw, one raster request/output on first raster, one normal visible cell, one normal cluster, zero complex cells, no legacy fallback.
- Add an owner-local direct-normal unit test in `direct_normal.zig` proving a default semantic empty publication space or tab takes the fast candidate as blank: visible normal cell, zero normal clusters, zero sprite draws, zero raster requests/outputs, and background consequence remains available through later direct-scene background building.
- Add an adjacent publication test in `frame_preparer.zig` or extend the existing publication ASCII test at lines 961-1015 to assert ASCII publication still stays out of the legacy path after the fast candidate change.
- Add or extend a publication complex/fallback test in `frame_preparer.zig` around lines 1136-1251 proving unsupported non-ASCII or combining publication input still falls through to the existing complex path and records `resolved_runs == 1`, `shaped_runs == 1`, with no missing glyph regression.
- Do not add benchmark-only tests, host tests, ABI tests, or temporary instrumentation tests.

Required verification commands:

- `/home/home/personal/projects/howl/howl-render`: `zig build test:unit`.
- `/home/home/personal/projects/howl/howl-linux-host`: `zig build install -Doptimize=ReleaseFast`.
- `/home/home/personal/projects/howl/utils/tools/rain-bench`: `zig build --release=fast stress:rain:build`.
- `/home/home/personal/projects/howl`: `env HOWL_RENDER_DEBUG_TIMING=1 python3 utils/tools/rain-bench/benchmark_terminals.py --duration 3 --mode ascii --terminals howl 2> /tmp/opencode/howl-render-debug-control.log`.
- `/home/home/personal/projects/howl`: `python3 utils/tools/rain-bench/benchmark_terminals.py --duration 10 --mode ascii --terminals howl alacritty`.

Required receipt paths from worker:

- Exact 3-second Howl-only summary path under `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/<timestamp>-ascii/summary.json`.
- Exact 10-second Howl/Alacritty summary path under `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/<timestamp>-ascii/summary.json`.
- Exact stderr timing proof log path: `/tmp/opencode/howl-render-debug-control.log`.
- Quoted final `howl-render-debug prepare_handle count=640 ...` line.
- Quoted final `howl-render-debug prepared_handle_create count=640 ...` line.
- Quoted final `howl-render-debug emit_prepared count=640 ...` line.
- Coder session id.
- Files changed.
- Exact tests run.
- Commit-hash handoff status pending orchestrator closure.

Timing proof expectations:

- Baseline from current proof: `direct_normal_avg_us=991`, `direct_normal_scan_avg_us=883`, `owner_create_avg_us=361`, `prepared_handle_create emit_avg_us=360` at `/tmp/opencode/howl-render-debug-control.log` lines 13-15.
- The slice must lower `direct_normal_scan_avg_us` below `883` on the 640-count 3-second timing proof.
- The slice must not raise `owner_create_avg_us` above `361` by more than normal noise without a source-backed explanation, because owner-create is outside the slice.
- The slice must not regress 10-second Howl FPS below the accepted post-payload `55.54 fps` without stopping for review.
- The slice does not need to beat Alacritty in one step. It must prove the direct-normal scan owner debt moved in the right direction without changing render consequences.

Exact non-goals:

- No host, GL, presentation, PTY, VT parser, ABI, benchmark-wrapper, owner-create, sprite cache-first, fresh rollback, payload initialization, prepared-handle, or temporary instrumentation work.
- No changes to `publication_cell_map.zig`, `shape/cluster.zig`, `source/vt.zig`, prepared emitter/store files, host files, benchmark files, or build files.
- No new cache, retained publication renderable store, damage architecture change, row hash, dirty tracking, sprite-cache redesign, or fallback pipeline rewrite.
- No broad direct-normal rewrite beyond the narrow publication fast candidate seam.

Exact stop conditions:

- Stop if the fast candidate cannot preserve exact generic publication consequences for its allowed subset without touching `publication_cell_map.zig` or `shape/cluster.zig`.
- Stop if ASCII rain publication cells are not in the simple default-style subset and the proposed fast candidate would not hit the measured workload.
- Stop if correctness requires changing C ABI source cell shape or VT publication semantics.
- Stop if tests expose that direct-normal currently depends on full `CellInput` mapping for default ASCII semantics in a way not captured here.
- Stop if timing does not lower `direct_normal_scan_avg_us` below `883`; report the measured value and do not broaden into another owner.
- Stop if a correctness issue appears in publication color, selection, inverse, continuation, or complex fallback semantics.
- Stop if worker needs to edit outside the two allowed files.

Risks:

- The fast helper is intentionally strict. If the benchmark emits styled or colored ASCII cells, this slice may not hit the hot path and must stop rather than broadening.
- Duplicating even a small subset of publication mapping inside direct-normal is acceptable only because the subset is tiny and asserted. If it grows beyond default-style ASCII/blank, ownership should be re-reviewed instead of expanding casually.
- The existing timing seam reports only aggregate scan time. It is enough for this slice because the source pin is current and the acceptance gate is a before/after scan timing reduction, but it will not identify sub-line residuals inside the new helper if the reduction is weak.

Proof gaps:

- Current proof does not count how many publication cells satisfy the strict fast subset. The worker must stop if code inspection or tests show ASCII rain does not match the subset.
- `direct_normal_scan_avg_us` is benchmark-noisy. Reviewer should require the 640-count line and the 10-second FPS receipt, not a one-off early 128-count line.
- The plan is documentation-only until reviewer acceptance and orchestrator commit-hash closure.

Readiness judgment:

- Ready for reviewer. One worker slice is source-pinned to the direct-normal owner seam, has exact allowed files, exact shape, tests, non-goals, stop conditions, assertions, receipt paths, and timing proof expectations.
