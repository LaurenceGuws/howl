# Cursor Kitty Restart Plan

Status:

- Active restart planning artifact.
- Purpose: replace the deleted stale cursor slice chain with a Kitty-first worker-ready restart plan.
- This artifact is planning authority only after reviewer acceptance.

Receipt Header:

- Orchestrator session id: `orch-2026-06-15-cursor-restart-01`.
- Researcher session id: `ses_135074a6bffeuLKDxy30qK2cAL`.
- Reviewer session id: `ses_13508b5e7ffe0XZUyUcJd4EPEs`.

Primary User Instruction:

- Rip out existing Howl cursor code and port Kitty's cursor code to Zig.

Cursor-Scoped Reference Receipt:

- Exact user decision: for cursor work, preserve full Kitty parity first; only if Kitty cursor behavior truly cannot be modeled without ownership blurring may Ghostty be consulted for ownership advice.
- Exact reference being overridden: `AGENTS.md` cursor-adjacent VT shape pressure that would otherwise prioritize Ghostty first for VT shape and `loops/cursor-kitty-port-pre-research.txt` reference order that listed Ghostty before Kitty for VT shape.
- Reason for override: the user explicitly directed replacement of existing Howl cursor code with Kitty cursor code, and explicitly constrained Ghostty to fallback advice only when needed to preserve full Kitty parity cleanly.
- Accountable orchestrator session id: `orch-2026-06-15-cursor-restart-01`.
- User approval receipt: recorded in live chat before this artifact was authored.

Resolved User Decisions:

- Alt-screen semantics: Kitty.
- Save/restore payload: Kitty-like payload.
- Restore without prior save: Kitty behavior.
- `DECSCUSR >= 7`: Kitty behavior.
- Ownership rule: Kitty parity first; Ghostty fallback only if needed to preserve full Kitty behavior without ownership blurring.

Current-State Owner Map:

- Parser dispatch owner: `howl-vt/src/stream_terminal.zig:156-219` applies parser actions into `route.apply`.
- CSI/ESC cursor parse owners:
  - `howl-vt/src/csi_intermediate.zig:102-108`
  - `howl-vt/src/csi_plain.zig:34-38`
  - `howl-vt/src/esc.zig:18-27,42-53`
  - `howl-vt/src/csi_private.zig:95-100`
  - `howl-vt/src/csi_params.zig:72-81`
- Semantic contract owner: `howl-vt/src/vocabulary.zig:81-97,153-156,234-237,294-302,362-364`.
- Semantic routing owner: `howl-vt/src/route.zig:144-152,216-217`.
- Stale cursor state owner: `howl-vt/src/screen/cursor.zig:4-92`.
- Stale per-screen save owner: `howl-vt/src/screen/cursor.zig:107-120`.
- Stale `Screen.saved_cursor` owner: `howl-vt/src/screen.zig:77-87,378-383`.
- Stale alt-screen cursor snapshot owner: `howl-vt/src/screen_set.zig:79-92,127-159`.
- DEC mode consequence owner: `howl-vt/src/mode.zig:146-170,184-189`.
- Terminal aggregate owner: `howl-vt/src/terminal.zig:18-37,48-50,66-101,154-182`.
- Report owner: `howl-vt/src/report.zig:18-36,47-74,141-167,201-208,226-264`.
- VT FFI translation owners:
  - `howl-vt/src/ffi/lifecycle.zig:15-35,42-47`
  - `howl-vt/src/ffi/surface.zig:91-120,220-257`
- Render publication translation owners:
  - `howl-render/src/vt_publication/abi.zig:16-21,36-51,106-140`
  - `howl-render/src/vt_publication/publication.zig:18-174`
  - `howl-render/src/vt_publication/source_slot.zig:110-135`
  - `howl-render/src/vt_publication/cursor.zig:67-115`
  - `howl-render/src/vt_publication/text_input.zig:232-237`
- Render cursor draw owner: `howl-render/src/text/scene_rects.zig:334-390`.
- Host VT consumption owners:
  - `howl-linux-host/src/terminal/vt_surface.zig:46-71,147-183`
  - `howl-linux-host/src/terminal/render_retained.zig:76-93,191-194,210-244`
  - `howl-linux-host/src/terminal/surface.zig:396-423,591-614,777-856`
  - `howl-linux-host/src/terminal/cursor_blink.zig:17-22,40-162`

Kitty Source Map:

- `utils/dev_references/terminals/kitty/kitty/vt-parser.c:1271-1272,1314-1315,1359-1369` for `ESC 7/8`, `CSI s/u`, `DECSCUSR` dispatch.
- `utils/dev_references/terminals/kitty/kitty/screen.c:1624-1659` for alt-screen cursor semantics.
- `utils/dev_references/terminals/kitty/kitty/screen.c:2265-2273,2349-2364` for savepoint payload and restore behavior.
- `utils/dev_references/terminals/kitty/kitty/screen.c:2002-2004` for cursor visibility truth.
- `utils/dev_references/terminals/kitty/kitty/screen.c:2954-2969` for `DECSCUSR` mapping.
- `utils/dev_references/terminals/kitty/kitty/screen.c:3310-3325` for DECRQSS `" q"` reporting.
- `utils/dev_references/terminals/kitty/kitty/cursor.c:249-260` for `cursor_reset` and `cursor_copy_to` payload behavior.
- `utils/dev_references/terminals/kitty/kitty/data-types.h:76,303-314` for exact cursor shape and copy/reset API truth.
- `utils/dev_references/terminals/kitty/kitty/child-monitor.c:702-742` for render-time blink/focus/text-blink behavior consumed by host/render layers.

Exact Behavior Contract To Port:

- Port Kitty semantics for:
  - `ESC 7`, `ESC 8`
  - `CSI s`, `CSI u`
  - `CSI Ps SP q`
  - `CSI ? 25 h/l`
  - `CSI ? 47 h/l`
  - `CSI ? 1047 h/l`
  - `CSI ? 1049 h/l`
  - DECRQSS `" q"`
- `DECSCUSR` mapping is exact:
  - `0` blinking block
  - `1` blinking block
  - `2` steady block
  - `3` blinking underline
  - `4` steady underline
  - `5` blinking beam
  - `6` steady beam
  - `>=7` no cursor shape
- Savepoint payload is Kitty-like and must include:
  - cursor coordinates
  - cursor shape/no-shape
  - cursor non-blinking flag
  - current pen/display attrs
  - origin mode
  - auto-wrap mode
  - charset state
  - valid bit
  - separate savepoint per screen bank
- Savepoint payload must not include:
  - cursor visibility
  - cursor colors
- Restore without prior save is Kitty behavior:
  - move to `1,1`
  - reset origin mode
  - zero charset state
  - no fake saved payload
- Alt-screen semantics are Kitty:
  - `47` switches without save/restore and without clear
  - `1047` clears alt on enter without save/restore
  - `1049` clears alt on enter and uses Kitty-like save/restore
  - entering alt resets alt cursor instead of copying primary cursor into alt
- DECRQSS `" q"` reporting is Kitty:
  - no-shape reports as `1`
  - blinking block reports `0`
  - steady block `2`
  - blinking underline `3`
  - steady underline `4`
  - blinking beam `5`
  - steady beam `6`

Exact Post-Port Owner/File Split:

- Add `howl-vt/src/terminal/savepoint.zig` as the Kitty-like savepoint owner.
- `howl-vt/src/terminal.zig` becomes owner of:
  - `saveCursor`
  - `restoreCursor`
  - `switchScreenMode`
  - per-screen savepoint orchestration
  - charset-coupled cursor save/restore consequences
- `howl-vt/src/screen/cursor.zig` remains only active cursor-state owner.
- `howl-vt/src/screen.zig` keeps active screen/grid/pen mutation only.
- `howl-vt/src/screen/apply.zig` remains the only owner that mutates active screen cursor truth from parsed semantic events after terminal/savepoint owners resolve higher-level consequences.
- `howl-vt/src/screen_set.zig` becomes passive screen-container/view logic only.
- `howl-vt/src/mode.zig` stays routing-only for cursor-relevant DEC modes.
- `howl-vt/src/ffi/lifecycle.zig` and `howl-vt/src/ffi/surface.zig` remain translation-only.
- `howl-render/src/vt_publication/abi.zig` widens main cursor shape to represent Kitty no-shape.
- `howl-render/src/vt_publication/publication.zig`, `source_slot.zig`, `cursor.zig`, `text_input.zig` remain consumer-only and carry widened shape truth.
- `howl-render/src/text/scene_rects.zig` remains draw owner; no-shape becomes draw-no-op.
- Host files remain consumers only.

Exact Delete / Replace / Leave-Unchanged Ledger:

- Delete symbols outright:
  - `Screen.saved_cursor`
  - `Screen.saveCursor`
  - `Screen.restoreCursor`
  - `screen.cursor.save`
  - `screen.cursor.restore`
  - `screen_set.Set.CursorSnapshot`
  - `screen_set.Set.saved_primary_cursor`
  - `screen_set.Set.enterAlt`
  - `screen_set.Set.exitAlt`
  - `mode.enterAltScreen`
  - `mode.exitAltScreen`
- Replace file contents materially:
  - `howl-vt/src/terminal.zig`
  - `howl-vt/src/screen_set.zig`
  - `howl-vt/src/screen.zig`
  - `howl-vt/src/screen/cursor.zig`
  - `howl-vt/src/screen/apply.zig`
  - `howl-vt/src/mode.zig`
  - `howl-vt/src/csi_private.zig`
  - `howl-vt/src/csi_intermediate.zig`
  - `howl-vt/src/csi_plain.zig`
  - `howl-vt/src/esc.zig`
  - `howl-vt/src/csi_params.zig`
  - `howl-vt/src/vocabulary.zig`
  - `howl-vt/src/route.zig`
  - `howl-vt/src/report.zig`
  - `howl-vt/src/ffi/surface.zig`
  - `howl-vt/src/ffi/lifecycle.zig`
  - `howl-vt/include/howl_vt.h`
  - `howl-render/src/vt_publication/abi.zig`
  - `howl-render/src/vt_publication/publication.zig`
  - `howl-render/src/vt_publication/source_slot.zig`
  - `howl-render/src/vt_publication/cursor.zig`
  - `howl-render/src/vt_publication/text_input.zig`
  - `howl-render/src/vt_publication/damage.zig`
  - `howl-render/src/vt_publication/prepare_queue.zig`
  - `howl-linux-host/src/terminal/vt_surface.zig`
  - `howl-linux-host/src/terminal/surface.zig`
- Add new files:
  - `howl-vt/src/terminal/savepoint.zig`
  - `howl-vt/test/unit/terminal_cursor_test.zig`
- Leave behavior ownership unchanged:
  - `howl-linux-host/src/terminal/cursor_blink.zig`
  - `howl-linux-host/src/terminal/render_retained.zig` as unchanged host retained-present consumer for published cursor truth
  - `howl-render/src/text/scene_rects.zig` as draw owner only
  - `howl-render/src/text/scene.zig` as existing cursor primitive storage owner with no new policy
  - `howl-render/src/text/surface_preparer.zig` as existing consumer path with no new policy

- Full stale-path accounting against the current-state owner map:
  - Parser dispatch root `stream_terminal.zig` remains unchanged for this slice; cursor-specific parser consequence owners that are replaced semantically are `csi_intermediate.zig`, `csi_plain.zig`, `esc.zig`, `csi_private.zig`, and `csi_params.zig`.
  - Semantic contract and routing remain but are replaced semantically: `vocabulary.zig`, `route.zig`.
  - Stale save/restore owners are removed: `screen/cursor.zig` save/restore helpers, `Screen.saved_cursor`, `Screen.saveCursor`, `Screen.restoreCursor`, `screen_set.Set.CursorSnapshot`, `saved_primary_cursor`, `enterAlt`, `exitAlt`, `mode.enterAltScreen`, `mode.exitAltScreen`.
  - Terminal aggregate owner is replaced to absorb Kitty-like savepoint and alt-screen consequences: `terminal.zig`.
  - Report and FFI publication owners remain translation/report owners but are replaced semantically for Kitty behavior: `report.zig`, `ffi/lifecycle.zig`, `ffi/surface.zig`.
  - Render publication owners remain consumers but are replaced semantically for widened no-shape truth and retained publication behavior: `vt_publication/abi.zig`, `publication.zig`, `source_slot.zig`, `cursor.zig`, `text_input.zig`, `damage.zig`, `prepare_queue.zig`.
  - Host consumers remain host consumers but must be updated for explicit no-shape consumption and tests: `terminal/vt_surface.zig`, `terminal/surface.zig`, `terminal/surface_test.zig`.
  - Host retained present owner remains unchanged and is explicitly not part of the replacement path: `terminal/render_retained.zig`.

Exact ABI / Publication / Host Impact:

- VT ABI change required:
  - widen main cursor shape enum to represent Kitty no-shape explicitly
  - affected owners:
    - `howl-vt/include/howl_vt.h`
    - `howl-vt/src/ffi/lifecycle.zig`
    - `howl-vt/src/ffi/surface.zig`
