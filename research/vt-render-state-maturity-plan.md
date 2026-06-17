# VT Render-State Maturity Plan

Status: accepted planning amendment after Slice 4 blocker; amended Slice 4 is seeded for execution.

Orchestrator session id: `orch-2026-06-16-vt-render-state-planning-01`.

Researcher session id: `researcher-2026-06-17-vt-render-state-hover-abi-amendment-correction-04`.

Reviewer session id: `reviewer-2026-06-17-vt-render-state-hover-abi-amendment-rereview-02`.

Planning commit receipt: prior accepted root `b5f9eb5 Plan VT render state maturity sprint`; current accepted amendment has no dedicated commit receipt yet.

## Problem Statement

- The current Howl VT ABI exposes one monolithic `HowlVtSurfaceResult` and one `HowlVtSurface` value that mixes viewport cells, dirty spans, cursor presentation, colors, extra cursors, and selection.
- The renderer mirrors that aggregate in `howl-render/src/vt_surface/surface.zig` as `VtSurface`, then adds renderer-owned presentation facts such as cursor opacity, focus, effective shape, cursor trail, and compatibility blink state.
- That mirrored `VtSurface` is rejected as the endpoint. VT owns terminal viewport render-state truth. Render owns shaping, retained prepared surfaces, render contracts, and backend-neutral preparation. Host owns hover policy and runtime orchestration, but host mutation of copied VT cells is rejected as the endpoint.
- Ghostty is the main bias for VT shape. Kitty is cross-reference pressure only. The required endpoint is a stateful, C ABI render-state boundary owned by `howl-vt`, consumed by host and renderer only after it exists and is tested.

## Accepted Start Gates

- After the public VT render-state hover/highlight update C ABI exists and passes VT ABI tests, host hover/highlight cleanup may start.
- After the VT render-state C ABI exists and passes VT ABI tests, renderer `VtSurface` deletion and input reshaping may start.
- After host and renderer can consume the new VT render-state boundary, downstream cleanup may start.
- Before those conditions are true, downstream cleanup remains blocked.
- The old `howl_vt_terminal_copy_surface` path may be kept only as the named bridge slice below. Its deletion condition is host and renderer no longer using `HowlVtSurfaceResult` or renderer `VtSurface`.

## Ghostty Anchor Map

