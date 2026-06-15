# Cursor Kitty Amended Slices

## Receipt Header

- Artifact owner: `research/2026-06-15-cursor-kitty-amended-slices.md`
- Role: reviewer amendment from hostile audit findings
- Session id: no internal session identifier exposed beyond this task session
- Basis:
  - `research/2026-06-15-cursor-kitty-line-map.md`
  - reviewer judgment that the original cursor sprint missed both stated goals:
    1. remove Howl's bolted-on cursor code
    2. port Kitty's cursor code to its entirety

## Sprint Verdict Basis

- The completed sprint achieved partial Kitty-shaped behavior.
- The completed sprint did not remove all bolted-on Howl cursor code.
- The completed sprint did not port Kitty's cursor code in its entirety.
- The amended sprint below is the execution shape the cursor work should have had after those findings were known.

## Remaining NO KITTY SOURCE Code That Must Be Deleted Or Replaced

- `howl-vt/src/route.zig:138-168,202-217`
- `howl-vt/src/report.zig:228-260`
- `howl-render/src/vt_publication/prepare_queue.zig:22-198,288-305`
- `howl-render/src/vt_publication/source_slot.zig:152-306,461-494,495-525,545-559`
- `howl-render/src/render_session.zig:381-415,499-504,586-666,854-879`
- `howl-linux-host/src/terminal/render_retained.zig:63-93,191-194`
- `howl-linux-host/src/event.zig:52,72,89,194-202,240,255,263,273,631,653,668,684,692-764`
- `howl-vt/simulation/protocol.zig:155-156,387-390,415-416`
- `howl-vt/simulation/scrollback.zig:46-47,257-267,370-371,380-406`

## Ambiguous Zones Needing User Decision

- Multiple cursors are still missing as a full port item, but the earlier sprint marked them non-goal. The user must decide whether the amended sprint now expands to full Kitty multiple-cursor support or records an explicit override against "port Kitty's cursor code to its entirety".
- Kitty's full cursor replay/export shape is still not present as one coherent Howl owner. The user must decide whether the product requires full Kitty replay/export parity or whether the C ABI/render surface boundary intentionally replaces part of that shape with a different exported consequence model.
- Some Howl-owned render/host orchestration may be unavoidable because Howl is embeddable and C-ABI-first. The user must decide whether "port Kitty's cursor code to its entirety" means behavior-only parity at those seams or a stricter structural deletion of as much Howl-owned cursor orchestration as possible.

## Ordered Slice List

### Slice 1: Delete VT Cursor Plumbing That Has No Kitty Owner

- Slice type: deletion-driven
- Goal:
  - remove Howl-only VT cursor routing/plumbing that survived the original sprint
  - delete cursor report assembly with no Kitty source match
- Exact files:
  - `howl-vt/src/route.zig`
  - `howl-vt/src/report.zig`
  - `howl-vt/test/unit/csi_mapping_test.zig`
  - `howl-vt/test/unit/terminal_modes_test.zig`
  - `howl-vt/test/unit/terminal_surface_test.zig`
  - `howl-vt/test/unit/terminal_cursor_test.zig`
  - `howl-vt/test/unit/terminal_snapshot_test.zig`
- Required delete/replace focus:
  - delete or replace `howl-vt/src/route.zig:138-168,202-217`
  - delete or replace `howl-vt/src/report.zig:228-260`
- Exact proof roots:
  - `howl-vt/test/unit/csi_mapping_test.zig`
  - `howl-vt/test/unit/terminal_modes_test.zig`
  - `howl-vt/test/unit/terminal_surface_test.zig`
  - `howl-vt/test/unit/terminal_cursor_test.zig`
  - `howl-vt/test/unit/terminal_snapshot_test.zig`
  - `howl-vt/src/report.zig` inline tests
- Stop conditions:
  - stop if cursor routing remains in an unbacked Howl dispatch spine rather than a Kitty-pressured owner split
  - stop if `DECCIR` cursor report behavior is preserved without an explicit user override against Kitty
  - stop if VT proof roots still mention deleted cursor report behavior without replacement proof

### Slice 2: Delete Or Replace Howl-Invented Retained Cursor Pipeline

- Slice type: deletion-driven
- Goal:
  - remove the retained cursor publication pipeline that is still Howl-invented rather than a true Kitty cursor port
  - replace only the minimum seams truly forced by the Howl C ABI or retained renderer product boundary
