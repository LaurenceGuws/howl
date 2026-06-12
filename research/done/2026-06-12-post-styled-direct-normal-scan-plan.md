Post-styled direct-normal scan plan

Date: 2026-06-12.
Status: active researcher target.
Role owner: researcher.
Orchestrator session id: `orch-2026-06-11-ascii-rain-honest-performance-02`.
Researcher session id: `research-2026-06-12-post-styled-direct-normal-scan-01`.
Reviewer session id: pending.
Planning commit-hash receipt: pending.

Preload receipt:

- Role: researcher
- Active sprint:
  - `/home/home/personal/projects/howl/sprints/2026-06-11-ascii-rain-honest-performance-sprint.md`
- Active loop:
  - `/home/home/personal/projects/howl/loops/ascii-rain-live-loop.txt`
- Active research:
  - `/home/home/personal/projects/howl/research/2026-06-12-post-styled-direct-normal-scan-plan.md`
- Current proof receipts:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-021917-ascii/summary.json`
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-021928-ascii/summary.json`
  - `/tmp/opencode/howl-render-debug-control.log`
- Execution authorized:
  - research and planning only; no implementation from this pass

Problem statement:

- The accepted styled ASCII direct-normal slice landed in `howl-render` commit `98bb85a` and root commit `ad7195f`.
- Howl improved to `60.26 fps`, but Alacritty remains `981.84 fps` on the same 10-second ASCII-rain telemetry.
- The post-styled bottleneck proof still ranks `direct_normal` first: `direct_normal_avg_us=925`, `direct_normal_scan_avg_us=811`, while `owner_create_avg_us=318`.
- The next research task is to source-pin the remaining direct-normal scan debt and produce one reviewer-acceptable worker slice.

Required current evidence:

- `howl-render-debug prepare_handle count=640 prepare_surface_avg_us=927 prepare_surface_max_us=19037 input_avg_us=0 session_preparer_avg_us=0 session_prepare_cells_avg_us=0 direct_normal_avg_us=925 direct_normal_scan_avg_us=811 direct_normal_backgrounds_avg_us=29 direct_normal_clears_avg_us=0 direct_normal_decorations_avg_us=47 direct_normal_cursor_avg_us=0 direct_normal_raster_avg_us=35 owner_create_avg_us=318 owner_create_max_us=1202`
- `howl-render-debug prepared_handle_create count=640 alloc_avg_us=0 alloc_max_us=1 register_avg_us=0 register_max_us=1 emit_avg_us=317 emit_max_us=1200`
- `howl-render-debug emit_prepared count=640 ... sprites_avg_us=302 ... atlas_resource_avg_us=133 ... publish_avg_us=1 ...`

Initial owner focus:

- `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
- adjacent direct-normal tests only if source proves they own the next slice

Research requirements:

- Read the live workflow, active loop, current sprint index, this file, TigerBeetle readings, and source/reference anchors before writing a plan.
- Explain what remains expensive in direct-normal scan after styled ASCII publication fast-candidate.
- Produce one reviewer-acceptable worker slice with exact allowed files, shape, tests, non-goals, stop conditions, assertions, receipt paths, and timing proof expectations.
- Do not drift into host, GL, benchmark-wrapper, PTY, VT, ABI, owner-create, sprite cache, fresh rollback, payload initialization, or temporary instrumentation unless current source proves it is required.
- Stop and report if the truthful next step exposes a big correctness issue or vague bucket.

Readiness judgment:

- Ready for reviewer gate after this researcher pass. The next worker slice is narrow, owner-local, and source-backed: add a safe direct-normal publication fast candidate for semantic-empty ASCII spaces only, preserving the generic fallback for every styled, colored, linked, selected, RGB, tab, combining, continuation, or otherwise unsupported blank.

Researcher pass receipt:

- Researcher session id:
  - `research-2026-06-12-post-styled-direct-normal-scan-01`
- Execution authorization:
  - research and planning only
  - no implementation performed
- Sources read in required order:
  - `/home/home/personal/projects/howl/loop/flow.md`
  - `/home/home/personal/projects/howl/loop/orcestrator.md`
  - `/home/home/personal/projects/howl/loop/researcher.md`
  - `/home/home/personal/projects/howl/loop/reviewer.md`
  - `/home/home/personal/projects/howl/loop/coder.md`
  - `/home/home/personal/projects/howl/sprints/current.txt`
  - `/home/home/personal/projects/howl/loops/ascii-rain-live-loop.txt`
  - `/home/home/personal/projects/howl/research/2026-06-12-post-styled-direct-normal-scan-plan.md`
  - `/home/home/personal/projects/howl/reference-index.md`
  - `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
  - `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`, only to prove semantic-empty publication blank truth before planning space handling
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-021917-ascii/summary.json`
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-021928-ascii/summary.json`
  - `/tmp/opencode/howl-render-debug-control.log`

