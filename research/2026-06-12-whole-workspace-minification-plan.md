# Whole Workspace Minification Plan

Date: 2026-06-12.

Status: active research target.

Role owner: researcher.

Orchestrator session id: `orch-2026-06-12-minify-sloppy-code-01`.

Researcher session id: `research-2026-06-12-minify-sloppy-code-01`.

Reviewer session id: `review-2026-06-12-minify-sloppy-code-01`.

Planning commit-hash receipt: root commit `aa2c3de`.

Question:

- What full, source-backed sprint plan will minify sloppy code across Howl into smaller, idiomatic owners with shallow/local control spines and exact verification slices?

## Sources Read In Order

1. `/home/home/personal/projects/howl/loop/flow.md` lines 1-137.
2. `/home/home/personal/projects/howl/loop/orcestrator.md` lines 1-61.
3. `/home/home/personal/projects/howl/loop/researcher.md` lines 1-86.
4. `/home/home/personal/projects/howl/loop/reviewer.md` lines 1-57.
5. `/home/home/personal/projects/howl/loop/coder.md` lines 1-60.
6. `/home/home/personal/projects/howl/loop/researcher.md` lines 1-86, reread as active role contract.
7. `/home/home/personal/projects/howl/sprints/current.txt` lines 1-34.
8. `/home/home/personal/projects/howl/loops/whole-workspace-minification-live-loop.txt` lines 1-58.
9. `/home/home/personal/projects/howl/research/2026-06-12-whole-workspace-minification-plan.md` lines 1-21 before this pass.
10. `/home/home/personal/projects/howl/reference-index.md` lines 1-273.
11. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md` lines 1-511.
12. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md` lines 1-710.
13. Current source and reference anchors listed below.
14. Correction pass for reviewer rejection: `/home/home/personal/projects/howl/loops/whole-workspace-minification-live-loop.txt` lines 67-77.
15. Correction pass current render routing proof: `howl-render/src/text/classify/special_glyphs.zig` lines 1-38, `howl-render/src/text/classify/symbol_map.zig` lines 1-48, `howl-render/src/text/classify/lane.zig` lines 260-280, `howl-render/src/text/resolver.zig` lines 115-166, `howl-render/src/text/ft_hb/glyph_raster.zig` lines 152-166 and 242-255, `howl-render/src/text/raster/special.zig` lines 49-85 and 96-105, and `howl-render/src/text/raster/special_test.zig` lines 21-50.

Current commit receipts checked by command, not by stale archive prose:

- Root: `de8f30c579da6963d36ad17d1e0fd1b95e497d3a`.
- `howl-render`: `97e386b1a7a1797baf6845bdf9089f2d0126a213`.
- `howl-pty`: `c908f424dc175c3a1049815d606d6c718b29d9b3`.
- `howl-vt`: `7bdf98f999b344f9fcfd4a9ff84fb26a293a80b4`.

## Metric Input

`python3 /home/home/personal/projects/howl/style.py --by-repo --format json` was used as a signal only.

- Total target repos: 246 files, 62,760 lines, 19 long functions, 11 bucket-named structs, 249 `usize`, 431 `anytype`, 4,398 casts.
- `howl-render`: 79 files, 25,734 lines, 9 long functions, 0 bucket-named structs, 92 `usize`, 98 `anytype`, 2,129 casts.
- `howl-linux-host`: 48 files, 13,478 lines, 5 long functions, 6 bucket-named structs, 75 `usize`, 145 `anytype`, 586 casts.
- `howl-vt`: 100 files, 20,274 lines, 3 long functions, 4 bucket-named structs, 47 `usize`, 185 `anytype`, 1,433 casts.
- `howl-pty`: 19 files, 3,274 lines, 2 long functions, 1 bucket-named struct, 35 `usize`, 3 `anytype`, 250 casts.

Worst files by current metric signal:

- `howl-render/src/text/ft_hb/special_sprite.zig`: 4 long functions.
- `howl-render/src/prepared/render_surface_emitter.zig`: 2 long functions.
- `howl-vt/src/test/terminal_benchmark.zig`: 1 long function and 1 bucket-named struct.
- `howl-linux-host/src/display/renderer/render_surface.zig`: 1 long function.
- `howl-linux-host/src/input/input.zig`: 1 long function.
- `howl-render/src/text/surface_preparer.zig`: 1 long function.
- `howl-pty/src/pty/posix.zig`: 1 long function.
- `howl-linux-host/src/terminal/pty/pump.zig`: 1 long function.
- Build files also report long functions, but those are lower priority unless they hide duplicate test wiring or root-tooling debt.

Metrics are not authority. The source facts below decide the slice plan.

## Compact Anchor Map

Reference anchors:

- TigerBeetle style requires simple explicit control flow, minimum excellent abstractions, bounded loops/queues, fixed upper bounds, and assertions for function arguments/returns/invariants at `/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:90-113`.
- TigerBeetle function shape requires a hard 70-line limit and says to centralize control flow while pushing branch-heavy control up and loop-heavy work down at `TIGER_STYLE.md:161-175`.
- TigerBeetle naming rejects weak names, asks for exact nouns/verbs, no abbreviations, and top-down source order at `TIGER_STYLE.md:271-335`.
- TigerBeetle warns against duplicate variables/aliases, broad scope, and delayed checks at `TIGER_STYLE.md:372-430`.
- TigerBeetle architecture frames static limits as the forcing function for simple bounded systems at `ARCHITECTURE.md:189-222` and control-plane/data-plane separation at `ARCHITECTURE.md:408-423`.
- TigerBeetle bounded-array reference stores fixed capacity inline, tracks `count_u32`, exposes `count_as`, asserts capacity/index invariants, and fuzzes against a model at `/utils/dev_references/zig_maturity/tigerbeetle/src/stdx/bounded_array.zig:5-84` and `:138-160`.
- Alacritty host root has a top-level `Processor` owning scheduler, windows, proxy, config, and event dispatch at `/utils/dev_references/terminals/alacritty/alacritty/src/event.rs:83-101`; it creates/runs windows through explicit methods at `event.rs:147-206`.
- Alacritty per-window owner keeps terminal, display, notifier, mouse/search/title state in `WindowContext` at `/utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs:47-70`, and `WindowContext::new` wires PTY, terminal, display, and IO thread explicitly at `window_context.rs:168-258`.
- Alacritty display owns display/window/font/render surface concepts at `/utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:1-68` and typed size info at `display/mod.rs:143-195`.
- Alacritty PTY event loop centralizes bounded PTY read/write: read buffer size is 1 MiB, locked read is bounded by `u16::MAX`, and `pty_read` controls polling/locking/parse/wakeup in one spine at `/utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs:23-28` and `:103-171`.
- Ghostty VT stream handler owns action-to-terminal mutation and routes effectful reports through callbacks, not broad report buckets, at `/utils/dev_references/terminals/ghostty/src/terminal/stream_terminal.zig:19-39`, `:46-100`, and `:122-260`.
- Ghostty C VT entrypoint reexports explicit C-facing functions from owner modules at `/utils/dev_references/terminals/ghostty/src/terminal/c/main.zig:5-43` and `:45-182`; the repo-local C API rule requires module definition, C main reexport, lib export, and header declaration in order.
- Ghostty C terminal wrapper owns persistent stream/effects state at `/utils/dev_references/terminals/ghostty/src/terminal/c/terminal.zig:30-42`, validates terminal options before allocation at `terminal.zig:223-260`, and keeps opaque pointer ABI shape at `terminal.zig:208-216`.

Current owner seams:

- `howl-render/src/libhowl_render.zig:1-28` is a pure C ABI export root. It should remain export choreography only.
- `howl-render/src/text/surface_preparer.zig:53-65` owns retained text prepare state; `prepareComplexSurface` currently coordinates resolve, shape, group, scene, raster, merge, and counters at `surface_preparer.zig:260-352`.
- `howl-render/src/prepared/render_surface_emitter.zig:257-278` owns bounded render-surface emission arrays; `emitPrepared` and `emitPreparedFresh` duplicate the same fill/sprite/publish spine at `render_surface_emitter.zig:288-362`.
- `howl-render/src/text/classify/special_glyphs.zig:11-24` owns the current generated-special support table, but the table is currently broader than shared raster dispatch for `0x1fb3c...0x1fbae`: `special_test.zig:46-50` proves `0x1fb93` and `0x1fbae` are marked supported while `rasterizeGeneratedSpecialAlpha` returns false.
- `howl-render/src/text/classify/symbol_map.zig:4-11` owns builtin special-sprite routing; `lane.zig:260-280` uses that route to force special-sprite lane classification, and `resolver.zig:129-152` uses it to split sprite routes out of font runs.
- `howl-render/src/text/raster/special.zig:49-85` owns shared generated special rasterization for box/powerline/block/eight/sextant/octant; it does not yet own smooth mosaic, half-triangle, shade, mid-line, corner mask, circle, or branch/private-use families that live in `text/ft_hb/special_sprite.zig:41-83`.
- `howl-vt/src/libhowl_vt.zig:1-32` is a pure C ABI export root. It should remain export choreography only.
- `howl-vt/src/howl_vt.zig:1-45` is a unit-test package root plus curated exports. It is a legitimate wrapper only if it stays package/test wiring.
- `howl-vt/src/control/report.zig:42-88` currently builds a `Context` bucket from terminal state; `Context` is declared at `report.zig:90-103`; `applyWithContext` dispatches every report action through that bucket at `report.zig:105-148`.
- `howl-vt/src/test/terminal_benchmark.zig:59-152` duplicates a `CountingAllocator` with `howl-render/src/benchmark_main.zig:144-237`.
- `howl-pty/src/libhowl_pty.zig:1-19` is a pure C ABI export root.
- `howl-pty/src/session.zig:17-24` has `Config`, but it is an initialization request crossing owner construction, not an arbitrary bucket if renamed/sharpened to session launch/init semantics. `PendingQueue` is bounded and asserted at `session.zig:125-199`.
- `howl-pty/src/pty/posix.zig:50-167` owns POSIX PTY lifecycle and current `startTransport` long function; child process setup is already separated at `posix.zig:494-582`.
- `howl-linux-host/src/app/processor.zig:20-33` owns top-level host event loop state, matching Alacritty’s processor pressure. Its `runLoopTurn` control spine is clear at `processor.zig:156-200`.
- `howl-linux-host/src/terminal/context.zig:52-126` is currently a broad per-terminal owner, like Alacritty `WindowContext`, but it also carries render upload telemetry/result buckets and repeated zero-result literals at `context.zig:542-600`, `:644-699`, and `:702-757`.
- `howl-linux-host/src/display/renderer/render_surface.zig:34-84` owns GL realization for render resources; `uploadRenderSurface` mixes shape classification, host surface creation, GL command dispatch, and failure handling at `render_surface.zig:439-479`.
- `howl-linux-host/src/input/input.zig:9-59` has a local fixed ring that matches bounded owner pressure; `byteSlice` is a long string switch at `input.zig:380-479`, and SDL event processing has local control at `input.zig:203-261`.

## Current-Code Facts

