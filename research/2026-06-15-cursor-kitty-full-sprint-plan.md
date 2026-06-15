# Cursor Kitty Full Sprint Plan

## Receipt Header

- Artifact owner: `research/2026-06-15-cursor-kitty-full-sprint-plan.md`
- Orchestrator session id: `orch-2026-06-15-cursor-restart-01`
- Researcher session id: `ses_135074a6bffeuLKDxy30qK2cAL`
- Reviewer session id: `ses_13508b5e7ffe0XZUyUcJd4EPEs`
- Source loop artifact: `loops/cursor-kitty-port-pre-research.txt`
- Artifact status: full remaining sprint planning package from blank-state restart
- Commit-hash receipt status: no planning commit recorded in this artifact
- Live authority note: prior coder work is unauthorized debt and not live planning authority for this artifact

## Primary User Instruction

- Rip out existing Howl cursor code.
- Port Kitty cursor code to Zig.
- Kitty parity is primary for cursor work.
- Ghostty may only be consulted as fallback ownership advice if full Kitty cursor behavior cannot otherwise stay clean.
- C ABI boundary remains non-negotiable.

## Cursor-Scoped Reference Receipt

- Active cursor-scoped authority order for this artifact:
  1. User direction.
  2. Kitty cursor sources.
  3. Alacritty host and render organization.
  4. TigerBeetle ownership, assertions, source order, and tests.
  5. Ghostty fallback only for ownership cleanliness if Kitty parity is otherwise impossible to model cleanly.
  6. Official docs for protocol facts.
- This artifact intentionally overrides the default VT-first Ghostty pressure in `reference-index.md:19-25,71-107` and `AGENTS.md:226-249` for this cursor slice only.
- Override reason: the user explicitly set Kitty parity as primary for cursor work in `loops/cursor-kitty-port-pre-research.txt:14-40`.

## Resolved User Decisions

- Decision 1: alt-screen semantics are Kitty.
- Decision 2: save and restore payload is Kitty-like payload.
- Decision 3: restore without prior save follows Kitty behavior.
- Decision 4: `DECSCUSR >= 7` follows Kitty behavior.
- Decision 5: ownership shape preserves full Kitty parity first; Ghostty may only be consulted as fallback advice if needed to keep ownership clean without losing Kitty parity.

## Current-State Owner Map

### Parser and semantic routing

- `howl-vt/src/csi_intermediate.zig:102-108` owns `DECSCUSR` parse dispatch through `processSpace`, mapping `CSI Ps SP q` into `SemanticEvent.cursor_style`.
- `howl-vt/src/csi_plain.zig:34-38` owns `CSI s` and `CSI u` parse aliases.
- `howl-vt/src/esc.zig:18-27,42-53` owns `ESC 7` and `ESC 8` parse aliases.
- `howl-vt/src/csi_private.zig:95-100` owns cursor-relevant alt-screen parse consequences for `47`, `1047`, and `1049`.
- `howl-vt/src/vocabulary.zig:81-97,153-156,234-237,294-302,362-364` defines the current cursor semantic surface: `CursorShape`, `CursorStyle`, `CursorStyleCommand`, `cursor_visible`, `cursor_style`, `cursor_color`, `cursor_text_color`, `save_cursor`, `restore_cursor`, `enter_alt_screen`, `exit_alt_screen`.
- `howl-vt/src/route.zig:144-152,216-217` routes cursor semantics into screen and mode owners.

### VT cursor state and save/restore

