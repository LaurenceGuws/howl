# Howl-Term Semantic Contract

Purpose: lock Milestone 2 for `howl-term` as one terminal product with two public surfaces.

Proof layer: contract

Last updated: 2026-05-12

## Canonical Contract

`howl-term` exposes one semantic contract.
It has two public surfaces:
- a Zig-native owner value surface
- a C ABI handle surface

The semantics are the same across both surfaces:
- one terminal instance owns terminal state, session linkage, snapshot state, and frame preparation state
- the embedder owns outer control flow and decides when to call lifecycle, transport, apply, snapshot, and frame operations
- callbacks and drain operations are explicit host-consumed outputs
- the current terminal state path remains the implementation behind the contract; it is not a second product

Canonical Zig root names:
- `HowlTerm`
- `C`
- `lifecycle`
- `frame`
- `input`
- `callback`
- `surface`
- `viewport`
- `event`

Negative space at the root:
- no root-level `Ffi` alias
- no root-level `runtime` compatibility namespace
- no root-level `Input` type catalog alias

## Surface Map

| Contract Area | Zig Surface | C Surface | Semantic Rule |
|---|---|---|---|
| lifecycle | `HowlTerm.initPty`, `start`, `stop`, `deinit` | `howl_term_init`, `howl_term_start`, `howl_term_stop`, `howl_term_deinit` | construct a stopped terminal, start it explicitly, stop it explicitly, then release it |
| convenience lifecycle alias | none required for canonical proof | `howl_term_create`, `howl_term_create_with_start_path`, `howl_term_destroy` | thin entry aliases only; they must not add scheduler, geometry-sync, or other separate execution semantics |
| transport wait | `waitTransport` | `howl_term_wait_transport` | host may block for transport readiness, but blocking does not advance terminal state |
| transport progress | `pumpTransport` | `howl_term_pump_transport` | host advances one bounded transport pass with explicit read and byte limits |
| VT/apply progress | `applyPending` | `howl_term_apply_pending` | host advances one bounded apply pass with an explicit event limit |
| snapshot publication | `publishSnapshot` | `howl_term_publish_snapshot` | host publishes renderable state explicitly; wake is observation of this publication, not scheduler ownership |
| input bytes | `publishInputBytes` | `howl_term_publish_input_bytes` | host submits raw bytes for session output |
| key input | `publishInputKey` | `howl_term_publish_input_key` | host submits one key plus modifiers |
| focus | `setInputFocus` | `howl_term_set_input_focus` | host publishes focus transitions explicitly |
| paste | `publishPaste` | `howl_term_publish_paste` | host submits paste text explicitly |
| mouse | `publishMouseEvent` | `howl_term_publish_mouse_event` | host submits one mouse event with explicit kind, button, position, modifiers, and buttons-down state |
| control signal | `publishControlSignal` | `howl_term_publish_control_signal` | host submits one explicit control signal from a fixed ABI table |
| wake callback | `setRenderWakeNotify` | `howl_term_set_render_wake_notify` | host registers or clears one render-wake callback and owns callback lifetime |
| snapshot wake wait | `awaitRenderWake`, `awaitRenderWakeTimeout`, `awaitSnapshotEvent` | `howl_term_await_render_wake`, `howl_term_await_snapshot_event` | host may block for explicit wake or snapshot events |
| frame geometry | `syncFrameGeometry` | `howl_term_sync_frame_geometry` | host publishes render and grid geometry explicitly |
| frame work poll | `hasQueuedRenderWork`, `needsPrepare`, `needsFrame` | `howl_term_has_queued_render_work`, `howl_term_needs_prepare`, `howl_term_needs_frame` | host learns whether renderable work exists without hidden pacing policy |
| frame prepare | `prepareNextFrame` | `howl_term_prepare_next_frame` | host asks for one explicit prepare step |
| frame submit | `renderReadyFrame` | `howl_term_render_ready_frame` | host consumes one explicit ready-to-render step |
| compatibility render pass | `renderFrame`, `renderLatestSnapshot`, `renderFrameSized` | `howl_term_render_frame`, `howl_term_render_latest_snapshot`, `howl_term_render_frame_sized` | explicit compatibility paths over the same state |
| readouts and drains | `surfaceState`, `scrollState`, `copyCurrentTitle`, `drainPendingClipboardSet`, query methods | matching `howl_term_*` readout and drain functions | host pulls explicit state from the terminal; no hidden side channel |

## Lifecycle Contract

Zig owner-value path:
1. host allocates owner storage by constructing `HowlTerm` with `initPty`
2. host starts the session-backed terminal with `start`
3. host drives runtime work explicitly with `waitTransport`, `pumpTransport`, `applyPending`, `publishSnapshot`, frame operations, and readout operations while started
4. host may call `stop` explicitly
5. host releases all terminal-owned resources with `deinit`

C handle path:
1. library allocates one opaque handle in `howl_term_init`
2. host starts that handle with `howl_term_start`
3. host drives runtime work explicitly with `howl_term_wait_transport`, `howl_term_pump_transport`, `howl_term_apply_pending`, `howl_term_publish_snapshot`, frame operations, and readout operations while started
4. host may call `howl_term_stop` explicitly
5. host releases the opaque handle and all terminal-owned resources with `howl_term_deinit`

