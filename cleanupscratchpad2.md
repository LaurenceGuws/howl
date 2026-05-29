Paths read
Mandatory/project:
- /home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md
- /home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md
- /home/home/personal/projects/howl/AGENTS.md
- /home/home/personal/projects/howl/loop.txt
- /home/home/personal/projects/howl/current.txt
- /home/home/personal/projects/howl/render-ownership-restart-scratchpad.md
Howl render/VT:
- /home/home/personal/projects/howl/howl-render/include/howl_render.h
- /home/home/personal/projects/howl/howl-render/src/ffi.zig
- /home/home/personal/projects/howl/howl-render/src/source/slot.zig
- /home/home/personal/projects/howl/howl-render/src/source/vt.zig
- /home/home/personal/projects/howl/howl-render/src/source/cell.zig
- /home/home/personal/projects/howl/howl-render/src/source/damage.zig
- /home/home/personal/projects/howl/howl-render/src/source/prepare_request.zig
- /home/home/personal/projects/howl/howl-render/src/surface/text.zig
- /home/home/personal/projects/howl/howl-render/src/surface/prepared_owner.zig
- /home/home/personal/projects/howl/howl-render/src/session/submitted.zig
- /home/home/personal/projects/howl/howl-render/src/surface/tokens.zig
- /home/home/personal/projects/howl/howl-vt/include/howl_vt.h
Alacritty:
- /home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/term/mod.rs
- /home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs
- /home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/damage.rs
Alacritty-derived ownership facts
- Terminal input/source truth is owned by terminal state:
- Term owns grid: Grid<Cell>, inactive_grid, colors, selection, cursor state, and damage: TermDamageState at term/mod.rs:268-330.
- Rendering asks terminal for borrowed renderable input through Term::renderable_content() at term/mod.rs:635-642.
- Damage/source mutation is terminal-owned:
- TermDamageState stores full/partial line damage at term/mod.rs:216-226.
- Term::damage() publishes damage since last reset and says caller should reset after reading at term/mod.rs:447-490.
- Mutations such as resize, scroll, cursor motion, and input mark terminal damage inside Term at term/mod.rs:654-705, 713-735, 1020-1026, 1059+.
- Display adapts terminal source into render cells, but does not own terminal source:
- display/content.rs:24-38 defines RenderableContent as renderable terminal content wrapping TerminalContent<'a>.
- RenderableContent::new() borrows term.renderable_content() at display/content.rs:41-88.
- RenderableCell::new() adapts terminal cells into display/render cell shape at display/content.rs:208-299.
- Display damage is display-owned and separate from terminal damage:
- DamageTracker owns display-frame damage at display/damage.rs:12-28.
- It swaps/reset frames at display/damage.rs:56-73.
- It converts terminal damaged lines into render damage rectangles with RenderDamageIterator at display/damage.rs:215-274.
Howl conclusion: current C ABI is a publication seam. It should mirror Alacritty’s split:
- source/* owns VT-derived publication storage and validation.
- surface/text.zig composes source, prepare, submitted, and prepared owners behind the public C handle.
- ffi.zig only returns C spans and translates C status/struct fields.
Concrete no-header-change publish scratch shape
Header remains stable. HowlRenderPublishSlot.cells stays HowlVtSurfaceCell * (howl_render.h:242-252).
Store source cells directly, not FFI scratch
Use source-owned retained cells as the temporary writable C span.
Current source facts:
- source/slot.zig:13-20 already has RetainedSlot.cells: []source_vt.SourceCell.
- source/slot.zig:73-77 already has SourceSlot.retained_slot and reserved.
- source/slot.zig:95-103 already reserves source storage and returns PublicationSlot.
- source/slot.zig:109-138 already commits reserved source and validates/canonicalizes dirty metadata.
- source/vt.zig:8-15 aliases source publication ABI-like cell/color/selection structs.
- howl_vt.h:125-142 defines HowlVtSurfaceCell.
Worker-ready shape:
1. In /home/home/personal/projects/howl/howl-render/src/source/vt.zig:
- Make SourceCell, SourceCellFlags, SourceCellAttrs, SourceColor, SourceColors, SourceSelection, and SourceSelectionPoint the source-owned VT publication types.
- Keep them ABI-layout-compatible with HowlVtSurfaceCell but do not import C.
- Add source-owned validation:
- pub fn validateSourceCell(cell: SourceCell) !void
- pub fn validateSourceCells(cells: []const SourceCell) !void
- pub fn validateReservedSourceMeta(meta: ReservedSourceMeta) !void
- Add primitive constructors/validators:
- pub fn sourceColorValid(color: SourceColor) bool
- pub fn underlineStyleValid(value: u8) bool
- cursor shape conversion remains in FFI only as C numeric translation to source_cell.CursorShape, but source owns validity of final ReservedSourceMeta.
2. In /home/home/personal/projects/howl/howl-render/src/source/slot.zig:
- SourceSlot continues to own retained []source_vt.SourceCell.
- reserveSourceSlot() returns PublicationSlot{ .cells = retained source cells, ... }.
- commitReservedSource() must call:
- source_vt.validateReservedSourceMeta(meta)
- source_vt.validateSourceCells(source.cells)
- source_damage.validateDirtySource(...)
- source_damage.canonicalizeDirtyMetadata(...)
- This makes cancel-on-invalid source policy source-owned.
3. In /home/home/personal/projects/howl/howl-render/src/ffi.zig:
- Delete global PublishScratch, ScratchMutex, publish_scratch_mutex, publish_scratch_entries.
- Delete reservePublishScratch(), copyPublishScratch(), removePublishScratch().
- reservePublishSlot():
- gets source_slot.PublicationSlot from owner.reservePublishSlot(cols, rows).
- returns .cells.ptr = @ptrCast(slot.cells.ptr) and .cells.len = slot.cells.len.
- returns dirty spans directly.
- FFI owns only the pointer cast and span translation.
- Add compile-time layout assertions in FFI because FFI is the C translation seam:
- @sizeOf(source_vt.SourceCell) == @sizeOf(c.HowlVtSurfaceCell)
- @alignOf(source_vt.SourceCell) == @alignOf(c.HowlVtSurfaceCell)
- @offsetOf(...) equality for every field used by the ABI.
- commitPublishSlot():
- translates HowlRenderPublishSlotCommit into source_vt.ReservedSourceMeta.
- calls owner.commitPublishSlot(meta).
- if owner returns invalid-source/missing-slot errors, maps to C invalid argument and cancels through owner policy only if SurfaceTextOwner defines that as the composition behavior.
- no direct owner.source_slot.reservedSource() access.
- no per-cell validation loop.
Why this follows Alacritty:
- Alacritty Term owns the source grid and damage (term/mod.rs:268-330, 447-490).
- Display borrows/adapts source (display/content.rs:41-88, 208-299) but does not own terminal cell scratch.
- Therefore Howl source/slot.zig owns the writable publication storage; FFI merely exposes that storage as the stable C span.
Revised ordered slices
Slice 1: Remove FFI publish scratch and source publication policy
Highest-value invented FFI ownership.
Files:
- /home/home/personal/projects/howl/howl-render/src/ffi.zig
- /home/home/personal/projects/howl/howl-render/src/source/vt.zig
- /home/home/personal/projects/howl/howl-render/src/source/slot.zig
- /home/home/personal/projects/howl/howl-render/src/surface/text.zig
Move/remove:
- Remove from ffi.zig: PublishScratch, ScratchMutex, publish_scratch_mutex, publish_scratch_entries, reservePublishScratch, copyPublishScratch, removePublishScratch, direct owner.source_slot.reservedSource() policy, validatePublicationCellValue.
- Move validation into source/vt.zig and source/slot.zig.
- Keep ABI C pointer span translation in ffi.zig.
Slice 2: Move prepared-handle lifecycle policy out of FFI
Files:
- surface/text.zig
- surface/prepared_owner.zig
- session/submitted.zig
- ffi.zig
Move direct prepared_publish_handle / prepared_submit_handle mutation from FFI into SurfaceTextOwner methods.
Slice 3: Move token invariants out of FFI
Files:
- surface/tokens.zig
- ffi.zig
Move prepare/prepared token construction and equality into token owner.
Slice 4: Move source primitive validation out of FFI
Files:
- source/cell.zig
- source/vt.zig
- ffi.zig
Move color/underline/cell primitive validation out of FFI. FFI only translates C fields to source primitives.
First worker-ready slice
Goal
Remove retained publication scratch and source publication policy from ffi.zig without changing howl-render/include/howl_render.h.
Exact edits
howl-render/src/source/vt.zig
Add:
- pub fn validateSourceCell(cell: SourceCell) !void
- pub fn validateSourceCells(cells: []const SourceCell) !void
- pub fn validateReservedSourceMeta(meta: ReservedSourceMeta) !void
- validation helpers for source-owned ABI publication facts:
- codepoint <= std.math.maxInt(u21)
- combining_len <= combining.len
- every active combining codepoint <= u21
- SourceColor.kind in {0,1,2}
- indexed color value <= u8
- rgb value <= u24
- underline style in 0...4
- snapshot_seq != 0
No C import.
howl-render/src/source/slot.zig
In commitReservedSource():
- Validate meta before mutating committed source fields where practical.
- After source fields are populated and before dirty validation/canonicalization:
- call source_vt.validateSourceCells(source.cells).
- Preserve existing dirty validation/canonicalization.
- Preserve retained-storage behavior.
howl-render/src/surface/text.zig
In SurfaceTextOwner.commitPublishSlot():
- Keep composition only:
- assert/validate nonzero snapshot through source owner.
- call source_slot.commitReservedSource(...).
- set cursor phase.
- call prepare_requests.acceptSource(...).
- Do not expose source_slot.reservedSource() to FFI.
howl-render/src/ffi.zig
- Delete lines 16-34 global scratch definitions.
- Delete removePublishScratch(owner) call in deinit() line 66.
- Rewrite reservePublishSlot() lines 123-135:
- no scratch allocation.
- call owner.reservePublishSlot(cols, rows).
- publishSlotOut(slot) returns HowlVtSurfaceCell * by casting source_vt.SourceCell *.
- Rewrite commitPublishSlot() lines 137-174:
- no owner.source_slot.reservedSource().
- no copyPublishScratch.
- no cell validation loop.
- translate commit fields to ReservedSourceMeta.
- call owner.commitPublishSlot(meta).
- Delete helpers:
- reservePublishScratch
- copyPublishScratch
- removePublishScratch
- validatePublicationCellValue
- unused cellValueIn
- unused byteSpanIn if still unused.
- Add FFI-only layout assertions proving the stable ABI cast:
- source cell size/alignment equals c.HowlVtSurfaceCell.
- offset equality for codepoint, combining_len, combining, flags, fg_color, bg_color, underline_color, underline_style, attrs, link_id.
- source color size/alignment/field offsets equal c.HowlVtColor.
- source attrs/flags size and offsets equal C.
Invariants
- No C header change.
- No @cImport outside ffi.zig.
- No global mutable publication scratch in FFI.
- Source slot owns retained writable publication storage.
- Source owner validates cell and dirty metadata before publication is accepted.
- FFI never reads or writes owner.source_slot.reservedSource().
- FFI does not decide source cancel policy beyond calling public owner methods.
- No compatibility shims.
- No types.zig.
- No manager, controller, runtime, flow, pipeline, or queue owner.
Tests
Add/adjust owner-local tests:
- In source/vt.zig:
- rejects source cell codepoint > u21.
- rejects combining_len > 3.
- rejects active combining codepoint > u21.
- rejects invalid color kind.
- rejects indexed color value > u8.
- rejects rgb color value > u24.
- rejects underline style > 4.
- rejects ReservedSourceMeta.snapshot_seq == 0.
- In source/slot.zig:
- existing dirty metadata tests stay source-owned.
- add “source slot commit rejects invalid source cell without FFI scratch”.
- add “source slot exposes retained source cell storage for publication”.
- add “source slot cancel clears reserved source after invalid commit policy” only if commit path still cancels on invalid input; otherwise test exact retained state chosen by implementation.
- In test/ffi.zig:
- preserve “render ffi publish slot translates vt cell ffi storage”.
- add/keep invalid publication tests through ABI:
- invalid cell codepoint causes commitPublishSlot() invalid argument.
- invalid underline style causes invalid argument.
- invalid color kind causes invalid argument.
- Add one pointer/lifetime behavior test:
- reserve slot, write C cell through returned pointer, commit, take prepare request succeeds.
- reserve again after cancel and pointer storage is owner-retained, not global FFI scratch. Do not require same pointer if capacity changes; require no FFI global state via grep.
Grep gates
No matches in /home/home/personal/projects/howl/howl-render/src/ffi.zig:
- PublishScratch
- ScratchMutex
- publish_scratch
- reservePublishScratch
- copyPublishScratch
- removePublishScratch
- validatePublicationCellValue
- reservedSource
- owner.source_slot
No matches outside ffi.zig:
- @cImport
- HowlVtSurfaceCell
- HowlRenderPublishSlot
No new names under howl-render/src:
- types.zig
- manager
- controller
- runtime
- flow
- pipeline
- queue
Verification:
- From /home/home/personal/projects/howl:
- zig build check
- zig build test
- If needed from /home/home/personal/projects/howl/howl-render:
- zig build check
- zig build test
Risks and bounded mitigations
- Risk: source SourceCell layout may not currently match HowlVtSurfaceCell.
- Mitigation: first slice includes explicit FFI @sizeOf, @alignOf, and @offsetOf assertions. If an assertion fails, adjust source-owned SourceCell field padding/order to match the stable VT ABI. Do not change the C header.
- Risk: moving validation may change which function cancels reserved source on invalid commit.
- Mitigation: make the policy explicit in SurfaceTextOwner.commitPublishSlot() or SourceSlot.commitReservedSource() and test it. FFI must not implement the policy.
- Risk: source/vt.zig still aliases surface/publication_source.zig.
- Mitigation: acceptable only inside this slice if it remains a narrow source shape. No compatibility shim naming. Later slice can fold it into source/vt.zig.
Explicit readiness judgment
Ready for implementation: Slice 1 is worker-ready.
It gives a concrete no-header-change solution for publish scratch: source owner stores the writable source-cell span directly; FFI casts and returns the stable C span, then delegates commit/validation/cancel policy to source/session owners.
