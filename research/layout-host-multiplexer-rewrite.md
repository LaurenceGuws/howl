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

## Stage 7 Phase 2 Two-Pane Runtime Contract

Session: `teammate-2026-06-21-layout-mux-two-pane-runtime-plan-01`

Verdict: ready, accepted by orchestrator with clarification: `Tab.splitRight` and `Tab.splitDown` are internal runtime methods only in Phase 2. No user-visible input actions, config fields, or default keybindings may be added until Phase 3.

Problem:

- Phase 1 made presentation able to draw multiple panes, but `src/tab.zig` still owns exactly one terminal surface.
- Phase 2 must move runtime tab ownership to a bounded two-pane model and add internal right/down split methods without exposing actions or bindings.

Reference pressure:

- `utils/dev_references/terminals/zellij/zellij-utils/src/cli.rs` proves new-pane actions create panes by right/down direction and carry command/cwd semantics.
- `utils/dev_references/terminals/zellij/zellij-server/src/route.rs` proves `Action::NewPane` maps to tiled placement and spawns a default terminal.
- `utils/dev_references/terminals/zellij/zellij-utils/src/data.rs` proves tiled new-pane placement is separate from floating/in-place/stacked.
- `utils/dev_references/terminals/tmux/cmd-split-window.c` proves split execution resolves current pane/layout and spawns pane runtime through owner state.
- `utils/dev_references/terminals/tmux/window.c` proves pane collection insertion belongs to the runtime window/tab owner.
- `utils/dev_references/terminals/wezterm/docs/cli/cli/split-pane.md` proves split-pane splits the current pane and spawns the default command, while cwd/size/move are separate options.

Coder contract:

- Update `howl-linux-host/src/tab.zig` from one terminal delegation to bounded two-pane runtime ownership.
- Update `howl-linux-host/src/events/event.zig` to consume tab-owned active placement and frame panes.
- Do not add files or delete files.
- Do not update `input/keys.zig`, `config/term.zig`, or `assets/default_config/init.lua`.
- Do not update C headers or render ABI files.

Required tab symbols and state:

- `pub const max_frame_panes = 2;`
- private `const second_pane: Layout.pane.PaneId = @enumFromInt(1);`
- replace `first_pane` with `panes: [max_frame_panes]TerminalSurface = undefined`.
- add `pane_count: u8 = 0`.
- add `active_pane: Layout.pane.PaneId = .first`.
- add `split_tree: Layout.splits.Tree = Layout.splits.leaf(.first)`.
- add stored focus booleans for applying focus to new panes.
- `activePaneId`, `pane`, `paneConst`, `paneIndex`, `activePane`, `activePaneConst`.
- `place(self: *const Tab, tab_body: Layout.tab.Body, out: []Layout.pane.Placement) []Layout.pane.Placement`.
- `activeTerminalPlacement(self: *const Tab, tab_body: Layout.tab.Body) Layout.pane.TerminalPlacement`.
- `framePanes(self: *const Tab, tab_body: Layout.tab.Body, out: []Layout.FramePane) []Layout.FramePane`.
- internal runtime split methods `splitRight`, `splitDown`, and shared `split` using default `TerminalConfig` init inputs and tab-body geometry.

Runtime behavior:

- `init` initializes only `panes[0]`, sets `pane_count = 1`, `active_pane = .first`, and `split_tree = Layout.splits.leaf(.first)`.
- Split from one pane computes a pair tree, places both panes, initializes the second pane using default config and second placement, resizes first pane, then commits `pane_count = 2`, `split_tree`, and `active_pane = second_pane`.
- Split at capacity returns `false` with no mutation.
- Text, pointer, scroll, paste, zoom, title, hover, and terminal mouse policy target active pane.
- Focus state is stored on `Tab`; active pane gets widget focus when tab is active, inactive panes get false.
- Runtime facts, wake acknowledgement, progress driving, render turn, present submission, and present completion iterate initialized panes and aggregate results conservatively.
- `framePanes` returns initialized panes as `Layout.FramePane` records using current split placement.
- Inactive pane close/cleanup behavior remains deferred.

Tests and gates:

- Initial tab state has one pane, active `.first`, and leaf split tree.
- `pane(.first)` returns `&panes[0]`.
- Right and down split state install pair tree, preserve first pane, create second pane, and make second active using pure/testable helpers where real PTY init would be too expensive.
- Capacity rejection does not corrupt pane count, active pane, or split tree.
- `framePanes` returns two ids/rects after split state is installed.
- `activeTerminalPlacement` returns second pane placement after split state is installed.
- `events/event.zig` one-pane present frame test uses `pane_count == 1` even though capacity is 2.
- `presentFrame` slices only `snapshot.pane_count`.
- No `Input.Bindings.Action` additions and no `terminal_split_right`, `terminal_split_down`, `split_right`, or `split_down` user-visible symbols outside internal `src/tab.zig` method names.
- No changes to `input/keys.zig`, `config/term.zig`, or `assets/default_config/init.lua`.
- No C/render ABI files changed.
- Verify with `zig fmt build.zig src`, `zig build check`, `zig build test:unit`, `git diff --check`, and targeted stale searches.

## Stage 7 Phase 3 Split Action Binding Contract

Session: `teammate-2026-06-21-layout-mux-split-bindings-plan-01`

Verdict: ready, accepted by orchestrator.

Problem:

- Phase 1 made presentation multi-pane capable and Phase 2 added bounded two-pane runtime ownership with internal split methods.
- Phase 3 exposes those methods through user-visible terminal binding actions and default config keys while keeping advanced pane behavior deferred.

Reference pressure:

- `utils/dev_references/terminals/zellij/zellij-utils/src/cli.rs` proves `NewPane` opens a new pane in right/down direction and command/cwd are separate semantics.
- `utils/dev_references/terminals/zellij/zellij-server/src/route.rs` proves new-pane action maps to tiled placement and default shell spawn.
- `utils/dev_references/terminals/zellij/zellij-utils/src/data.rs` proves tiled placement remains separate from floating/in-place/stacked.
- `utils/dev_references/terminals/zellij/default-plugins/status-bar/src/one_line_ui.rs` exposes Split Right and Split Down as new-pane actions.
- `utils/dev_references/terminals/wezterm/docs/cli/cli/split-pane.md` proves split-pane splits current pane and default-spawns when no command is specified.
- `utils/dev_references/terminals/wezterm/docs/config/default-keys.md` provides `CTRL+SHIFT+ALT` split key pressure.
- Current Howl `input/keys.zig` owns binding action tags and parser-supported key labels including `five` and `apostrophe`.
- Current Howl `config/term.zig` owns terminal binding specs; current default config keeps terminal bindings under `term.bindings`.

Coder contract:

- Update `howl-linux-host/src/input/keys.zig` with `terminal_split_right` and `terminal_split_down` actions.
- Update `howl-linux-host/src/config/term.zig` with binding fields `split_right` and `split_down`.
- Update `howl-linux-host/assets/default_config/init.lua` under `term.bindings`:
  - `split_right = { "ctrl+shift+alt+five" }`
  - `split_down = { "ctrl+shift+alt+apostrophe" }`
- Update `howl-linux-host/src/events/event.zig` to dispatch split actions to active tab using current tab body geometry.
- Do not update `src/tab.zig` unless a compile-only signature adjustment is strictly required.
- Add no files and delete no files.
- Do not update C headers or render ABI files.

Behavior:

- `.terminal_split_right` calls active tab `splitRight(self.input, self.event_loop, &self.conf.term, tab_body)`.
- `.terminal_split_down` calls active tab `splitDown(self.input, self.event_loop, &self.conf.term, tab_body)`.
- If split succeeds, request redraw, reconfigure input policies, and sync active window title.
- If capacity is full and split returns false, do not request redraw and do not mutate unrelated state.
- If terminal init/start returns an error, propagate it.
- New pane uses default `conf.term` command/cwd.

Tests and gates:

- `input/keys.zig` tests parse `ctrl+shift+alt+five` to `.terminal_split_right` and `ctrl+shift+alt+apostrophe` to `.terminal_split_down`.
- `config/term.zig` tests prove `split_right` and `split_down` fields produce the new actions.
- Add a pure event dispatch/helper test for action-to-direction mapping if practical; otherwise rely on compile coverage and tab Phase 2 tests.
- Gate: new action symbols appear only in expected files and default config.
- Gate: no capacity beyond two, cwd/custom command/floating/hidden/move/transfer/resize UI symbols, or C/render ABI changes.
- Verify with `zig fmt build.zig src`, `zig build check`, `zig build test:unit`, and `git diff --check`.

## Remaining Split Runtime Order

Current accepted state:

- One split per tab is supported.
- Both split directions work.
- The new pane becomes active.
- Two-pane focus movement is supported through layout-owned pane directions and bindings.
- There is no pane resize yet.
- There is no pane close yet.

Recommended remaining order:

1. Pane close for the current two-pane split.
   - Closing one pane restores the other pane to the full tab body.
   - Closing the last pane follows existing tab/session behavior only after explicitly planned.
2. Pane resize for the current two-pane split.
   - Add split ratio storage before UI actions mutate size.
   - Current `layout/splits.zig` halves placement only; resize requires layout shape growth.
3. More than two panes.
   - Add pane id allocation and recursive split tree ownership.
   - Split target becomes active pane path, not just the root two-pane split.
4. Cwd and command semantics.
   - Default command is already used.
   - Cwd inheritance/override and custom command remain deferred.
5. Pane movement and transfer.
   - Move panes within split structure first.
   - Cross-tab and cross-window transfer later.
6. Floating and hidden panes.
   - Add tiled vs floating ownership, z-index mutation, and hide/show retention as separate contracts.
7. Tab transfer across windows.
   - Requires mature window/tab runtime collections and is not near-term.

Next recommended slice:

- Stage 8 Phase 2: two-pane close only.
- It should add no resize math, no more-than-two-pane support, no render ABI work, and no transfer behavior.

## Stage 8 Phase 1 Two-Pane Focus Movement

Session: `ses_116502da4ffeGfmz3gkBalJn1T`

Verdict: implemented and committed in `howl-linux-host` as `a49966c Add two pane focus movement`.

Problem:

- Split-right and split-down created a second pane and made it active, but users could not return focus to the first pane.
- Focus movement belongs to the tab/layout multiplexer layer. Lower terminal instances only receive focused/unfocused state.
- Tab and pane keybindings are layout ownership, not terminal-local config and not tab-bar visual config.

Reference pressure:

- Zellij exposes directional pane focus separately from resize/move behavior.
- tmux `select-pane` changes active pane and then updates focus delivery separately.
- WezTerm `ActivatePaneDirection` activates an adjacent pane by direction.

Implemented behavior:

- `layout/pane.zig` adds `Direction = enum { left, right, up, down }`.
- `src/tab.zig` adds `Tab.focusPane(direction)`.
- Left/right focus works only for left-right splits.
- Up/down focus works only for top-bottom splits.
- Single-pane tabs no-op.
- Focus changes update `active_pane`, call existing pane focus sync, and return `true` only when focus changed.
- Event dispatch requests redraw, refreshes input policies, and syncs title only on actual focus change.
- `layout.bindings` owns split, pane focus, and tab navigation bindings.
- `term.bindings` remains terminal-local.
- `tab_bar` remains visual tab-bar config only.

Changed files:

- `assets/default_config/init.lua`
- `src/config.zig`
- `src/config/layout.zig`
- `src/config/tab_bar.zig`
- `src/config/term.zig`
- `src/events/event.zig`
- `src/input/keys.zig`
- `src/layout/pane.zig`
- `src/layout/tab_bar.zig`
- `src/layout/window.zig`
- `src/tab.zig`

Verified:

- `zig fmt build.zig src`
- `zig build check`
- `zig build test:unit`
- `git diff --check`

Non-goals preserved:

- No `bucket2.zig` cleanup.
- No terminal `Surface` move or rename.
- No C/render ABI change.
- No pane close, resize, more-than-two panes, cwd/custom command, movement/transfer, floating, or hidden pane behavior.

## Stage 8 Phase 2A Zellij Pane Info Model

Session: `ses_11638bd08ffeFeIg9JUtmmmhFi`