- `howl-vt/src/screen/cursor.zig:4-92` is the current active cursor state owner. It defines `CursorShape`, `CursorStyle`, `default_cursor_style`, and `SemanticCursor` with `row`, `col`, `visible`, `effective_shape`, `blink_intent`, `default_style`, `program_override_style`, `cursor_color`, `cursor_text_color`, and `position_changed_by_client_at`.
- `howl-vt/src/screen/cursor.zig:107-120` is the current save/restore owner. It saves only `row`, `col`, and `wrap_pending`.
- `howl-vt/src/screen.zig:77-87,105-140` embeds cursor state in `Screen` as `cursor`, `saved_cursor`, and `current_attrs`.
- `howl-vt/src/screen.zig:378-383` exposes `Screen.saveCursor` and `Screen.restoreCursor` as forwards into `screen/cursor.zig`.
- `howl-vt/src/screen/apply.zig:102-111,146-170` mutates cursor state directly: save/restore, visibility, style, cursor colors, origin mode, auto-wrap, insert mode.
- `howl-vt/src/screen_set.zig:79-92,127-159` adds a second stale save/restore owner via `CursorSnapshot` and `saved_primary_cursor`, storing only `row`, `col`, `wrap_pending`, and `cursor_visible` for alt-screen return.
- `howl-vt/src/screen_set.zig:167-194` exports cursor view truth for publication as `cursor_row`, `cursor_col`, `cursor_visible`, `cursor_shape`, and `cursor_blink`.
- `howl-vt/src/mode.zig:146-170,184-189` owns DEC private cursor consequences: `?25`, `47`, `1047`, `1049`.
- `howl-vt/src/mode.zig:74-87,96-112,192-212` includes cursor visibility and alt-screen state in DECRQM reporting.
- `howl-vt/src/terminal.zig:48-50,66-101` seeds default cursor style through terminal init options.

### Reports, ABI, render publication, and host cadence

- `howl-vt/src/report.zig:18-36,47-74,91-92,107-120,141-167,201-208,226-264` owns cursor reports: CPR, DECXCPR, DECRQSS `" q"`, and DECCIR payload assembly.
- `howl-vt/src/ffi/lifecycle.zig:15-35,42-47` translates FFI init cursor-style options into VT state.
- `howl-vt/src/ffi/surface.zig:91-120,220-257` owns the shipped VT surface cursor ABI through `FfiCursor`, `cursor_color`, `cursor_text_color`, and `extra_cursor_count`.
- `howl-vt/include/howl_vt.h` is the shipped C ABI header and therefore part of the cursor contract surface whenever cursor enum or struct fields change.
- `howl-render/src/vt_publication/abi.zig:16-21,36-51,106-140` owns the render-side accepted VT cursor ABI. Current main-cursor shape cannot represent Kitty `NO_CURSOR_SHAPE`; `SourceCursorShape` only accepts `block`, `underline`, `beam`, `hollow_block`.
- `howl-render/src/vt_publication/publication.zig:100-129,131-173` copies VT-published cursor truth into render-owned `PublicationSource`.
- `howl-render/src/vt_publication/source_slot.zig:110-135` owns retained-source copies of published cursor truth.
- `howl-render/src/vt_publication/cursor.zig:33-39,67-115,142-158` maps VT cursor truth into render presentation. Presentation already has `none`, but current VT ABI cannot produce it.
- `howl-render/src/vt_publication/text_input.zig:232-237` threads cursor presentation into text scene input.
- `howl-render/src/vt_publication/damage.zig` and `howl-render/src/vt_publication/prepare_queue.zig` are part of the current render publication consequence spine for cursor-only damage and preparation sequencing.
- `howl-render/src/text/scene_rects.zig:334-390` owns cursor draw and recolor primitives.
- `howl-linux-host/src/terminal/vt_surface.zig:56-71` copies VT cursor visibility and blink into host-retained state.
- `howl-linux-host/src/terminal/surface.zig:155-166,224-239,396-423,777-856` owns host cursor cadence consumption, focus and unfocused presentation, blink visibility, and trail policy.
- `howl-linux-host/src/terminal/cursor_blink.zig:17-22,40-162` owns host blink timing and easing only.

### Current proof roots

- `howl-vt/test/unit/screen/cursor_test.zig:9-132`
- `howl-vt/test/unit/csi_mapping_test.zig:291-304`
- `howl-vt/test/unit/terminal_surface_test.zig:207-219,575-586`
- `howl-vt/test/unit/terminal_snapshot_test.zig:15-205`
- `howl-vt/test/unit/terminal_modes_test.zig:494-560,660-680`
- `howl-vt/test/unit/terminal_end_to_end_test.zig:31-43`
- `howl-vt/test/abi.zig:53-67`
- `howl-render/src/vt_publication/cursor.zig:228-307`
- `howl-render/src/vt_publication/publication.zig:100-173,449-476`
- `howl-render/src/vt_publication/source_slot.zig:508-539`
- `howl-render/src/vt_publication/abi.zig:177-199`
- `howl-linux-host/src/terminal/surface_test.zig:376-414,1309-1359`

