# Cursor Kitty Restart Plan

## Receipt Header

- Artifact owner: `research/2026-06-15-cursor-kitty-restart-plan.md`
- Orchestrator session id: `orch-2026-06-15-cursor-restart-01`
- Researcher session id: `ses_135074a6bffeuLKDxy30qK2cAL`
- Reviewer session id: `ses_13508b5e7ffe0XZUyUcJd4EPEs`
- Source loop artifact: `loops/cursor-kitty-port-pre-research.txt`
- Artifact status: worker-ready planning package proposal from blank-state restart
- Commit-hash receipt status: no planning commit recorded in this artifact

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
  3. Alacritty host/render organization.
  4. TigerBeetle ownership, assertions, source order, and tests.
  5. Ghostty fallback only for ownership cleanliness if Kitty parity is otherwise impossible to model cleanly.
  6. Official docs for protocol facts.
- This artifact intentionally overrides the default VT-first Ghostty pressure in `reference-index.md:19-25,71-107` and `AGENTS.md:226-249` for this cursor slice only.
- Override reason: the user explicitly set Kitty parity as primary for cursor work in `loops/cursor-kitty-port-pre-research.txt:14-40`.

## Resolved User Decisions

- Decision 1: alt-screen semantics are Kitty.
- Decision 2: save/restore payload is Kitty-like payload.
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
- `howl-render/src/vt_publication/abi.zig:16-21,36-51,106-140` owns the render-side accepted VT cursor ABI. Current main-cursor shape cannot represent Kitty `NO_CURSOR_SHAPE`; `SourceCursorShape` only accepts `block`, `underline`, `beam`, `hollow_block`.
- `howl-render/src/vt_publication/publication.zig:100-129,131-173` copies VT-published cursor truth into render-owned `PublicationSource`.
- `howl-render/src/vt_publication/source_slot.zig:110-135` owns retained-source copies of published cursor truth.
- `howl-render/src/vt_publication/cursor.zig:33-39,67-115,142-158` maps VT cursor truth into render presentation. Presentation already has `none`, but current VT ABI cannot produce it.
- `howl-render/src/vt_publication/text_input.zig:232-237` threads cursor presentation into text scene input.
- `howl-render/src/text/scene_rects.zig:334-390` owns cursor draw and recolor primitives.
- `howl-linux-host/src/terminal/vt_surface.zig:56-71` copies VT cursor visibility and blink into host-retained state.
- `howl-linux-host/src/terminal/surface.zig:155-166,224-239,396-423,777-856` owns host cursor cadence consumption, focus/unfocused presentation, blink visibility, and trail policy.
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

- Current Howl cursor truth is split across parser, screen, screen-set, mode, report, FFI, render, and host seams, with two incompatible save/restore owners and no Kitty-grade savepoint payload. The shape is stale and must be replaced rather than preserved.

## Kitty Source Map

### Parse and dispatch anchors

- `utils/dev_references/terminals/kitty/kitty/vt-parser.c:1271-1272,1314-1315` dispatches parsed save/restore commands to `screen_save_cursor` and `screen_restore_cursor`.
- `utils/dev_references/terminals/kitty/kitty/vt-parser.c:1359-1369` dispatches `DECSCUSR`.
  `CSI Ps SP q` goes to `screen_set_cursor`.
  `CSI > ... SP q` is Kitty multiple cursors and adjacent, not required for the main-cursor restart.

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

### Adjacent but non-primary anchors

- `utils/dev_references/terminals/kitty/kitty/window.py:441-452` shows Kitty’s cursor replay/export surface: emit `?25h/l`, cursor position, `?12h/l` when shape is `NO_CURSOR_SHAPE`, otherwise `CSI Ps SP q`.
- `utils/dev_references/terminals/kitty/kitty/window.py:1737-1742` defines GUI-side restore of default cursor appearance. This is host/UI-adjacent, not VT-core savepoint truth.
- `utils/dev_references/terminals/kitty/kitty_tests/parser.py:778-780` is direct parser proof for `DECSCUSR`.
- `utils/dev_references/terminals/kitty/kitty/terminfo.py:285-288` is protocol naming only: `Ss` for set cursor style and `Se` for reset cursor style.

## Exact Behavior Contract To Port

- In-scope protocol surface:
  `ESC 7`,
  `ESC 8`,
  `CSI s`,
  `CSI u`,
  `CSI Ps SP q`,
  `CSI ? 25 h/l`,
  `CSI ? 47 h/l`,
  `CSI ? 1047 h/l`,
  `CSI ? 1049 h/l`,
  DECRQSS `" q"`.
- `DECSCUSR` must match Kitty exactly:
  `0/1` blinking block,
  `2` steady block,
  `3` blinking underline,
  `4` steady underline,
  `5` blinking beam,
  `6` steady beam,
  `>=7` no-shape.
