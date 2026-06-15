# Cursor Kitty Line Map

## Receipt Header

- Artifact owner: `research/2026-06-15-cursor-kitty-line-map.md`
- Researcher role: active researcher
- Session id: no internal session identifier exposed beyond this task session
- Method: current Howl source re-read plus direct Kitty source reads only

## Scope Rule

- Included: terminal cursor state, shape, visibility, blink cadence, trail, save/restore, alt-screen cursor consequences, `DECSCUSR`, `DECRQSS " q"`, publication, draw, host cadence, host-to-render cursor seam, cursor config knobs, and tests proving those behaviors.
- Excluded as out of scope: mouse pointer cursor helpers and link-hover pointer-cursor code, because they do not touch terminal cursor semantics.

## Kitty Anchors Used

- `utils/dev_references/terminals/kitty/kitty/vt-parser.c:300-308,1269-1272,1312-1315,1359-1362`
- `utils/dev_references/terminals/kitty/kitty/screen.c:1624-1659,1698-1735,2002-2004,2265-2273,2349-2364,2393,2954-2968,3311-3325`
- `utils/dev_references/terminals/kitty/kitty/screen.h:220-221,233,255,294`
- `utils/dev_references/terminals/kitty/kitty/cursor.c:249-260`
- `utils/dev_references/terminals/kitty/kitty/data-types.h:76,219-252`
- `utils/dev_references/terminals/kitty/kitty/colors.c:552-553`
- `utils/dev_references/terminals/kitty/kitty/window.py:443-452,1737-1742`
- `utils/dev_references/terminals/kitty/kitty/options/definition.py:318-427`
- `utils/dev_references/terminals/kitty/kitty/options/utils.py:542-563`
- `utils/dev_references/terminals/kitty/kitty/options/types.py:558-569`
- `utils/dev_references/terminals/kitty/kitty/options/to-c-generated.h:152-252`
- `utils/dev_references/terminals/kitty/kitty/options/to-c.h:260-291`
- `utils/dev_references/terminals/kitty/kitty/glfw.c:41-45`
- `utils/dev_references/terminals/kitty/kitty/child-monitor.c:717-742,786-829`
- `utils/dev_references/terminals/kitty/kitty/shaders.c:519-566`
- `utils/dev_references/terminals/kitty/kitty/cursor_trail.c:15-181`

## VT

### Parse and semantic contract

- `howl-vt/src/vocabulary.zig:81-97,131-157`
  Kitty source: `vt-parser.c:1269-1272,1312-1315,1359-1362`, `screen.c:2954-2968`, `data-types.h:76,219-229`, `colors.c:552-553`
  Notes: semantic contract for cursor move events, visibility, style, save/restore, cursor color, cursor text color, and explicit no-shape.

- `howl-vt/src/csi_intermediate.zig:102-105`
  Kitty source: `vt-parser.c:1359-1362`, `screen.c:2954-2968`
  Notes: `CSI Ps SP q` to `DECSCUSR` semantic routing.

- `howl-vt/src/csi_plain.zig:34-38`
  Kitty source: `vt-parser.c:1269-1272,1312-1315`
  Notes: `CSI s` and `CSI u` aliases.

- `howl-vt/src/esc.zig:18-27,42-53`
  Kitty source: `vt-parser.c:300-308`, `screen.h:220-221`
  Notes: `ESC 7` and `ESC 8` aliases.

- `howl-vt/src/csi_private.zig:96-103`
  Kitty source: `screen.c:1728-1735`, `screen.c:1624-1659`
  Notes: DEC private `47`, `1047`, `1049` alt-screen consequences.

- `howl-vt/src/route.zig:138-168,202-217`
  Kitty source: `NO KITTY SOURCE`
  Notes: Howl-only internal semantic routing spine; behavior it routes is Kitty-backed, but this owner split is not from Kitty.

- `howl-vt/src/mode.zig:148-160,187-206`
  Kitty source: `screen.c:1698-1735,2002-2004`
  Notes: DEC cursor visible mode, alt-screen toggles, and DECRQM reporting for `?25`, `47`, `1047`, `1049`.

### Screen cursor owner

- `howl-vt/src/screen/cursor.zig:4-106`
  Kitty source: `cursor.c:249-260`, `data-types.h:76,219-229`, `screen.c:2393,2954-2968`
  Notes: active cursor state, explicit no-shape, blink bit, color fields, and position-changed counter.