### Current-state severity verdict

- Current Howl cursor truth is split across parser, screen, screen-set, mode, report, FFI, render, and host seams, with two incompatible save/restore owners and no Kitty-grade savepoint payload.
- Current VT and render ABI cannot represent Kitty no-shape explicitly end-to-end.
- Current host and render consequence surfaces are cursor-adjacent enough that full Kitty parity cannot be closed in one isolated VT-only step without leaving the sprint fake-finished.

## Kitty Source Map

### Parse and dispatch anchors

- `utils/dev_references/terminals/kitty/kitty/vt-parser.c:1271-1272,1314-1315` dispatches parsed save/restore commands to `screen_save_cursor` and `screen_restore_cursor`.
- `utils/dev_references/terminals/kitty/kitty/vt-parser.c:1359-1369` dispatches `DECSCUSR`.
  `CSI Ps SP q` goes to `screen_set_cursor`.
  `CSI > ... SP q` is Kitty multiple cursors and adjacent, not part of the remaining main-cursor sprint.

### Alt-screen, visibility, savepoint, and style behavior

- `utils/dev_references/terminals/kitty/kitty/screen.c:1624-1659` defines Kitty alt-screen cursor behavior in `screen_toggle_screen_buffer`.
  On alt enter:
  optional clear,
  optional `screen_save_cursor`,
  switch buffers,
  `screen_cursor_position(self, 1, 1)`,
  `cursor_reset(self->cursor)`.
  On return to main:
  optional `screen_restore_cursor`.
  Kitty does not copy the main cursor into alt.
- `utils/dev_references/terminals/kitty/kitty/screen.c:1729,1734-1735` ties that behavior to DEC private alt-screen mode handling.
- `utils/dev_references/terminals/kitty/kitty/screen.c:2002-2004` defines cursor visibility truth in `screen_is_cursor_visible`.
- `utils/dev_references/terminals/kitty/kitty/screen.c:2265-2273` defines the Kitty savepoint payload in `screen_save_cursor`: copied `Cursor`, `mDECOM`, `mDECAWM`, `mDECSCNM`, `charset`, `is_valid`.
- `utils/dev_references/terminals/kitty/kitty/screen.c:2349-2364` defines restore behavior in `screen_restore_cursor`.
  Without prior save:
  move to `1,1`,
  reset `DECOM`,
  reset `DECSCNM`,
  zero charset.
  With prior save:
  restore `DECOM`,
  restore `DECAWM`,
  restore `DECSCNM`,
  restore copied `Cursor`,
  restore charset,
  clamp with `screen_ensure_bounds`.
- `utils/dev_references/terminals/kitty/kitty/screen.c:2954-2969` defines `DECSCUSR` mapping in `screen_set_cursor`:
  `0/1` blinking block,
  `2` steady block,
  `3` blinking underline,
  `4` steady underline,
  `5` blinking beam,
  `6` steady beam,
  `>=7` `NO_CURSOR_SHAPE`.
- `utils/dev_references/terminals/kitty/kitty/screen.c:3310-3325` defines DECRQSS `" q"` reporting:
  `NO_CURSOR_SHAPE`, `CURSOR_HOLLOW`, and invalid states report as `1`;
  blinking block reports `0`;
  steady block `2`;
  underline `3/4`;
  beam `5/6`.

### Cursor data-shape anchors

- `utils/dev_references/terminals/kitty/kitty/cursor.c:249-260` defines `cursor_reset` and `cursor_copy_to`.
  `cursor_reset` sets `x=0`, `y=0`, `shape=NO_CURSOR_SHAPE`, `non_blinking=false`, and resets display attrs.
  `cursor_copy_to` copies `x`, `y`, `shape`, `non_blinking`, and full `sgr`.