- Savepoint payload must be Kitty-like:
  cursor position,
  cursor shape/no-shape,
  steady/blinking bit,
  pen/current display attrs,
  origin mode,
  auto-wrap mode,
  charset,
  valid bit,
  distinct savepoint per main and alt screen bank.
- Cursor visibility must not be saved in the Kitty-like savepoint payload.
- Cursor colors must not be saved in the Kitty-like savepoint payload.
- Restore without prior save must be Kitty behavior:
  move to `1,1`,
  reset origin mode,
  zero charset state.
- Alt-screen behavior must be Kitty:
  `47` switch only, no clear, no save/restore.
  `1047` clear alt on enter, no save/restore.
  `1049` clear alt on enter and save/restore through the Kitty-like savepoint.
  Alt enter resets active alt cursor instead of copying the main cursor into alt.
- DECRQSS `" q"` reporting must match Kitty:
  no-shape reports as `1`,
  blinking block as `0`,
  steady block `2`,
  underline `3/4`,
  beam `5/6`.
- Shipped host-facing surface ABI must expose main cursor shape exactly, including no-shape.
- Render consumption must treat no-shape as an explicit shape, not implicit invisibility.
- Host cadence remains host policy, but must consume the widened shape and new save/restore consequences correctly.

## Exact Post-Port Owner/File Split

- `howl-vt/src/csi_intermediate.zig`, `csi_plain.zig`, `esc.zig`, `csi_private.zig` stay parser consequence owners only.
- `howl-vt/src/vocabulary.zig` stays the semantic contract owner, but its cursor event space must widen to represent Kitty no-shape exactly.
- `howl-vt/src/screen/cursor.zig` should survive only as the active cursor-state owner:
  cursor coordinates,
  cursor shape including no-shape,
  blink and steady bit,
  visibility,
  cursor colors,
  client-movement counter.
  It must stop owning save/restore payload policy.
- `howl-vt/src/terminal/savepoint.zig` should be added as the new Kitty-savepoint owner.
  It should own:
  copied cursor state,
  copied pen/current display attrs,
  saved origin mode,
  saved auto-wrap mode,
  saved charset state,
  valid bit,
  separate primary and alternate savepoints.
- `howl-vt/src/terminal.zig` should own invoking that savepoint owner because current charset truth is terminal-owned at `howl-vt/src/terminal.zig:31-34`.
- `howl-vt/src/screen.zig` should keep active screen mutation and pen mutation only. `saved_cursor` must be removed.
- `howl-vt/src/screen_set.zig` should own only screen switching and visible-view projection. `CursorSnapshot` and `saved_primary_cursor` must be deleted.
- `howl-vt/src/mode.zig` should keep only DEC mode routing for `?25`, `47`, `1047`, `1049`.
- `howl-vt/src/report.zig` should remain the owner of cursor reports, but it must emit Kitty semantics for DECRQSS `" q"`.
- `howl-vt/src/ffi/lifecycle.zig` and `howl-vt/src/ffi/surface.zig` must remain translation-only.
- `howl-render/src/vt_publication/abi.zig` must widen main-cursor source shape to represent Kitty no-shape exactly.
- `howl-render/src/vt_publication/publication.zig`, `source_slot.zig`, and `cursor.zig` remain consumer-only and must carry the widened shape unchanged.
- `howl-render/src/text/scene_rects.zig` remains the draw owner. `none` must stay a draw no-op, not a VT policy shim.
- `howl-linux-host/src/terminal/vt_surface.zig` and `surface.zig` remain host consumers only: focus policy, unfocused-shape substitution, blink cadence, trail policy.

## Exact Delete/Replace/Leave-Unchanged Ledger

### Delete outright

- Delete `Screen.saved_cursor` from `howl-vt/src/screen.zig:77-80,134`.
- Delete `CursorSnapshot` and `saved_primary_cursor` from `howl-vt/src/screen_set.zig:79-92`.
- Delete the stale alt-screen cursor save/restore logic in `howl-vt/src/screen_set.zig:127-159`.

### Replace

- Replace the save/restore policy in `howl-vt/src/screen/cursor.zig:107-120`.
- Replace `howl-vt/src/screen.zig:378-383` forwarding behavior so save/restore no longer depends on the stale local payload.
- Replace cursor semantic enums and style mapping in `howl-vt/src/vocabulary.zig` and parser dispatch in `howl-vt/src/csi_intermediate.zig`.
- Replace `1049` behavior proof and implementation in `howl-vt/src/mode.zig` and `howl-vt/src/screen_set.zig`.
- Replace DECRQSS `" q"` report behavior in `howl-vt/src/report.zig:141-167`.
- Replace shipped VT cursor ABI shape handling in `howl-vt/src/ffi/surface.zig:91-120,239-251`.
- Replace render-side cursor source enum handling in `howl-render/src/vt_publication/abi.zig:16-21,121-126` and consumers.

