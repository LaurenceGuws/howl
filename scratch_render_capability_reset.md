# Render capability reset scratchpad

Current slice: `settle_run_text_boundary`

The rejected mixed renderer was deleted at `93cb1c6`. This slice is decision
evidence only: derive the smallest contiguous visual-run input and
native/generated output lifetime that lets render prepare perfect terminal text
without owning cache, pane, frame, generation, GPU, or executable policy.

## Current decision checklist

- inventory exact `native_text` run/shape/raster ownership and generated-glyph
  input/output lifetimes;
- derive run boundaries from retained visual cells without moving terminal
  semantics back into the executable;
- compare caller-buffer and explicit-allocator-owned output using concrete
  maximum counts, rollback, and cleanup;
- preserve ligature, combining, fallback, font-slot, baseline, generated-glyph,
  and cell-placement facts needed for Kitty-quality text;
- keep mask cache identity/admission/eviction outside render;
- prove every compile-time capability combination has a direct, absent-when-
  disabled API shape;
- recommend one smallest contract or state the exact unresolved product choice;
- do not edit implementation or build source.

## Run-aware text boundary recommendation

Recommend one stateless `howl_render.terminal_text.prepareNextRun` boundary. It
borrows one complete retained visual row and discovers and prepares exactly one
render-owned homogeneous run containing the supplied iteration cell. One call
returns a tagged native, generated, or no-glyph payload; only the native case
owns a positioned-glyph slice. It does not rasterize masks. A separate
one-glyph raster operation produces an owned alpha mask only after an
executable-owned cache has decided that the glyph is absent.

This boundary is public only when terminal projection and at least one text
source are selected. With native text absent, native preparation/raster entry
points and native variants are absent. With generated glyphs absent, generated
entry points and variants are absent. Existing `text`, `generated`, and
`terminal` namespaces remain independently selectable; no disabled path
returns a placeholder or `UnsupportedCapability` error.

### Exact borrowed input

```zig
pub const RowInput = struct {
    cells: []const terminal.Cell,
    affected_start: u16,
    affected_end: u16,
    geometry: terminal.LineGeometry,
    metrics: CellMetrics,
};

pub const CellMetrics = struct {
    width_px: u16,
    height_px: u16,
    baseline_px: u16,
};
```

- `cells` is the complete nonempty retained visual row after ordered
  `RowPatch` application. Its length is at most `maxInt(u16)` and it remains
  immutable for the call only. Supplying the complete row gives render the
  left/right shaping context needed to expand sparse damage to complete runs;
  no VT borrow crosses this boundary.
- `affected_start...affected_end` is an in-bounds inclusive visual cell span.
  It selects work, not shaping context. The caller starts iteration at
  `affected_start`; render expands only the current run to its complete source
  coverage.
- `geometry` is the retained row geometry. It is necessary for effective
  horizontal cell extent and DEC double-height placement. It is row-local and
  conveys no pane or layout coordinate.
- `metrics` is validated nonzero render text geometry. Width times the
  geometry's horizontal scale and height/baseline transformations use checked
  `u32` intermediates before narrowing. Pane position, window scale, clipping,
  GPU pixel format, and device limits are not inputs.
- Each `terminal.Cell` already supplies base and combining scalars, font slot,
  normal/raised/lowered baseline, bold/italic style, invisibility, selection,
  and final colors. Font slot, bold, italic, baseline, invisibility, and
  generated classification affect run preparation. Selection and colors do
  not split shaping; source-cell coverage lets later render-owned draw
  preparation apply retained per-cell appearance without reshaping. Underline,
  strike, dim, blink, hyperlink, background, and cursor facts are not text-run
  inputs. Cursor ligature policy is not accepted and is not smuggled into this
  boundary.

The executable owns the retained row and chooses which damaged row/span to
prepare. It repeatedly calls `prepareNextRun` with the returned exclusive
`end_cell` until that value is greater than `affected_end`. Render owns
interpretation of the cell fields, run expansion, shaping, fallback, and glyph
placement. The executable never groups Unicode or decides font,
generated-glyph, ligature, combining, blank, or invisible semantics.

