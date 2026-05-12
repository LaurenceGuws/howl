# Howl-Term Render Owner Table

Purpose: turn Milestone 1.1 of the render reset sprint into one authoritative owner table for
`HowlTerm`, so implementation work can be handed off without reopening architecture questions.

Proof layer: contract

Last updated: 2026-05-12

## Canonical Rule

`HowlTerm` is the terminal owner.
It may join session, VT, and render contracts.
It must not own renderer runtime policy.

Final owner classes in this doc:
- terminal-owned: state that defines terminal semantics.
- render-owned: state that belongs to render runtime ownership and must move to `howl-render-core`.
- host-owned: state that belongs to outer event loops, redraw pacing, platform wake policy, or UI.

Disposition terms in this doc:
- keep: remains in `HowlTerm`.
- move: leaves `HowlTerm` for a render-core owner.
- delete: removed outright with no replacement field.
- split: one part stays terminal-owned, one part moves.

## Boundary Rules

- If a field exists only because `howl-term/src/render/` existed, it should not survive the reset.
- If a field stores renderer runtime state, it must move instead of being mirrored.
- If a field stores terminal semantics but is currently expressed through render storage, keep the
  semantic state and replace the storage model.
- Host concerns stay out of `HowlTerm` even if the current Linux host happens to be the only caller.

## Field Table

### Session And VT Core

| Field | Current Meaning | Final Owner | Disposition | Why |
|---|---|---|---|---|
| `session` | PTY/session owner handle | terminal-owned | keep | `HowlTerm` joins host input and terminal output to the session contract. |
| `vt` | VT parser and grid state | terminal-owned | keep | Terminal semantics are meaningless without VT state. |
| `allocator` | owner allocator | terminal-owned | keep | Lifecycle ownership remains in `HowlTerm`. |
| `runtime_mutex` | protects terminal state path | split | split | Terminal-side locking stays only if the new owner chain still needs shared access to terminal semantics. Render runtime locking must move with render ownership. |

### Terminal Geometry And View State

| Field | Current Meaning | Final Owner | Disposition | Why |
|---|---|---|---|---|
| `cols` | current terminal columns | terminal-owned | keep | Terminal and VT resize semantics depend on this directly. |
| `rows` | current terminal rows | terminal-owned | keep | Same as `cols`. |
| `requested_cols` | render-derived target cols | split | split | Terminal should keep only committed terminal geometry. Render-derived requested geometry belongs to render runtime or an explicit geometry contract. |
| `requested_rows` | render-derived target rows | split | split | Same as `requested_cols`. |
| `scrollback_offset` | active viewport offset into history | terminal-owned | keep | This is terminal semantics. |
| `last_history_count` | last observed history count | terminal-owned | keep | Scrollback repair and selection shift are terminal semantics. |
| `scrollback_view_invalidated` | terminal viewport must be recomputed | terminal-owned | keep | View invalidation is terminal-owned. |
| `last_alt_screen` | remembered alt-screen state | terminal-owned | keep | Terminal-facing viewport and UX semantics depend on it. |

### Selection, Focus, Title, And Interactive Terminal State

| Field | Current Meaning | Final Owner | Disposition | Why |
|---|---|---|---|---|
| `has_input_focus` | terminal focus state | terminal-owned | keep | Input semantics belong to the terminal. |
| `selection` | selection anchor and progress state | terminal-owned | keep | Selection is terminal semantics. |
| `hover_link_id` | current hovered link id | terminal-owned | keep | Hyperlink hit-testing policy belongs to the terminal. |
| `hover_underline_style` | hover underline policy | terminal-owned | keep | Same as `hover_link_id`. |
| `current_title` | current terminal title bytes | terminal-owned | keep | Host consumes it, but terminal owns the semantic source. |
| `output_seen` | proof that output arrived | terminal-owned | keep | This is terminal/session semantic state, not render runtime state. |

### Snapshot, Dirty, And Epoch State

| Field | Current Meaning | Final Owner | Disposition | Why |
|---|---|---|---|---|
| `snapshot` | terminal-facing frame snapshot storage | split | split | The terminal must keep semantic visibility state, but it should not keep renderer-runtime snapshot storage in the current form. The meaning survives; the storage model changes. |
| `render_snapshot` | copied snapshot for prepare work | render-owned | move | This exists only because `howl-term` currently owns prepare/runtime behavior. |
| `snapshot_seq` | published snapshot sequence | split | split | Terminal-owned if it remains the semantic publication epoch. Render-owned if it exists only for render queue progression. One sequence model must remain, not two mirrored meanings. |
| `rendered_snapshot_seq` | last rendered snapshot sequence | render-owned | move | This belongs to submit/present ownership. |
| `vt_epoch` | VT changed since last sync | terminal-owned | keep | This is terminal semantic dirtiness. |
| `synced_epoch` | VT state reflected into snapshot model | split | split | The terminal keeps semantic sync progress; render-runtime local sync bookkeeping must move. |
| `dirty_epoch` | terminal-visible dirtiness epoch | terminal-owned | keep | Dirty semantic state belongs to the terminal. |
| `rendered_epoch` | dirtiness accepted by a rendered frame | render-owned | move | This belongs to render submission lifecycle. |
| `geometry_epoch` | geometry generation counter | split | split | One semantic geometry epoch may remain terminal-owned, but render-surface epoch validation belongs to render runtime. |

### Snapshot Wait And Wake State