### Leave consumer-only

- Leave `howl-render/src/vt_publication/publication.zig` consumer-only.
- Leave `howl-render/src/vt_publication/source_slot.zig` consumer-only.
- Leave `howl-render/src/vt_publication/cursor.zig` consumer-only.
- Leave `howl-render/src/text/scene_rects.zig` consumer-only.
- Leave `howl-linux-host/src/terminal/vt_surface.zig` consumer-only.
- Leave `howl-linux-host/src/terminal/surface.zig` consumer-only.
- Leave `howl-linux-host/src/terminal/cursor_blink.zig` host-policy only.

### Leave unchanged unless proof forces translation edits

- `howl-linux-host/src/config/terminal.zig`
- `howl-vt/src/ffi/lifecycle.zig` public init option semantics other than widened shape translation if required

## Exact ABI/Publication/Host Impact

### ABI impact

- The shipped VT cursor ABI in `howl-vt/src/ffi/surface.zig` must widen main cursor shape to represent Kitty no-shape exactly.
- The render publication ABI in `howl-render/src/vt_publication/abi.zig` must accept that widened main cursor shape.
- FFI init style translation in `howl-vt/src/ffi/lifecycle.zig` must continue honoring default cursor shape and blink semantics after the rewrite.

### Publication impact

- `howl-vt/src/screen_set.zig` visible-view export must publish the rewritten cursor truth without preserving stale savepoint owners.
- `howl-render/src/vt_publication/publication.zig` and `source_slot.zig` must preserve no-shape and updated main cursor truth across owned and retained copies.
- `howl-render/src/vt_publication/cursor.zig` must map the widened main cursor shape to presentation `none` when Kitty no-shape is active.
- `howl-render/src/vt_publication/text_input.zig` is in-scope because it threads publication cursor truth into scene input at `howl-render/src/vt_publication/text_input.zig:232-237`. The widened main cursor shape must be proved across this active render input seam rather than left half-decided.

### Host impact

- `howl-linux-host/src/terminal/vt_surface.zig` must continue copying visibility and blink while tolerating widened shape values.
- `howl-linux-host/src/terminal/surface.zig` must consume Kitty-style `1049` and no-shape without inventing fallback VT behavior.
- Host blink cadence remains host-owned and must not be moved into VT.

## Exact Proof Plan

- Update `howl-vt/test/unit/csi_mapping_test.zig` to prove `ESC 7/8`, `CSI s/u`, `DECSCUSR 0..6`, and `DECSCUSR >= 7`.
- Replace `howl-vt/test/unit/screen/cursor_test.zig` with active-cursor-owner proof only: no-shape state, blink and steady state, movement counter, visibility mutation, cursor colors staying outside savepoint payload.
- Add `howl-vt/test/unit/terminal_cursor_test.zig` as the main savepoint and terminal proof root:
  savepoint round-trip,
  restore-without-save,
  `47`,
  `1047`,
  `1049`,
  alt enter resets cursor instead of copying it,
  pen/current attrs round-trip,
  charset round-trip,
  auto-wrap round-trip,
  origin round-trip.
- Update `howl-vt/test/unit/terminal_surface_test.zig:207-219` to prove Kitty `1049` behavior instead of current copied-cursor behavior.
- Keep and update `howl-vt/test/unit/terminal_surface_test.zig:575-586` as required proof scope because exported live-viewport cursor suppression is part of the current shipped VT surface behavior and this slice changes the cursor owner and publication path that feed it.
- Update `howl-vt/test/unit/terminal_modes_test.zig:494-560,660-680` to prove DECRQSS `" q"` and DECRQM visibility state against the new owners.
- Update `howl-vt/test/unit/terminal_snapshot_test.zig` and `howl-vt/test/support/screen_capture.zig` as required proof roots because this slice changes the active cursor owner and savepoint behavior that snapshot and direct-screen capture currently prove.
- Update `howl-vt/test/abi.zig` and `howl-vt/src/ffi/lifecycle.zig` tests to prove init and default-style behavior still holds after the owner rewrite.
- Update `howl-vt/include/howl_vt.h` proof through `howl-vt/test/abi.zig` because the shipped VT cursor ABI contract changes and the public header is part of the product surface.
- Update `howl-vt/src/ffi/surface.zig` tests to prove exported cursor shape can represent Kitty no-shape.
- Update `howl-render/src/vt_publication/abi.zig` tests to prove widened main-cursor enum acceptance and rejection bounds.
- Update `howl-render/src/vt_publication/publication.zig` and `source_slot.zig` tests to prove no-shape survives owned-source and retained-slot boundaries.
- Update `howl-render/src/vt_publication/cursor.zig` tests to prove no-shape maps to presentation `none`.
- Update `howl-render/src/vt_publication/text_input.zig` tests to prove publication cursor truth, including no-shape, is threaded unchanged into scene input.
- Update `howl-render/src/text/scene_rects.zig` as required proof scope to prove that visible Kitty no-shape produces no cursor draws without collapsing visibility semantics in the active render draw owner.
- Update `howl-linux-host/src/terminal/surface.zig` because it is the active host consumer owner for Kitty-style `1049` and no-shape consequences at `howl-linux-host/src/terminal/surface.zig:155-166,396-423,777-856`.
- Update `howl-linux-host/src/terminal/surface_test.zig` to prove host cadence consumption remains correct with no-shape and with Kitty-style `1049`.

