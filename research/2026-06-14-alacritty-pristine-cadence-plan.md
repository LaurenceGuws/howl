# Kitty Cursor Parity Rewrite Plan

Status:

- Active research artifact for the active benchmark sprint.
- Orchestrator session id: `orch-2026-06-14-ascii-rain-performance-01`
- Researcher session id: `research-2026-06-14-ascii-rain-performance-01`
- Reviewer session id: `review-2026-06-14-ascii-rain-performance-01`
- Planning state: worker-ready pending reviewer acceptance.

Problem statement:

- Beat Alacritty on the benchmark by making Howl pristine, pragmatic, and idiomatic.
- Rewrite Howl cursor truth, rendering, cadence, protocol, config, and ABI to full Kitty cursor feature parity.
- No cursor feature deferrals are authorized.
- Cursor trail is promoted into this sprint because Kitty exposes `cursor_trail`, `cursor_trail_decay`, `cursor_trail_start_threshold`, and `cursor_trail_color` as cursor features and renders them through cursor runtime/render owners.
- All cursor-related modules found in this research are assigned below to exactly one primary owner slice or to historical/test-only coverage; later integration/proof touches are separately listed and do not change primary ownership.

Exact Kitty override receipt:

- User decision:
  `The user wants a cursor redesign. Every single line of code touching the cursor is in scope for rewrite.`
  `Nothing is deferred.`
  `The target is parity with Kitty cursor features.`
  `We are rewriting Kitty cursor features to Zig.`
  `All modules touched by cursor truth/rendering/cadence/protocol/ABI are in scope for change.`
- Reference being overridden:
  `reference-index.md:21-25`
  `reference-index.md:60-69`
  Specifically: default Alacritty-first host/runtime pressure and Kitty being limited to UX/protocol maturity only.
- Reason for override:
  The user explicitly directed that this slice use Kitty cursor rendering and feature parity as the governing reference instead of the default Alacritty-first host/runtime pressure.
- Accountable session ids:
  `orch-2026-06-14-ascii-rain-performance-01`
  `research-2026-06-14-ascii-rain-performance-01`
  `review-2026-06-14-ascii-rain-performance-01`
- User approval receipt:
  The live user messages in this session on `2026-06-14` directing full Kitty cursor parity with no deferrals.

Sources read in order:

1. `loop/flow.md`
2. `loop/researcher.md`
3. `sprints/current.txt`
4. `sprints/2026-06-14-alacritty-pristine-cadence-sprint.md`
5. `loops/alacritty-pristine-cadence-live-loop.txt`
6. `research/2026-06-14-alacritty-pristine-cadence-plan.md`
7. `reference-index.md`
8. `howl-linux-host/src/event.zig`
9. `howl-linux-host/src/terminal/surface.zig`
10. `howl-linux-host/src/terminal/cursor_blink.zig`
11. `howl-linux-host/src/terminal/term.zig`
12. `howl-linux-host/src/config/terminal.zig`
13. `howl-linux-host/src/config/config.zig`
14. `howl-linux-host/src/terminal/surface_test.zig`
15. `howl-vt/src/screen.zig`
16. `howl-vt/src/screen/cursor.zig`
17. `howl-vt/src/screen/apply.zig`
18. `howl-vt/src/screen_set.zig`
19. `howl-vt/src/csi_params.zig`
20. `howl-vt/src/csi_intermediate.zig`
21. `howl-vt/src/csi_private.zig`
22. `howl-vt/src/route.zig`
23. `howl-vt/src/vocabulary.zig`
24. `howl-vt/src/osc_color.zig`
25. `howl-vt/src/report.zig`
26. `howl-vt/src/ffi/lifecycle.zig`
27. `howl-vt/src/ffi/surface.zig`
28. `howl-vt/src/kitty/apply.zig`
29. `howl-vt/src/kitty/state.zig`
30. `howl-render/src/vt_publication/abi.zig`
31. `howl-render/src/vt_publication/publication.zig`
32. `howl-render/src/vt_publication/source_slot.zig`
33. `howl-render/src/vt_publication/damage.zig`
34. `howl-render/src/vt_publication/theme.zig`
35. `howl-render/src/vt_publication/cursor.zig`
36. `howl-render/src/vt_publication/text_input.zig`
37. `howl-render/src/text/contract.zig`
38. `howl-render/src/text/metrics.zig`
39. `howl-render/src/text/scene.zig`
40. `howl-render/src/text/scene_rects.zig`
41. `howl-render/src/text/surface_preparer.zig`
42. `howl-render/src/c/test_support.zig`
43. `howl-linux-host/src/terminal/render_retained.zig`
44. `utils/dev_references/terminals/kitty/kitty/data-types.h`
45. `utils/dev_references/terminals/kitty/kitty/cursor.c`
46. `utils/dev_references/terminals/kitty/kitty/cursor_trail.c`
47. `utils/dev_references/terminals/kitty/kitty/screen.h`
48. `utils/dev_references/terminals/kitty/kitty/screen.c`
49. `utils/dev_references/terminals/kitty/kitty/child-monitor.c`
50. `utils/dev_references/terminals/kitty/kitty/shaders.c`
51. `utils/dev_references/terminals/kitty/kitty/fonts.c`
52. `utils/dev_references/terminals/kitty/kitty/state.h`
53. `utils/dev_references/terminals/kitty/kitty/options/definition.py`
54. `utils/dev_references/terminals/kitty/kitty/options/utils.py`
55. `utils/dev_references/terminals/kitty/kitty/options/parse.py`
56. `utils/dev_references/terminals/kitty/docs/multiple-cursors-protocol.rst`

Current-code facts:

- Host loop cursor ownership is currently limited to `active_cursor`, `cursor_wait_ms`, and `cursor_redraw` facts; cursor-only redraw is separately classified at present planning time in `howl-linux-host/src/event.zig:184-215` and `:395-458`.
- Host surface cursor ownership is still only a blink-phase owner. `CursorFacts` carries visibility cadence only, and `consumeCursorFacts` just toggles render blink visibility in `howl-linux-host/src/terminal/surface.zig:368-385`.
- `howl-linux-host/src/terminal/cursor_blink.zig:6-80` models blink as a boolean visible phase plus deadline, not render-time opacity or inactivity stop.
- Host terminal state duplicates only `cursor_visible` and `cursor_blink` in `howl-linux-host/src/terminal/term.zig:35-49`; shape and color truth stay elsewhere.
- VT semantic surface export currently carries only row, col, visible, shape, and blink in `howl-vt/src/ffi/surface.zig:76-98` and `:211-217`.
- VT already supports default cursor style init and DECSCUSR override in `howl-vt/src/ffi/lifecycle.zig:28-46` and `howl-vt/src/csi_params.zig:72-80`.
- VT internal color state knows `cursor_text`, but the shipped render-facing color ABI drops it and exports only `foreground`, `background`, `cursor`, and palette in `howl-vt/src/ffi/surface.zig:24-29` and `:157-165`.
- Render publication still models cursor presentation as `cursor` plus host-owned `cursor_phase_visible` in `howl-render/src/vt_publication/publication.zig:18-34`.
- Render cursor mapping is geometry-only and single-color in `howl-render/src/vt_publication/cursor.zig:24-49`.
- Render cursor drawing is simple rect emission for block, beam, underline, and hollow shapes in `howl-render/src/text/scene_rects.zig:535-560`; there is no Kitty-style block text color resolution or multicell extent handling.
- Render cursor geometry is still fixed-width/fixed-thickness by default in `howl-render/src/text/metrics.zig:28-32`.
- Howl VT already has partial Kitty multiple-cursor protocol state in `howl-vt/src/kitty/apply.zig:58-64` and `howl-vt/src/kitty/state.zig:8-12`, but it is not exported or rendered.
- Howl has no cursor trail owner, no cursor trail config, no cursor trail render primitive, and no cursor trail cadence owner.

Reference facts:

- Kitty stores terminal cursor semantic state in a dedicated cursor object with `x`, `y`, `non_blinking`, `shape`, SGR attrs, and `position_changed_by_client_at` in `utils/dev_references/terminals/kitty/kitty/data-types.h:217-229` and `utils/dev_references/terminals/kitty/kitty/cursor.c:43-59`.
- Kitty keeps separate render-time cursor presentation state in `CursorRenderInfo` and compares it against `last_rendered.cursor` to decide cursor dirtiness in `utils/dev_references/terminals/kitty/kitty/data-types.h:231-236`, `utils/dev_references/terminals/kitty/kitty/screen.h:122-149`, and `utils/dev_references/terminals/kitty/kitty/child-monitor.c:697-699`.
- Kitty computes render-time cursor presentation in `collect_cursor_info`, including visibility, focus, multicursor count, effective shape, cursor opacity, text blink opacity, and next wait in `utils/dev_references/terminals/kitty/kitty/child-monitor.c:702-742`.
- Kitty blink is render-time opacity driven by interval, easing, and inactivity stop, and blinking text is synchronized with the same rhythm in `utils/dev_references/terminals/kitty/kitty/child-monitor.c:720-739` and `utils/dev_references/terminals/kitty/kitty/options/definition.py:358-378`.
- Kitty supports unfocused cursor shape as render policy in `utils/dev_references/terminals/kitty/kitty/options/definition.py:342-346` and `utils/dev_references/terminals/kitty/kitty/shaders.c:519-520`.
- Kitty supports separate `cursor_text_color` and contrast-aware block cursor color resolution in `utils/dev_references/terminals/kitty/kitty/options/definition.py:318-326` and `utils/dev_references/terminals/kitty/kitty/shaders.c:446-456,553-562`.
- Kitty prebuilds dedicated beam, underline, and hollow cursor sprites in `utils/dev_references/terminals/kitty/kitty/fonts.c:2048-2054`.
- Kitty multiple-cursor protocol is a real render surface feature, not advisory metadata, in `utils/dev_references/terminals/kitty/docs/multiple-cursors-protocol.rst:6-45`.
- Kitty cursor trail is a cursor feature with runtime update, opacity decay, thresholding, color, render-layers participation, and draw output in `utils/dev_references/terminals/kitty/kitty/cursor_trail.c:15-176`, `utils/dev_references/terminals/kitty/kitty/child-monitor.c:786-829`, `utils/dev_references/terminals/kitty/kitty/shaders.c:1512-1521,1672`, `utils/dev_references/terminals/kitty/kitty/state.h:64-68,379,588`, and `utils/dev_references/terminals/kitty/kitty/options/definition.py:380-422`.

Compact anchor map:

- Host control spine: `howl-linux-host/src/event.zig:184-215,224-244,395-458`
- Host surface cursor seam: `howl-linux-host/src/terminal/surface.zig:368-385,524-543`
- Host blink owner: `howl-linux-host/src/terminal/cursor_blink.zig:6-80`
- VT exported cursor seam: `howl-vt/src/ffi/surface.zig:24-29,76-98,157-165,211-217`
- VT visible view seam: `howl-vt/src/screen_set.zig:175-187`
- Render publication seam: `howl-render/src/vt_publication/publication.zig:18-34`
- Render cursor mapping seam: `howl-render/src/vt_publication/cursor.zig:24-49`
- Render cursor draw seam: `howl-render/src/text/scene_rects.zig:535-560`
- Kitty terminal cursor object: `utils/dev_references/terminals/kitty/kitty/data-types.h:217-229`
- Kitty cursor render owner: `utils/dev_references/terminals/kitty/kitty/child-monitor.c:702-742`
- Kitty shader cursor/color owner: `utils/dev_references/terminals/kitty/kitty/shaders.c:465-566`
- Kitty cursor trail owner: `utils/dev_references/terminals/kitty/kitty/cursor_trail.c:15-176`
- Kitty multiple cursor protocol: `utils/dev_references/terminals/kitty/docs/multiple-cursors-protocol.rst:6-45`

Complete coverage map authority:

- `Primary owner slice` below means the slice that is allowed to introduce or redefine the file's cursor-related product shape.
- Later slices may list the same file only for integration, proof updates, or mechanical propagation from the primary owner shape; later slices must not redefine the primary owner shape without returning to reviewer.
- Historical/test-only files are proof surfaces only and do not own product shape.

Primary owner slice map:

- `howl-vt/src/screen.zig`: Slice 1 owns semantic cursor fields and cursor movement timestamp truth.
- `howl-vt/src/screen/cursor.zig`: Slice 1 owns the dedicated VT cursor data shape and default/program style state.
- `howl-vt/src/screen/apply.zig`: Slice 1 owns mutation of semantic cursor truth from events.
- `howl-vt/src/screen_set.zig`: Slice 1 owns visible screen cursor view extraction for later export.
- `howl-vt/src/csi_params.zig`: Slice 1 owns DECSCUSR parse consequences.
- `howl-vt/src/csi_intermediate.zig`: Slice 1 owns CSI intermediate routing needed by cursor reports and style commands.
- `howl-vt/src/csi_private.zig`: Slice 1 owns private CSI cursor-mode consequences.
- `howl-vt/src/route.zig`: Slice 1 owns routing of cursor-relevant semantic events.
- `howl-vt/src/vocabulary.zig`: Slice 1 owns cursor semantic event vocabulary changes.
- `howl-vt/src/osc_color.zig`: Slice 1 owns cursor and cursor-text color mutation vocabulary.
- `howl-vt/src/report.zig`: Slice 1 owns cursor report payloads.
- `howl-vt/src/ffi/lifecycle.zig`: Slice 1 owns initialization/default cursor style proof and options import into VT.
- `howl-vt/src/ffi/surface.zig`: Slice 2 owns exported VT cursor/color/multiple-cursor ABI truth.
- `howl-vt/src/kitty/apply.zig`: Slice 7 owns multiple-cursor protocol state mutation completion.
- `howl-vt/src/kitty/state.zig`: Slice 7 owns multiple-cursor state storage completion.
- `howl-render/src/vt_publication/abi.zig`: Slice 2 owns render-facing cursor ABI widening.
- `howl-render/src/vt_publication/publication.zig`: Slice 2 owns publication storage, damage comparison, and removal of `cursor_phase_visible` as boundary truth.
- `howl-render/src/vt_publication/source_slot.zig`: Slice 2 owns copy/promote preservation of widened cursor presentation.
- `howl-render/src/vt_publication/damage.zig`: Slice 2 owns cursor-damage classification at the publication boundary.
- `howl-render/src/c/test_support.zig`: Slice 2 owns C test fixture updates for widened cursor ABI.
- `howl-linux-host/src/terminal/render_retained.zig`: Slice 2 owns retained-source integration with the widened publication contract.
- `howl-render/src/vt_publication/theme.zig`: Slice 6 owns cursor config/theme color threading.
- `howl-render/src/vt_publication/cursor.zig`: Slice 3 owns `CursorPresentation` and deletes the old `CursorInput` boundary shape.
- `howl-render/src/vt_publication/text_input.zig`: Slice 3 owns text-input mapping into `CursorPresentation`.
- `howl-render/src/text/contract.zig`: Slice 3 owns scene contract exposure of `CursorPresentation` and cursor primitives.
- `howl-render/src/text/scene.zig`: Slice 3 owns scene storage of cursor presentation and primitives.
- `howl-render/src/text/surface_preparer.zig`: Slice 3 owns mapping publication cursor presentation into scene cursor presentation.
- `howl-render/src/text/metrics.zig`: Slice 4 owns beam/underline thickness and cursor extent metrics.
- `howl-render/src/text/scene_rects.zig`: Slice 4 owns block/beam/underline/hollow/cursor-trail primitive emission.
- `howl-linux-host/src/event.zig`: Slice 5 owns bounded cursor-redraw admission and terminal-frame versus host-damage classification.
- `howl-linux-host/src/terminal/surface.zig`: Slice 5 owns host-side cursor presentation facts, focus policy, and publication inputs.
- `howl-linux-host/src/terminal/cursor_blink.zig`: Slice 5 owns blink opacity phase, inactivity stop, text blink synchronization, and cursor trail decay timing.
- `howl-linux-host/src/terminal/term.zig`: Slice 5 owns removal of duplicated/incomplete cursor state in host terminal state.
- `howl-linux-host/src/config/terminal.zig`: Slice 6 owns parsed cursor parity config fields.
- `howl-linux-host/src/config/config.zig`: Slice 6 owns top-level config propagation.
- `howl-linux-host/src/terminal/surface_test.zig`: Slice 8 owns host cross-owner cursor proofs.
- `howl-vt/test/abi.zig`: historical/test-only; Slice 8 updates proof expectations through the ABI test root.
- `howl-vt/test/unit/csi_mapping_test.zig`: historical/test-only; Slice 8 keeps cursor parse proof covered through the existing unit root.
- `howl-vt/test/unit/terminal_end_to_end_test.zig`: historical/test-only; Slice 8 keeps end-to-end cursor position proof covered.
- `howl-vt/test/unit/terminal_snapshot_test.zig`: historical/test-only; Slice 8 keeps snapshot cursor truth proof covered.
- `howl-vt/test/unit/terminal_modes_test.zig`: historical/test-only; Slice 8 keeps cursor mode/report proof covered.
- `howl-vt/test/unit/screen_test.zig`: historical/test-only; Slice 8 keeps screen cursor mutation proof covered.

Later integration/proof touch map:

- `howl-vt/src/ffi/surface.zig`: primary owner Slice 2; Slice 7 may mechanically add extra-cursor export from the Slice 2 ABI shape; Slice 8 may update tests only.
- `howl-render/src/vt_publication/abi.zig`: primary owner Slice 2; Slice 7 may mechanically preserve extra-cursor records from the Slice 2 ABI shape; Slice 8 may update tests only.
- `howl-render/src/vt_publication/publication.zig`: primary owner Slice 2; Slice 5 may feed host cadence presentation inputs into the Slice 2 publication shape; Slice 7 may preserve extra-cursor records; Slice 8 may update tests only.
- `howl-render/src/vt_publication/source_slot.zig`: primary owner Slice 2; Slice 8 may update tests only.
- `howl-render/src/vt_publication/damage.zig`: primary owner Slice 2; Slice 8 may update tests only.
- `howl-render/src/vt_publication/cursor.zig`: primary owner Slice 3; Slices 4, 5, 6, and 7 may consume or populate fields already defined by `CursorPresentation`; Slice 8 may update tests only.
- `howl-render/src/text/contract.zig`: primary owner Slice 3; Slice 7 may expose extra-cursor primitives using the Slice 3 contract; Slice 8 may update tests only.
- `howl-render/src/text/scene.zig`: primary owner Slice 3; Slice 4 may add primitive emission storage from the Slice 3 shape; Slice 7 may add extra-cursor primitive instances; Slice 8 may update tests only.
- `howl-render/src/text/surface_preparer.zig`: primary owner Slice 3; Slices 4 and 7 may mechanically map fields already defined by `CursorPresentation`; Slice 8 may update tests only.
- `howl-render/src/text/metrics.zig`: primary owner Slice 4; Slice 6 may thread configured values into the Slice 4 metric fields; Slice 8 may update tests only.
- `howl-render/src/text/scene_rects.zig`: primary owner Slice 4; Slice 6 may consume configured values; Slice 7 may emit extra-cursor instances using the Slice 4 primitive rules; Slice 8 may update tests only.
- `howl-linux-host/src/event.zig`: primary owner Slice 5; Slice 8 may update tests only.
- `howl-linux-host/src/terminal/surface.zig`: primary owner Slice 5; Slice 6 may feed parsed config into the Slice 5 presentation inputs; Slice 8 may update tests only.
- `howl-vt/src/kitty/apply.zig`: primary owner Slice 7; Slice 8 may update tests only.
- `howl-vt/src/kitty/state.zig`: primary owner Slice 7; Slice 8 may update tests only.

