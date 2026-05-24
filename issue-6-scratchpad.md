# Issue 6 Scratchpad

Owner: workspace root.

Source:

- `feature-gap-scratchpad.md` item 6

Issue:

- Kitty graphics state is implemented in VT but not exportable above VT.

First rule:

- Treat this as staged VT-truth repair first, not "add an ABI now".

Product rule:

- The ABI is the product.
- Do not ship a fake graphics ABI over false VT truth.

Repo owner truth:

- `howl-vt` owns kitty graphics truth.
- `howl-render` and hosts must not consume kitty graphics through Zig-module shortcuts.
- Any eventual consumer above VT must use the C ABI seam only.

Current status:

- `work-not-clear`

Why current state is not exportable yet:

- graphics state is terminal-global, not per buffer/screen
- RIS/reset does not clear graphics truth honestly
- alt-screen switching does not switch graphics truth
- supported text mutation paths do not update placements
- scroll paths do not move or delete placements honestly
- `a=T` is not implemented honestly
- placement replacement semantics are incomplete
- retained payloads are protocol payload bytes, not render-ready decode truth

New blocker found after early VT-truth checkpoints:

- `work-not-clear` for text/scroll mutation coupling with the current placement model
- Reason:
  current `Placement` truth only stores `row`, `col`, `columns`, `rows`, and `z_index`
- Missing truth needed for honest Kitty-style mutation coupling:
  - source rectangle / clipping state
  - cell pixel offsets
  - partial visibility / cropped-placement truth
  - virtual / relative placement identity and ancestry
- Consequence:
  scroll, erase, and line-mutation paths can move or delete simple full-region placements, but cannot honestly represent placements that are partially clipped by region boundaries or text mutation. Kitty's owner truth can crop and adjust refs during these operations; Howl's current placement model cannot.
- Rule from this point:
  do not fake checkpoint 5 by deleting or blindly shifting all intersecting placements unless the supported subset is explicitly narrowed to a shape the current placement truth can actually prove.
- Decision:
  do not narrow the subset as a shortcut.
- Active route:
  extend VT placement truth first, then resume mutation coupling.
- Quality bar:
  match or exceed Kitty's lifecycle honesty here, with TigerBeetle pressure against second-best shortcuts.

Primary live owner files:

- `howl-vt/src/kitty/graphics.zig`
- `howl-vt/src/kitty/state.zig`
- `howl-vt/src/kitty/apply.zig`
- `howl-vt/src/kitty/protocol.zig`
- `howl-vt/src/terminal.zig`
- `howl-vt/src/control/mode.zig`
- `howl-vt/src/screen_set.zig`
- `howl-vt/src/screen/apply.zig`
- `howl-vt/src/test/terminal_graphics.zig`

Reference files:

- `AGENTS.md`
- `reference-index.md`
- `utils/dev_references/terminals/ghostty/src/lib_vt.zig:244-259`
- `utils/dev_references/terminals/ghostty/src/terminal/c/terminal.zig:577-606`
- `utils/dev_references/terminals/ghostty/src/terminal/c/kitty_graphics.zig`
- `utils/dev_references/terminals/ghostty/include/ghostty/vt/kitty_graphics.h`
- `utils/dev_references/terminals/kitty/kitty/screen.h`
- `utils/dev_references/terminals/kitty/kitty/screen.c`
- `utils/dev_references/terminals/kitty/kitty/graphics.h`
- `utils/dev_references/terminals/kitty/kitty/graphics.c`
- `utils/dev_references/terminals/kitty/kitty/parse-graphics-command.h`
- `utils/dev_references/terminals/kitty/kitty/vt-parser.c`
- `utils/official_docs/kitty/graphics-protocol.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`

## Clear Comparison

### Kitty Has

- VT is the source of truth for kitty graphics lifecycle.
- Main and alternate screens have separate graphics owners.
- Physical placements are retained terminal truth, not a render cache.
- Full-page upward scroll moves placements into retained above-screen state.
- Full-page downward scroll moves placements downward and can retain them below the page.
- Margin-region scroll mutates retained placement truth with clipping.
- Full-screen clear deletes visible placements.
- `a=T` is real transmit-and-display, not a fake alias for upload.
- Placement replies include placement id when `p != 0`.
- Chunked transmit-and-display depends on first-command placement metadata surviving until completion.
- Virtual placements, placeholder-driven behavior, relative placements, and animation are real parts of Kitty, but are not required for Howl v1.