1. The active workflow explicitly forbids implementation before reviewer-accepted planning and requires every slice to have exact allowed files, required shape, tests, non-goals, stop conditions, and session receipts at `/loop/flow.md:22-41`, `/sprints/current.txt:20-29`, and `/loops/whole-workspace-minification-live-loop.txt:32-49`.
2. `howl-render/src/text/ft_hb/special_sprite.zig` is a large generated-special rasterizer with a 78-line public dispatch `rasterizeSpecialSpriteAlpha` at lines 8-86, a 124-line `drawAlphaShade` at lines 113-236, a 118-line `drawAlphaEightBlockCodepoint` at lines 362-458, and a 135-line `drawAlphaBranchCodepoint` at lines 481-615. It currently owns routed fallback visuals for smooth mosaic `0x1fb3c...0x1fb67`, half triangles `0x1fb68...0x1fb6f`, extended eight bars `0x1fb7c...0x1fb8b`, shade/corner/cross families `0x1fb8c...0x1fb9f`, mid-lines `0x1fba0...0x1fbae`, and branch/private-use glyphs `0xf5d0...0xf60d` at lines 41-83.
3. `howl-render/src/text/raster/special.zig` already owns shared generated special rasterization dispatch and families at lines 49-85, with box and powerline coverage at lines 108-155, block/eight/sextant/octant coverage at lines 157-230, and a shared eight-partition helper at lines 178-207. Its `generatedSpecialFamily` only recognizes box, powerline, block, eight-bar `0x1fb70...0x1fb7b`, sextant, and octant at lines 96-105, so full deletion of `ft_hb/special_sprite.zig` is not proved until the missing routed families are either migrated or deliberately removed from routing with tests.
4. Current routing support is split across `special_glyphs.zig`, `symbol_map.zig`, `lane.zig`, `resolver.zig`, and `glyph_raster.zig`: support returns true for `0x1fb00...0x1fbae` at `special_glyphs.zig:18`, builtin routing classifies generated-supported `0x1fb00+` or `0x1cd00+` as `.legacy_computing` at `symbol_map.zig:10`, lane classification turns non-blank builtin routes into `.special_sprite` at `lane.zig:273-280`, resolver records sprite routes before font resolution at `resolver.zig:129-152`, and FT/HB provider fallback calls `special_sprite.rasterizeSpecialSpriteAlpha` only when shared rasterization fails at `glyph_raster.zig:152-162`.
5. Current tests prove the gap instead of proving deletion: `glyph_raster.zig:242-255` only checks selected special-sprite pixels become non-zero, while `special_test.zig:46-50` explicitly expects `isGeneratedSpecialSupported(0x1fb93)` to be true and `rasterizeGeneratedSpecialAlpha` for `0x1fb93` and `0x1fbae` to be false. Slice 2 must first make routing/support/raster parity exact before any deletion slice may remove fallback ownership.
6. `howl-render/src/prepared/render_surface_emitter.zig` has `emitPrepared` and `emitPreparedFresh` with nearly identical pass order and timing code at lines 288-362. The only material differences are copy-in/copy-out/resource rollback semantics. This is an owner-local duplication suitable for first executable deletion/collapse.
7. `howl-render/src/prepared/render_surface_emitter.zig` keeps a large debug timing bucket at lines 29-185. It is owner-local debug state, but it inflates call signatures, and `record` takes eight positional/domain buckets at line 110. This should be reduced only after the pass-collapse proves timing behavior.
8. `howl-render/src/text/surface_preparer.zig` `prepareComplexSurface` at lines 260-352 is a long but owner-true pipeline: select complex cells, resolve runs, shape runs, group, build scene, rasterize, merge, assert lane report, count, deinit, return. It should be split by moving non-branchy chunks down, not by inventing an engine/manager.
9. `howl-vt/src/control/report.zig` constructs a 13-field `Context` bucket at lines 46-86 and passes it by value into `applyWithContext` at lines 90-148. The bucket exists only to avoid exact argument threading across reports and mixes allocator/output/scratch/screen/modes/checksum/color depth. Ghostty’s equivalent pressure is a handler with terminal pointer plus explicit effects callbacks, not a one-off report `Context` bucket.
10. `howl-vt/src/test/terminal_benchmark.zig` defines `Options` at lines 27-36 and a complete `CountingAllocator` at lines 59-152; `howl-render/src/benchmark_main.zig` defines a separate `Options` at lines 20-23 and a nearly identical `CountingAllocator` at lines 144-237. This is duplicate benchmark/test helper code across repos.
11. `howl-pty/src/session.zig` `Config` at lines 17-24 is flagged by bucket metrics. It is close to a legitimate init request because it crosses construction and owns required allocator/dimensions/transport launch. Do not delete it as LOC theater; if touched, rename to a domain noun such as `InitRequest` only if the slice also proves call-site clarity.
12. `howl-pty/src/session.zig` bounded queue is owner-true: it stores buffer/head/count at lines 125-130, asserts capacity in `init`, `pushSlice`, `discardPrefix`, and `capacity` at lines 131-189, and has local ring math at lines 152-198. It should not be replaced with generic helpers.
13. `howl-pty/src/pty/posix.zig` `startTransport` at lines 114-167 is one long lifecycle spine covering validation, open transport, wake pipe, child-ready pipe, fd flags, fork, parent setup, await child session, and invariant assertions. It should be split into parent/child-start leaf helpers only if lifecycle order remains obvious in the parent.
14. `howl-linux-host/src/app/processor.zig` already has a good shallow event spine in `runLoopTurn` at lines 156-200 and small local helpers for admission, event pumping, host mutations, runtime progress, present, and tab routing at lines 202-607. This owner should be protected from broad reshaping.
15. `howl-linux-host/src/terminal/context.zig` has a broad `Context` owner at lines 52-126. It matches Alacritty per-window/per-terminal owner pressure but the nested render telemetry result shapes are bloated: `TurnResult` at lines 68-92, `DriveResult` at lines 542-564, `SubmitPreparedResult` at lines 702-722, repeated zero literals in `driveRenderLocked` at lines 573-599, repeated failure literals in `submitPreparedLockedWith` at lines 644-699, and field-copy fanout at lines 395-425 and 732-757.
16. `howl-linux-host/src/display/renderer/render_surface.zig` `RenderResourceTextures` owns GL resource slots at lines 34-84. `uploadRenderSurface` at lines 439-479 repeatedly classifies surface shape and dispatches to two upload paths, including duplicate patch checks. The owner is correct, but the classification spine should be made explicit and small.
17. `howl-linux-host/src/input/input.zig` local `FixedRing` at lines 9-59 is a useful bounded local helper. `byteSlice` at lines 380-479 is long generated mapping and should be replaced by a one-byte static table/range-backed literal only if tests prove all existing mapped bytes.
18. ABI export roots in `howl-render/src/libhowl_render.zig:1-28`, `howl-vt/src/libhowl_vt.zig:1-32`, and `howl-pty/src/libhowl_pty.zig:1-19` are intentionally thin. Do not collapse them into product roots or add Zig-shaped convenience APIs.