- `utils/dev_references/terminals/kitty/kitty/data-types.h:76` defines the cursor-shape enum: `NO_CURSOR_SHAPE`, `CURSOR_BLOCK`, `CURSOR_BEAM`, `CURSOR_UNDERLINE`, `CURSOR_HOLLOW`.
- `utils/dev_references/terminals/kitty/kitty/data-types.h:303-314` exports `cursor_reset`, `cursor_copy`, `cursor_copy_to`, and `cursor_as_sgr`.
- `utils/dev_references/terminals/kitty/kitty/screen.h:194-205,219-256,294-295` is the public screen-owner seam: `screen_save_cursor`, `screen_restore_cursor`, `screen_toggle_screen_buffer`, `screen_set_cursor`, `screen_is_cursor_visible`.

### Adjacent but still parity-relevant anchors

- `utils/dev_references/terminals/kitty/kitty/window.py:441-452` shows Kitty’s cursor replay and export surface: emit `?25h/l`, cursor position, `?12h/l` when shape is `NO_CURSOR_SHAPE`, otherwise `CSI Ps SP q`.
- `utils/dev_references/terminals/kitty/kitty/window.py:1737-1742` defines GUI-side restore of default cursor appearance. This is host and UI adjacent and relevant to remaining host cadence and presentation parity boundaries even though it is not VT-core savepoint truth.
- `utils/dev_references/terminals/kitty/kitty_tests/parser.py:778-780` is direct parser proof for `DECSCUSR`.
- `utils/dev_references/terminals/kitty/kitty/terminfo.py:285-288` is protocol naming only: `Ss` for set cursor style and `Se` for reset cursor style.

## Full Remaining Parity Surface Map

- Surface A: VT savepoint payload parity.
  Remaining because current Howl still saves only `row`, `col`, and `wrap_pending` in `howl-vt/src/screen/cursor.zig:107-120`, while Kitty savepoints include copied cursor state, `DECOM`, `DECAWM`, `DECSCNM`, and charset at `kitty/screen.c:2265-2273`.
- Surface B: restore-without-save parity.
  Remaining because current Howl restore uses local saved state only and has no Kitty-like invalid-save behavior. Kitty resets to `1,1`, resets `DECOM`, resets `DECSCNM`, and zeroes charset at `kitty/screen.c:2349-2356`.
- Surface C: alt-screen parity for `47`, `1047`, and `1049`.
  Remaining because current Howl keeps copied-primary semantics in `howl-vt/src/screen_set.zig:127-159`, while Kitty resets the alt cursor on enter and does not copy the main cursor into alt at `kitty/screen.c:1624-1659`.
- Surface D: main-cursor no-shape parity.
  Remaining because current VT and render source ABI cannot represent Kitty `NO_CURSOR_SHAPE` explicitly from `kitty/screen.c:2961-2968` and `kitty/data-types.h:76`.
- Surface E: DECRQSS `" q"` parity.
  Remaining because current Howl reports block `1/2` and does not model Kitty no-shape report-as-`1` or blinking-block report-as-`0` from `kitty/screen.c:3310-3325`.
- Surface F: public ABI parity.
  Remaining because `howl-vt/include/howl_vt.h` and `howl-vt/src/ffi/surface.zig` must carry explicit no-shape truth through the shipped C ABI.
- Surface G: render publication parity.
  Remaining because `howl-render/src/vt_publication/abi.zig`, `publication.zig`, `source_slot.zig`, `cursor.zig`, `text_input.zig`, `damage.zig`, and `prepare_queue.zig` must preserve explicit no-shape and cursor-only damage consequences through the retained render pipeline.
- Surface H: draw-owner parity.
  Remaining because `howl-render/src/text/scene_rects.zig` must prove visible no-shape produces no cursor draws without collapsing visibility semantics.
- Surface I: host consumption parity.
  Remaining because `howl-linux-host/src/terminal/vt_surface.zig` and `howl-linux-host/src/terminal/surface.zig` must consume widened shape truth and Kitty-style `1049` without inventing fallback VT behavior.
- Surface J: proof-surface parity.
  Remaining because current curated tests prove stale owners and copied-primary behavior. The whole sprint must replace those proofs with Kitty-first owner and behavior proofs before coding is authorized.

## Exact Full-Sprint Slice Sequence From This Point On