### Ghostty Has

- A strong retained row owner model through terminal page/page-list truth.
- Graphics references borrow retained row location truth from terminal ownership rather than inventing a parallel graphics row model.
- A public C seam for kitty graphics inspection.
- A more mature publication/acquisition story than Howl currently has.
- A useful shape reference for publication and owner split.
- Not a literal copy target for Howl internals.

### Howl Has Now

- `howl-vt` owns graphics truth.
- Main and alternate screens now own separate graphics state.
- Reset clears graphics truth.
- Placement replacement semantics are now honest.
- Unsupported subset is now rejected explicitly.
- Physical placement truth now includes:
  - image identity
  - placement identity
  - row-anchor truth
  - crop truth
  - offsets
  - requested extents
  - effective extents
- Full-page upward movement is retained honestly.
- Below-page retained anchor truth now exists.
- Margin-region clipping for fully enclosed physical placements now exists.
- A public graphics ABI now exists for:
  - graphics meta
  - indexed image query
  - indexed placement query
  - payload copy
  - cell-pixel-size input
- `howl-render` now consumes graphics publication metadata only and forces full damage when that metadata changes.
- The graphics publication contract is explicit, but still conservative.
- `a=T` now works for the supported physical direct-upload subset.

### Howl Still Does Not Have

- A graphics-local publication key proved to advance only on graphics-local mutation.
- A completed caller-owned acquisition path that pairs visible surface publication with graphics publication in the real host seam.
- Item-level image/placement ingestion above VT.
- Any truthful drawing path above VT.
- Virtual/placeholder placement truth.
- Relative placement truth.
- Non-`t=d` media.
- Compression.
- Animation/frame publication in the eventual ABI target.

Correction after the first above-VT render slice:

- The public graphics ABI now exists for graphics meta, indexed image query, indexed placement query, payload copy, and cell-pixel-size input.
- The first `howl-render` consumer slice is landed and metadata-only:
  - it carries graphics publication metadata through render VT publication input
  - it forces full damage when graphics publication changes
  - it does not yet ingest images, placements, or payload bytes
- But that slice does not yet close the real host acquisition boundary:
  - this was the next truthful checkpoint at the time
- The host acquisition boundary is now closed and proved:
  - the real host caller acquires graphics meta alongside the copied VT surface
  - the host/render publish seam now carries that paired truth through the shipped contract
- The copied item metadata ingestion checkpoint is now landed, still without drawing.

## Exact Goal

Howl should become better than both references in one specific way:

- Kitty-level lifecycle honesty.
- Ghostty-level publication discipline.
- TigerBeetle-level skepticism about shipping false seams.

That means:

- VT remains the source of truth.
- Render translates VT truth to rendered output.
- Render does not invent behavior above VT.
- Hosts do not reach around the ABI.
- The first graphics ABI must describe only retained truth that VT already owns and proves.
- Above-VT progress stops whenever the acquisition/publication boundary is weaker than the truth it claims to carry.

## Exact Howl Graphics Target

Public graphics ABI work starts only after VT truth is complete for the currently supported subset.

When ABI work begins, the first public graphics product should expose only this exact subset:

- direct payload medium `t=d`
- physical cursor-anchored placements only
- actions `t`, `T`, `p`, `d`
- image ids and image numbers
- active-screen retained image metadata
- active-screen retained physical placement metadata
- retained payload bytes exactly as stored by VT
- row-anchor truth, including off-screen retained states
- crop truth
- offsets
- requested extents
- effective extents
- publication through an explicit graphics publication contract

The first public graphics product should explicitly omit:

- placeholders / `U=1`
- relative placements `P/Q/H/V`
- decoded/render-ready image publication
- non-`d` media
- compression
- animation control/composition
- render-derived geometry

## Drive Rule

When a checkpoint is ambiguous, decide by asking three direct questions:

1. Is this VT-owned truth or render-owned translation?
2. Does Kitty already require this behavior for the subset we claim to support?
3. Would exporting this now create a false ABI seam?

If any answer is bad, do not ship the checkpoint.

No-guessing rules:

- Read the live owner files before each checkpoint.
- Re-state the supported subset before editing if the checkpoint depends on scope.
- Prefer `work-not-clear` over speculative export or speculative lifecycle claims.
- Reject any pass that claims visible/public semantics the owner truth does not actually prove.
- Keep trees clean. Reset rejected work immediately.

