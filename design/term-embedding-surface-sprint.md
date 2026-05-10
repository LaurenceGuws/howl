# Term Embedding Surface Sprint

## Goal

Make `howl-term` the boring embeddable package surface: catalog-shaped public exports plus compile-time orchestration over lower runtime owners. It should not own runtime mechanics when `howl-session`, `howl-vt-core`, or `howl-render-core` is the clearer owner.

Android is parked until ownership boundaries are pristine. Android runtime proof remains open until real Android runtime code exists; no fake parity checks.

## Ownership Priority

- First: embeddable intuitiveness, checked against `utils/dev_references/terminals/ghostty`.
- Second: raw speed, efficiency, and quality, checked against `utils/dev_references/terminals/alacritty`.
- If references pull differently, keep the embed boundary intuitive and move hot-path internals only when the owner is unambiguous.
- If ownership is unclear, stop and mark `work-not-clear`.

## Non-Negotiable Rules

- Hosts depend on `howl-term` only.
- `howl-term` may depend on session/render/VT roots; lower modules never depend upward.
- Public roots and namespace wrappers stay catalogs.
- Runtime mechanics move down only to a concrete owner, not to a new ambiguous `howl-term` bucket.
- ABI churn is out of scope unless a checkpoint explicitly marks itself ABI-changing.
- No Android parity closure without real Android runtime proof.
- Commit and push every green checkpoint.

## Reference Anchors

| Priority | Reference | Boundary lesson for Howl |
| --- | --- | --- |
| 1 | `ghostty/src/Surface.zig` | The embeddable surface owns the user-facing terminal handle, input callbacks, draw/size/focus surface, and app-runtime linkage. It is intuitive for embedders, but delegates I/O machinery to `termio`. |
| 1 | `ghostty/src/termio.zig` | Terminal I/O is a named domain with `Termio`, `Thread`, backend, mailbox, and messages. PTY/backend lifecycle, write queueing, and I/O thread entry/exit are not smeared into the public root. |
| 1 | `ghostty/src/termio/Exec.zig` | Concrete PTY/subprocess start, stop, resize, read thread setup, write queueing, and process exit handling sit under the I/O/backend owner. |
| 1 | `ghostty/src/termio/mailbox.zig` | Cross-thread write and control messages are I/O-owned mailbox mechanics. Producers publish messages; they do not own the flush loop. |
| 2 | `alacritty_terminal/src/event_loop.rs` | PTY read/write, resize/shutdown messages, parser advancement, and wake events are handled by the terminal event loop, not by the UI shell. |
| 2 | `alacritty_terminal/src/tty/mod.rs` | PTY is a focused abstraction with read/write/register/child-event behavior; platform details are behind the terminal I/O layer. |

## Current Baseline

| Area | Current owner | Baseline status |
| --- | --- | --- |
| Public package root | `howl-term/src/howl_term.zig` | Catalog-shaped and host-facing. |
| Namespace wrapper | `howl-term/src/term_namespace.zig` | Declarative and `c_api`-gated. |
| Linux host dependency | `howl-hosts/howl-linux-host` | Imports `howl_term` root only. |
| C ABI route | `howl-term/src/c_api/*` plus `ffi.zig` ABI names/layouts | Domain-split enough for current route; ABI names preserved. |
| Render pure mechanics | `howl-render-core` | Frame snapshot, pipeline, queue, metrics, frame pixels, and submit output shaping are lower-owned. |
| Session I/O mechanics | `howl-session` | Owned transport storage/construction, lifecycle status query, outbound queueing/flush policy, transport waiting, bounded read pumping and pump budget policy, resize propagation, and control signals are lower-owned. |
| Terminal reply handoff | `howl-term/src/runtime/terminal_reply.zig` | Term-owned sequencing from VT pending output into session outbound input; queue-full preserves VT pending output. |
| Runtime I/O pass | `howl-term/src/runtime/io_tick.zig` | Term-owned hot path from session transport bytes through VT apply, scrollback repair, and render wake decision. |
| Frame wake sequencing | Linux host wake/prepare threads plus `howl-term/src/wake/wake.zig` | Host wake/prepare workers block when idle and coalesce wake requests into latest terminal state. |
| Android proof | none | Parked: `host_runtime_surface_skip=missing_android_runtime`. |