- `utils/dev_references/terminals/ghostty/src/terminal/render.zig:20-23`: render state belongs under `src/terminal`, not renderer, because it is renderer-generic and converts terminal state to renderable form.
- `utils/dev_references/terminals/ghostty/src/terminal/render.zig:25-48`: `RenderState` is stateful, optimized for repeated render calls and dirty regions, initialized empty then updated from terminal state.
- `utils/dev_references/terminals/ghostty/src/terminal/render.zig:49-83`: `RenderState` owns rows, cols, colors, cursor, row data, dirty state, and active screen key.
- `utils/dev_references/terminals/ghostty/src/terminal/render.zig:90-92`: render state caches selection, so selection projection belongs in the VT render-state boundary.
- `utils/dev_references/terminals/ghostty/src/terminal/render.zig:123-128`: render colors are grouped as background, foreground, optional cursor color, and palette.
- `utils/dev_references/terminals/ghostty/src/terminal/render.zig:130-168`: cursor render-state exposes active position, viewport position, cursor cell, style, visual style, password input, visibility, blink, and wide-tail status.
- `utils/dev_references/terminals/ghostty/src/terminal/render.zig:170-199`: each viewport row owns raw row data, copied cells, dirty flag, selection range, and highlights.
- `utils/dev_references/terminals/ghostty/src/terminal/render.zig:201-208`: highlight ranges are row-local tagged ranges; Howl must model hover/highlight as row render-state facts, not host mutation of cells.
- `utils/dev_references/terminals/ghostty/src/terminal/render.zig:210-224`: render-state cells copy raw cell data plus grapheme and style data while avoiding unsafe managed memory exposure.
- `utils/dev_references/terminals/ghostty/src/terminal/render.zig:226-239`: dirty state is a three-way enum: false, partial, full.
- `utils/dev_references/terminals/ghostty/src/terminal/render.zig:259-267`: `RenderState.update` reads terminal state and returns allocation failure only.
- `utils/dev_references/terminals/ghostty/src/terminal/render.zig:268-304`: update computes full redraw from active screen change, terminal dirty, screen dirty, dimension change, and viewport pin change.
- `utils/dev_references/terminals/ghostty/src/terminal/render.zig:306-340`: update copies cheap global fields every frame: dimensions, viewport pin, cursor, colors, reverse color handling.
- `utils/dev_references/terminals/ghostty/src/terminal/render.zig:342-390`: update retains row storage, resizes rows to viewport height, and preserves row-level storage across updates.
- `utils/dev_references/terminals/ghostty/src/terminal/render.zig:397-461`: row iteration maps viewport pins, finds cursor viewport position, reads page cells, and clears row/page dirty ownership.
- `utils/dev_references/terminals/ghostty/src/terminal/render.zig:478-506`: raw cells are copied row-by-row and count is asserted against viewport columns.
- `utils/dev_references/terminals/ghostty/src/terminal/render.zig:556-628`: selection projection is row-local and cached; asserted ranges guarantee `start.x <= end.x` and same row.
- `utils/dev_references/terminals/ghostty/src/terminal/render.zig:631-649`: update sets global dirty to full or partial and consumes terminal/screen dirty flags.
- `utils/dev_references/terminals/ghostty/src/terminal/render.zig:651-731`: `updateHighlightsFlattened` adds tagged row-local highlights outside terminal critical sections and marks affected rows dirty.
- `utils/dev_references/terminals/ghostty/src/terminal/render.zig:799-824`: hyperlink lookup asserts viewport coordinates against render-state dimensions and returns empty on out-of-range input.
- `utils/dev_references/terminals/ghostty/include/ghostty/vt/render.h:22-41`: C API shape is a render-state group with create, update, then read.
- `utils/dev_references/terminals/ghostty/include/ghostty/vt/render.h:42-59`: dirty tracking has global and per-row layers; caller clears both after rendering.
- `utils/dev_references/terminals/ghostty/include/ghostty/vt/render.h:89-99`: C dirty enum matches internal false/partial/full and has max-value sentinel.
- `utils/dev_references/terminals/ghostty/include/ghostty/vt/render.h:121-191`: C data enum exposes cols, rows, dirty, row iterator, colors, cursor facts, and cursor viewport facts.
- `utils/dev_references/terminals/ghostty/include/ghostty/vt/render.h:204-228`: C row data enum exposes row dirty, raw row, cells, and row-local selection.
- `utils/dev_references/terminals/ghostty/include/ghostty/vt/render.h:241-262`: C row-local selection uses a sized struct with start/end columns and no-value result when absent.
- `utils/dev_references/terminals/ghostty/include/ghostty/vt/render.h:303-426`: C functions create/free/update/get/get_multi/set/colors_get render state.
- `utils/dev_references/terminals/ghostty/include/ghostty/vt/render.h:428-538`: C functions create/free row iterator, advance it, get/get_multi row facts, and set row dirty.
- `utils/dev_references/terminals/ghostty/include/ghostty/vt/render.h:540-721`: C functions create/free row cells iterator, advance/select cells, and get/get_multi cell facts.
- `utils/dev_references/terminals/ghostty/src/terminal/c/render.zig:20-23`: C `RenderStateWrapper` owns allocator and internal `renderpkg.RenderState`.
- `utils/dev_references/terminals/ghostty/src/terminal/c/render.zig:25-40`: C row iterator stores slices into render-state row arrays, including dirty, selection, and palette.
- `utils/dev_references/terminals/ghostty/src/terminal/c/render.zig:42-52`: C row-cells iterator stores slices into row cell arrays plus row selection and palette.
- `utils/dev_references/terminals/ghostty/src/terminal/c/render.zig:54-71`: C opaque handles and sized `RowSelection` map internal render-state values to ABI shapes.
- `utils/dev_references/terminals/ghostty/src/terminal/c/render.zig:90-127`: C data enum has comptime output-type mapping for typed `get` calls.
- `utils/dev_references/terminals/ghostty/src/terminal/c/render.zig:180-189`: C `update` validates handles and updates render state from terminal.
- `utils/dev_references/terminals/ghostty/src/terminal/c/render.zig:191-231`: C `get` and `get_multi` validate enum values and stop on first failed get.
- `utils/dev_references/terminals/ghostty/src/terminal/c/render.zig:234-285`: typed get writes cols, rows, dirty, row iterator, colors, and cursor facts; cursor viewport values return invalid when absent.
- `utils/dev_references/terminals/ghostty/src/terminal/c/render.zig:288-320`: C `set` only mutates render-state dirty option.
- `utils/dev_references/terminals/ghostty/src/terminal/c/render.zig:322-378`: sized color struct getter copies fields only when the caller-provided size includes each field.
- `utils/dev_references/terminals/ghostty/src/terminal/c/render.zig:408-450`: row and cell iterator advance/select are bounded against stored slice lengths.
- `utils/dev_references/terminals/ghostty/src/terminal/c/render.zig:459-485`: row-cells data enum maps raw cell, style, graphemes, colors, selected, styling, and UTF-8 graphemes to output types.
- `utils/dev_references/terminals/ghostty/src/terminal/c/render.zig:531-583`: row-cells typed get handles selection membership and styling with direct row/cell slices.
- `utils/dev_references/terminals/ghostty/src/terminal/c/render.zig:617-647`: row data and row option enum types map dirty/raw/cells/selection and row dirty mutation.
- `utils/dev_references/terminals/ghostty/src/terminal/c/render.zig:649-727`: row get validates current row, returns cells iterator and row selection, and returns no-value when selection is absent.
- `utils/dev_references/terminals/ghostty/src/terminal/c/render.zig:729-762`: row dirty mutation is explicit and row-position bounded.
- `utils/dev_references/terminals/ghostty/src/terminal/c/render.zig:764-820`: C render-state tests cover new/free, invalid update/get, colors, and dirty behavior.
- `utils/dev_references/terminals/ghostty/src/terminal/c/main.zig:32`: C render module is imported as `render` under terminal C API.
- `utils/dev_references/terminals/ghostty/src/terminal/c/main.zig:69-87`: C render-state functions are re-exported through terminal C main.
- `utils/dev_references/terminals/ghostty/src/lib_vt.zig:214-232`: lib VT exports every C render-state symbol with stable `ghostty_render_state_*` names.
- `utils/dev_references/terminals/ghostty/src/terminal/Screen.zig:47-57`: `Screen` owns cursor and tracked selection.
- `utils/dev_references/terminals/ghostty/src/terminal/Screen.zig:81-93`: `Screen.Dirty` currently covers selection and hyperlink hover dirtiness.
- `utils/dev_references/terminals/ghostty/src/terminal/Screen.zig:121-185`: `Screen.Cursor` owns active coordinate, visual style, wrapping/protection/style/hyperlink/semantic state, and page pointers.
- `utils/dev_references/terminals/ghostty/src/terminal/ScreenSet.zig:17-31`: `ScreenSet` owns primary/alternate keys, active screen pointer, and initialized screens.
- `utils/dev_references/terminals/ghostty/src/terminal/ScreenSet.zig:33-36`: `ScreenSet` has generation counters for stale external handles.
- `utils/dev_references/terminals/ghostty/src/terminal/ScreenSet.zig:63-107`: `ScreenSet` provides get, get-init, remove, and switch-to behavior around active screen ownership.

## Kitty Cross-Pressure Only

