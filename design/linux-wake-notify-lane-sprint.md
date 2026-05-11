## Linux Wake Notify Lane Sprint (Design Checkpoint)

### Scope

- Linux host plus `howl-term` only.
- Android is explicitly deferred; this checkpoint defines a minimal shared ABI lane first.

### Goal

Fix no-frame-thread freeze after input quiet by making wake-to-UI bridging event-driven and explicit:

- producer thread (`howl-term-io`) emits wake intent when render work becomes available,
- host thread (`howl-main`) blocks in native SDL wait,
- host wakes only on real events (input/window/term wake),
- no polling scan loop to discover work.

### C ABI Callback Shape

One registration surface with explicit null unregister semantics:

- callback type: `fn (?*anyopaque) callconv(.c) void`
- context: opaque pointer passed through unchanged
- register API:
  - `howl_term_set_render_wake_notify(handle, callback, context)`
  - `callback == null` means unregister and clear context

Constraints:

- callback must be non-blocking,
- callback may be called from runtime producer thread,
- callback must not call back into `howl-term` synchronously.

### Wake Emission Points

Emit notify only on producer-side transition to pending render work:

1. PTY bytes applied path in `runtime/io_tick.zig` after VT apply and wake state update.
2. Any producer-side path that causes pending render work from quiet state must route through the same latch transition function.

Do not emit from host prepare/render APIs. Host APIs consume work; they do not produce runtime wake intent.

### Edge/Level Semantics

Use edge-triggered notify with a runtime latch:

- level predicate: `pending = hasPendingRenderWork(term)`
- edge emit condition: `pending` transitions `false -> true` while latch is disarmed
- on emit: arm latch and invoke callback once
- while armed and pending true: suppress duplicate callback calls
- re-arm point: after render catch-up when pending becomes false, disarm latch

This guarantees bounded notify rate under sustained producer activity.

### Host Coalescing Semantics

Host callback path is intentionally tiny:

1. atomically set `wake_pending` from false to true,
2. only the successful transition pushes one SDL user wake event,
3. duplicate callback invocations while pending true are dropped.

Main loop semantics:

- if local frame work is pending, use non-blocking SDL poll turn,
- if local frame work is not pending, block in `SDL_WaitEvent`,
- on any event turn, clear `wake_pending` and run one bounded frame work turn,
- no zero-time `awaitRenderWakeTimeout(..., 0)` polling fallback.

### Final Implemented Producer Contract

- Producer-side pending edge (`false -> true`) now does three explicit actions in order:
  1. publish latest snapshot request into the render queue,
  2. advance snapshot event sequence,
  3. invoke host wake callback through the edge latch.
- Geometry sync path publishes initial full-dirty snapshot work for first frame bootstrap.
- Locking rule: when runtime mutex is already held, publish uses a lock-held token path to avoid recursive mutex acquisition.

### Invariants and Assertions

Runtime invariants:

- register/unregister requires valid handle,
- if callback is null then context must be null after registration call,
- callback invocation only when callback pointer is non-null,
- latch state transitions are explicit and monotonic per edge cycle,
- impossible transition (`latch armed` with `pending false` after rearm path) asserts.

Host invariants:

- callback must never block,
- callback must not allocate,
- callback must push at most one outstanding SDL wake event per coalesced window.

Bounded work invariants:

- main loop handles one render turn per wake/event pass,
- no unbounded mailbox/drain loop added in host path.

### Why This Matches Alacritty + TigerStyle

Alacritty direction:

- PTY/event producer emits wake event to UI loop when new render-relevant content exists,
- UI loop remains native event-driven and redraw-triggered, not timer-polled.

TigerStyle fit:

- explicit control flow: one registration point, one transition function, one host callback path,
- bounded work: edge latch plus host coalescing prevents wake storms,
- assert-heavy invariants on registration, transitions, and lifecycle assumptions,
- no fake progress: no placeholder API, no polling loop pretending to be event-driven.

### Android Deferral Rationale

- API is minimized now to validate correctness under Linux first.
- Android parity is outcome-level validation later, using this already-proven lane.
- Avoids co-design complexity and keeps this sprint focused on the freeze/perf correctness bug.