## Sprint 7: Runtime Ownership Board

Purpose: remove remaining runtime implementation ownership from `howl-term` where references and current boundaries prove a lower owner.

Priority rule: Ghostty decides embeddable intuitiveness first; Alacritty decides raw speed/efficiency/quality when the embedding boundary is not weakened.

### Board

| Item | Status | Scope | Exit condition |
| --- | --- | --- | --- |
| Checkpoint 1: reference-boundary audit | complete | Compare Ghostty and Alacritty boundaries to remaining `howl-term` runtime code. | This document classifies each remaining runtime mechanic as lower-owned, term orchestration, or `work-not-clear`. |
| Checkpoint 2: session-owned transport ownership | complete | Move owned transport construction/storage/attach/deinit out of `howl-term` if audit remains green. | `howl-term` no longer stores `howl_session.OwnedTransport`, calls `transport.pty()`, or deinitializes transport directly. |
| Checkpoint 3: lifecycle start/stop split | complete | Decide whether session transport start/stop can become a single session-owned lifecycle operation while thread join/wake remains term orchestration. | Start/stop mechanics are split without session knowing VT/render/thread details. |
| Checkpoint 4: terminal reply handoff | complete | Review `vt.pendingOutput()` to session input publication. | Formalized as term orchestration; no VT reply semantics moved into session. |
| Checkpoint 5: runtime thread boundary | complete | Decide whether the loop remains `howl-term` orchestration or a session I/O runner with callbacks. | Thread lifecycle and hot I/O pass are named separately inside `howl-term`; no VT/render concepts moved into session. |
| Checkpoint 6: wake/render sequencing | complete | Review snapshot wake state and render completion bookkeeping. | Host wake/prepare workers are latest-only and blocking; no sleep, publisher thread, or readiness listener thread was added. |
| Checkpoint 7: session-owned pump budget | complete | Remove remaining transport read-budget constants from `howl-term`. | Session owns named transport pump modes; term only selects normal vs constrained from render backpressure. |

### Out Of Scope

- Android runtime implementation.
- ABI renames or extern struct layout changes.
- Host UX/runtime migration into lower modules.
- Moving VT/render concepts into `howl-session`.
- Moving session/PTY concepts into `howl-vt-core` or `howl-render-core`.

## Checkpoint 1 Audit