- Kitty is cross-pressure only. It does not override Ghostty for Howl VT render-state shape.
- `utils/dev_references/terminals/kitty/kitty/screen.h:50-67`: Kitty tracks selections as screen-owned state with last-rendered iteration data and count/capacity.
- `utils/dev_references/terminals/kitty/kitty/screen.h:83-98`: Kitty overlay line separately owns CPU/GPU cells and dirty state, reinforcing line/cell render data separation.
- `utils/dev_references/terminals/kitty/kitty/screen.h:113-148`: Kitty `Screen` owns dimensions, selections, last-rendered cursor info, dirty flags, active cursor, line buffers, graphics managers, history, color profile, hyperlink state, and cursor render info.
- `utils/dev_references/terminals/kitty/kitty/line.h:37-42`: Kitty splits GPU cell styling/render fields from CPU text cell fields.
- `utils/dev_references/terminals/kitty/kitty/line.h:50-82`: Kitty `CPUCell` stores codepoint/index, hyperlink id, wrap, multicell and layout flags.
- `utils/dev_references/terminals/kitty/kitty/line.h:84-105`: Kitty `Line` owns GPU cells, CPU cells, dimensions, dirty/image attrs, and text cache.
- `utils/dev_references/terminals/kitty/kitty/line-buf.h:13-22`: Kitty `LineBuf` owns cell buffers, row mapping, line attributes, and a reusable line object.
- `utils/dev_references/terminals/kitty/kitty/line-buf.c:47-55`: line dirty state is per-line and explicitly markable/clearable.
- `utils/dev_references/terminals/kitty/kitty/screen.c:225-231`: full sprite dirty invalidation marks screen dirty and marks all main/alt/history lines dirty.
- `utils/dev_references/terminals/kitty/kitty/screen.c:3498-3502`: screen dirty reset clears screen dirty and history-added count after render update.
- `utils/dev_references/terminals/kitty/kitty/screen.c:3637-3704`: cell data update resets dirty, iterates render lines, renders only dirty lines or cursor-moved rows, updates line data, then clears line dirty.
- `utils/dev_references/terminals/kitty/kitty/screen.c:3851-3882`: selection rendering is projected into row/cell ranges, including multicell expansion.
- `utils/dev_references/terminals/kitty/kitty/screen.c:3897-3917`: selection, URL ranges, and extra cursors are applied into a render-side mask buffer, not baked into base cell storage.
- `utils/dev_references/terminals/kitty/kitty/screen.c:5296-5311`: selection dirtiness compares scroll, selection counts, extra cursor dirty, and last-rendered iteration data.
- `utils/dev_references/terminals/kitty/kitty/data-types.h:217-236`: Kitty `Cursor` and `CursorRenderInfo` separate terminal cursor state from render info such as focus, visibility, shape, opacity, blink opacity, and multicursor count.

## Current Howl Divergence Map

- `howl-vt/include/howl_vt.h:83-138`: current cell ABI already flattens codepoint, combining, flags, colors, attrs, selected bit, and link id into one `HowlVtSurfaceCell`.
- `howl-vt/include/howl_vt.h:162-185`: current cursor ABI and extra cursor ABI live inside the surface aggregate.
- `howl-vt/include/howl_vt.h:198-209`: selection exists as a terminal-level struct/result, but row-local selection is baked into cell attrs via `selected` later.
- `howl-vt/include/howl_vt.h:215-233`: `HowlVtSurface` is monolithic: cells, dimensions, scroll row, dirty rows/spans, cursor, cursor colors, extra cursors, render colors, and selection.
- `howl-vt/include/howl_vt.h:246-258`: `HowlVtSurfaceResult` adds status, history, scrollback offset, snapshot, dirty generation, and the monolithic source.
- `howl-vt/include/howl_vt.h:332-347`: the ABI copies the entire surface into caller buffers via `howl_vt_terminal_copy_surface`.
- `howl-vt/include/howl_vt.h:427`: surface acknowledgement is separate from the copy operation.
- `howl-vt/src/ffi/surface.zig:13-121`: `ffi/surface.zig` mirrors the monolithic C ABI with FFI structs and no stateful render-state owner.
- `howl-vt/src/ffi/surface.zig:139-162`: `FfiSurfaceResult` uses the field name `source`, which hides owner truth and mirrors the rejected aggregate.
- `howl-vt/src/ffi/surface.zig:220-258`: `surfaceResult` fills the monolithic aggregate and sets selection on the surface result rather than exposing row-local selection from a render-state object.
- `howl-vt/src/ffi/surface.zig:274-285`: selection is projected by mutating copied cell attrs with `selected = 1`.
- `howl-vt/src/ffi/surface.zig:300-347`: `terminalCopySurface` snapshots, validates buffers, copies cells, mutates selection into cells, copies dirty rows, and returns the monolithic result.
- `howl-vt/src/ffi/surface.zig:359-597`: current tests prove monolithic surface copy, colors, cursor, color identity, hyperlink copy, stale hyperlink rejection, and selection baked into cells.
- `howl-render/src/vt_surface/surface.zig:4-15`: renderer has its own `VtSurfaceSnapshot` with dirty metadata copied from VT.
- `howl-render/src/vt_surface/surface.zig:17-45`: renderer `VtSurface` mirrors VT fields and adds cursor opacity, text blink opacity, cursor focus, effective shape, cursor trails, retained storage, and a compatibility blink field.
- `howl-render/src/vt_surface/surface.zig:46-93`: renderer owns allocation/deallocation and cloning of copied VT cells and dirty metadata.
- `howl-render/src/vt_surface/surface.zig:111-140`: renderer validates the mirrored VT surface boundary rather than consuming a VT-owned render-state boundary.
- `howl-render/src/vt_surface/surface.zig:171-205`: renderer validates `HowlVtSurfaceResult`, including pointer spans and dirty arrays.
- `howl-render/src/vt_surface/surface.zig:207-252`: renderer converts `HowlVtSurfaceResult` into a renderer-owned `VtSurface` copy.
- `howl-render/src/render_session.zig:106-112`: render session prepare input takes `vt_surface.VtSurface`, making the renderer mirror a required input.
- `howl-render/src/render_session.zig:169-179`: render session derives theme, cursor, and damage from renderer `VtSurface` fields.
- `howl-render/src/render_session.zig:192-201`: render session maps renderer `VtSurface` cells into text scene input through scratch storage.
- `howl-render/src/vt_surface/text_input.zig:68-97`: renderer maps `HowlVtSurfaceCell` directly to text input, including inverse and selected styles.
- `howl-render/src/vt_surface/text_input.zig:117-140`: renderer maps dirty-only cells from dirty row metadata.
- `howl-render/src/vt_surface/text_input.zig:183-238`: renderer consumes `vt_surface.VtSurface` to produce text scene input, cursor, and damage.
- `howl-render/src/vt_surface/damage.zig:5-23`: renderer validates dirty rows/spans copied from VT.
- `howl-render/src/vt_surface/damage.zig:42-60`: renderer compares cursor presentation changes on renderer-owned `VtSurface` fields.
- `howl-render/src/vt_surface/damage.zig:67-75`: renderer mutates cursor blink visibility inside `VtSurface`.
- `howl-render/src/vt_surface/damage.zig:81-112`: renderer deduplicates entire mirrored `VtSurface`, including cells, dirty metadata, colors, selection, cursor facts, and renderer presentation additions.
- `howl-render/src/vt_surface/cursor.zig:72-90`: renderer defines `CursorPresentation`, a renderer-owned output shape.
- `howl-render/src/vt_surface/cursor.zig:92-120`: renderer maps cursor presentation from mirrored `VtSurface`.
- `howl-render/src/vt_surface/cursor.zig:122-146`: renderer still supports legacy generic state cursor mapping.
- `howl-linux-host/src/terminal/vt_surface.zig:24-31`: host `VisibleCopy` wraps the monolithic `HowlVtSurfaceResult`.
- `howl-linux-host/src/terminal/vt_surface.zig:33-38`: host scratch owns copied surface cells and dirty arrays.
- `howl-linux-host/src/terminal/vt_surface.zig:56-71`: host captures visible surface, applies optional hover mutation, and writes cursor flags into host VT state.
- `howl-linux-host/src/terminal/vt_surface.zig:147-184`: host calls `howl_vt_terminal_copy_surface`, validates monolithic spans, and returns copied surface.
- `howl-linux-host/src/terminal/vt_surface.zig:195-214`: host mutates copied cells for hyperlink hover underline and marks dirty ranges locally.
- `howl-linux-host/src/terminal/vt_surface.zig:216-230`: host dirty range mutation is tied to copied cell mutation, not VT render-state highlight truth.
- `howl-linux-host/src/terminal/vt_surface.zig:236-263`: host tests prove hover mutation as host-side copied-cell mutation; this is rejected as endpoint.
- `howl-vt/include/howl_vt.h:386-452`: current public render-state ABI declares init/deinit/update/ack/get/get_multi/set/colors/row/row-cells functions only; it has no public host-callable hover/highlight update function.
- `howl-vt/src/render_state.zig:216-242`: current VT owner has `RenderState.updateHighlightsForHyperlink`, but it is not reachable from public C ABI.
- `howl-vt/src/ffi/render_state.zig:496-507`: current FFI exposes hover update only through `testRenderStateUpdateHighlightsForHyperlink`, so host code cannot call it through `howl_vt.h`.
- `howl-vt/src/ffi/main.zig:100-119`: current FFI main re-exports render-state reads/iterators but no hover update symbol.
- `howl-vt/src/libhowl_vt.zig:32-51`: current shared-library exports include render-state reads/iterators but no `howl_vt_render_state_*highlight*` update symbol.
- `howl-linux-host/src/terminal/surface.zig:591-600`: host render drive dereferences `visible.surface` and passes a `HowlVtSurfaceResult` pointer to renderer prepare, so host consumption cannot be completed by editing `vt_surface.zig` alone.