- `howl-vt/src/screen/cursor.zig:108-131`
  Kitty source: `screen.c:2357-2363,1708-1715`
  Notes: cursor position resolution relative to origin and margins.

- `howl-vt/src/screen.zig:87-144,248-273,338-345,381-385`
  Kitty source: `cursor.c:249-253`, `screen.c:1624-1659,2265-2273,2349-2364,2954-2968`
  Notes: screen owns active cursor instance, reset, default cursor style, apply path, and alt-entry reset.

- `howl-vt/src/screen/apply.zig:110-167`
  Kitty source: `screen.c:1698-1715,2002-2004,2954-2968`
  Notes: visibility, `DECSCUSR` program/default style application, cursor colors, origin mode, and cursor-relative control flow.

- `howl-vt/src/screen_set.zig:13-21,125-167`
  Kitty source: `screen.c:1624-1659,2002-2004`
  Notes: visible-view projection of cursor row, col, visibility, shape, blink, and alt-screen flag.

### Terminal savepoint and alt-screen owner

- `howl-vt/src/terminal/savepoint.zig:1-25`
  Kitty source: `screen.c:2265-2273,2349-2364`
  Notes: Howl savepoint struct mirrors Kitty savepoint payload pressure.

- `howl-vt/src/terminal.zig:29-38,51-105`
  Kitty source: `screen.c:2954-2968`, `window.py:1737-1742`
  Notes: default cursor style initialization and per-bank savepoint storage.

- `howl-vt/src/terminal.zig:151-160`
  Kitty source: `window.py:1737-1742`, `cursor.c:249-253`
  Notes: reset path re-seeds cursor defaults and clears saved cursor state.

- `howl-vt/src/terminal.zig:162-205,322-340`
  Kitty source: `screen.c:2265-2273,2349-2364`, `cursor.c:255-260`
  Notes: terminal-owned save/restore payload, restore-without-save behavior, charset restore, and bounds clamp.

- `howl-vt/src/terminal.zig:207-223`
  Kitty source: `screen.c:1624-1659,1728-1735`
  Notes: `47`, `1047`, `1049` switching, clear-on-enter, save/restore on `1049`, and reset-on-alt-entry.

### Reports and ABI

- `howl-vt/src/report.zig:18-24,31-36,42-124`
  Kitty source: `screen.c:2002-2004,3311-3325`
  Notes: cursor position reporting inputs, DECRQSS dispatch, and cursor-information reporting payload.

- `howl-vt/src/report.zig:130-170`
  Kitty source: `screen.c:3311-3325`
  Notes: `DECRQSS " q"` mapping, including no-shape => `1`.

- `howl-vt/src/report.zig:203-210`
  Kitty source: `window.py:443-452`
  Notes: CPR and DECXCPR cursor position export shape.

- `howl-vt/src/report.zig:228-260`
  Kitty source: `NO KITTY SOURCE`
  Notes: Howl `DECCIR` report assembly has no direct Kitty implementation match in the cursor sprint anchor set.

- `howl-vt/src/ffi/lifecycle.zig:15-37,43-53,96-137`
  Kitty source: `window.py:1737-1742`, `screen.c:2954-2968`
  Notes: shipped init option translation for default cursor style and blink.

- `howl-vt/src/ffi/surface.zig:91-121,220-257`
  Kitty source: `data-types.h:219-252`, `screen.c:2002-2004,2393`, `colors.c:552-553`
  Notes: shipped VT cursor ABI: row/col/visible/shape/blink/cell extent/position-changed plus cursor colors.

- `howl-vt/include/howl_vt.h:155-213,215-236`
  Kitty source: `data-types.h:76,219-252`
  Notes: public C ABI enums and structs for cursor shape, cursor style, cursor record, and surface cursor publication.

### VT tests

- `howl-vt/test/unit/csi_mapping_test.zig:158-160,292-308`
  Kitty source: `vt-parser.c:1269-1272,1312-1315,1359-1362`, `screen.c:2954-2968`

- `howl-vt/test/unit/screen/cursor_test.zig:9-139`
  Kitty source: `cursor.c:249-260`, `screen.c:1708-1715,2002-2004,2954-2968`