| Current Howl code | Current behavior | Reference read | Decision | Next action |
| --- | --- | --- | --- | --- |
| `runtime/lifecycle.zig` owned transport construction path | `HowlTerm.init` passes an owned transport into `Session.initOwnedTransport`; `HowlTerm.initPty` asks `Session.initPty` to construct the build-selected PTY. Term does not store, attach, or deinitialize the owned transport. | Ghostty `termio/Exec.zig` keeps PTY/subprocess ownership below `Surface`; Alacritty keeps PTY under terminal event loop/TTY layer. | `session-owned` | Complete. Parent checks should reject transport storage/attach/deinit returning to `howl-term`. |
| `runtime/lifecycle.zig` starts/stops session and term thread | Calls `Session.start`, `Session.stop`, and `Session.isActive` while keeping thread flags, snapshot waiter stop, wake signal, and join in term. Term no longer branches on raw session status fields or status snapshots. | Ghostty splits I/O backend lifecycle from surface/runtime thread handles; Alacritty event loop owns PTY I/O but UI owns app lifecycle. | mixed: `session-owned` for transport status/start/stop, `term-orchestration-only` for thread/wake/join | Complete. Parent checks should reject direct session status inspection from term runtime/query code. |
| `runtime/thread.zig` drains outbound input and waits for readability through session pump methods | Term thread owns stop/wait/lock sequencing and delegates the locked PTY-to-VT pass to `runtime/io_tick.zig`. | Ghostty `termio` owns mailbox/write mechanics without weakening surface embedding; Alacritty event loop keeps PTY read/write, parser advancement, and wake decisions local for throughput. | `term-orchestration-only` plus session-owned pump calls | Complete. Parent checks keep transport parsing/render wake details out of the thread lifecycle loop. |
| `runtime/io_tick.zig` selects session transport pump mode | Term maps render backpressure to `.normal` or `.constrained`; session owns the actual read count/byte budget policy. | Alacritty keeps PTY drain budgets in the event loop/TTY I/O layer; Ghostty termio owns I/O pump mechanics. | split: term chooses pressure state, session owns pump budget mechanics | Complete. Parent checks reject read-budget constants returning to `howl-term`. |
| `runtime/io_tick.zig` feeds bytes to `vt.feedSlice`, calls `vt.apply`, updates title | Turns transport bytes into VT state and user-visible title in one locked hot path. | Alacritty event loop advances parser with terminal lock; Ghostty stream handler maps terminal actions inside the termio owner. | `vt-owned` plus `term-orchestration-only` | Complete. Do not move to session. Consider a VT handoff only if it stays VT-owned and does not degrade the hot path. |
| `runtime/io_tick.zig` adjusts scrollback and selection after history growth | Maintains viewport/selection behavior after VT history changes. | Ghostty surface owns viewport/selection UX; not PTY/session. | `term-orchestration-only` | Keep in term unless a viewport owner is created within `howl-term` or lower neutral owner becomes obvious. |
| `runtime/terminal_reply.zig` drains `vt.pendingOutput()` into session host input | Bridges terminal replies from VT to PTY/session outbound queue. If session queueing fails, VT pending output is preserved for a later pass. | Ghostty stream handler emits termio write requests; Alacritty parser/event loop handles terminal output notifications. | `term-orchestration-only` | Complete. Parent checks require the named term-owned reply drain and keep raw reply draining out of the thread loop. |
| `input/input.zig` encodes host input with `vt.encodeInput` then publishes through session pump | Maps embed input events to VT bytes and session outbound queue. | Ghostty surface owns input callbacks; termio owns write queue. | split: `vt-owned` encoding, `session-owned` queue, `term-orchestration-only` event sequencing | Keep current split. Do not move pixel-to-cell mapping to session. |
| `wake/wake.zig` owns snapshot condition variable and render completion wake bookkeeping | Publishes render/snapshot wake events and dirty completion. | Ghostty renderer and surface use domain wakeups; Alacritty event loop sends wake events. | `term-orchestration-only` or future render owner, not session | Keep out of session. Revisit only with render-core proof. |
| Linux host wake/prepare workers gate frame wake admission | Wake thread blocks on snapshot events. Prepare thread blocks on its semaphore. Requests arriving while a prepare job is running are coalesced by `prepare_thread_signal_pending`; after a job finishes, only the latest current terminal state is checked. | Ghostty renderer thread drains a mailbox on wake and renders current state; Alacritty treats wake as a UI redraw signal rather than a render-work producer. | host-owned blocking workers plus `term-orchestration-only` wake state | Complete. No sleep-based pacing, no render-work publisher, and no render-output listener thread. |
| `render/render.zig` prepares and submits frames | Coordinates geometry, VT snapshot sync, render-core snapshot copy, renderer prepare/submit, metrics, and wake completion. | Ghostty surface/renderer split and Alacritty rendering quality favor hot-path clarity, but term state crosses VT/render/session. | `term-orchestration-only` | Keep orchestration in term; only move pure render contracts to render-core. |
| `terminal.zig` stores broad runtime state | Public embed handle and method facade over lower owners. | Ghostty `Surface.zig` is an embeddable terminal surface; public roots remain catalogs. | acceptable embed handle, not pure root | Keep as handle while removing mechanics below it. Do not move host UX down. |

## Work-Not-Clear

| Topic | Reason | Required proof before code movement |
| --- | --- | --- |
| Moving runtime I/O pass to `howl-session` | `runtime/io_tick.zig` intentionally touches VT state, title, scrollback, selection, render wake epochs, and session I/O in one hot locked pass. Moving it below term would either import VT/render concepts into session or add callbacks on the critical path. | A callback/event contract that lets session own only I/O without importing VT/render or mutating term state directly, plus proof that the hot path is not slower or less embeddable than the current split. |
| Moving terminal reply drain below `howl-term` | It crosses VT output semantics and session queueing; Checkpoint 4 intentionally formalized it as term-owned orchestration. | A lower-owner contract with tests for queue-full preservation and partial writes that does not import VT semantics into `howl-session`. |
| Moving snapshot wake logic | It mixes render completion, VT dirty epochs, condition variables, and embed wait APIs. | Proof that render-core or another lower owner can own it without session or host concepts. |
| Adding a render-output listener thread | Previous publisher/readiness experiments made prepared-batch availability the pacing driver and risked presentation readiness spinning under load. | Measured proof that readiness is latest-only, blocking when idle, and cannot become a producer-driven hot loop. |