## Exact Required Howl Shape

- Add `howl-vt/src/render_state.zig` as the VT owner of stateful renderable viewport data. It owns `RenderState`, retained row storage, copied cell rows, dirty state, colors, cursor render facts, row-local selection ranges, and row-local highlight ranges.
- Add `howl-vt/src/ffi/render_state.zig` as C ABI translator only. It owns opaque wrapper handles and typed C get/set/iterator functions. It does not own terminal mutation policy.
- Update `howl-vt/src/ffi/main.zig` and `howl-vt/src/libhowl_vt.zig` to route and export the new C ABI symbols.
- Update `howl-vt/include/howl_vt.h` to declare the render-state ABI. Keep declarations sorted in the existing single header without adding a second public header.
- Do not add `howl-vt/src/ffi/surface_bridge.zig`. The old `howl_vt_terminal_copy_surface` compatibility path remains in `howl-vt/src/ffi/surface.zig` until Slice 6 deletes the monolithic endpoint.
- Do not add a manager, controller, context, source, publication, or bucket struct.
- Do not add Zig-shaped host imports. Hosts consume C ABI symbols only.
- C ABI symbol set to add exactly:
- `typedef struct HowlVtRenderState HowlVtRenderState;`
- `typedef HowlVtRenderState *HowlVtRenderStateHandle;`
- `typedef struct HowlVtRenderStateRowIterator HowlVtRenderStateRowIterator;`
- `typedef HowlVtRenderStateRowIterator *HowlVtRenderStateRowIteratorHandle;`
- `typedef struct HowlVtRenderStateRowCells HowlVtRenderStateRowCells;`
- `typedef HowlVtRenderStateRowCells *HowlVtRenderStateRowCellsHandle;`
- `typedef enum { HOWL_VT_RENDER_STATE_DIRTY_FALSE = 0, HOWL_VT_RENDER_STATE_DIRTY_PARTIAL = 1, HOWL_VT_RENDER_STATE_DIRTY_FULL = 2 } HowlVtRenderStateDirty;`
- `typedef enum { HOWL_VT_RENDER_STATE_CURSOR_VISUAL_STYLE_BAR = 0, HOWL_VT_RENDER_STATE_CURSOR_VISUAL_STYLE_BLOCK = 1, HOWL_VT_RENDER_STATE_CURSOR_VISUAL_STYLE_UNDERLINE = 2, HOWL_VT_RENDER_STATE_CURSOR_VISUAL_STYLE_BLOCK_HOLLOW = 3 } HowlVtRenderStateCursorVisualStyle;`
- `typedef enum { HOWL_VT_RENDER_STATE_DATA_INVALID = 0, HOWL_VT_RENDER_STATE_DATA_COLS = 1, HOWL_VT_RENDER_STATE_DATA_ROWS = 2, HOWL_VT_RENDER_STATE_DATA_DIRTY = 3, HOWL_VT_RENDER_STATE_DATA_ROW_ITERATOR = 4, HOWL_VT_RENDER_STATE_DATA_COLOR_BACKGROUND = 5, HOWL_VT_RENDER_STATE_DATA_COLOR_FOREGROUND = 6, HOWL_VT_RENDER_STATE_DATA_COLOR_CURSOR = 7, HOWL_VT_RENDER_STATE_DATA_COLOR_CURSOR_HAS_VALUE = 8, HOWL_VT_RENDER_STATE_DATA_COLOR_PALETTE = 9, HOWL_VT_RENDER_STATE_DATA_CURSOR_VISUAL_STYLE = 10, HOWL_VT_RENDER_STATE_DATA_CURSOR_VISIBLE = 11, HOWL_VT_RENDER_STATE_DATA_CURSOR_BLINKING = 12, HOWL_VT_RENDER_STATE_DATA_CURSOR_VIEWPORT_HAS_VALUE = 13, HOWL_VT_RENDER_STATE_DATA_CURSOR_VIEWPORT_X = 14, HOWL_VT_RENDER_STATE_DATA_CURSOR_VIEWPORT_Y = 15, HOWL_VT_RENDER_STATE_DATA_CURSOR_VIEWPORT_WIDE_TAIL = 16, HOWL_VT_RENDER_STATE_DATA_SNAPSHOT_SEQ = 17, HOWL_VT_RENDER_STATE_DATA_DIRTY_GENERATION = 18, HOWL_VT_RENDER_STATE_DATA_HISTORY_COUNT = 19, HOWL_VT_RENDER_STATE_DATA_SCROLLBACK_OFFSET = 20, HOWL_VT_RENDER_STATE_DATA_SCROLL_ROW = 21, HOWL_VT_RENDER_STATE_DATA_IS_ALTERNATE_SCREEN = 22 } HowlVtRenderStateData;`
- `typedef enum { HOWL_VT_RENDER_STATE_OPTION_DIRTY = 0 } HowlVtRenderStateOption;`
- `typedef enum { HOWL_VT_RENDER_STATE_ROW_DATA_INVALID = 0, HOWL_VT_RENDER_STATE_ROW_DATA_DIRTY = 1, HOWL_VT_RENDER_STATE_ROW_DATA_CELLS = 2, HOWL_VT_RENDER_STATE_ROW_DATA_SELECTION = 3, HOWL_VT_RENDER_STATE_ROW_DATA_HIGHLIGHT_COUNT = 4, HOWL_VT_RENDER_STATE_ROW_DATA_HIGHLIGHT = 5 } HowlVtRenderStateRowData;`
- `typedef enum { HOWL_VT_RENDER_STATE_ROW_OPTION_DIRTY = 0 } HowlVtRenderStateRowOption;`
- `typedef enum { HOWL_VT_RENDER_STATE_ROW_CELLS_DATA_INVALID = 0, HOWL_VT_RENDER_STATE_ROW_CELLS_DATA_CELL = 1, HOWL_VT_RENDER_STATE_ROW_CELLS_DATA_SELECTED = 2, HOWL_VT_RENDER_STATE_ROW_CELLS_DATA_HIGHLIGHTED = 3 } HowlVtRenderStateRowCellsData;`
- `typedef struct { size_t size; uint16_t start_col; uint16_t end_col; } HowlVtRenderStateRowSelection;`
- `typedef struct { size_t size; uint8_t tag; uint8_t reserved0; uint16_t index; uint16_t start_col; uint16_t end_col; } HowlVtRenderStateRowHighlight;`
- `typedef struct { size_t size; HowlVtRgb8 background; HowlVtRgb8 foreground; HowlVtRgb8 cursor; uint8_t cursor_has_value; uint8_t reserved0; uint16_t reserved1; HowlVtRgb8 palette[256]; } HowlVtRenderStateColors;`
- `HowlVtCallStatus howl_vt_render_state_init(HowlVtRenderStateHandle *out_state);`
- `void howl_vt_render_state_deinit(HowlVtRenderStateHandle state);`
- `HowlVtCallStatus howl_vt_render_state_update(HowlVtRenderStateHandle state, HowlVtHandle terminal, uint64_t scrollback_offset);`
- `HowlVtCallStatus howl_vt_render_state_ack(HowlVtRenderStateHandle state, HowlVtHandle terminal);`
- `HowlVtCallStatus howl_vt_render_state_update_highlights_for_hyperlink(HowlVtRenderStateHandle state, uint8_t tag, uint16_t row, uint16_t col, uint8_t underline_style);`
- `HowlVtCallStatus howl_vt_render_state_get(HowlVtRenderStateHandle state, HowlVtRenderStateData data, void *out);`
- `HowlVtCallStatus howl_vt_render_state_get_multi(HowlVtRenderStateHandle state, size_t count, const HowlVtRenderStateData *keys, void **values, size_t *out_written);`
- `HowlVtCallStatus howl_vt_render_state_set(HowlVtRenderStateHandle state, HowlVtRenderStateOption option, const void *value);`
- `HowlVtCallStatus howl_vt_render_state_colors_get(HowlVtRenderStateHandle state, HowlVtRenderStateColors *out_colors);`
- `HowlVtCallStatus howl_vt_render_state_row_iterator_init(HowlVtRenderStateRowIteratorHandle *out_iterator);`
- `void howl_vt_render_state_row_iterator_deinit(HowlVtRenderStateRowIteratorHandle iterator);`
- `uint8_t howl_vt_render_state_row_iterator_next(HowlVtRenderStateRowIteratorHandle iterator);`
- `HowlVtCallStatus howl_vt_render_state_row_get(HowlVtRenderStateRowIteratorHandle iterator, HowlVtRenderStateRowData data, void *out);`
- `HowlVtCallStatus howl_vt_render_state_row_get_multi(HowlVtRenderStateRowIteratorHandle iterator, size_t count, const HowlVtRenderStateRowData *keys, void **values, size_t *out_written);`
- `HowlVtCallStatus howl_vt_render_state_row_set(HowlVtRenderStateRowIteratorHandle iterator, HowlVtRenderStateRowOption option, const void *value);`
- `HowlVtCallStatus howl_vt_render_state_row_cells_init(HowlVtRenderStateRowCellsHandle *out_cells);`
- `void howl_vt_render_state_row_cells_deinit(HowlVtRenderStateRowCellsHandle cells);`
- `uint8_t howl_vt_render_state_row_cells_next(HowlVtRenderStateRowCellsHandle cells);`
- `HowlVtCallStatus howl_vt_render_state_row_cells_select(HowlVtRenderStateRowCellsHandle cells, uint16_t col);`
- `HowlVtCallStatus howl_vt_render_state_row_cells_get(HowlVtRenderStateRowCellsHandle cells, HowlVtRenderStateRowCellsData data, void *out);`
- `HowlVtCallStatus howl_vt_render_state_row_cells_get_multi(HowlVtRenderStateRowCellsHandle cells, size_t count, const HowlVtRenderStateRowCellsData *keys, void **values, size_t *out_written);`
- Internal Zig names to add exactly:
- `render_state.RenderState`, `render_state.RenderState.Dirty`, `render_state.RenderState.Row`, `render_state.RenderState.Cell`, `render_state.RenderState.Highlight`, `render_state.RenderState.SelectionRange`, `render_state.RenderState.Colors`, `render_state.RenderState.Cursor`.
- `RenderState.empty`, `RenderState.deinit`, `RenderState.update`, `RenderState.ack`, `RenderState.updateHighlightsForHyperlink`, `RenderState.rowCount`, `RenderState.cellCount`.
- `ffi/render_state.zig` symbols: `FfiRenderState`, `FfiRowIterator`, `FfiRowCells`, `FfiDirty`, `FfiCursorVisualStyle`, `FfiData`, `FfiOption`, `FfiRowData`, `FfiRowOption`, `FfiRowCellsData`, `FfiRowSelection`, `FfiRowHighlight`, `FfiColors`, `renderStateInit`, `renderStateDeinit`, `renderStateUpdate`, `renderStateAck`, `renderStateUpdateHighlightsForHyperlink`, `renderStateGet`, `renderStateGetMulti`, `renderStateSet`, `renderStateColorsGet`, `renderStateRowIteratorInit`, `renderStateRowIteratorDeinit`, `renderStateRowIteratorNext`, `renderStateRowGet`, `renderStateRowGetMulti`, `renderStateRowSet`, `renderStateRowCellsInit`, `renderStateRowCellsDeinit`, `renderStateRowCellsNext`, `renderStateRowCellsSelect`, `renderStateRowCellsGet`, `renderStateRowCellsGetMulti`.