### Run splitting and source coverage

`prepareNextRun(input, cell)` requires
`affected_start <= cell <= affected_end`. On the first call, if `cell` lies
inside a run that started before `affected_start`, render scans left to that
run's boundary; later calls begin exactly at the preceding exclusive
`end_cell`. Every result guarantees `first_cell <= cell < end_cell`, so
iteration advances, visits each run intersecting the dirty span exactly once,
and terminates without a caller-side semantic test. Work is linear in the
reported run plus its one-time left-boundary discovery, never the complete
grid.

A native run is a maximal
contiguous row interval with equal `(font slot, bold, italic, CellBaseline)`
and visible textual content. A maximal contiguous blank/invisible interval is
a no-glyph run with exact source coverage; returning it is necessary to clear
previous retained glyph draw state and guarantees iteration cannot stall. A
cell whose base scalar is generated and has no combining scalar is a one-cell
generated run. A generated-range scalar with combining content remains native
text so its complete grapheme is not discarded. Row geometry is constant and
therefore not repeated in the split key.

One cell contributes its nonzero base scalar followed by its initialized
combining scalars. Every scalar receives that cell column as the HarfBuzz
cluster identity. The shaped cluster value maps each output glyph to
`source_start`; the next distinct cluster, or the run end, supplies the
exclusive `source_end`. Decreasing HarfBuzz cluster order is accepted and
coverage is derived from ordered distinct source identities rather than glyph
array order. A ligature may therefore cover many cells and combining glyphs
may share one cell. No pane/layout policy enters that mapping.

Native face fallback remains whole-run, matching current `FontSet.shape`.
`MissingGlyph` retries the same run with U+FFFD once; failure of U+FFFD remains
`MissingGlyph`. Generated classification precedes native shaping only for the
exact generated case above. This preserves deterministic replacement without
inventing mixed-face cluster splicing.

### Output and lifetime

```zig
pub const FontStyle = enum(u2) { normal, bold, italic, bold_italic };

pub const FontKey = packed struct(u6) {
    style: FontStyle,
    slot: u4,
};

pub const GlyphKey = union(enum) {
    native: struct {
        font: FontKey,
        face_index: u8,
        glyph_id: u32,
        cell_span: u16,
    },
    generated: struct { codepoint: u21, width_px: u16, height_px: u16 },
};

pub const PositionedGlyph = struct {
    key: GlyphKey,
    source_start: u16,
    source_end: u16,
    x_26_6: i32,
    y_26_6: i32,
    x_advance_26_6: i32,
    y_advance_26_6: i32,
};

pub const PreparedGlyphs = union(enum) {
    native: struct {
        allocator: std.mem.Allocator,
        values: []PositionedGlyph,
    },
    generated: PositionedGlyph,
    none,
};

pub const PreparedRun = struct {
    first_cell: u16,
    end_cell: u16, // Exclusive.
    glyphs: PreparedGlyphs,
    pub fn deinit(self: *PreparedRun) void;
};
```

Each `PreparedRun` describes exactly one native, generated, or no-glyph run.
A native payload owns exactly one final glyph slice and its explicit caller
allocator. A generated payload stores its one record inline. A no-glyph
payload stores no record. `deinit` switches once: it frees only
`native.values`, performs no cleanup for the other tags, and then invalidates
the complete value. Coverage and iteration remain uniform in outer
`first_cell...end_cell`; a consumer switches only to inspect glyph records.
Any slice borrowed from a native payload, or pointer borrowed from the inline
generated payload, ends before `PreparedRun` is moved or deinitialized.

The tagged payload is earned and is smaller in ownership debt than a uniform
slice: generated and blank runs need no allocator, allocation, synthetic empty
owner, or special zero-length free rule. A union is also clearer than an inline
one-element array plus a separate length because the three cases have distinct
cleanup contracts. Native keys remain valid only while the exact render-owned
font configuration used for preparation remains alive; generated keys have
value lifetime. Coordinates are row-local, relative to the run's first cell
and the supplied baseline. Baseline displacement and row geometry are resolved
into placement here. The output has no colors, pane coordinates,
texture/cache residency identity, generation, frame identity, GPU handle,
backend command, or scheduling fact. `GlyphKey` is render-owned glyph identity
suitable for lookup; it is not a cache slot or admission token.