Compact anchor map:

- Workflow authority:
  - `loop/flow.md:22-41` requires planning completion only after exact allowed files, shape, tests, non-goals, stop conditions, and accountable session ids are present.
  - `loop/researcher.md:60-75` requires line references, current-code facts, reference facts, owner roles, slice plan, assertions, tests, risks, proof gaps, and readiness judgment.
  - `loops/ascii-rain-live-loop.txt:663-675` promotes this exact post-styled direct-normal scan planning target after `direct_normal_scan_avg_us=811` remains the top bucket.
- Reference anchors:
  - `reference-index.md:21-24` assigns renderer organization pressure to Alacritty where applicable and Zig discipline to TigerBeetle.
  - `TIGER_STYLE.md:90-100` requires bounded simple control flow; the next slice must keep the publication scan as one bounded pass over `sourceLen(source)`.
  - `TIGER_STYLE.md:104-140` requires assertions for positive and negative space; the slice must assert semantic-empty blank invariants and test unsupported blank fallback.
  - `TIGER_STYLE.md:231-264` favors data-plane predictability and hot-loop directness; avoiding generic publication mapping/classification and glyph lookup for empty spaces is source-backed only if correctness stays explicit.
  - `ARCHITECTURE.md:408-423` separates control plane from data plane; the support decision must stay outside expensive per-cell glyph work for semantic-empty blank cells.
- Current owner seams:
  - `direct_normal.zig:110-151` owns direct-normal preparation timing and wraps `appendVisible` as `scan_us`.
  - `direct_normal.zig:195-240` owns the scan loop, lane-report rollback, rejected-complex counting, and scratch cleanliness.
  - `direct_normal.zig:249-261` currently tries the publication fast candidate first, then falls through to generic `sourceItem` mapping/classification when publication support says unsupported.
  - `direct_normal.zig:263-274` builds fast publication candidates only after `publicationCellSupported` and still asserts normal-lane classification.
  - `direct_normal.zig:276-290` rejects spaces because `cell.codepoint < 0x21` returns false before the styled ASCII fast path can help them.
  - `direct_normal.zig:292-331` constructs supported printable publication cells without going through `publication_cell_map.mapPublicationCellInput`.
  - `direct_normal.zig:412-461` appends renderable cells, resolves face, looks up glyphs, reserves atlas slots, and constructs sprite draws inside the measured scan bucket.
  - `frame_preparer.zig:155-178` proves publication direct-normal is first tried with `.require_all_normal`; rejected complex publication cells then fall back through the shared shaped-scene owner.
  - `frame_preparer.zig:1008-1184` contains the adjacent publication direct-normal tests that own this next slice.
  - `publication_cell_map.zig:81-91` defines semantic-empty publication blank truth: blank space or tab, no combining, default foreground/background, and no continuation, inverse, underline, or strikethrough.
  - `publication_cell_map.zig:186-195` asserts empty truth and classification; direct-normal space handling must preserve equivalent truth without taking over the map owner.

Current-code facts:

- `direct_normal.prepare` records `timings.scan_us` around only `appendVisible`; backgrounds, clears, decorations, cursor, and raster have separate timing buckets (`direct_normal.zig:121-150`).
- The current hot `direct_normal_scan` bucket includes publication support checks, generic fallback mapping, damage checks, lane classification, scratch append, face resolution, glyph lookup, atlas reservation, and sprite draw construction (`direct_normal.zig:195-261`, `direct_normal.zig:412-461`).
- The accepted styled ASCII fast candidate supports printable non-space ASCII only; `publicationCellSupported` still rejects every space before style/color checks because the first guard is `cell.codepoint < 0x21` (`direct_normal.zig:276-289`).
- Unsupported publication cells do not automatically reject the whole direct-normal path. They fall through to `sourceItem` and can still remain direct-normal if the generic publication mapper/classifier proves them normal (`direct_normal.zig:249-261`). This fallback behavior must remain intact.
- Existing publication tests prove that a default publication space has no sprite draw and does have background truth (`frame_preparer.zig:959-1006`). This is the correctness anchor that makes a semantic-empty space fast path possible.
- Existing tests also prove styled/indexed non-space ASCII stays direct-normal (`frame_preparer.zig:1064-1113`) and unsupported spaces/RGB keep fallback scratch clean (`frame_preparer.zig:1115-1132`). The next slice must not weaken these negative-space proofs.
- `publication_cell_map.publicationCellTruth` already owns semantic-empty classification for source publication cells (`publication_cell_map.zig:81-91`). The direct-normal fast path may rely on that public owner truth but must not edit the mapping owner in this slice.
- `appendRenderable` skips sprite work only when `text.first_cp == 0` or tab (`direct_normal.zig:420-425`). A semantic-empty publication space fast candidate can intentionally produce a blank `contract.CellText` with `first_cp = 0` so direct-normal appends the renderable for background/clear/decorations but does not resolve a face, look up a glyph, reserve atlas space, or append a sprite.
- `recordLane` increments `normal_clusters` only when `blankText(text)` is false (`direct_normal.zig:406-410`, `direct_normal.zig:557-562`). The semantic-empty space candidate must preserve blank text so counters do not invent glyph clusters.
- The live timing proof shows the direct-normal scan remains the largest logged owner bucket after styled ASCII: `direct_normal_avg_us=925`, `direct_normal_scan_avg_us=811`, `owner_create_avg_us=318`, and `emit_prepared sprites_avg_us=302` at count 640 (`/tmp/opencode/howl-render-debug-control.log:13-15`).
- The accepted 10-second receipt still shows a large external gap: Howl `60.26 fps` versus Alacritty `981.84 fps` (`20260612-021928-ascii/summary.json:70-80`, `20260612-021928-ascii/summary.json:108-118`).

What remains expensive after styled ASCII publication fast-candidate:

- The styled fast candidate removed generic mapping/classification for supported printable non-space publication ASCII, but the scan still pays per-cell work for publication spaces because spaces are explicitly unsupported at `direct_normal.zig:277`.
- Every unsupported publication space falls back through `sourceItem` and `cluster.sourceRenderableTextFromPublication` from `direct_normal.zig:388-394`, then damage and lane classification from `direct_normal.zig:258-260`. If the generic path treats the blank as normal, `appendRenderable` then still owns correctness for no-sprite blank output.
- For semantic-empty blank publication cells, this generic fallback is unnecessary work. The source map already proves the empty blank contract, and the direct-normal owner can create the exact blank renderable/text pair directly, append it, and skip face/glyph/atlas/sprite work through the existing `first_cp == 0` branch.
- The next slice is not a broad direct-normal redesign. It is a precise publication blank support extension that keeps unsupported blank variants on the existing generic fallback path.

Owner roles:

- `howl-render/src/text/direct_normal.zig` owns the direct-normal scan loop, publication fast candidate shape, scratch rollback, lane-report consequences, and scan timing.
- `howl-render/src/text/frame_preparer.zig` owns the adjacent publication preparation tests that prove direct-normal publication consequences through the public preparer seam.
- `howl-render/src/source/publication_cell_map.zig` owns semantic-empty truth, but this slice must not edit it. It is read-only reference/source evidence for the space subset.
- Host, GL, PTY, VT, ABI, benchmark-wrapper, owner-create, sprite-cache, fresh rollback, payload initialization, and temporary instrumentation owners are not part of this slice.

Proposed worker slice: `direct-normal-publication-empty-space-fast-candidate`

- Purpose:
  - remove generic publication mapping/classification and glyph/sprite work for semantic-empty publication spaces inside the existing direct-normal scan owner, while preserving fallback behavior for every non-empty or unsupported blank.
- Allowed files:
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
- Not allowed:
  - any other file
  - no edits to `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`
  - no temporary instrumentation
  - no benchmark harness edits
  - no host, GL, PTY, VT, ABI, owner-create, sprite cache, fresh rollback, or payload initialization edits

Required implementation shape:

- In `direct_normal.zig`, extend the publication fast-candidate path with a separate semantic-empty space case before the current printable non-space case rejects `cell.codepoint < 0x21`.
- The supported fast blank subset must be exactly:
  - `cell.codepoint == ' '`
  - `cell.combining_len == 0`
  - `cell.flags.continuation == 0`
  - `publicationCellSpan(cells, idx) == 1`
  - `cell.link_id == 0`
  - `cell.fg_color.kind == 0`
  - `cell.bg_color.kind == 0`
  - `cell.attrs.bold == 0`
  - `cell.attrs.dim == 0`
  - `cell.attrs.italic == 0`
  - `cell.attrs.underline == 0`
  - `cell.attrs.underline_color_set == 0`
  - `cell.attrs.blink == 0`
  - `cell.attrs.inverse == 0`
  - `cell.attrs.invisible == 0`
  - `cell.attrs.strikethrough == 0`
  - `cell.attrs.selected == 0`
  - `cell.underline_style == 0`
- The semantic-empty space path must construct a normal `cluster.RenderableText` with:
  - `renderable.first_cell = idx`
  - `renderable.cell_span = 1`
  - regular style and `.any` presentation
  - default semantic foreground/background
  - `fg = theme.default_fg`
  - `bg = theme.default_bg`
  - no underline, strikethrough, invisible, continuation, or underline color
  - blank text that causes `blankText(text)` to be true and `appendRenderable` to return before face/glyph/atlas/sprite work, preferably `text.first_cp = 0` with an empty codepoint slice if current contract permits it
- The worker must add assertions close to construction proving:
  - the cell is the exact semantic-empty space subset
  - the produced text is blank
  - the produced renderable has `cell_span == 1`
  - `lane.classifyRenderableCell(item.renderable, item.text).renderableClass() == .normal`
  - direct-normal scratch has no sprite/raster append for the blank via unit tests, not by instrumentation
- The existing unsupported path must remain tri-state:
  - supported printable non-space ASCII remains fast candidate
  - supported semantic-empty space becomes fast candidate
  - unsupported publication cells still fall through to `sourceItem` generic mapping and then to the existing reject/skip/include policy
- Do not collapse the publication blank logic into a broad bucket named `Options`, `Context`, `Info`, `Data`, or similar. If a helper is needed, use an owner-true name such as `publicationEmptySpaceSupported` and `publicationEmptySpaceRenderableText`.
- Keep the scan one bounded pass over `sourceLen(source)` and do not add a second publication scan.

Required assertions:

- Assert `idx < count32(cells)` at the publication candidate entry remains intact.
- Assert the positive supported blank subset in the blank construction helper, split into simple assertions rather than one compound assertion.
- Assert `publication_cell_map.publicationCellTruth(cell).empty` for the supported blank subset, because semantic-empty truth is owned by the publication map.
- Assert unsupported styled/colored/linked/continuation/combining/tab blanks do not enter the blank fast construction path.
- Assert lane-report validity after scan remains through the existing `lane_report.assertValid()` calls.
- Preserve existing scratch rollback assertions in `appendVisible` unchanged.

Required tests:

- Run from `/home/home/personal/projects/howl/howl-render`:
  - `zig build test:unit`
- Add or sharpen adjacent tests in `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig` only:
  - semantic-empty publication space stays on direct-normal with zero sprite draws, zero raster outputs, one background draw using the theme default background, zero resolved runs, zero shaped runs, and zero glyph groups
  - semantic-empty publication space followed by styled/indexed printable ASCII stays on direct-normal and produces only the printable glyph sprite plus the expected background consequences
  - colored-background publication space does not use the semantic-empty blank fast path and still preserves existing generic behavior; if current generic behavior stays direct-normal, assert zero resolved/shaped runs and the expected background color
  - tab publication blank remains unsupported by the new fast subset and preserves existing generic behavior or fallback behavior without partial scratch leakage
- Existing tests that must remain green and are specifically relevant:
  - `text preparation publication clears use empty default background truth`
  - `text preparation publication ascii stays on direct normal path`
  - `text preparation publication styled indexed ascii stays on direct normal path`
  - `text preparation publication unsupported space and rgb keep fallback scratch clean`
  - `text preparation publication unsupported curly falls back without partial direct scratch`
  - `text preparation publication unsupported combining falls back without partial direct scratch`

Required benchmark and timing proof:

- Build commands:
  - `/home/home/personal/projects/howl/howl-render`: `zig build test:unit`
  - `/home/home/personal/projects/howl/howl-linux-host`: `zig build install -Doptimize=ReleaseFast`
  - `/home/home/personal/projects/howl/utils/tools/rain-bench`: `zig build --release=fast stress:rain:build`