## Worker-Ready Slice Spec

### Slice identity

- Slice name: `cursor-kitty-restart-full-port`
- Slice class: single execution slice
- Reason: splitting VT, ABI, render, and host cursor consequences would preserve stale seams and create fake progress.

### Exact files allowed

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
- `howl-vt/src/ffi/lifecycle.zig`
- `howl-vt/src/ffi/surface.zig`
- `howl-vt/include/howl_vt.h`
- `howl-vt/test/unit/csi_mapping_test.zig`
- `howl-vt/test/unit/screen/cursor_test.zig`
- `howl-vt/test/unit/terminal_cursor_test.zig`
- `howl-vt/test/unit/terminal_surface_test.zig`
- `howl-vt/test/unit/terminal_modes_test.zig`
- `howl-vt/test/unit/terminal_snapshot_test.zig`
- `howl-vt/test/support/screen_capture.zig`
- `howl-vt/test/abi.zig`
- `howl-render/src/vt_publication/abi.zig`
- `howl-render/src/vt_publication/publication.zig`
- `howl-render/src/vt_publication/source_slot.zig`
- `howl-render/src/vt_publication/cursor.zig`
- `howl-render/src/vt_publication/text_input.zig`
- `howl-render/src/text/scene_rects.zig`
- `howl-linux-host/src/terminal/vt_surface.zig`
- `howl-linux-host/src/terminal/surface.zig`
- `howl-linux-host/src/terminal/surface_test.zig`

### Exact required shape

- Remove `Screen.saved_cursor`.
- Remove `screen_set.Set.CursorSnapshot`.
- Remove `screen_set.Set.saved_primary_cursor`.
- Add terminal-owned Kitty-like savepoints.
- Widen main-cursor shape to include no-shape across VT and render ABI.
- Keep render and host consumer-only.
- Preserve C ABI discipline while changing the shipped cursor enum contract only where required for Kitty parity.

### Exact proof roots required

- `howl-vt/test/unit/csi_mapping_test.zig`
- `howl-vt/test/unit/screen/cursor_test.zig`
- `howl-vt/test/unit/terminal_cursor_test.zig`
- `howl-vt/test/unit/terminal_surface_test.zig`
- `howl-vt/test/unit/terminal_modes_test.zig`
- `howl-vt/test/unit/terminal_snapshot_test.zig`
- `howl-vt/test/support/screen_capture.zig`
- `howl-vt/test/abi.zig`
- `howl-vt/src/ffi/lifecycle.zig` inline tests
- `howl-vt/src/ffi/surface.zig` inline tests
- `howl-render/src/vt_publication/abi.zig` inline tests
- `howl-render/src/vt_publication/publication.zig` inline tests
- `howl-render/src/vt_publication/source_slot.zig` inline tests
- `howl-render/src/vt_publication/cursor.zig` inline tests
- `howl-render/src/vt_publication/text_input.zig` inline tests
- `howl-render/src/text/scene_rects.zig` inline tests
- `howl-linux-host/src/terminal/vt_surface.zig` inline tests
- `howl-linux-host/src/terminal/surface_test.zig`

### Exact non-goals

- Kitty multiple cursors.
- Pointer cursor shape.
- Cursor trail redesign.
- Shell integration behavior.
- Non-cursor host runtime redesign.
- Convenience compatibility layers preserving stale Howl cursor owners.

### Exact stop conditions

- Stop if implementation preserves current copied-cursor alt-screen behavior.
- Stop if implementation keeps save/restore local to `Screen` while still needing terminal charset in the payload.
- Stop if implementation collapses no-shape into hidden.
- Stop if implementation saves cursor visibility or cursor colors in the savepoint payload.
- Stop if implementation broadens into unrelated Kitty features.
- Stop if Ghostty is used to weaken Kitty parity rather than only to justify a clean owner split.