Explicit ordered worker slices:

1. Slice 1: Rebuild VT semantic cursor truth and protocol vocabulary.
Allowed files:
- `howl-vt/src/screen.zig`
- `howl-vt/src/screen/cursor.zig`
- `howl-vt/src/screen/apply.zig`
- `howl-vt/src/screen/write.zig`
- `howl-vt/src/screen/edit.zig`
- `howl-vt/src/screen/erase.zig`
- `howl-vt/src/screen/history.zig`
- `howl-vt/src/screen/margins.zig`
- `howl-vt/src/screen/resize.zig`
- `howl-vt/src/screen/scroll.zig`
- `howl-vt/src/screen/tabs.zig`
- `howl-vt/src/screen_set.zig`
- `howl-vt/src/mode.zig`
- `howl-vt/src/csi_params.zig`
- `howl-vt/src/csi_intermediate.zig`
- `howl-vt/src/csi_private.zig`
- `howl-vt/src/route.zig`
- `howl-vt/src/vocabulary.zig`
- `howl-vt/src/osc_color.zig`
- `howl-vt/src/report.zig`
- `howl-vt/src/ffi/surface.zig`
- `howl-vt/src/ffi/lifecycle.zig`
- `howl-vt/test/abi.zig`
- `howl-vt/test/support/screen_capture.zig`
- `howl-vt/test/unit/csi_mapping_test.zig`
- `howl-vt/test/unit/terminal_end_to_end_test.zig`
- `howl-vt/test/unit/terminal_snapshot_test.zig`
- `howl-vt/test/unit/terminal_modes_test.zig`
- `howl-vt/test/unit/terminal_surface_test.zig`
- `howl-vt/test/unit/screen_test.zig`
- `howl-vt/test/unit/screen/cursor_test.zig`
- `howl-vt/test/unit/screen/history_test.zig`
- `howl-vt/test/unit/screen/resize_test.zig`
- `howl-vt/test/unit/screen/tabs_test.zig`
- `howl-vt/test/unit/screen/write_test.zig`
Required shape:
- Introduce a dedicated VT semantic cursor shape in `howl-vt/src/screen/cursor.zig` carrying row, col, visible, effective shape, blink intent, default style, program override style, cursor color, cursor text color, and `position_changed_by_client_at`.
- `howl-vt/src/screen.zig` stores exactly one primary semantic cursor owner and does not duplicate cursor style/color fields outside that owner.
- `howl-vt/src/screen/apply.zig` is the only owner that mutates the semantic cursor from parsed semantic events.
- Existing screen helpers that move, read, save, restore, wrap, resize, scroll, erase, tab, or write at the cursor must route through the semantic cursor owner instead of preserving duplicate `Screen` cursor fields.
- `howl-vt/src/osc_color.zig` emits explicit cursor-color and cursor-text-color semantic events; `howl-vt/src/vocabulary.zig` names those events directly.
- `howl-vt/src/report.zig` reports cursor position/style from the semantic cursor owner.
Exact tests:
- Extend `howl-vt/src/ffi/lifecycle.zig` tests for default style restore and DECSCUSR behavior.
- Add cursor color and cursor-text color mutation tests through `howl-vt/src/osc_color.zig` and `howl-vt/src/screen/apply.zig`.
- Add report tests in `howl-vt/src/report.zig` for cursor position/style payloads.
- Update existing VT unit/support tests listed in the allowlist so proofs assert through the semantic cursor owner instead of the removed duplicate `Screen` cursor fields.
Non-goals:
- No render code changes.
- No host cadence changes.
- No VT/render ABI widening; `howl-vt/src/ffi/surface.zig` is allowed only for compile-preserving reads of the existing published cursor fields, not for exporting the new cursor color/style facts.
Stop conditions:
- No semantic cursor fact required by Kitty parity remains implicit or host-invented.
- VT semantic cursor truth is not exported in this slice; export is owned by Slice 2.

