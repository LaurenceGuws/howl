# Render capability reset scratchpad

Current slice: `classify_remaining_render_code`

Render's stateless terminal projection was accepted at `269a8c1`. This slice
changes no product behavior. It accounts for every remaining symbol and proof
in the old renderer/cache/draw-preparation source after extracted visual values
were deleted, then recommends deletion, retention evidence, or a separately
owned rebuild without preserving compilation compatibility.

## Current classification checklist

- inventory every remaining declaration and test in `howl_frame.zig` and
  `howl_render.zig` by exact line range;
- classify runtime publication, synchronization, resize, cache, text
  preparation, grid/effect, damage, and draw-preparation semantics separately;
- identify all consumers and build edges without treating them as authority;
- compare earned behavior against native text/generated glyph capabilities and
  the accepted stateless terminal projection;
- cite Foot, TigerBeetle, and relevant terminal-renderer evidence only where it
  resolves ownership or source shape;
- recommend deletion by default; retained behavior must name its exact owner,
  invariant, proof, and reason it cannot be rebuilt more directly;
- do not edit product source or make quarantined files compile.

## Accepted render projection checkpoint

VT's visual observation contract was accepted at `f9be93f`. This slice now
implements only render's stateless projection into caller-provided buffers.
Executable admission/storage, retained-grid ownership, text shaping,
rasterization, GPU commands, control, and compatibility adapters remain out of
scope.

## Current implementation checklist

- add the direct selected `howl-render` dependency on `howl-vt` without making
  unrelated text/generated selections compile VT;
- replace retained visual values from the rejected frame source with the
  accepted terminal projection vocabulary;
- preflight exact cell and row-patch counts before writing either caller buffer;
- project full and sparse viewport rows, resolved colors, selection appearance,
  line geometry, and old/new cursor overlay damage;
- return only `FullRequired`, `InsufficientCells`, or `InsufficientPatches`;
- prove short buffers remain byte-for-byte unchanged and projection allocates
  nothing;
- prove one-cell, cursor-only, mixed scrollback, geometry, selection, full,
  and baseline-discontinuity cases;
- run render owner checks for every selected capability combination and the VT
  owner checks affected by the direct dependency.

## Accepted VT checkpoint

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
- `r` dirty rows containing `c` visual cells cost O(r + c);
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
- cells contain valid Unicode scalars and bounded combining data;
- visual cells are currently 1x1 with zero cluster offsets; render asserts this
  sibling invariant until VT deliberately earns broader cell geometry;
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
  resolved foreground, background, and underline `Rgb`; `font: u4`;
  `CellBaseline`; bold, dim, italic,
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
`damage_start...damage_end` is the inclusive union of the exact VT dirty span
and old/new cursor cells. Geometry is the current value for that row and can be applied
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

## `vt_visual_view_contract` implementation findings

Implemented VT ownership is narrower than the rejected surface publication:

- Screen dirty storage: `terminal.zig:2870-2934`, `markDirtyCols`,
  `markDirtyRows`, `markAllRowsDirty`, and `:3501`, `DirtyState`, own
  caller-allocated cumulative spans and their private mutation revision.
- Borrowed source: `terminal.zig:9244`, `View`, `:9317`, `VisualSource`, and
  `:9420`, `projectVisualSource`, own viewport cells, geometry, and selection.
- Byte boundary: `terminal.zig:11999`, `TerminalStream.nextSliceSummary`, and
  `:12919`, `completeStreamMutation`, close successful and partial-error work.
- Visual identity: `terminal.zig:12636-12667`, `DirtyToken`, `VisualDirty`, and
  `VisualView`, plus `:12863-12908`, own sparse/full and cursor comparison.
- Public observation: `terminal.zig:13621`, `ackVisual`, and `:13714`,
  `visualView`, own allocation-free borrowing and cumulative retirement.
- Selection appearance: `terminal.zig:14222-14239`, `noteSelectionChanged` and
  `markSelectionAppearance`, union old and new visible selected spans.

- `Terminal.visualView` allocates nothing and borrows visible cells, row
  geometry, selection, palette, and dirty spans only until terminal mutation.
  Its copied `DirtyToken` identifies that exact observation.
- `VisualDirty` is `none`, dense cumulative row spans, or `full`. Existing
  caller-allocated screen dirty-column arrays remain the sole span storage;
  resize allocates replacement arrays transactionally through the terminal's
  caller-provided allocator.
