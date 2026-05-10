# Module Public Export Shape Sprint

## Goal

Make every public Howl module entrypoint look and behave like a curated public API catalog in the spirit of Ghostty's `src/lib_vt.zig`.

This is about shape and hygiene, not copying Ghostty symbol names. A pristine root file should be boring to read: import owned implementation files, re-export deliberate public domains and types, group special API areas under clear namespaces, gate ABI exports explicitly, and run public-surface compile checks.

## Reference Shape

Ghostty `lib_vt.zig` has these important properties:

- The root is a public catalog, not the implementation owner.
- One or more implementation owners are imported privately near the top.
- Public modules/domains are re-exported intentionally with `pub const`.
- Public types are aliases from owners, not newly invented wrapper types.
- Special areas such as input are grouped under a nested public namespace.
- C ABI export wiring is explicit and gated in one place.
- Root tests reference the public surface, not private implementation details.

## Non-Negotiable Target

Every package root must become a catalog-shaped file.

This includes `howl-term/src/howl_term.zig`. It must stop being the large runtime owner file. The runtime owner body needs to move to a specific implementation file, then `howl_term.zig` should re-export the public runtime type and related public domains from that owner.

Target sketch for `howl-term/src/howl_term.zig`:

```zig
//! Public API of the howl-term Zig module.

const lib = @This();
const std = @import("std");

const terminal = @import("terminal.zig");
const input = @import("input/input.zig");
const ffi = @import("ffi.zig");

pub const HowlTerm = terminal.HowlTerm;
pub const Input = terminal.Input;
pub const Ffi = ffi;

pub const runtime = struct {
    pub const LifecycleState = terminal.LifecycleState;
    pub const FramePixels = terminal.FramePixels;
    pub const SurfaceState = terminal.SurfaceState;
    pub const ScrollState = terminal.ScrollState;
};

test {
    std.testing.refAllDecls(lib);
}
```

The exact names can change during implementation, but the shape cannot: root files are catalogs; owner files own state and behavior.

## Current Mismatch

- `howl-vt-core/src/vt_core.zig` is close to the target catalog shape.
- `howl-render-core/src/howl_render.zig` is close, but still needs a cleaner grouping story for render contracts vs runtime.
- `howl-session/src/root.zig` is a small catalog, but should be reorganized into deliberate public groups instead of a flat list.
- `howl-term/src/howl_term.zig` is not close. It is a runtime owner with fields and methods. This is the main gap.
- Host roots are executable/test roots, not package API roots, but they still need clear import boundaries and thin test aggregation.

## Work Rules

- Work sequentially and commit each checkpoint.
- No fake completion: a sprint is complete only when the root shape actually matches the catalog target.
- Do not use compatibility shims unless they protect real external consumers or persisted ABI.
- Do not duplicate VT input vocabulary in `howl-term`.
- Do not expose backend/session/VT internals through hosts.
- Verify each checkpoint with targeted repo tests and parent `zig build test --summary all`.
- Keep Android runtime proof explicitly open until real Android runtime code exists.

## Active Checkpoint

Sprint 0 is active.

Do not start root reshaping until the export inventory and keep/move/remove decisions are written into this document.

## Sprint 0: Public Surface Inventory

Purpose: know exactly what each root exports and who consumes it before moving code.

Tasks:

- Inventory every `pub const`, `pub fn`, and public nested namespace in these roots: `howl-vt-core/src/vt_core.zig`, `howl-session/src/root.zig`, `howl-render-core/src/howl_render.zig`, `howl-term/src/howl_term.zig`, `howl-hosts/howl-linux-host/src/main.zig`, `howl-hosts/howl-linux-host/src/test_host.zig`.
- Inventory cross-repo consumers of each public root export.
- Classify every export as public contract, test-only contract, ABI glue, or internal leak.
- Write the inventory into this sprint doc before implementation starts.

Acceptance:

- The doc contains an export table for each root.
- Each export has a keep/move/remove decision.
- No code movement has happened yet, except inventory-only docs.

## Sprint 1: Define Catalog Shape Checks

Purpose: update enforcement to match the real target before doing broad movement.

Tasks:

- Change parent shape checks so package roots are forbidden from owning large runtime structs directly.
- Add a check that `howl-term/src/howl_term.zig` is catalog-shaped and does not contain runtime fields.
- Add checks for root tests that reference public declarations.
- Preserve existing dependency direction checks.
- Keep explicit executable-owner exceptions for host `main.zig` only.

Acceptance:

- The checks describe the target shape, even if temporarily marked as expected-failing in the doc.
- No checkpoint claims completion until checks pass without expected-fail markers.

## Sprint 2: `howl-term` Root Reshape

Purpose: fix the biggest mismatch first.

Tasks:

- Move the current `HowlTerm` runtime owner body out of `src/howl_term.zig` into a specific owner file such as `src/terminal.zig`.
- Keep implementation imports in the owner file, not the root catalog.
- Make `src/howl_term.zig` a public catalog that imports the owner and re-exports deliberate public API.
- Group public contract areas under clear namespaces where useful: runtime state, frame/render surface, input, FFI.
- Keep host-facing Zig API working or update hosts in the same checkpoint if the public shape intentionally changes.
- Keep FFI ABI fields stable, including `FfiPrepareMetrics.term_us`.

Acceptance:

- `howl_term.zig` has no runtime fields.
- `howl_term.zig` reads as a public catalog comparable to `lib_vt.zig`.
- Linux host builds and tests pass.
- Parent workspace tests pass.

## Sprint 3: `howl-vt-core` Catalog Polish

Purpose: make the closest module the reference Howl root.

Tasks:

- Keep `src/vt_core.zig` as a catalog only.
- Group VT input APIs in a nested namespace if that reads closer to the Ghostty shape without breaking consumers unnecessarily.
- Keep `terminal.zig` as the VT runtime/protocol owner.
- Ensure root tests reference all public exports.

Acceptance:

- `vt_core.zig` is the example for other Howl package roots.
- Consumers do not import private VT implementation files.

## Sprint 4: `howl-render-core` Catalog Polish

Purpose: separate render contracts from selected backend runtime shape.

Tasks:

- Decide the public grouping for render contracts, renderer runtime, and backend-selected helpers.
- Keep backend implementation details out of root exports unless grouped under an explicit public namespace.
- Ensure `howl-term` uses only root-level render contracts.
- Add or update root public-surface tests.

Acceptance:

- `howl_render.zig` is a catalog, not a backend leak.
- Linux host still has no direct render-core dependency.

## Sprint 5: `howl-session` Catalog Polish

Purpose: make session root deliberate, grouped, and test-aware.

Tasks:

- Group session runtime contracts separately from PTY contracts.
- Keep test PTYs under a clearly test-only namespace.
- Keep PTY ownership in session.
- Add or update root public-surface tests.

Acceptance:

- `root.zig` reads like a public catalog with grouped domains.
- Production API and test-only API are visually distinct.

## Sprint 6: Host Root Boundaries

Purpose: keep host roots clear without pretending they are package catalogs.

Tasks:

- Keep host `main.zig` as executable owner.
- Keep host test roots thin.
- Enforce that hosts consume terminal runtime through `howl-term` only.
- Remove any direct host dependency on lower modules if found.

Acceptance:

- Host roots are small where appropriate.
- Import direction checks pass.

## Sprint 7: ABI And Platform Proof Gate

Purpose: keep public catalog cleanup from hiding ABI or platform proof gaps.

Tasks:

- Keep C/FFI exports explicit and easy to audit from the `howl-term` public root.
- Preserve stable ABI fields unless an ABI-changing checkpoint explicitly says otherwise.
- Keep Android runtime proof missing as an explicit open item.
- Do not add stubs or fake Android parity.

Acceptance:

- Native checks pass.
- Android compile-only proof remains real if run.
- Runtime proof gap remains explicit until actual Android runtime code exists.

## Done Means Done

- All package roots are catalog-shaped like `lib_vt.zig` in structure.
- `howl-term/src/howl_term.zig` is no longer the runtime owner body.
- Owner files own state and behavior behind roots.
- Public exports are intentional and grouped.
- Root public-surface tests exist for each package.
- Parent shape checks enforce the catalog shape.
- Parent `zig build test --summary all` passes.
- `./status.sh` is empty after commits and pushes.
