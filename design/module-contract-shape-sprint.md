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
- `howl-session/src/howl_session.zig` is a small catalog with explicit `runtime`, `transport`, and `testing` groups.
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

The public export shape sprint checkpoints are complete.

Current follow-up focus: keep catalog-shape checks green while closing the separately tracked Android runtime proof gap. Do not replace that proof with stubs or fake parity.

## Sprint 0 Inventory

This inventory is the source of truth for the first implementation pass. "Keep" means keep as part of the public catalog shape. "Move" means move implementation ownership behind the catalog root. "Remove" means delete or privatize after consumers are updated.

### `howl-vt-core/src/vt_core.zig`

| Export | Current consumers | Class | Decision |
| --- | --- | --- | --- |
| `Input` | `howl-term` input routing and public `howl_term.Input`; VT tests | Public contract | Keep; consider nested `input` grouping only if consumer churn is justified. |
| `Grid` | `howl-term/src/render/sync.zig`; VT tests | Public contract | Keep. |
| `Parser` | VT tests/self surface | Public contract | Keep if parser is intended as public protocol API; otherwise mark for future removal after test audit. |
| `Snapshot` | VT tests/self surface | Public contract candidate | Keep for now; confirm external need in Sprint 3. |
| `Selection` | VT tests/self surface | Public contract candidate | Keep for now; confirm external need in Sprint 3. |
| `VtCore` | `howl-term` runtime and fuzz; VT tests | Public runtime type | Keep as alias from `terminal.zig`. |

Shape decision: this root is already catalog-shaped. Do not move implementation into it. Sprint 3 should only polish grouping and public-surface tests.

### `howl-session/src/howl_session.zig`

| Export | Current consumers | Class | Decision |
| --- | --- | --- | --- |
| `runtime.Session` | `howl-session` tests; top-level `Session` remains for `howl-term` | Public contract namespace | Keep grouped under `runtime`; keep top-level alias as deliberate stable catalog export. |
| `runtime.Config` | Top-level `SessionConfig` alias | Public contract namespace | Keep. |
| `runtime.Status` | `howl-session` tests; top-level `SessionStatus` alias | Public contract namespace | Keep. |
| `runtime.Snapshot` | Top-level `SessionSnapshot` alias | Public contract namespace | Keep. |
| `runtime.Ops` | Top-level `SessionOps` alias | Public contract namespace | Keep. |
| `pty.Pty` | Top-level `Pty` alias | Public PTY namespace | Keep. |
| `pty.Class` | `howl-session` tests; top-level `PtyClass` alias | Public PTY namespace | Keep. |
| `pty.ControlSignal` | `howl-term` control-signal mapping through top-level alias; `howl-session` tests | Public PTY namespace | Keep. |
| `transport.Owned` | `howl-term` runtime owner through top-level `OwnedTransport` alias | Public transport namespace | Keep. |
| `pty.LaunchConfig` | Top-level `PtyLaunchConfig` alias and `pty.init` | Public PTY namespace | Keep. |
| `pty.class` | `howl-session` tests; top-level `pty_class` alias | Public PTY namespace | Keep. |
| `pty.init` | Top-level `initPty`; `howl-term` lifecycle | Public PTY namespace | Keep. |
| `testing.Transport.Mem` | `howl-session` tests; top-level `TestTransport` remains for fuzz/tests | Test-only namespace | Keep; visually separated from production API. |
| `testing.Transport.Partial` | `howl-session` tests; top-level `TestTransport` remains for fuzz/tests | Test-only namespace | Keep. |
| `testing.Transport.Fail` | `howl-session` tests; top-level `TestTransport` remains for fuzz/tests | Test-only namespace | Keep. |

Consumer cleanup note: `howl-term/src/fuzz/terminal_replies.zig` uses the deliberate top-level `howl_session.TestTransport.*` alias. Session-owned tests use the grouped `howl_session.testing.Transport.*` names.

Shape decision: root is catalog-shaped with grouped runtime, PTY, and test-only namespaces. Top-level aliases remain deliberate stable exports for current downstream consumers.

### `howl-render-core/src/howl_render.zig`

