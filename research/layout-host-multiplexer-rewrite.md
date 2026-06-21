# Host Layout Multiplexer Rewrite Research

Owner: host layout sprint planning.

Status:

- Active.
- Product code changes must follow the staged execution contract in this file.

## User Direction

- `window/` is responsible for SDL windowing.
- `layout/` is Howl's HTML/CSS structure layer.
- `layout/` defines the structure inside windows created and owned by `window/`.
- Comments must stay explicit. Use `//!` for unit-level docs and `///` for symbol-level docs.
- The top reference pressure for this slice is tmux `session/window/pane/layout` plus zellij `tab/pane/layout`.
- Panes must be loosely coupled from placement.
- Panes must be able to become tiled, horizontal/vertical by placement, floating, hidden/shown, and travel across splits, tabs, and windows.
- Tabs must be able to travel between windows.
- Floating panes must hide/show while staying accurate.
- The sprint must proceed strictly in three stages:
  1. make/move the planned files/folders
  2. define symbols, signatures and tests
  3. define signatures' bodies correctly to make correct valuable tests pass

## Problem Statement

Current host `layout/viewport.zig` is a lie. It mixes host window/tab-bar/terminal placement under a VT-shaped noun and blocks the introduction of real multiplexer structure. The host needs a structure layer that can mature into tabs, panes, splits, and floating placement without tying pane identity to one geometry slot.

## Reference Nouns Accepted For This Sprint

Top pressure:

- tmux: `session`, `window`, `pane`, `layout`
- zellij: `tab`, `pane`, `layout`

Supporting pressure:

- WezTerm: `window`, `tab`, `pane`, `split`, `mux`
- Ghostty: `Surface`, `SplitTree`, `View`
- Kitty: tab and splits UX pressure

Current decision:

- `layout/` will use multiplexer nouns first: `window`, `tab`, `pane`, `splits`, `tab_bar`, `scrollbar`, `scroll_chip`.
- `viewport` dies.
- `screen` stays VT-owned and is forbidden for host structure.
- `Surface` is not the top noun for this slice.
- `overlay` is rejected as a host structure noun. Scrollbar-related structure must use real owner nouns and explicit layer/z-index modeling.

## Target Owner Model

- `window/`
  - owns SDL windows and OS window lifecycle
- `layout/window.zig`
  - owns the interior structure of an OS window
- `layout/tab.zig`
  - owns one tab's structure inside a window
- `layout/pane.zig`
  - owns pane identity and pane placement facts that survive moves
- `layout/splits.zig`
  - owns tiled split structure over pane ids/handles
- `layout/tab_bar.zig`
  - owns tab bar band placement
- `layout/scrollbar.zig`
  - owns scrollbar placement within pane placement
- `layout/scroll_chip.zig`
  - owns scroll-chip placement and layering facts

Pane pressure:

- A pane is not an OS window.
- A pane is not a render ABI surface.
- A pane is not VT screen truth.
- A pane is a host multiplexer instance that can be placed, moved, hidden, floated, shown, and transferred.

## Planned File Moves And Adds

Stage 1 file work only:

- delete: `howl-linux-host/src/layout/viewport.zig`
- add: `howl-linux-host/src/layout/window.zig`
- add: `howl-linux-host/src/layout/tab.zig`
- add: `howl-linux-host/src/layout/pane.zig`
- add: `howl-linux-host/src/layout/tab_bar.zig`
- add: `howl-linux-host/src/layout/scrollbar.zig`
- add: `howl-linux-host/src/layout/scroll_chip.zig`
- reserve next-slice file: `howl-linux-host/src/layout/splits.zig`

Stage 1 notes:

- `splits.zig` may be added empty/stubbed if needed to make the owner path explicit, but split behavior implementation is not required until Stage 2/3.
- Current callers of `viewport.zig` should route to `window.zig` + `pane.zig` structure helpers instead of a one-file replacement lie.

## Symbol And Signature Contract

Stage 2 defines signatures and tests before meaningful bodies expand.

Required symbol pressure:

- `layout/window.zig`
  - functions that derive tab-bar band and tab body placement from host window facts