Native preparation derives each key's nonzero `cell_span` from
`PositionedGlyph.source_end - source_start`. This is the glyph's actual source
coverage: a ligature can span several cells while multiple combining glyphs
can each cover one. Retaining that exact derived span in the key is necessary
after the row borrow ends: native raster fitting and cache equality both depend
on it. It is not the former vague whole-run span.

The native-selected
`rasterizeGlyph(allocator, font_map, key) -> Raster` normalizes both sources to
one allocator-owned tightly packed alpha mask with validated signed placement.
For a native key, render indexes `font_map` with `key.font`, selects
`face_index` inside that exact `FontSet`, and passes the key's exact
`cell_span`; the caller cannot select or substitute a font owner. Generated
keys allocate exactly `width_px * height_px` bytes, call current generated
rasterization, and free on failure. `Raster.deinit` releases exactly once. A
cache caller retains pixels on rejection or transfers them under its own
separately approved contract; render defines no cache count, byte budget,
eviction, pinning, or admission policy.

In a generated-only selection the operation omits the nonexistent `font_map`
parameter and accepts only the generated key variant. The root exposes no
native key constructor, `FontMap`, or native raster branch. This is compile-time
API absence, not a nullable font owner.

Within one mapping-immutable `FontMap`, native key equality is exactly
`(FontKey, face_index, glyph_id, cell_span)`. Font pixel size, fallback order,
and native face identity are fixed by that map entry for its complete lifetime.
The key is therefore collision-safe for a cache scoped to that exact
`FontMap`; keys from different maps are never comparable or admitted to the
same cache without an additional executable-owned map identity. Deinitializing
the map invalidates every native key and requires its scoped masks to have been
retired first. Generated equality is its complete value tuple
`(codepoint, width_px, height_px)` and is independent of a font map.

### Bounds, transaction, and exact failures

- A row has at most `maxInt(u16)` cells. Each cell contributes at most four
  scalars (`terminal.max_combining + 1`). The exact scalar count is preflighted
  with checked `usize`; a native run exceeding `text.max_codepoints` returns
  `TextTooLong` rather than being split across a ligature boundary.
- One native call stages exactly one `text.Run` and therefore produces at most
  `text.max_glyphs` (65,536) final glyph records. One generated run is one cell
  and exactly one inline record. One no-glyph run has zero records. There is no
  aggregate multi-run allocation or aggregate glyph-count claim. Peak native
  record storage is one staged slice of at most 65,536 `text.Glyph` values plus
  one final slice of the same count of `PositionedGlyph` values; shaping occurs
  once.
- Pen accumulation uses checked `i64`; every final 26.6 position and advance
  must fit `i32`, otherwise `InvalidPlacement`. Source coverage is nonempty and
  bounded by the borrowed row.
- Generated width/height are checked nonzero and against
  `generated.max_extent_px`; mask bytes are at most 65,536. Native masks retain
  the current sixteen-MiB bound.
- Run discovery, validation, and scalar counting happen before final output
  allocation. Native preparation stages exactly one existing owned `text.Run`,
  then allocates one final positioned array, fills it, releases the staged run,
  and returns; every error releases both staged and final allocations.
  Generated preparation validates before assigning its inline record.
  No-glyph preparation assigns only coverage. Neither allocates. No partial
  `PreparedRun` escapes.

Preparation's exact error set is the selected native/generated validation and
shaping errors plus `OutOfMemory`, `InvalidSpan`, `InvalidMetrics`, and
`InvalidPlacement`; native selection also adds
`MissingFontConfiguration`. Rasterization exposes the selected source's
current exact raster errors plus `OutOfMemory`; it does not translate them into
a generic render failure. Typed terminal-cell invariants are assertions, as in
accepted projection, rather than hostile-input errors.

