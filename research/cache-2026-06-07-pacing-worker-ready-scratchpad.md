# Pacing Lane Worker-Ready Scratchpad

Research loop:

- researcher session: `ses_15d706406ffe3DzK7XbbPdCUyk`
- reviewer session: `ses_15d68c9d0ffeyz3CuIAos5uYoK`

Status:

- worker-ready after hostile reviewer deltas below

## Sprint Goal

Remove owner-thread PTY/runtime churn that occurs with no real admission reason, while preserving the accepted pacing model and preserving retained render/present ownership.

Hard constraints:

- preserve `pty_pump.Outcome.keep` semantics exactly
- preserve retained render/present ownership exactly
- do not move PTY parsing or VT progression into the wait thread
- do not make swap completion the pacing owner

## Authority Model

- `howl-linux-host/src/event_loop.zig`
  - owns SDL wake-event registration, enqueueing, bounded draining, quit state, and SDL wait/no-wait execution
  - does not own frame cadence, PTY readability, VT progression, or present policy
- `howl-linux-host/src/display/frame_timer.zig`
  - owns frame permits and monitor-cadence timing only
  - does not own runtime scheduling
- `howl-linux-host/src/display/display.zig`
  - owns GL context lifetime, synchronous present submission, and present token bookkeeping
  - does not own pacing policy
- `howl-linux-host/src/app/present.zig`
  - owns mapping from terminal render consequences to host present reasons and host-token to retained-present bridging
- `howl-linux-host/src/terminal/context.zig`
  - owns per-terminal owner-thread orchestration and is the true owner of PTY/runtime drive admission
- `howl-linux-host/src/terminal/pty/wait_thread.zig`
  - owns blocking readability wait plus background-to-owner wake handoff only
- `howl-linux-host/src/terminal/pty/pump.zig`
  - owns one bounded PTY/runtime slice and `Outcome.keep`
- `howl-linux-host/src/terminal/render/retained.zig`
  - owns prepare/submit/present-in-flight retained state

## Hard Decisions

- keep `Outcome.keep` unchanged
- keep retained render/present ownership unchanged
- sticky host-input admission remains processor-owned, but is only the first admission reason for newly published active-tab input
- continuation admission after any real PTY/runtime slice is per-terminal and lives on `Context`
- `Context.driveProgress` has exactly one production API shape
- `context_test.zig` proves admission and continuation through a context-owned testing seam

## Slice A

Purpose:

- fix PTY/runtime drive admission without changing `Outcome.keep`

Files:

- `howl-linux-host/src/terminal/context.zig`
- `howl-linux-host/src/app/processor.zig`
- `howl-linux-host/src/terminal/context_test.zig`

Exact symbols:

- `Context.progress_continuation_pending`
- `Context.DriveAdmission`
- `Context.DriveProgressResult`
- `Context.driveProgress`
- `Context.driveProgressWith`
- `context_mod.testing.driveProgressWith`
- `Processor.terminal_input_admitted`
- `Processor.peekTerminalInputAdmission`
- `Processor.clearTerminalInputAdmissionOnDrive`
- `Processor.driveRuntimeProgress`
- `Processor.driveTerminalProgress`
- `Processor.driveTabRuntimeTurn`
- `Processor.computeLoopAdmission`

Exact production API:

```zig
pub const DriveAdmission = struct { input_published: bool };
pub const DriveProgressResult = struct { drove: bool, outcome: pty_pump.Outcome };
pub fn driveProgress(self: *Context, active: bool, now_ns: u64, admission: DriveAdmission) DriveProgressResult
```

Exact invariant:

- a PTY/runtime slice is admitted if any of these are true:
  - `self.progress_continuation_pending`
  - `pty_wait_thread.wakePending(self)`
  - `self.runtimeObligationDueNow(now_ns)`
  - `active and admission.input_published`
- if none are true, no PTY/runtime drive occurs
- if a real drive occurs:
  - returned `drove=true`
  - `self.progress_continuation_pending = outcome.keep`
- if no real drive occurs:
  - returned `drove=false`
  - `self.progress_continuation_pending` is unchanged