- `layout/tab.zig`
  - functions that derive pane root placement for one tab
- `layout/pane.zig`
  - `PaneId`
  - pane placement/visibility/floating facts
- `layout/tab_bar.zig`
  - tab-bar band placement only
- `layout/scrollbar.zig`
  - scrollbar placement relative to one pane placement
- `layout/scroll_chip.zig`
  - scroll-chip placement and explicit front/back layering facts
- `layout/splits.zig`
  - split tree over pane ids/handles, not embedded pane runtime state

Explicit tests required in Stage 2:

- host window interior placement after tab bar reservation
- single-pane tab body placement
- scrollbar and scroll-chip placement relative to pane placement
- split structure tests over pane ids once `splits.zig` lands
- pane move/hide/show/floating transfer tests as soon as the relevant symbols exist

## Execution Contract

### Condensed Stage 1 Contract

This narrows the earlier Stage 1 file-add list. Current source only proves one live geometry owner path: `layout/viewport.zig` feeds `events/event.zig` tab open/close, resize, input forwarding, and render placement (`howl-linux-host/src/events/event.zig:7`, `142-165`, `339-340`, `443-449`, `503-507`, `554-564`, `652-658`), while `layout.zig` still curates the lie as `pub const viewport` (`howl-linux-host/src/layout.zig:7`) and the host test root still imports that path (`howl-linux-host/src/host_test_root.zig:38`). `howl-linux-host/src/layout/viewport.zig:8-50` is still one owner carrying all current tab-bar reservation and terminal placement behavior. Stage 1 must therefore stay a structural owner move, not a behavioral split.

Exact files for Stage 1:

- add: `howl-linux-host/src/layout/window.zig`
- add: `howl-linux-host/src/layout/tab.zig`
- add: `howl-linux-host/src/layout/pane.zig`
- add: `howl-linux-host/src/layout/tab_bar.zig`
- add: `howl-linux-host/src/layout/overlay.zig`
- delete: `howl-linux-host/src/layout/viewport.zig`
- update: `howl-linux-host/src/layout.zig`
- update: `howl-linux-host/src/events/event.zig`
- update: `howl-linux-host/src/host_test_root.zig`

Exact temporary owner boundary for Stage 1 only:

- `howl-linux-host/src/events/window.zig` stays the SDL and OS-window owner only; no host structure moves into it (`howl-linux-host/src/events/window.zig:15-105`, `123-208`).
- `howl-linux-host/src/layout/window.zig` temporarily owns all geometry moved out of `layout/viewport.zig`: tab-bar reservation, content pixel/logical regions, terminal texture rect placement, and terminal logical input size.
- `howl-linux-host/src/layout/tab.zig`, `layout/pane.zig`, `layout/tab_bar.zig`, and `layout/overlay.zig` are Stage 1 placeholder owners only. They exist to engrave the planned folder boundary, not to introduce new behavior yet.
- `howl-linux-host/src/layout.zig` remains a curated package root only.

Exact symbol plan for Stage 1 only:

- move `Regions`, `Terminal`, `regions`, `terminal`, and `tabBarHeight` from `howl-linux-host/src/layout/viewport.zig` into `howl-linux-host/src/layout/window.zig` with no semantic change.
- change `howl-linux-host/src/events/event.zig` to import `layout/window.zig` instead of `layout/viewport.zig`, and retarget every current `Viewport.*` use to the new owner path only.
- change `howl-linux-host/src/layout.zig` export from `pub const viewport = @import("layout/viewport.zig");` to `pub const window = @import("layout/window.zig");`.
- change `howl-linux-host/src/host_test_root.zig` smoke import from `@import("layout.zig").viewport` to `@import("layout.zig").window`.
- add no public behavior symbols yet in `layout/tab.zig`, `layout/pane.zig`, `layout/tab_bar.zig`, or `layout/overlay.zig`.

Exact non-goals for Stage 1:

- do not add `howl-linux-host/src/layout/splits.zig` yet; no current caller or proof point requires it, so adding it in Stage 1 would be broadening scope without source pressure.
- do not introduce `PaneId`, split trees, floating geometry state, tab structs, or overlay placement helpers yet.
- do not move or rename the existing render/widget owner `howl-linux-host/src/tab_bar.zig` in Stage 1.
- do not change resize semantics, input routing semantics, render semantics, or terminal runtime behavior.
- do not rename the moved `Regions` and `Terminal` data shapes in Stage 1; owner path changes first, shape renames later.

Exact tests and grep gates for Stage 1:

- run `zig build check` in `howl-linux-host/`.
- run `zig build test:unit` in `howl-linux-host/`.
- grep gate: no `@import("../layout/viewport.zig")` or `@import("layout/viewport.zig")` remains under `howl-linux-host/src/**/*.zig`.
- grep gate: no `@import("layout.zig").viewport` remains under `howl-linux-host/src/**/*.zig`.
- grep gate: no `howl-linux-host/src/layout/viewport.zig` file remains.

Explicit stop conditions and blockers:

- stop if deleting `layout/viewport.zig` forces semantic edits outside the files listed above.
- stop if Stage 1 cannot stay green without inventing early `tab/pane/overlay` behavior.
- stop if the new `layout/tab_bar.zig` placeholder creates unavoidable ownership confusion with `howl-linux-host/src/tab_bar.zig` that cannot be resolved by comments and zero exported behavior alone.
- stop if any reference-backed requirement appears that contradicts this owner move and has not been receipted into the sprint artifact.

### Stage 1: Make Or Move Files/Folders

Acceptance:

- `viewport.zig` removed
- new `layout/` owner files exist
- imports route through the new owner paths
- no compatibility alias file left behind

Proof:

- grep for `viewport` in `howl-linux-host/src/layout` and host callers
- build/tests may be temporarily broken during the structural move, but the stage-end tree must be explicit

### Stage 2: Define Symbols, Signatures, And Tests

Acceptance:

- new files have unit docs with `//!`
- public symbols have `///` where needed for non-obvious owner contracts
- tests define the intended structure behavior before broad body work
- pane identity is separate from split placement in signatures

Proof:

- `zig fmt`
- grep for banned vague nouns introduced by the slice
- test roots compile once stub/initial bodies are coherent enough

### Stage 3: Define Bodies Correctly To Make Valuable Tests Pass

Acceptance:

- tests prove the new structure behavior
- old host behavior routes through the new owner paths
- pane placement can evolve toward splits/floats/tabs/windows without redoing owner boundaries

Proof:

- `zig build check`
- `zig build test:unit`
- `git diff --check`
- grep for stale `viewport` and stale old paths

## Initial Narrow Implementation Slice

The first execution slice inside this sprint should be:

- Stage 1: remove `layout/viewport.zig`; add `layout/window.zig`, `layout/tab.zig`, `layout/pane.zig`, `layout/tab_bar.zig`; the rejected `layout/overlay.zig` placeholder was removed by the accepted scrollbar layer slice
- Stage 2: define single-pane-only signatures and tests
- Stage 3: implement single-pane placement and route current callers through the new structure

Deliberately deferred to later slices inside the same sprint:

- real split tree behavior
- pane transfer across tabs/windows
- floating-pane retained geometry
- full scrollbar and scroll-chip owner rewrite

Those deferred slices must fit the owner model established here rather than redefining it.

## Stage 2 Scrollbar Layer Contract

Session: `teammate-2026-06-21-layout-mux-stage2-scroll-layer-01`

Verdict: ready, accepted by orchestrator with one clarification: `layout/z_index.zig` may exist only as the explicit host composition ordering contract. It must not grow into a generic constants bucket, layer manager, draw-policy owner, or hidden overlay replacement.

Problem:

- Stage 1 committed placeholder `howl-linux-host/src/layout/overlay.zig`.
- Existing host source still uses `OverlaySnapshot`, `overlaySnapshot`, and a local `overlay` value in the terminal surface path.
- User explicitly rejected `overlay`; Stage 2 must use `scrollbar` and `scroll_chip` with explicit z-index ordering.

Reference pressure:

- `utils/dev_references/terminals/tmux/tmux.h` uses pane `zentry` and window `z_index`.
- `utils/dev_references/terminals/tmux/layout-custom.c` dumps floating panes by iterating `w->z_index` and fixes pane z-index after layout application.
- `utils/dev_references/terminals/tmux/window-visible.c` accounts for pane scrollbars while iterating z-index visibility.
- `utils/dev_references/terminals/tmux/cmd-join-pane.c` exposes `move-pane -z` with front/back/forward/backward pressure.
- `utils/dev_references/terminals/zellij/zellij-server/src/panes/floating_panes/mod.rs` owns `z_indices` and produces a stack of layers.
- `utils/dev_references/terminals/zellij/zellij-server/src/output/mod.rs` consumes explicit `z_index` against a floating panes stack.

Coder contract:

- Delete `howl-linux-host/src/layout/overlay.zig`; do not leave an alias, shim, empty file, export, or compatibility import.
- Add `howl-linux-host/src/layout/z_index.zig` as the host composition z-index contract only.
- Add `howl-linux-host/src/layout/scrollbar.zig` for scrollbar track placement inside a pane.
- Add `howl-linux-host/src/layout/scroll_chip.zig` for scroll-chip/thumb placement above the scrollbar track.
- Update `howl-linux-host/src/layout.zig` to export `z_index`, `scrollbar`, and `scroll_chip`.
- Replace `Layout.ScrollbarLayout` with `Layout.scrollbar.Placement` plus `Layout.scroll_chip.Placement` in the frame path.
- Update `howl-linux-host/src/scroll_bar.zig` so interaction state can remain there, but geometry output is split into scrollbar and scroll-chip placements.
- Remove `OverlaySnapshot` and `overlaySnapshot` from `howl-linux-host/src/buckets that must die/bucket2.zig`; expose separate scrollbar and scroll-chip placement methods.
- Update `howl-linux-host/src/events/event.zig` to carry scrollbar and scroll-chip placements through snapshot/frame presentation.
- Update texture presentation so draw order is explicit: tab bar, terminal texture, scrollbar, scroll chip.
- Do not change C ABI or render ABI contracts.

Exact symbols:

- `layout/z_index.zig`: `pub const ZIndex = enum(u8) { pane = 0, scrollbar = 10, scroll_chip = 20 };`
- `layout/z_index.zig`: `pub fn before(a: ZIndex, b: ZIndex) bool`
- `layout/scrollbar.zig`: `pub const Placement = struct { visible: bool, rect: Layout.Rect, z_index: ZIndex };`
- `layout/scrollbar.zig`: `pub fn hidden(pane_rect: Layout.Rect) Placement`
- `layout/scrollbar.zig`: `pub fn place(pane_rect: Layout.Rect, logical_pane: Layout.Size, logical_x: c_int, logical_y: c_int, logical_width: c_int, logical_height: c_int) Placement`
- `layout/scroll_chip.zig`: `pub const Placement = struct { visible: bool, rect: Layout.Rect, z_index: ZIndex };`
- `layout/scroll_chip.zig`: `pub fn hidden(scrollbar: Scrollbar.Placement) Placement`
- `layout/scroll_chip.zig`: `pub fn place(scrollbar: Scrollbar.Placement, logical_pane: Layout.Size, logical_y: c_int, logical_height: c_int) Placement`
- `scroll_bar.zig`: expose separate `scrollbar(...) Layout.scrollbar.Placement` and `scrollChip(...) Layout.scroll_chip.Placement` methods from `State`.
- terminal surface path: expose separate `scrollbarPlacement(...) Layout.scrollbar.Placement` and `scrollChipPlacement(...) Layout.scroll_chip.Placement` methods.

Tests and gates:

- Add inline tests in `layout/z_index.zig` proving scroll chip is above scrollbar and scrollbar is above pane.
- Add inline tests in `layout/scrollbar.zig` proving track placement scales logical track into pane rect and hidden placement preserves scrollbar z-index.
- Add inline tests in `layout/scroll_chip.zig` proving chip placement stays inside scrollbar track and chip z-index is above scrollbar.
- Update `scroll_bar.zig` tests to assert scrollbar track and scroll chip are separate placements.
- Update `host_test_root.zig` imports for the new layout owners.
- Add stale-symbol checks: no `layout/overlay.zig`, no `layout/overlay.zig` import, no `OverlaySnapshot`, no `overlaySnapshot`, no local `overlay` variable.
- Verify with `zig fmt build.zig src`, `zig build check`, `zig build test:unit`, and `git diff --check` in `howl-linux-host/`.

Deferred:

- Floating-pane transfer, pane hide/show transfer, z-index mutation operations, split trees, tab transfer between windows, and full scrollbar interaction rewrite.
- Renaming root `scroll_bar.zig` interaction/state owner unless a narrow compiler-required retarget forces it.
- Any `overlay`, `viewport`, `screen`, `types.zig`, bucket structs, vague names, or ABI changes.

## Stage 3 Pane/Tab Structure Contract

Session: `teammate-2026-06-21-layout-mux-pane-tab-plan-01`

Verdict: ready, accepted by orchestrator with clarifications: `Pane.TerminalPlacement` may describe host geometry for terminal texture placement inside a pane only; it must not imply pane ownership of render ABI resources. `PaneId.first` is a temporary single-pane identity seam only; do not add an allocator or multi-pane id source in this slice.

Problem:

- Current committed host layout has the right file boundary but still routes behavior through temporary Stage 1 names in `layout/window.zig`: `Regions`, `Terminal`, `regions`, `terminal`, and `tabBarHeight`.
- `layout/tab.zig`, `layout/pane.zig`, and `layout/tab_bar.zig` are placeholders.
- `events/event.zig` still has host-structure locals named `next_viewport`, `viewport`, and `after_viewport`.

Reference pressure:

- `utils/dev_references/terminals/tmux/layout.c` keeps window layout as a tree over panes, proving pane identity must be separate from placement.
- `utils/dev_references/terminals/tmux/tmux.h` gives `window_pane`, active pane, pane lists, z-index, and `layout_root`, proving window-owned pane collection/order with separate panes.
- `utils/dev_references/terminals/tmux/window.c` computes pane index and z-index by walking window-owned pane lists, proving identity/order is not embedded in render geometry.
- `utils/dev_references/terminals/tmux/layout-custom.c` assigns panes into layout cells and then fixes z-index and pane offsets, supporting a placement seam before split implementation.
- `utils/dev_references/terminals/zellij/zellij-server/src/tab/mod.rs` has tabs holding panes and coordinates/size, supporting `layout/tab.zig` as tab body to pane placement owner.
- `utils/dev_references/terminals/zellij/zellij-server/src/panes/terminal_pane.rs` has explicit `PaneId` variants, source-backing a minimal pane id.
- `utils/dev_references/terminals/zellij/zellij-server/src/panes/floating_panes/mod.rs` tracks panes, positions, z-indices, and layers by `PaneId`, supporting identity/placement separation without implementing floating now.
- `utils/dev_references/terminals/wezterm/docs/cli/cli/split-pane.md` targets pane ids for split operations, supporting early `PaneId` and deferred split/move behavior.
- `utils/dev_references/terminals/wezterm/docs/config/lua/wezterm.mux/spawn_window.md` and `mux-window/spawn_tab.md` return distinct mux window/tab/pane objects.

Coder contract:

- Update `howl-linux-host/src/layout.zig` to export `tab`, `pane`, and `tab_bar`; keep root geometry helpers only if still used by owner files.
- Update `howl-linux-host/src/layout/window.zig` to replace public `Regions`, `Terminal`, `regions`, `terminal`, and `tabBarHeight` with `Interior` and `interior`.
- Update `howl-linux-host/src/layout/tab_bar.zig` with tab-bar band owner symbols and tests.
- Update `howl-linux-host/src/layout/tab.zig` with single-pane tab body/placement symbols and tests.
- Update `howl-linux-host/src/layout/pane.zig` with `PaneId`, pane placement, terminal placement symbols, and tests.
- Update `howl-linux-host/src/events/event.zig` so open-tab sizing, input forwarding, render snapshot, resize, and close-tab resize route through `Window.interior`, `Tab.body`, `Tab.singlePane`, and `Pane.terminal`.
- Remove `viewport` local names from host layout paths.
- Update `howl-linux-host/src/host_test_root.zig` imports and stale-symbol checks.
- Do not add `howl-linux-host/src/layout/splits.zig` in this slice.