Supported subset for the first implementation phase:

- In scope:
  - direct payload medium `t=d`
  - actions `t`, `p`, `d`, `f`
  - image ids and image numbers
  - physical cell-anchored placements
  - bounded retained payload ownership as protocol payload bytes
- Out of scope for now:
  - public graphics ABI
  - file/shared-memory media
  - compression
  - unicode placeholders `U=1`
  - relative placements `P/Q/H/V`
  - animation control `a=a`
  - animation composition `a=c`
  - render-ready decode ownership

Important semantics from Kitty that the supported subset must honor:

- main and alternate screen graphics truth are separate
- reset clears graphics truth appropriately
- alt enter/exit switches the active graphics truth
- scrolling moves placements with text
- text erasure and line mutation remove or adjust intersecting placements honestly
- re-uploading an existing image id replaces the image and deletes its placements
- placing the same image id plus placement id replaces that placement
- delete commands abort partial uploads
- `a=T` means transmit and display, not just transmit

Shortcuts to reject:

- export `vt.kitty.global.graphics` directly
- copy Ghostty's borrowed-handle ABI before Howl truth matches it
- claim active-screen visibility while storage is terminal-global
- claim render-ready image bytes while VT only stores retained base64 payloads
- silently ignore unsupported kitty graphics actions once scope is frozen

Internal loop plan:

1. Define the exact checkpoint.
2. Read the owning files for that checkpoint.
3. Implement the smallest owner-truth repair only.
4. Add focused proofs in `howl-vt/src/test/terminal_graphics.zig`.
5. Run targeted VT proof.
6. Review the diff against owner truth and Kitty semantics.
7. If weak, reset and restart narrower.

Checkpoint queue:

1. Per-buffer graphics ownership.
   - Move graphics truth from terminal-global storage to main-vs-alt screen-owned storage shape.
   - Keep mutation control centralized.
   - Proof:
     - main and alt counts diverge correctly
     - alt enter with clear has empty graphics state
     - alt exit restores main graphics state unchanged

2. Reset semantics.
   - Make terminal reset clear graphics truth for the supported subset.
   - Proof:
     - RIS clears images, placements, frames, and partial upload state

3. Alt-screen semantics.
   - Ensure enter/exit alt uses the correct graphics owner and clear behavior.
   - Proof:
     - placing in alt does not affect main
     - returning from alt does not leak alt placements into main

4. Placement replacement semantics.
   - Ensure same image id replaces image and clears dependent placements.
   - Ensure same image id plus placement id replaces that placement.
   - Proof:
     - replacement is idempotent and bounded

5. Supported text-mutation coupling.
   - Decide the smallest honest mutation set for this phase.
   - Minimum expected candidates:
     - scroll up/down region
     - insert/delete lines
     - erase display modes that clear active screen regions
   - Open edge discovered:
     the current placement model is too weak to represent Kitty-style clipped/cropped movement honestly across these mutations.
   - Before implementing this checkpoint:
     - extend VT placement truth first so clipped movement is representable.
   - Proof:
     - placements move or clear honestly for the supported set

4.5. Placement truth extension.
   - Add the smallest placement truth needed so later mutation coupling can be honest.
   - Minimum design questions to close before editing:
     - what exact placement fields are required to represent clipped movement honestly for the supported subset?
     - which of those fields are VT truth vs later render-derived data?
     - how do these fields interact with replacement, reset, alt-screen, and future ABI export?
   - Proof target for this checkpoint:
     - new placement truth can represent the mutation outcomes we need, without relying on host/render guesswork.

Design decision for checkpoint 4.5:

- Do not take the shortcut subset route.
- Do not add relative/virtual placement truth in this checkpoint.
- Extend VT placement truth for physical, cursor-anchored placements only.

Exact supported placement subset after this decision:

- in scope:
  - physical placements only
  - cursor-anchored placement origin
  - direct payload medium `t=d`
  - source rectangle selection
  - cell-pixel offsets
  - scroll-driven movement and clipping
- out of scope:
  - unicode placeholders `U=1`
  - relative placements `P/Q/H/V`
  - placeholder-realized cell refs
  - text-coupled image mutation semantics that exist only for placeholder-driven images