## Owner Roles And Proposed Shape

- `howl-render` owns render contracts, geometry policy, retained-frame state, prepare/submit scheduling, render-surface contracts, and text shaping. Minification should collapse duplicate render-owner code, not move host GL realization into render.
- `text/raster/special.zig` should become the only owner for generated special sprite rasterization only after `special_glyphs.zig`, `symbol_map.zig`, `lane.zig`, `resolver.zig`, and `glyph_raster.zig` prove exact routing/support/raster parity. `text/ft_hb/special_sprite.zig` should not be deleted until every currently routed fallback family is either migrated into the shared raster owner with tests or removed from routing/support with tests proving the behavioral decision.
- `prepared/render_surface_emitter.zig` should keep bounded arrays and publish control. Its emit path should have one parent pass spine and leaf helpers for rollback/copy behavior.
- `howl-vt` owns parser, terminal state, selection, input encoding, host-facing protocol consequences, and VT surface truth. `control/report.zig` should either pass exact views to report helpers or own a narrow `ReportView` only if it is a real VT report data shape. The current `Context` name/shape is rejected.
- `howl-pty` owns PTY variants, child I/O, resize delivery, signals, and transport state. Its queue/session ownership is mostly owner-true; minification should target `Config` naming and POSIX lifecycle shape, not replace bounded internals.
- `howl-linux-host` owns platform UX, event loop, wake policy, presentation cadence, orchestration, GL resources, input, and tabs. Keep `Processor` and `TerminalContext` as host owners, but collapse repeated result buckets and literal factories into exact owner-local functions.
- Root tooling/docs should only be touched when proving current active planning or test wiring. Do not minify historical docs during this sprint.

## Full Sprint Scratchpad

- Bias deletion first: eliminate duplicate emit passes and duplicate special-raster ownership before cosmetic rename work.
- Preserve ABI roots. Thin export roots are not sloppy by themselves.
- Treat `Config`, `State`, `Options`, and `Context` names as suspect, not automatically wrong. Config modules and ABI/constructor requests may justify the shape if names and fields are exact.
- First executable slice should be high-confidence and small: collapse `emitPrepared`/`emitPreparedFresh` duplicate pass body inside `prepared/render_surface_emitter.zig` without changing ABI or public behavior.
- Avoid file motion unless the target owner is already proved. File motion without changed owner/control facts is rejected.
- Each slice must improve one of: duplicate code removal, function length/control spine, bucket struct removal/rename, hidden bounds/assertions, `anytype`/`usize` edge isolation, host/render/VT ownership seam.
- Verification must include targeted unit/ABI tests for touched owners plus style metric rerun. Benchmark runs are optional only for benchmark slices, but benchmark build must still compile.

## Ordered Slice Plan

### Slice 1: Render Emitter Duplicate Pass Collapse

Allowed files:

- `howl-render/src/prepared/render_surface_emitter.zig`.
- `howl-render/src/prepared/render_surface_emitter_test.zig`.

Required shape:

- Keep `Emitter` as owner and keep all bounded arrays in the same file.
- Collapse `emitPrepared` and `emitPreparedFresh` into one owner-local pass helper that takes an exact emission mode enum or exact private leaf callbacks for copy/rollback behavior.
- Parent spine must still show pass order: reset, full damage, full-redraw clear, clears, backgrounds, decorations, sprites, cursors, publish.
- Preserve resource rollback for fresh emission and copy-in/copy-out behavior for non-fresh emission.
- Add assertions that published surface and resource state are updated only after all append passes succeed.

Exact tests:

- From `howl-render`: `zig build test`.
- Existing `prepared/render_surface_emitter_test.zig` coverage for reusable/fresh emission behavior.
- `python3 ../style.py --by-file --format json howl-render/src/prepared/render_surface_emitter.zig` from repo root or equivalent workspace path.

Non-goals:

- No ABI changes.
- No debug timing redesign.
- No sprite-resource-store redesign.
- No file motion.

Stop conditions:

- Stop if fresh/non-fresh behavior cannot be expressed without hiding rollback/copy semantics.
- Stop if tests require touching C ABI headers or host GL code.

Receipt fields:

- Orchestrator session id, researcher session id `research-2026-06-12-minify-sloppy-code-01`, reviewer session id, coder session id, commit hash, verification output, style metric before/after for the file.

### Slice 2: Render Generated Special Routing And Parity Proof

Allowed files:

- `howl-render/src/text/ft_hb/special_sprite.zig`.
- `howl-render/src/text/raster/special.zig`.
- `howl-render/src/text/raster/special_test.zig`.
- `howl-render/src/text/classify/special_glyphs.zig`.
- `howl-render/src/text/classify/symbol_map.zig`.
- `howl-render/src/text/classify/lane.zig`.
- `howl-render/src/text/resolver.zig`.
- `howl-render/src/text/ft_hb/glyph_raster.zig`.

Required shape:

- Do not delete `special_sprite.zig` in this slice.
- Make support truth exact before owner deletion: `special_glyphs.isGeneratedSpecialSupported`, `symbol_map.builtinRoute`, lane special-sprite classification, resolver sprite-route splitting, and provider fallback must agree for every currently routed generated/special family.
- Add an explicit current-family table in code or tests covering at least: box `0x2500...0x257f`, block `0x2580...0x259f`, braille `0x2800...0x28ff`, powerline `0xe0b0...0xe0bf` and `0xe0d6...0xe0d7`, sextant `0x1fb00...0x1fb3b`, smooth mosaic `0x1fb3c...0x1fb67`, half-triangle `0x1fb68...0x1fb6f`, eight-bar `0x1fb70...0x1fb8b`, shade/corner/cross `0x1fb8c...0x1fb9f`, mid-line `0x1fba0...0x1fbae`, octant `0x1cd00...0x1cde5` plus `0x1fbe6...0x1fbe7`, and branch/private-use `0xf5d0...0xf60d`.
- For each family, record one of two exact outcomes in tests: shared raster owner returns true and draws non-empty pixels, or FT/HB special fallback remains the only drawing owner and routing/support intentionally requires fallback.
- Fix the current unsupported-supported mismatch for `0x1fb93` and `0x1fbae` either by making shared rasterization draw them or by making support/routing no longer claim shared generated support. The chosen outcome must be encoded in tests, not prose.
- Keep `special_sprite.zig` as fallback-only until Slice 3. Do not add `manager`, `engine`, generic `types`, or a new routing bucket.

Exact tests:

- `zig build test` in `howl-render`.
- Existing `text/raster/special_test.zig` tests plus new or sharpened tests for every family listed above.
- Existing or new inline tests in `special_glyphs.zig`, `symbol_map.zig`, `lane.zig`, `resolver.zig`, and `glyph_raster.zig` proving support, builtin route, lane classification, sprite route splitting, and fallback drawing agree for representative codepoints.
- If benchmarks build separately, `zig build benchmark` or existing benchmark target compile only.
- `python3 ../style.py --by-file --format json howl-render/src/text/ft_hb/special_sprite.zig howl-render/src/text/raster/special.zig howl-render/src/text/classify/special_glyphs.zig howl-render/src/text/classify/symbol_map.zig howl-render/src/text/classify/lane.zig howl-render/src/text/resolver.zig howl-render/src/text/ft_hb/glyph_raster.zig`.

Non-goals:

- No new glyph protocol support.
- No visual redesign.
- No FreeType/HarfBuzz provider redesign.
- No host GL changes.
- No deletion of `special_sprite.zig`.

Stop conditions:

- Stop if any family in the required table lacks a test-backed support/route/raster/fallback outcome.
- Stop if branch/private-use routing would require a product decision to remove support rather than migrate it.
- Stop if ownership depends on external protocol/spec interpretation not already encoded in current tests.

Receipt fields:

- Same receipt fields as Slice 1, plus table of every listed family with support owner, route owner, raster owner, fallback owner, and tests.

### Slice 3: Render Generated Special Raster Owner Deletion

Allowed files:

- `howl-render/src/text/ft_hb/special_sprite.zig`.
- `howl-render/src/text/raster/special.zig`.
- `howl-render/src/text/raster/special_test.zig`.
- `howl-render/src/text/classify/special_glyphs.zig`.
- `howl-render/src/text/classify/symbol_map.zig`.
- `howl-render/src/text/classify/lane.zig`.
- `howl-render/src/text/resolver.zig`.
- `howl-render/src/text/ft_hb/glyph_raster.zig`.

Required shape:

- Proceed only from Slice 2's accepted family table and tests.
- Make `text/raster/special.zig` the sole generated special raster owner for every family that remains routed as a generated/special sprite.
- Delete `special_sprite.zig` only if no fallback-only generated family remains after Slice 2 proof. If a fallback-only family remains because deletion would remove supported visuals, stop instead of preserving duplicate owner code.
- Remove the `special_sprite` import and fallback call from `glyph_raster.zig` only after shared rasterization covers the routed family or tests prove the route/support entry was removed.
- Split long generated-special family dispatch into small exact helpers where the family is owner-true; do not add `manager`, `engine`, or generic `types` buckets.

Exact tests:

- `zig build test` in `howl-render`.
- All Slice 2 support/route/lane/resolver/fallback tests must still pass, with fallback expectations updated only when owner deletion is proved.
- `text/raster/special_test.zig` must include representative drawing tests for every migrated/routed family.
- If benchmarks build separately, `zig build benchmark` or existing benchmark target compile only.
- `python3 ../style.py --by-file --format json howl-render/src/text/ft_hb/special_sprite.zig howl-render/src/text/raster/special.zig howl-render/src/text/classify/special_glyphs.zig howl-render/src/text/classify/symbol_map.zig howl-render/src/text/classify/lane.zig howl-render/src/text/resolver.zig howl-render/src/text/ft_hb/glyph_raster.zig`.

Non-goals:

- No new glyph protocol support.
- No visual redesign.
- No FreeType/HarfBuzz provider redesign.
- No host GL changes.
- No compatibility alias or empty wrapper for `special_sprite.zig` unless a concrete remaining import proves it is required inside allowed files.

