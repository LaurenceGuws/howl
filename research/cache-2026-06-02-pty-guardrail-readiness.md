# PTY Guardrail Readiness Research Cache - 2026-06-02

Research cache. Research only. No product code edits.

## Readiness Judgment

There is a worker-ready PTY guardrail slice, but PTY should stay lower priority for broad hygiene/refactor work. Current PTY source is compact and mostly owner-true; broad reshaping would be fake progress right now.

## Source-Backed Facts

- `howl-pty/src/ffi.zig` defines one call-status enum, four ABI result mirror structs, translation helpers, and exported lifecycle/control/input/pump/wait/read/limits calls.
- `howl-pty/src/session.zig` owns transport chunk/read/byte limits, bounded transport pump behavior, mode limits, terminal stop/snapshot/resize consequences.
- `howl-pty/include/howl_pty.h` is the shipped C ABI contract for statuses, modes, snapshots, pump/read results, and limits.
- `howl-pty/src/test/abi.zig` currently checks struct sizes and some enum values, but not struct alignment, field offsets, session-status values, control-signal values, pump-mode values, or chunk constant.
- `howl-pty/src/test/ffi.zig` covers handle lifecycle, invalid control signals, pump limits, wake seam, and snapshot terminal reason/wait outcome.
- `howl-pty/build.zig` exposes `test:abi`, `test:unit`, `test:integration`, and aggregate `test`.

## Worker-Ready Slice

Tests-only ABI/FFI guardrail hardening.

Allowed files:

- `howl-pty/src/test/abi.zig`
- `howl-pty/src/test/ffi.zig`

Required shape:

- In `src/test/abi.zig`, extend existing comptime block with `@alignOf` checks for all four FFI/C result structs.
- In `src/test/abi.zig`, add `@offsetOf` checks for every field of `FfiSnapshot`, `FfiOutboundPump`, `FfiReadResult`, and `FfiTransportPumpLimits` against the C imported structs.
- In `src/test/abi.zig`, add missing enum/constant parity checks for `HOWL_PTY_SESSION_*`, `HOWL_PTY_CONTROL_SIGNAL_*`, `HOWL_PTY_TRANSPORT_PUMP_*`, and `HOWL_PTY_TRANSPORT_CHUNK_BYTES`.
- In `src/test/ffi.zig`, add invalid launch/initialization guard tests for null pointer with nonzero length, zero dimensions, zero pending capacity, and pending capacity overflow when `usize` can exceed `u32`.
- Do not edit `howl-pty/src/ffi.zig`, `howl-pty/include/howl_pty.h`, or owner files unless a test exposes a real current bug.

## Verification

- From `howl-pty`: `zig build test:abi --summary all`.
- From `howl-pty`: `zig build test:unit --summary all`.
- Optional if touched behavior unexpectedly: `zig build test --summary all`.

## Non-Goals

- No public ABI changes.
- No result/status family collapse.
- No splitting `ffi.zig`.
- No new owner files.
- No launch config struct unless separately authorized by an ABI-product slice.