Exact placement truth required for the next implementation pass:

- identity truth:
  - `image_id`
  - `placement_id`
  - `z_index`
- anchor truth:
  - `anchor_row`
  - `anchor_col`
- source/crop truth owned by VT:
  - `source_x`
  - `source_y`
  - `source_width`
  - `source_height`
- cell-pixel offset truth owned by VT:
  - `cell_x_offset`
  - `cell_y_offset`
- requested size truth:
  - `columns`
  - `rows`
- effective visible extent truth owned by VT:
  - `effective_columns`
  - `effective_rows`

Fields that are render-derived, not VT truth for this checkpoint:

- viewport position
- final visible clipping against the viewport
- pixel width/height after host/render geometry policy
- clamped source rectangle against decoded image bounds

Important correction from Kitty source review:

- For the supported non-placeholder subset, honest mutation coupling is narrower than previously assumed.
- Must affect placements now:
  - scroll/index/reverse-index
  - margin scroll clipping
  - full-screen clear semantics that delete visible placements
- Must not be claimed yet for this subset:
  - generic partial erase affecting normal placements
  - insert/delete-line coupling for normal placements
  - placeholder-driven image movement/deletion without implementing placeholder truth

Why this is the right shape:

- Kitty mutates stored placement/reference truth for scroll and clipping.
- Kitty's richer placeholder and relative-placement behaviors depend on extra reference truth we do not yet own.
- TigerBeetle pressure rejects pretending those semantics exist before the underlying truth exists.

Required invariants/proofs for the next implementation pass:

- placements never reference a missing image on the same screen owner
- `effective_columns > 0`
- `effective_rows > 0`
- `source_width > 0`
- `source_height > 0`
- if clipping would reduce visible extent to zero, delete the placement
- scroll mutation must either move the anchor, shrink effective extent, adjust source crop, or delete the placement
- no host/render guesswork is required to know the retained placement truth after mutation

New blocker after checkpoint 4.5:

- `work-not-clear` for the next scroll/index/reverse-index checkpoint.
- Reason:
  current `anchor_row` truth is screen-relative `u16` only.
- Why this blocks honest Kitty-style scroll coupling:
  - main-screen upward scroll can move placements with text into scrollback
  - Kitty retains those refs with off-screen negative row state, bounded by scrollback history
  - Howl currently cannot represent that retained state at all
- Consequence:
  implementing only visible-screen movement and margin clipping would be a shortcut, not a correct checkpoint, because it would omit honest retained truth for main-screen scroll into scrollback.

Design question that must be closed before the next implementation pass:

- what is the smallest VT-owned anchor truth that can represent:
  - on-screen rows
  - off-screen-above rows retained in main-screen scrollback
  - active-screen separation
  - later clipping mutations

Likely direction:

- replace plain `u16 anchor_row` with a signed or tagged anchor representation that can encode above-viewport retained rows for the main screen.
- do not guess the final shape until the owner and proof story are explicit.

Progress after that blocker:

- tagged row-anchor truth is now landed
- upward full-page scroll retention is now landed
- full-screen clear deletion semantics are now landed

New blocker after the rejected full-page downward draft:

- `work-not-clear` for downward full-page movement beyond simple re-entry.
- What the rejected draft got right:
  - retained-above rows can re-enter the visible page correctly
- What it got wrong:
  - bottom-overflow placements were deleted instead of clipped honestly
- Exact missing truth:
  - VT still does not own enough geometry truth to map downward row overflow into correct `source_height` crop updates without guessing
  - Kitty clips references using geometry knowledge that Howl VT does not yet own directly
- Rule from this point:
  do not land downward movement that deletes bottom-overflow placements as a shortcut.
- Next design question:
  what is the full, exact VT-owned geometry truth needed to crop physical placements honestly on downward overflow without violating the render boundary?

Current design answer:

- exact downward bottom clipping likely requires VT to own retained placement geometry in two spaces at once:
  - image-space crop truth
  - cell-grid pixel-space destination geometry truth
- image-space crop truth:
  - `source_x`
  - `source_y`
  - `source_width`
  - `source_height`
- cell-grid destination geometry truth likely required for exactness:
  - `anchor_row`
  - `anchor_col`
  - `dest_left_cell_px`
  - `dest_top_cell_px`
  - `dest_right_cell_px`
  - `dest_bottom_cell_px`
  - `placement_cell_width_px`
  - `placement_cell_height_px`

