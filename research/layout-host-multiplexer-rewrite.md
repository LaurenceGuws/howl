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

## Stage 4 Split Structure Contract

Session: `teammate-2026-06-21-layout-mux-splits-plan-01`

Verdict: ready, accepted by orchestrator with clarification: stale-name gates must target host layout structure symbols and files. They must not reject official VT scroll viewport protocol names or GL viewport API spellings.

Problem:

- Current layout has real window/tab/tab-bar/pane owners, but no split owner.
- The next smallest multiplexer slice is a tested split-tree placement owner over `Pane.PaneId` that computes host geometry without adding runtime behavior, hidden panes, transfers, resize interaction, serialization, render ABI changes, or terminal state.

Reference pressure:

- `utils/dev_references/terminals/tmux/layout.c` keeps split layout as a tree of container cells and pane leaves.
- `utils/dev_references/terminals/tmux/layout.c` separates node cells from window pane leaves.
- `utils/dev_references/terminals/tmux/layout.c` derives z-index from pane leaves after walking layout.
- `utils/dev_references/terminals/tmux/layout-custom.c` serializes left-right and top-bottom split kinds, but serialization is deferred.
- `utils/dev_references/terminals/zellij/zellij-utils/src/input/layout.rs` has explicit horizontal/vertical split direction pressure and stores tiled pane layouts as children with split direction.
- `utils/dev_references/terminals/zellij/zellij-server/src/panes/tiled_panes/tiled_pane_grid.rs` keeps tiled panes keyed by `PaneId` and computes geometry separately.
- `utils/dev_references/terminals/wezterm/docs/cli/cli/split-pane.md` targets pane ids and returns pane ids for split operations.

Coder contract:

- Add `howl-linux-host/src/layout/splits.zig` as the owner of split layout shape and deterministic pane placement.
- Update `howl-linux-host/src/layout.zig` to export `splits`.
- Update `howl-linux-host/src/layout/tab.zig` only if needed to route `singlePane` or two-pane placement through `Splits` without broadening behavior.
- Update `howl-linux-host/src/host_test_root.zig` to import `layout.splits` and add targeted stale-symbol gates if needed.
- Do not change `events/event.zig` unless compile proof requires only narrow import/name fallout.

Exact symbols:

- `layout/splits.zig`: `pub const Direction = enum { left_right, top_bottom };`
- `layout/splits.zig`: `pub const Leaf = struct { pane: Pane.PaneId };`
- `layout/splits.zig`: `pub const Pair = struct { direction: Direction, first: Leaf, second: Leaf };`
- `layout/splits.zig`: `pub const Tree = union(enum) { leaf: Leaf, pair: Pair };`
- `layout/splits.zig`: `pub fn leaf(pane: Pane.PaneId) Tree`
- `layout/splits.zig`: `pub fn pair(direction: Direction, first: Pane.PaneId, second: Pane.PaneId) Tree`
- `layout/splits.zig`: `pub fn place(body_value: Tab.Body, tree: Tree, out: []Pane.Placement) []Pane.Placement`

Rules:

- `Tree` owns layout shape only.
- `Pane.Placement` remains the host geometry output.
- `Pane.PaneId` remains identity.
- `Tab.Body` remains the tab content rectangle.
- `place` must assert output capacity for the tree leaf count.
- `place` must not allocate, and must not mutate terminal/render/runtime state.
- For odd dimensions, give the remainder to the second pane.

Tests and gates:

- Single leaf fills the whole `Tab.Body`.
- Left-right pair splits width and preserves full height.
- Top-bottom pair splits height and preserves full width.
- Pane ids in output match tree leaf order.
- Odd pixel/logical sizes preserve total coverage without overlap.
- If current test style allows assertion testing, prove insufficient output capacity asserts in safety builds; otherwise rely on explicit `std.debug.assert` in implementation.
- Verify with `zig fmt build.zig src`, `zig build check`, `zig build test:unit`, `git diff --check`, and targeted stale-symbol searches in `howl-linux-host/`.

Deferred:

- Dynamic pane id allocation, split target lookup, focus model, pane close/rebalance, interactive resizing, hidden pane retention, floating panes, pane/tab transfer, z-order repair, layout serialization, runtime event routing for split commands, and any render or C ABI contract.

## Stage 5 Tab/Splits Seam Contract

Session: `teammate-2026-06-21-layout-mux-tab-splits-plan-02`

