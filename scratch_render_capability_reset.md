# Render capability reset scratchpad

Current slice: `classify_terminal_visual_values`

Scope: inventory only. Source and public API remain unchanged. Dispositions are
`retain_render`, `executable_evidence`, `delete`, or `discussion`; they classify
current evidence and do not approve a replacement API.

## Baseline

- Source: `howl-render/src/howl_frame.zig`, 1,083 lines, 44,111 UTF-8 bytes.
- Imports: `std` and `howl_vt`; the file is not selected by the accepted
  `howl_render` roots or current child build.
- Direct import sites outside the file: stale control and host build graphs,
  control, unselected render preparation, host renderer, and host measurement
  evidence. No accepted current render root imports it; that current-tree fact
  does not negate render's settled public embeddable role.
- Allocation: seven allocations per storage set: one pending-damage array plus
  two slots, each with cells, line geometry, and damage. Prepared resize owns a
  second complete seven-allocation set until commit or rollback.
- Synchronization: one retained `std.Io.Mutex`, one retained `std.Io`, seven
  `lockUncancelable`/unlock pairs; no atomics.
- Bounds: `max_combining = 3`, `slot_count = 2`, nonzero `u16` rows/columns,
  checked `usize` cell-count multiplication, monotonic non-reused `u64`
  publication identity.

## Exact source partition

These non-overlapping ranges cover every source byte exactly once.

| Range | Bytes | Symbols/family | Disposition |
|---|---:|---|---|
| 1-5 | 139 | file contract; `std`, `howl_vt` imports | discussion |
| 6-10 | 223 | `max_combining`, `slot_count` | split below |
| 11-170 | 6,042 | visual value declarations | split below |
| 171-196 | 851 | initialization, resize, publish, release errors/results | split below |
| 197-221 | 696 | `SlotState`, `Slot` | executable_evidence |
| 222-248 | 934 | `PreparedResize`, `commit`, `deinit` | executable_evidence |
| 249-264 | 621 | `Borrow`, `Borrow.release` | executable_evidence |
| 265-445 | 7,005 | `Publisher` state and public lifecycle; `writableSlot` | executable_evidence |
| 446-470 | 937 | `commitResize`, `cancelResize` | executable_evidence |
| 471-513 | 2,083 | `validateSurface` | discussion |
| 514-538 | 925 | `accumulateDamage` | executable_evidence |
| 539-633 | 4,426 | `copyFrame` and `Publisher` close | discussion |
| 634-658 | 999 | `frameFromSlot` | executable_evidence |
| 659-710 | 1,686 | `deinitSlot`, `Storage`, storage construction/cleanup | executable_evidence |
| 711-717 | 185 | `expectPublished` test helper | delete |
| 718-754 | 1,977 | complete visual reconstruction test | discussion |
| 755-836 | 4,134 | cumulative and sparse-damage tests | split below |
| 837-895 | 2,335 | ready replacement and invalid-publication tests | split below |
| 896-970 | 3,414 | saturation, release identity, generation-exhaustion tests | executable_evidence |
| 971-1004 | 1,144 | storage bounds/allocation and source-validation test | split below |
| 1005-1072 | 2,948 | resize reservation/allocation/commit tests | executable_evidence |
| 1073-1083 | 407 | allocation-failure test helpers | delete |

## Symbol-family inventory

### Imports and constants

| Range | Symbols | Current purpose/consumers | Ownership and disposition | Independent evidence |
|---|---|---|---|---|
| 1-5 | file contract, `std`, `howl_vt` | `std` supplies allocator, IO mutex, checked math, memory operations, and tests. `howl_vt` supplies semantic surface and value types. | `discussion`: retained imports depend on the approved transformation and value types. The current file contract falsely combines visual facts with acknowledgement. | A transformation must validate scalar bounds and resolve semantic colors; no dependency direction is approved. |
| 6-7 | `max_combining` | Sizes `Cell.combining`; old renderer derives its shaped-codepoint bound from it. | `retain_render`: fixed visual-cell storage needs an explicit bound. The exact value is proven by current VT source but the replacement public placement is undecided. | Reject over-bound clusters before destination mutation. |
| 8-10 | `slot_count` | Fixes every slot/storage array and the two-borrow saturation policy. | `executable_evidence`: this is publication scheduling, not visual knowledge. | At most one consumed frame plus one newer frame was the old policy; that policy is not accepted merely because it is bounded. |

