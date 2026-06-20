# C ABI-Only Kitty-Derived Text Rewrite Research

Owner: render text C ABI sprint planning.

Status:

- Active.
- Teammate research plus coder-prep package from `teammate-2026-06-20-render-text-c-abi-kitty-01`.
- Product code is not authorized by this file until orchestrator/reviewer accepts a concrete execution contract.

## User Direction

- C is the only host integration option.
- Do not propose optional Zig host seams.
- Drive this as a sprint, not a slice.
- Remove `metrics` from new Howl-owned symbols; use real nouns such as layout, size, slot, span, baseline, decoration, glyph, sprite, atlas, surface, or cell.
- Rewrite everything not looking like Kitty, but do it properly and over multiple accepted execution contracts.
- Moving defaults/configuration toward Lua must be proven against Kitty-style configuration maturity before product-code changes.
- Feature maturity must be proven in tests, including ligature/operator shaping cases such as `<->` and `!=`.
- Phase 1 exit is the clean C ABI-only Kitty-derived text rewrite base: render-owned cell layout, glyph fitting, sprite slots, decorations, shaping path, host C ABI surface-size consumption, and proof gates.
- Phase 2 exit is Kitty text-configuration maturity: the user can recreate their Kitty font/text config in Howl exactly enough for visual edge-case comparison against Kitty.
- Phase 1 proof requires a reproducible Iosevka Term Nerd Font fixture set. The existing `howl-linux-host/assets/fonts/IosevkaTermNerdFont-Regular.ttf` is not enough; all needed face/flavor variants must be copied into host assets or an accepted fixture owner with source/license/inventory receipts, not referenced implicitly from the developer's Arch install paths.

## Problem Statement

The recent render ABI cell authority fix made grid placement coherent, but many font faces now clip because Howl's text stack lacks Kitty's terminal font cell layout owner and backend glyph fitting policy. The sprint must replace Howl-only text/font/cell ownership with a Kitty-derived renderer-owned model exposed through the C ABI.

## Sources Read In Order

Workflow and live accountability:

- `loop/flow.md:1-60`: current single-agent workflow, broad structural correction allowed when owner boundary requires it, no compatibility glue.
- `loop/orcestrator.md:1-66`: orchestrator owns receipts, live artifact compression, and blocks unreceipted reference conflicts.
- `loop/researcher.md:1-89`: researcher output contract requires line refs, source-backed current facts, owner shape, slice plan, assertions, tests, risks, gaps, readiness.
- `loop/reviewer.md:1-60`: reviewer rejects weak evidence, missing receipts, stale active artifacts, missing loop notes.
- `loop/coder.md:1-63`: coder has no design authority and must not touch git.
- `sprints/current.txt:1-44`: active strict sprint is C ABI-only Kitty-derived text rewrite; product code must not change before accepted research/user discussion/reviewer acceptance.
- `loops/render-text-c-abi-kitty-rewrite-loop.txt:1-42`: C ABI only, no `metrics` in new Howl symbols, render owns font-derived cell facts and glyph fitting consequences.
- `reference-index.md:1-273`: reference order and curated paths; Alacritty renderer organization, Ghostty seams, TigerBeetle discipline, Kitty facts for this sprint.
- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:90-156`, `:273-381`, `:443-466`: bounded control flow, assertions, exact names, in-place construction, off-by-one discipline.
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:189-222`, `:408-423`: static limits and control/data plane separation.

Kitty anchors:

- `utils/dev_references/terminals/kitty/kitty/data-types.h:273-282`: `CellPixelSize`, `SPRITE_MAP_HANDLE`, and `FontCellMetrics` with `cell_width`, `cell_height`, `baseline`, underline and strikethrough facts stored in font data.
- `utils/dev_references/terminals/kitty/kitty/fonts.h:34-48`: backend API includes `GlyphRenderInfo`, `cell_metrics`, and `render_glyphs_in_cells(... cell_width, cell_height, num_cells, baseline ...)`.
- `utils/dev_references/terminals/kitty/kitty/fonts.c:86-130`: `ScaledFontData`, decoration map, `FontGroup` own font facts, canvas, sprite tracker, caches, and decoration index map together.
- `utils/dev_references/terminals/kitty/kitty/fonts.c:164-180`: render canvas allocation is based on `cells * cell_width * (cell_height + 1) * scale * scale`; alpha scratch is based on cell width/height and scale.
- `utils/dev_references/terminals/kitty/kitty/fonts.c:293-343`: sprite tracker limits and layout derive x capacity from `max_texture_size / cell_width` and y capacity from `max_texture_size / cell_height`.
- `utils/dev_references/terminals/kitty/kitty/fonts.c:518-571`: `calc_cell_metrics` adjusts cell width/height, validates min/max, shifts baseline/decorations with baseline adjustment, clamps underline position, and distributes line-height adjustment.
- `utils/dev_references/terminals/kitty/kitty/fonts.c:846-900`: scaled cell dimensions and font scaling shrink/retry until scaled font facts fit inside target scaled cell dimensions.
- `utils/dev_references/terminals/kitty/kitty/fonts.c:904-918`: sprite storage reserves `cell_width * (cell_height + 1)` and clears the last row for underline exclusion.
- `utils/dev_references/terminals/kitty/kitty/fonts.c:921-958`: scaled/multicell rendering computes source/destination row intersections and extracts fixed unscaled cell regions from larger scaled canvases.
- `utils/dev_references/terminals/kitty/kitty/fonts.c:967-1028`: scaled decoration geometry maps from scaled source to unscaled cell destination; all underline variants are rendered and indexed as sprites.
- `utils/dev_references/terminals/kitty/kitty/fonts.c:1116-1131`: HarfBuzz buffer is loaded from terminal cells, skips multicell continuations, and guesses segment properties.
- `utils/dev_references/terminals/kitty/kitty/fonts.c:1145-1162`: horizontal alignment shifts the rendered canvas for subscale and centered wide glyphs.
- `utils/dev_references/terminals/kitty/kitty/fonts.c:1193-1285`: render group caches per-cell sprite positions, renders glyphs into scaled cell canvases, clamps rendered width, extracts cell sprites, and restores scaled/unscaled font facts.
- `utils/dev_references/terminals/kitty/kitty/fonts.c:1317-1354`: `shape` builds groups from HarfBuzz glyph infos/positions after `hb_shape`.
- `utils/dev_references/terminals/kitty/kitty/freetype.c:145-171`: cell height accounts for font height and buggy underscore rendered outside the bounding box.
- `utils/dev_references/terminals/kitty/kitty/freetype.c:493-528`: cell width is max ASCII `horiAdvance`; cell height, baseline, underline position/thickness, and strikethrough position/thickness are derived from FreeType face facts.
- `utils/dev_references/terminals/kitty/kitty/freetype.c:590-638`: processed bitmap stores buffer, start, width, rows, pixel mode, factor, right edge, `bitmap_left`, and `bitmap_top` from FreeType slot.
- `utils/dev_references/terminals/kitty/kitty/freetype.c:657-689`: too-wide glyph handling trims italic border when small, allows 2px single-cell right crop, otherwise rescales scalable glyphs and rerenders.
- `utils/dev_references/terminals/kitty/kitty/freetype.c:1010-1044`: bitmap placement uses `x_offset + bitmap_left`, shifts left if early glyph overflows the cell, computes y from baseline and `bitmap_top`, then clips/copies into the fixed cell canvas.
- `utils/dev_references/terminals/kitty/kitty/freetype.c:1049-1096`: `render_glyphs_in_cells` loops shaped glyph infos/positions, uses HarfBuzz x/y offsets and x advance, renders into `cell_width * num_cells` by `cell_height`, and reports rendered/canvas width.
- `utils/dev_references/terminals/kitty/kitty/shaders.c:211-268`: sprite GL texture height is `ynum * (cell_height + 1)` and uploads each sprite as `cell_width` by `cell_height + 1`.
- `utils/dev_references/terminals/kitty/kitty/decorations.c:16-38`: straight underline and strikethrough use font cell positions/thickness and clamp by cell height.
- `utils/dev_references/terminals/kitty/kitty/decorations.c:41-77`: missing glyph and double underline are full cell/saturated by cell width/height.
- `utils/dev_references/terminals/kitty/kitty/decorations.c:101-128`: dotted/dashed underline distribution depends on cell width and underline thickness.
- `utils/dev_references/terminals/kitty/kitty/decorations.c:146-181`: curl underline clamps within cell height and uses underline position/thickness as source facts.
- `utils/dev_references/terminals/kitty/kitty/decorations.c:183-225`: cursor beam/underline/hollow are decoration geometry over the same font cell facts.

Font/vendor anchors:

- `utils/dev_references/fonts/freetype/include/freetype/freetype.h:396-457`: `FT_Glyph_Metrics` width/height/bearings/advance are 26.6 fractional pixels unless unscaled; stroking does not increase advance.
- `utils/dev_references/fonts/freetype/include/freetype/freetype.h:2088-2205`: `FT_GlyphSlotRec` exposes loaded glyph metrics, advance, bitmap, `bitmap_left`, `bitmap_top`; bitmap top is distance from baseline to top scanline upward; bitmap bearings place bitmap relative to pen position.
- `utils/dev_references/fonts/freetype/include/freetype/freetype.h:3228-3347`: `FT_Load_Glyph` loads glyph into slot, default load does not render outlines, `FT_LOAD_RENDER` calls `FT_Render_Glyph`.
- `utils/dev_references/fonts/harfbuzz/src/hb-buffer.h:175-199`: `hb_glyph_position_t` carries x/y advances and x/y offsets relative to current point; offsets must not affect line advance.
- `utils/dev_references/fonts/harfbuzz/src/hb-font.h:95-119`: `hb_font_extents_t` carries ascender, descender, line gap in scaled units.
- `utils/dev_references/fonts/harfbuzz/src/hb-common.h:497-512`: `hb_glyph_extents_t` carries x/y bearing, width, height; height is negative in coordinate systems that grow up.
- `utils/dev_references/fonts/harfbuzz/src/hb-font.h:915-997`: HarfBuzz exposes h/v extents, advances, origins, and glyph extents.
- `utils/dev_references/fonts/harfbuzz/src/hb-shape.h:43-54`: shaping entrypoints are `hb_shape`/`hb_shape_full`.
- `utils/dev_references/fonts/crossfont/src/lib.rs:101-158`: Alacritty/crossfont raster output is `GlyphKey`, `Size`, and `RasterizedGlyph` with width, height, top, left, advance, buffer.
- `utils/dev_references/fonts/crossfont/src/lib.rs:185-252`: crossfont `Metrics` includes average advance, line height, descent, underline/strikeout positions/thickness; it is a useful reference for Alacritty but not sufficient for Kitty-derived fixed cell sprite layout.
- `utils/dev_references/fonts/unicode_width/src/lib.rs:68-93`: character width API returns display columns or `None` for controls, with CJK ambiguous width alternative.
- `utils/dev_references/fonts/unicode_width/src/lib.rs:96-128`, `src/tables.rs:67-84`: string width sums char widths and maps ASCII/control widths. Influence: use only for terminal cell span/classification pressure, not for font cell layout or glyph fitting.