- Exact files:
  - `howl-render/src/vt_publication/prepare_queue.zig`
  - `howl-render/src/vt_publication/source_slot.zig`
  - `howl-render/src/render_session.zig`
  - `howl-linux-host/src/terminal/render_retained.zig`
  - `howl-render/src/vt_publication/publication.zig`
  - `howl-render/src/vt_publication/damage.zig`
  - `howl-render/src/vt_publication/cursor.zig`
  - `howl-render/src/c/text_session.zig`
  - `howl-render/src/text/scene_rects.zig`
  - `howl-linux-host/src/terminal/surface.zig`
  - `howl-linux-host/src/terminal/vt_surface.zig`
  - `howl-render/src/vt_publication/abi.zig`
- Required delete/replace focus:
  - delete or replace `howl-render/src/vt_publication/prepare_queue.zig:22-198,288-305`
  - delete or replace `howl-render/src/vt_publication/source_slot.zig:152-306,461-494,495-525,545-559`
  - delete or replace `howl-render/src/render_session.zig:381-415,499-504,586-666,854-879`
  - delete or replace `howl-linux-host/src/terminal/render_retained.zig:63-93,191-194`
- Exact proof roots:
  - `howl-render/src/vt_publication/publication.zig` inline tests
  - `howl-render/src/vt_publication/damage.zig` inline tests
  - `howl-render/src/vt_publication/cursor.zig` inline tests
  - `howl-render/src/c/text_session.zig` inline tests
  - `howl-render/src/text/scene_rects.zig` inline tests
  - `howl-linux-host/src/terminal/vt_surface.zig` inline tests
  - `howl-linux-host/src/terminal/surface_test.zig`
- Stop conditions:
  - stop if the retained pipeline survives mainly because it already exists rather than because the C ABI/product boundary proves it necessary
  - stop if any remaining cursor-retention owner is left as `NO KITTY SOURCE` without a fresh explicit justification of why Howl must invent it
  - stop if render or host policy continues to mutate cursor truth that should still belong to a smaller cursor owner

### Slice 3: Delete Howl-Owned Host Cursor Event/Cadence Policy

- Slice type: deletion-driven
- Goal:
  - remove host cursor event/cadence orchestration that is still Howl-owned cursor policy rather than a minimal host consequence model pressured by Kitty
  - collapse the event-loop cursor policy surface to the smallest necessary host seam
- Exact files:
  - `howl-linux-host/src/event.zig`
  - `howl-linux-host/src/terminal/surface.zig`
  - `howl-linux-host/src/terminal/cursor_blink.zig`
  - `howl-linux-host/src/terminal/render_retained.zig`
  - `howl-linux-host/src/terminal/surface_test.zig`
- Required delete/replace focus:
  - delete or replace `howl-linux-host/src/event.zig:52,72,89,194-202,240,255,263,273,631,653,668,684,692-764`
  - delete or replace any remaining host-side cursor policy in `howl-linux-host/src/terminal/surface.zig:155-167,398-425,779-906` that cannot be traced to Kitty or to a forced host-only cadence obligation
- Exact proof roots:
  - `howl-linux-host/src/terminal/surface_test.zig`
  - `howl-linux-host/src/terminal/vt_surface.zig` inline tests
  - `howl-linux-host/src/event.zig` tests
  - `howl-linux-host/src/terminal/cursor_blink.zig` inline tests
- Stop conditions:
  - stop if the host event loop still owns cursor policy beyond wake/wait/present obligations that the host boundary truly forces
  - stop if cursor wait/redraw choreography remains Howl-invented without explicit Kitty pressure or explicit user override
  - stop if host-side cursor blink/trail policy survives as broad local machinery instead of the smallest accountable host owner surface

### Slice 4: Delete Or Quarantine Unbacked Cursor Diagnostics And Simulation Code

- Slice type: deletion-driven
- Goal:
  - remove or explicitly quarantine remaining VT cursor diagnostics/simulation code that has no Kitty source and only preserves Howl-owned cursor accounting
- Exact files:
  - `howl-vt/simulation/protocol.zig`
  - `howl-vt/simulation/scrollback.zig`
  - any curated test roots that still rely on those cursor diagnostics
- Required delete/replace focus:
  - delete or replace `howl-vt/simulation/protocol.zig:155-156,387-390,415-416`
  - delete or replace `howl-vt/simulation/scrollback.zig:46-47,257-267,370-371,380-406`
- Exact proof roots:
  - simulation or diagnostic roots that still consume cursor row/col/shape snapshots
  - any package root that would fail if these cursor diagnostics are removed
- Stop conditions:
  - stop if these cursor-only diagnostics remain merely because they are convenient local tooling
  - stop if deleting them exposes hidden runtime cursor dependencies that should instead live in accountable proof roots

### Slice 5: Port Kitty Multiple Cursors End To End Or Escalate For User Override

- Slice type: missing-port-driven
- Goal:
  - finish the still-missing Kitty multiple-cursor port from VT protocol noun through shipped VT surface and render consumption
  - if the product intentionally refuses multiple cursors, force an explicit user override receipt against the original sprint goal