- Timing proof command:
  - `/home/home/personal/projects/howl`: `env HOWL_RENDER_DEBUG_TIMING=1 python3 utils/tools/rain-bench/benchmark_terminals.py --duration 3 --mode ascii --terminals howl 2> /tmp/opencode/howl-render-debug-control.log`
- Control rerun command:
  - `/home/home/personal/projects/howl`: `python3 utils/tools/rain-bench/benchmark_terminals.py --duration 10 --mode ascii --terminals howl alacritty`
- Required receipt paths from worker:
  - exact 3-second run directory under `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/<timestamp>-ascii/`
  - exact 3-second `summary.json`
  - exact 10-second run directory under `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/<timestamp>-ascii/`
  - exact 10-second `summary.json`
  - `/tmp/opencode/howl-render-debug-control.log`
- Required quoted before baseline:
  - `direct_normal_avg_us=925`
  - `direct_normal_scan_avg_us=811`
  - `owner_create_avg_us=318`
  - `emit_prepared sprites_avg_us=302`
  - Howl `60.26 fps`, Alacritty `981.84 fps`
- Required timing expectation:
  - `direct_normal_scan_avg_us` must be lower than `811` at the final 640-frame timing line.
  - The 10-second Howl FPS must not regress below `60.26 fps` unless the worker stops and reports measurement noise with both receipt paths and the reviewer accepts a rerun demand.
  - If `direct_normal_scan_avg_us` does not drop below `811`, stop and report that semantic-empty publication spaces are not the remaining live hot subset or that another uninstrumented direct-normal child dominates.

Non-goals:

- no support for RGB publication cells
- no support for indexed or styled spaces in the fast blank subset
- no support for tabs in the fast blank subset
- no support for selected, inverse, invisible, underlined, strikethrough, linked, combining, or continuation blanks in the fast blank subset
- no changes to publication map ownership
- no changes to source/vt contracts or ABI
- no changes to renderer prepared-handle emission, owner-create, sprite resource store, atlas resource creation, or payload initialization
- no host/GL/event-loop/presentation work
- no temporary timing instrumentation
- no benchmark wrapper changes
- no broad refactor of `appendVisible`, lane classification, or generic fallback

Stop conditions:

- Stop if implementing semantic-empty space support requires editing outside the two allowed files.
- Stop if the direct-normal owner cannot represent a semantic-empty publication space without lying about `contract.CellText` blank truth or renderable background consequences.
- Stop if `publication_cell_map.publicationCellTruth(cell).empty` does not match the planned supported blank subset.
- Stop if the slice would need to include styled, colored, selected, inverse, linked, tab, RGB, combining, or continuation blanks to make the timing gate plausible.
- Stop if any unsupported publication blank bypasses the generic fallback or leaks partial direct-normal scratch on rejection.
- Stop if `zig build test:unit` fails for reasons not directly fixed inside the allowed files.
- Stop if the 3-second timing rerun does not lower `direct_normal_scan_avg_us` below `811`.
- Stop if the 10-second rerun shows a correctness failure, missing final metrics receipt, or a clear FPS regression below the accepted baseline.

Risks:

- The live rain workload may not contain enough semantic-empty spaces for this slice to move the timing line. That is an honest stop condition, not permission to broaden into styled spaces or instrumentation.
- The direct-normal blank text representation must match existing scene/background behavior exactly. A fake blank that suppresses required background draws would be a correctness bug.
- If `contract.CellText` with `first_cp = 0` and empty codepoints is not valid for the direct-normal lane, the worker must stop instead of inventing a new bucket shape.
- Timing variation can obscure small wins; the required gate uses the existing 640-frame timing line and a 10-second control rerun to reduce acceptance ambiguity.

Proof gaps:

- Current timing does not break down how many publication cells are spaces versus printable non-space ASCII. Temporary instrumentation is intentionally not authorized for this slice; the timing gate will prove whether semantic-empty spaces are live enough to matter.
- The source read proves semantic-empty publication blank truth, but not benchmark workload composition. The worker must therefore stop if the timing gate fails rather than broadening by assumption.
- Planning commit-hash receipt is still pending; the orchestrator must close it if the reviewer accepts this package and promotes the worker slice.
