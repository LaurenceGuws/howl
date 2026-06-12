Styled ASCII direct-normal scan plan

Date: 2026-06-12.
Status: active researcher package ready for reviewer.
Role owner: researcher.
Orchestrator session id: `orch-2026-06-11-ascii-rain-honest-performance-02`.
Researcher session id: `research-2026-06-12-styled-ascii-direct-normal-scan-01`.
Reviewer session id: pending.
Planning commit-hash receipt: pending.

Preload receipt:

- Role: researcher
- Active sprint:
  - `/home/home/personal/projects/howl/sprints/2026-06-11-ascii-rain-honest-performance-sprint.md`
- Active loop:
  - `/home/home/personal/projects/howl/loops/ascii-rain-live-loop.txt`
- Active research:
  - `/home/home/personal/projects/howl/research/2026-06-12-styled-ascii-direct-normal-scan-plan.md`
- Current proof receipts:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-015956-ascii/summary.json`
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-020015-ascii/summary.json`
  - `/tmp/opencode/howl-render-debug-control.log`
- Accepted baseline receipts:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-014446-ascii/summary.json`
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-014500-ascii/summary.json`
- Execution authorized:
  - research and planning only; no implementation from this pass

Sources read in required order:

- `/home/home/personal/projects/howl/loop/flow.md`
- `/home/home/personal/projects/howl/loop/orcestrator.md`
- `/home/home/personal/projects/howl/loop/researcher.md`
- `/home/home/personal/projects/howl/loop/reviewer.md`
- `/home/home/personal/projects/howl/loop/coder.md`
- `/home/home/personal/projects/howl/sprints/current.txt`
- `/home/home/personal/projects/howl/loops/ascii-rain-live-loop.txt`
- `/home/home/personal/projects/howl/research/2026-06-12-styled-ascii-direct-normal-scan-plan.md`
- `/home/home/personal/projects/howl/reference-index.md`
- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `/home/home/personal/projects/howl/utils/tools/rain-bench/ascii_rain_stress.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
- `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`
- `/home/home/personal/projects/howl/howl-render/src/source/vt.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/classify/lane.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/contract.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/scene.zig`
- `/home/home/personal/projects/howl/howl-vt/src/ffi/surface.zig`
- `/home/home/personal/projects/howl/howl-vt/src/screen/style.zig`
- `/home/home/personal/projects/howl/howl-vt/src/screen/color.zig`
- `/home/home/personal/projects/howl/howl-vt/src/screen/cell.zig`
- Proof receipts listed above

Problem statement:

- The strict default-style ASCII fast-candidate slice hit its accepted stop condition and was not committed.
- The proof showed live ASCII-rain does not fit the default-style subset because `/home/home/personal/projects/howl/utils/tools/rain-bench/ascii_rain_stress.zig` emits random SGR foreground/background/style changes in ASCII mode.
- The failed timing reruns did not beat the accepted baseline: `direct_normal_scan_avg_us=891` and `887` versus the accepted baseline `883`.
- The current top bottleneck remains direct-normal scan debt on styled/color ASCII publication cells.

Compact anchor map:

- TigerBeetle style anchors:
  - `TIGER_STYLE.md:96-100` requires bounded loops and explicit limits.
  - `TIGER_STYLE.md:104-140` requires assertions for positive and negative space.
  - `TIGER_STYLE.md:158-176` requires small scope, centralized control flow, and parent-owned branching.
  - `TIGER_STYLE.md:231-264` pushes hot loops toward predictable data-plane work with explicit mechanics.
  - `ARCHITECTURE.md:408-423` separates control-plane checks from data-plane loops and supports moving hot-loop branching out when the input class is homogeneous.
- Current workload anchors:
  - `ascii_rain_stress.zig:103-105` selects ASCII mode with `--ascii`.
  - `ascii_rain_stress.zig:211-214` emits SGR before cursor-positioned glyph writes in the dense loop.
  - `ascii_rain_stress.zig:221-226` emits `style;38;5;fg;48;5;bg`, where `style` is randomly `0...7` and both colors are indexed `0...255`.
  - `ascii_rain_stress.zig:241-245` emits only printable ASCII bytes `33...126` in ASCII mode.
  - `ascii_rain_stress.zig:268-276` emits long-line printable ASCII with more random SGR changes.
- Current publication and mapping anchors:
  - `howl-vt/src/screen/style.zig:32-60` maps SGR `0...7` to reset, bold, dim, italic, straight underline, blink, and reverse; `38;5` and `48;5` are handled by `style.zig:101-119` as indexed colors.
  - `howl-vt/src/ffi/surface.zig:167-190` publishes codepoint, combining, continuation, fg/bg/underline colors, attrs, and link id into `FfiSurfaceCell`.
  - `howl-render/src/source/vt.zig:48-65` defines the render-side `SourceCell` ABI shape consumed by publication rendering.
  - `howl-render/src/source/vt.zig:194-225` validates codepoints, combining count, color kinds, and underline style ranges.
  - `howl-render/src/source/publication_cell_map.zig:33-65` maps each publication cell to `CellInput`, including font style, semantic colors, rgba colors, dim/invisible, underline, strikethrough, continuation, empty truth, inverse, and selection.
  - `publication_cell_map.zig:81-91` defines semantic empty truth; blank cells are empty only with default fg/bg, no combining, no continuation, no inverse, no underline, and no strikethrough.
  - `publication_cell_map.zig:94-110` swaps colors for inverse and selection and forces non-empty.
  - `publication_cell_map.zig:149-157` maps default/indexed/rgb semantic color identity.
  - `publication_cell_map.zig:159-164` maps bold/italic to `FontStyle`; dim is a separate alpha modifier.
  - `publication_cell_map.zig:166-174` maps underline style values; value `2` is curly.
- Current direct-normal owner anchors:
  - `direct_normal.zig:110-151` owns direct-normal preparation, scan timing, fallback rejection, scene append, and finish.
  - `direct_normal.zig:187-232` owns the publication scan loop and the rollback/reject behavior for `.require_all_normal`.
  - `direct_normal.zig:241-245` maps each source cell to a candidate through the generic source path and then classifies it.
  - `direct_normal.zig:256-263` sends publication cells through `cluster.sourceRenderableTextFromPublication`, which calls the full publication mapper.
  - `direct_normal.zig:280-329` appends renderable cells, resolves the face, reserves the atlas entry, appends raster requests, and appends sprite draws.
  - `direct_normal.zig:406-418` already fast-resolves plain ASCII text to the primary face.
  - `frame_preparer.zig:155-178` owns the publication entrypoint and fallback to sparse/shaped scene if direct-normal rejects complex cells.
  - `frame_preparer.zig:220-223` asserts expected complex-cell counts when publication direct-normal rejection falls through the shared shaped-scene owner.
- Current generic fallback anchors:
  - `cluster.zig:328-376` builds sparse publication cells through the same publication mapper for fallback.
  - `cluster.zig:549-555` maps a publication cell to renderable text for the current direct-normal scan path.
  - `cluster.zig:677-704` defines the renderable-cell field mapping from `CellInput`.
  - `cluster.zig:785-790` infers publication cell span from continuation cells.
  - `lane.zig:260-270` classifies a cell as normal when it is single-codepoint, not emoji, not builtin special sprite, not icon, and not curly underline.
  - `scene.zig:1136-1158` applies dim and invisible effects to sprite colors.
  - `direct_scene.zig:35-67` routes direct-normal backgrounds, clears, cursor, and decorations through the shared scene helpers.

Current-code facts:

- The live ASCII workload uses printable ASCII glyph bytes only in ASCII mode, not Unicode, combining marks, emoji, wide cells, or links. The exact glyph range from the stress tool is `33...126`.
- The live workload also uses random indexed foreground and background colors and random SGR styles `0...7`; the exact emitted SGR form is `ESC[{style};38;5;{fg};48;5;{bg}m`.
- Because style values accumulate except for `0`, live cells may carry combinations of bold, dim, italic, straight underline, blink, and reverse. The stress source does not emit SGR `8` invisible, SGR `9` strikethrough, underline-color SGR `58`, OSC 8 hyperlinks, RGB colors, combining marks, or wide Unicode in ASCII mode.
- The current direct-normal publication scan pays the generic publication mapping/classification cost for every cell through `cluster.sourceRenderableTextFromPublication` before it can learn that the cell is normal.
- The direct-normal fallback semantics are already correct: when a `.require_all_normal` publication scan sees a complex candidate, it rolls back direct scratch state, counts rejected complex cells, returns null, and `frame_preparer` continues through sparse publication and shaped-scene fallback.
- A styled/color ASCII fast candidate is safe only if unsupported cells do not become skips. Unsupported publication cells must fall through to the existing generic source candidate so current fallback/reject semantics remain unchanged.
- A fast candidate that returns `null` for both unsupported and damage-skipped cells would be unsafe or slow. The worker must use an explicit local result shape that distinguishes `candidate`, `skip`, and `unsupported` for publication cells.
- The current direct-normal unmanaged decoration path supports straight, double, dotted, and dashed underline but not curly underline; lane classification marks only curly underline complex. The live workload emits only straight underline through SGR `4`.
- Blink is published by VT but not mapped into `CellInput` today. A fast candidate must ignore blink exactly as the generic mapper does.
- Inverse affects foreground/background and empty truth in the generic mapper. Because the live workload emits SGR `7`, a candidate that does not reproduce inverse color swapping is not correct for the live subset.

Styled/color ASCII subset conclusion:

- The live workload subset is publication cells with:
  - `codepoint` in printable non-space ASCII `0x21...0x7e` from explicit glyph writes.
  - `combining_len == 0`.
  - `flags.continuation == 0` and inferred publication span exactly `1`.
  - no link id.
  - foreground and background color kinds `default` or `indexed`, with the actual live SGR path using `indexed` for both foreground and background.
  - attrs limited to bold, dim, italic, straight underline, blink, and inverse; blink must be ignored because the generic mapper ignores it.
  - no underline color, no selected attr, no invisible attr, no strikethrough attr, no curly underline, no non-straight underline styles for this worker slice.
- This subset can be safely fast-candidated inside `direct_normal.zig` only if every cell outside the subset falls through to the current generic publication mapping/classification path. The worker must not weaken the existing `.require_all_normal` rollback or fallback behavior.
- The proposed slice does not need VT changes because VT already publishes enough exact source fields to prove the subset and render consequences.

Owner roles:

- `howl-render/src/text/direct_normal.zig` owns the hot scan decision, direct-normal scratch mutation, atlas reservation, raster request append, and fallback rollback contract.
- `howl-render/src/text/frame_preparer.zig` owns publication entrypoint tests and the proof that unsupported publication cells still fall through to the shaped-scene fallback.
- `howl-render/src/source/publication_cell_map.zig` remains the generic mapping authority. The worker may read it but must not change it in this slice.
- `howl-vt` owns source publication and SGR interpretation. The worker may read it but must not change it in this slice.

Reviewer-gated worker slice: `direct-normal-styled-ascii-publication-fast-candidate`

Purpose:

- Remove generic publication cell mapping and lane classification from the direct-normal scan for the proven styled/color ASCII publication subset, while keeping every unsupported publication cell on the existing generic fallback path.

Allowed files:

- `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`

Not allowed:

- Any other file.
- No VT source edits.
- No `publication_cell_map.zig` edits.
- No host, GL, benchmark-wrapper, PTY, ABI, owner-create, sprite cache, fresh rollback, payload initialization, or temporary instrumentation edits.
- No new owner files, helper buckets, manager/controller/utils shapes, benchmark harness changes, or compatibility aliases.

Required implementation shape:

- In `direct_normal.zig`, keep `appendVisible` as the owner of the scan loop and fallback decision.
- Add a private publication-only candidate path used by `sourceCandidate` before the existing generic `cluster.sourceRenderableTextFromPublication` path.
- The publication-only path must return a local explicit result with three outcomes:
  - candidate: a fully built `Candidate` for a supported styled/color ASCII cell.
  - skip: the cell is supported by the fast subset but outside normalized damage, so it must be skipped without falling through to generic mapping.
  - unsupported: the cell is outside the fast subset and must fall through to the existing generic source candidate.
- The candidate path must accept only cells with inferred publication span `1`. Any continuation or multi-cell span must be unsupported, not skipped.
- The candidate path must build the same render-visible fields as `publication_cell_map.mapPublicationCellInput` plus `cluster.renderableFromCellInput` for the accepted subset:
  - `text_id = .{ .value = 0 }`.
  - `first_cell = idx`.
  - `cell_span = 1`.
  - `style = regular|bold|italic|bold_italic` from bold/italic attrs.
  - `presentation = .any`.
  - `dim = attrs.dim != 0`.
  - `invisible = false` because invisible is outside the accepted subset.
  - semantic foreground/background from source color kind and value.
  - rgba foreground/background from default theme or palette only.
  - inverse color swap when `attrs.inverse != 0`.
  - `underline = attrs.underline != 0` only when `underline_style == 0` or straight-equivalent value.
  - `underline_style = .straight`.
  - `underline_color_set = false`, semantic underline default, underline rgba alpha zero.
  - `strikethrough = false`.
  - `continuation = false`.
  - `text.first_cp = codepoint`, `text.codepoints` as the one inline codepoint, and no heap allocation.
  - `choice = lane.LaneClass.normal()` or equivalent existing constructor, with an assertion that the constructed candidate is normal by construction.
- The candidate path must reject to generic fallback for:
  - `codepoint < 0x21` or `codepoint >= 0x7f`; spaces, tabs, controls, blanks, and erase/scroll consequences are not in this fast subset.
  - `combining_len != 0`.
  - any continuation or inferred span not equal to `1`.
  - `link_id != 0`.
  - invalid color kind, out-of-range indexed color, or any RGB color kind; RGB is not in this worker slice and must fall through to the generic mapper.
  - `attrs.selected != 0`.
  - `attrs.invisible != 0`.
  - `attrs.strikethrough != 0`.
  - `attrs.underline_color_set != 0`.
  - underline style other than straight for underlined cells.
  - curly underline always.
- The candidate path must not record lane counters itself except through the existing `candidateDecision` and `appendRenderable` flow.
- The generic publication path must remain the only fallback for unsupported publication cells.
- The existing rollback assertions in `appendVisible` must remain intact.

Required assertions:

- Assert source index bounds before reading source cells in the new publication candidate helper.
- Assert accepted indexed colors are within `u8` before palette indexing.
- Assert accepted color kinds are only default or indexed; RGB must not enter the fast candidate.
- Assert accepted publication span is exactly `1`.
- Assert accepted candidates have a single codepoint and `lane` normal classification.
- Assert unsupported cells do not mutate direct-normal scratch state.
- Preserve existing `scratchEmpty`, `lane_report.assertValid`, and rejected-complex assertions.

Required tests:

- Run existing unit root:
  - `/home/home/personal/projects/howl/howl-render`: `zig build test:unit`
- Add or sharpen owner-local tests in `frame_preparer.zig` because the existing publication direct-normal tests live there:
  - A styled indexed ASCII publication source with bold, dim, italic, straight underline, blink, and inverse stays on the direct-normal path: `resolved_runs == 0`, `shaped_runs == 0`, expected sprite/background/decorations exist, sprite foreground reflects inverse plus dim/invisible rules exactly as the generic mapper would, and background color reflects the swapped foreground/background when inverse is set.
  - A non-inverse indexed-color ASCII publication source stays on the direct-normal path and preserves semantic foreground/background identity through render-visible consequences already exposed by scene draws.
  - A publication ASCII cell with space remains unsupported by the fast candidate and reaches the existing generic path without direct-normal partial scratch leakage.
  - A publication ASCII cell with RGB foreground or background remains unsupported by the fast candidate and reaches the existing generic path without direct-normal partial scratch leakage.
  - A publication ASCII cell with curly underline remains unsupported by the fast candidate and reaches the generic complex fallback without direct-normal partial scratch leakage: the frame is produced, direct-normal does not claim normal-only completion, and resolved/shaped or glyph-group counters prove the complex path ran.
  - A publication ASCII cell with combining mark remains unsupported by the fast candidate and reaches the existing generic fallback without direct-normal partial scratch leakage.
  - A publication ASCII cell with `link_id != 0` remains unsupported by the fast candidate and still produces the same fallback behavior as the current generic path without direct-normal partial scratch leakage.
- Do not add tests outside the two allowed files.

Required verification commands:

- `/home/home/personal/projects/howl/howl-render`: `zig build test:unit`
- `/home/home/personal/projects/howl/howl-linux-host`: `zig build install -Doptimize=ReleaseFast`
- `/home/home/personal/projects/howl/utils/tools/rain-bench`: `zig build --release=fast stress:rain:build`
- `/home/home/personal/projects/howl`: `env HOWL_RENDER_DEBUG_TIMING=1 python3 utils/tools/rain-bench/benchmark_terminals.py --duration 3 --mode ascii --terminals howl 2> /tmp/opencode/howl-render-debug-control.log`
- `/home/home/personal/projects/howl`: `python3 utils/tools/rain-bench/benchmark_terminals.py --duration 10 --mode ascii --terminals howl alacritty`

Required receipt fields from the worker:

- Coder session id.
- Files changed.
- Exact tests and commands run.
- Exact updated 3-second `summary.json` receipt path.
- Exact updated 10-second `summary.json` receipt path.
- Exact timing log path: `/tmp/opencode/howl-render-debug-control.log`.
- Quoted final `howl-render-debug prepare_handle` line from the timing log.
- Before/after `direct_normal_avg_us`, `direct_normal_scan_avg_us`, `direct_normal_backgrounds_avg_us`, `direct_normal_decorations_avg_us`, and `owner_create_avg_us`.
- Before/after Howl FPS and Alacritty FPS from the 10-second summary.
- Commit-hash handoff status pending orchestrator closure.

Timing proof expectations:

- Accepted baseline timing proof from `/tmp/opencode/howl-render-debug-control.log` after the failed default-style candidate:
  - `direct_normal_avg_us=1002`
  - `direct_normal_scan_avg_us=887`
  - `owner_create_avg_us=334`
- Accepted baseline product proof from `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-014500-ascii/summary.json`:
  - Howl `55.54 fps`
  - Alacritty `987.81 fps`
- Failed default-style fast-candidate receipts:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-015956-ascii/summary.json`
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-020015-ascii/summary.json`
  - Failed timing values reported by the loop: `direct_normal_scan_avg_us=891` and `887`.
- Acceptance requires the 3-second timing rerun to lower `direct_normal_scan_avg_us` below the accepted baseline `883` from the post-payload bottleneck proof and below the failed rerun values.
- Acceptance requires the 10-second Howl FPS not to regress below `55.54 fps` and the run to complete with final metrics for both Howl and Alacritty.
- If `direct_normal_scan_avg_us` does not improve below `883`, the worker must stop and report the stop condition rather than broaden the slice.

Non-goals:

- No spaces, tabs, controls, blanks, erase/scroll blank fast path, Unicode, mixed mode, combining, wide cells, emoji, icon codepoints, box/special sprites, links, selection, RGB support, underline-color support, invisible support, strikethrough support, non-straight underline support, or curly underline support.
- No change to fallback semantics.
- No change to `publication_cell_map.zig` generic truth.
- No change to VT publication, ABI structs, terminal parser, host loop, GL backend, prepared-handle owner, owner-create path, sprite cache, payload initialization, or benchmark wrapper.
- No temporary instrumentation.
- No new files.

Stop conditions:

- Stop if the worker cannot distinguish supported damage-skips from unsupported cells without weakening fallback semantics.
- Stop if the fast candidate would need to mutate or duplicate broad publication truth outside the exact subset above.
- Stop if the implementation requires edits outside the two allowed files.
- Stop if a test proves the live workload includes combining, wide, link, selection, curly underline, invisible, strikethrough, or underline-color cells in the hot subset.
- Stop if unsupported cells bypass the existing generic fallback path.
- Stop if `.require_all_normal` rollback, rejected-complex counting, or scratch-empty assertions need to be weakened.
- Stop if `zig build test:unit` fails.
- Stop if the timing rerun does not lower `direct_normal_scan_avg_us` below `883`.
- Stop if the benchmark changes semantics, fails to emit final metrics, or regresses Howl below the accepted `55.54 fps` 10-second baseline.

Risks:

- The fast candidate will duplicate a small amount of publication mapping truth for the accepted subset. This is acceptable only because the subset is exact, owner-local to the hot direct-normal scan, and every unsupported cell falls back to the single generic mapper.
- The live workload may include blank or erased cells that are not printable glyph writes. This slice must leave those cells on the generic path and prove no direct-normal scratch leakage for the space case.
- An overly broad candidate could silently render selected, linked, curly-underlined, invisible, strikethrough, or combining cells incorrectly. The negative-space tests and stop conditions are mandatory.
- The timing gain may be smaller than expected if the remaining scan cost is dominated by atlas/glyph work rather than mapping/classification. The timing gate prevents accepting optimization theater.

Proof gaps:

- No current source proves that every visible publication cell in the live run is inside the exact accepted subset, because erase/insert/scroll consequences can produce cells not directly emitted by `emitGlyph`. The proposed candidate remains safe by falling unsupported cells back to generic mapping.
- There is no permanent per-cell subset telemetry, and temporary instrumentation is explicitly not authorized for this slice.
- The exact performance gain is unknown until the worker reruns the accepted timing proof.

Readiness judgment:

- Ready for reviewer.
- One worker slice is fully specified.
- Implementation is safe to seed only if the reviewer accepts the two-file boundary, the tri-state publication candidate result, the negative-space fallback tests, and the `direct_normal_scan_avg_us < 883` proof gate.
