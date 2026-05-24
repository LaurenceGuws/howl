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
