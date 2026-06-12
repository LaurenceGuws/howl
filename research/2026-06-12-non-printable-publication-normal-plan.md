Non-printable publication normal plan

Date: 2026-06-12.
Status: active researcher target.
Role owner: researcher.
Orchestrator session id: `orch-2026-06-11-ascii-rain-honest-performance-02`.
Researcher session id: `research-2026-06-12-non-printable-publication-normal-01`.
Reviewer session id: pending.
Planning commit-hash receipt: pending; documentation-only planning artifact on this pass.

Preload receipt:

- Role: researcher.
- Active sprint:
  - `/home/home/personal/projects/howl/sprints/2026-06-11-ascii-rain-honest-performance-sprint.md`.
- Active loop:
  - `/home/home/personal/projects/howl/loops/ascii-rain-live-loop.txt`.
- Active research:
  - `/home/home/personal/projects/howl/research/2026-06-12-non-printable-publication-normal-plan.md`.
- Current proof receipts:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-082436-ascii/summary.json`.
  - `/tmp/opencode/howl-render-debug-control.log`.
- Failed instrumentation probes retained as context only:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-082209-ascii/summary.json`.
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-082228-ascii/summary.json`.
- Accepted product baseline receipts:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-021917-ascii/summary.json`.
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-021928-ascii/summary.json`.
- Execution authorized:
  - research and planning only; no implementation from this pass.

Problem statement:

- The count-only generic-fallback proof resolved the prior vague bucket enough for planning.
- At `count=640`, live generic fallback was dominated by `unsupported_non_printable=6966461`, with `publication_generic_entered=6966461` and `publication_generic_normal=6966461`; every other unsupported reason and generic consequence count was `0` in the final proof line (`/tmp/opencode/howl-render-debug-control.log:17`).
- The accepted product baseline remains Howl `60.26 fps`, Alacritty `981.84 fps`, and accepted `direct_normal_scan_avg_us=811` (`loops/ascii-rain-live-loop.txt:660`, `loops/ascii-rain-live-loop.txt:667`).
- The next research task is to explain which non-printable publication cell classes dominate the live fallback and whether they can be fast-pathed safely without violating publication semantics.

Sources read in order:

1. `/home/home/personal/projects/howl/loop/flow.md:1-137`.
2. `/home/home/personal/projects/howl/loop/orcestrator.md:1-61`.
3. `/home/home/personal/projects/howl/loop/researcher.md:1-86`.
4. `/home/home/personal/projects/howl/loop/reviewer.md:1-57`.
5. `/home/home/personal/projects/howl/loop/coder.md:1-60`.
6. `/home/home/personal/projects/howl/sprints/current.txt:1-36`.
7. `/home/home/personal/projects/howl/loops/ascii-rain-live-loop.txt:1-780`.
8. `/home/home/personal/projects/howl/research/2026-06-12-non-printable-publication-normal-plan.md:1-50`.
9. `/home/home/personal/projects/howl/reference-index.md:1-273`.
10. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:1-400`.
11. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:1-400`.
12. `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig:1-562`.
13. `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig:1-293`.
14. `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig:1-500`, `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig:540-659`.
15. `/home/home/personal/projects/howl/howl-render/src/text/classify/lane.zig:1-596`.
16. `/home/home/personal/projects/howl/utils/tools/rain-bench/ascii_rain_stress.zig:1-292`.
17. `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-082436-ascii/summary.json:1-85`.
18. `/tmp/opencode/howl-render-debug-control.log:1-20`.
19. Adjacent current proof required to explain owner truth:
  - `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig:155-177`, `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig:959-1184`.
  - `/home/home/personal/projects/howl/howl-render/src/source/vt.zig:48-65`, `/home/home/personal/projects/howl/howl-render/src/source/vt.zig:103-174`.
  - `/home/home/personal/projects/howl/howl-render/src/text/classify/symbol_map.zig:1-48`.
  - `/home/home/personal/projects/howl/howl-vt/src/ffi/surface.zig:167-191`, `/home/home/personal/projects/howl/howl-vt/src/ffi/surface.zig:264-312`.
  - `/home/home/personal/projects/howl/howl-vt/src/screen/cell.zig:31-71`.
  - `/home/home/personal/projects/howl/howl-vt/src/screen/erase.zig:109-130`.
  - `/home/home/personal/projects/howl/howl-vt/src/screen/edit.zig:34-176`.
  - `/home/home/personal/projects/howl/howl-vt/src/screen/scroll.zig:26-102`.

Reference facts:

- The references win over existing Howl code until current source re-proves it (`reference-index.md:14-36`).
- TigerBeetle law requires explicit owner truth, bounded work, and assertions around both positive and negative space (`TIGER_STYLE.md:96-149`).
- TigerBeetle also requires directness over vague buckets; design work should solve the real problem before implementation and should not preserve technical debt for convenience (`TIGER_STYLE.md:37-60`, `TIGER_STYLE.md:221-229`).
- Architecture pressure favors deterministic owner-local work and proving the mental model before optimization (`ARCHITECTURE.md:92-100`, `ARCHITECTURE.md:281-307`, `ARCHITECTURE.md:329-376`).

Current-code facts:

- The publication direct-normal fast path currently accepts only printable ASCII `0x21...0x7e`, single-cell, non-link, non-selected, non-invisible, non-strikethrough, non-RGB, straight-underline publication cells (`direct_normal.zig:276-290`).
- When a publication cell is accepted by that fast path, it is forced to a `LaneClass.normal()` candidate and asserted to classify as `.normal` (`direct_normal.zig:263-274`).
- Unsupported publication cells fall through `sourceItem(source, idx)`, which maps the source cell through `publication_cell_map.mapPublicationCellInput`, re-runs lane classification, and then continues in generic direct-normal scan if the result is still normal (`direct_normal.zig:249-260`, `cluster.zig:549-555`).
- `publicationCellTruth` marks only `' '` and `'	'` as blank candidates for `empty`; `codepoint == 0` is not semantic empty by current owner truth (`publication_cell_map.zig:81-92`).
- Lane classification treats `codepoint == 0` and `'	'` as the `.blank` builtin route, which stays in the normal lane rather than the complex lane (`symbol_map.zig:4-11`, `lane.zig:260-280`, `lane.zig:483-496`).
- `appendRenderable` already has the exact behavior needed for blank-route cells: it appends the renderable cell, skips glyph lookup and sprite draw for `text.first_cp == 0 or text.first_cp == '\t'`, and still leaves backgrounds/decorations/clears to later direct-scene passes (`direct_normal.zig:420-425`, `direct_normal.zig:139-149`).
- The publication source seam preserves raw VT cell codepoints and attrs into `SourceCell`; it does not rewrite erased cells to spaces (`source/vt.zig:48-65`, `ffi/surface.zig:167-191`, `ffi/surface.zig:264-312`).
- VT owner truth for erased/default cells is `codepoint = 0`, not `' '`: `default_cell` is zero-codepoint, `eraseCell()` returns zero-codepoint with current attrs, and insert/delete/scroll operations refill exposed cells with `eraseCell()` or `default_cell` (`screen/cell.zig:68-71`, `screen/erase.zig:128-130`, `screen/edit.zig:34-176`, `screen/scroll.zig:26-102`).
- The ASCII rain workload writes only printable glyphs in ASCII mode, `33...126`, and introduces non-printable visible cell states only through erase/scroll/edit control consequences (`ascii_rain_stress.zig:197-245`, `ascii_rain_stress.zig:228-239`).
- The live proof line shows that all generic publication fallback in the workload lands in `unsupported_non_printable`, while `unsupported_space`, `unsupported_tab`, `unsupported_rgb_*`, `unsupported_link`, `unsupported_selected`, `unsupported_invisible`, `unsupported_strikethrough`, `unsupported_underline_color`, `unsupported_underline_style`, `unsupported_combining`, `unsupported_continuation`, and `unsupported_multi_cell_span` are all `0` (`/tmp/opencode/howl-render-debug-control.log:17`).

Workload conclusion:

- The dominant live class is not semantic-empty space.
- The dominant live class is control-derived blank publication cells with `codepoint == 0` that still classify `normal`.
- Those cells are produced by VT erase/default/edit/scroll owners, may carry current default or indexed attrs because `eraseCell()` copies `current_attrs`, and are intentionally preserved as zero-codepoint cells through the publication ABI.
- At the render seam, erase consequences, insert/delete exposed blanks, and scroll-exposed blanks collapse to the same owner-truth shape: `SourceCell{ codepoint = 0, combining_len = 0, flags.continuation = 0, attrs... }`.
- Because the publication fast path currently rejects all `codepoint < 0x21`, these zero-codepoint cells pay generic publication mapping plus generic lane classification even though lane already says they are normal.

Fast-path safety judgment:

- Safe: fast-path `codepoint == 0` publication cells inside `direct_normal.zig` when every other existing fast-path restriction still holds.
- Safe because the generic path already proves these cells are normal, `appendRenderable` already suppresses sprite work for `text.first_cp == 0`, and backgrounds/decorations remain owned by the same direct-scene passes.
- Not safe in this slice: broad “all non-printable” support, semantic-empty rewrites, converting zero-codepoint cells to spaces, changing publication truth in `publication_cell_map.zig`, or widening to RGB/links/selection/invisible/strikethrough/underline-color/curly/multi-cell/combining/continuation cases.
- Important owner truth: the render seam cannot honestly distinguish “erase” from “scroll” once the VT publication owner has emitted a `SourceCell`; the truthful optimization target is the zero-codepoint publication cell shape, not upstream control-op names.

Compact anchor map:

- Stable references:
  - `reference-index.md:14-36` for reference precedence.
  - `TIGER_STYLE.md:96-149` for assertions and negative-space proof.
  - `ARCHITECTURE.md:92-100` for prove-the-model-first pressure.
- Current owner seams:
  - VT creates and publishes zero-codepoint blank cells: `screen/cell.zig:68-71`, `screen/erase.zig:128-130`, `screen/edit.zig:34-176`, `screen/scroll.zig:26-102`, `ffi/surface.zig:167-191`.
  - Publication source preserves that cell shape: `source/vt.zig:48-65`.
  - Render fast/generic split happens only in `direct_normal.zig:249-290`.
  - Generic path already proves zero-codepoint cells are normal: `cluster.zig:549-555`, `lane.zig:260-280`, `symbol_map.zig:4-11`.
  - Direct scene already knows how to skip glyphs for blank-route cells while still drawing backgrounds/decorations: `direct_normal.zig:420-425`.

Owner roles and proposed shape:

- True owner seam: `howl-render/src/text/direct_normal.zig`.
- Supporting proof root only: `howl-render/src/text/frame_preparer.zig` unit tests.
- No upstream VT, host, ABI, or benchmark-wrapper owner change is required for the next slice.

Proposed next worker slice:

- Slice name: `direct-normal-publication-zero-codepoint-fast-candidate`.
- Goal: remove generic publication mapping/classification for zero-codepoint publication cells that are already normal by owner truth, while preserving fallback for every other unsupported publication case.

Exact allowed files:

- `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`.
- `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`.

Not allowed:

- Any other file.

Exact required shape:

- Extend the publication fast-candidate decision in `direct_normal.zig` so `codepoint == 0` is admitted under the same restrictions already applied to the styled/indexed printable ASCII subset.
- Treat `codepoint == 0` as the only supported non-printable fast-candidate shape in this slice. Tabs, spaces, other controls, and every other blank-route peer must stay on generic fallback.
- Keep the fast path publication-local. Do not move or duplicate publication truth into new owners.
- Preserve current `SourceCell -> CellInput` semantics for the generic path. The slice must not rewrite `codepoint == 0` into `' '` or mark it `empty`.
- Reuse the existing blank-route behavior in `appendRenderable`; do not add a fake sprite path for zero-codepoint cells.
- Preserve generic fallback for every other unsupported publication cell and preserve no-partial-scratch behavior on fallback.

Required assertions:

- Keep or add an assertion that a zero-codepoint publication fast candidate still classifies `normal` before inclusion.
- Keep or add an assertion that the produced text for the zero-codepoint fast candidate has exactly one codepoint and that it is `0`.
- If a helper splits zero-codepoint support from printable ASCII support, assert the helper’s negative space explicitly so tabs, spaces, and every unsupported non-printable still fall through to generic fallback.

Required owner-local tests:

- Add one `direct_normal.zig` owner-local test proving a publication cell with `codepoint == 0` returns `.candidate` from the publication fast-candidate owner seam instead of `.unsupported`.
- Add one `direct_normal.zig` owner-local negative-space test proving `codepoint == '\t'` and another non-printable such as `0x1f` both stay `.unsupported` at the same owner seam.
- Add a publication test that `codepoint == 0` with default colors stays on the direct-normal path, produces no sprite draw, and does not enter shaped runs.
- Add a publication test that `codepoint == 0` with indexed colors and allowed attrs already supported by the printable fast path still stays on the direct-normal path and preserves background/decorations semantics.
- Add a publication test that `codepoint == '\t'` stays on generic fallback without partial direct scratch leakage.
- Add a publication test that another non-printable codepoint such as `0x1f` still falls back through the generic publication path without partial direct scratch leakage.

Required commands and verification:

- `/home/home/personal/projects/howl/howl-render`: `zig build test:unit`.
- `/home/home/personal/projects/howl/howl-linux-host`: `zig build install -Doptimize=ReleaseFast`.
- `/home/home/personal/projects/howl/utils/tools/rain-bench`: `zig build --release=fast stress:rain:build`.
- `/home/home/personal/projects/howl`: `env HOWL_RENDER_DEBUG_TIMING=1 python3 utils/tools/rain-bench/benchmark_terminals.py --duration 3 --mode ascii --terminals howl 2> /tmp/opencode/howl-render-debug-control.log`.
- `/home/home/personal/projects/howl`: `python3 utils/tools/rain-bench/benchmark_terminals.py --duration 10 --mode ascii --terminals howl alacritty` only if the 3-second timing gate passes.

Timing proof expectations:

- Required 3-second receipt path: `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/<timestamp>-ascii/summary.json`.
- Required timing log path: `/tmp/opencode/howl-render-debug-control.log`.
- Required 3-second gate: `direct_normal_scan_avg_us < 811`.
- Expected supporting signal: `direct_normal_avg_us` should also move down from the current `925`/`811` post-styled baseline pair recorded in the live loop (`loops/ascii-rain-live-loop.txt:667`).
- Required 10-second receipt path if the gate passes: `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/<timestamp>-ascii/summary.json`.
- Expected product proof if the gate passes: Howl should beat the accepted `60.26 fps` baseline; if micro timing improves but the 10-second product receipt does not, the worker must stop and report that mismatch rather than broadening scope.

Exact non-goals:

- No host, GL, PTY, VT, ABI, benchmark-wrapper, or owner-create work.
- No publication truth rewrite in `publication_cell_map.zig`.
- No semantic-empty optimization retry.
- No broad “all non-printables” fast path.
- No tab fast path.
- No RGB, link, selection, invisible, strikethrough, underline-color, curly-underline, combining, continuation, or multi-cell-span support expansion.
- No temporary instrumentation beyond the existing `HOWL_RENDER_DEBUG_TIMING` proof seam.

Exact stop conditions:

- Stop if truthful zero-codepoint support requires touching any file outside the two allowed files.
- Stop if unit tests or the benchmark proof show that zero-codepoint publication cells do not preserve generic-path semantics for backgrounds/decorations/blank-route glyph suppression.
- Stop if truthful owner-local proof cannot keep `codepoint == 0` as the only supported non-printable fast-candidate shape without widening to tabs, spaces, or other blank-route peers.
- Stop if the 3-second rerun does not beat `direct_normal_scan_avg_us=811`.
- Stop if the 3-second timing gate passes but the 10-second product rerun fails to beat the accepted `60.26 fps` baseline; report the mismatch instead of widening the slice.

Receipt fields required from the worker:

- coder session id.
- files changed.
- exact tests run.
- exact updated receipt paths.
- quoted timing lines from `/tmp/opencode/howl-render-debug-control.log`.
- exact before/after `direct_normal_avg_us` and `direct_normal_scan_avg_us`.
- exact before/after Howl FPS and Alacritty FPS if the 10-second rerun is reached.
- commit-hash handoff status pending orchestrator closure.

Risks:

- The render seam cannot distinguish erase-origin from scroll-origin zero-codepoint cells; the slice must stay on the shared shape, not invent origin-specific policy.
- Zero-codepoint fast support may cut scan cost but still miss the product gate if the remaining cost is elsewhere in `appendVisible`.
- Styled zero-codepoint cells may be numerous enough to help materially, but that still needs proof on the clean tree.

Proof gaps:

- The clean proof receipts count unsupported reasons, not zero-codepoint values directly. Current source plus the ASCII rain workload make zero-codepoint the only source-backed live explanation, but the worker should stop if clean-tree results contradict that model.
- The render seam cannot measure erase vs scroll vs insert/delete shares separately without new instrumentation, and that instrumentation is not authorized for this slice.

Readiness judgment:

- Ready.
- The truthful next worker slice is a narrow zero-codepoint publication fast candidate in `direct_normal.zig` with owner-local publication tests in `frame_preparer.zig`.
- No bigger correctness blocker or vague bucket remains at the render seam on current proof.