| Field | Current Meaning | Final Owner | Disposition | Why |
|---|---|---|---|---|
| `snapshot_signal_seq` | wake sequence for snapshot waiters | terminal-owned | keep | Snapshot publication observation is part of terminal contract. |
| `snapshot_signal_stop` | stop flag for snapshot waiters | terminal-owned | keep | Lifecycle stop for terminal observers belongs here. |
| `snapshot_signal_mutex` | waiter mutex | terminal-owned | keep | Same as snapshot waiter ownership. |
| `snapshot_signal_cond` | waiter condition variable | terminal-owned | keep | Same as snapshot waiter ownership. |
| `render_wake_notify` | host callback for render wake | split | split | The callback registration point is public contract, so the registration surface stays in `howl-term`. The logic deciding when render wake is needed must move with render runtime. |
| `render_wake_notify_ctx` | callback context | split | split | Same as `render_wake_notify`. |
| `render_wake_latched` | dedupe bit for render wake policy | render-owned | move | This is render-runtime wake bookkeeping, not terminal semantics. |

### Renderer Runtime Fields That Must Leave

| Field | Current Meaning | Final Owner | Disposition | Why |
|---|---|---|---|---|
| `renderer` | selected backend runtime owner | render-owned | move | This is the center of the ownership inversion. |
| `render_queue` | retained-frame queue and prepared-slot owner | render-owned | move | Queue policy belongs with render runtime ownership. |
| `last_submitted_frame` | last accepted submitted frame | render-owned | move | Submit/present lifecycle is render runtime state. |
| `last_prepare_metrics` | last prepare metrics snapshot | render-owned | move | Render runtime should own what it measures. |
| `last_render_metrics` | last render metrics snapshot | render-owned | move | Same as `last_prepare_metrics`. |

### Surface, Cell, And Font Geometry Fields

| Field | Current Meaning | Final Owner | Disposition | Why |
|---|---|---|---|---|
| `render_width_px` | current render surface width | split | split | Host publishes geometry; render runtime owns surface implications. Terminal should not store render-surface state beyond what terminal semantics truly require. |
| `render_height_px` | current render surface height | split | split | Same as `render_width_px`. |
| `grid_width_px` | current grid width in pixels | split | split | Geometry contract survives; owner of layout consequences changes. |
| `grid_height_px` | current grid height in pixels | split | split | Same as `grid_width_px`. |
| `cell_px` | active cell pixel size | split | split | Terminal may observe cell size for hit-testing and viewport semantics, but render-derived layout ownership must not remain terminal-owned. |
| `font_size_px` | configured font pixel size | split | split | The semantic config input stays terminal-owned; renderer runtime should own the applied backend runtime state. |
| `last_cols` | last render-derived committed cols | render-owned | move | This is current geometry-sync bookkeeping for the render-driven world. |
| `last_rows` | last render-derived committed rows | render-owned | move | Same as `last_cols`. |
| `primary_font_path` | configured primary font path | terminal-owned | keep | This is configuration state the terminal exposes to the render contract. |
| `fallback_font_paths` | configured fallback fonts | terminal-owned | keep | Same as `primary_font_path`. |

### Miscellaneous Runtime Fields

| Field | Current Meaning | Final Owner | Disposition | Why |
|---|---|---|---|---|
| `io_ctx` | threaded I/O helper context | delete | delete | This is not part of the desired owner model for the render reset sprint. If truly needed later, it must return with a clear owner. |
| `io` | `io_ctx` view | delete | delete | Same as `io_ctx`. |
| `lifecycle_state` | high-level terminal lifecycle status | terminal-owned | keep | Public lifecycle readouts remain terminal-owned. |
| `last_sync_metrics` | VT-to-visible-state sync metrics | terminal-owned | keep | This is terminal-side projection work, not render submit work. |

## Summary By Class

Terminal-owned and expected to remain:
- `session`
- `vt`
- `allocator`
- `cols`
- `rows`
- `scrollback_offset`
- `last_history_count`
- `scrollback_view_invalidated`
- `has_input_focus`
- `selection`
- `hover_link_id`
- `hover_underline_style`
- `last_alt_screen`
- `current_title`
- `output_seen`
- `vt_epoch`
- `dirty_epoch`
- `snapshot_signal_seq`
- `snapshot_signal_stop`
- `snapshot_signal_mutex`
- `snapshot_signal_cond`
- `primary_font_path`
- `fallback_font_paths`
- `lifecycle_state`
- `last_sync_metrics`

Render-owned and expected to leave:
- `render_snapshot`
- `rendered_snapshot_seq`
- `rendered_epoch`
- `render_wake_latched`
- `renderer`
- `render_queue`
- `last_submitted_frame`
- `last_prepare_metrics`
- `last_render_metrics`
- `last_cols`
- `last_rows`

Delete rather than migrate:
- `io_ctx`
- `io`

Split and redesign rather than copy directly:
- `runtime_mutex`
- `requested_cols`
- `requested_rows`
- `snapshot`
- `snapshot_seq`
- `synced_epoch`
- `geometry_epoch`
- `render_wake_notify`
- `render_wake_notify_ctx`
- `render_width_px`
- `render_height_px`
- `grid_width_px`
- `grid_height_px`
- `cell_px`
- `font_size_px`

## Immediate Deletion Targets

The first code handoff should be allowed to delete references anchored on these fields without
preserving the old owner chain:
- `renderer`
- `render_queue`
- `render_snapshot`
- `last_submitted_frame`
- `last_prepare_metrics`
- `last_render_metrics`
- `render_wake_latched`

## Review Rule

No implementation is acceptable if it:
- keeps render-owned fields in `HowlTerm` under slightly different names.
- mirrors moved render state back into `HowlTerm` "for convenience".
- replaces one stale snapshot copy model with two new snapshot copy models.
- preserves deleted fields behind `legacy`, `compat`, or `deprecated` structures.