## Worker Slice Queue

### Slice 1: VT Render-State Owner And ABI Skeleton

- Goal: add the stateful VT render-state owner, C ABI declarations, FFI handles, export routing, and base lifecycle/get/set tests without changing host or renderer consumers.
- Allowed files: `howl-vt/include/howl_vt.h`, `howl-vt/src/render_state.zig`, `howl-vt/src/ffi/render_state.zig`, `howl-vt/src/ffi/main.zig`, `howl-vt/src/libhowl_vt.zig`, `howl-vt/test_ffi.zig`, `howl-vt/test/abi.zig`, `howl-vt/test_abi.zig`, `howl-vt/test_unit.zig`.
- Required shape: implement `RenderState.empty`, `RenderState.deinit`, `FfiRenderState`, handle init/deinit, dirty enum, data enum for scalar metadata, `get`, `get_multi`, `set`, colors sized struct getter, row/cell iterator handle allocation stubs that return no rows before update, and exports with the exact C symbols listed above.
- Required tests: VT ABI tests for init/deinit null safety, missing handle status, invalid enum status, dirty get/set, get_multi success and first-failure `out_written`, colors sized-struct minimum-size rejection, row iterator empty before update, row/cell handle deinit null safety.
- Non-goals: no host changes, no renderer changes, no deletion of `HowlVtSurfaceResult`, no hover/highlight behavior, no input reshaping, no compatibility aliases.
- Stop conditions: missing exact C symbol names, unbounded enum casts, new manager/controller/context/source/publication names, C ABI not exported through `ffi/main.zig` and `libhowl_vt.zig`, tests requiring host or renderer changes.
- Receipt fields: orchestrator session id, researcher session id `researcher-2026-06-16-vt-render-state-plan-correction-02`, reviewer session id, coder session id, commit hash, `zig build -Dskip-run=false test:abi -Dfilter=render_state` result, `zig build test:unit -Dfilter=render_state` result.