- Slice 1: VT savepoint and alt-screen rewrite.
- Slice 2: shipped VT ABI and render publication widening for explicit no-shape.
- Slice 3: render draw and host consumption closure.
- Slice 4: sprint-wide proof and artifact closeout pass.

## Slice 1: VT Savepoint And Alt-Screen Rewrite

### Exact goal

- Replace stale screen-local and screen-set-local cursor save/restore owners with terminal-owned Kitty-like savepoints.
- Port Kitty behavior for `ESC 7/8`, `CSI s/u`, `47`, `1047`, `1049`, restore-without-save, and DECRQSS `" q"` at the VT owner boundary.
- Make no-shape first-class VT truth even before ABI widening reaches render and host consumers.

### Exact files

- `howl-vt/src/vocabulary.zig`
- `howl-vt/src/csi_intermediate.zig`
- `howl-vt/src/csi_plain.zig`
- `howl-vt/src/csi_private.zig`
- `howl-vt/src/esc.zig`
- `howl-vt/src/route.zig`
- `howl-vt/src/mode.zig`
- `howl-vt/src/screen/cursor.zig`
- `howl-vt/src/screen.zig`
- `howl-vt/src/screen/apply.zig`
- `howl-vt/src/screen_set.zig`
- `howl-vt/src/terminal.zig`
- `howl-vt/src/terminal/savepoint.zig`
- `howl-vt/src/report.zig`
- `howl-vt/test/unit/csi_mapping_test.zig`
- `howl-vt/test/unit/screen/cursor_test.zig`
- `howl-vt/test/unit/terminal_cursor_test.zig`
- `howl-vt/test/unit/terminal_surface_test.zig`
- `howl-vt/test/unit/terminal_modes_test.zig`
- `howl-vt/test/unit/terminal_snapshot_test.zig`
- `howl-vt/test/support/screen_capture.zig`
- `howl-vt/test/unit/terminal_end_to_end_test.zig`

### Exact proof roots

- `howl-vt/test/unit/csi_mapping_test.zig`
- `howl-vt/test/unit/screen/cursor_test.zig`
- `howl-vt/test/unit/terminal_cursor_test.zig`
- `howl-vt/test/unit/terminal_surface_test.zig`
- `howl-vt/test/unit/terminal_modes_test.zig`
- `howl-vt/test/unit/terminal_snapshot_test.zig`
- `howl-vt/test/support/screen_capture.zig`
- `howl-vt/test/unit/terminal_end_to_end_test.zig`
- `howl-vt/src/report.zig` inline tests

### Exact non-goals

- Public C ABI widening.
- Render publication wiring.
- Host cadence consumption changes.
- Multiple cursors.
- Pointer cursor shape.
- Cursor trail redesign.

### Exact stop conditions

- Stop if implementation preserves current copied-primary alt-screen semantics.
- Stop if savepoint truth remains screen-owned instead of terminal-owned.
- Stop if restore-without-save does not match Kitty behavior.
- Stop if visibility or cursor colors enter the savepoint payload.
- Stop if DECRQSS `" q"` remains xterm-like instead of Kitty-like.

## Slice 2: Shipped VT ABI And Render Publication Widening

### Exact goal

- Carry explicit Kitty no-shape through the shipped VT C ABI and across all active render publication owners without reinterpretation.
- Preserve cursor-only damage and preparation semantics through the active render publication path.

### Exact files

- `howl-vt/src/ffi/lifecycle.zig`
- `howl-vt/src/ffi/surface.zig`
- `howl-vt/include/howl_vt.h`
- `howl-vt/test/abi.zig`
- `howl-render/src/vt_publication/abi.zig`
- `howl-render/src/vt_publication/publication.zig`
- `howl-render/src/vt_publication/source_slot.zig`
- `howl-render/src/vt_publication/cursor.zig`
- `howl-render/src/vt_publication/text_input.zig`
- `howl-render/src/vt_publication/damage.zig`
- `howl-render/src/vt_publication/prepare_queue.zig`

### Exact proof roots