2. Slice 2: Widen the VT/render ABI and publication seam for full cursor truth.
Allowed files:
- `howl-vt/include/howl_vt.h`
- `howl-vt/src/ffi/surface.zig`
- `howl-render/src/vt_publication/abi.zig`
- `howl-render/src/vt_publication/publication.zig`
- `howl-render/src/vt_publication/source_slot.zig`
- `howl-render/src/vt_publication/damage.zig`
- `howl-render/src/c/test_support.zig`
- `howl-linux-host/src/terminal/render_retained.zig`
- `howl-linux-host/src/terminal/surface_test.zig`
Required shape:
- `howl-vt/src/ffi/surface.zig` exports primary cursor row, col, visible, shape, blink intent, cursor color, cursor text color, and `position_changed_by_client_at` from the VT semantic cursor owner.
- `howl-vt/include/howl_vt.h` mirrors the widened shipped C ABI surface exactly; render and host builds must compile against that installed header without local ABI drift.
- Exact ABI/publication constants: `HOWL_VT_MAX_EXTRA_CURSORS = 256` for VT export and render publication, and `HOWL_RENDER_MAX_CURSOR_TRAIL_RECTS = 16` for render publication only.
- Exact ABI color representation stays the existing `FfiColor { kind: u8, value: u32 }` and `FfiRgb8 { r: u8, g: u8, b: u8 }`; new cursor colors use those existing ABI color types, not new color buckets.
- Exact VT primary cursor ABI shape: `FfiCursor { row: u16, col: u16, visible: u8, shape: u8, blink: u8, reserved0: u8, position_changed_by_client_at_ms: u64, cell_cols: u16, cell_rows: u16 }`.
- Exact extra cursor ABI shape: `FfiExtraCursor { row: u16, col: u16, rows: u16, cols: u16, shape: u8, mode: u8, shape_follows_main: u8, color_follows_main: u8, cursor_color: FfiColor, text_color: FfiColor }`.
- Extra cursor `mode` values: `0` point, `1` rectangle. Extra cursor `shape` values: `0` none, `1` block, `2` beam, `3` underline, `4` hollow. `shape_follows_main=1` means use the main effective shape and ignore `shape`. `color_follows_main=1` means use main cursor color/text-color resolution and ignore `cursor_color` and `text_color`.
- Exact cursor aggregate ABI fields in `FfiSurface`: `extra_cursor_count: u16` and `extra_cursors: [HOWL_VT_MAX_EXTRA_CURSORS]FfiExtraCursor`. Cursor trail records are not VT ABI data because VT does not own cursor trail animation.
- Slice 2 ownership boundary: `howl-vt/src/ffi/surface.zig` defines the exact extra-cursor ABI shape and exports `extra_cursor_count=0` with zeroed `extra_cursors` until Slice 7 adds bounded extra-cursor state storage and export. Slice 2 must not invent placeholder extra-cursor state outside the later Slice 7 owners.
- Exact render publication cursor presentation shape adds host-owned fields not present in VT ABI: `cursor_opacity: u8`, `text_blink_opacity: u8`, `focused: bool`, and `effective_shape: u8`; opacity fields are 0..255 where 0 is transparent and 255 is opaque.
- Exact cursor trail publication shape: `SourceCursorTrailRect { row: u16, col: u16, rows: u16, cols: u16, opacity: u8, reserved0: u8, reserved1: u16, color: FfiRgb8 }` plus `cursor_trail_count: u16` and `cursor_trail_rects: [HOWL_RENDER_MAX_CURSOR_TRAIL_RECTS]SourceCursorTrailRect` in the render publication source.
- Cursor trail source ownership: host cadence owns trail timing and trail rectangle source data, writes at most `HOWL_RENDER_MAX_CURSOR_TRAIL_RECTS` trail records into the publication input, and render publication owns copying and damage comparison of those records; VT does not own cursor trail animation data.
- Slice 2 ownership boundary: the widened render publication source must carry exact trail fields with zero trail records until Slice 5 adds host-owned trail source plumbing. Slice 2 must not invent cursor trail timing or source owners outside the later Slice 5 files.
- `howl-render/src/vt_publication/abi.zig` mirrors these VT ABI and render-publication shapes exactly with Zig source types, validates every enum value and opacity <= 255, and rejects invalid publication sources with `error.InvalidSurfaceSource`.
- `howl-render/src/vt_publication/publication.zig` removes `cursor_phase_visible` as boundary truth and stores the widened cursor publication as source truth.
- `howl-render/src/vt_publication/damage.zig` classifies changes to primary cursor fields, extra cursor count/records, cursor colors, cursor trail count/records, and `position_changed_by_client_at_ms` as cursor damage.
Exact tests:
- Publication boundary validation tests for every widened cursor field, both maximum constants, every enum value, opacity bounds, and invalid enum rejection.
- Source-slot copy/promote tests covering primary cursor presentation preservation and zero-preservation of empty extra-cursor/trail aggregates.
- Retained-source tests proving primary cursor visibility/presentation changes and widened empty aggregate fields classify as cursor damage and not terminal content changes.
Non-goals:
- No scene draw implementation.
- No host timing changes.
- No extra-cursor state storage or clipping; that owner work remains in Slice 7.
- No cursor-trail source production or overflow behavior; that owner work remains in Slice 5.
Stop conditions:
- Render no longer relies on a single `cursor_phase_visible` boolean to express cursor presentation truth.
- Workers must not change cursor capacities, field names, integer widths, enum values, overflow behavior, or trail ownership from this Slice 2 contract without reviewer rejection and a new planning artifact.

3. Slice 3: Introduce render-owned cursor presentation data.
Allowed files:
- `howl-render/src/vt_publication/cursor.zig`
- `howl-render/src/vt_publication/text_input.zig`
- `howl-render/src/text/contract.zig`
- `howl-render/src/text/direct_normal.zig`
- `howl-render/src/text/direct_scene.zig`
- `howl-render/src/text/scene_rects.zig`
- `howl-render/src/text/scene.zig`
- `howl-render/src/text/surface_preparer.zig`
- `howl-render/src/render_session.zig`
Required shape:
- Introduce `CursorPresentation` in `howl-render/src/vt_publication/cursor.zig` with this exact owner data shape:
  `pub const max_extra_cursors = 256;`
  `pub const max_cursor_trail_rects = 16;`
  `pub const CursorColor = struct { kind: ColorKind, value: u32 };`
  `pub const Rgb8 = struct { r: u8, g: u8, b: u8 };`
  `pub const CellExtent = struct { row: u16, col: u16, rows: u16, cols: u16 };`
  `pub const CursorShape = enum(u8) { none = 0, block = 1, beam = 2, underline = 3, hollow = 4 };`
  `pub const ExtraCursorMode = enum(u8) { point = 0, rectangle = 1 };`
  `pub const ExtraCursorPresentation = struct { extent: CellExtent, shape: CursorShape, mode: ExtraCursorMode, shape_follows_main: bool, color_follows_main: bool, cursor_color: CursorColor, text_color: CursorColor };`
  `pub const CursorTrailRect = struct { extent: CellExtent, opacity: u8, color: Rgb8 };`
  `pub const CursorTrailSource = struct { rects: [max_cursor_trail_rects]CursorTrailRect, count: u16 };`
  `pub const CursorPresentation = struct { focused: bool, visible: bool, blink: bool, shape: CursorShape, cursor_opacity: u8, text_blink_opacity: u8, cursor_color: CursorColor, cursor_text_color: CursorColor, default_foreground: Rgb8, default_background: Rgb8, primary_extent: CellExtent, extra_cursors: [max_extra_cursors]ExtraCursorPresentation, extra_cursor_count: u16, trail: CursorTrailSource };`