### Plain and mixed values

| Range | Symbols | Current purpose/consumers | Ownership/lifetime | Disposition and proof worth preserving |
|---|---|---|---|---|
| 13-14 | `Baseline` | Cell baseline consumed by old render shaping. | Copied value; no allocation or cleanup. | `retain_render`: normal, raised, and lowered placement is visual meaning. |
| 16-62 | `Cell` | Old render consumes every cluster/rendition field; host draw consumes codepoint, multicell placement, visibility, and resolved colors; host labels manufacture the same type. | Inline copied value. It currently embeds VT `Rgb` and `UnderlineStyle`, so the concrete dependency is unapproved. | `retain_render`: bounded cluster, multicell geometry, resolved colors, font/baseline, rendition, underline, and link identity are visual facts. Preserve exact color reversal/resolution and bounded cluster validation, not the current type identity. |
| 64-70 | `LineGeometry` | Old render validates one value per row; no current host draw uses it. | Inline copied value. | `retain_render`: DEC row geometry affects terminal visual interpretation even though current drawing is incomplete. Preserve exact one-row association. |
| 72-78 | `CellPixelSize` | Control aliases it; VT receives it; old render validates it; host dimensions are derived independently. | Inline value; nonzero is checked by publisher. | `discussion`: pixel cell size crosses VT, rendering, and executable layout. Current duplicate type and public owner are not justified. Preserve nonzero validation if the selected boundary carries it. |
| 80-96 | `Cursor` | Host draw uses row/col, visibility, shape, and resolved colors; old render validates position. | Inline copied value; shape and RGB currently use VT types. | `retain_render`: cursor presentation is visual knowledge. Preserve position validation and explicit resolved foreground/background behavior; timer policy is not retained. |
| 98-114 | `SelectionPoint`, `Selection` | `copyFrame` and the reconstruction test consume them; old render and host do not yet draw selection. Operator-approved scope requires primary-screen scrollback selection/copy. | Inline copied values borrowing no memory. VT owns selection semantics, render owns selection appearance, and the executable owns gesture and clipboard policy. | `discussion`: the duplicate types do not survive automatically, but selection's visual responsibility and semantic-to-visual evidence must survive. Exact visual values and ownership transfer belong to the VT/render API gate. |
| 116-132 | `RowDamage`, `Damage` | Old render limits row/cell preparation; host measurement counts rows; host renderer forces complete redraw. | `Damage.rows` borrows publisher slot storage until release. Cumulative lifetime is acknowledgement-defined. | `executable_evidence`: VT owns dirty facts; accumulation across skipped work and redraw continuity are executable scheduling. Preserve the observed need for full-redraw fallback and bounded row spans, not these public nouns. |
| 134-170 | `TerminalFrame` | Old render uses generation, dimensions, cells, row geometry, cursor, cell pixels, and damage. Host draw uses dimensions/cells/cursor. Current drawing omits selection, history base/count, alternate flag, scroll offset, and mouse mode. | Borrows slot cells/geometry/damage until exact `Borrow.release`; scalar fields copy VT and runtime facts. | `discussion`: the type cannot survive intact. Rows/columns/cells/row geometry/cursor and selection appearance are visual evidence; generation and damage are executable evidence; history/mouse remain VT or executable policy. Preserve complete reconstruction, not this aggregate or borrowed lifetime. |

### Errors and runtime state