### Slice 2: Render-State Update From Terminal Viewport

- Goal: make `RenderState.update` copy viewport rows/cells, metadata, dirty rows, colors, cursor, selection ranges, and screen key truth from `terminal.Terminal` without changing old `terminalCopySurface` behavior.
- Allowed files: `howl-vt/src/render_state.zig`, `howl-vt/src/ffi/render_state.zig`, `howl-vt/src/ffi/surface.zig`, `howl-vt/test_unit.zig`, `howl-vt/test_abi.zig`.
- Required shape: `RenderState.update(allocator, vt, scrollback_offset)` uses existing `visibleMeta`, `surfaceSnapshot`, `screen_set.copyViewCells`, `screen_set.copyDirtyRows`, `selection_projection.visibleRange`, and `host_state.terminalColorState` to populate retained row storage. Row-local selection is stored in `RenderState.Row.selection` and cells no longer need selection mutation for render-state consumers. The old `terminalCopySurface` path remains byte-for-byte compatible for existing tests.
- Required tests: VT unit tests proving rows/cols/history/scrollback/snapshot/dirty generation, row iteration length equals rows, cell iteration length equals cols, copied cell codepoints match terminal output, dirty false/partial/full classification follows dimensions/dirty rows, cursor viewport has-value/x/y/wide-tail fields, colors and palette match existing surface tests, row selection range matches existing selection projection with live and scrolled viewport.
- Non-goals: no host hover cleanup, no renderer deletion, no old surface ABI removal, no new convenience API for Zig hosts.
- Stop conditions: render-state update mutates renderer-owned facts, selection remains available only as cell attr, dirty rows are exposed without row dirty API, snapshot ack semantics are lost, scrollback offset overflow is not clamped as current surface copy tests expect.
- Receipt fields: orchestrator session id, researcher session id, reviewer session id, coder session id, commit hash, `zig build test:abi -Dfilter=render_state` result, `zig build test:unit -Dfilter=render_state` result, `zig build test:abi -Dfilter=surface` result.

### Slice 3: Row Cells, Selection, And Highlight ABI Completion

- Goal: complete row/cell/selection/highlight C reads so host hover and renderer selection styling can consume VT render-state facts instead of host-mutated cells.
- Allowed files: `howl-vt/include/howl_vt.h`, `howl-vt/src/render_state.zig`, `howl-vt/src/ffi/render_state.zig`, `howl-vt/src/ffi/status.zig`, `howl-vt/test_ffi.zig`, `howl-vt/test/abi.zig`, `howl-vt/test_unit.zig`, `howl-vt/test_abi.zig`.
- Required shape: implement `HOWL_VT_RENDER_STATE_ROW_DATA_SELECTION`, `HOWL_VT_RENDER_STATE_ROW_DATA_HIGHLIGHT_COUNT`, `HOWL_VT_RENDER_STATE_ROW_DATA_HIGHLIGHT`, `HOWL_VT_RENDER_STATE_ROW_CELLS_DATA_CELL`, `HOWL_VT_RENDER_STATE_ROW_CELLS_DATA_SELECTED`, and `HOWL_VT_RENDER_STATE_ROW_CELLS_DATA_HIGHLIGHTED`. Add `RenderState.updateHighlightsForHyperlink(tag, row, col, underline_style)` that resolves the hovered cell link id in render-state rows, writes tagged row-local highlight ranges, and marks affected rows/global dirty partial. Use tag `1` for hyperlink hover underline.
- Required tests: ABI tests for row selection no-value on rows outside selection, selection sized-struct size rejection, selected cell boolean from row range, highlight count zero before hover, hover highlight range covers contiguous same-link cells across rows, highlighted cell boolean true only inside range, dirty rows/global dirty marked after highlight update, out-of-range hover is success with no highlight and no dirty escalation.
- Non-goals: no host consumption yet, no renderer consumption yet, no `HowlVtSurfaceResult` deletion, no hyperlink URI API replacement.
- Stop conditions: highlight is represented by mutating copied cells as the endpoint, highlight rows lack tags, row highlight lookup is unbounded, no-value and invalid-argument statuses are conflated, sized structs lack size validation.
- Receipt fields: orchestrator session id, researcher session id, reviewer session id, coder session id, commit hash, `zig build test:abi -Dfilter=render_state` result, `zig build test:unit -Dfilter=render_state` result.