- Color ownership: `CursorColor` mirrors the ABI color kind/value and remains unresolved until `howl-render/src/text/scene_rects.zig`; `Rgb8` is used only for already-resolved default colors and cursor trail color.
- `CellExtent.rows` and `CellExtent.cols` are never zero after validation; point cursors use `rows=1` and `cols=1`.
- `extra_cursor_count` must be <= `max_extra_cursors`; `trail.count` must be <= `max_cursor_trail_rects`; mapping asserts those bounds after ABI validation.
- Delete the current `CursorInput` single-color geometry-only boundary shape from `howl-render/src/vt_publication/cursor.zig`.
- `howl-render/src/text/contract.zig` exposes `CursorPresentation` to scene construction without host-side inference.
- `howl-render/src/text/scene.zig` stores `CursorPresentation` as one scene-owned cursor presentation value.
- `howl-render/src/text/surface_preparer.zig` maps the widened publication to `CursorPresentation` field-for-field.
- The old public `CursorInput` geometry-only seam must be removed from the render boundary in this slice. Added render consumer files may only mechanically consume `CursorPresentation` or scene-owned cursor presentation data already defined here; they must not invent Slice 4 primitive policy, color resolution policy, or new cursor owners.
Exact tests:
- Scene/preparer tests proving every `CursorPresentation`, `ExtraCursorPresentation`, `CursorTrailRect`, and `CellExtent` field survives mapping intact.
- Contract tests proving `CursorPresentation` represents block, beam, underline, hollow, point extra cursors, rectangle extra cursors, and cursor trail source up to the exact capacities.
Non-goals:
- No host config parsing.
- No protocol owner changes.
- No Slice 4 cursor primitive-policy changes; added render consumer files are mechanical seam consumers only.
Stop conditions:
- Render cursor truth is representable without host-side inference or shader-side guessing.
- Workers must not rename `CursorPresentation`, `ExtraCursorPresentation`, `CursorTrailSource`, `CursorTrailRect`, or `CellExtent`, and must not add a second cursor presentation owner.

4. Slice 4: Rebuild cursor primitive emission for main cursor and cursor trail.
Allowed files:
- `howl-render/src/text/scene_rects.zig`
- `howl-render/src/text/scene.zig`
- `howl-render/src/text/metrics.zig`
- `howl-render/src/text/surface_preparer.zig`
- `howl-render/src/vt_publication/cursor.zig`
Required shape:
- Introduce explicit scene cursor primitives in `howl-render/src/text/scene.zig`: `CursorFillRect`, `CursorTextRecolorSpan`, and `CursorTrailRect`.
- Block cursor emits one `CursorFillRect` for the cursor background and one `CursorTextRecolorSpan` for the covered text cells.
- Beam cursor emits one `CursorFillRect` using configured beam thickness and the primary cursor cell extent.
- Underline cursor emits one `CursorFillRect` using configured underline thickness and the primary cursor cell extent.
- Hollow cursor emits exactly four `CursorFillRect` perimeter edges derived from the primary cursor cell extent.
- Cursor trail emits ordered `CursorTrailRect` primitives with opacity and color from `CursorPresentation` trail source.
- Block cursor color resolution is owned by `resolveBlockCursorColors(presentation: CursorPresentation, cell_fg: Rgb8, cell_bg: Rgb8) struct { cursor_fg: Rgb8, cursor_bg: Rgb8 }` in `howl-render/src/text/scene_rects.zig`.
- Source-backed color algorithm from `kitty/shaders.c:446-456,552-562`: first compute `cell_contrast = rgb_contrast(cell_fg, cell_bg)`; the contrast helper threshold is `2.5`; when `cell_contrast < 2.5` and `rgb_contrast(default_foreground, default_background) > cell_contrast`, the helper result is `cursor_fg = default_background` and `cursor_bg = default_foreground`, otherwise helper result starts as `cursor_fg = cell_bg` and `cursor_bg = cell_fg`.
- Final special cursor-color branch matches `kitty/shaders.c:553-558`: when cursor color is special and the cell has a resolved line, `cell_bg == cell_fg` resolves to `cursor_fg = default_background` and `cursor_bg = default_foreground`; otherwise it resolves to `cursor_fg = cell_bg` and `cursor_bg = cell_fg`.
- Final non-special cursor-color branch matches `kitty/shaders.c:559-562`: `cursor_bg` is the resolved configured cursor color; when cursor text color is special, `cursor_fg = cell_bg`; otherwise `cursor_fg` is the resolved configured cursor text color.
- Extra cursor color resolution in Slice 7 must use the same `resolveBlockCursorColors` contract when extra cursor color follows main or uses special color semantics.
- Cursor extent covers large multicell glyph spans for block, beam, underline, and hollow cursor primitives.
Exact tests:
- Block cursor fill plus text recolor primitive tests.
- Configured cursor-text color tests.
- Contrast helper tests at contrast below `2.5`, contrast above `2.5`, and default foreground/background contrast greater than cell contrast.
- Special cursor-color tests for equal cell foreground/background and non-equal cell foreground/background.
- Non-special cursor-color tests for special cursor-text color and configured cursor-text color.
- Multicell extent tests for block, beam, underline, and hollow.
- Hollow cursor four-edge geometry tests.
- Cursor trail rect ordering, opacity, and color tests.
Non-goals:
- No host cadence changes.
- No extra-cursor drawing.
Stop conditions:
- Block cursor no longer renders as a single solid overlay rectangle with one color.