Ownership rules:
- Zig caller owns the allocator passed to `initPty` and must keep it valid until `deinit`
- Zig caller owns the `HowlTerm` storage and must not copy the owner value after start
- C caller does not allocate terminal storage directly; the library allocates it during `howl_term_init`
- C caller owns the opaque handle lifetime and must call `howl_term_deinit` exactly once for each successful `howl_term_init`
- callback function pointers and callback contexts are borrowed from the host; they must stay valid until cleared or until terminal deinit

Negative space:
- `howl-term` does not own the host event loop
- `howl-term` does not start itself implicitly on the canonical lifecycle path
- `howl-term` does not require a hidden library-owned runtime thread for correctness on the canonical path
- no caller should rely on deinit to explain when start happened; start is an explicit step in the canonical contract

## Input, Output, And Event Contract

Host-to-terminal inputs:
- bytes
- key plus modifiers
- focus changes
- paste text
- mouse events
- control signals
- frame geometry

Terminal-to-host outputs:
- render wake callback registration point
- snapshot event waits
- render wake waits
- copied title bytes
- drained clipboard-set request bytes
- copied hyperlink URI bytes
- read-only state queries such as surface state, scroll state, liveness, snapshot sequence, and render metrics

Drain and callback rules:
- `setRenderWakeNotify` installs at most one callback for one terminal instance
- passing a null callback clears the callback and clears the callback context
- a non-null callback requires a non-null callback context on the C surface
- `drainPendingClipboardSet` transfers bytes by copy into caller-owned memory; the terminal retains no borrow of the caller buffer
- `copyCurrentTitle` and `copyHyperlinkUriAtPixel` copy into caller-owned memory; the caller decides buffer size

Named negative event space:
- no hidden host callback exists for title, clipboard, or viewport events
- those outputs are observable only through the explicit readout and drain operations above
- if a host needs a behavior not listed here, that capability is not part of the current Milestone 2 public contract

## Snapshot And Frame Contract

Render-facing semantics:
- `waitTransport` is an observation surface only; it does not advance session, VT, snapshot, or frame state
- `pumpTransport` performs one explicit bounded transport pass with caller-supplied limits
- `applyPending` performs one explicit bounded VT apply pass with a caller-supplied event limit
- `publishSnapshot` performs one explicit publication step from terminal state into render-queue work
- `syncFrameGeometry` publishes the host's current render and grid geometry
- `needsPrepare` means one prepare step is admissible now
- `prepareNextFrame` performs one explicit prepare step and returns a bounded status
- `needsFrame` means a prepared or retained frame is ready for one explicit render-ready step
- `renderReadyFrame` performs one explicit ready-frame step and returns a bounded status
- `awaitRenderWake` and `awaitSnapshotEvent` are observations; they do not publish work or grant `howl-term` ownership of the host scheduler

Bounded status surfaces:
- Zig `PublishResult`: `idle`, `published`, `queued`, `blocked`
- Zig `PrepareStatus`: `idle`, `prepared`, `failed`
- Zig `RenderStatus`: `idle`, `rendered`, `rendered_more_pending`, `needs_prepare`, `stale`, `failed`
- C `HowlTermPublishStatus`: `0 idle`, `1 published`, `2 queued`, `3 blocked`
- C `HowlTermPrepareStatus`: `0 idle`, `1 prepared`, `2 failed`
- C `HowlTermRenderStatus`: `0 idle`, `1 rendered`, `2 rendered_more_pending`, `3 needs_prepare`, `4 stale`, `5 failed`

Compatibility render paths:
- `renderFrame` is the same-geometry compatibility path
- `renderLatestSnapshot` and `renderFrameSized` are explicit compatibility paths for callers not using the prepare and ready split directly
- these compatibility paths do not change the canonical meaning of prepare and ready-frame work

## Canonical Examples

Zig example file:
- `howl-term/examples/zig-contract/main.zig`

C example file:
- `howl-term/examples/c-contract/main.c`

Public C header:
- `howl-term/include/howl_term.h`

Both examples exercise the same flow:
- init
- start
- sync frame geometry
- publish initial snapshot
- publish input bytes
- wait transport
- pump bounded transport
- apply bounded VT work
- publish snapshot explicitly
- prepare one frame
- render one ready frame
- stop
- deinit

## Parity Proof Targets

Contract proof targets in repo:
- this document
- `design/howl-term-embedding-sprint.md`
- `design/howl-term-contract-boundaries.md`
- `howl-term/src/test/root.zig`

What parity proof must cover:
- lifecycle sequencing exists on both surfaces
- host-driven bounded progress exists on both surfaces
- callback ownership rules are explicit on both surfaces
- prepare and render-ready statuses are explicit on both surfaces
- C ABI structs and result-code values that the contract names are asserted directly
- examples and tests exercise the same contract shape instead of two unrelated flows
