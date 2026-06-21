# Zellij Pane Policy Scratchpad

Owner: main agent scratchpad for Zellij-derived pane/mux policy work.

Status:

- Working scratchpad, not an accepted sprint contract by itself.
- User decision authority: copy Zellij unless the user explicitly decides otherwise.
- Main agent owns orchestration and review with the user.
- Teammate session for research/coding: `ses_11638bd08ffeFeIg9JUtmmmhFi`.

## Current Worktree Context

The host worktree currently contains uncommitted code from three related cuts:

1. Presentation/layout bucket face cut.
2. Explicit scrollbar owner-call cut replacing touched `anytype` adapters.
3. Zellij pane visibility policy attempt.

Review status:

- The first two cuts are directionally accepted after main-agent fixes.
- The third cut is not accepted as final because it used Zellij as pressure but did not copy the Zellij shape explicitly enough.
- Before commit, rework the third cut toward Zellij-like tab/pane info vocabulary.

## User Decisions

- Zellij is the primary reference for pane/tab policy here.
- tmux and WezTerm are pressure/support only where Zellij is immature or unclear.
- Copy Zellij unless the user decides otherwise.
- Floating can exist as vocabulary/state now, but floating behavior implementation is deferred.
- The lower terminal instance must not know multiplexing.
- Focus is not visibility.
- Visible unfocused panes must still participate in runtime/render redraw policy.
- Only focused visible pane receives input admission.
- Do not make the bucket prettier.
- Delete mux scope out of the bucket when ownership moves.
- No compatibility shims, aliases, or old-interface preservation.
- Touched symbols must not introduce or leave old `anytype`; removing touched `anytype` is required, not avoidable.

## Zellij Source Pressure To Engrave

Directional focus movement:

- `utils/dev_references/terminals/zellij/zellij-utils/src/input/actions.rs:158-170`
- Facts:
  - `FocusNextPane`
  - `FocusPreviousPane`
  - `MoveFocus { direction: Direction }`
  - `MoveFocusOrTab { direction: Direction }`

Direction vocabulary:

- `utils/dev_references/terminals/zellij/zellij-utils/src/data.rs:633-663`
- Facts:
  - `Direction::{Left, Right, Up, Down}`
  - `is_horizontal()`
  - `is_vertical()`

Visible/selectable pane sets for focus/resize UI:

- `utils/dev_references/terminals/zellij/default-plugins/status-bar/src/one_line_ui.rs:755-764`
- Facts:
  - `are_floating_panes_visible`
  - `selectable_floating_panes_count`
  - `selectable_tiled_panes_count`
  - focus/resize shortcuts key off the visible/selectable pane set, not merely focused/unfocused.

Pane/tab info model:

- `utils/dev_references/terminals/zellij/zellij-utils/src/data.rs:2253-2306`
- Facts:
  - `are_floating_panes_visible`
  - `selectable_tiled_panes_count`
  - `selectable_floating_panes_count`
  - `PaneManifest`
  - `PaneInfo`
  - `PaneInfo.is_focused`

## Howl Target Vocabulary

`layout/pane.zig` should own pure pane structural vocabulary:

- `PaneId`
- `Direction`
- `Visibility = enum { visible, hidden }`
- `Kind = enum { tiled, floating }`

`src/tab.zig` should own runtime tab/pane mux facts derived from current tab state:

- `TabInfo`
  - `are_floating_panes_visible: bool`
  - `selectable_tiled_panes_count: usize`
  - `selectable_floating_panes_count: usize`
- `PaneInfo`
  - `id: PaneId`
  - `kind: Layout.pane.Kind`
  - `visibility: Layout.pane.Visibility`
  - `is_focused: bool`
  - `is_selectable: bool`
- `paneInfo(out: []PaneInfo) []PaneInfo`
- `tabInfo() TabInfo`

Initial current-state values:

- Initialized panes are tiled.
- Selected tab tiled panes are visible.
- Unselected tab panes are hidden for the current window presentation.
- `are_floating_panes_visible = false`.
- `selectable_floating_panes_count = 0`.
- `selectable_tiled_panes_count = initialized tiled pane count for the selected tab`.

Floating deferred behavior:

- `Kind.floating` may exist as vocabulary.
- No floating placement.
- No floating z-order mutation.
- No floating visibility toggle.
- No floating focus/selectable set behavior.
- Any code path encountering floating in current runtime should assert/unreachable or report zero, depending on whether it is data construction or query.

## Caller Policy Target

Runtime/progress callers should use `PaneInfo` and `TabInfo`, not ad hoc active/focus booleans.

Rules:

- `Tab` decides pane visibility.
- `Tab` decides pane focus.
- `Tab` decides input admission.
- Bucket runtime/progress is called only for panes that participate.
- Input admission is already filtered before calling bucket runtime/progress.
- Bucket runtime/progress must not receive mux `active`/visibility/focus policy parameters.
- Lower terminal focus remains delivered through existing focus setters.

Current selected tab, two tiled panes:

- both panes are visible
- both panes are selectable tiled panes
- one pane is focused
- only focused pane receives input admission
- visible unfocused pane can still produce redraw from runtime progress

Unselected tab:

- panes are hidden for current window presentation
- no input admission
- no visible-pane runtime/progress participation for current window redraw policy

## Current Implementation Defect To Correct

The current uncommitted visibility attempt added:

- `TabSelection`
- local `PaneFocus`
- local `InputAdmission`
- `paneVisibility(...)`

This fixed part of the behavior but did not copy Zellij's tab/pane info shape explicitly enough.

Required rework:

- Replace or subsume ad hoc local policy helpers with `TabInfo`/`PaneInfo`-driven policy.
- Keep the bucket active-parameter removal if it remains correct.
- Keep explicit scrollbar owner calls and deleted presentation bucket methods if review still passes.
- Record Zellij source pressure in accepted research before committing.

## Proposed Next Teammate Seed

Use teammate session `ses_11638bd08ffeFeIg9JUtmmmhFi`.

Ask for implementation rework, not broad new research:

1. Preserve accepted bucket-face and explicit-scrollbar cuts.
2. Rework the pane visibility policy attempt to copy Zellij's info model:
   - add `layout.pane.Kind`
   - keep/add `layout.pane.Visibility`
   - add `TabInfo` and `PaneInfo` in `src/tab.zig`
   - add tab-owned info builders
   - route runtime facts, progress drive, frame panes, and focus tests through those info facts
3. Keep current two-pane tiled behavior only.
4. Floating state may exist only as deferred vocabulary with explicit tests/proof that current runtime reports zero floating panes.
5. Do not add close/resize/more panes/transfer/floating behavior.
6. Do not touch C/render ABI.
7. Do not add compatibility shims.
8. Do not leave touched `anytype`.

## Review Checklist

Before accepting code:

- Zellij citations are added to `research/layout-host-multiplexer-rewrite.md`.
- Loop receipt records teammate session and accepted facts.
- `layout.pane.Kind` and `layout.pane.Visibility` are explicit.
- `TabInfo` includes Zellij-count fields with correct current values.
- `PaneInfo` includes id, kind, visibility, focused, selectable.
- Runtime/progress logic reads from pane info, not ad hoc focus booleans.
- Bucket runtime/progress has no mux `active` policy argument.
- Visible unfocused pane redraw test exists.
- Focus movement does not change pane info visibility/kind/selectability.
- Floating is vocabulary only and deferred explicitly.
- No touched `anytype` remains except pre-existing untouched test fake if still outside touched symbols.
- `zig fmt build.zig src` passes.
- `zig build check` passes.
- `zig build test:unit` passes.
- `git diff --check` passes.