Alacritty anchors:

- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/mod.rs:177-229`: renderer draws cells through `GlyphCache`, and variable-position strings use `unicode_width` for wide-character spacer generation.
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:11-21`: text renderer owns `atlas` and `glyph_cache` modules.
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:49-95`: text renderer trait centralizes draw cells, resize, loader API.
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:111-172`: render API gets glyphs from cache and batches draw items; zero-width characters are drawn inside the preceding cell.
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/atlas.rs:11-70`: atlas owns row packing and rejects too-large glyphs.
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/atlas.rs:118-220`: atlas inserts `RasterizedGlyph`, uploads bitmap, stores glyph top/left/width/height/UV.
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/atlas.rs:224-295`: row room/advance and atlas growth are explicit.
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs:17-79`: cache owns buffered glyphs, rasterizer, font keys, font size, font/glyph offsets, and loaded font facts.
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs:101-115`: font facts are loaded from rasterizer after loading one glyph; strikeout is adjusted by glyph offset.
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs:191-269`: cache loads, transforms, and uploads glyphs; zero-width glyph left is shifted by average advance.
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/rects.rs:121-155`: decoration rect y comes from baseline, descent, position, and thickness, with visible minimum thickness.

Ghostty anchors:

- `utils/dev_references/terminals/ghostty/src/renderer.zig:1-8`: renderer turns screen state into output; windowing prepares backend-specific resources.
- `utils/dev_references/terminals/ghostty/src/renderer.zig:12-42`: renderer root curates backend, state, size, thread, and API exports.
- `utils/dev_references/terminals/ghostty/src/Surface.zig:521-558`: surface builds renderer size from `font_grid.cellSize()` and passes `font_grid` into renderer initialization.
- `utils/dev_references/terminals/ghostty/src/Surface.zig:581-609`: surface stores `font_metrics`, renderer, renderer thread/state, and size.
- `utils/dev_references/terminals/ghostty/src/Surface.zig:684-699`: app is notified of initial cell size and size limits derived from cell size.
- `utils/dev_references/terminals/ghostty/src/Surface.zig:1984-2014`: host-facing selection viewport converts cell coordinate to pixel coordinate using cell width/height and `font_metrics.cell_baseline`.
- `utils/dev_references/terminals/ghostty/src/font/Atlas.zig:1-16`: atlas owner is explicit texture atlas with bin-pack references.
- `utils/dev_references/terminals/ghostty/src/font/Atlas.zig:27-88`: atlas owns raw data, square size, nodes, format, modification counters, and region shape.
- `utils/dev_references/terminals/ghostty/src/font/Atlas.zig:132-210`: reserve is bounded by explicit atlas size and node list.
- `utils/dev_references/terminals/ghostty/src/font/Atlas.zig:253-306`: atlas copies exact region data with assertions and modified counter.
- `utils/dev_references/terminals/ghostty/src/font/Atlas.zig:313-376`: atlas grow/clear preserve data and maintain a 1px border.
- `utils/dev_references/terminals/ghostty/src/font/shaper/run.zig:10-39`: text run is one line, carries hash, offset, cells, grid, and font index.
- `utils/dev_references/terminals/ghostty/src/font/shaper/run.zig:47-107`: run iterator trims empty right side, skips invisible and wide spacer cells.
- `utils/dev_references/terminals/ghostty/src/font/shaper/run.zig:149-176`: style and presentation select font style/presentation.
- `utils/dev_references/terminals/ghostty/src/font/shaper/run.zig:221-303`: run iterator finds fallback font, handles Kitty image placeholders as blank, hashes text and font index.
- `utils/dev_references/terminals/ghostty/src/font/shaper/run.zig:312-395`: grapheme font support requires one candidate supporting all codepoints, ignoring VS/ZWJ where appropriate.
- `utils/dev_references/terminals/ghostty/src/font/sprite/draw/special.zig:13-37`: underline sprite clamps to canvas padding beyond cell height.
- `utils/dev_references/terminals/ghostty/src/font/sprite/draw/special.zig:39-72`: double underline uses underline position/thickness and padding.
- `utils/dev_references/terminals/ghostty/src/font/sprite/draw/special.zig:74-133`: dotted underline computes dot count from width/thickness and clamps vertical position.
- `utils/dev_references/terminals/ghostty/src/font/sprite/draw/special.zig:135-165`: dashed underline is width/thickness based.
- `utils/dev_references/terminals/ghostty/src/font/sprite/draw/special.zig:167-220`: curly underline clamps to drawable area outside the cell by canvas padding.

Current Howl anchors:

- `howl-render/include/howl_render.h:67-75`: ABI has `HowlRenderPixelSize` and `HowlRenderCellSize` only; no cell baseline/decorations/sprite slot facts.
- `howl-render/include/howl_render.h:236-243`: `HowlRenderGlyphRef` exposes atlas rect, x/y pixel offset, glyph id, and color, not a fixed cell sprite slot model.
- `howl-render/include/howl_render.h:289-301`: surface frame exposes `cell_px` but not baseline, decoration geometry, or sprite slot height.
- `howl-render/include/howl_render.h:347-374`: `HowlRenderTextConfig` only carries font size/path, while `HowlRenderTextPrepare` requires host-submitted `grid_px`, `cell_px`, and grid.
- `howl-render/include/howl_render.h:385-392`: cell-surface prepare also requires host-submitted `grid_px`, `cell_px`, and grid.
- `howl-render/src/text/surface.zig:35-53`: `TextSurface` owns glyph cache, preparer, resources, scratches, font paths, and font size.
- `howl-render/src/text/surface.zig:98-148`: text prepare rejects zero host cell size and forwards host `cell_px` into face selection and prepared surface.
- `howl-render/src/text/surface.zig:150-195`: cell-surface prepare repeats the same host cell-size authority.
- `howl-render/src/text/surface.zig:207-228`: capacity is visible-cell based but named around current cache shapes.
- `howl-render/src/text/draw_primitives.zig:27-35`: `FontMetrics` is an existing Howl-owned symbol using `Metrics` and holds ascent/descent/line/decorations. This conflicts with the sprint naming rule for new/rewritten symbols.
- `howl-render/src/text/draw_primitives.zig:37-43`: `FaceMetrics26Dot6` is a bucket of face facts and uses the forbidden name form for sprint-end rewritten ownership.
- `howl-render/src/text/draw_primitives.zig:58-63`: `CellMetrics` currently has only cell width, cell height, baseline, and box thickness, missing underline/strikethrough positions/thickness and sprite slot height.
- `howl-render/src/text/draw_primitives.zig:65-68`: `CellGridMetrics` duplicates grid dimensions with forbidden name form.
- `howl-render/src/text/draw_primitives.zig:122-131`: `RunFont` has Kitty-like scale/subscale/multicell facts but no owner proof or complete Kitty pipeline.
- `howl-render/src/text/draw_primitives.zig:144-157`: glyph instances carry offsets/advance, matching HarfBuzz pressure.
- `howl-render/src/text/draw_primitives.zig:183-200`: sprite position/draw is per sprite, but slot height is not encoded as `cell_height + 1` ownership.
- `howl-render/src/text/raster/operation.zig:4-20`: raster request/output uses `cell_metrics`, bearing, advance, alpha mask; not Kitty fixed cell sprite output.
- `howl-render/src/text/raster/key.zig:4-27`: sprite keys include `cell_metrics` width/height/baseline only; they miss decoration and slot-height consequences and use forbidden name form.
- `howl-render/src/text/glyph_raster.zig:13-28`: sprite raster allocates caller width/height and advances pen; no Kitty `cell_height + 1` slot row.
- `howl-render/src/text/glyph_raster.zig:55-91`: raster path uses `FT_LOAD_RENDER`, FreeType bitmap placement, and clipping into caller width/height.
- `howl-render/src/text/glyph_raster.zig:238-246`: Howl already copied part of Kitty placement but only has cell width/baseline, no too-wide trim/rescale/cropping rule.
- `howl-render/src/text/glyph_cache.zig:43-62`: `GlyphCache` owns loaded faces, caches, scratches, cached cell facts, and font paths; it is too broad and uses forbidden `metrics` fields.
- `howl-render/src/text/glyph_cache.zig:177-263`: provider shaping uses HarfBuzz positions and cell facts but cache key depends on current incomplete `CellMetrics`.
- `howl-render/src/text/glyph_cache.zig:416-456`: cell facts are derived from font or fallback and cached as `CellMetrics`; `deriveCellSize` exists internally but the C ABI still makes hosts submit cell size.
- `howl-render/src/surface/surface_preparer.zig:22-34`: preparer owns atlas, shaper, sprite rasterizer, glyph lookup/raster, scratches, resolver, draw list; it is the likely sprint execution owner for prepared text surfaces but not the cell-layout owner.
- `howl-render/src/surface/surface_preparer.zig:80-118`: direct normal path is attempted first, then complex path; both receive selection with current cell facts.
- `howl-render/src/surface/surface_preparer.zig:193-260`: complex path resolves shape/group/raster and merges draw list.
- `howl-linux-host/src/render/surface_layout.zig:137-176`: host derives cell width as half font height from prior render layout cell height, then commits VT cell pixel size. This directly conflicts with render-owned Kitty-derived cell facts.
- `howl-linux-host/src/render/surface_layout.zig:211-218`: host writes VT cell pixel size from the host-derived layout.
- `howl-linux-host/src/layout/cells.zig:5-21`: current host pixel-to-cell mapping exists and must be removed or demoted during Phase 1 because render owns VT-cell-to-surface-pixel layout. Host may consume dirty cell ranges only as invalidation facts.
- `howl-linux-host/assets/fonts/IosevkaTermNerdFont-Regular.ttf`: current single Iosevka Term Nerd Font fixture is insufficient for Phase 1 clipping/shaping proof across required face/flavor variants.

## Current Howl Owner Map And Conflicts

Conflicting current owners:

- `howl-linux-host/src/render/surface_layout.zig`: owns cell width/height derivation today. Conflict: Kitty and user direction put font-derived terminal cell facts in render, exposed through C ABI, not host heuristics. The `cell_h = font_size`, `cell_w = cell_h / 2` rule at `surface_layout.zig:156-176` is false authority.
- `howl-render/include/howl_render.h`: exposes host-submitted `cell_px` in prepare structs at `:355-374` and `:385-392`. Conflict: callers can pass stale or non-Kitty cell facts after render has fonts loaded.
- `howl-render/src/text/draw_primitives.zig`: current `FontMetrics`, `FaceMetrics26Dot6`, `CellMetrics`, and `CellGridMetrics` names and shapes are not sprint-end acceptable. Conflict: names violate the new-symbol rule, and `CellMetrics` lacks Kitty facts.
- `howl-render/src/text/glyph_cache.zig`: broad cache owner mixes loaded faces, font analysis, shaping scratch, cell fact cache, glyph cache, and fallback paths. Conflict: Kitty has `FontGroup` owning font cell layout, scaling, sprites, and decoration map; Howl's shape hides ownership behind `GlyphCache` and `cached_cell_metrics`.
- `howl-render/src/text/glyph_raster.zig`: owns bitmap placement and raster output. Conflict: only copied part of Kitty placement and lacks too-wide trim/crop/rescale and fixed sprite slot height.
- `howl-render/src/text/raster/key.zig`: sprite keys are under-keyed against Kitty facts and use `metrics` naming. Conflict: sprite keys must include the true fixed cell layout and fitting consequences.
- `howl-render/src/text/raster/operation.zig`: raster request/output is glyph-raster shaped, not Kitty cell-sprite shaped. Conflict: output should be fixed cell sprite slot data, including the extra row consequence when applicable.
- `howl-render/src/surface/surface_preparer.zig`: owns surface preparation and is a valid execution owner, but currently receives incomplete cell facts. Conflict: it should consume a renderer-owned cell layout, not host-provided dimensions.
- `howl-linux-host/src/layout/cells.zig`: not a conflict if it remains a consumer of C ABI layout. It must not derive font facts.

Conflicting symbols requiring rename or deletion during the sprint:

- `FontMetrics`, `FaceMetrics26Dot6`, `CellMetrics`, `CellGridMetrics`, `cell_metrics`, `cached_cell_metrics`, `cached_cell_metrics_font_px`, `cached_cell_metrics_valid`, `deriveCellMetricsWithConfig`, `configuredCellMetrics`, `computeBaselineFromFace`, and all cache keys that spell `metrics` in Howl-owned code.
- `HowlRenderTextPrepare.cell_px`, `HowlRenderCellSurfacePrepare.cell_px`, and any host caller treating `cell_px` as input authority.
- `HowlRenderSurfaceFrame.cell_px` may stay only if it becomes render-produced output authority, not host input echo. User decision required for whether ABI names should keep shipped C field names for transition or break/rename them now; see ABI section.

## Reference Facts

Kitty-derived facts that must control this sprint:

- A font group owns cell width, cell height, baseline, underline position/thickness, strikethrough position/thickness, scaled cell variants, sprite tracker, decoration index, and canvas allocation (`data-types.h:279-282`, `fonts.c:86-130`).
- Cell width comes from max ASCII horizontal advance and fallback max advance, not host width heuristic (`freetype.c:493-503`).
- Cell height comes from font height, with a specific underscore escape for bad fonts (`freetype.c:145-171`, `:507-528`).
- Baseline and decorations are derived from ascender/underline/OS2 strikethrough facts and adjusted with line height and user adjustments (`freetype.c:507-528`, `fonts.c:527-571`).
- Glyph render canvas is fixed to cells: width is `cell_width * num_cells`; height is `cell_height`; sprite storage adds one row (`fonts.c:164-180`, `:904-918`, `shaders.c:211-268`).
- Glyph placement uses FreeType `bitmap_left`/`bitmap_top` plus HarfBuzz offsets, then clamps/crops at cell canvas (`freetype.c:1010-1044`, `:1049-1096`).
- Too-wide glyph handling is explicit: trim italic empty border, tolerate a 2px crop for single-cell glyphs, otherwise rescale scalable glyphs and rerender (`freetype.c:657-689`).
- Scaled/multicell rendering does region intersection and extraction into unscaled cell slots (`fonts.c:846-900`, `:921-958`, `:1193-1285`).
- Decorations are cell-layout products and can be sprites with exclusion data (`decorations.c:16-225`, `fonts.c:967-1039`).

Vendor facts that constrain implementation:

- FreeType's `bitmap_left`/`bitmap_top` are integer-pixel bitmap bearings relative to pen/baseline; `bitmap_top` is upward from baseline (`freetype.h:2135-2141`, `:2202-2205`).
- FreeType loaded glyph facts depend on load flags; `FT_LOAD_RENDER` renders into slot bitmap (`freetype.h:2097-2105`, `:3342-3347`).
- HarfBuzz offsets are placement-only and must not change advance; advances move current point (`hb-buffer.h:175-199`).
- HarfBuzz extents are useful for proof/diagnostics but Kitty's backend uses FreeType rendered bitmaps for final fitting.
- Crossfont and Alacritty show a renderer cache/atlas shape, but not Kitty's fixed terminal cell sprite slot model.
- `unicode_width` should influence terminal cell span and spacers only; it must not decide font cell pixel layout or glyph clipping.

Alacritty/Ghostty pressure:

- Alacritty supports a renderer root with text renderer, glyph cache, atlas, and batch API. Use this for Howl owner splitting and resource flow, not for cell facts.
- Ghostty supports renderer/font-grid seam and host notification of cell size; this reinforces C ABI cell-layout query/notification, not Zig host import.
- Ghostty's special sprite canvas can extend below cell height; Kitty's concrete sprite slot for text is `cell_height + 1`. Howl should follow Kitty for this sprint unless orchestrator records a source conflict override.

## Proposed Howl Owner Names

New Howl-owned names must not use `metrics`.

- `text/cell_layout.zig`: true owner for Kitty-derived font cell facts. Proposed primary shape: `CellLayout` with `cell_width_px`, `cell_height_px`, `baseline_px`, `underline_y_px`, `underline_height_px`, `strikethrough_y_px`, `strikethrough_height_px`, `sprite_slot_height_px`. Why owner-true: it is the exact font-derived terminal cell contract currently called `FontCellMetrics` in Kitty, minus the forbidden name.
- `text/face_layout.zig`: true owner for FreeType face-to-cell-layout derivation only if `face` is used in the FreeType sense: one real loaded font face/style source, not the shape of a glyph or character. Proposed functions: `deriveCellLayoutFromFace`, `deriveCellWidthFromAsciiAdvance`, `deriveCellHeightFromFace`, `deriveBaselineFromFace`, `deriveDecorationLayoutFromFace`. Why owner-true: FreeType face facts are not cache state and should be isolated from surface preparation.
- `text/glyph_bitmap.zig`: true owner for rendered glyph bitmap facts copied from FreeType slot. Proposed shape: `GlyphBitmap` with buffer view, width, rows, stride, pixel mode, `left_px`, `top_px`, optional owned copy. Why owner-true: it maps directly to Kitty `ProcessedBitmap` and FreeType slot bitmap facts.
- `text/glyph_fit.zig`: true owner for Kitty too-wide and placement consequences. Proposed functions: `fitGlyphBitmapInCells`, `placeGlyphBitmapInCanvas`, `trimItalicBorder`, `scaleFaceForWidth`. Why owner-true: this is not atlas policy and not shape policy; it is glyph-to-cell fitting.
- `text/sprite_slot.zig`: true owner for fixed cell sprite slot geometry. Proposed shape: `SpriteSlot` with `width_px`, `height_px`, `cell_height_px`, `extra_row_px`. Why owner-true: Kitty's storage consequence `cell_height + 1` must be explicit and reused by resource/ABI code.
- `text/decoration_layout.zig`: true owner for underline/strikethrough/cursor decoration geometry derived from `CellLayout`. Why owner-true: Kitty decorations use the same cell facts and should not hide in generic rect primitives.
- Existing `surface/surface_preparer.zig`: remains the prepared-surface execution owner, but consumes `CellLayout` rather than deriving or trusting host cell input.
- Existing `text/raster/atlas.zig` or successor `text/sprite_atlas.zig`: owns atlas/slot storage and upload planning. If renamed, prefer `sprite_atlas` because the sprint model stores cell sprites, not raw glyph rasters.

Names to avoid in new/rewrite work: `Metrics`, `metrics`, `Info`, `Options`, `Context`, `State` unless already source-backed by external C ABI or narrowed owner proof. Existing `State` in host code is not part of this sprint unless touched.

## C ABI Consequences

Required ABI direction:

- Render must expose a C ABI path that accepts the current surface pixel size and derives renderer-owned text layout/grid consequences from that surface size and VT surface facts.
- Host must stop deriving terminal cell width/height from font size. Host supplies surface pixel size and consumes rendered surface consequences; host must not own pixel-to-cell mapping.
- `HowlRenderTextPrepare` and `HowlRenderCellSurfacePrepare` must stop treating `cell_px` as input authority. Render should either compute layout internally from handle config plus content size, or require a prior render-produced layout token.
- Surface frames must carry render-produced `cell_px`, grid, and enough sprite slot/resource facts for host backend realization.
- C ABI must remain C-only. No host imports of Zig render internals.

Accepted user decision:

- Phase 1 Contract 1 is accepted with working C ABI symbol `howl_render_surface_layout(...)` unless current ABI/source review proves a sharper owner name before product-code edits.
- Inputs include current `surface_px` and VT surface facts; outputs are render-produced layout/grid consequences.
- Host remains in pixels. Render decides how VT cells present inside the rendered surface.
- No host `pixel-to-cell` owner and no host cell-size derivation.
- Whether to break/rename existing C fields now. Option A: keep `HowlRenderSurfaceFrame.cell_px` as output and remove or ignore prepare input `cell_px` in a breaking ABI version. Option B: rename output to `cell_size_px` and introduce explicit `HowlRenderTextLayout`. Consequence: Option B is grep-cleaner but broader C ABI churn. Recommendation: break cleanly in this private product and use explicit output names if orchestrator accepts.
- Whether cell-surface ABI is allowed to pass an explicit layout for offscreen fixed-cell surfaces. Consequence: if yes, it must be a render-produced `CellLayout`/layout token or an explicit test-only/simple-surface API; otherwise cell-surface surfaces also need render layout query.

## Ordered Sprint Execution Contracts

Phase 1: currently implemented scope rewrite on a clean base.

| Order | Execution contract | Owner boundary | C ABI consequence | Tests | Grep gates | Stop conditions |
|---|---|---|---|---|---|---|
| 1 | Establish renderer-owned surface-to-text layout query. Add `CellLayout` owner, derive from FreeType like Kitty, expose C ABI that accepts current surface pixels and VT surface facts, remove host heuristic authority. | `howl-render` owns font-derived cell layout and maps VT cells into rendered surface pixels; host owns only surface pixel size and surface consumption. | Add or revise C ABI layout/prepare response; prepare input no longer authoritative for `cell_px`. | ABI layout tests for font-size/path fallback, nonzero width/height/baseline/decorations, render-derived grid from surface pixels, host tests proving no cell-size derivation. | No `snapSurfaceLayout` font-size heuristic; no new `metrics`; no host-derived `cell_w = cell_h / 2`; no `pixel-to-cell` host owner. | User has not chosen exact ABI shape; FreeType unavailable in tests without deterministic fallback plan. |
| 2 | Replace current cell fact shapes and cache keys with Kitty-derived layout facts. Rename/delete `Metrics` owner symbols in touched render text paths. | `text/cell_layout.zig`, `text/face_layout.zig`, cache keys keyed by full layout. | Surface frame carries render-produced layout facts needed by host; ABI structs remain coherent. | Unit tests for cache key changes by baseline, underline, strikethrough, sprite slot height; layout assertions. | No `CellMetrics`, `FontMetrics`, `FaceMetrics26Dot6`, `cell_metrics` in rewritten owner paths. | If ABI compatibility is requested, stop: project law says private product, no compatibility glue unless user explicitly asks. |
| 3 | Implement Kitty glyph bitmap fitting. Add processed bitmap owner, placement, too-wide trim/crop/rescale, and fixed cell canvas rendering. | `text/glyph_bitmap.zig` and `text/glyph_fit.zig` own FreeType slot bitmap and cell fitting. | No direct ABI change if sprite uploads already use cell slots; output behavior changes. | Tests for `bitmap_left`, `bitmap_top`, baseline placement, early-glyph overflow shift, italic trim, 2px crop, scalable rescale fallback path with deterministic hooks. | No old partial `cellBitmapOrigin` as sole fitting rule; no unbounded bitmap writes. | If scalable-font rescale cannot be tested without real font fixtures, mark proof gap and split deterministic unit proof from integration proof. |
| 4 | Convert sprite raster/storage to Kitty slot height. Store/upload text sprites as `cell_width * (cell_height + 1)` with explicit extra row/exclusion semantics. | `text/sprite_slot.zig`, sprite atlas/resource upload owner. | Resource create/upload dimensions may change; host backend consumes larger sprite rects through C ABI. | Tests for upload height `cell_height + 1`, last row zero/exclusion, atlas rect bounds, resource byte counts. | No glyph atlas path assuming raw glyph bitmap height for text cell sprites. | If GL host shader/resource path assumes glyph-only atlas coordinates, require orchestrator contract for host backend update. |
| 5 | Rebuild decoration/cursor text sprites from layout facts. | `text/decoration_layout.zig` owns decoration geometry; direct/complex draw consume it. | ABI decoration commands must match render-produced layout; host remains draw executor. | Tests for straight/double/dotted/dashed/curl/strike/cursor geometry, minimum visible thickness, clamping. | No decoration calculation from ad hoc cell height without `CellLayout`. | If Kitty/Ghostty decoration facts conflict for undercurl padding, stop for orchestrator decision; Kitty wins by current sprint direction. |
| 6 | Reconcile shaping/grouping with Kitty multicell/scaled flow. | Shape/group owner maps HarfBuzz clusters to fixed cell sprite groups; renderer owns scaled extraction. | No Zig host seam; C frame output remains surface commands/resources. | Tests for wide glyphs, ligatures, zero-width combining, emoji/color fallback, multicell/subscale grouping. | No host-visible Zig convenience; no uncached broad buckets. | If full Kitty multicell image protocol is out of current text sprint, record explicit non-goal; do not fake support. |
| 7 | Host integration cleanup and proof gates. | Host supplies surface pixels and consumes rendered surfaces; render owns VT-cell-to-surface-pixel layout. | Prepare/resize sequence is host surface pixels -> render layout/grid consequences -> VT/PTY resize consequence if needed -> prepare surface -> host present. | Host tests prove surface pixel input only; render ABI tests prove layout/grid consequences; dirty range tests may use VT/render cell ranges without host cell-size ownership. | No `metrics` in new Howl-owned symbols; no host cell heuristic; no prepare input `cell_px` authority; no host `pixel-to-cell` owner. | If C ABI order needs event-loop sequencing decision, ask orchestrator/user before coding. |
| 7a | Introduce reproducible Iosevka Term Nerd Font fixture set for proof. | Font fixture owner records copied face/flavor files, source path or package, license/source receipt, and test usage. | No C ABI change; tests use stable repo-local font paths. | Tests load every required Iosevka face/flavor fixture and run clipping/layout/shaping proof against them. | No tests depending on `/usr/share/fonts` or any local Arch path; fixture inventory names every file. | If license/source receipt cannot be recorded, stop before committing broader font assets. |

Phase 2: maturity/config parity on the clean Phase 1 base.

| Order | Execution contract | Owner boundary | C ABI consequence | Tests | Grep gates | Stop conditions |
|---|---|---|---|---|---|---|
| 8 | Prove Kitty text-config parity before moving defaults to Lua. | Config/default owner must model Kitty text/font configuration closely enough to recreate the user's Kitty text config for visual comparison, without host Zig shortcuts. | C ABI exposes only concrete render consequences; Lua/default loading cannot become a host integration seam. | Tests for default font features, disabled/enabled ligatures, operator ligature strings including `<->` and `!=`, and config-to-render consequence mapping. | No unproved Lua default migration; no hidden render defaults outside the accepted config owner; no missing Kitty text-config knob that affects the comparison set. | If Kitty config/default model conflicts with Howl C ABI boundary, stop for user/orchestrator decision. |

## First Execution Contract Recommendation

Recommend contract 1 first: establish render-owned cell layout query and remove host cell-size authority.

Why first:

- It addresses the root ownership conflict exposed by the sprint.
- It forces the exact C ABI decision before product code churn.
- It gives every later raster/cache/sprite contract one authoritative `CellLayout` to consume.
- It prevents a fake local clipping fix that would preserve host-derived false layout.

Proposed first-contract scope after user ABI decision:

- Add `text/cell_layout.zig` and `text/face_layout.zig` or equivalent accepted names.
- Add C ABI layout query/response or accepted alternate ABI.
- Change host layout sync to pass surface pixels into render instead of deriving `cell_w = cell_h / 2`.
- Wire VT resize/grid consequences from render-owned layout, without host pixel-to-cell mapping.
- Add tests for render layout derivation, host consumption, and ABI structs.
- Do not implement glyph too-wide fitting yet; leave it as contract 3.

## Required Assertions

- `cell_width_px > 0`, `cell_height_px > 0`, `baseline_px >= 0`, `baseline_px < cell_height_px` unless an explicit extra-cell baseline policy is accepted.
- `underline_y_px < cell_height_px`, `underline_height_px > 0`, `strikethrough_y_px < cell_height_px`, `strikethrough_height_px > 0`.
- `sprite_slot_height_px == cell_height_px + 1` for Kitty text sprites.
- `grid_px.width == cols * cell_width_px`, `grid_px.height == rows * cell_height_px`.
- FreeType bitmap buffer slices are bounded by `abs(pitch) * rows` before any copy.
- Glyph placement source/destination rectangles are clipped before slice writes.
- Scaled extraction source/destination intersections are non-negative and within both scaled canvas and unscaled cell slot.
- C ABI functions assert/return invalid argument for null handles/out pointers and zero content size.
- Cache keys include every fact that changes sprite/layout output.

## Required Tests

- ABI test: layout query returns nonzero cell width/height, baseline, decoration facts, sprite slot height.
- ABI test: prepare surface frame echoes render-owned layout output, not caller-invented cell input.
- Host test: surface pixel size is passed to render and host does not derive cell size.
- Render ABI test: surface pixel size plus VT surface facts derive cols/rows and rendered surface layout consequences.
- Unit test: FreeType-derived cell width uses max ASCII advance with fallback when no ASCII glyph loads.
- Unit test: cell height accounts for font height and underscore escape with deterministic fake face if possible.
- Unit test: baseline and underline/strikethrough positions clamp to cell bounds.
- Unit test: sprite slot height is `cell_height + 1` and extra row is zeroed/exclusion-owned.
- Unit test: bitmap placement uses `bitmap_left`, `bitmap_top`, HarfBuzz offsets, and baseline.
- Unit test: too-wide glyph trim/crop/rescale branches are each reached.
- Shaping test: operator ligature sequences such as `<->` and `!=` shape through HarfBuzz/font-feature policy according to the accepted Kitty-derived defaults.
- Configuration/defaults test: Lua/default migration preserves explicit font feature defaults and proves toggling ligatures on/off if the sprint accepts that configuration surface.
- Configuration parity test: the user's Kitty font/text config can be represented in Howl and maps to the same render-facing consequences needed for visual edge-case comparison.
- Integration/proof test: representative problematic font faces no longer clip. Proof gap until font fixtures are selected.
- Fixture test: every required Iosevka Term Nerd Font face/flavor copied into the repo fixture set loads successfully and participates in clipping/layout/shaping proof.
- Grep test/gate: forbidden new `metrics` names do not appear in touched Howl-owned render/host text paths.

## Grep Gates

- `rg "\bmetrics\b|Metrics" howl-render/src/text howl-render/src/surface howl-linux-host/src/render howl-linux-host/src/layout howl-render/include/howl_render.h`
- `rg "cell_w = @max\(@divTrunc\(cell_h, 2\)|font_size_px.*cell|cell_px.*input|deriveCellMetrics|CellMetrics|FontMetrics|FaceMetrics26Dot6" howl-render howl-linux-host`
- `rg "cell_height \+ 1|sprite_slot_height|extra_row" howl-render/src/text howl-render/src/surface`
- `rg "howl_render_text_layout|HowlRenderTextLayout|layout_epoch" howl-render howl-linux-host`
- `rg "Zig host|optional Zig|@import\(.*howl-render" howl-linux-host` only if checking no new host Zig seam; host may import generated C bindings, not render internals.

## Risks

- ABI sequencing risk: render must derive layout/grid consequences from host surface pixels before VT resize and before prepare. This requires event-loop order changes, not just render code.
- Test fixture risk: proving real font clipping requires stable local font fixtures or deterministic FreeType fake hooks.
- Scope risk: full Kitty text model includes scaling, multicell, ligatures, decorations, color glyphs, and atlas consequences. Fake narrow patches will leave clipping bugs.
- Naming risk: current code widely uses `metrics`; a partial rename can produce worse ambiguity. Contracts must rename within touched owner boundaries fully.
- Resource risk: `cell_height + 1` sprite slots change upload byte counts and atlas/resource dimensions; host shaders/UV assumptions may need updates.
- Reference conflict risk: Ghostty sprite canvas padding differs from Kitty's exact extra row. Current sprint explicitly weights Kitty for text cell facts, so Kitty should win unless orchestrator records override.

## Proof Gaps

- Phase 1 Contract 1 C ABI direction is accepted with working symbol `howl_render_surface_layout(...)`; worker must stop if source review proves `surface_layout` is not owner-true.
- Exact broader font fixture set for clipping proof is not selected. Iosevka Term Nerd Font face/flavor fixtures must be made repo-local with source/license/inventory receipts; Arch install paths may be a copy source but must not be test dependencies.
- Kitty configuration/defaults and font-feature maturity references are not yet read; Lua/default migration is not coding-ready.
- Exact ligature fixture font and expected glyph grouping for `<->`, `!=`, and related operator sequences are not selected.
- The user's actual Kitty text/font config has not been captured yet; exact parity cannot be proven until it is added as a sprint input.
- Current Howl `text/raster/atlas.zig`, emitter/resource-store, and host GL upload/shader paths were not fully read in this pass; contract 4 must read them before coding.
- Current shape/grouping files beyond `glyph_cache.zig` and `surface_preparer.zig` were not fully read; contract 6 must re-read them.
- Whether to preserve C field names while breaking semantics is unresolved. Private-product law favors clean break, but user decision is required for exact ABI names.

## Readiness Judgment

- Research readiness: sufficient for orchestrator review and user ABI discussion.
- Coding readiness for contract 1: blocked on user decision for exact C ABI layout shape.
- Coding readiness for Phase 1 contracts 2-7: not ready until contract 1 ABI is accepted and committed/receipted by orchestrator workflow.
- Coding readiness for Phase 2 contract 8: intentionally deferred until Phase 1 produces a clean base.
- Product-code edit authorization: not granted by this research package.
