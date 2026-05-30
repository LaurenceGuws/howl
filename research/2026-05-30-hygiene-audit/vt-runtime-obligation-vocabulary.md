# VT Runtime Obligation Vocabulary

Date: 2026-05-30

## Question

Decide whether `runtime` in the VT obligation ABI is accepted protocol vocabulary or banned owner
vocabulary leaking into ABI.

## Sources Read

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `research/2026-05-30-hygiene-audit/roadmap.md` Slice 4.4
- `howl-vt/src/terminal.zig`
- `howl-vt/src/ffi.zig`
- `howl-vt/src/libhowl_vt.zig`
- `howl-vt/src/test/abi.zig`
- `howl-linux-host/src/terminal/vt/retained.zig`
- `howl-linux-host/src/terminal/context.zig`
- `howl-linux-host/src/terminal/pty/pump.zig`
- `howl-linux-host/src/main.zig`
- `howl-linux-host/src/window/pacing.zig`

## Current ABI Shape

- VT exports `howl_vt_terminal_query_runtime_obligation` and
  `howl_vt_terminal_progress_runtime`.
- `Terminal.RuntimeObligation` has `pending_now` and `deadline_ns`.
- `Terminal.RuntimeProgress` returns `state_changed` plus a `RuntimeObligation`.
- Current VT implementation returns idle defaults from `runtimeObligation` and `progressRuntime`.
- FFI translates runtime obligation structs only; it does not own policy.
- ABI tests assert runtime obligation result sizes and default idle behavior.

## Host Use

- `howl-linux-host/src/terminal/vt/retained.zig` wraps the C ABI as retained VT calls.
- `Context.runtimeObligationDueNow` and `Context.nextRuntimeObligationWaitMs` query the VT obligation.
- `main.zig` folds due-now runtime obligations into event-loop wake decisions and minimum wait time.
- `window/pacing.zig` treats `runtime_wake` as wait admission, not a frame permit.
- `terminal/pty/pump.zig` calls `progressRuntime` while pumping PTY transport and uses returned
  `pending_now`, `deadline_ns`, and `state_changed` to request more work/redraw.

## Decision

`runtime` is accepted ABI vocabulary for host scheduling obligations. It is not accepted as an owner
name.

Reasoning:

- The ABI describes a contract between VT and hosts: VT may need host-driven progress at or before a
  deadline independent of incoming bytes. That is a scheduling obligation, not a module owner.
- Hosts already own event loops, wake policy, presentation cadence, and runtime orchestration. The
  VT ABI exposes consequences only; host code decides wait admission and redraw policy.
- Renaming the ABI now would be an ABI break with no source-backed improvement in behavior.
- Creating `runtime.zig`, `RuntimeManager`, or a VT runtime owner would violate project law. The
  current owner is still `Terminal` plus FFI translation.

## Invariants

- Do not rename `howl_vt_terminal_query_runtime_obligation` in a hygiene slice.
- Do not rename `howl_vt_terminal_progress_runtime` in a hygiene slice.
- Do not create a `runtime` owner file in `howl-vt`.
- Host `runtime_wake` remains loop wake/admission vocabulary, not render/frame permission.
- VT FFI remains a translator for the obligation/result structs.

## Proposed Next Slice

No implementation slice is required from this scratchpad alone.

If a documentation slice is desired, update `project-memory.md` or the hygiene roadmap with the
accepted vocabulary rule:

- `runtime` is allowed in ABI and host scheduling field names when it names a scheduling obligation.
- `runtime` remains banned as an owner/module name.

Verification for a documentation-only slice:

- `git diff --check`
- `rg 'runtime_obligation|RuntimeObligation|runtime' howl-vt howl-linux-host project-memory.md`

## Proof Gaps

- Future non-idle runtime behavior still needs a feature-specific owner. This scratchpad does not
  authorize adding a runtime owner.