- `howl-vt/test/abi.zig`
- `howl-vt/src/ffi/lifecycle.zig` inline tests
- `howl-vt/src/ffi/surface.zig` inline tests
- `howl-render/src/vt_publication/abi.zig` inline tests
- `howl-render/src/vt_publication/publication.zig` inline tests
- `howl-render/src/vt_publication/source_slot.zig` inline tests
- `howl-render/src/vt_publication/cursor.zig` inline tests
- `howl-render/src/vt_publication/text_input.zig` inline tests
- `howl-render/src/vt_publication/damage.zig` inline tests
- `howl-render/src/vt_publication/prepare_queue.zig` inline tests

### Exact non-goals

- Rewriting VT savepoint ownership again.
- Host cadence consumption changes.
- Render draw primitive changes.
- Pointer cursor shape.
- Multiple cursors.

### Exact stop conditions

- Stop if no-shape is collapsed into hidden visibility or inferred block style.
- Stop if ABI widening is done in Zig only and not in `howl-vt/include/howl_vt.h`.
- Stop if render publication adds policy instead of preserving VT truth.
- Stop if cursor-only damage handling regresses into full-scene fallback without proof.

## Slice 3: Render Draw And Host Consumption Closure

### Exact goal

- Close the remaining cursor parity consequences in the active draw owner and host consumer owners.
- Prove visible no-shape draws nothing while preserving visibility semantics.
- Prove Kitty-style `1049` and widened cursor shape propagate correctly into host cadence consumption without host-side VT reinterpretation.

### Exact files

- `howl-render/src/text/scene_rects.zig`
- `howl-linux-host/src/terminal/vt_surface.zig`
- `howl-linux-host/src/terminal/surface.zig`
- `howl-linux-host/src/terminal/surface_test.zig`

### Exact proof roots

- `howl-render/src/text/scene_rects.zig` inline tests
- `howl-linux-host/src/terminal/vt_surface.zig` inline tests
- `howl-linux-host/src/terminal/surface_test.zig`

### Exact non-goals

- New host runtime abstractions.
- Cursor trail redesign.
- Shell integration behavior.
- Pointer cursor shape.
- Multiple cursors.

### Exact stop conditions

- Stop if host code invents fallback VT semantics for no-shape or `1049`.
- Stop if host or render collapses no-shape into hidden instead of preserving visible no-draw truth.
- Stop if draw-owner changes leak back into VT ownership.

## Slice 4: Sprint-Wide Proof And Artifact Closeout Pass

### Exact goal

- Re-run and tighten the full curated proof surface for the sprint.
- Remove stale proof expectations and ensure the active planning artifacts can gate the whole sprint end-to-end.
- Produce final accountability receipts for reviewer acceptance of the full sprint, not just one implementation pass.

### Exact files

- `research/2026-06-15-cursor-kitty-full-sprint-plan.md`
- `sprints/current.txt`
- `loops/cursor-kitty-slice-1-vt-savepoint-and-alt-screen.txt`

### Exact proof roots

- Whole-sprint verification logs for:
  `zig build test:unit` in `howl-vt`
  `zig build test:abi` in `howl-vt`
  `zig build test` in `howl-render`
  `timeout 300s zig build test:unit` in `howl-linux-host`

### Exact non-goals

- Any new code changes outside reviewer-requested fixups revealed by the full proof run.
- New behavior slices.

### Exact stop conditions

- Stop if any slice still depends on unauthorized prior coder work rather than the accepted slice receipts from this full sprint.
- Stop if any active artifact still authorizes coding before full reviewer acceptance of the sprint package.
- Stop if any proof root remains vague, conditional, or category-only.

## Sprint-Level Invariants Across All Remaining Slices

- Save and restore is terminal-owned, not screen-owned.
- Alt-screen cursor consequences follow Kitty semantics, not copied-primary semantics.
- No-shape is explicit shape truth, not collapsed hidden visibility.
- Cursor visibility and cursor colors are not part of the savepoint payload.
- Render and host remain consumers only.
- FFI translates contracts only.
- Public C ABI is the product and must change wherever cursor contract truth changes.
- Kitty parity is not weakened by Ghostty. Ghostty may only justify a cleaner owner split if the exact Kitty behavior remains intact.
- No slice may preserve stale cursor owners, stale file seams, or stale tests for diff comfort.
- Every slice must remain accountable through exact files, exact proof roots, exact non-goals, and exact stop conditions.

