# Render capability reset scratchpad

Current slice: `vt_visual_view_contract`

The VT/render boundary was accepted at `4a95571`. This slice implements only
VT's side of that contract: visual borrowing, cumulative dirty evidence, exact
acknowledgement, and owner-local proofs. Render projection, executable storage,
control coupling, GPU work, and compatibility adapters remain out of scope.

## Implementation checklist

- inventory the current VT visual publication and every mutation path that
  contributes visual dirtiness;
- replace the overloaded publication noun instead of aliasing it;
- keep cursor overlay state separate from cell dirty spans;
- prove cumulative sparse dirtiness and source-wide full discontinuities;
- prove stale or mismatched acknowledgement cannot discard newer dirtiness;
- preserve explicit caller allocation and borrowed lifetime boundaries;
- run howl-vt owner checks and the workspace check before review.

## Accepted boundary record

The remainder of this file records the accepted design evidence from
`4a95571`; implementation findings are appended above it while this slice is
active.

Scope: decision evidence only. No source or build contract is implemented by
this slice. The symbol inventory accepted at `0ea9f52` remains the source
accounting baseline.

## Revised decision

Recommend one public, stateless visual-delta projection under
`howl_render.terminal`:

```zig
pub fn project(
    source: howl_vt.Terminal.VisualView,
    mode: ProjectMode,
    buffers: Buffers,
    selection_style: SelectionStyle,
) Error!Update
```

Normal projection visits and copies only cumulative VT-dirty rows/cells plus
bounded old/new overlay facts. Full projection is explicit recovery for first
use, resize, lost backing continuity, or a source-wide visual change. Render
does not retain a grid, publish, queue, lock, acknowledge, allocate, shape,
rasterize, or issue backend commands.

Required complexity:

- one dirty cell with unchanged overlays is O(1) cells and one row;
- a source cursor overlay change is O(1) rows/cells; executable blink phase
  changes require no VT scan or projection;
- `r` dirty rows containing `c` visual cells after bounded multicell expansion
  cost O(r + c);
- full projection alone costs O(rows * cols).

## Dependency and VT input

- `howl-render` depends directly on the independently embeddable `howl-vt`
  package. Render owns semantic-to-visual interpretation; an adapter or generic
  iterator would make every embedder reproduce that interpretation.
- `howl_render.terminal` is the core render namespace. Accepted `text` and
  `generated` capabilities remain independently selectable and are not invoked
  by `project`.
- VT replaces the overloaded visual use of `Terminal.SurfacePublication` with
  `Terminal.visualView() -> Terminal.VisualView`. The borrow contains only
  coherent visual semantics, cumulative dirty evidence, and an opaque
  `DirtyToken`; host consequences and runtime publication facts are absent.

`VisualView` supplies:

- nonzero `u16` rows and columns;
- copied cursor position, visibility, shape, and blink intent;
- borrowed cell lookup and DEC line geometry;
- copied palette/default/cursor colors and reverse-screen state;
- VT-resolved selected half-open span per visible row;
- cumulative `VisualDirty` since the last successful `ackVisual`.

`VisualDirty` is either `full` or one inclusive minimum column span per dirty
row. VT guarantees, and render asserts, these sibling-module invariants:

- every row/span/cursor/cell/selection fact is in bounds;
- cells contain valid Unicode scalars, bounded combining data, and coherent
  multicell geometry;
- old and new selected spans are dirty when selection appearance changes;
- a changed row geometry dirties its complete row;
- viewport/screen/resize discontinuity and palette/default/reverse changes that
  cannot be represented sparsely produce `full`;
- dirty state is cumulative and unchanged until exact acknowledgement.

`VisualDirty` covers cell mutations, selection-span changes, row geometry, and
source-wide presentation discontinuities. Cursor position, shape, visibility,
blink intent, and resolved colors are a separate overlay: render compares the
source `Cursor` with `ProjectionBaseline.cursor` and emits cursor-only
`RowPatch` values for the old and new affected rows without changing VT cell
dirty semantics.

The caller excludes mutation of the terminal for `visualView`, `project`,
runtime admission, and optional acknowledgement. `project` retains no VT
pointer or slice. Every returned variable-length fact resides in caller-owned
buffers and remains valid after VT mutation.

## Small retained baseline

Render requires no previous complete `Visual`. Incremental mode carries only:

```zig
pub const ProjectionBaseline = struct {
    rows: u16,
    cols: u16,
    cursor: Cursor,
    selection_style: SelectionStyle,
};

pub const ProjectMode = union(enum) {
    full,
    incremental: ProjectionBaseline,
};
```

`ProjectionBaseline` is copied metadata for the last update admitted to
caller-owned runtime storage. It exists to damage the prior cursor position and
to reject a selection-style or geometry discontinuity that needs explicit full
projection. It contains no cells, allocation, generation, borrow, lock, or
cleanup.

VT cumulative dirty owns prior selection, row-geometry, palette, and cell
effects; duplicating them in render baseline would recreate a shadow terminal.
Executable cursor blink phase is not terminal state: toggling it damages only
the cursor cell identified by `ProjectionBaseline.cursor` and requires no VT
scan or projection. Source cursor movement or presentation changes use the
projection baseline's old cursor and the source's new cursor independently of
cumulative VT dirty spans.

## Backend-neutral delta vocabulary

Public values:

- `Rgb`: `r`, `g`, `b: u8`.
- `ProjectionBaseline`, `ProjectMode`, `Buffers`, `Update`, and `RowPatch`.
- `CellBaseline`: `normal`, `raised`, `lowered`.
- `UnderlineStyle`: `none`, `single`, `double`, `curly`, `dotted`, `dashed`.
- `CursorShape`: `block`, `underline`, `bar`, `none`.
- `SelectionStyle`: resolved `foreground`, `background: Rgb`.
- `Cursor`: `row`, `col: u16`; `visible`, `blink: bool`; `CursorShape`;
  `color`, `text_color: Rgb`.
- `Cell`: `codepoint: u21`; `combining_len: u8`; `combining: [3]u21`;
  multicell `width`, `height`, `x`, `y: u8`; resolved foreground, background,
  and underline `Rgb`; `font: u4`; `CellBaseline`; bold, dim, italic,
  ordinary/rapid blink, glyph visibility, underline, strikethrough, and
  selection booleans; `UnderlineStyle`; `link_id: u32`.
- `LineGeometry`: single width, double width, double-height top, or
  double-height bottom.

Caller buffers and initialized output:

```zig
pub const Buffers = struct {
    cells: []Cell,
    rows: []RowPatch,
};

pub const RowPatch = struct {
    row: u16,
    start_col: u16,
    cell_offset: usize,
    cell_count: u16,
    geometry: LineGeometry,
    damage_start: u16,
    damage_end: u16,
};

pub const Update = struct {
    rows: u16,
    cols: u16,
    full: bool,
    cells: []const Cell,
    row_patches: []const RowPatch,
    cursor: Cursor,
    next_baseline: ProjectionBaseline,
};
```

Each affected row yields exactly one `RowPatch`, matching VT's dense
minimum-span model. `cell_offset` and `cell_count` select its row-major packed
cells in `Update.cells`; `cell_count == 0` represents cursor-only visual damage
and copies no cell. For that case `start_col = damage_start` and `cell_offset`
is the used cell-buffer length, making the empty slice canonical.
`damage_start...damage_end` is the inclusive union of the cell patch and old/new
cursor cells. Render expands a semantic cell span only to complete affected
multicell clusters; VT invariants make that bounded from cells at the span
edges. Geometry is the current value for that row and can be applied
idempotently when a cursor-only patch carries no changed cells. Pixel glyph
overhang/filter expansion belongs to later text/backend preparation because it
depends on metrics.

Selected cells have final selection colors and retain a selection boolean for
later non-color appearance. Reverse/default/indexed colors are resolved.
Protection, palette indices, VT modes, pane coordinates, cell pixels, history
policy, source generations, glyph masks, textures, and GPU values are absent.

This is a render-owned delta, not a GPU command stream. The executable owns a
complete retained visual grid and row geometry and applies admitted row patches
in order. Applying a patch is structural copying of render-owned values; the
embedder does not interpret VT colors, selection endpoints, protection, line
flags, or state-machine modes. Later render text preparation may inspect the
retained neighboring visual cells needed for shaping and ligature context, so
the delta does not force shaping isolated dirty cells. Storage and ordering are
runtime-owned; shaping rules remain render-owned. Accepted `howl_render.text`
and `howl_render.generated` remain separate shaping and rasterization
operations.

## Storage, errors, and transaction

- `project` allocates nothing. The caller allocates `Buffers` through its
  explicit allocator and owns their lifetime and cleanup.