### Slice 4: Public Hover/Highlight Update ABI

- Goal: expose the existing VT-owned hyperlink hover/highlight update path through public C ABI before host consumption starts.
- Allowed files: `howl-vt/include/howl_vt.h`, `howl-vt/src/render_state.zig`, `howl-vt/src/ffi/render_state.zig`, `howl-vt/src/ffi/main.zig`, `howl-vt/src/libhowl_vt.zig`, `howl-vt/test_ffi.zig`, `howl-vt/test/abi.zig`, `howl-vt/test_unit.zig`, `howl-vt/test_abi.zig`.
- Required shape: add public C symbol `howl_vt_render_state_update_highlights_for_hyperlink(HowlVtRenderStateHandle state, uint8_t tag, uint16_t row, uint16_t col, uint8_t underline_style)`. Add Zig FFI owner function `renderStateUpdateHighlightsForHyperlink` in `howl-vt/src/ffi/render_state.zig`, route it through `howl-vt/src/ffi/main.zig`, and export it from `howl-vt/src/libhowl_vt.zig`. The FFI function validates missing render-state handle as `HOWL_VT_CALL_MISSING_HANDLE`, accepts out-of-range row/col as `HOWL_VT_CALL_OK` with no highlight and no dirty escalation, passes `tag`, `row`, `col`, and `underline_style` to `RenderState.updateHighlightsForHyperlink`, and returns `HOWL_VT_CALL_INVALID_ARGUMENT` for underline styles outside `0..4`. `RenderState.updateHighlightsForHyperlink` must stop discarding underline style; it must accept and validate `UnderlineStyle` through the FFI seam while preserving existing row-local tagged highlight behavior.
- Required tests: ABI-root tests in `howl-vt/test/abi.zig` proving missing handle status, invalid underline style status, out-of-range hover success with no highlight and no dirty escalation, no-link hover success with no highlight and no dirty escalation, same-link hover produces tagged row highlight ranges readable through public row APIs, highlighted cell reads true only inside the range, and global/row dirty become partial/true after hover. Unit tests in `howl-vt/src/render_state.zig` or `howl-vt/test_unit.zig` must prove `underline_style` is accepted through the owner path without changing non-hover cell attrs.
- Non-goals: no host changes, no renderer changes, no old surface ABI deletion, no test-only helper as public substitute, no Zig-shaped host shortcut.
- Stop conditions: host consumption starts before this public symbol is declared/exported/tested, public symbol is only available through `test_ffi.zig`, underline style is ignored or unvalidated at the FFI seam, hover update mutates copied surface cells instead of render-state row highlights, tests live only inline and not in ABI root.
- Receipt fields: orchestrator session id, researcher session id `researcher-2026-06-17-vt-render-state-hover-abi-amendment-03`, reviewer session id, coder session id, commit hash, `zig build test:abi -- render_state` result, `zig build test:unit -- render_state` result, `zig build check` result in `howl-vt`.

### Slice 5: Host Consumes Render-State Boundary For Visible Capture And Hover

- Goal: move host visible capture and hover/highlight handling onto the public VT render-state C ABI after the public hover/highlight update API exists and is tested.
- Allowed files: `howl-linux-host/src/terminal/vt_surface.zig`, `howl-linux-host/src/terminal/surface.zig`, `howl-linux-host/src/terminal/surface_test.zig`.
- Required shape: replace `VisibleCopy.surface: HowlVtSurfaceResult` as the host visible-state owner with a host visible wrapper that owns `HowlVtRenderStateHandle`, row iterator, row cells iterator, and snapshot metadata read from `howl_vt_render_state_get`. `captureVisibleLockedWith` updates render state through `howl_vt_render_state_update`, applies hover through public `howl_vt_render_state_update_highlights_for_hyperlink`, and stops mutating copied `HowlVtSurfaceCell` arrays. Ack uses `howl_vt_render_state_ack`. `howl-linux-host/src/terminal/surface.zig` must stop dereferencing `visible.surface` as host visible truth at lines 591-600 and must read cursor/source facts from the new visible wrapper. The renderer prepare call may keep the old `HowlVtSurfaceResult` only as a named temporary compatibility payload inside the visible wrapper until Slice 6 reshapes renderer input; it must not be the host visible-state owner and it must not receive host hover mutation.
- Required tests: host unit tests proving capture updates render-state metadata, hover underline is expressed as a render-state highlight row range through public C ABI, dirty state becomes partial after hover, old `applyHyperlinkHover` mutation path is deleted, ack forwards render-state snapshot sequence through the new ack symbol, acquisition failure preserves no render mutation, and `surface.zig` drive path no longer dereferences `visible.surface` for cursor/source truth.
- Non-goals: no renderer deletion, no removal of old VT surface ABI, no host presentation redesign, no new preload micro-management file.
- Stop conditions: host starts before Slice 4 is accepted, host still mutates copied surface cells for hover, host imports Zig VT internals, host stores `HowlVtSurfaceResult` as the host visible-state owner, `surface.zig` still dereferences `visible.surface` for cursor/source truth, missing tests for hover dirty range.
- Receipt fields: orchestrator session id, researcher session id, reviewer session id, coder session id, commit hash, `zig build test:unit -Dfilter=vt_surface` result, `zig build test:integration` result.

### Slice 6: Renderer Consumes Render-State Boundary And Deletes Mirrored `VtSurface`