Why this is now the active question:

- current row anchor, crop fields, offsets, and effective row counts are enough for upward retention and visible deletion
- they are not yet enough to prove exact bottom crop updates for downward overflow
- deleting on overflow was rejected as second-best

Boundary warning:

- do not solve this by asking render/host to provide post-scroll crop truth
- do not leak render viewport/output geometry into VT owner state
- if exact downward clipping needs a new resolved-geometry owner inside `howl-vt`, make that owner explicit and keep it fully below the ABI

Current blocker after reassessing `a=T`:

- `work-not-clear` for honest `a=T` support even after the current VT-truth repairs.
- Why it is still blocked:
  - current upload truth does not retain enough placement metadata across chunked `a=T`
  - current placement reply semantics are not yet Kitty-honest for non-zero `p`
  - current VT path does not implement the required default cursor movement after transmit-and-display placement
- Rule from this point:
  do not land `a=T` until those three prerequisites are repaired explicitly.

Next smaller prerequisite checkpoints before `a=T` can land:

1. placement reply semantics for non-zero `p`
2. retained upload metadata shape for chunked `a=T`
3. default cursor movement semantics for accepted physical placement

ABI readiness review result:

- VT truth is now substantially repaired for the current supported physical subset.
- The public graphics ABI checkpoint has landed.
- The first render-side metadata/publication-only consumer checkpoint has landed.
- The next blocker is the real acquisition boundary above VT, not whether a first public ABI should exist.

When public ABI work begins, the smallest honest first ABI must:

- expose only the currently supported physical subset
- expose retained payload bytes exactly as stored, not decoded pixels
- omit placeholders, relative/virtual placements, non-`d` media, compression, animation, and render-derived geometry
- tie publication explicitly to a graphics publication rule, preferably the existing `surface_snapshot_seq` only if graphics publication is proven to cohere with that contract

Immediate blockers before the next render ingestion pass can begin:

1. state the exact rule for pairing VT surface publication with graphics item publication
2. decide the owner of that pairing above VT without bypassing the C ABI boundary
3. keep the next slice metadata-only: copied image and placement metadata, no payload bytes, no decoded pixels, no render-derived geometry

Exact current pairing rule:

- `howl_vt_terminal_copy_surface()` publishes visible text/dirty/cursor/color/selection truth under `snapshot_seq`.
- `howl_vt_terminal_query_graphics_meta()` publishes graphics truth under a separate `publication_seq`.
- Graphics publication is conservative today:
  - it can advance on any terminal `dirty_generation` change
  - it is not yet a graphics-local cache key
- Therefore the first honest above-VT consumer rule is:
  1. one caller acquires surface truth and graphics truth together
  2. surface and graphics are treated as two publication tokens from one acquisition attempt, not one shared token
  3. graphics item queries must use the exact `publication_seq` returned by `query_graphics_meta()`
  4. if any item query rejects that publication, the caller restarts acquisition instead of mixing generations
- This keeps ownership honest:
  - VT owns both publication tokens
  - the caller above VT owns acquisition/retry policy
  - render still consumes copied results only, not direct VT internals

Current answer from the latest render-facing scrutiny round:

- We are not ready for item-level ingestion yet.
- The host acquisition boundary was honest enough to start the next checkpoint.
- That copied item metadata checkpoint is now landed.
- The copied item retention/replacement proof is now landed.
- Remaining constraints after that pass:
  - current graphics publication is still conservative and invalidates on terminal dirty-generation changes, not only graphics-local changes
  - copied item metadata must not treat query index as stable identity or paint order
  - copied item metadata alone still does not define draw order, viewport mapping, or render-owned geometry meaning
- Therefore the next truthful checkpoint is:
  1. accept that no honest pre-drawing checkpoint remains
  2. answer the draw-semantics gate before any drawing work
  3. only then start code again

Next design-round questions before any more coding:

1. Kitty quality bar:
   - For the supported physical subset, what exact visible ordering and clipping semantics must the next render-facing checkpoint preserve?
   - What would count as a second-best shortcut against Kitty truth here?
2. Ghostty integration bar:
   - What is the smallest integration shape for carrying retained graphics truth above VT without reopening a borrowed-handle or direct-owner seam that Howl does not actually own?
   - Which Ghostty integration ideas are shape references only and must not be copied literally?