- The caller first reserves one bounded runtime update buffer, then calls
  `project` into it. `Update` borrows only initialized buffer prefixes.
- Destination buffers are nonaliasing by programmer contract; render asserts
  this internal boundary instead of adding a recoverable alias error.
- Incremental required counts are computed from bounded dirty spans and overlay
  rows before any destination mutation. Full required counts are checked from
  `rows * cols`. A short buffer leaves every destination byte unchanged.
- After bounds checks, typed VT invariants are assertions. There is no duplicate
  full-grid validation pass and no `InvalidCell`, `InvalidCursor`,
  `InvalidSelection`, or `InvalidDamage` error.

Exact recoverable errors:

```text
FullRequired       incremental baseline geometry/style does not match source
InsufficientCells caller cell-patch capacity is short
InsufficientPatches caller row-patch capacity is short
```

There is no `OutOfMemory`, deinit, generation exhaustion, saturation, borrow,
release, or resize error. Capacity arithmetic uses checked `usize`; overflow is
an impossible VT `u16` invariant and is asserted after VT bounds establish it.

## Admission, acknowledgement, and skipped work

Projection is preparatory and does not mutate `ProjectionBaseline` or VT:

1. Executable reserves caller-owned runtime storage.
2. While VT mutation is excluded, it obtains `VisualView`, retains that view's
   opaque `DirtyToken`, and calls `project`.
3. It either declines the produced update, or admits the complete update to its
   bounded runtime storage.
4. Only after successful admission does it replace its small
   `ProjectionBaseline` with `Update.next_baseline` and call
   `Terminal.ackVisual(source.dirty_token)` with the exact token retained from
   that serialized source view.

Decline, capacity failure, or runtime saturation therefore leaves both baseline
and VT cumulative dirty unchanged. A later projection includes every
unacknowledged semantic change.

An admitted delta may not subsequently disappear. Runtime may apply admitted
deltas in order to its own retained backing and then coalesce presentation, or
retain them in an ordered bounded queue until application. That choice, slot
count, locking, wakeup, generation, and backpressure policy belong entirely to
the executable. Render owns none of them.

For a thread handoff, the producer writes a reserved executable-owned buffer;
after admission its initialized `Update` bytes are immutable until the consumer
returns that storage. No VT borrow crosses the handoff. Runtime can remain
nonblocking with respect to terminal progress by declining before
acknowledgement when no update storage is available; VT continues accumulating
bounded dirty facts.

## Full reconstruction and recovery

`project(source, .full, ...)` emits one full-width `RowPatch` per row with
`start_col = 0`, `cell_count = cols`, and damage `0...cols - 1`, plus the
complete cursor and next baseline. It is used for init, resize, lost backing
continuity, changed selection style, or a VT `VisualDirty.full`.

Once admitted and applied, a full update reconstructs every render visual fact
without prior state. Ordered nonvisual terminal consequences remain outside
this contract and cannot be collapsed by visual update coalescing.

## Current Howl evidence

- `howl-vt/src/terminal.zig:9238-9309`, `View`: borrowed projected cells,
  cursor, viewport, and line geometry until mutation.
- `howl-vt/src/terminal.zig:9311-9316`, `SurfaceSnapshot`, and
  `:9415-9428`, `projectSurface`: current coherent view, dirty, and selection.
- `howl-vt/src/terminal.zig:3490-3539`, `ScreenDirtyRows`/`DirtyState`:
  cumulative dense row spans and clean-row sentinel are already bounded.
- `howl-vt/src/terminal.zig:9467-9698`, `TerminalSelection`, `visibleRange`:
  VT already resolves selection semantics to visible row spans.
- `howl-vt/src/terminal.zig:9742-9780`, `Publication`, and
  `:13487-13491`, `ackSurface`: exact acknowledgement identity is useful VT
  evidence, while current publication sequence policy does not enter render.
- `howl-vt/src/terminal.zig:13566-13605`, `surfaceSnapshot`, and
  `:14092-14177`, `SurfacePublication`/`Presentation`: coherent colors are
  proven, but the aggregate is overloaded with nonvisual consequences.
- `howl-render/src/howl_frame.zig:471-633`, `validateSurface`,
  `accumulateDamage`, `copyFrame`: color/reverse/cluster/cursor translation and
  sparse-span evidence survive; complete validation, slots, and cumulative
  render damage do not.