Explicit allocator-owned output is preferred over caller buffers here.
HarfBuzz determines one native run's glyph count only after shaping, while
current native shaping already owns that one bounded staged allocation. A
caller-buffer API would need either duplicate shaping or the same hidden
staging allocation and could not preflight capacity exactly. One final owned
slice per native run and inline generated/no-glyph payloads keep rollback and
cleanup visible without an `ArrayList`, reallocation, aggregate multi-run
owner, or duplicate shaping. Masks remain demand-rasterized one at a time, so
this choice does not recreate the deleted renderer's eager mask allocation.

### Source evidence

- `howl-render/src/terminal.zig:47-85,138-170,281-376` supplies retained visual
  cells, row patches, and allocation-free semantic projection; later text may
  inspect retained neighboring cells without VT knowledge.
- `howl-render/src/native_text.zig:99-165,254-370,466-500` already owns bounded
  scalar/cluster shaping, whole-sequence fallback, allocator-owned runs and
  masks, placement validation, and exact cleanup.
- `howl-render/src/generated.zig:9-83` owns exact generated classification and
  transactional caller-buffer alpha rasterization up to 256 by 256 pixels.
- Kitty `kitty/fonts.c:1584-1685,1689-1707,1817-1858,1883-1978` shapes complete
  font-homogeneous runs, derives cell groups from HarfBuzz clusters, handles
  combining and ligatures, and keeps generated/blank/missing handling distinct.
  Howl borrows the run-and-cluster lesson, not Kitty's global scratch, sprite
  cache, Python objects, or GPU-cell mutation.
- Foot `render.c:900-1014` resolves generated, grapheme, fallback, cell-span,
  and glyph-overhang facts directly before pixel composition. Howl borrows
  explicit generated/grapheme separation and bounded source coverage, not
  Foot's terminal-owned render cache or pixman backend.
- TigerBeetle `src/lsm/set_associative_cache.zig:147-219,298-361` demonstrates
  explicit allocator construction/cleanup and separately owned cache
  admission. It supports keeping mask production ownership separate from the
  future executable cache rather than retaining the deleted mixed owner.

### Settled font configuration

Current `native_text.FontSet` (`native_text.zig:180-252`) owns one copied
primary/fallback chain, one FT library, and initialized FT/HB faces using its
explicit construction allocator. It has no terminal slot/style mapping. The
smallest mapping that preserves every projected fact is therefore:

```zig
pub const FontConfig = struct {
    key: FontKey,
    native: text.Config,
};

pub const FontMapInitError = text.InitError || error{
    TooManyConfigurations,
    DuplicateConfiguration,
    MissingDefaultConfiguration,
};

pub const FontMap = struct {
    sets: [16 * 4]?text.FontSet,

    pub fn init(
        allocator: std.mem.Allocator,
        configs: []const FontConfig,
    ) FontMapInitError!FontMap;
    pub fn deinit(self: *FontMap) void;
};
```

`FontMap` is render-owned native-text state. Its 64 fixed optional entries are
indexed by the exact six-bit `FontKey` value (`slot * 4 + style`); it allocates
no map/index storage.
`configs` is bounded to 64 unique tuples and borrows `text.Config` paths only
for construction. `init` first validates the complete tuple set with a fixed
64-bit seen mask, requires slot 0/normal, then transactionally constructs each
present `FontSet` with the caller allocator. A duplicate tuple,
over-capacity input, or missing slot 0/normal fails before native construction.
Any `FontSet.init` failure destroys previously initialized entries in reverse
construction order. `deinit` destroys every present set in reverse index order
and invalidates the map. No global state or executable lifetime is retained.

The direct fixed map deliberately does not alias or reference-count identical
configs: assigning the same paths to several tuples constructs independent
`FontSet` owners. The cost is explicit and bounded by 64 sets; the ordinary
four-style slot-zero configuration constructs four. Sharing native owners
would add a second identity/lifetime system and is deferred unless measured
memory evidence earns it.

