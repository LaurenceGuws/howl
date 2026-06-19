# Historical Authority

- Historical authority at the time: active host surface layout redesign plan for `orch-2026-06-19-host-surface-layout-01`.
- Why done: accepted host/display viewport slices were implemented, verified, committed, and pushed before the event-semantics sprint replaced the active surface.
- Must not be used for: live execution scope, current slice authority, or event-semantics naming decisions.

# Howl Linux Host Surface Layout Redesign

Status: active source-backed plan seed. Reviewer must gate this package before coder execution. Coder and reviewer own execution correction inside `loops/howl-linux-host-surface-layout-loop.txt`.

Orchestrator session id: `orch-2026-06-19-host-surface-layout-01`.
Research seed id: `orch-research-seed-2026-06-19-host-surface-layout-01`.
Reviewer id: open.
Coder id: open.
Commit-hash receipt status: open.

## Problem

- `deriveHostLayout(...)` in `howl-linux-host/src/terminal/render_surface_layout.zig` must die.
- Current host layout can report `rows=35`, `cell_px.height=16`, and `grid_px.height=570` together.
- That violates the terminal grid invariant because `35 * 16 = 560`, not `570`.
- The bug class is owner mixing: host content region, terminal grid sizing, and render surface pixel allocation are collapsed into one vague derivation.
- The live product symptom is terminal content/viewport placement around the top tab bar and bottom visible content.

## Source Anchors

Current Howl anchors:

- `howl-linux-host/src/terminal/render_surface_layout.zig:10-13` defines `SurfaceLayoutRequest` with separate `render_px` and `grid_px`.
- `howl-linux-host/src/terminal/render_surface_layout.zig:40-55` initializes render/grid dimensions to the same raw input size.
- `howl-linux-host/src/terminal/render_surface_layout.zig:57-79` stores pending grid size from raw resize dimensions.
- `howl-linux-host/src/terminal/render_surface_layout.zig:148-169` derives layout while holding term state.
- `howl-linux-host/src/terminal/render_surface_layout.zig:171-181` is the bad `deriveHostLayout(...)` implementation.
- `howl-linux-host/src/display/layout.zig:35-57` owns content size and rect after tab bar.
- `howl-linux-host/src/event.zig:142-144` opens tabs with display-owned content pixel/logical size.
- `howl-linux-host/src/event.zig:438-446` currently presents the raw display content rect as the terminal texture rect.
- `howl-linux-host/src/terminal/render_retained.zig:45-51` stores render pixels, grid pixels, columns, rows, and cell pixels.
- `howl-render/src/geometry.zig:114-120` currently derives grid size by truncating pixels by cell size, but does not snap the pixel size back to the derived grid.

Alacritty anchors:

- `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:145-169` has `SizeInfo` owning window dimensions, cell dimensions, padding, screen lines, and columns together.
- `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:245-249` derives `screen_lines` and `columns` from content area divided by cell size.
- `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:186-194` derives PTY `WindowSize` from `columns`, `screen_lines`, `cell_width`, and `cell_height`.
- `utils/dev_references/terminals/alacritty/alacritty_terminal/src/tty/unix.rs:428-435` reports PTY pixel size as `ws_col * cell_width` and `ws_row * cell_height`.
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/mod.rs:329-339` sets the GL viewport for cell rendering from display-owned size and padding.

Kitty anchors:

- `utils/dev_references/terminals/kitty/kitty/state.c:695-722` splits OS window regions into `central` and `tab_bar` before terminal window rendering.
- `utils/dev_references/terminals/kitty/kitty/state.c:1133-1145` stores explicit window render geometry through `set_window_render_data(...)`.
- `utils/dev_references/terminals/kitty/kitty/shaders.c:1435-1447` renders using explicit geometry width/height and sets the GPU viewport to that geometry.

## Required Shape

The replacement must separate the owners:

- Display owns raw content region after tab bar.
- Terminal surface layout owns grid snapping from content pixels and cell pixels.
- Render owns a terminal surface whose pixel size equals the snapped grid size.
- Present draws the terminal texture using the snapped terminal surface rect, not the raw content rect.
- Leftover raw content pixels are display-owned background area below/right of the terminal grid unless reviewer finds a stronger source-backed alignment rule.

Canonical derivation:

```zig
cols = max(1, content_px.width / cell_w)
rows = max(1, content_px.height / cell_h)
grid_px.width = cols * cell_w
grid_px.height = rows * cell_h
render_px = grid_px
```

Required invariants:

```zig
assert(layout.cols > 0)
assert(layout.rows > 0)
assert(layout.cell_px.width > 0)
assert(layout.cell_px.height > 0)
assert(layout.grid_px.width == layout.cols * layout.cell_px.width)
assert(layout.grid_px.height == layout.rows * layout.cell_px.height)
assert(layout.render_px.width == layout.grid_px.width)
assert(layout.render_px.height == layout.grid_px.height)
```

Expected example:

```text
content_px.height = 570
cell_px.height = 16
rows = 35
grid_px.height = 560
render_px.height = 560
```

## Proposed Slice

Allowed product files for the first executable slice:

- `howl-linux-host/src/terminal/render_surface_layout.zig`
- `howl-linux-host/src/terminal/render_retained.zig`
- `howl-linux-host/src/terminal/surface.zig`
- `howl-linux-host/src/terminal/surface_test.zig`
- `howl-linux-host/src/terminal/input.zig`
- `howl-linux-host/src/display/layout.zig`
- `howl-linux-host/src/event.zig`
- `howl-linux-host/src/display/present.zig`
- `howl-linux-host/src/display/display.zig`
- `howl-linux-host/src/display/rects.zig`

Allowed accountability file for coder evidence:

- `loops/howl-linux-host-surface-layout-loop.txt`

Reviewer may narrow allowed files if current source proves fewer are needed. Coder must stop if additional product files are required.

Implementation requirements:

- Delete `deriveHostLayout(...)`.
- Replace `SurfaceLayoutRequest` with this exact shape:

```zig
pub const SurfaceLayoutRequest = struct {
    content_px: c.HowlRenderPixelSize,
};
```

- Replace `deriveHostLayout(...)` with this exact public owner-local derivation function for tests and layout sync:

```zig
pub fn snapSurfaceLayout(request: SurfaceLayoutRequest, font_size_px: u16) retained.SurfaceLayout
```

- In `State`, replace raw render/grid field names with content-owned field names:
  - `render_px_w` and `render_px_h` die.
  - `grid_px_w` and `grid_px_h` die.
  - `pending_grid_px_w` and `pending_grid_px_h` die.
  - Add `content_px_w`, `content_px_h`, `pending_content_px_w`, and `pending_content_px_h`.
- Update `howl-linux-host/src/terminal/input.zig:132` to pass `self.geometry.content_px_w` and `self.geometry.content_px_h` to `Ops.contentRelativeEvent(...)` after the field rename.
- Derive terminal columns/rows from display-owned content pixels and host cell pixels.
- Snap `grid_px` and `render_px` to `cols * cell_w` and `rows * cell_h`.
- `snapSurfaceLayout(...)` must return `.render_px == .grid_px` using the snapped pixel dimensions, not raw `content_px`.
- Commit layout only after asserting the invariants above.
- Ensure PTY resize and VT resize consume snapped `cols` and `rows`.
- Ensure render text prepare receives snapped `render_px` and `grid_px`.
- Add this exact `TerminalSurface` method in `howl-linux-host/src/terminal/surface.zig`:

```zig
pub fn textureRect(self: *const Context, content_rect: Layout.Rect) Layout.Rect
```

- `textureRect(...)` must return `content_rect.x` and `content_rect.y`, and must return width/height from `self.term.render.surface_layout.render_px` cast to `c_int`.
- `textureRect(...)` must assert the snapped render width and height are positive and do not exceed the passed display-owned content rect width/height.
- Change `event.renderSnapshot(...)` at current `howl-linux-host/src/event.zig:438-446` to compute `const content_rect = DisplayLayout.contentRect(...)`, then `const texture_rect = tab.textureRect(content_rect)`, then pass `texture_rect` to `overlaySnapshot(...)` and the present snapshot.
- Preserve top-left placement under the tab bar unless reviewer supplies a stronger source-backed leftover-pixel policy.

Non-goals:

- No VT behavior changes.
- No render C ABI/header changes.
- No PTY behavior changes beyond receiving corrected rows/cols/pixel size consequences already owned by layout.
- No diagnostic logging additions unless reviewer requires a short-lived proof print.
- No cursor/blink work.
- No renderer architecture redesign.
- No tab-bar visual redesign.
- No compatibility alias or bridge preserving `deriveHostLayout(...)`.

Required tests and verification:

- Add owner-local tests for `snapSurfaceLayout(...)`, including `960x570` with `8x16` cells producing `120x35` and `960x560` snapped pixels.
- Update `howl-linux-host/src/terminal/surface_test.zig` calls at current `:242` and `:322` away from `deriveHostLayout(...)`.
- Add a `howl-linux-host/src/terminal/surface_test.zig` test for `Surface.textureRect(...)` proving a content rect height of `570` with a retained snapped render height of `560` returns a terminal texture rect height of `560` and preserves the content rect `x`/`y`.
- Add or update present/layout tests so the terminal texture rect height follows `Surface.textureRect(...)`, not raw `DisplayLayout.contentRect(...)` height.
- Run `zig build check` in `howl-linux-host`.
- Run any existing host unit test target if present; if no separate unit target exists, record that explicitly.
- Run root `zig build check` after host verification passes.

Stop conditions:

- Reviewer rejects this plan as under-specified.
- Coder needs files outside the allowed list.
- Any implementation keeps `deriveHostLayout(...)` as a compatibility wrapper.
- `rows * cell_px.height != grid_px.height` or `cols * cell_px.width != grid_px.width` can still be committed.
- `render_px` and `grid_px` disagree without an explicit source-backed render-surface reason recorded in this artifact.
- Fix requires changing VT, PTY, render C ABI, or headers.

## Loop Handoff

- Next role: reviewer gates this plan for execution readiness.
- If accepted, coder implements only the accepted slice and records evidence in `loops/howl-linux-host-surface-layout-loop.txt`.
- Reviewer then reviews the diff and verification output.
- Orchestrator closes receipts only after reviewer acceptance and independent verification.

## Slice 2: Display-Owned Terminal Placement

Status: active next-slice seed after slice 1 was accepted by reviewer and orchestrator verification. Reviewer must gate before coder execution.

Problem:

- Slice 1 made snapped terminal size correct, but terminal placement still lives as `TerminalSurface.textureRect(...)` in `howl-linux-host/src/terminal/surface.zig`.
- Kitty pressure keeps OS/window regions and terminal geometry in the window/display region path: `kitty/state.c:695-722` splits `central` and `tab_bar`; `kitty/shaders.c:1435-1447` renders explicit geometry.
- Alacritty pressure keeps display size/padding/viewport placement in display `SizeInfo`, while terminal state consumes lines/columns.
- Howl should not make terminal surface own placement inside the host content region. The terminal can expose snapped texture size; display layout should place it.

Required shape:

- Add to `howl-linux-host/src/display/layout.zig`:

```zig
pub fn terminalRect(content_rect: Rect, texture_size: Size) Rect
```

- `terminalRect(...)` must preserve `content_rect.x` and `content_rect.y`.
- `terminalRect(...)` must use `texture_size.width` and `texture_size.height` as the returned width/height.
- `terminalRect(...)` must assert positive texture dimensions and assert texture dimensions fit inside the content rect.
- Replace `Surface.textureRect(...)` with:

```zig
pub fn textureSize(self: *const Context) Layout.Size
```

- `textureSize(...)` returns snapped `term.render.surface_layout.render_px` width/height as `c_int` and asserts positivity.
- `event.renderSnapshot(...)` must compute `content_rect = DisplayLayout.contentRect(...)`, `texture_size = tab.textureSize()`, and `texture_rect = DisplayLayout.terminalRect(content_rect, texture_size)`.
- `overlaySnapshot(...)` continues to receive the placed `texture_rect`.

Allowed product files:

- `howl-linux-host/src/display/layout.zig`
- `howl-linux-host/src/terminal/surface.zig`
- `howl-linux-host/src/terminal/surface_test.zig`
- `howl-linux-host/src/event.zig`

Allowed accountability file:

- `loops/howl-linux-host-surface-layout-loop.txt`

Required tests and verification:

- Move the slice-1 texture rect proof to `DisplayLayout.terminalRect(...)`: raw content rect height `570` with texture size `960x560` returns rect height `560` and preserves `x`/`y`.
- Add or update a `Surface.textureSize(...)` proof that it returns the snapped retained render size.
- `zig build check` in `howl-linux-host`.
- `zig build test:unit` in `howl-linux-host`.
- root `zig build check`.

Non-goals:

- No changes to snapping math.
- No VT, PTY, or render ABI changes.
- No cursor/blink work.
- No visual styling or tab-bar redesign.

Stop conditions:

- `TerminalSurface` still owns placement from content rect to terminal rect after the slice.
- `DisplayLayout.terminalRect(...)` permits terminal texture dimensions outside the content rect.
- Coder needs files outside the allowed list.

## Slice 3: Terminal Input Uses Placed Terminal Rect

Status: active next-slice seed after Slice 2 was accepted by reviewer and orchestrator verification. Reviewer must gate before coder execution.

Problem:

- Display now owns the placed snapped terminal rect for presentation, but input still enters through raw content logical/pixel extents.
- Current source: `howl-linux-host/src/event.zig:324-336` forwards input with content logical width/height and tab-bar logical origin.
- Current source: `howl-linux-host/src/terminal/input.zig:132` maps mouse events through `self.geometry.content_px_w` and `self.geometry.content_px_h`.
- This lets raw leftover pixels below/right of the snapped grid behave as terminal cells by clamping to the last row/column.
- Alacritty pressure rejects this: `SizeInfo.contains_point(...)` excludes padding/non-grid area from the terminal grid.

Required shape:

- Add to `howl-linux-host/src/display/layout.zig`:

```zig
pub fn terminalLogicalSize(content_logical: Size, content_px: Size, terminal_px: Size) Size
```

- `terminalLogicalSize(...)` must scale terminal pixel width/height into logical units using the existing `scaleLogicalSpan(...)` direction: terminal logical span equals `(terminal_px * content_logical) / content_px`, clamped to at least `1` and at most the corresponding content logical dimension.
- Add assertions that content and terminal dimensions are positive and terminal pixels fit inside content pixels.
- Change `event.forwardTerminalInput(...)` to compute:
  - `content_px = DisplayLayout.contentPixelSize(...)`
  - `content_logical = DisplayLayout.contentLogicalSize(...)`
  - `terminal_px = tab.textureSize()`
  - `terminal_logical = DisplayLayout.terminalLogicalSize(content_logical, content_px, terminal_px)`
  - `origin_y = DisplayLayout.tabBarHeightLogical(...)`
  - forward terminal input with `terminal_logical.width` and `terminal_logical.height`, not raw content logical size.
- Change `terminal/input.zig` mouse mapping to use snapped terminal texture size from `self.term.render.surface_layout.render_px`, not `self.geometry.content_px_w/content_px_h`.
- Leave `origin_x/origin_y` unchanged; placement remains top-left inside the content region.

Allowed product files:

- `howl-linux-host/src/display/layout.zig`
- `howl-linux-host/src/event.zig`
- `howl-linux-host/src/terminal/input.zig`
- `howl-linux-host/src/terminal/surface_test.zig`

Allowed accountability file:

- `loops/howl-linux-host-surface-layout-loop.txt`

Required tests and verification:

- Add `DisplayLayout.terminalLogicalSize(...)` tests proving raw content `960x570`, content logical `960x570`, terminal pixels `960x560` returns logical height `560`.
- Add or update terminal input test so a mouse event in the raw leftover strip below snapped terminal height is rejected rather than mapped to the last row.
- `zig build check` in `howl-linux-host`.
- `zig build test:unit` in `howl-linux-host`.
- root `zig build check`.

Non-goals:

- No snapping math changes.
- No VT, PTY, render ABI, or header changes.
- No cursor/blink work.
- No scrollback behavior redesign beyond rejecting pointer events outside the snapped terminal rect.

Stop conditions:

- Pointer events outside the snapped terminal rect still map to a terminal row/column.
- Input scaling needs files outside the allowed list.
- Fix requires changing SDL event collection or input ring ownership.