## Verification Cadence

For every implementation checkpoint:

- `howl-session`: `zig build test`
- `howl-term`: `zig build test && zig build ffi:build`
- `howl-linux-host`: `zig build test`
- parent: `sh tools/check_module_shape.sh && zig build && zig build test && ./status.sh`

Use `--summary all` only to diagnose failures.

## Sprint 8: Linux Host Handoff Surface

Purpose: make `howl-linux-host` hand off to `howl-term` through the smallest clear host-owned surface before pursuing lower-module ownership moves.

Priority rule: public export hygiene and embeddable maturity first, ownership assertions second, performance optimization third.

### Board

| Item | Status | Scope | Exit condition |
| --- | --- | --- | --- |
| Checkpoint 1: link and selection host UX split | complete | Move link hover/opening and selection drag behavior out of the broad Linux terminal widget file. | Link-specific term calls live in `terminal/links.zig`; selection-specific term calls live in `terminal/selection.zig`; parent checks reject those mechanics returning to `terminal/terminal.zig`. |
| Checkpoint 2: frame handoff split | complete | Move render wake waiting, frame preparation, and ready-frame rendering handoff out of the Linux terminal widget and thread loops. | Frame-specific term calls live in `terminal/frame.zig`; `terminal/thread.zig` has no direct `self.term.*` calls; parent checks reject frame handoff calls returning to `terminal/terminal.zig`. |
| Checkpoint 3: scroll handoff split | complete | Move wheel/page scrolling, scrollbar mouse handling, passive hover wake, and overlay layout handoff out of the Linux terminal widget. | Scroll-specific term calls live in `terminal/scroll.zig`; parent checks reject scroll state and offset mechanics returning to `terminal/terminal.zig`. |
| Checkpoint 4: input handoff split | complete | Move input event draining and term input publication out of the Linux terminal widget. | Input publication and drain ordering live in `terminal/input_flow.zig`; parent checks reject input publication and raw event draining returning to `terminal/terminal.zig`. |
| Checkpoint 5: lifecycle/config handoff split | complete | Move term creation, font configuration, runtime start, child thread spawn, title/focus sync, and teardown out of the Linux terminal widget. | Lifecycle-specific term calls live in `terminal/lifecycle.zig`; parent checks reject those startup/shutdown mechanics returning to `terminal/terminal.zig`. |
| Checkpoint 6: geometry handoff split | complete | Move geometry locking, resize coalescing, and frame geometry sync out of the Linux terminal widget. | Geometry-specific term calls and mutex mechanics live in `terminal/geometry.zig`; parent checks reject geometry sync/mutex mechanics returning to `terminal/terminal.zig`. |
| Checkpoint 7: focus/title/effects split | complete | Move title refresh, focus publication, and clipboard host effects out of the Linux terminal widget. | Effect-specific term calls live in `terminal/effects.zig`; frame and lifecycle use that module directly; parent checks reject focus/title/clipboard mechanics returning to `terminal/terminal.zig`. |
| Checkpoint 8: font-size policy split | complete | Move zoom, reset, stress-toggle bounds, and term font-size publication out of the Linux terminal widget. | Font-size policy lives in `terminal/font_size.zig`; parent checks reject font-size bounds and direct `setFontSizePx` calls returning to `terminal/terminal.zig`. |
| Checkpoint 9: query facade split | complete | Move host-facing surface, overlay, lifecycle, and text query reads out of the Linux terminal widget. | Read/query facade lives in `terminal/query.zig`; parent checks reject surface-state/text-query mechanics returning to `terminal/terminal.zig`. |

### Open Candidates

| Topic | Reason | Required proof before code movement |
| --- | --- | --- |
| Linux host widget end-state review | The widget is now mostly a facade over focused host modules. | Decide whether any further split remains clear enough to justify the extra file, otherwise stop host decomposition and move back to module hygiene/maturity work. |