Stop conditions:

- Stop if any accepted Slice 2 family still requires `special_sprite.zig` to draw supported/routed pixels.
- Stop if deleting fallback would change lane/resolver/provider behavior without exact tests proving the intended new route/support outcome.
- Stop if deletion requires touching files outside the allowed list.

Receipt fields:

- Same receipt fields as Slice 1, plus list of deleted/migrated codepoint families and the Slice 2 table rows that authorized each deletion.

### Slice 4: Benchmark Helper Deduplication

Allowed files:

- `howl-render/src/benchmark_main.zig`.
- `howl-vt/src/test/terminal_benchmark.zig`.

Required shape:

- First try same-file minification: shrink duplicate `CountingAllocator` implementations to the smallest local form in each repo without new cross-repo dependencies.
- Do not introduce shared helper files in this slice; if local minification cannot beat duplication without cross-repo coupling, keep the duplication and record why.
- Rename benchmark `Options` only if the name remains ambiguous after helper collapse; command-line option bags may be legitimate in benchmark entrypoints.

Exact tests:

- `zig build test` in `howl-render`.
- `zig build test` in `howl-vt`.
- Compile/run benchmark target for each repo with `--help` or zero/one-run mode if supported.
- Style metric for both benchmark files.

Non-goals:

- No product runtime dependencies.
- No benchmark schema changes unless tests explicitly require schema version update.
- No performance tuning.

Stop conditions:

- Stop if deduplication creates a dependency across independent product repos.
- Stop if benchmark output schema changes accidentally.

Receipt fields:

- Standard receipt fields, plus benchmark output compatibility note.

### Slice 5: Host Terminal Render Result Collapse

Allowed files:

- `howl-linux-host/src/terminal/context.zig`.
- `howl-linux-host/src/terminal/context_test.zig`.

Required shape:

- Collapse repeated zero `DriveResult`/`SubmitPreparedResult` literals into exact owner-local constructors such as `failedSubmit`, `idleDrive`, or equivalent domain nouns.
- Consider nesting upload telemetry as one exact `UploadStats`/`RenderTiming` field only if it reduces repeated field fanout and remains owner-true. Do not create a generic `Result` or `Info` bucket.
- Keep `Context` as per-terminal owner unless reviewer demands broader Alacritty-backed split. Do not rename `Context` in this slice because it is a public host owner seam.
- Preserve lock/unlock ordering around prepared upload at `context.zig:644-660`.

Exact tests:

- `zig build test` in `howl-linux-host`.
- Existing `terminal/context_test.zig` tests.
- Add/sharpen tests for failed upload, stale handle, and idle render-action result constructors if not already covered.
- Style metric for `terminal/context.zig`.

Non-goals:

- No GL upload behavior changes.
- No `Processor` event loop changes.
- No ABI changes.

Stop conditions:

- Stop if lock ordering becomes less obvious.
- Stop if collapsing fields hides which phase produced `prepare_ns`, `upload_ns`, or `retained_submit_ns`.

Receipt fields:

- Standard receipt fields, plus explicit lock-order preservation note.

### Slice 6: VT Report Bucket Removal

Allowed files:

- `howl-vt/src/control/report.zig`.
- `howl-vt/src/control/report_test.zig`.
- `howl-vt/src/terminal.zig`.

Required shape:

- Delete or rename `Context` at `report.zig:90-103`.
- Prefer exact helper arguments for simple appenders and narrow view structs only where they are actual protocol views, e.g. cursor report, charset report, mode views.
- Keep report side effects explicit: pending output append, checksum flag mutation, and active-screen reads must remain visible at call sites.
- Follow Ghostty pressure: terminal handler/effects are explicit; do not hide all report effects in one local bucket.

Exact tests:

- `zig build test` in `howl-vt`.
- Existing `control/report_test.zig`.
- Terminal OSC/report tests if wired: `terminal_osc_test.zig`, `terminal_modes_test.zig`.
- Style metric for `control/report.zig`.

Non-goals:

- No protocol behavior changes.
- No new report support.
- No parser/action vocabulary redesign.

Stop conditions:

- Stop if any report action loses rollback behavior around pending output.
- Stop if the slice requires changing C ABI surfaces.

Receipt fields:

- Standard receipt fields, plus list of report actions whose argument threading changed.

### Slice 7: Host GL Render-Surface Classification Spine

Allowed files:

- `howl-linux-host/src/display/renderer/render_surface.zig`.
- `howl-linux-host/src/display/renderer/render_surface_test.zig`.

Required shape:

- Keep `RenderResourceTextures` as GL resource owner.
- Extract one explicit render-surface classification function returning a domain enum such as fill, fill_patch, sprite, sprite_patch, glyph, glyph_patch.
- Parent `uploadRenderSurface` should validate/realize resources, ensure host surface, switch once on classification, and handle patch matching in one visible place.
- Add assertions for patch requiring an existing matching host surface.

Exact tests:

- `zig build test` in `howl-linux-host`.
- Existing `display/renderer/render_surface_test.zig`, with new cases for patch classification and unsupported shape if missing.
- Style metric for `display/renderer/render_surface.zig`.

Non-goals:

- No GL backend architecture redesign.
- No render ABI changes.
- No texture lifetime policy changes.

Stop conditions:

- Stop if classification requires changing render-surface ABI constants.
- Stop if tests cannot construct representative surface shapes.

Receipt fields:

- Standard receipt fields, plus classification cases tested.

### Slice 8: PTY POSIX Lifecycle Spine Split

Allowed files:

- `howl-pty/src/pty/posix.zig`.
- `howl-pty/src/pty/posix_test.zig`.
- `howl-pty/src/pty/pty_test.zig`.