- `howl-render/src/native_text.zig:15-165` and `FontSet` at `:175`: accepted
  text bounds and caller allocation remain separate from terminal projection.
- `howl-render/src/generated.zig:9-123`, `classify` and
  `rasterizeWithStroke`: accepted generated rasterization already uses bounded
  caller storage and changes no terminal contract.

## Reference lessons, not donated structure

- Ghostty `src/terminal/render.zig:356-723`, `RenderState.beginUpdate`, rebuilds
  only dirty rows in the common path and clears terminal dirty only after its
  owned copy is complete. Howl borrows proportional dirty consumption, but not
  retained render state, arenas, terminal mutation, or two-phase lifecycle.
- Alacritty `alacritty/src/display/content.rs:27-220`, `RenderableContent` and
  `RenderableCell`, resolves colors, selection, cursor, and wide-cell facts
  before backend drawing. `alacritty/src/display/damage.rs:15-130`,
  `DamageTracker`, retains only old cursor/selection metadata for damage;
  `:215-250`, `RenderDamageIterator.overdamage`, keeps pixel expansion in the
  backend. Howl borrows those separations, not its display architecture.
- Foot `render.c:3293-3321`, `dirty_old_cursor`/`dirty_cursor`, demonstrates
  explicit old/new cursor damage without scanning the grid.
  `render.c:3207-3291`, `reapply_old_damage`, shows backing continuity is a
  renderer/runtime concern rather than terminal dirty truth.
- Libvaxis `src/Cell.zig:4-127`, `Cell`/`Style`, and
  `src/Screen.zig:13-69`, caller-allocated `buf`, show that copied visual cells
  and caller storage form a useful low-level boundary. Howl does not adopt its
  application-screen or image architecture.
- TigerBeetle `src/vsr/client_sessions.zig:50-69`, `init`/`deinit`, uses exact
  allocator symmetry and asserts established capacity invariants after checked
  construction. `src/vsr/grid.zig:230-351`, `Grid.init`/`deinit`, checks
  recoverable allocation boundaries while asserting internal ownership facts.
  Howl applies the lesson directly: caller capacity is recoverable; malformed
  typed sibling VT facts are invariant violations, not duplicated hot errors.

## Rejected alternatives

1. **Complete `Visual` plus complete previous `Visual`.** Rejected because one
   cursor or cell change scans/copies the grid and pressures 4K batching.
2. **Have `project` mutate the executable's shared complete backing.** Rejected
   because the projection call would then own runtime synchronization and
   handoff policy. It instead emits immutable patches; the executable applies
   admitted patches in order to its retained complete grid.
3. **Trust VT dirty but acknowledge during projection.** Rejected because a
   declined/saturated runtime admission would lose semantic changes.
4. **Treat typed VT output as hostile.** Rejected because duplicate full-grid
   validation adds hot work and two owners for the same invariants. Render
   asserts sibling contracts; only caller storage/admission failures return.
5. **Consume `Terminal.SurfacePublication`.** Rejected because it couples
   render to title, clipboard, shell, pointer, file, window, DCS, and policy.
6. **Generic callback/iterator adapter.** Rejected because it moves terminal
   visual interpretation into every embedder and adds erased ownership.
7. **Backend draw-command stream now.** Rejected because glyph placement,
   masks, pixel overdamage, batching, and textures require later text/backend
   evidence and would settle unapproved APIs.

## Implementation gate

No evidence blocker remains for this work unit. Approval permits the next slice
to add the narrow VT `VisualView`/`VisualDirty`/`DirtyToken` contract, make VT
dirty cumulative for cell, selection-span, row-geometry, and source-wide visual
changes, add the direct render namespace and delta projection, and prove sparse
cursor-overlay derivation, admission/ack rollback, full recovery, exact bounds,
and no borrowed VT data after return.

It does not approve runtime slots, queues, locks, generations, thread topology,
GPU commands, concrete backend behavior, or graphics capability.

## Validation receipt

- [x] One cursor or dirty cell does not scan/copy the complete grid.
- [x] Typed VT invariants have one owner and no duplicate recoverable errors.
- [x] Projection-baseline metadata is bounded and contains no complete visual
  state.
- [x] Declined updates preserve baseline and cumulative VT dirty facts.
- [x] Admitted updates are immutable caller storage with no VT borrow.
- [x] Full reconstruction is explicit and independent of skipped projections.
- [x] Render owns no runtime publication, synchronization, or GPU resource.