- Render publication change required:
  - accept widened main cursor shape in:
    - `howl-render/src/vt_publication/abi.zig`
    - `howl-render/src/vt_publication/publication.zig`
    - `howl-render/src/vt_publication/source_slot.zig`
    - `howl-render/src/vt_publication/cursor.zig`
    - `howl-render/src/vt_publication/text_input.zig`
- Host-facing consequence:
  - `howl-linux-host/src/terminal/vt_surface.zig` must capture explicit no-shape distinctly from hidden visibility.
  - `howl-linux-host/src/terminal/surface.zig` must consume explicit no-shape distinctly from hidden visibility in host cadence/render submission consequences.

Exact Proof Plan:

- VT proof roots:
  - `howl-vt/test/unit/csi_mapping_test.zig`
  - `howl-vt/test/unit/screen/cursor_test.zig`
  - `howl-vt/test/unit/terminal_cursor_test.zig` (new)
  - `howl-vt/test/unit/terminal_surface_test.zig`
  - `howl-vt/test/unit/terminal_modes_test.zig`
  - `howl-vt/test/unit/terminal_snapshot_test.zig`
  - `howl-vt/test/abi.zig`
  - `howl-vt/src/report.zig` inline tests
  - `howl-vt/src/ffi/lifecycle.zig` inline tests
- Render proof roots:
  - `howl-render/src/vt_publication/abi.zig` inline tests
  - `howl-render/src/vt_publication/publication.zig` inline tests
  - `howl-render/src/vt_publication/source_slot.zig` inline tests
  - `howl-render/src/vt_publication/cursor.zig` inline tests
  - `howl-render/src/vt_publication/text_input.zig` inline tests
  - `howl-render/src/vt_publication/damage.zig` inline tests
  - `howl-render/src/vt_publication/prepare_queue.zig` inline tests
- Host proof roots:
  - `howl-linux-host/src/terminal/vt_surface.zig` inline tests
  - `howl-linux-host/src/terminal/surface_test.zig`
- Verification commands:
  - `zig build test:unit` in `howl-vt`
  - `zig build test:abi` in `howl-vt`
  - `zig build test` in `howl-render`
  - `timeout 300s zig build test:unit` in `howl-linux-host`

Worker-Ready Slice Spec:

- Slice name: `cursor-kitty-restart-full-port`
- Preconditions: none remaining at planning level; user decisions and cursor-scoped reference receipt are resolved in this artifact.
- Exact artifact list to touch:
  - `howl-vt/src/terminal.zig`
  - `howl-vt/src/terminal/savepoint.zig`
  - `howl-vt/src/screen_set.zig`
  - `howl-vt/src/screen.zig`
  - `howl-vt/src/screen/cursor.zig`
  - `howl-vt/src/screen/apply.zig`
  - `howl-vt/src/mode.zig`
  - `howl-vt/src/csi_private.zig`
  - `howl-vt/src/csi_intermediate.zig`
  - `howl-vt/src/csi_plain.zig`
  - `howl-vt/src/esc.zig`
  - `howl-vt/src/csi_params.zig`
  - `howl-vt/src/vocabulary.zig`
  - `howl-vt/src/route.zig`
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
  - `howl-vt/test/abi.zig`
  - `howl-render/src/vt_publication/abi.zig`
  - `howl-render/src/vt_publication/publication.zig`
  - `howl-render/src/vt_publication/source_slot.zig`
  - `howl-render/src/vt_publication/cursor.zig`
  - `howl-render/src/vt_publication/text_input.zig`
  - `howl-render/src/vt_publication/damage.zig`
  - `howl-render/src/vt_publication/prepare_queue.zig`
  - `howl-linux-host/src/terminal/vt_surface.zig`
  - `howl-linux-host/src/terminal/surface.zig`
  - `howl-linux-host/src/terminal/surface_test.zig`
- Invariants:
  - save/restore is terminal-owned, not screen-owned
  - alt-screen cursor consequences are Kitty semantics, not copied-primary semantics
  - no-shape is explicit shape truth, not collapsed hidden visibility
  - cursor visibility and cursor colors are not part of savepoint payload
  - render and host remain consumers only
- Success criteria:
  - all commands in the proof plan pass
  - stale save/restore owners and alt-screen cursor snapshot owners are removed
  - DECSCUSR, save/restore, alt-screen, reporting, and ABI publication match the Kitty contract recorded here
- Out of scope:
  - multiple cursors
  - pointer cursor shape
  - cursor trail redesign
  - shell integration
  - unrelated renderer/runtime redesign