Required shape:

- Keep parent `startTransport` as the readable lifecycle spine.
- Move non-branchy setup into exact owner-local helpers: open pipes, configure master, fork child, parent adoption, await ready, assert started.
- Do not hide the sequence behind a generic `startContext`, `manager`, or `Options` bucket.
- Preserve child-ready pipe close behavior and `errdefer self.stopTransport()` semantics.

Exact tests:

- `zig build test` in `howl-pty`.
- Existing POSIX tests.
- Integration tests only if environment supports them; if not, record skipped with reason.
- Style metric for `pty/posix.zig`.

Non-goals:

- No platform support changes.
- No signal policy changes.
- No ABI changes.

Stop conditions:

- Stop if lifecycle order becomes less visible in `startTransport`.
- Stop if tests require live PTY integration unavailable in the environment; record blocker and do not fake proof.

Receipt fields:

- Standard receipt fields, plus PTY integration availability note.

### Slice 9: Host Input Literal Table Collapse

Allowed files:

- `howl-linux-host/src/input/input.zig`.

Required shape:

- Replace or shrink `byteSlice` only if the replacement is smaller, bounded, and easier to audit.
- Prefer a static table for ASCII bytes accepted by `sdlAltTextBytes`, with positive assertions that all returned slices are one byte and stable.
- Preserve SDL key/mod behavior in `processKeyDown`.

Exact tests:

- `zig build test` in `howl-linux-host`.
- Add owner-local inline tests in `input.zig` for representative shifted/unshifted alt text mappings and unsupported keys.
- Style metric for `input/input.zig`.

Non-goals:

- No new keyboard protocol behavior.
- No input binding redesign.
- No SDL event-loop policy changes.

Stop conditions:

- Stop if the mapping cannot be tested exhaustively for all existing returned byte values.

Receipt fields:

- Standard receipt fields, plus exhaustive byte mapping test note.

### Slice 10: Render Text Prepare Pipeline Split

Allowed files:

- `howl-render/src/text/surface_preparer.zig`.
- `howl-render/src/text_session_test.zig`.

Required shape:

- Keep `TextSurfacePreparer` as owner.
- Split `prepareComplexSurface` by moving non-branchy phase bodies into exact leaf helpers: select complex cells, resolve/shape/group, build complex scene, rasterize, merge, apply counters.
- Parent function must keep the high-level phase order and error/deinit ownership visible.
- Do not create `Pipeline`, `Engine`, `Context`, or generic buckets.

Exact tests:

- `zig build test` in `howl-render`.
- Existing inline tests in `surface_preparer.zig`.
- `text_session_test.zig`.
- Style metric for `text/surface_preparer.zig`.

Non-goals:

- No shaping/raster behavior changes.
- No font provider changes.
- No benchmark tuning.

Stop conditions:

- Stop if ownership of `OwnedLineTextCache`, `OwnedRenderableCells`, or `OwnedClusters` deinit becomes harder to audit.

Receipt fields:

- Standard receipt fields, plus deinit/errdefer audit note.

### Slice 11: Bucket Struct Naming And Legitimacy Pass

Allowed files:

- `howl-pty/src/session.zig`.
- `howl-vt/src/host/state.zig`.
- `howl-vt/src/simulation/protocol.zig`.
- `howl-linux-host/src/config/terminal.zig`.
- `howl-linux-host/src/config/tab_bar.zig`.
- `howl-linux-host/src/terminal/render/surface_layout.zig`.
- `howl-linux-host/src/terminal/render/retained.zig`.
- `howl-linux-host/src/terminal/scrollbar.zig`.

Required shape:

- For each flagged `Config`, `State`, `Options`, or `Result`, either record why the current name is owner-true or rename to an exact domain noun.
- Do not mass rename. Each rename must improve external call-site/accountability proof.
- Keep C ABI-compatible names stable unless the ABI contract changes with explicit approval.
- For config files, `Config` may be acceptable because the owner is a config module; do not rename for metrics only.

Exact tests:

- `zig build test` in every touched repo.
- Style metric before/after for all allowed files.
- Targeted owner tests where names affect public imports.

Non-goals:

- No behavior changes.
- No file motion.
- No compatibility aliases unless a concrete ABI/export need is proved.

Stop conditions:

- Stop if a rename requires broad import churn without owner clarity.
- Stop if a name is ABI-visible and no ABI migration receipt exists.

Receipt fields:

- Standard receipt fields, plus per-struct decision table: keep/rename/delete, reason, tests.

### Slice 12: `anytype`, `usize`, And Cast Boundary Pass

Allowed files:

- `howl-linux-host/src/display/renderer/render_surface.zig`.
- `howl-linux-host/src/display/renderer/render_surface_test.zig`.
- `howl-linux-host/src/input/input.zig`.
- `howl-vt/src/host/state.zig`.
- `howl-render/src/text/surface_preparer.zig`.
- `howl-render/src/text_session_test.zig`.
- `howl-render/src/prepared/render_surface_emitter.zig`.
- `howl-render/src/prepared/render_surface_emitter_test.zig`.

Required shape:

- Replace `anytype` only where it hides a real owner/interface. Keep comptime testing hooks only when tests require them and names are exact.
- Keep `usize` at allocator/C callback/slice boundaries; translate immediately to fixed-width domain counts with assertions.
- Add assertions before every narrowing cast that is not already dominated by a visible bound.
- For `display/renderer/render_surface.zig`, restrict changes to GL/render-surface shape classification, resource-count, patch, and upload-boundary casts/generics left after Slice 7; no new backend owner.
- For `input/input.zig`, restrict changes to byte/key mapping count boundaries and any remaining test-only `anytype` hooks left after Slice 9; no keyboard behavior changes.
- For `howl-vt/src/host/state.zig`, restrict changes to host-facing VT state count/cast boundaries and generic helpers in that owner; no C ABI or protocol behavior changes.
- For `text/surface_preparer.zig`, restrict changes to prepare-pipeline owned scratch/count/cast boundaries left after Slice 10; no shape/raster behavior changes.
- For `prepared/render_surface_emitter.zig`, restrict changes to bounded-array append counts, publish counts, and timing/copy helper generics left after Slice 1; no pass-order or debug timing redesign.

Exact tests:

- `zig build test` in `howl-linux-host`.
- `zig build test` in `howl-vt`.
- `zig build test` in `howl-render`.
- Existing `display/renderer/render_surface_test.zig`, `text_session_test.zig`, and `prepared/render_surface_emitter_test.zig` coverage plus inline tests in `input.zig`, `host/state.zig`, and `surface_preparer.zig` when a changed assertion needs a direct case.
- Targeted tests for boundary overflow, invalid-count, unsupported-shape, or zero/maximum-count cases where a cast assertion is introduced and such a case is constructible without new infrastructure.
- `python3 style.py --by-file --format json howl-linux-host/src/display/renderer/render_surface.zig howl-linux-host/src/input/input.zig howl-vt/src/host/state.zig howl-render/src/text/surface_preparer.zig howl-render/src/prepared/render_surface_emitter.zig` from workspace root.

Non-goals:

- No mechanical cast churn.
- No replacing clear generic test hooks with duplicated code.
- No ABI type changes unless explicitly planned.
- No touching files outside the allowed list, even if fresh metrics show another file above threshold.
- No broad cleanup of casts introduced by external C libraries unless the cast is inside one of the five fixed owner files.

Stop conditions:

- Stop if removing `anytype` makes tests weaker or creates fake interfaces.
- Stop if a cast is ABI-required and cannot be safely narrowed without ABI review.
- Stop if a needed assertion/test would require touching a source or test file outside the allowed list.
- Stop if fresh metric output suggests a different candidate file; record it for a later sprint instead of changing this slice's file set.

Receipt fields:

- Standard receipt fields, plus cast/usize/anytype table with keep/change reason.

### Slice 13: Root Tooling And Active Surface Hygiene

Allowed files:

- `style.py`.
- `sprints/2026-06-12-whole-workspace-minification-sprint.md`.
- `loops/whole-workspace-minification-live-loop.txt`.
- `research/2026-06-12-whole-workspace-minification-plan.md`.

Required shape:

- Keep active accountability files current-only.
- Update sprint execution queue only after reviewer acceptance.
- Do not edit archived historical artifacts except orchestrator archive hygiene.

Exact tests:

- `python3 style.py --by-repo --format json`.
- `python3 style.py --by-file --format json` after final slice.
- Repo tests from every touched product repo.

Non-goals:

- No broad docs cleanup.
- No archive rewriting.
- No README browsing as authority.

Stop conditions:

- Stop if stale active artifacts are discovered in `loops/`, `research/`, or `sprints/`.
- Stop if planning/execution receipts are incomplete.

Receipt fields:

- Planning commit receipt, per-slice commit receipts, final style metric summary, reviewer acceptance.

## Required Assertions And Tests

- Every slice must preserve or add assertions for bounds before narrowing casts and for arrays/queues/resources before writes.
- Render emitter must assert bounded counts before appending and assert surface storage pointers/counts after publish.
- Generated special raster must assert pixel buffer capacity before raster writes and must test support/routing/raster/fallback parity before owner deletion.
- Host terminal render collapse must assert lock-sensitive render handle identity and present-pending invariants before/after unlock.
- VT report bucket removal must test pending-output rollback and report text for key protocol queries.
- PTY POSIX split must assert started/FD/child invariants at lifecycle transition end and preserve wait/close behavior.
- Host input table must test every returned alt-text byte or a mechanically generated exhaustive subset from current switch cases.
- Final sprint acceptance must include `style.py --by-repo --format json` and compare long functions/bucket structs against starting metrics.

## Risks And Proof Gaps

- `howl-render/src/text/ft_hb/special_sprite.zig` may carry externally expected icon visuals not fully covered by current tests. Slice 2 must add parity/routing tests before Slice 3 may delete the fallback owner.
- `howl-linux-host/src/terminal/context.zig` is broad but reference-backed as a per-terminal host owner. Splitting it by file could become file motion theater unless a specific owner seam is proved.
- Config `Config` names are metric noise in several modules. Renaming config modules can reduce clarity, so Slice 11 must allow justified keeps.
- Benchmark helper sharing across nested repos may introduce worse coupling than duplication. Slice 4 forbids new helper files and requires local minification or an explicit keep-duplication note.
- Live PTY integration tests may be environment-sensitive. If unavailable, the coder must record the skip and run all non-integration proof; reviewer decides adequacy.
- Host GL tests may not exercise real GL. Shape/classification tests must use pure validation where possible and not fake successful GL behavior.
- Active sprint metadata records concrete researcher and reviewer session ids in `/home/home/personal/projects/howl/sprints/2026-06-12-whole-workspace-minification-sprint.md:11-15`; only the planning commit-hash receipt remains pending until orchestrator closure.

## Readiness Judgment

Ready for reviewer planning re-gate. The prior Slice 2 deletion risk is now split into exact parity/routing proof followed by deletion only after proof, and the boundary-pass dynamic file selection is replaced by a fixed allowed-file list.

The first executable slice should be Slice 1. It is local, owner-true, high confidence, does not need redesign, and deletes/collapses duplicate control without ABI or cross-repo consequences.