- `ackVisual` accepts only the current unacknowledged token. It retires active
  spans and `full`; stale and repeated acknowledgement leave state unchanged.
- Cell and geometry paths converge on `markDirtyCols`, `markDirtyRows`, or
  `markAllRowsDirty`. A private revision records mutation even when a new span
  is already contained by cumulative unacknowledged bounds.
- Cursor position, visibility, shape, blink intent, and cursor-specific colors
  are compared as a copied overlay. Hidden cursor details are canonicalized so
  invisible movement does not create visual work. Cursor changes never mark VT
  cell spans.
- Direct selection operations union only old and new visible selected spans.
  Selection invalidation during byte application and screen-bank changes use
  full reconstruction because the former projection may no longer be
  addressable after mutation. Finishing selection changes gesture state but
  not visual dirtiness.
- Resize, viewport/source mapping, alternate-bank identity, row-origin shifts,
  reverse-screen changes, and palette/default-color mutation produce `full`.
  Failed resize and failed color transactions leave visual identity unchanged.
- `TerminalStream.next`, `nextSlice`, and `nextSliceSummary` now close the same
  visual mutation boundary as `Terminal.feed`, including a partially applied
  slice that later returns an error. No borrowed view survives that boundary.
- `hardReset`, `restoreCursor`, `switchScreenMode`, `applyModeEvent`, resize,
  viewport movement, and selection APIs account for direct callers rather than
  relying on a later feed wrapper.
- The old aggregate is now `StateSnapshot` and contains retained consequences
  and input-policy facts only. `SurfacePublication`, `surfaceSnapshot`,
  `ackSurface`, publication slots/sequences, and visual fields in that aggregate
  were deleted rather than aliased.

Owner-local proof covers initial full state, sparse cumulative cells, cursor-only
token movement with clean cell spans, stale/repeated acknowledgement, exact
selection add/remove spans, full row geometry, palette and resize full recovery,
and fragmented stream accumulation.

Pedantic correction tightened three owner boundaries:

- `VisualView` no longer exports raw selection endpoints. `selectedSpan(row)`
  resolves the half-open selected columns inside VT for the borrowed viewport,
  including retained-history and mixed history/screen rows.
- `VisualDirty.rows` rebases borrowed active-screen spans into visible viewport
  coordinates. Its iterator skips history rows and offscreen active rows while
  preserving sparse cumulative screen dirtiness. Selection appearance on a
  retained-history row requests full reconstruction because screen-owned dirty
  arrays cannot name that row; it is never misreported as an active-screen row.
- Dirty revisions, visual identity, and source-wide revision use checked
  monotonic increment. Exhausting `u64` is an explicit invariant panic, so an
  ancient `DirtyToken` can never become current through modulo reuse.
- `visibleCellHyperlinkUri` treats a token as current visual identity rather
  than acknowledgement ownership: acknowledging the token keeps the borrow
  eligible until the next visual mutation; stale identities are rejected.

Additional proof covers row-resolved selection while moving through retained
history, a two-history/two-screen viewport with one visible and one offscreen
active-screen mutation, and current-versus-stale hyperlink identity.

Validation completed:

- `howl-vt`: `zig build check` in Debug, ReleaseSafe, ReleaseFast, ReleaseSmall.
- `howl-vt`: `zig build test` in Debug and ReleaseSafe.
- `howl-vt`: `zig build simulate`; `zig build fuzz`.
- formatting and `git diff --check` pass for the owned files.

The root workspace check remains blocked before reaching this VT boundary:
`howl-control` still names deleted `howl-frame`, root aliases still name deleted
`howl-text`, `howl-frame`, `howl-window`, and `consumer-vt`, and the source-audit
allowlist still describes those quarantined paths. The rejected
`howl-render/src/howl_frame.zig` and control consumers still name
`SurfacePublication`; changing them belongs to later approved slices.

## `render_delta_projection` implementation findings

`howl-render/src/terminal.zig` now owns the accepted stateless projection:

- `project` borrows one `Terminal.VisualView`, writes only initialized prefixes
  of caller `Buffers`, and retains no VT pointer or slice. It has no allocator,
  deinitializer, lock, queue, publication identity, or backend value. The
  accepted public value parameter is addressed once; every iterator and
  per-row/per-cell helper borrows that one local value by pointer.
