# VT Screen Owner Seams

Date: 2026-05-30

## Question

Map `Screen` fields to true owner files and identify one first extractable seam without starting a
giant screen rewrite.

## Sources Read

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `research/2026-05-30-hygiene-audit/roadmap.md` Slice 4.3
- `howl-vt/src/screen.zig`
- `howl-vt/src/screen/cursor.zig`
- `howl-vt/src/screen/dirty.zig`
- `howl-vt/src/screen/history.zig`
- `howl-vt/src/screen/margins.zig`
- `howl-vt/src/screen/resize.zig`
- `howl-vt/src/screen/tabs.zig`

## Field Map

- Geometry: `rows`, `cols`, `row_origin`, and visible storage are still owned by `Screen` because
  write, scroll, resize, history, dirty rows, and view projection all consume them together.
- Cursor owner: `screen/cursor.zig` owns cursor movement and save/restore behavior, but fields remain
  on `Screen`: `cursor_row`, `cursor_col`, `wrap_pending`, `cursor_visible`, `cursor_style_default`,
  `cursor_style`, and `saved_cursor`.
- Margins owner: `screen/margins.zig` owns scroll and left/right margin mutation, with fields
  `origin_mode`, `left_right_margin_mode`, `left_margin`, `right_margin`, `scroll_top`, and
  `scroll_bottom` still on `Screen`.
- History owner: `screen/history.zig` owns logical history authority/projection helpers, with fields
  `history`, `history_wraps`, `history_capacity`, `history_count`, `history_write_idx`,
  `history_lines`, `history_lines_start`, `open_history_line`, and `open_history_reuse_slot` still
  on `Screen`.
- Dirty owner: `screen/dirty.zig` owns dirty range mutation, with fields `dirty_rows`,
  `dirty_cols_start`, and `dirty_cols_end` still on `Screen`.
- Tabs owner: `screen/tabs.zig` owns tab stop behavior, with `tab_stops` still on `Screen`.
- Resize owner: `screen/resize.zig` owns reflow machinery and allocates temporary line/reflow buffers,
  but it mutates geometry, visible storage, dirty buffers, tab stops, cursor, and history together.
- Cell/style/write/erase/edit/scroll owners already own behavior, but not their own state structs.

## Current Shape

`Screen` is still the right state aggregate today. Existing owner files are behavior owners over a
single central state object, not independent state owners. Pulling cursor, margins, history, dirty,
tabs, or resize state into separate structs in one pass would create false simplicity: almost every
operation crosses geometry, storage, dirty marking, and cursor state.

The first safe seam is not history or resize. `screen/resize.zig` currently allocates temporary
`LogicalLinesState` and `ReflowState`, rebuilds history authority, installs visible buffers, restores
cursor, and frees old storage. That is too wide for the first Phase 4 implementation slice.

The first extractable seam is dirty state ownership because:

- `screen/dirty.zig` already owns all mark algorithms.
- `Screen.clearDirtyRows`, `peekDirtyRows`, `markDirtyRow`, `markDirtyCols`, `markDirtyRows`, and
  `markAllRowsDirty` are thin wrappers or direct field manipulation.
- Dirty buffers are allocated in initialization and resize, but the mutation contract is compact.
- Surface publication ack already clears dirty rows through `screen_set.clearDirtyRows`, so dirty
  behavior is externally important and already tested.

## Proposed Next Slice

Name: `Extract Screen Dirty State`.

Exact files:

- `howl-vt/src/screen.zig`
- `howl-vt/src/screen/dirty.zig`
- `howl-vt/src/screen/resize.zig` only for field installation after resize
- `howl-vt/src/test/terminal_surface.zig` or existing screen tests for exact dirty behavior coverage
- `libs.yaml` only if owner metadata needs sharper wording

Changes:

- Introduce `dirty.State` holding `rows: ?DirtyRows`, `cols_start: ?[]u16`, and `cols_end: ?[]u16`.
- Replace `Screen.dirty_rows`, `Screen.dirty_cols_start`, and `Screen.dirty_cols_end` with one
  `dirty_state: dirty.State` field.
- Keep `Screen.peekDirtyRows`, `clearDirtyRows`, and mark methods as entrypoints that delegate to
  `dirty.State`/`dirty.zig`.
- Preserve allocation ownership: initialization and resize still allocate/free dirty column buffers
  with the screen allocator in this slice.

Verification:

- `zig build check`
- `zig build test`
- `git diff --check`
- `rg 'dirty_rows|dirty_cols_start|dirty_cols_end' howl-vt/src/screen.zig howl-vt/src/screen/resize.zig howl-vt/src/screen/dirty.zig`

Stop conditions:

- Stop if resize reflow must be reshaped beyond installing the new dirty state.
- Stop if history, cursor, margins, tabs, or visible storage movement becomes necessary.
- Stop if a broad `screen/state.zig` or `types.zig` bucket appears.

## Later Seams

- History authority/projection needs a separate scratchpad because `history.zig` mixes logical lines,
  projected row storage, resize reflow helpers, and scrollback retention.
- Resize temporary storage needs capacity research before any static-storage or bounded-work claims.
- Cursor/margins can be considered only after dirty state is no longer interleaved with every mark.