## Sprint 9: Android FFI Host Reopen

Purpose: reopen Android only on the same `howl-term` FFI surface used by Linux host backend selection, so Android cannot drift into a second terminal contract again.

Priority rule: one shared term-facing contract first, Android runtime proof second, host chrome/features third.

### Non-Negotiable Rules

- Android host must consume the same `howl-term` FFI contract as Linux host.
- No Android-only JNI terminal surface.
- No Java terminal API that invents new term lifecycle, wake, render, scrollback, or query semantics.
- The only allowed variants across hosts are PTY launch/runtime selection and renderer selection.
- Host wake behavior stays latest-only and blocking when idle; no sleep loops.
- Android parity closes only with real `adb` runtime proof.
- If Android needs a term capability Linux does not use, add it to the shared FFI seam first or stop with `work-not-clear`.

### Why The Previous Android Surface Was Wrong

- `howl-hosts/howl-android-host` commit `60e9aff` correctly deleted the stale Android terminal surface.
- Deleted files such as `src/main/java/howl/term/Terminal.java`, `src/main/java/howl/term/terminal/NativeBinding.java`, and `src/main/java/howl/term/widget/TerminalWidget.java` formed a separate Java/JNI terminal contract.
- That deleted contract embedded Android-specific assumptions into the term seam:
  - bespoke `waitRenderWake` / `presentAck` protocol
  - bespoke retained surface getters
  - Java-owned terminal lifecycle state
  - Java-owned scrollback/query/render telemetry surface
- Recreating that shape would reintroduce Linux/Android drift by definition.

### Target Shape

- Linux stays the reference host.
- Android copies Linux host layering, but binds term calls through the shared FFI seam.
- Desired host shape:
  - app owner: Linux `main.zig`, Android `Main`
  - term seam: Linux `src/terminal/api.zig`, Android `howl.term.terminal.Ffi`
  - widget/runtime composition: Linux `src/terminal/*`, Android `widget/Terminal`
  - platform leaves: Linux SDL/window/input, Android GL/view/input/IME
- Shared seam responsibilities:
  - term init/start/stop/deinit
  - frame geometry sync
  - latest-only render wake wait
  - metadata wake wait
  - prepare/render handoff
  - input/key/mouse/paste/focus publication
  - title/clipboard/query reads already kept in the seam

### Board

| Item | Status | Scope | Exit condition |
| --- | --- | --- | --- |
| Checkpoint 1: Linux FFI seam freeze | proposed | Audit Linux `src/terminal/api.zig` and current `howl-term/src/ffi.zig` as the only Android term surface. | Android reopen scope lists the exact shared FFI calls/types it may use; anything else is explicitly banned. |
| Checkpoint 2: Android delete-line confirmation | proposed | Confirm deleted Java/JNI terminal surface stays deleted and is not partially restored. | No revived `Terminal.java`, `NativeBinding.java`, or old `TerminalWidget.java` logic returns outside the new shared seam shape. |
| Checkpoint 3: Android FFI shim owner | proposed | Add one boring Java owner that mirrors Linux `api.zig` against `libhowl_term.so`. | Android has one FFI class with shared term calls only; no extra semantics or host policy inside it. |
| Checkpoint 4: Android terminal facade rebuild | proposed | Recreate Android `Terminal` as a thin host-local facade over the shared FFI shim. | Android `Terminal` only stores host-local state and forwards shared seam calls; no bespoke terminal protocol. |
| Checkpoint 5: Android widget wake/render split | proposed | Rebuild `widget/Terminal` with separate frame and metadata servicing lanes matching Linux intent. | Android widget blocks on shared render/metadata wakes and does not poll term state in UI loops. |
| Checkpoint 6: Android input and geometry parity | proposed | Reattach Android IME, hardware keyboard, touch, resize, and focus handling through the shared seam. | Android input/geometry behavior uses only shared term calls plus platform-specific input translation. |
| Checkpoint 7: Android host proof on device | proposed | Install, run, and verify on a real `adb` device. | Android shows frame output, title updates, clipboard path, and lifecycle proof through the shared FFI host path. |
| Checkpoint 8: shared-host parity gate | proposed | Add explicit repo checks/docs so Linux and Android must stay on the same seam. | A documented verification step fails if Android reintroduces a private terminal contract or misses the shared seam. |