Verdict: ready, accepted by orchestrator. This supersedes the rejected first tab/splits plan by explicitly avoiding the `tab.zig`/`splits.zig` import cycle.

Problem:

- `layout/splits.zig` owns pure split placement but currently imports `layout/tab.zig` for `Tab.Body`.
- `layout/tab.zig` still exposes `singlePane` as a direct `Pane.place` wrapper.
- A tab-owned split-placement seam must not create an import cycle.

Reference pressure:

- `utils/dev_references/terminals/tmux/tmux.h` proves pane identity/runtime facts and layout cells are related but distinct through `window_pane.layout_cell`.
- `utils/dev_references/terminals/tmux/tmux.h` proves windows own pane lists and `layout_root`.
- `utils/dev_references/terminals/tmux/tmux.h` proves layout cells carry geometry and optional pane leaves, not tab/window convenience wrappers.
- `utils/dev_references/terminals/tmux/layout-set.c` applies pane leaves through layout geometry after creating a layout root.
- `utils/dev_references/terminals/zellij/zellij-server/src/tab/mod.rs` proves tabs hold multiple panes and track coordinates/sizes.
- `utils/dev_references/terminals/zellij/zellij-server/src/tab/layout_applier.rs` proves tab layout application owns the layout-to-pane application seam.
- `utils/dev_references/terminals/zellij/zellij-utils/src/input/layout.rs` proves split layout shape is separate from runtime panes.
- `utils/dev_references/terminals/wezterm/docs/cli/cli/split-pane.md` proves split operations produce pane ids and keep direction/target behavior separate from move-pane/top-level behavior.

Coder contract:

- Update `howl-linux-host/src/layout/splits.zig` so it no longer imports `layout/tab.zig`.
- Change `Splits.place` to take concrete geometry directly: `rect`, `pixel_size`, and `logical_size`.
- Update `howl-linux-host/src/layout/tab.zig` to import `splits.zig` and expose `placePanes` as the tab-owned body-to-split-placement seam.
- Update `singlePane` to route through `placePanes` and `Splits.leaf`.
- Do not add files, delete files, or change `events/event.zig` unless compile proof requires narrow fallout.

Exact symbols:

- `layout/splits.zig`: remove `const Tab = @import("tab.zig");`
- `layout/splits.zig`: `pub fn place(rect: Layout.Rect, pixel_size: Layout.Size, logical_size: Layout.Size, tree: Tree, out: []Pane.Placement) []Pane.Placement`
- `layout/tab.zig`: add `const Splits = @import("splits.zig");`
- `layout/tab.zig`: `pub fn placePanes(body_value: Body, tree: Splits.Tree, out: []Pane.Placement) []Pane.Placement`
- `layout/tab.zig`: keep `pub fn singlePane(body_value: Body, pane_id: Pane.PaneId) Pane.Placement`, implemented through a local one-item placement array and `placePanes(body_value, Splits.leaf(pane_id), out[0..])`.

Tests and gates:

- Update `layout/splits.zig` tests to call `place(testRect(), testPixelSize(), testLogicalSize(), tree, out[0..])`.
- Replace private `testBody() Tab.Body` with `testRect() Layout.Rect`, `testPixelSize() Layout.Size`, and `testLogicalSize() Layout.Size`.
- Keep split tests for leaf fill, left-right, top-bottom, pane order, and odd-size total coverage.
- Add `layout/tab.zig` tests for `placePanes` routing split tree inside tab body and `singlePane` matching split-leaf placement.
- Confirm `layout/splits.zig` has no `@import("tab.zig")`; `layout/tab.zig` may import `splits.zig`.
- Verify with `zig fmt build.zig src`, `zig build check`, `zig build test:unit`, `git diff --check`, and targeted stale-symbol searches.

Deferred:

- Split command bindings, event routing, dynamic pane id allocation, split target lookup, focus, pane activation, close/rebalance, interactive resizing, hidden pane retention, floating panes, pane/tab transfer, z-index repair, serialization, runtime multi-pane terminal ownership, C ABI changes, render ABI changes, and any rejection of official VT scroll viewport or GL viewport spellings.

## Stage 6 Runtime Tab Owner Contract

Session: `teammate-2026-06-21-layout-mux-runtime-tab-plan-01`

Verdict: ready, accepted by orchestrator with clarification: forwarded associated type constants in `tab.zig` are current-behavior delegation seams only. They are not compatibility shims or a new public host integration API.