Exact symbols:

- `layout/tab_bar.zig`: `pub const Band = struct { rect: Layout.Rect, pixel_height: u32, logical_height: u32 };`
- `layout/tab_bar.zig`: `pub fn height(config: *const Config, tab_count: u8) u32`
- `layout/tab_bar.zig`: `pub fn band(window: *const Window, config: *const Config, tab_count: u8) Band`
- `layout/window.zig`: `pub const Interior = struct { tab_bar: TabBar.Band, tab_body_rect: Layout.Rect, tab_body_px: Layout.Size, tab_body_logical: Layout.Size };`
- `layout/window.zig`: `pub fn interior(window: *const Window, tab_bar: *const TabBarConfig, tab_count: u8) Interior`
- `layout/tab.zig`: `pub const Body = struct { rect: Layout.Rect, pixel_size: Layout.Size, logical_size: Layout.Size };`
- `layout/tab.zig`: `pub fn body(window: WindowLayout.Interior) Body`
- `layout/tab.zig`: `pub fn singlePane(body_value: Body, pane_id: Pane.PaneId) Pane.Placement`
- `layout/pane.zig`: `pub const PaneId = enum(u16) { first = 0, _ };`
- `layout/pane.zig`: `pub const Placement = struct { id: PaneId, rect: Layout.Rect, pixel_size: Layout.Size, logical_size: Layout.Size };`
- `layout/pane.zig`: `pub const TerminalPlacement = struct { pane: Placement, texture_px: Layout.Size, texture_rect: Layout.Rect, logical_size: Layout.Size };`
- `layout/pane.zig`: `pub fn place(id: PaneId, rect: Layout.Rect, pixel_size: Layout.Size, logical_size: Layout.Size) Placement`
- `layout/pane.zig`: `pub fn terminal(placement: Placement, texture_px: Layout.Size) TerminalPlacement`

Tests and gates:

- `layout/tab_bar.zig`: `height` hides below configured minimum and shows at or above configured minimum.
- `layout/tab_bar.zig`: `band` returns zero-height rect when hidden and top band rect when shown.
- `layout/window.zig`: `interior` reserves tab-bar band and exposes tab body rect/sizes below it.
- `layout/tab.zig`: `body` maps window interior tab body exactly.
- `layout/tab.zig`: `singlePane` preserves `PaneId.first` and body geometry.
- `layout/pane.zig`: `place` preserves pane identity separately from rect/sizes.
- `layout/pane.zig`: `terminal` derives texture rect/logical size inside pane placement.
- `host_test_root.zig`: import `@import("layout.zig").tab`, `pane`, and `tab_bar`.
- Stale grep gates in host production source: no `LayoutWindow.Regions`, no `LayoutWindow.Terminal`, no `LayoutWindow.regions`, no `LayoutWindow.terminal`, no `pub const Regions`, no `pub const Terminal` in `layout/window.zig`, no local `next_viewport`, no local `after_viewport`, no `const viewport = LayoutWindow`, no `layout/overlay.zig`, no `OverlaySnapshot`, no `overlaySnapshot`.
- Verify with `zig fmt build.zig src`, `zig build check`, `zig build test:unit`, `git diff --check`, and stale-symbol searches in `howl-linux-host/`.

Deferred:

- No `layout/splits.zig` yet.
- No split tree, split direction, resize tree, split serialization, floating pane placement, hide/show retention, z-index mutation, pane transfer, or tab transfer between windows.
- No C ABI or render ABI changes.
- No root `scroll_bar.zig` rename or broader scrollbar interaction rewrite.
- No `overlay`, `viewport`, host `screen`, `types.zig`, manager/engine/controller/utils owner, or new vague bucket structs.