### Allowed Variants

Only these host differences are allowed:

- PTY/runtime selection
  - Linux may use its normal PTY/runtime path.
  - Android may use Android-specific PTY/userland/runtime setup.
- Renderer selection
  - Linux and Android may bind different render backends or texture ownership details.

Everything else must be outcome-level shared behavior through the same FFI seam.

### Shared FFI Contract Inventory

Android reopen is allowed to consume only the shared term-facing capabilities already represented by Linux `howl-hosts/howl-linux-host/src/terminal/api.zig` over `howl-term` FFI.

Allowed shared types:

- handle and lifecycle
  - `TermHandle`
  - lifecycle state via `surfaceState.state` / `isSessionAlive`
- geometry and frame
  - `FfiFramePixels`
  - `FfiSurfaceState`
  - `FfiSnapshotWake`
  - `FfiMetadataWake`
- viewport and interaction
  - `FfiScrollState`
  - `FfiLinkHoverResult`
- input constants
  - key constants from `ffi.zig`
  - modifier constants from `ffi.zig`
  - mouse kind/button constants from `ffi.zig`

Allowed shared lifecycle calls:

- `createWithStartPath`
- `destroy`
- `isSessionAlive`
- `wakeSnapshotWaiters`
- `wakeMetadataWaiters`

Allowed shared frame/render calls:

- `syncFrameGeometry`
- `needsFrame`
- `needsPrepare`
- `hasQueuedRenderWork`
- `awaitRenderWake`
- `awaitMetadataWake`
- `prepareNextFrame`
- `renderReadyFrame`
- `surfaceState`
- `renderedSnapshotSeq`
- `setRuntimeBackpressure`

Allowed shared font/config calls:

- `setFontSizePx`
- `setPrimaryFontPath`
- `clearFallbackFontPaths`
- `addFallbackFontPath`

Allowed shared input calls:

- `publishInputBytes`
- `publishInputKey`
- `publishPaste`
- `publishMouseEvent`
- `setInputFocusChanged`

Allowed shared metadata/query calls:

- `copyCurrentTitle`
- `drainPendingClipboardSetAlloc`
- `scrollState`
- `followLiveBottomChanged`
- `setScrollbackOffsetChanged`
- `setHoveredLinkAtPixel`
- `copyHyperlinkUriAtPixelAlloc`
- `selectionInProgress`
- `beginSelection`
- `updateSelection`
- `finishSelection`
- `renderedTextContains`

Shared seam rules for Android:

- Android must map its Java FFI shim to this inventory directly.
- Android may wrap memory ownership for alloc-returning calls, but may not change semantics.
- Android may not add substitute calls for render wake, present ack, surface getters, or scroll state when equivalent shared calls already exist.
- If Android needs a new call, Linux `api.zig` must be able to consume the same capability through the same `howl-term` FFI surface.

Explicitly banned Android terminal contract shapes:

- Java-owned terminal lifecycle enum that diverges from the runtime lifecycle exposed by the shared seam
- Android-only `presentAck`
- Android-only `waitRenderWake`
- Android-only retained texture getters separate from `surfaceState`
- Android-only scrollback count/offset protocol separate from `scrollState`, `followLiveBottomChanged`, and `setScrollbackOffsetChanged`
- Android-only terminal telemetry/query surface unless Linux uses the same shared FFI call

### Explicitly Out Of Scope

- Reintroducing the deleted Java/JNI terminal contract.
- Android-only terminal query methods when Linux does not use them.
- Android-only render wake semantics.
- Android-only scrollback or selection protocol.
- Closing parity without device proof.

### Verification Cadence

For every Android reopen checkpoint:

- `howl-term`: `zig build test`
- Linux host: `zig build test && zig build test -Dterm-backend-ffi=true`
- Android host: build the app and install/run on the attached `adb` device
- parent: `sh tools/check_module_shape.sh && zig build && zig build test`

Android proof is green only when the shared FFI path is exercised on device, not just when Java compiles.