- `howl-vt/test/unit/terminal_cursor_test.zig:19-149`
  Kitty source: `screen.c:1624-1659,2265-2273,2349-2364,2954-2968`

- `howl-vt/test/unit/terminal_surface_test.zig:207-220,575-586`
  Kitty source: `screen.c:1624-1659,1728-1735,2002-2004,2393`

- `howl-vt/test/unit/terminal_modes_test.zig:494-607,660-679`
  Kitty source: `screen.c:2002-2004,3311-3325,2265-2273,2349-2364`, `window.py:443-452`

- `howl-vt/test/unit/terminal_snapshot_test.zig:36-46,73-78,108-110,205-210`
  Kitty source: `screen.c:2002-2004`, `data-types.h:219-236`

- `howl-vt/test/abi.zig:58-67`
  Kitty source: `window.py:1737-1742`, `screen.c:2954-2968`

- `howl-vt/test/unit/terminal_end_to_end_test.zig:31-42`
  Kitty source: `colors.c:552-553`
  Notes: proof that OSC cursor color and cursor text color route into the semantic cursor owner.

- `howl-vt/simulation/protocol.zig:155-156,387-390,415-416`
  Kitty source: `NO KITTY SOURCE`
  Notes: Howl-only determinism digest and diagnostic accounting include cursor row, col, visibility, and shape.

- `howl-vt/simulation/scrollback.zig:46-47,257-267,370-371,380-406`
  Kitty source: `NO KITTY SOURCE`
  Notes: Howl-only scrollback simulation invariants, hashing, and breakpoint diagnostics include cursor coordinates.

## Render

### VT publication ABI and copy

- `howl-render/src/vt_publication/abi.zig:13-23,37-52,107-140,178-208`
  Kitty source: `data-types.h:76,219-252`
  Notes: render-side cursor source shape enums, main cursor payload, extra cursor payload, and validation.

- `howl-render/src/vt_publication/publication.zig:100-174,273-315,419-463`
  Kitty source: `data-types.h:219-252`
  Notes: VT C ABI to render-owned cursor copy; no-shape preserved without reinterpretation.

- `howl-render/src/vt_publication/source_slot.zig:110-135,309-331,443-460,527-543`
  Kitty source: `data-types.h:219-252`
  Notes: retained-copy cursor truth import/export and explicit no-shape proof use the shipped VT cursor payload directly.

- `howl-render/src/vt_publication/source_slot.zig:152-306,495-525,545-559`
  Kitty source: `NO KITTY SOURCE`
  Notes: Howl-only retained-slot commit, promotion, refresh, metadata carry-forward, and local proof scaffolding.

- `howl-render/src/vt_publication/damage.zig:42-75,205-236`
  Kitty source: `child-monitor.c:717-742,786-829`, `cursor_trail.c:161-181`
  Notes: cursor-visible, shape, blink, opacity, extra-cursor, and trail changes are treated as cursor presentation changes; proof lines exercise those cursor consequences.

- `howl-render/src/vt_publication/damage.zig:81-112`
  Kitty source: `NO KITTY SOURCE`
  Notes: Howl-only publication-source equality and dedupe logic.

- `howl-render/src/vt_publication/prepare_queue.zig:22-198,288-305`
  Kitty source: `NO KITTY SOURCE`
  Notes: retained prepare queue, blink refresh scheduling, and admission logic are Howl render-pipeline invention.

- `howl-render/src/render_session.zig:381-415,499-504,586-666,854-879`
  Kitty source: `NO KITTY SOURCE`
  Notes: Howl-only render-session owner, cadence storage, local source mutation path, and proof scaffolding. Kitty pressures the behavior, but no direct Kitty owner/file boundary matches these exact lines.

### Cursor presentation and text-scene input

- `howl-render/src/vt_publication/cursor.zig:33-115,142-227,229-346`
  Kitty source: `shaders.c:519-566`, `cursor_trail.c:15-49,129-181`, `data-types.h:231-252`
  Notes: maps published cursor shape/colors/opacity/unfocused shape/trail into render presentation.

- `howl-render/src/vt_publication/text_input.zig:232-237,240-261`
  Kitty source: `shaders.c:519-566`
  Notes: threads cursor presentation into text-scene input.