Problem:

- Layout can describe pane identity and split placement, but runtime still treats each tab as one raw terminal surface stored directly in `tab_bar/tab_slots.zig` and orchestrated by `events/event.zig`.
- The next source-backed runtime slice is to introduce a real tab owner while preserving current one-terminal-per-tab behavior.

Reference pressure:

- `utils/dev_references/terminals/tmux/tmux.h` proves `window_pane` owns pane identity/runtime facts and links to layout cells.
- `utils/dev_references/terminals/tmux/tmux.h` proves tmux windows own active pane, pane lists, z-index list, and layout root.
- `utils/dev_references/terminals/tmux/layout.c` proves layout leaves attach panes while layout nodes stay separate from pane runtime.
- `utils/dev_references/terminals/tmux/window.c` proves pane index/count are derived from window-owned pane lists.
- `utils/dev_references/terminals/zellij/zellij-server/src/tab/mod.rs` proves tabs hold multiple panes and track their coordinates/sizes.
- `utils/dev_references/terminals/zellij/zellij-server/src/panes/tiled_panes/mod.rs` proves tiled panes are pane-id keyed collections.
- `utils/dev_references/terminals/zellij/zellij-server/src/panes/floating_panes/mod.rs` proves floating panes are separately owned by pane id, z-order, and visibility.
- `utils/dev_references/terminals/wezterm/docs/config/lua/mux-window/spawn_tab.md` and `wezterm.mux/spawn_window.md` prove mux windows/tabs/panes are distinct objects.

Coder contract:

- Add `howl-linux-host/src/tab.zig` as the host runtime tab owner.
- `Tab` wraps exactly one existing terminal surface as `PaneId.first`.
- `Tab` exposes current methods needed by `events/event.zig` by delegating to its one pane.
- Update `tab_bar/tab_slots.zig` to store `Tab` instead of raw terminal surfaces.
- Update `events/event.zig` to operate on `RuntimeTab` while preserving all current behavior.
- Update `host_test_root.zig` to import `tab.zig`.
- Do not update `bucket2.zig` except compile-required import fallout; expected no change.

Exact symbols:

- `src/tab.zig`: `pub const Tab = struct { first_pane: TerminalSurface = undefined, ... };`
- `Tab.activePaneId(self: *const Tab) Layout.pane.PaneId`
- `Tab.pane(self: *Tab, id: Layout.pane.PaneId) *TerminalSurface`, asserting `id == .first`.
- `Tab` delegates current lifecycle/runtime/render/input/focus/font/title/paste/session methods to `first_pane` with the same signatures currently used by `events/event.zig`.
- `tab_bar/tab_slots.zig`: storage changes from raw terminal surface to `RuntimeTab`.
- `events/event.zig`: raw terminal type changes to `RuntimeTab` owner type; behavior stays unchanged.

Tests and gates:

- `src/tab.zig`: test `activePaneId()` returns `Layout.pane.PaneId.first`.
- `src/tab.zig`: test `pane(.first)` returns `&tab.first_pane`.
- Existing `tab_bar/tab_slots.zig` tests must pass with `RuntimeTab`.
- Add/import smoke in `host_test_root.zig` for `tab.zig`.
- Verify with `zig fmt build.zig src`, `zig build check`, `zig build test:unit`, `git diff --check`, and targeted stale-symbol searches.

Deferred:

- Runtime split behavior, second pane allocation, dynamic `PaneId` allocator, active pane focus movement, split commands/keybindings, hidden/floating pane behavior, pane transfer, tab transfer, resize/rebalance, z-index repair, serialization, C ABI changes, render ABI changes, and broad cleanup/rename of `bucket2.zig`.

## User Decision: Initial Runtime Split UX

- Copy Zellij's split UX while Howl learns.
- Start implementation in terms of richness, but keep the minimum action set that gets machinery planned and started correctly.
- First runtime split behavior should add both split directions, because vertical and horizontal splits should share all machinery except placement math.
- First split creation spawns a new terminal in the current tab using the default command/cwd.
- Defer cwd inheritance, custom commands, split sizing UI, moving panes, floating, hidden panes, transfer, and advanced focus behavior unless a narrow first slice requires an explicit placeholder.

## Stage 7 Zellij-Style Split Runtime Plan

Session: `teammate-2026-06-21-layout-mux-zellij-splits-plan-02`