3. Alacritty speed/simplicity bar:
   - What is the simplest host/render control spine that can carry the next graphics truth without adding a new layer or speculative cache?
   - What should remain out of scope to keep the next pass small and bounded?
4. TigerBeetle final-say/style bar:
   - What assertions and proof obligations must exist before we claim any pre-drawing or drawing-adjacent checkpoint?
   - If the next step cannot be stated as a small, explicit, bounded owner checkpoint, should we stop and mark `work-not-clear`?

Smallest subagent plan for this round:

1. Derive subagent:
   - exact task: propose the smallest honest next checkpoint from the questions above
   - inputs: `AGENTS.md`, `reference-index.md`, `loop.txt`, `current.txt`, this scratchpad, live Howl VT/render/host files, Kitty/Ghostty/Alacritty/TigerBeetle reference paths
   - output: checkpoint name, owner, exact shape, exact proof list, exact stop condition
   - constraints: research-only, no code changes, no new ABI, no new layer, no Zig bypass
2. Critique subagent:
   - exact task: attack that checkpoint for false seams, guessed geometry, guessed ordering, weak proof, or style violations
   - same pinned inputs
   - output: severity-ordered findings, single must-close blocker, yes/no on starting code
   - constraints: research-only, no code changes
3. Main agent:
   - accept/reject/reset from those two outputs
   - write the chosen checkpoint into this scratchpad
   - only then start proof-first coding
- Rule:
  - slow progress is preferred over fake progress
  - stop above-VT expansion whenever the acquisition boundary is weaker than the claimed truth

Accepted answer from the latest derive/critique round:

- Recommended next checkpoint name:
  `Graphics Draw-Semantics Gate`
- Honest pre-drawing checkpoint still exists:
  no
- Why:
  - VT item queries are publication-local and index order is unstable
  - Kitty requires explicit draw-order semantics
  - the remaining unresolved questions are already draw-order, viewport inclusion, and clipping questions
- Critique correction:
  - draw order is not the primary blocker anymore
  - the primary blocker is destination extent truth for placements that omit `c` and/or `r`
  - current copied ABI fields are not truthful enough for viewport inclusion or clipping in those cases
- Single must-close blocker:
  - state the exact current destination extent contract for copied placements, especially for `c`-only, `r`-only, or fully default placements, so render can decide visibility and clipping without guessing
- Rule from here:
  - do not build a scene, cache, or drawing pass until draw-order, viewport inclusion, and clipping contracts are named explicitly from copied ABI truth

Accepted answer after critique completion:

- Current copied ABI fields are sufficient for stating most supported-subset draw-order rules:
  - sort by `z_index`
  - then by lower `image_id`
  - never use query index order as paint order
- But current copied ABI fields are not sufficient for truthful viewport inclusion or clipping when placement size is implicit.
- Kitty requires omitted `c`/`r` dimensions to derive from aspect ratio and cell geometry.
- Howl currently collapses those cases too early into insufficient retained extent truth above VT.
- Therefore the next truthful checkpoint is no longer a render drawing checkpoint.
- The next truthful checkpoint is a VT-truth/design checkpoint for destination extent publication.

6. Unsupported-action rejection.
   - Reject unsupported scope explicitly instead of partially accepting it.
   - Minimum expected rejects for now:
     - `a=T` until implemented honestly
     - `U=1`
     - relative placement keys
     - unsupported media/compression if not implemented in owner truth
   - Proof:
     - unsupported commands fail explicitly and do not mutate retained truth

7. ABI readiness review.
   - Stop and answer whether VT truth is now honest enough to export.
   - If no, record `work-not-clear` with the exact remaining gaps.
   - If yes, start a separate ABI scratchpad and checkpoint queue.

Per-checkpoint start conditions:

- Which repo owns this state?
  - `howl-vt`
- Which file owns this control flow?
  - Name it exactly before editing.
- Which thread owns this work?
  - terminal owner thread
- Is this honoring the C ABI boundary?
  - yes, VT-truth phase stays below the ABI
- What proof closes the change?
  - state it before editing

Acceptance target for this scratchpad:

- Future loops do not attempt one-shot Issue 6 delivery.
- Each pass closes one truthful checkpoint or stops at `work-not-clear`.
- ABI work begins only after VT truth becomes explicitly and provably honest.