Verdict: implemented, orchestrator-reviewed, and verified. Pending commit because no explicit commit request has been made.

Problem:

- The active bucket-dissection work exposed that pane focus and pane visibility were conflated.
- Visible unfocused panes must still participate in runtime/progress redraw policy.
- Only the focused visible pane may receive input admission.
- Bucket runtime/progress must not receive mux `active`, focus, visibility, or selection policy.
- The first visibility attempt fixed behavior but did not copy Zellij's tab/pane info shape explicitly enough.

Reference pressure:

- `utils/dev_references/terminals/zellij/zellij-utils/src/input/actions.rs:158-170` exposes `FocusNextPane`, `FocusPreviousPane`, `MoveFocus`, and `MoveFocusOrTab` as pane focus actions separate from terminal input.
- `utils/dev_references/terminals/zellij/zellij-utils/src/data.rs:633-663` defines `Direction::{Left, Right, Up, Down}` and horizontal/vertical helpers.
- `utils/dev_references/terminals/zellij/default-plugins/status-bar/src/one_line_ui.rs:755-764` consumes `are_floating_panes_visible`, `selectable_floating_panes_count`, and `selectable_tiled_panes_count` rather than a single active flag.
- `utils/dev_references/terminals/zellij/zellij-utils/src/data.rs:2253-2306` defines the tab/pane info pressure through `PaneManifest`, `PaneInfo`, `PaneInfo.is_focused`, and the selectable pane count fields.

Implemented behavior:

- `layout/pane.zig` adds `Kind = enum { tiled, floating }` and `Visibility = enum { visible, hidden }`.
- `src/tab.zig` adds `TabSelection = enum { selected, unselected }`.
- `src/tab.zig` adds `TabInfo` with `are_floating_panes_visible`, `selectable_tiled_panes_count`, and `selectable_floating_panes_count`.
- `src/tab.zig` adds `PaneInfo` with `id`, `kind`, `visibility`, `is_focused`, and `is_selectable`.
- Selected tabs report initialized panes as tiled, visible, selectable, and exactly one focused pane.
- Unselected tabs report initialized panes as tiled, hidden, not selectable, and not focused for the current window presentation.
- Floating is vocabulary only: `are_floating_panes_visible = false` and `selectable_floating_panes_count = 0`.
- Runtime facts, runtime progress, and frame pane emission now consume tab-owned `PaneInfo` facts before calling the lower terminal bucket.
- Lower terminal runtime/progress no longer receives a mux `active` policy argument.
- Presentation bucket forwarding methods for active-pane texture and scrollbar/chip placement were removed in the same dirty slice, with `Tab.framePanes` composing per-pane frame facts directly from true owners.
- Touched scrollbar owner-call adapters no longer use `anytype`.

Tests/proof added:

- Pane kind vocabulary has distinct tiled and floating values.
- Focus movement does not change pane visibility.
- Selected split tabs expose both tiled panes as visible.
- `TabInfo` reports selected and unselected selectable counts.
- `PaneInfo` reports selected tiled panes, unselected hidden panes, and focus movement as a focused-flag-only change.
- Input admission reaches only the focused visible pane.
- A visible unfocused pane can still contribute progress redraw.

Verified:

- `zig fmt --check build.zig src`
- `zig build check`
- `zig build test:unit`
- `git diff --check`

Non-goals preserved:

- No floating placement, z-order, visibility toggle, focus behavior, or selectable-set implementation.
- No pane close, resize, more-than-two-pane support, cwd/custom command semantics, pane movement/transfer, or tab transfer.
- No C/render ABI change.
- No whole-bucket move or rename.
- No compatibility shims or aliases.

## Stage 8 Phase 2B Active Pane Input Forwarding Cut

Session: `orch-2026-06-21-layout-mux-01`

Verdict: implemented, verified, and ready to commit.

Problem:

- `bucket2.zig::Surface` still exposed `drainTextInputFastPath` and `drainPointerInput` as pure forwarding wrappers into `input/processor.zig`.
- Input admission and active-pane selection are tab/mux policy, not bucket ownership.
- The bucket should expose only the terminal-local adapter needed by the input processor until that adapter can move to a smaller terminal/input owner.