Verdict: ready, accepted by orchestrator for Phase 1 first. The initial visible split support sequence must be phased so no user-visible split action lands before multi-pane presentation can render correctly.

Reference pressure:

- `utils/dev_references/terminals/zellij/zellij-utils/src/cli.rs` exposes `NewPane` with right/down direction, command, and cwd semantics.
- `utils/dev_references/terminals/zellij/zellij-server/src/route.rs` maps `Action::NewPane` to tiled placement and default terminal spawn.
- `utils/dev_references/terminals/zellij/zellij-utils/src/data.rs` separates tiled new-pane placement from floating/in-place/stacked placement.
- `utils/dev_references/terminals/zellij/zellij-client/src/input_handler.rs` treats `Action::NewPane` as a normal action beside tab and floating-pane actions.
- `utils/dev_references/terminals/tmux/cmd-split-window.c` proves split execution resolves session/window/current pane/layout cell and spawns a pane through runtime ownership.
- `utils/dev_references/terminals/tmux/window.c` proves pane collection ownership belongs to the window/tab runtime owner.
- `utils/dev_references/terminals/tmux/layout.c` proves layout leaf identity and pane runtime must reconcile before visible split behavior.
- `utils/dev_references/terminals/wezterm/docs/cli/cli/split-pane.md` proves split-pane splits the current pane, returns a new pane id, and spawns a default command when none is specified.
- `utils/dev_references/terminals/wezterm/docs/config/default-keys.md` gives default split key pressure for vertical/horizontal split actions.

Minimum user-visible actions for the later binding phase:

- `Input.Bindings.Action.terminal_split_right`
- `Input.Bindings.Action.terminal_split_down`
- terminal config binding fields: `split_right`, `split_down`
- default config entries under `term.bindings` after key-label spelling is confirmed.

Phases:

- Phase 1: pluralize host presentation frame while preserving current one-pane runtime behavior. No split action, no runtime pane allocation.
- Phase 2: convert `src/tab.zig` from one-pane delegation to bounded two-pane runtime ownership, still without user-visible binding dispatch.
- Phase 3: wire `terminal_split_right` and `terminal_split_down` through input config/default config and `events/event.zig` to tab split methods.
- Phase 4: grow beyond two panes and add focus movement, close, resize, movement/transfer, floating, and hidden behavior as separate contracts.

Stage 7 Phase 1 coder contract:

- Update `howl-linux-host/src/layout.zig`.
- Add `pub const FramePane = struct { id: pane.PaneId, term_texture_id: u32, term_texture_rect: Rect, scrollbar: scrollbar.Placement, scroll_chip: scroll_chip.Placement };`.
- Change `Frame` to replace `term_texture_id`, `term_texture_rect`, `scrollbar`, and `scroll_chip` with `panes: []const FramePane` plus `tab_bar_height_px: c_int`.
- Keep tab-bar metadata fields: `tab_count`, `active_tab`, `tab_bar_revision`, `tab_bar_font_size_px`, `tab_labels`, `damage`.
- Update `events/event.zig` to populate exactly one `FramePane` for current behavior and pass a slice into `Layout.Frame.panes`.
- Update `texture/frame.zig` to assert `frame.panes.len > 0`, use `frame.tab_bar_height_px` for tab-bar cache height, draw every pane texture, then draw every pane scrollbar/chip.
- Update `texture/tab_bar.zig` if it reads `frame.term_texture_rect.y`; use `frame.tab_bar_height_px` instead.
- No changes to `input/keys.zig`, `config/term.zig`, default config, or runtime split allocation in Phase 1.
- No C/render ABI changes.

Phase 1 tests and gates:

- `Layout.Frame` can carry one `FramePane` with explicit `tab_bar_height_px`.
- `texture/frame.zig` fake-C tests prove submitting a frame with two panes draws two terminal textures and scrollbar/chip for each pane.
- tab-bar cache height uses `Frame.tab_bar_height_px`, not first pane rect y.
- current one-pane render snapshot emits exactly one `FramePane`.
- no `terminal_split_right`, `terminal_split_down`, `split_right`, or `split_down` user-visible symbols appear in Phase 1.
- no C ABI files change.
- no manager/controller/engine/utils/types files are added.
- verify with `zig fmt build.zig src`, `zig build check`, `zig build test:unit`, `git diff --check`, and targeted stale-symbol searches.
