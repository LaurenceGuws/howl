# Module FFI Route Sprint

## Goal

Give every Howl module a first-class FFI/C ABI route shaped like Ghostty's `lib_vt.zig` route.

This means the public root owns the ABI route shape: it imports a module-local FFI namespace, exposes it deliberately, and gates C symbol exports from the root with `comptime` `@export` wiring when the root is being built as the C library. FFI code must be real ABI surface, not placeholder stubs.

## Reference Shape

Ghostty `src/lib_vt.zig` does three important things:

- Public root imports the implementation owner.
- Public root exposes Zig API as a catalog.
- Public root has a `comptime` export block that exports C ABI functions from an internal C API namespace only when `@import("root") == lib`.

Target shape for Howl roots:

```zig
const lib = @This();
const ffi = @import("ffi.zig");

pub const Ffi = ffi;

comptime {
    if (@import("root") == lib) {
        @export(&ffi.someFunction, .{ .name = "howl_module_some_function" });
    }
}
```

Exact symbol names are module-specific, but every exported C symbol must have an intentional ABI reason and a stable prefix.

## Current State

| Module | Current FFI state | Gap |
| --- | --- | --- |
| `howl-term` | Has `src/ffi.zig` and `pub const Ffi` from root. ABI functions are currently `pub export fn` inside `ffi.zig`. | Convert to first-class root-gated `@export` route without changing C symbol names or ABI fields. |
| `howl-vt-core` | No public FFI route. | Add real VT FFI namespace and root gate for useful backend-agnostic terminal/input primitives only. |
| `howl-session` | No public FFI route. | Add real session/PTY FFI route only for session-owned contracts that make sense outside Zig. |
| `howl-render-core` | No public FFI route; existing `c_api` names are backend C dependency imports, not public ABI. | Add render FFI route for render-core owned contract helpers where useful; do not expose backend internals. |
| hosts | Host roots are executable/runtime owners, not module FFI roots. | Hosts should consume module FFI, not define lower-module ABI. |

## Rules

- No fake FFI. If a module has no real ABI functions yet, mark it open in checks and docs instead of adding no-op exports.
- C symbol prefixes must be module-specific: `howl_vt_*`, `howl_session_*`, `howl_render_*`, `howl_term_*`.
- Root `comptime @export` is the preferred route. Avoid scattered `pub export fn` as the long-term shape.
- ABI structs must be `extern` and intentionally documented by name.
- Do not change existing `howl-term` ABI names or fields unless an ABI-changing checkpoint explicitly says so.
- Preserve `FfiPrepareMetrics.term_us`.
- Verify each module with targeted tests and parent `zig build test --summary all`.

## Active Checkpoint

Sprint 0 is active.

Do not implement new ABI functions until the current ABI inventory and first implementation order are committed.

## Sprint 0: ABI Inventory And Export Plan

Purpose: record exactly what exists and define the first safe conversion.

Tasks:

- Inventory `howl-term/src/ffi.zig` exported symbols and ABI structs.
- Confirm no public ABI route exists in VT/session/render roots.
- Decide the first module to convert.
- Add parent checks that report missing module FFI routes as explicit open markers.

Acceptance:

- This doc lists current ABI state and first implementation order.
- Parent checks print open markers for missing first-class FFI routes.
- No fake `ffi.zig` files are added.

Current open markers from `tools/check_module_shape.sh`:

- `vt_core_ffi_route_missing`: `howl-vt-core` has no first-class FFI route yet.
- `session_ffi_route_missing`: `howl-session` has no first-class FFI route yet.
- `render_ffi_route_missing`: `howl-render-core` has no first-class FFI route yet.
- `term_ffi_root_export_route_missing`: `howl-term` has an FFI module, but root does not own Ghostty-style `@export` wiring yet.

First implementation order:

- Start with `howl-term` because it has real existing ABI and the first checkpoint can preserve behavior while changing route shape.
- Then implement `howl-render-core` geometry ABI because the contract is small and backend-agnostic.
- Then implement `howl-session` constants/status ABI.
- Then implement `howl-vt-core` input/constants ABI.

## Sprint 1: `howl-term` Root-Gated ABI Route

Purpose: convert the existing real ABI route to Ghostty-style root ownership without ABI churn.

Tasks:

- Convert `howl-term/src/ffi.zig` functions from exported symbols to callable ABI functions where needed.
- Add root `comptime` export block in `howl-term/src/howl_term.zig`.
- Preserve current C symbol names exactly.
- Preserve ABI structs and `FfiPrepareMetrics.term_us`.
- Keep `pub const Ffi = ffi` as the Zig-facing ABI namespace.

Acceptance:

- Existing term ABI symbols still export with the same names.
- Root owns the export route.
- Native and parent tests pass.

## Sprint 2: `howl-vt-core` FFI Route

Purpose: expose real VT-owned backend-agnostic primitives through a module FFI route.

Candidate ABI areas:

- Input constants and modifier values.
- Input encoding helpers if they can be made useful without owning a host/session.
- Small parser/control helpers only if already stable enough.

Acceptance:

- `howl-vt-core/src/vt_core.zig` has `pub const Ffi` and a root `comptime` export block.
- Exported symbols use `howl_vt_*` prefix.
- No fake terminal runtime stubs.

## Sprint 3: `howl-session` FFI Route

Purpose: expose real session-owned contracts where C consumers can use them safely.

Candidate ABI areas:

- `ControlSignal` constants/raw conversion.
- PTY launch/config value helpers only if they do not fake platform runtime behavior.
- Session status constants.

Acceptance:

- `howl-session/src/root.zig` has `pub const Ffi` and a root `comptime` export block.
- Exported symbols use `howl_session_*` prefix.
- PTY behavior is not stubbed.

## Sprint 4: `howl-render-core` FFI Route

Purpose: expose render-core owned contract helpers without exposing backend internals.

Candidate ABI areas:

- Geometry helpers: derive grid size and derive frame grid size.
- Stable value structs: pixel size, cell size, grid size.
- Possibly color/handle structs if already ABI-safe.

Acceptance:

- `howl-render-core/src/howl_render.zig` has `pub const Ffi` and a root `comptime` export block.
- Exported symbols use `howl_render_*` prefix.
- Backend implementation types remain private.

## Sprint 5: Parent Enforcement

Purpose: make first-class FFI route shape enforceable.

Tasks:

- Parent shape checks require module roots to expose `pub const Ffi` once real route lands.
- Parent checks require root-gated export blocks for each module with ABI.
- Missing route markers are removed only when real ABI functions exist.

Acceptance:

- `zig build` emits no FFI route open markers.
- `zig build test --summary all` passes.
- `./status.sh` is empty after commits and pushes.

## Done Means Done

- Every module root has a first-class FFI route or an explicit documented reason why it is still open.
- Existing `howl-term` ABI remains stable.
- VT/session/render expose only real module-owned ABI, no stubs.
- C symbol ownership is obvious from prefixes.
- Root files own C export wiring like Ghostty `lib_vt.zig`.