- Exact files:
  - `howl-vt/src/vocabulary.zig`
  - `howl-vt/src/kitty/apply.zig`
  - `howl-vt/src/ffi/surface.zig`
  - `howl-vt/include/howl_vt.h`
  - `howl-vt/test/abi.zig`
  - `howl-render/src/vt_publication/abi.zig`
  - `howl-render/src/vt_publication/publication.zig`
  - `howl-render/src/vt_publication/source_slot.zig`
  - `howl-render/src/vt_publication/cursor.zig`
  - `howl-render/src/text/scene_rects.zig`
  - `howl-linux-host/src/terminal/vt_surface.zig`
  - `howl-linux-host/src/terminal/surface.zig`
- Missing-port basis:
  - protocol noun still exists in `howl-vt/src/vocabulary.zig:193-195`
  - VT export still hard-codes no extra cursors in `howl-vt/src/ffi/surface.zig:252-253`
  - render can consume extras in `howl-render/src/vt_publication/cursor.zig:173-202`
- Exact proof roots:
  - `howl-vt/test/abi.zig`
  - `howl-render/src/vt_publication/abi.zig` inline tests
  - `howl-render/src/vt_publication/publication.zig` inline tests
  - `howl-render/src/vt_publication/source_slot.zig` inline tests
  - `howl-render/src/vt_publication/cursor.zig` inline tests
  - `howl-render/src/text/scene_rects.zig` inline tests
  - `howl-linux-host/src/terminal/vt_surface.zig` inline tests
  - `howl-linux-host/src/terminal/surface_test.zig`
- Stop conditions:
  - stop if multiple cursors remain intentionally absent without an explicit user override receipt
  - stop if VT still exports `extra_cursor_count = 0` by construction after this slice
  - stop if render keeps extra-cursor consumption code without a matching VT producer or a removal decision

### Slice 6: Port Full Kitty Cursor Replay/Export Shape As One Coherent Owner Or Escalate

- Slice type: missing-port-driven
- Goal:
  - finish the still-partial Kitty cursor replay/export behavior as one coherent Howl owner
  - stop treating partial reports as completion of the full Kitty cursor export surface
- Exact files:
  - `howl-vt/src/report.zig`
  - `howl-vt/src/terminal.zig`
  - `howl-vt/src/ffi/surface.zig`
  - `howl-vt/include/howl_vt.h`
  - `howl-vt/test/unit/terminal_modes_test.zig`
  - `howl-vt/test/unit/terminal_cursor_test.zig`
  - `howl-vt/test/abi.zig`
- Missing-port basis:
  - only partial pieces currently exist in `howl-vt/src/report.zig:130-170,203-210`
  - the original sprint never established one coherent owner equivalent to Kitty cursor replay/export behavior
- Exact proof roots:
  - `howl-vt/test/unit/terminal_modes_test.zig`
  - `howl-vt/test/unit/terminal_cursor_test.zig`
  - `howl-vt/test/abi.zig`
  - `howl-vt/src/report.zig` inline tests
- Stop conditions:
  - stop if the product boundary intentionally replaces part of Kitty replay/export behavior and no explicit user decision documents that replacement
  - stop if cursor export remains fragmented across unrelated report helpers without one accountable owner

### Slice 7: Final Structural Review Of Remaining Cursor Owners Against Kitty Entirety Goal

- Slice type: deletion-driven plus missing-port-driven closeout
- Goal:
  - prove no remaining cursor-touching Howl code survives without either exact Kitty backing or an explicit user-approved override
  - close the amended sprint only after every remaining cursor owner passes the line-map standard
- Exact files:
  - `research/2026-06-15-cursor-kitty-line-map.md`
  - `research/2026-06-15-cursor-kitty-amended-slices.md`
  - `sprints/current.txt`
  - `loops/cursor-kitty-full-sprint.txt`
- Exact proof roots:
  - full line-map rereview against current tree
  - `zig build test:unit` in `howl-vt`
  - `zig build test:abi` in `howl-vt`
  - `zig build test` in `howl-render`
  - `timeout 300s zig build test:unit` in `howl-linux-host`
- Stop conditions:
  - stop if any remaining cursor-touching line is not mapped to exact Kitty lines or explicit `NO KITTY SOURCE`
  - stop if any `NO KITTY SOURCE` cursor code remains without being either deleted, replaced, or explicitly user-approved as a Howl invention
  - stop if the sprint still only achieves partial Kitty-shaped behavior instead of the full stated goal

## Reviewer Bottom Line

- The original sprint should have split into a deletion campaign and a missing-port campaign instead of stopping at behavior-level parity.
- The amended execution shape above does not shrink scope.
- Without these amended slices, the cursor work remains incomplete against the original user goal.