Run discovery derives `FontStyle` directly from each cell's bold/italic bits
and uses the exact projected `font` slot. Lookup never silently falls back to
slot 0, normal, or another style. An unconfigured requested tuple returns the
preparation error `MissingFontConfiguration` before shaping or output
allocation. Callers that want the same files for several tuples list those
mappings explicitly; the
executable supplies configuration data but never interprets a run or chooses a
font during preparation. Once selected, that entry's existing ordered native
face fallback handles Unicode coverage, and U+FFFD retry uses the same entry.

`FontMap` and native `prepareNextRun`/raster variants exist only when native
text is selected. A generated-only terminal-text graph has neither the type nor
the parameter. Native `PreparedRun` keys remain valid until that `FontMap` is
deinitialized. This settles the only prior product choice without introducing
cache, runtime, or backend ownership.

### Correction self-review

- One call now discovers and prepares exactly one homogeneous run. No wording
  claims one allocation can contain alternating or multiple native/generated
  runs.
- Native preparation has exactly one staged `text.Run`, one final allocation,
  and the existing 65,536-glyph maximum. Generated and no-glyph runs contain
  exactly one and zero records respectively.
- The exclusive coverage invariant advances across native, generated, blank,
  and invisible intervals, so dirty-span iteration visits every intersecting
  run once and cannot stall.
- Native `GlyphKey` contains the exact six-bit map key, face, glyph, and
  per-glyph span required for map-scoped raster/cache equality. The span is
  derived from exact source coverage rather than copied from the complete run.
- `PreparedGlyphs` owns native slices, stores generated records inline, and
  represents no-glyph coverage without allocation; its tag is earned by three
  distinct cleanup contracts.
- `FontMap` preserves all 16 slots and four bold/italic styles with exact
  lookup, fixed bounds, transactional construction, reverse cleanup, and an
  explicit missing-entry error. No product decision remains in this boundary.
- Caller buffers, `ArrayList`, duplicate shaping, multi-run aggregation, and
  cache/runtime ownership are absent.

## Accepted renderer deletion checkpoint

The remaining legacy render source was completely classified at `37f59ff`.
This slice deletes only the mixed `howl_render.zig` implementation, its dead
proofs, and exact stale references. Run-aware text preparation is not rebuilt
until its input/output lifetime gate; `howl_frame.zig` remains for the later
runtime/control-coupling deletion slice.

## Current deletion checklist

- delete `howl-render/src/howl_render.zig` without alias, stub, or replacement;
- remove only references whose sole target is that deleted source;
- keep accepted `native_text`, `generated`, and `terminal` capability roots and
  proofs unchanged;
- preserve classified lessons in this scratch until promoted or superseded;
- prove all eight selected capability graphs remain green;
- do not touch control, executable runtime, cache reconstruction, or the
  quarantined frame publication source.

## Rejected renderer deletion result

`howl-render/src/howl_render.zig` was deleted in full: 1,023 source lines,
37,652 characters, 36 named non-test declarations, and 11 dead proof families.
No alias, stub, replacement root, or compatibility surface was added. The
selected `native_text`, `generated`, and `terminal` implementation and proof
files were unchanged.

The deleted file had no selected `howl-render` build edge. Its sole permanent
source-map entry and the two durable reconstruction bullets that said its
classification remained pending were removed. Historical inventory references
below deliberately retain the deleted path and `Renderer` noun as classified
deletion evidence. The quarantined executable evidence still contains direct
calls to the removed `howl_render.Renderer`; those are rejected runtime source,
not a render build edge or compatibility obligation, and this slice does not
rewrite executable policy.

Validation from `howl-render`:

- all eight `terminal` x `native_text` x `generated_glyphs` selections passed
  `zig build check`;
- plain defaults passed `zig build check` and `zig build test`;
- `zig fmt --check build.zig src/*.zig` passed;
- repository tracked documentation/build search has no current
  `howl_render.zig` or `Renderer` path claim outside this explicitly historical
  scratch inventory; and
- `git diff --check` passed with no product capability file changed besides
  deletion of the rejected source.

The optional repository source audit remains independently blocked: its stable
allowlist names deleted `howl-window` and `howl-text` paths while the currently
quarantined sources are under `howl-host` and `howl-render`. Correcting that
workspace-wide reconstruction residue is outside this deletion slice.

## Accepted remaining-source classification

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