Implemented behavior:

- Deleted `Surface.drainTextInputFastPath`.
- Deleted `Surface.drainPointerInput`.
- Made `Surface.termInput` callable so the selected terminal can provide the existing `input_processor.TermInput` adapter.
- `Tab.drainTextInputFastPath` now creates the active pane's terminal input adapter and calls `input_processor.drainTextInputFastPath` directly.
- `Tab.drainPointerInput` now creates the active pane's terminal input adapter and calls `input_processor.drainPointerInput` directly.
- Runtime behavior is unchanged: only the active pane receives text/pointer input forwarding.

Verified:

- `zig fmt --check build.zig src`
- `zig build check`
- `zig build test:unit`
- `git diff --check`

Non-goals preserved:

- No pointer hit-testing changes.
- No scroll input rewrite.
- No paste/font/title rewrite.
- No C/render ABI change.
- No whole-bucket move or rename.

## Stage 8 Phase 2C Active Pane Scroll Input Cut

Session: `orch-2026-06-21-layout-mux-01`

Verdict: implemented, verified, and ready to commit.

Problem:

- `bucket2.zig::Surface.handleScrollInput` was another pure forwarding wrapper.
- Scroll page handling is owned by `scroll_bar.zig`; active-pane selection is tab policy.
- Keeping a bucket method for this hid the true owners and preserved bucket surface area without adding safety.

Implemented behavior:

- Deleted `Surface.handleScrollInput`.
- `Tab.handleScrollInput` now calls `terminal_scrollbar.handlePages` for the active pane's terminal and scrollbar state.
- Runtime behavior is unchanged: scroll-page input still targets the active pane.

Verified:

- `zig fmt --check build.zig src`
- `zig build check`
- `zig build test:unit`
- `git diff --check`

Non-goals preserved:

- No scrollbar behavior change.
- No pointer hit-testing change.
- No C/render ABI change.
- No whole-bucket move or rename.

## Stage 8 Phase 2D Active Pane Hover Policy Cut

Session: `orch-2026-06-21-layout-mux-01`

Verdict: implemented, verified, and ready to commit.

Problem:

- `bucket2.zig::Surface.wantsLinkHover` and `Surface.wantsTerminalHoverReporting` were active-pane policy wrappers.
- Link-hover policy is read from the active pane terminal config, while terminal mouse-motion reporting is a terminal-local VT input fact.
- The tab already owns active-pane selection, so keeping bucket wrappers widened the fake surface API.

Implemented behavior:

- Deleted `Surface.wantsLinkHover`.
- Deleted `Surface.wantsTerminalHoverReporting`.
- `Tab.wantsLinkHover` reads the active pane config directly.
- `Tab.wantsTerminalHoverReporting` checks active pane liveness and `term_input.wouldReportUnpressedMouseMotion` directly.
- Runtime behavior is unchanged: input policy configuration still follows the active pane.

Verified:

- `zig fmt --check build.zig src`
- `zig build check`
- `zig build test:unit`
- `git diff --check`

Non-goals preserved:

- No link processing behavior change.
- No mouse reporting protocol change.
- No pointer hit-testing change.
- No C/render ABI change.
- No whole-bucket move or rename.

## Stage 8 Phase 2E Active Pane Paste Cut

Session: `orch-2026-06-21-layout-mux-01`

Verdict: implemented, verified, and ready to commit.

Problem:

- `bucket2.zig::Surface.paste` was another active-pane forwarding face used only through `Tab.paste`.
- The actual behavior is terminal-local VT paste publication plus cursor activity reset.
- `Tab` owns active-pane selection and can apply the existing terminal-local operation directly to the selected pane.

Implemented behavior:

- Deleted `Surface.paste`.
- `Tab.paste` now calls `term_input.publishPaste` on the active pane terminal and resets active pane cursor blink activity.
- Runtime behavior is unchanged: paste still targets the active pane.

Verified:

- `zig fmt --check build.zig src`
- `zig build check`
- `zig build test:unit`
- `git diff --check`

Non-goals preserved:

- No paste protocol behavior change.
- No input binding behavior change.
- No C/render ABI change.
- No whole-bucket move or rename.