- `Processor.terminal_input_admitted` is not a continuation mechanism
- follow-up admission after `Outcome.keep=true` comes from `Context.progress_continuation_pending`

Processor-owned admission rule:

- `computeLoopAdmission` must still use `terminal_input_admitted` for wait/no-wait policy
- it must do so non-destructively through `peekTerminalInputAdmission(self.terminal_input_admitted)`
- destructive `takeTerminalInputAdmission` is removed from this path
- only `clearTerminalInputAdmissionOnDrive(&self.terminal_input_admitted, drive_result.drove)` may clear the bit
- if `drive_result.drove=false`, the bit must remain set

Mandatory proofs:

- in `howl-linux-host/src/terminal/context_test.zig` through `context_mod.testing.driveProgressWith(...)`
  - no-admission path returns `drove=false`
  - first drive admitted by `input_published=true` can return fake `Outcome.keep=true`
  - second drive with `input_published=false`, `wakePending=false`, runtime not due, and `progress_continuation_pending=true` still returns `drove=true`
  - later drive with `Outcome.keep=false` clears continuation state
  - inactive-tab continuation also re-enters on `progress_continuation_pending=true`
- in inline processor tests in `howl-linux-host/src/app/processor.zig`
  - non-destructive wait admission
  - clear-on-drove
  - preserve-on-no-drive

Out of scope:

- changing `Outcome.keep`
- moving PTY reads, VT feed, or runtime progression into `wait_thread.zig`
- frame-pacer redesign
- retained render/present changes

Stop conditions:

- stop if continuation cannot be owned per-terminal on `Context` without broad unrelated reshaping
- stop if preserving follow-up `keep=true` turns requires redefining `Outcome.keep`
- stop if `context_test.zig` cannot prove continuation through `context_mod.testing.driveProgressWith(...)`

## Slice B

Purpose:

- coalesce synthetic SDL wake events across owner-thread and wait-thread callers

Files:

- `howl-linux-host/src/event_loop.zig`

Exact symbols:

- `EventLoop.wake_queued: std.atomic.Value(bool)`
- `EventLoop.init`
- `EventLoop.wakeWith`
- `EventLoop.processEvent`
- `EventLoop.requestQuitWith`

Exact invariant:

- `wake_queued=false` means no synthetic wake event is outstanding
- `wakeWith` performs atomic `swap(true)`
  - previous `false`: enqueue one synthetic wake event
  - previous `true`: enqueue nothing
- failed synthetic wake push is fail-stop for this slice; worker must not retry or clear the bit after a failed push
- only owner-thread synthetic wake-event consumption clears `wake_queued=false`
- `requestQuitWith` sets `quit_requested=true` before `wakeWith`
- an already queued wake is sufficient to release wait and expose quit

Mandatory proofs:

- duplicate wake calls collapse to one pushed event
- synthetic wake consumption re-arms future wake pushes
- queued wake plus quit still yields correct quit behavior
- synthetic wake still does not become input

Out of scope:

- scheduler extraction
- changes to PTY wait-thread `wake_pending`
- SDL event turn bound changes
- converting wake events into redraw events

Stop conditions:

- stop if correctness depends on SDL wake/wait guarantees not proved by current source/reference set
- stop if worker attempts failed-push retry or failed-push release logic; this lane has no source-backed SDL recovery contract for synthetic wake push failure
- stop if wake coalescing cannot remain fully owned by `EventLoop`

## Ordering

1. Slice B
2. Slice A
3. Combined verification: `zig build test:unit --summary all`

## Reviewer Acceptance Gates

- reject if retained render/present ownership changed
- reject if `Outcome.keep` meaning changed
- reject if continuation after `Outcome.keep=true` still depends on sticky input admission or a fresh wait-thread wake
- reject if there is more than one live `Context.driveProgress` API shape
- reject if `context_test.zig` cannot fake PTY outcomes through `context_mod.testing.driveProgressWith(...)`
- reject if any new continuation state lives in `Processor` instead of per-terminal `Context`
- reject if `computeLoopAdmission` still clears terminal-input admission
- reject if any destructive equivalent of `takeTerminalInputAdmission` remains in the wait-admission path
- reject if processor-level clear-on-drove and preserve-on-no-drive proofs are absent
