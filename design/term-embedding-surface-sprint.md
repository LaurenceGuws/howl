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
| Session I/O mechanics | `howl-session` | Owned transport storage/construction, outbound queueing/flush policy, transport waiting, bounded read pumping, resize propagation, and control signals are lower-owned. |
| Android proof | none | Parked: `host_runtime_surface_skip=missing_android_runtime`. |

## Sprint 7: Runtime Ownership Board

Purpose: remove remaining runtime implementation ownership from `howl-term` where references and current boundaries prove a lower owner.

### Board

| Item | Status | Scope | Exit condition |
| --- | --- | --- | --- |
| Checkpoint 1: reference-boundary audit | complete | Compare Ghostty and Alacritty boundaries to remaining `howl-term` runtime code. | This document classifies each remaining runtime mechanic as lower-owned, term orchestration, or `work-not-clear`. |
| Checkpoint 2: session-owned transport ownership | complete | Move owned transport construction/storage/attach/deinit out of `howl-term` if audit remains green. | `howl-term` no longer stores `howl_session.OwnedTransport`, calls `transport.pty()`, or deinitializes transport directly. |
| Checkpoint 3: lifecycle start/stop split | ready | Decide whether session transport start/stop can become a single session-owned lifecycle operation while thread join/wake remains term orchestration. | Start/stop mechanics are split without session knowing VT/render/thread details. |
| Checkpoint 4: terminal reply handoff | candidate | Review `vt.pendingOutput()` to session input publication. | Either formalize as term orchestration or move only if a precise VT/session contract exists. |
| Checkpoint 5: runtime thread boundary | candidate | Decide whether the loop remains `howl-term` orchestration or a session I/O runner with callbacks. | No move unless session can own I/O without importing VT/render concepts. |
| Checkpoint 6: wake/render sequencing | later | Review snapshot wake state and render completion bookkeeping. | Keep out of session; move only to render-core or a neutral owner if proven. |

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
| `runtime/lifecycle.zig` starts/stops session and term thread | Calls session start/stop while also handling thread flags, snapshot waiter stop, wake signal, and join. | Ghostty splits I/O backend lifecycle from surface/runtime thread handles; Alacritty event loop owns PTY I/O but UI owns app lifecycle. | mixed: `session-owned` for transport start/stop, `term-orchestration-only` for thread/wake/join | Checkpoint 3. Do not move as one block. |
| `runtime/thread.zig` drains outbound input and waits for readability through session pump methods | Term sequences session-owned outbound/read pumps with VT apply and render wake. | Ghostty `termio` owns mailbox/write mechanics; Alacritty event loop owns PTY write/read loops. | current lower ownership is acceptable | Keep session pump checks. Further loop move is `work-not-clear` until callback boundaries are designed. |
| `runtime/thread.zig` feeds bytes to `vt.feedSlice`, calls `vt.apply`, updates title | Turns transport bytes into VT state and user-visible title. | Alacritty event loop advances parser with terminal lock; Ghostty stream handler maps terminal actions. | `vt-owned` plus `term-orchestration-only` | Do not move to session. Consider a VT handoff helper only if it stays VT-owned. |
| `runtime/thread.zig` adjusts scrollback and selection after history growth | Maintains viewport/selection behavior after VT history changes. | Ghostty surface owns viewport/selection UX; not PTY/session. | `term-orchestration-only` | Keep in term unless a viewport owner is created within `howl-term` or lower neutral owner becomes obvious. |
| `runtime/thread.zig` drains `vt.pendingOutput()` into session host input | Bridges terminal replies from VT to PTY/session outbound queue. | Ghostty stream handler emits termio write requests; Alacritty parser/event loop handles terminal output notifications. | `term-orchestration-only` for now | Checkpoint 4 candidate. Needs explicit VT/session contract before moving. |
| `input/input.zig` encodes host input with `vt.encodeInput` then publishes through session pump | Maps embed input events to VT bytes and session outbound queue. | Ghostty surface owns input callbacks; termio owns write queue. | split: `vt-owned` encoding, `session-owned` queue, `term-orchestration-only` event sequencing | Keep current split. Do not move pixel-to-cell mapping to session. |
| `wake/wake.zig` owns snapshot condition variable and render completion wake bookkeeping | Publishes render/snapshot wake events and dirty completion. | Ghostty renderer and surface use domain wakeups; Alacritty event loop sends wake events. | `term-orchestration-only` or future render owner, not session | Keep out of session. Revisit only with render-core proof. |
| `render/render.zig` prepares and submits frames | Coordinates geometry, VT snapshot sync, render-core snapshot copy, renderer prepare/submit, metrics, and wake completion. | Ghostty surface/renderer split and Alacritty rendering quality favor hot-path clarity, but term state crosses VT/render/session. | `term-orchestration-only` | Keep orchestration in term; only move pure render contracts to render-core. |
| `terminal.zig` stores broad runtime state | Public embed handle and method facade over lower owners. | Ghostty `Surface.zig` is an embeddable terminal surface; public roots remain catalogs. | acceptable embed handle, not pure root | Keep as handle while removing mechanics below it. Do not move host UX down. |

## Work-Not-Clear

| Topic | Reason | Required proof before code movement |
| --- | --- | --- |
| Moving entire runtime thread to `howl-session` | The loop currently touches VT state, title, scrollback, selection, render wake epochs, and session I/O. | A callback/event contract that lets session own only I/O without importing VT/render or mutating term state directly. |
| Moving terminal reply drain out of `howl-term` | It crosses VT output semantics and session queueing. | A named VT/session handoff contract with tests for queue-full preservation and partial writes. |
| Moving snapshot wake logic | It mixes render completion, VT dirty epochs, condition variables, and embed wait APIs. | Proof that render-core or another lower owner can own it without session or host concepts. |

## Verification Cadence

For every implementation checkpoint:

- `howl-session`: `zig build test`
- `howl-term`: `zig build test && zig build ffi:build`
- `howl-linux-host`: `zig build test`
- parent: `sh tools/check_module_shape.sh && zig build && zig build test && ./status.sh`

Use `--summary all` only to diagnose failures.