- `WorkIterator` performs the same ordered pass for preflight and writing. It
  merges sparse viewport dirty rows with at most two old/new cursor rows; full
  mode alone enumerates every row. Capacity rejection precedes every write.
- One selected span is resolved by VT per affected row, avoiding repeated
  history/selection scans per cell. Cell colors resolve palette, defaults,
  cell reverse, screen reverse, and caller selection appearance before copying
  backend-neutral RGB values.
- The basics-first decision supersedes the earlier multicell projection
  assumption. Render `Cell` contains no cluster geometry and sparse work copies
  the exact VT dirty span. `projectCell` asserts the current sibling invariant
  `width == height == 1` and `x == y == 0`, so a future VT expansion fails
  loudly until its mutation and render contracts are approved together.
- VT retains dormant `ScreenCell.width`, `height`, `x`, and `y` vocabulary.
  Production assigns only their 1x1 defaults; non-default assignments existed
  only in removed synthetic tests. Those fields remain VT classification debt
  and are intentionally neither deleted nor exposed by render in this slice.
- The complete dirty-call audit is explicit: `changeRectAttrs`, combining
  append, and selection appearance preserve cell geometry; `writeCell` marks
  before replacing one cell; `fillRect`, `copyRect`, insert/delete characters
  and columns, left/right shifts, structural clear, erase, and row copy mark
  after destructive mutation. None of those paths creates a non-1x1 cell.
  `markDirtyCols` therefore remains constant work for one cell and constant
  union work for any supplied span; full-row callers do not rescan cells.
- Hidden or `none` cursors canonicalize position, shape, blink, and colors.
  Incremental old/new cursor damage is independent of VT cell dirtiness and
  emits canonical zero-cell row patches. Admitted baseline cursors are a
  programmer contract: visible values are asserted in bounds and hidden values
  are asserted equal to the canonical zero form.
- Incremental geometry or selection-style mismatch and VT `full` dirtiness
  return `FullRequired`. Short row or cell buffers return only
  `InsufficientPatches` or `InsufficientCells`; destination bytes remain exact.

The child build adds `-Dterminal`, default false. Only that branch resolves the
direct sibling `howl-vt` dependency and exposes `howl_render.terminal`; native
text and generated glyph selections remain independent. Eight compile-time
selection combinations are checked. Verbose receipts prove neither,
generated-only, and native-only graphs omit `howl-vt`; terminal-only omits
FreeType and HarfBuzz.

The duplicate `Cell`, baseline, line-geometry, cursor, selection, and cell-pixel
values were deleted from quarantined `howl_frame.zig` rather than aliased. Its
remaining Publisher/Borrow/PreparedResize runtime source now has unresolved
references by design and remains unselected reconstruction evidence until the
approved runtime-deletion slice; no adapter was added.

Proof covers complete reconstruction, RGB/rendition/selection/row geometry,
one-cell and mixed-scrollback sparse work, declined cumulative work, selection
and geometry spans, same-row and cross-row cursor-only updates, a dirty cell
beneath an unchanged cursor, exact untouched capacity failures, and
style/geometry full-recovery requirements.
The projection API contains no allocation boundary. Preflight counts use
geometry-derived assertions and direct bounded addition; buffer alias checking
uses ordered pointer differences. No new `catch unreachable` site remains.

The eight small public roots are deliberate Zig compile-time selection facts,
not placeholder APIs: each root declares exactly one of the eight possible
native/generated/terminal namespace sets. A conditional public declaration
would keep a disabled namespace present, while source-file selection makes the
declaration absent before module analysis. Shared capability implementations
remain single-source imports, so the roots contain no behavior duplication.
Terminal projection defaults enabled alongside native text and generated
glyphs, so plain `zig build check` exercises the complete owner graph. A
text-only consumer must explicitly select `-Dterminal=false`.

Validation completed:

- `howl-render`: all eight `native_text` × `generated_glyphs` × `terminal`
  check combinations; terminal-only tests in Debug and ReleaseSafe; terminal
  compile checks in Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
- `howl-render`: verbose graph receipts confirm lazy VT selection and native
  library exclusion described above.
- `howl-vt`: check in all four optimization modes and tests in Debug and
  ReleaseSafe remain green against the selected sibling dependency.