| Export | Current consumers | Class | Decision |
| --- | --- | --- | --- |
| `Core` | `howl-term` render/snapshot/sync/benchmark; render-core tests | Public contract namespace | Keep; consider more Ghostty-like domain aliasing only after consumer audit. |
| `Renderer` | `howl-term/src/render/render.zig`; render-core tests | Public runtime type | Keep as selected renderer runtime alias from `renderer.zig`. |
| `geometry.deriveGridSize` | render-core tests | Public helper namespace | Keep grouped under `geometry`; no top-level helper alias. |
| `geometry.deriveGridForFrame` | render-core tests | Public helper namespace | Keep grouped under `geometry`; no top-level helper alias. |

Shape decision: root is catalog-shaped. Sprint 4 moved geometry helpers under `geometry` and removed unused top-level `init`.

### `howl-term/src/howl_term.zig`

| Export | Current consumers | Class | Decision |
| --- | --- | --- | --- |
| `Ffi` | Native ABI build/export surface | ABI glue | Keep in root catalog as explicit ABI area. |
| `Input` | FFI and Linux host input conversion via `howl_term.Input` | Public pass-through contract | Keep; do not duplicate VT input vocabulary. Consider nested `input` catalog group. |
| `HowlTerm` | Linux host, FFI, tests/benchmarks | Public runtime type | Keep as root export, but move implementation body to an owner file such as `terminal.zig`. |
| `HowlTerm.SurfaceHandle` | Linux host | Public host contract | Keep initially; later consider root `surface`/`runtime` grouping with host updates. |
| `HowlTerm.LinkUnderlineStyle` | Linux host and FFI | Public host/ABI contract | Keep initially. |
| `HowlTerm.LifecycleState` | Linux host | Public host contract | Keep initially. |
| `HowlTerm.FramePixels` | Linux host and FFI | Public host/ABI contract | Keep initially. |
| `HowlTerm.SurfaceMetrics` | Linux host | Public host contract | Keep initially. |
| `HowlTerm.SurfaceState` | Linux host | Public host contract | Keep initially. |
| `HowlTerm.ScrollState` | Linux host | Public host contract | Keep initially. |

`HowlTerm` public methods currently exported by the runtime owner body:

| Method group | Methods | Current consumers | Class | Decision |
| --- | --- | --- | --- | --- |
| Lifecycle | `init`, `initPty`, `deinit`, `start`, `stop`, `isAlive`, `hasOutputProof` | Linux host, FFI, tests | Public runtime contract | Keep methods on the runtime type, but move the type body out of root. |
| Frame queue | `prepareNextFrame`, `renderReadyFrame`, `awaitRenderWake`, `awaitRenderWakeTimeout`, `hasQueuedRenderWork`, `needsFrame`, `needsPrepare`, `wakeSnapshotWaiters`, `setRuntimeBackpressure` | Linux host, FFI | Public/host runtime contract | Keep initially; owner file after root split. |
| Metrics/state | `takePrepareMetrics`, `takeSurfaceMetrics`, `surfaceState`, `scrollState`, `surfaceHandle`, `lastRenderMetrics`, `inputBytesApplied`, `snapshotEventSeq`, `renderedSnapshotSeq`, `currentScrollbackCount`, `currentScrollbackOffset`, `viewportRows`, `copyCurrentTitle` | Linux host, FFI | Public/ABI contract | Keep initially; consider grouping aliases in root catalog later. |
| Input | `publishInputBytes`, `input`, `publishInputKey`, `setInputFocus`, `publishPaste`, `publishMouseEvent`, `publishControlSignal` | Linux host, FFI | Public input contract | Keep initially; no VT vocabulary duplication. |
| Clipboard/link/selection | `drainPendingClipboardSet`, `copyHyperlinkUriAtPixel`, `setHoveredLinkAtPixel`, `selectionInProgress`, `beginSelection`, `updateSelection`, `finishSelection`, `clearSelection` | Linux host, FFI | Public host contract | Keep initially. |
| Font/config | `setPrimaryFontPath`, `setFontSizePx`, `setFallbackFontPaths`, `clearFallbackFontPaths`, `addFallbackFontPath` | Linux host, FFI | Public host/ABI contract | Keep initially. |
| Render internals exposed today | `syncSnapshotFromCore`, `renderLatestSnapshot`, `prepareLatestSnapshot`, `prepareSnapshotForRequest`, `prepareSnapshotForRequestIfDirty`, `submitPreparedSnapshot`, `renderFrame`, `renderFrameSized`, `syncFrameGeometry`, `awaitSnapshotEvent`, `snapshotToken`, `lastSubmittedFrame`, `shiftSelectionForHistoryGrowth` | FFI, tests, internal modules, some Linux host geometry paths | Mixed public/internal leak | Move with owner file first; later reduce visibility or group as explicit frame/render namespace after consumers are audited. |
| Render diagnostics | `renderMissingGlyphs`, `renderFallbackHits`, `renderFallbackMisses`, `renderShapedClusters`, `renderResolveStage`, `renderedTextContains`, `visibleTextContains`, `isAlternateScreen`, `setScrollbackOffset`, `followLiveBottom` | Linux host, FFI | Public diagnostics/viewport contract | Keep initially. |