| Range | Symbols | Current behavior | Ownership/cleanup | Disposition |
|---|---|---|---|---|
| 171-176 | `InitError`, `PrepareResizeError` | Report allocation/bounds and active-borrow resize rejection. | Coupled to allocated publication storage. | `executable_evidence`; replacement errors depend on executable storage policy. |
| 177-186 | `PublishError` | Validates source/grid/cursor/damage/selection/cell pixels plus runtime generation exhaustion. Control translates it into reader/resize errors. | No retained resource. | `discussion`: source validation failure is worth preserving transactionally; `GenerationExhausted` and control translation are rejected runtime coupling. Do not retain this mixed error set. |
| 188-192 | `PublishResult` | Returns generation or two-slot saturation. | Runtime admission result. | `executable_evidence`. |
| 194-195 | `ReleaseError` | Distinguishes stale and non-borrowed generation. | Runtime acknowledgement result. | `executable_evidence`. |
| 197-221 | `SlotState`, `Slot` | Stores two complete copies, visual scalars, generations, state, and redraw facts. | Each slot owns three allocations; bytes are immutable only while state is borrowed. | `executable_evidence`; the visual fields are already accounted for by their value families. |
| 222-248 | `PreparedResize`, `commit`, `deinit` | Reserves publisher, owns replacement storage, atomically installs or frees it. | Owns seven replacement allocations; `commit` transfers, `deinit` cancels and frees. | `executable_evidence`; preserve rollback discipline if a future runtime owner chooses allocated publication. |
| 249-264 | `Borrow`, `Borrow.release` | Couples immutable frame slices to publisher identity and reports pending recovery. | Holds publisher pointer; release invalidates itself, no allocation. | `executable_evidence`; renderer acknowledgement is explicitly rejected from render. |
| 265-445 | `Publisher`, `init`, `deinit`, `prepareResize`, `publish`, `borrowNewest`, `newestGeneration`, `release`, `writableSlot` | Control owns it; host consumes through control; measurement uses it directly. Manages two slots, newest replacement, saturation, damage retirement, generation, and resize reservation. | Retains allocator, IO, mutex, seven allocations and all runtime state. `deinit` requires no borrow/resize and frees in reverse order. | `executable_evidence`; all publication, queueing, synchronization, generation, saturation, and acknowledgement policy belongs to the executable. Preserve only generic evidence for bounded nonblocking saturation, immutable consumed bytes, exact cleanup, and validation-before-mutation. |
| 446-470 | `commitResize`, `cancelResize` | Swap/free replacement storage or revoke reservation under mutex. | Same executable-owned storage and lock lifetime. | `executable_evidence`; preserve atomic rollback behavior only if selected runtime storage needs it. |

### Transformation, damage, projection, and storage

| Range | Symbols | Current behavior | Ownership/lifetime | Disposition and independent evidence |
|---|---|---|---|---|
| 471-513 | `validateSurface` | Checks destination capacity, cursor, optional pixel size, selection columns, dirty spans/sentinel, Unicode scalar range, and combining bound before locking or mutation. Walks the complete source grid. | Borrows `Terminal.SurfacePublication`; allocates nothing. Capacity comes from `Publisher`. | `discussion`: validation-before-mutation is required, but exact checks/output errors depend on the transformation contract. |
| 514-538 | `accumulateDamage` | Merges VT row spans by min/max unless full redraw is already pending; ignores clean sentinel rows. | Mutates retained publisher damage until latest release. | `executable_evidence`: accumulation/retirement is publication policy. Preserve sparse sentinel handling as VT-to-runtime evidence. |
| 539-633 | `copyFrame` | Walks every visible row/cell; maps line geometry; resolves palette/default colors; applies screen/cell reverse; copies clusters, rendition, cursor, selection, history, mouse, damage, and identities into a slot. | Borrows VT surface only during call; mutates caller-selected slot; allocates and locks nothing itself. | `discussion`: render's semantic-to-visual responsibility is settled, but runtime identities, history/mouse copying, slot destination, and damage are not one coherent transformation. Exact API, I/O, dependency, allocation, and lifetime require the supervised gate. |
| 634-658 | `frameFromSlot` | Exposes initialized prefixes as borrowed `TerminalFrame` slices. | Lifetime ends at exact release; no allocation. | `executable_evidence`: projection exists only for the rejected slot/borrow API. |
| 659-663 | `deinitSlot` | Frees damage, geometry, then cells. | Caller allocator must match construction allocator. | `executable_evidence`; reverse cleanup discipline is worth preserving, not the helper. |
| 665-668 | `Storage` | Bundles pending damage and two slots for transactional construction. | Owns seven allocations after successful return. | `executable_evidence`. |
| 670-687 | `initStorage` | Checks row×column multiplication, allocates pending damage, constructs two slots, and rolls back initialized prefixes. | Explicit caller allocator; transfers seven allocations on success. | `executable_evidence`; preserve checked sizing and complete allocation rollback if future runtime storage is allocated. |
| 689-696 | `deinitStorage` | Frees both slots then pending damage. | Exact owner cleanup. | `executable_evidence`. |
| 698-708 | `initSlot` | Allocates cells, geometry, damage with staged `errdefer`. | Explicit caller allocator; transfers three allocations. | `executable_evidence`. |