- Goal: remove renderer-owned mirrored `VtSurface` as input and reshape text preparation to consume render-state row/cell ABI facts through a render-owned adapter with no VT state ownership.
- Allowed files: `howl-render/src/vt_surface/surface.zig`, `howl-render/src/vt_surface/text_input.zig`, `howl-render/src/vt_surface/damage.zig`, `howl-render/src/vt_surface/cursor.zig`, `howl-render/src/render_session.zig`, `howl-render/src/test_unit.zig`, `howl-render/src/test_abi.zig`.
- Required shape: delete `VtSurface` as a retained mirror endpoint. Replace it with a small renderer adapter named `VtRenderStateInput` that borrows a `HowlVtRenderStateHandle` plus row/cell iterator handles for the duration of prepare only. `render_session.PrepareInput` uses `state: VtRenderStateInput`. Text input maps cells by iterating render-state rows/cells, selection/highlight by row facts, cursor presentation by render-state cursor data, colors by render-state colors, and damage by global/row dirty facts. Renderer may keep `CursorPresentation` as renderer-owned output.
- Required tests: renderer unit tests proving text scene input maps cells from render-state row/cell reads, dirty-only mapping uses row dirty flags, selection styling comes from row selection/cell selected reads, hover highlight styling comes from row highlight/cell highlighted reads, cursor presentation maps render-state cursor facts, blink opacity remains renderer-owned and no longer mutates VT surface mirror, old `sameVtSurface` dedupe tests are removed or replaced with render-state token/damage tests.
- Non-goals: no VT ABI symbol additions beyond those already accepted, no host changes, no compatibility aliases, no renderer-owned cell mirror replacement under another name.
- Stop conditions: a struct equivalent to old `VtSurface` remains as the endpoint, renderer still validates `HowlVtSurfaceResult`, renderer still owns VT cells beyond prepare scratch lifetime, selection is consumed only through cell attrs, cursor blink mutation writes into VT-owned data.
- Receipt fields: orchestrator session id, researcher session id, reviewer session id, coder session id, commit hash, `zig build test:unit -Dfilter=vt_surface` result, `zig build test:unit -Dfilter=render_session` result, `zig build test:abi` result.

### Slice 7: Delete Old Monolithic Endpoint

- Goal: remove the old `HowlVtSurfaceResult` endpoint after host and renderer consume render state.
- Allowed files: `howl-vt/include/howl_vt.h`, `howl-vt/src/ffi/surface.zig`, `howl-vt/src/ffi/main.zig`, `howl-vt/src/libhowl_vt.zig`, `howl-vt/test_abi.zig`, `howl-vt/test_unit.zig`, `howl-linux-host/src/terminal/vt_surface.zig`, `howl-linux-host/src/terminal/surface_test.zig`, `howl-render/src/vt_surface/surface.zig`, `howl-render/src/vt_surface/text_input.zig`, `howl-render/src/vt_surface/damage.zig`, `howl-render/src/vt_surface/cursor.zig`, `howl-render/src/render_session.zig`, `howl-render/src/test_unit.zig`, `howl-render/src/test_abi.zig`.
- Required shape: delete `HowlVtSurface`, `HowlVtSurfaceResult`, `howl_vt_terminal_query_visible_meta`, `howl_vt_terminal_copy_surface`, and `howl_vt_terminal_ack_surface` after Slice 5 and Slice 6 are accepted and product-code searches prove no old consumer remains. Keep cell, color, cursor, and selection leaf structs that are still used by render-state ABI. No bridge file exists in this plan.
- Required tests: full VT ABI tests passing with render-state symbols only, host tests passing without old copy surface symbols, renderer tests passing without `VtSurface`, and product-code search proving no `HowlVtSurfaceResult`, `howl_vt_terminal_copy_surface`, or renderer `VtSurface` references remain.
- Non-goals: no new ABI convenience aliases, no broad render architecture rewrite, no host UX changes.
- Stop conditions: host/render product code still references old surface symbols, deletion requires weakening tests, C ABI header leaves dead typedefs, a bridge file is added or retained.
- Receipt fields: orchestrator session id, researcher session id, reviewer session id, coder session id, commit hash, `zig build test` result, `zig build test:abi` result, `zig build test:unit` result, `rg "HowlVtSurfaceResult|howl_vt_terminal_copy_surface|\bVtSurface\b" howl-vt howl-render howl-linux-host` result with no product-code references to deleted old endpoint symbols.

## Sequencing Gates

- VT render-state ABI exists and is tested before host hover/highlight cleanup.
- Public VT render-state hover/highlight update ABI exists and is tested before host hover/highlight cleanup.
- VT render-state ABI exists and is tested before renderer `VtSurface` deletion/input reshaping.
- Host and renderer only consume the new boundary after it is available.
- Host cleanup starts after Slice 4 is accepted by reviewer and orchestrator.
- Renderer cleanup starts after Slice 1, Slice 2, Slice 3, and Slice 4 are accepted by reviewer and orchestrator.
- Old monolithic surface deletion starts after Slice 5 and Slice 6 are accepted and product-code searches prove no old consumer remains.

## Risks And Proof Gaps

- Ghostty C render-state API currently exposes internal highlight ranges in Zig but not in `include/ghostty/vt/render.h`; Howl must expose highlight rows because user gates require honest hover/highlight facts before host cleanup. This is a Howl invention, but it is the smallest extension of Ghostty `RenderState.Row.highlights` at `terminal/render.zig:197-208` and `updateHighlightsFlattened` at `terminal/render.zig:651-731`.
- Howl's existing screen storage differs from Ghostty PageList pins. The worker must map existing `screen_set.View` and dirty metadata into retained render-state rows without inventing page-pin handles.
- The old C ABI uses one public header. The plan keeps that to avoid extra public header churn, but the worker must keep declaration ordering readable.
- Row/cell iterator handles hold slices into render-state storage. Tests must prove row/cell data becomes invalid only by documented update ownership; C ABI docs must say row/cell data is valid until the render state is updated or deinitialized.
- Current renderer owns cursor blink opacity. That remains renderer-owned presentation policy and must not move into VT render state.
- Slice 4 exists because accepted Slice 3 exposed hover/highlight reads but left the write/update path test-only; host consumption is blocked until that public C ABI is added and tested.
- Host `surface.zig` is an exact Slice 5 allowed file because current drive code dereferences `visible.surface` at `howl-linux-host/src/terminal/surface.zig:591-600`.
- Full deletion of old surface ABI is safe only in this private product after host/render references are removed. The deletion slice records that condition explicitly.

## Readiness Judgment

- Corrected planning amendment accepted by reviewer.
- The plan rejects renderer-owned mirrored `VtSurface` as endpoint.
- The plan rejects monolithic `HowlVtSurfaceResult` as settled endpoint.
- The worker has exact files, symbols, tests, non-goals, stop conditions, and receipt fields.
- Amended Slice 4 is seeded in `sprints/current.txt`; host consumption remains blocked until Slice 4 is reviewed, verified, and accepted.