- formatting and `git diff --check` pass. The workspace root remains blocked
  only by quarantined deleted-package aliases, control's deleted frame edge,
  and the stale source-audit allowlist indexed by the active reset.

## `classify_remaining_render_code` inventory

Baseline: HEAD `65554f4`, after projection commit `269a8c1`. This inventory is
classification only. Neither quarantined file is selected by
`howl-render/build.zig`: current roots import only `native_text`,
`generated_glyphs`, and `terminal_projection`. The stale control and host build
graphs name the deleted sibling package `howl-frame`; they do not create a live
edge to `howl-render/src/howl_frame.zig`. The stale host source names the old
`howl_render.Renderer`, but current curated roots do not expose it. QAgent has
no edge to either file.

### Complete source accounting

| file/range | lines | chars | declarations and disposition |
|---|---:|---:|---|
| `howl_frame.zig:1-4` | 4 | 138 | Module claim and `std`/`howl_vt` imports. Delete with the file. |
| `howl_frame.zig:5-88` | 84 | 3,195 | `slot_count`, `RowDamage`, `Damage`, `TerminalFrame`, and five error/result types. Damage and visual copying are superseded by `terminal.RowPatch`/`Update`; generations, cell pixels, history, mouse facts, and saturation are executable policy. Delete. |
| `howl_frame.zig:89-157` | 69 | 2,252 | `SlotState`, `Slot`, `PreparedResize.commit/deinit`, and `Borrow.release`. Two-slot state, borrowing, acknowledgement, and resize reservation are rejected executable runtime policy. Delete. |
| `howl_frame.zig:158-525` | 368 | 15,375 | `Publisher`, seven public lifecycle methods, and six private publication helpers. Delete: mutex, slot selection, generation, saturation, cumulative retirement, resize transaction, and complete-grid copy are executable runtime state. `validateSurface` duplicates trusted VT validation; `copyFrame` is superseded by terminal projection. |
| `howl_frame.zig:526-603` | 78 | 2,686 | `frameFromSlot`, `deinitSlot`, `Storage`, `initStorage`, `deinitStorage`, and `initSlot`. Seven allocations per storage set (pending damage plus cells/geometry/damage for two slots) and their rollback exist only for rejected publication. Delete. |
| `howl_frame.zig:604-976` | 373 | 16,544 | `expectPublished`, thirteen tests, and two allocation-failure helpers. Delete after the proof classification below. |
| `howl_render.zig:1-5` | 5 | 183 | Module claim and `std`/old frame/text imports. Unselected stale imports; delete with the file. |
| `howl_render.zig:6-103` | 98 | 3,767 | Three bounds, mixed `Error`, `Pane`, `Prepared`, `Glyph`, `CellGlyphs.slice`, and `max_cell_codepoints`. Pane/layout and generation counters are executable policy. Glyph values combine accepted native raster facts with cache identity/lifetime. No type survives directly. |
| `howl_render.zig:104-220` | 117 | 3,974 | `Key`, `Entry`, `Cache` with five methods, and `Candidate`. Mutable retained mask storage, recency, identity, eviction, and byte/count policy belong to an executable runtime owner. Delete current implementation; preserve transactional-cache evidence only. |
| `howl_render.zig:221-517` | 297 | 11,584 | `Renderer`, six public methods, and three private resolvers. It couples accepted `FontSet`, executable generations/panes/cache, per-cell shaping, generated dispatch, replacement policy, and borrowed cache masks. Delete as a unit; rebuild only the text semantics identified below. |
| `howl_render.zig:518-570` | 53 | 2,075 | `glyphFromEntry` and `validatePanes`. The former projects executable cache entries; the latter validates window/layout/frame publication. Delete. |
| `howl_render.zig:571-1023` | 453 | 16,069 | `testFrame`, `testCell`, and eleven tests. Old frame fixtures are dead. Preserve only independently useful behavior evidence listed below. |

The ranges are contiguous and total exactly 976 lines/40,190 characters for
`howl_frame.zig` and 1,023 lines/37,652 characters for `howl_render.zig`.
There are no unclassified source lines.

### Declaration census

`howl_frame.zig` contains 41 named non-test declarations and 13 tests:

- 12 public constants/types: `slot_count`, `RowDamage`, `Damage`,
  `TerminalFrame`, `InitError`, `PrepareResizeError`, `PublishError`,
  `PublishResult`, `ReleaseError`, `PreparedResize`, `Borrow`, `Publisher`;
- 10 public methods: two resize-value methods, one borrow method, and seven
  publisher lifecycle methods;
- 5 private imports/types: `std`, `howl_vt`, `SlotState`, `Slot`, `Storage`;
- 14 private methods/functions: six publisher helpers, six storage/borrow
  helpers, and two allocation-test helpers.

Every declaration above is deletion. Earlier projection work already removed
the plain visual types it referenced, so this unselected file also contains
unresolved `Cell`, `Cursor`, `Selection`, `LineGeometry`, and `CellPixelSize`
names. Lazy non-selection is its only reason for compiling owners to remain
green; it is reconstruction residue, not a partial module.

`howl_render.zig` contains 36 named non-test declarations and 11 tests:

- 9 public constants/types: three bounds, `Error`, `Pane`, `Prepared`, `Glyph`,
  `CellGlyphs`, and `Renderer`;
- 7 public methods: `CellGlyphs.slice` plus six renderer methods;
- 8 private imports/types: three imports, `max_cell_codepoints`, `Key`, `Entry`,
  `Cache`, and `Candidate`;
- 12 private methods/functions: five cache methods, three renderer resolvers,
  `glyphFromEntry`, `validatePanes`, `testFrame`, and `testCell`.

No declaration survives as-is. Fields of each named struct/union are included
in its range and disposition above; anonymous key variants add no independent
owner.

### Frame proof disposition

| test/range | independent evidence | disposition |
|---|---|---|
| `611-647` complete reconstruction | VT-to-RGB/style/geometry copying | Superseded by `terminal_test` full projection; delete. |
| `648-694` skipped cumulative damage | decline must not lose dirty facts | Superseded by VT cumulative dirty plus exact acknowledgement; delete. |
| `695-729` sparse alternate screen | sparse rows do not invent middle damage | Superseded by viewport-resolved `VisualDirty`; delete. |
| `730-758` unread-ready replacement | mailbox coalescing | Executable policy; delete. |
| `759-788` invalid publication rollback | hostile duplicate validation | Typed VT facts are trusted; destination preflight is proven by projection; delete. |
| `789-824` two-borrow saturation | two-slot backpressure | Executable topology evidence only; delete. |
| `825-841` stale/double release | borrow identity | Executable policy; delete. |
| `842-863` generation exhaustion | non-wrapping runtime identity | Executable policy; delete. |
| `864-897` storage bounds/allocation rollback | seven-allocation cleanup | Storage exists only for rejected publication; delete. |
| `898-916` resize with borrow | resize reservation | Executable policy; delete. |
| `917-938` resize allocation rollback | old storage survives failure | Useful general discipline, but tied only to rejected storage; delete. |
| `939-957` resize grow/shrink commit | slot replacement | Executable policy; delete. |
| `958-976` exhaustive resize allocation failure | reverse cleanup | Tied to rejected storage; delete with helpers. |

### Text/cache/draw-preparation proof disposition

| test/range | behavior worth preserving | future owner/disposition |
|---|---|---|
| `631-668` mirrored frames share masks | identical glyph facts reuse one mask | Executable-owned mask cache proof; rebuild without pane/frame nouns. |
| `669-697` prepared glyph borrows admitted mask | admission takes one allocation and lookup does not allocate | Executable-owned cache lifetime proof; rebuild. |
| `698-731` presentation cells share masks | terminal and nonterminal visual text can share cache identity | Old label/frame API is deleted; the shared-cache claim requires a later executable input contract. |
| `732-758` stale composition generation | generation rejects before cache mutation | Executable scheduling policy; delete. |
| `759-812` capacity/pinning/eviction | fixed count/bytes, current-work pinning, oldest eviction | Executable-owned cache evidence; exact 1,024/8 MiB bounds are not yet accepted. |
| `813-836` no second mask allocation | successful admission consumes exact owned pixels | Executable-owned cache transfer proof; rebuild. |
| `837-857` oversized mask rejection | rejection preserves caller allocation and cache | Executable-owned cache transfer proof; rebuild. |
| `858-908` eviction preflight | impossible admission rejects before eviction | Executable-owned cache transaction proof; rebuild. |
| `909-960` missing glyph replacement | one U+FFFD fallback mask is shared and reusable | `howl-render` text-preparation semantics; rebuild after the gate below. |
| `961-988` generated allocation failure | failed caller allocation leaves cache/generation unchanged | Split proof: render-generated raster owns no allocation; future executable cache owns allocation/admission. Rebuild at those owners. |
| `989-1023` generated raster failure | staged pixels are freed before transfer | Same split; rebuild only if the future composition operation stages owned pixels. |