5. Slice 5: Rebuild host cadence, focus policy, inactivity stop, and cursor trail timing.
Allowed files:
- `howl-linux-host/src/event.zig`
- `howl-linux-host/src/terminal/surface.zig`
- `howl-linux-host/src/terminal/cursor_blink.zig`
- `howl-linux-host/src/terminal/term.zig`
- `howl-render/src/c/prepare_request.zig`
- `howl-render/src/render_session.zig`
- `howl-render/src/vt_publication/publication.zig`
- `howl-render/src/vt_publication/source_slot.zig`
- `howl-render/src/vt_publication/cursor.zig`
- `howl-linux-host/src/terminal/surface_test.zig`
Required shape:
- `howl-linux-host/src/terminal/cursor_blink.zig` owns blink opacity phase, synchronized text blink opacity, inactivity-stop deadline, and cursor trail decay deadline.
- `howl-linux-host/src/terminal/cursor_blink.zig` owns Kitty blink easing parity from `child-monitor.c:726-735` and `animation.h:19-21`: when cursor animation config is valid, blink cycle duration is `cursor_blink_interval * 2`, `frac_into_cycle = (now - cursor_blink_zero_time) % duration / duration`, opacity is `apply_easing_curve(animation.cursor, frac_into_cycle, duration)`, and the next wake is `50 ms`; when animation config is not valid, opacity is square-wave `1 - ((now - cursor_blink_zero_time) / cursor_blink_interval) % 2` and the next wake is the next interval edge.
- Eased cursor blink and SGR text blink share the same computed opacity; `cursor_opacity` uses that opacity only when the cursor is blinking and focused, while `text_blink_opacity` always uses that opacity when blinking text was used.
- Inactivity stop is keyed by VT `position_changed_by_client_at` from the publication boundary and stops blink opacity changes after the configured stop interval.
- `howl-linux-host/src/event.zig` performs bounded cursor work: at most one cursor-cadence update and at most one cursor-trail update per terminal per event-loop turn.
- `howl-linux-host/src/event.zig` schedules the next cursor wake from the minimum of blink deadline, inactivity-stop deadline, and trail decay deadline.
- `howl-linux-host/src/event.zig` classifies cursor-only presentation changes as host damage, not `terminal_frame`; terminal content changes remain the only owner of `terminal_frame` classification.
- `howl-linux-host/src/terminal/surface.zig` publishes focused/unfocused cursor presentation explicitly and never mutates VT cursor state for focus policy.
- `howl-render/src/c/prepare_request.zig` is part of the Slice 5 host-to-render prepare seam and may only be updated to pass host-owned cursor cadence and trail inputs into the already-defined render session/publication path.
- `howl-render/src/render_session.zig` and `howl-render/src/vt_publication/source_slot.zig` are part of the Slice 5 host-to-render prepare seam and may only be updated to carry host-owned cursor cadence and trail inputs into the already-defined publication shape.
- `howl-linux-host/src/terminal/term.zig` stops owning duplicated incomplete cursor-visible/blink state after `surface.zig` and `cursor_blink.zig` own presentation.
Exact tests:
- Inactivity-stop tests keyed to cursor movement time.
- Blink easing tests for valid animation config: cycle duration `2 * cursor_blink_interval`, sample wake `50 ms`, opacity sampled through the easing function, and synchronized text blink opacity.
- Square-wave blink tests for invalid animation config: interval-edge wake and `1,0,1,0` opacity sequence.
- Focus loss and regain tests for unfocused shape and restored focused shape.
- Bounded-work tests proving one cursor update and one trail update per loop turn.
- Autonomous cursor redraw classification tests proving cursor-only redraw is host damage and not `terminal_frame`.
- Restore-default appearance tests.
Non-goals:
- No config shape/thickness parsing.
- No multiple-cursor drawing.
- No unrelated render C/session API reshaping beyond the host-owned cursor cadence/trail seam.
Stop conditions:
- Cursor cadence is no longer representable as only `visible + deadline`.

6. Slice 6: Add Kitty cursor config parity and thread it through owners.
Allowed files:
- `howl-linux-host/src/config/terminal.zig`
- `howl-linux-host/src/config/config.zig`
- `howl-linux-host/src/terminal/surface.zig`
- `howl-render/src/vt_publication/theme.zig`
- `howl-render/src/vt_publication/cursor.zig`
- `howl-render/src/text/metrics.zig`
- `howl-render/src/text/scene_rects.zig`
Required shape:
- `howl-linux-host/src/config/terminal.zig` owns parsed Kitty cursor config fields: `cursor`, `cursor_text_color`, `cursor_shape`, `cursor_shape_unfocused`, `cursor_beam_thickness`, `cursor_underline_thickness`, `cursor_blink_interval`, `cursor_stop_blinking_after`, `cursor_trail`, `cursor_trail_decay_fast`, `cursor_trail_decay_slow`, `cursor_trail_start_threshold`, and `cursor_trail_color`.
- `howl-linux-host/src/config/config.zig` owns top-level propagation of those parsed fields to terminal creation.
- `howl-linux-host/src/terminal/surface.zig` owns applying host config to cursor presentation and trail timing inputs.
- `howl-render/src/vt_publication/theme.zig` owns cursor and cursor-text color theme propagation.
- `howl-render/src/text/metrics.zig` owns beam and underline thickness metrics.
- `howl-render/src/text/scene_rects.zig` consumes the configured thickness and trail color without hard-coded cursor constants.
Exact tests:
- Config parse tests for every listed cursor field in `howl-linux-host/src/config/terminal.zig`.
- Top-level config propagation tests in `howl-linux-host/src/config/config.zig`.
- Geometry tests proving beam and underline thickness take effect.
- Unfocused shape tests.
- Cursor trail config tests for enable duration, decay values, threshold, and color.
Non-goals:
- No benchmark tuning.
- No shell prompt integration policy beyond config needed for parity.
Stop conditions:
- No Kitty cursor config field listed above remains hard-coded.