- `howl-render/src/vt_publication/text_input.zig:352-378`
  Kitty source: `shaders.c:519-566`
  Notes: proof that explicit no-shape survives publication mapping into text-scene input.

- `howl-render/src/text/scene_rects.zig:334-420`
  Kitty source: `shaders.c:519-566`, `cursor_trail.c:15-49,129-181`
  Notes: draw/no-draw for no-shape, block/beam/underline/hollow geometry, recolor, and trail rectangles.

- `howl-render/src/text/metrics.zig:46-52,85-92`
  Kitty source: `cursor_trail.c:33-39`, `options/definition.py:348-355`
  Notes: beam and underline cursor geometry derive from configured thickness inputs.

- `howl-render/src/text/metrics.zig:54-57,59-83`
  Kitty source: `NO KITTY SOURCE`
  Notes: Howl-only thickness scaling helper and local proof scaffolding.

- `howl-render/src/text/contract.zig:23-36`
  Kitty source: `NO KITTY SOURCE`
  Notes: Howl-only contract-root re-exports for cursor geometry and cursor presentation owners.

- `howl-render/src/text/scene_rects.zig:869-900`
  Kitty source: `shaders.c:548,567-569`, `cursor_trail.c:161-181`
  Notes: proof that visible no-shape produces no cursor draw/fill/recolor while trail rendering remains independent.

- `howl-render/src/c/text_session.zig:80-150`
  Kitty source: `child-monitor.c:717-742,786-829`, `shaders.c:519-566`, `cursor_trail.c:15-181`
  Notes: host-cadence ABI intake for focused flag, opacity, effective shape, colors, thickness, and trail rects.

- `howl-render/include/howl_render.h:1-240`
  Kitty source: `NO KITTY SOURCE`
  Notes: shipped render ABI surface is Howl-specific.

- `howl-render/src/libhowl_render.zig:8-16`
  Kitty source: `NO KITTY SOURCE`
  Notes: Howl-only exported render ABI hooks.

## Host

### Cursor config

- `howl-linux-host/assets/default_config/init.lua:16-53`
  Kitty source: `options/definition.py:318-427`, `options/types.py:558-569`
  Notes: shipped default cursor config block and defaults.

- `howl-linux-host/src/config/terminal.zig:46-88,123-140,210-229,311-402`
  Kitty source: `options/definition.py:318-427`, `options/utils.py:542-563`, `options/types.py:558-569`, `options/to-c-generated.h:152-252`, `options/to-c.h:260-291`, `glfw.c:41-45`
  Notes: Linux-host cursor config model and loader for colors, shapes, blink interval, inactivity stop, and trail knobs.

- `howl-linux-host/src/config/config.zig:18-20,80-136`
  Kitty source: `options/definition.py:318-427`, `options/types.py:558-569`
  Notes: shipped asset load path and cursor config proof.

### Host VT seam and render seam

- `howl-linux-host/src/terminal/vt_surface.zig:56-71,89-183`
  Kitty source: `data-types.h:219-252`, `screen.c:2002-2004,2393`
  Notes: copies visible cursor payload from VT surface into host-retained state and acks published snapshot.

- `howl-linux-host/src/terminal/term.zig:47-48`
  Kitty source: `screen.c:2002-2004`, `child-monitor.c:721-739`
  Notes: host VT state caches cursor visible and blink facts.

- `howl-linux-host/src/terminal/vt_surface.zig:350-394`
  Kitty source: `screen.c:1624-1659,2002-2004,2954-2968`
  Notes: proof that visible capture preserves alternate-screen state and explicit no-shape cursor truth.

- `howl-linux-host/src/terminal/render_retained.zig:63-93,191-194`
  Kitty source: `NO KITTY SOURCE`
  Notes: Howl-only host-to-render cadence ABI.

- `howl-linux-host/src/terminal/cursor_blink.zig:3-38,40-226`
  Kitty source: `child-monitor.c:719-739`, `glfw.c:41-45`, `options/definition.py:358-427`, `cursor_trail.c:74-181`
  Notes: blink interval defaults, inactivity stop, shared text blink opacity, and trail decay timing.