Shape decision: `howl_term.zig` is the primary mismatch. Sprint 2 must move the runtime owner body out of this root and turn the root into a catalog. Do not claim the sprint done while this file still contains runtime fields.

### `howl-hosts/howl-linux-host/src/main.zig`

| Export | Current consumers | Class | Decision |
| --- | --- | --- | --- |
| `Options` | No external consumer found; local executable root only | Executable-owner convenience | Keep or privatize after host audit; not a package catalog requirement. |
| `main` | Zig executable entrypoint | Executable owner | Keep. |

Shape decision: this is an executable owner exception, not a package root. Keep import boundaries enforced.

### `howl-hosts/howl-linux-host/src/test_host.zig`

| Export | Current consumers | Class | Decision |
| --- | --- | --- | --- |
| `Config` | Test root aggregation | Test-only catalog | Keep. |
| `Input` | Test root aggregation | Test-only catalog | Keep. |
| `Main` | Test root aggregation | Test-only catalog | Keep. |
| `TerminalWidget` | Test root aggregation | Test-only catalog | Keep. |
| `Window` | Test root aggregation | Test-only catalog | Keep. |

Shape decision: already a thin test catalog. Keep it small and boring.

## Sprint 0: Public Surface Inventory

Purpose: know exactly what each root exports and who consumes it before moving code.

Tasks:

- Inventory every `pub const`, `pub fn`, and public nested namespace in these roots: `howl-vt-core/src/vt_core.zig`, `howl-session/src/howl_session.zig`, `howl-render-core/src/howl_render.zig`, `howl-term/src/howl_term.zig`, `howl-hosts/howl-linux-host/src/main.zig`, `howl-hosts/howl-linux-host/src/test_host.zig`.
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

Current open markers from `tools/check_module_shape.sh` after Sprint 5: none.

Closed markers:

- `howl_term_root_not_catalog`: closed by moving the runtime owner body to `howl-term/src/terminal.zig`.
- `term_root_ref_all_decls_missing`: closed by adding root declaration coverage to the catalog root.
- `render_root_ref_all_decls_missing`: closed by adding root declaration coverage in `howl-render-core/src/howl_render.zig`.
- `session_root_ref_all_decls_missing`: closed by adding root declaration coverage in `howl-session/src/howl_session.zig`.

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

Checkpoint decision: `howl-vt-core/src/vt_core.zig` is already the current reference catalog root. `Input` stays top-level for now because `howl-term` and tests consume `vt_core.Input` directly, and adding a nested alias now would be churn rather than clarity. The root imports the implementation owner `terminal.zig`, re-exports deliberate public domains/types, and references public declarations in its root test.

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

Checkpoint decision: `howl-render-core/src/howl_render.zig` stays a compact catalog exposing `Core`, `Renderer`, and a `geometry` namespace for frame/grid helper functions. Backend internals remain hidden from the root. Root declaration coverage is present.

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

Checkpoint decision: `howl-session/src/howl_session.zig` now groups contracts under `runtime`, `transport`, and `testing`. Top-level aliases remain deliberate stable exports for current downstream consumers. Root declaration coverage is present.

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