The current source emits no grid backgrounds, selection/cursor effects,
decorations, quads, draw commands, or backend-neutral paint list. `Prepared`
is counters plus cache warming, not draw preparation. Pane geometry and damage
walking duplicate executable layout and the accepted terminal row-patch
boundary. There is therefore no grid/effects implementation to retain.

### Earned rebuild candidates

Deletion remains the source boundary. These behaviors, not current APIs, earn
later direct reconstruction:

1. **Run-aware terminal text preparation — owner `howl-render`.** Input must be
   borrowed contiguous retained visual cells plus explicit row/run bounds and
   selected native/generated capabilities; isolated dirty cells are
   insufficient for ligature context. Every allocation must receive the
   caller allocator. Output must be backend-neutral positioned glyph/raster
   facts with explicit owned cleanup or caller buffers; it may not carry pane,
   frame generation, cache identity, or GPU facts. Bounds/errors derive from
   accepted `native_text` and `generated` APIs. Preserve U+FFFD fallback,
   generated-glyph dispatch, combining input, pen-offset overflow checks, and
   raster cleanup proofs. A direct rebuild is smaller than untangling
   `Renderer.resolveCell`, which is per-cell and mixes four owners.
2. **Bounded mask reuse — future executable owner.** Input is an exact
   render-produced mask key plus one caller-owned pixel allocation; rejection
   leaves it caller-owned and success consumes that allocation. Output is a
   borrowed mask identity valid under the executable cache lifetime. The owner
   must accept explicit count/byte bounds, allocator/deinit symmetry,
   non-reused identity, eviction/pinning policy, and `CacheFull`/
   `MaskTooLarge`/identity-exhaustion behavior. Current tests establish useful
   transaction evidence, but current 1,024-entry and 8 MiB choices are not
   durable decisions. A rebuild avoids importing pane generations into render.

Accepted `native_text.FontSet`, `Run`, `Raster`, and `generated.rasterize`
already own font construction, shaping, native raster allocation, generated
caller-buffer rasterization, errors, bounds, and cleanup. The old `Renderer`
wrapper duplicates those lifecycles and is not a retained candidate.

### Reference evidence and discussion gate

- Foot `render.c:948-990`, `render_cell`, resolves grapheme or scalar glyphs
  directly at drawing while its font layer owns raster caching. This supports
  retaining semantic dispatch evidence, not Howl's old pane/generation owner.
- Kitty `kitty/fonts.c:1689`, `shape_run`, and `:1904`, `render_run`, shape
  contiguous cell runs and preserve cluster context. This rejects rebuilding
  the old one-cell `resolveCell` as the terminal text boundary.
- TigerBeetle `src/lsm/set_associative_cache.zig:147-210`, `init`/`deinit`, and
  `:298-360`, `upsert`, keep allocation, fixed capacity, eviction, and returned
  ownership in one exact cache owner. The lesson supports rebuilding cache
  transactions at the executable owner, not retaining this mixed renderer.

One genuine supervised gate remains before text preparation is rebuilt: settle
the exact contiguous visual-run input and heterogeneous native/generated
output lifetime across compile-time capability selections. The public role is
already settled (`howl-render` owns semantic-to-visual/text interpretation),
but current evidence does not choose caller buffers versus allocator-owned
prepared output. No executable topology, cache API, or backend command shape
is decided by this inventory.

### Proposed deletion/rebuild boundaries

- Delete `howl-render/src/howl_frame.zig` completely; preserve no alias.
- Delete `howl-render/src/howl_render.zig` completely; preserve no `Renderer`,
  `Pane`, `Prepared`, generation, or cache compatibility surface.
- Rebuild run-aware text preparation only after its input/output lifetime gate.
- Rebuild a mask cache only inside an approved executable owner, using the
  classified transaction proofs rather than copying this file.