- `howl-linux-host/src/terminal/surface.zig:155-167,225-242,398-425,428-431,570-583,601-616,779-906`
  Kitty source: `child-monitor.c:717-742,786-829`, `shaders.c:519-566`, `cursor_trail.c:15-181`, `options/definition.py:342-427`, `window.py:1737-1742`
  Notes: host-owned cadence facts, focus/unfocused substitution, render cadence upload, trail start threshold, trail decay, cursor visibility toggling, and published-source cursor ingestion.

- `howl-linux-host/src/terminal/surface.zig:1415-1547`
  Kitty source: `child-monitor.c:717-742,786-829`, `shaders.c:519-566`, `options/definition.py:342-427`
  Notes: host proof coverage for invalid animation branch, unfocused hollow substitution, explicit no-shape preservation, trail-start threshold, configured trail decay, and cursor config fixture defaults.

- `howl-linux-host/src/event.zig:194-202,240,263,273`
  Kitty source: `NO KITTY SOURCE`
  Notes: Howl-only event-loop consumption and threading of cursor redraw and cursor wait facts into host redraw intent and wait admission.

- `howl-linux-host/src/event.zig:52,72,89,255,631,653,668,684,692-764`
  Kitty source: `NO KITTY SOURCE`
  Notes: Howl-only event-loop cursor-fact storage, wait merging, null initialization, and local cursor-wait test fixtures.

### Host tests

- `howl-linux-host/src/terminal/surface_test.zig:407-447`
  Kitty source: `child-monitor.c:721-735`

- `howl-linux-host/src/terminal/surface_test.zig:1341-1389`
  Kitty source: `child-monitor.c:717-742`

- `howl-linux-host/src/terminal/surface_test.zig:1512-1547`
  Kitty source: `shaders.c:519-566`, `child-monitor.c:717-742`
  Notes: proof that host cursor facts preserve explicit no-shape while keeping visible cadence truth, and that unfocused hollow remains distinct from no-shape.

- `howl-render/src/vt_publication/source_slot.zig:461-494`
  Kitty source: `NO KITTY SOURCE`
  Notes: Howl-only retained-storage lifetime proof for source-slot cursor publication storage.

## Untraceable Or Howl-Only Cursor Code

The following cursor-touching code is not directly backed by a Kitty source line and should be treated as delete-or-replace pressure unless the user explicitly wants a Howl-owned invention:

- `howl-vt/src/route.zig:138-168,202-217` -> `NO KITTY SOURCE`
- `howl-vt/src/report.zig:228-260` -> `NO KITTY SOURCE`
- `howl-vt/simulation/protocol.zig:155-156,387-390,415-416` -> `NO KITTY SOURCE`
- `howl-vt/simulation/scrollback.zig:46-47,257-267,370-371,380-406` -> `NO KITTY SOURCE`
- `howl-render/src/vt_publication/prepare_queue.zig:22-198,288-305` -> `NO KITTY SOURCE`
- `howl-render/src/vt_publication/damage.zig:81-112` -> `NO KITTY SOURCE`
- `howl-render/src/vt_publication/source_slot.zig:152-306,495-525,545-559` -> `NO KITTY SOURCE`
- `howl-render/src/vt_publication/source_slot.zig:461-494` -> `NO KITTY SOURCE`
- `howl-render/src/text/contract.zig:23-36` -> `NO KITTY SOURCE`
- `howl-render/src/render_session.zig:381-415,499-504,586-666,854-879` -> `NO KITTY SOURCE`
- `howl-render/include/howl_render.h:1-240` -> `NO KITTY SOURCE`
- `howl-render/src/libhowl_render.zig:8-16` -> `NO KITTY SOURCE`
- `howl-linux-host/src/terminal/render_retained.zig:63-93,191-194` -> `NO KITTY SOURCE`
- `howl-linux-host/src/event.zig:194-202,240,263,273` -> `NO KITTY SOURCE`
- `howl-linux-host/src/event.zig:52,72,89,255,631,653,668,684,692-764` -> `NO KITTY SOURCE`

## Bottom Line

- VT parse, save/restore, alt-screen, explicit no-shape, DECSCUSR, DECRQSS cursor-style reporting, and cursor config defaults all have direct Kitty pressure.
- Render retained publication, source-slot retention, prepare-queue admission, render ABI seams, and host event-loop orchestration are partly or wholly Howl-owned inventions.
- Unbacked cursor code was found.