## Tests and proof disposition

| Range | Test/helper | Current proof | Disposition; behavior worth preserving |
|---|---|---|---|
| 711-717 | `expectPublished` | Converts old publish result for tests. | `delete`; API-only helper. |
| 718-754 | `complete immutable frame reconstructs VT visual truth` | Exact cells, italic, row geometry, selection, dimensions, pixel size, and three generations after VT feed. | `discussion`; preserve a dense semantic-to-visual transcript for cell/color/cursor/geometry and selection appearance. Drop publication identity; reshape selection assertions only after its visual contract is approved. |
| 755-800 | `skipped publications retain cumulative damage until newest release` | Damage unions across unread generations and retires after latest release. | `executable_evidence`; this proves rejected acknowledgement policy, not render behavior. |
| 802-836 | `alternate-screen sparse dirty rows publish without inventing middle damage` | Clean middle sentinel remains clean while outer dirty range spans rows. | `discussion`; preserve exact sparse VT dirty interpretation if the selected transformation/runtime boundary consumes it. Drop borrow/ack ceremony. |
| 837-864 | `new publication replaces only the unread ready generation` | Newest complete slot replaces unread ready state and stale release rejects prior identity. | `executable_evidence`; no render-independent proof. |
| 866-895 | `invalid publication cannot mutate retained frame or pending damage` | Invalid pixel size leaves generation, borrowed bytes, full flag, and pending damage unchanged. | `discussion`; preserve validation-before-mutation for the selected transformation. Runtime fields are not retained. |
| 896-930 | `two borrowed slots saturate without consuming identity or damage` | Two borrowed slots saturate without consuming generation/damage; release permits recovery. | `executable_evidence`; current capacity and recovery policy are not accepted. |
| 932-947 | `release rejects stale double and unborrowed generations` | Exact acknowledgement errors. | `executable_evidence`; current API-only proof. |
| 949-970 | `generation exhaustion preserves the last complete publication` | `u64` identity never wraps and prior frame survives. | `executable_evidence`; preserve non-reused identity only if the future executable uses identities. |
| 971-1003 | `publisher validates bounds and rolls back every allocation` | Rejects zero/capacity/pixel bounds and proves all seven init allocation failures clean. | Split: storage proof is `executable_evidence`; source-bound validation is `discussion`. Preserve checked arithmetic, rollback, and validation before output mutation under whatever owners are selected. |
| 1005-1022 | `resize preparation rejects borrowed storage without mutation` | Active borrow prevents storage replacement without mutation. | `executable_evidence`; current runtime policy only. |
| 1024-1044 | `resize allocation failure preserves ready storage and borrowing` | Failed replacement allocation leaves old ready storage borrowable. | `executable_evidence`; transactional replacement behavior may inform future executable storage. |
| 1046-1063 | `resize commit replaces storage at exact geometry in both directions` | Exact replacement capacities in both directions. | `executable_evidence`; current storage API only. |
| 1065-1071 | `resize preparation rolls back every partial allocation` | Every replacement-allocation failure cleans up. | `executable_evidence`; preserve rollback discipline if future executable allocates replacement storage. |
| 1073-1083 | `initPublisher`, `preparePublisherResize` | Allocation-failure harness entry points. | `delete`; helpers exist only for rejected storage API. |

## Real consumer inventory