## Delete/Replace/Leave-Unchanged Ledger For The Whole Remaining Sprint

### Delete outright

- Delete `Screen.saved_cursor` from `howl-vt/src/screen.zig:77-80,134`.
- Delete `CursorSnapshot` and `saved_primary_cursor` from `howl-vt/src/screen_set.zig:79-92`.
- Delete the stale alt-screen cursor save and restore logic in `howl-vt/src/screen_set.zig:127-159`.

### Replace

- Replace the save and restore policy in `howl-vt/src/screen/cursor.zig:107-120`.
- Replace `howl-vt/src/screen.zig:378-383` forwarding behavior so save and restore no longer depend on the stale local payload.
- Replace cursor semantic enums and style mapping in `howl-vt/src/vocabulary.zig` and parser dispatch in `howl-vt/src/csi_intermediate.zig`.
- Replace `1049` behavior proof and implementation in `howl-vt/src/mode.zig` and `howl-vt/src/screen_set.zig`.
- Replace DECRQSS `" q"` report behavior in `howl-vt/src/report.zig:141-167`.
- Replace shipped VT cursor ABI shape handling in `howl-vt/src/ffi/surface.zig:91-120,239-251`.
- Replace render-side cursor source enum handling in `howl-render/src/vt_publication/abi.zig:16-21,121-126` and all direct consumers.
- Replace host consumption assumptions in `howl-linux-host/src/terminal/surface.zig` where widened shape and Kitty-style `1049` require different consequences.

### Leave consumer-only

- Leave `howl-render/src/vt_publication/publication.zig` consumer-only.
- Leave `howl-render/src/vt_publication/source_slot.zig` consumer-only.
- Leave `howl-render/src/vt_publication/cursor.zig` consumer-only.
- Leave `howl-render/src/vt_publication/text_input.zig` consumer-only.
- Leave `howl-render/src/vt_publication/damage.zig` consumer-only.
- Leave `howl-render/src/vt_publication/prepare_queue.zig` consumer-only.
- Leave `howl-render/src/text/scene_rects.zig` as draw-owner only.
- Leave `howl-linux-host/src/terminal/vt_surface.zig` consumer-only.
- Leave `howl-linux-host/src/terminal/surface.zig` host-consumer only.
- Leave `howl-linux-host/src/terminal/cursor_blink.zig` host-policy only.

### Leave unchanged unless reviewer discovers proof-backed debt outside this sprint

- `howl-linux-host/src/config/terminal.zig`
- non-cursor host runtime owners outside `howl-linux-host/src/terminal/vt_surface.zig` and `surface.zig`
- non-cursor render owners outside the explicit file lists above

## Exact Review Gates For The Whole Sprint

- Gate 1: source fidelity.
  Reviewer must reject any slice that diverges from Kitty source anchors for savepoint payload, restore-without-save, alt-screen behavior, `DECSCUSR`, and DECRQSS `" q"` without an explicit user override receipt.
- Gate 2: owner truth.
  Reviewer must reject any slice that leaves savepoint truth screen-owned, screen-set-owned, or host-owned.
- Gate 3: ABI truth.
  Reviewer must reject any slice that changes Zig-side cursor ABI without matching `howl-vt/include/howl_vt.h` and full proof roots.
- Gate 4: consumer-only discipline.
  Reviewer must reject any slice where render or host invent VT policy.
- Gate 5: proof completeness.
  Reviewer must reject any slice that uses category-level test language, conditional proof scope, or missing proof roots.
- Gate 6: sprint-sequence discipline.
  Reviewer must reject any coding attempt that skips ahead to later slices or broadens into unrelated Kitty features.
- Gate 7: closeout discipline.
  Reviewer must not accept the sprint as complete until all four slices are implemented, all listed proof roots pass, and active planning artifacts are updated with exact receipts.

## Coding Authorization Status

- No coding is authorized from this artifact until the reviewer accepts the full sprint artifact.
- `sprints/current.txt` and any execution loop artifact must be rewritten after reviewer acceptance so the whole remaining sprint, not a single slice, becomes the live authority.
