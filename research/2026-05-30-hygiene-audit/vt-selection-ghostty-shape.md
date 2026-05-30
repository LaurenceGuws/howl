# VT Selection Ghostty Shape

Date: 2026-05-30

## Question

Before moving selection projection or copy behavior out of `howl-vt/src/ffi.zig`, decide the owner shape from Ghostty first. The target is not a mechanical helper move. The target is a source-backed VT selection owner that keeps C ABI files as translators only.

## Sources Read

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `utils/dev_references/terminals/ghostty/src/terminal/Selection.zig`
- `utils/dev_references/terminals/ghostty/src/terminal/Screen.zig`
- `utils/dev_references/terminals/ghostty/src/terminal/ScreenSet.zig`
- `howl-vt/src/ffi.zig`
- `howl-vt/src/selection.zig`
- `howl-vt/src/selection/state.zig`
- `howl-vt/src/screen_set.zig`

## Ghostty Facts

- Ghostty stores selection on the terminal `Screen` itself: `Screen.zig` has `selection: ?Selection = null` and documents that it must be a tracked selection, with callers using `select` instead of writing the field directly.
- Ghostty's `Selection.zig` models selection bounds as page-list pins, either untracked or tracked. Tracked bounds are updated as screen/page data moves.
- Ghostty's `Screen.select` converts untracked selections to tracked selections, untracks the old selection, assigns the new one, and sets `dirty.selection`.
- Ghostty's `Screen.clearSelection` untracks selection pins and sets `dirty.selection` when a selection existed.
- Ghostty's selection-to-text path is a `Screen` method: `Screen.selectionString` uses `ScreenFormatter` with `.content = .{ .selection = opts.sel }`, `.unwrap = true`, and `.trim = opts.trim`.
- Ghostty tests selection movement under scrolling at `Screen.zig` test `Screen: scrolling moves selection`; the selected pins move with scroll and can become unresolvable when they leave retained content.
- Ghostty `ScreenSet.zig` only owns active-screen selection between primary/alternate screens by pointing at active `Screen`; it does not own selection projection behavior itself.

## Howl Facts

- `howl-vt/src/selection/state.zig` owns lifecycle state as viewport/history coordinates: start, update, finish, clear, ordered endpoints, and grid invalidation.
- `howl-vt/src/screen_set.zig` owns active primary/alternate screen choice, visible view creation, row-source mapping, dirty rows, and `SurfaceSnapshot` containing `selection`.
- `howl-vt/src/ffi.zig` still owns non-C selection behavior:
  - `selectionRowSource`
  - `selectionContentEndExclusive`
  - `visibleSelectionRow`
  - `visibleSelectionRange`
  - `applyVisibleSelection`
  - `copySelectionText`
- These helpers inspect `screen_set.Set`, `screen_set.View`, screen history/live rows, and terminal allocation. They are not C translation logic.
- Current Howl selection is not Ghostty-style tracked pins. It is coordinate-based and invalidated by explicit grid checks through `SelectionState.clearIfInvalidatedByGrid`.

## Decision

Do not deepen the current coordinate selection model in `ffi.zig`.

For the next non-ABI slice, move C-free selection projection and copy behavior to the smallest VT owners:

- `selection/state.zig` should continue owning lifecycle state and endpoint ordering only.
- A new or existing selection owner should own row-coordinate selection text and visible projection, but it must not import or mention `HowlVt*` C types.
- `screen_set.View` should remain the owner of visible row-source mapping and content end for a visible row.
- `screen_set.Set` should provide any needed C-free row-source/content lookup for selection copy only if the helper truly belongs to primary/alternate/history state.
- `ffi.zig` should translate handles, C buffers, status values, and exported C selection structs only.

This is a stopgap toward Ghostty's better model, not the final model. A later deeper VT slice should evaluate replacing coordinate selection with tracked screen/page positions once Howl's screen/page model can support it safely.

## Worker-Ready Slice Shape

The immediate slice may move only the current `ffi.zig` helper behavior out of FFI without changing ABI or semantics.

Allowed files:

- `howl-vt/src/ffi.zig`
- `howl-vt/src/selection.zig`
- `howl-vt/src/selection/state.zig`
- `howl-vt/src/screen_set.zig`
- A new exact owner under `howl-vt/src/selection/` only if naming is precise; do not use `manager`, `controller`, `runtime`, `flow`, `pipeline`, `api`, `abi`, or `types`.

Required behavior preservation:

- History rows remain addressed by negative selection rows.
- Alternate screen selection copy cannot read primary history.
- Visible selection marking remains based on the visible `screen_set.View` row-source mapping.
- End-column handling remains inclusive from user endpoint to exclusive internal range.
- Empty rows and space-only rows keep current copy/projection behavior.
- Copied text allocation remains caller-owned through the terminal allocator and FFI still copies into the C caller's buffer.

Required tests:

- Existing `howl-vt/src/ffi.zig` visible-selection tests must remain or move with the owner behavior.
- Add or preserve tests proving history-to-live selection projection and copy text across rows.
- Add or preserve an alternate-screen case proving selection copy/projection does not read primary history.

## Non-Goals

- Do not change `howl-vt/include/howl_vt.h`.
- Do not rename exported C functions.
- Do not redesign selection ABI.
- Do not introduce Ghostty pins in this slice.
- Do not rewrite terminal screen storage.
- Do not add compatibility aliases or module buckets.

## Review Gates

- `rg 'fn copySelectionText|fn applyVisibleSelection|fn visibleSelectionRange|fn selectionRowSource' howl-vt/src/ffi.zig` prints nothing.
- `rg 'HowlVt' howl-vt/src/selection howl-vt/src/screen_set.zig` prints nothing.
- `rg 'manager|controller|runtime|flow|pipeline|types\.zig|api\.zig|abi\.zig' howl-vt/src/selection howl-vt/src/screen_set.zig` has no new owner vocabulary hits.
- `zig build check`
- `zig build test`
- `git diff --check`

## Proof Gaps

- Howl does not yet have Ghostty tracked selection pins. Coordinate invalidation is weaker than Ghostty's selection movement under scroll.
- The final Ghostty-like design needs a separate screen/page model slice, not a hidden change in the C FFI cleanup.
- Current allocation in `copySelectionText` uses `ArrayList` during a C call. This slice may preserve it, but a later capacity slice should decide whether VT selection copy needs retained scratch storage.