| Consumer | Exact uses | Classification consequence |
|---|---|---|
| `howl-control/build.zig(.zon)` | Declares deleted standalone frame dependency and injects `howl_frame`. | Delete coupling; build evidence is quarantined. |
| `howl-control/src/howl_control.zig` lines 5, 54-60, 108, 123, 235, 272, 304-305, 373, 387, 419, 581-606, 766, 802-803, 825, 846-887, 940, 1339-1361 | Re-exports pixel/frame/error types; owns publisher; couples initialization, reader publication, viewport, resize, borrow/release, recovery, wake, and error translation. | Confirms all runtime publication currently sits in forbidden control ownership; it does not prove the API should survive. |
| control inline tests 1522-1718 | Saturation recovery, viewport, alternate sparse damage, cell pixels, publication failure, resize rollback. | Preserve terminal behavior proofs separately; publication-specific assertions are executable evidence. |
| `howl-control/src/test.zig` 126-153, 437-590 | Live child visual copy plus resize/borrow/allocation/cancellation coupling. | Preserve PTY/VT lifecycle and geometry behavior; rejected borrow/storage API does not survive. |
| `howl-render/src/howl_render.zig` lines 4, 42, 103, 306-565 | Uses `Cell`, `TerminalFrame`, `RowDamage`, `LineGeometry`, pixel size, cursor, damage, and generation for shaping/cache preparation and validation. It never uses Publisher/Slot/Borrow/PreparedResize. | Strong evidence for visual cell/cursor/grid facts. This unselected source does not define the exact public API; render's public embeddable role is already settled. |
| old render tests 631-1007 | Shared cache, glyph borrowing, presentation cells, damage/generation validation, ownership transfer, OOM and raster cleanup. | Classify in the later render-code slice; only their frame fixtures consume current values. |
| `howl-host/src/renderer.zig` lines 5, 321, 367, 488-535, 843, 979-1007 | Borrows via control, walks cells/cursor for drawing, releases via control, and manufactures terminal cells for labels. | Visual draw use is executable evidence. Label reuse shows accidental coupling, not a terminal-cell API requirement. |
| host renderer tests 1279-1585 | Mailbox/coalescing/failure/release/composition behavior. | Executable evidence; not frame-value API proof. |
| `howl-host/build/probe_scenario.zig` lines 4, 84, 154-192 | Direct Publisher lifecycle, dirty counting, old render preparation, release timing. | Delete with rejected measurement machinery; no architectural authority. |
| stale host build graph | Declares and injects deleted standalone frame module. | Delete coupling. |

No other maintained Zig/build consumer imports `howl_frame`. VT tests mentioning
`LineGeometry` or cell pixels use VT-owned types and are not frame consumers.

## Supervised VT/render boundary gate

Evidence established:

- `Terminal.SurfacePublication` is borrowed until VT mutation; cross-thread or
  delayed consumption therefore requires an owner-selected copy or stronger
  synchronization outside control.
- Semantic-to-visual work currently includes bounded cluster conversion, DEC
  row geometry, palette/default/underline/cursor color resolution, reverse
  interaction, cursor and selection presentation, and scalar validation.
- Current render preparation needs dimensions, cells, cursor, and dirty/full
  facts; current host drawing needs dimensions, cells, and cursor. Neither
  drawing consumer uses selection, history metadata, alternate-screen identity,
  scrollback offset, or mouse mode. Selection is an implementation gap, not an
  absent requirement: operator-approved daily scope includes primary-screen
  scrollback selection/copy and render owns its appearance.
- Current destination copy is allocation-free only because Publisher owns
  preallocated slot arrays. Initial and resize storage use an explicit caller
  allocator and exact rollback.
- A public embeddable render capability is settled. It hides terminal visual
  semantics from embedders that know their graphics backend but should not need
  terminal-state-machine internals. Quarantined current consumers are evidence
  for exact values and behavior, not the sole authority for capability scope.

Questions requiring operator approval before implementation:

1. Transformation placement: render owns semantic-to-visual interpretation;
   which selected render namespace and operation express it without importing
   runtime policy?
2. Input: borrowed VT publication, narrower semantic view, or another already
   earned concrete type?
3. Output: which exact visual values are required, and are dirty/full facts part
   of that output or executable publication state?
4. Dependency direction: may render depend directly on VT, or must a caller
   provide already-decoupled semantic facts?
5. Allocation/lifetime: caller-provided destination storage, one explicitly
   allocated owned copy, or another proven lifetime? Which owner frees it?
6. Public API: which exact operation and backend-neutral output vocabulary earn
   exposure from the already-settled embeddable render capability?

Gate: render's public role and transformation responsibility are settled. The
exact API, input/output types, direct VT dependency shape, caller-provided
allocator and storage lifetime, dirty/damage split, and backend command
vocabulary remain unsettled. Those decisions block implementation of the
replacement boundary only; the symbol inventory is complete.

## Validation

- Every line and UTF-8 byte in `howl_frame.zig` is covered once by the source
  partition.
- Every declaration, method, helper, allocation, lock, import, and test belongs
  to exactly one family above.
- Visual semantics are separated from runtime publication and acknowledgement.
- No transformation API, executable topology, or storage policy is selected.