7. Slice 7: Complete multiple-cursor export, render mapping, and drawing parity.
Allowed files:
- `howl-vt/src/kitty/apply.zig`
- `howl-vt/src/kitty/state.zig`
- `howl-vt/src/ffi/surface.zig`
- `howl-render/src/vt_publication/abi.zig`
- `howl-render/src/vt_publication/publication.zig`
- `howl-render/src/vt_publication/cursor.zig`
- `howl-render/src/text/contract.zig`
- `howl-render/src/text/scene.zig`
- `howl-render/src/text/scene_rects.zig`
- `howl-render/src/text/surface_preparer.zig`
Required shape:
- Command introducer and trailer are exact: `CSI > ... SPACE q`.
- Support query command is `CSI > SPACE q`; response is exactly `CSI > 1;2;3;29;30;40;100;101 SPACE q`.
- Cursor placement command form is `CSI > SHAPE;COORD_TYPE:COORDINATES;COORD_TYPE:COORDINATES SPACE q` with `SHAPE` values `0` none/clear, `1` block, `2` beam, `3` underline, and `29` follow main shape.
- Coordinate type `0` refers to the main cursor and has no following coordinates; coordinate type `2` consumes `y:x` point pairs using 1-based screen coordinates; coordinate type `4` consumes `top:left:bottom:right` rectangles using 1-based inclusive screen coordinates; type `4` with no numbers means full screen.
- Extra coordinate behavior is exact: for type `2`, an odd trailing coordinate is ignored; for type `4`, trailing 1..3 coordinates are ignored; unknown coordinate types are ignored with their malformed group and do not clear existing state.
- Out-of-screen behavior is exact: out-of-screen points are ignored with no effect; rectangles are intersected with the visible screen; rectangles with empty intersection produce no records.
- Bounds behavior is exact: state stores at most `HOWL_VT_MAX_EXTRA_CURSORS = 256` clipped records in parse order; additional records are ignored; overflow is not a protocol error and produces no response.
- Clear behavior is exact: shape `0` clears cursors at addressed cells; `CSI > 0;4 SPACE q` clears all extra cursors; ED parameters `2`, `3`, and `22`, terminal reset, and switching between main and alternate screen remove all extra cursors; IND and RI scrolling do not move extra cursors.
- Extra cursor color command form is `CSI > WHICH;COLOR_SPACE:COLOR_PARAMETERS SPACE q`, where `WHICH=30` sets text-under-extra-cursor color and `WHICH=40` sets extra cursor color.
- Extra cursor color spaces are exact: `0` unset/follow main with no parameters, `1` special/reverse-video with no parameters, `2` sRGB with three `u8` parameters `red:green:blue`, and `5` indexed color with one `u8` palette index. Invalid color spaces, missing parameters, and out-of-range color parameters leave the previous color state unchanged.
- Extra cursor color semantics are exact: unset follows the main cursor colors exactly; `40` special renders block extra cursors with reverse-video color resolution and ignores `30`; non-special `40` plus `30` special changes text under the cursor to the cell background for partial reverse video; otherwise `30` supplies text color and `40` supplies cursor color.
- Cursor query command is `CSI > 100 SPACE q`; response is one escape code `CSI > 100;SHAPE:COORD_TYPE:COORDINATES;... SPACE q`; empty state response is exactly `CSI > 100 SPACE q`; response order follows stored parse order grouped by shape and coordinate type only when grouping preserves exact state.
- Extra cursor color query command is `CSI > 101 SPACE q`; response is exactly `CSI > 101;30:COLOR_SPACE:COLOR_PARAMETERS;40:COLOR_SPACE:COLOR_PARAMETERS SPACE q` using the currently stored text and cursor color states.
- `howl-vt/src/kitty/apply.zig` implements support query, cursor query, color query, add/update, remove, clear, ED/reset/alternate-screen clearing hooks, and no-scroll-on-IND/RI behavior.
- `howl-vt/src/kitty/state.zig` stores bounded extra cursor records with exact row, col, rows, cols, mode, shape, `shape_follows_main`, `color_follows_main`, cursor color, and text color fields matching the Slice 2 ABI.
- `howl-vt/src/ffi/surface.zig` exports bounded extra cursor records from VT state with the Slice 2 ABI shape.
- `howl-render/src/vt_publication/abi.zig` and `howl-render/src/vt_publication/publication.zig` preserve extra cursor records field-for-field.
- `howl-render/src/vt_publication/cursor.zig` maps extra cursor records into `CursorPresentation.extra_cursors` without changing order.
- `howl-render/src/text/scene_rects.zig` draws point and rectangle extra cursors using the main cursor primitive rules, `shape_follows_main`, `color_follows_main`, and the Slice 4 block color resolver.
Exact tests:
- Support query response test for exact `CSI > 1;2;3;29;30;40;100;101 SPACE q` payload.
- Point command tests for shape `1`, `2`, `3`, and `29`, 1-based coordinate conversion, odd trailing coordinate ignore, out-of-screen point ignore, and 256-record overflow ignore.
- Rectangle command tests for full-screen rectangle, clipped rectangle intersection, trailing 1..3 coordinate ignore, empty intersection ignore, and shape `0` clearing.
- State clearing tests for `CSI > 0;4 SPACE q`, ED `2`, ED `3`, ED `22`, reset, and alternate-screen switch.
- Scroll interaction tests proving IND and RI do not move extra cursor state.
- Color command tests for `30` and `40`, color spaces `0`, `1`, `2`, and `5`, invalid color unchanged, special `40` ignoring `30`, `30` special partial reverse behavior, and unset follow-main behavior.
- Query tests for exact empty and non-empty `100` response payloads and exact `101` color response payload.
- ABI/publication tests for extra cursor export and preservation.
- Render tests for point cursor placement, rectangle cursor placement, shape-follow behavior, color-follow behavior, and special color resolution through `resolveBlockCursorColors`.
Non-goals:
- No unrelated graphics protocol work.
- No input method policy changes.
Stop conditions:
- No multiple-cursor protocol state remains unrendered after this slice.

8. Slice 8: Add end-to-end parity proofs across VT, ABI, render, host, config, and cursor trail.
Allowed files:
- `howl-linux-host/src/terminal/surface_test.zig`
- `howl-linux-host/src/event.zig`
- `howl-vt/src/ffi/lifecycle.zig`
- `howl-vt/src/ffi/surface.zig`
- `howl-vt/src/kitty/apply.zig`
- `howl-vt/src/kitty/state.zig`
- `howl-render/src/vt_publication/abi.zig`
- `howl-render/src/vt_publication/publication.zig`
- `howl-render/src/vt_publication/source_slot.zig`
- `howl-render/src/vt_publication/damage.zig`
- `howl-render/src/vt_publication/cursor.zig`
- `howl-render/src/text/contract.zig`
- `howl-render/src/text/metrics.zig`
- `howl-render/src/text/scene.zig`
- `howl-render/src/text/scene_rects.zig`
- `howl-render/src/text/surface_preparer.zig`
- `howl-vt/test/abi.zig`
- `howl-vt/test/unit/csi_mapping_test.zig`
- `howl-vt/test/unit/terminal_end_to_end_test.zig`
- `howl-vt/test/unit/terminal_snapshot_test.zig`
- `howl-vt/test/unit/terminal_modes_test.zig`
- `howl-vt/test/unit/screen_test.zig`
Required shape:
- Add deterministic parity proofs for DECSCUSR, cursor colors, cursor-text color, focus/unfocus presentation, blink cadence, inactivity stop, latest-snapshot cursor truth, restore-default cursor appearance, multiple-cursor rendering, cursor trail config, cursor trail cadence, and cursor trail primitive output.
- Proof crosses VT semantic owner, VT ABI export, render publication, render scene emission, host cadence, and config parsing.
Exact tests:
- VT surface export tests.
- Render mapping and scene draw tests.
- Host end-to-end cursor latest-snapshot and redraw-source tests.
- Multiple-cursor end-to-end tests.
- Cursor trail end-to-end tests from config through host cadence to scene primitive output.
Non-goals:
- No micro-optimization.
- No benchmark harness changes.
Stop conditions:
- Parity claims are rejected without cross-owner proofs for every cursor feature listed in this artifact.

Risks:

- Full Kitty parity forces ABI widening across VT to render and will ripple into generated C-facing contracts.
- Render architecture needs deeper cursor-specific primitive work than the current rect-only path.
- Blink opacity, cursor trail, and multiple-cursor parity increase redraw pressure and can perturb benchmark traces without bounded host cadence.
- The current partial multiple-cursor state makes half-complete implementation visibly untruthful.

Readiness judgment:

- Worker-ready for reviewer gating.
- Coding is not authorized until reviewer accepts this planning artifact and the orchestrator seeds Slice 1 as the active implementation contract.
