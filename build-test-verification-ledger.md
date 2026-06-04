# Build/Test Verification Ledger

Owner: workspace root.

Purpose:

- Record the current repository state for build, run, test, simulation, stress, benchmark, FFI, and install surfaces.
- Audit that current state against `build-test-architecture-spec.md` without proposing migration work in this document.

Current correction:

- This ledger supersedes earlier root/VT `test:regression` entries. The workspace
  root and VT package no longer expose an active `test:regression` step.
- VT deterministic workload generation is now named `simulate`. The run step
  currently exposes a parser assertion failure during simulation; `simulate:build`
  remains the non-running compile gate.

## Governing Inputs

- `AGENTS.md`
- `loop.txt`
- `reference-index.md`
- `current.txt`
- `build-test-architecture-spec.md`
- `build-test-architecture-blocker-scratchpad.md`
- `build-test-architecture-migration-scratchpad.md`
- `utils/dev_references/zig_maturity/tigerbeetle/build.zig`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`

## Audit Method

- This ledger was derived from the current checked-in package build files and the roots they wire today.
- `build.zig`
- `howl-linux-host/build.zig`
- `howl-vt/build.zig`
- `howl-render/build.zig`
- `howl-pty/build.zig`
- Source roots were read far enough to classify what each public step actually compiles or runs.
- Line references below are proof anchors, not an exhaustive source listing.

## Canonical Contract Reminder

- Product packages are `howl-pty`, `howl-vt`, and `howl-render`.
- The host package is `howl-linux-host` and is a laboratory harness, not a product app.
- Accepted public step families are the ones in `build-test-architecture-spec.md`.
- `runtime-proof` is forbidden by the canonical contract.

## Workspace Root

### Plain `zig build` Today

- `build.zig` explicitly sets the workspace default step to root `check` by constructing canonical root aggregate steps and assigning `b.default_step` when the aggregate name is `check` (`build.zig:84-93`).
- Today plain `zig build` at the workspace root is an orchestration-only aggregate over package `check` steps.
- Today the workspace root installs no artifacts of its own and introduces no root `run` path.

### Ledger

| Entry | Owner | Root file | Install behavior today | Run behavior today | Current classification | Target classification | Proof statement or proof gap |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Plain `zig build` / root `check` | workspace root | `build.zig` aggregate over package `check` steps | No root-owned install behavior | Runs no root-owned executable | Root orchestration aggregate | `check` | Concrete proof: the root depends only on `howl-pty:check`, `howl-vt:check`, `howl-render:check`, and `howl-linux-host:check`, preserving package ownership and ABI seams. |
| `test` | workspace root | Aggregate over package `test` steps | No root-owned install behavior | Runs package-local routine `test` surfaces only | Root orchestration aggregate | `test` | Concrete proof: the root maps directly to `howl-pty:test`, `howl-vt:test`, `howl-render:test`, and `howl-linux-host:test`; simulation, stress, and benchmark surfaces remain explicit root steps. |
| `test:unit` | workspace root | Aggregate over package `test:unit` steps | No root-owned install behavior | Runs package-local unit surfaces only | Root orchestration aggregate | `test:unit` | Concrete proof: the root maps directly to the four package `test:unit` steps and therefore stays owner-local in meaning. |
| `test:abi` | workspace root | Aggregate over product-package `test:abi` steps | No root-owned install behavior | Runs product-package ABI proofs only | Root orchestration aggregate | `test:abi` | Concrete proof: the root maps directly to `howl-pty:test:abi`, `howl-vt:test:abi`, and `howl-render:test:abi`; the host is absent because it does not own a shipped product ABI. |
| `test:integration` | workspace root | Aggregate over host `test:integration` only | No root-owned install behavior | Runs host-owned integration proof only | Root orchestration aggregate | `test:integration` | Concrete proof: the root maps only to `howl-linux-host:test:integration`, which is the package that owns cross-package ABI-seam proof. |
| `simulate` | workspace root | Aggregate over `howl-vt:simulate` only | No root-owned install behavior | Runs one package-local deterministic simulation surface | Root orchestration aggregate | `simulate` | Concrete proof: root aggregates only the VT-owned deterministic simulation run step. Current proof gap: the run exposes a parser assertion failure and must be fixed before treating simulation as green evidence. |
| `stress` | workspace root | Aggregate over host named stress steps | No root-owned install behavior | Runs `howl-linux-host:stress:rain`, `stress:rain:ascii`, `stress:rain:mixed`, and `stress:rain:visual` | Root orchestration aggregate | Aggregate `stress` over canonical named steps | Concrete proof: the root exposes no invented stress behavior; it only aggregates existing canonical named host stress steps. |
| `benchmark` | workspace root | Aggregate over named benchmark steps | No root-owned install behavior | Runs `howl-vt:benchmark:m7_baseline` and `howl-render:benchmark:render` | Root orchestration aggregate | Aggregate `benchmark` over canonical named steps | Concrete proof: the root exposes no invented benchmark behavior; it only aggregates existing canonical named package benchmark steps. |

## `howl-linux-host`

### Plain `zig build` Today

- `howl-linux-host/build.zig` explicitly sets `b.default_step = steps.check` and then makes `check` depend on the compiled host executable only (`howl-linux-host/build.zig:63-79`).
- Today plain `zig build` is a non-running build of the host harness executable.
- Today plain `zig build` does not run tests or stress harnesses.
- Today plain `zig build` does not install the harness; host install behavior is separate and remains dev-only (`howl-linux-host/build.zig:204-210`).

### Ledger

| Entry | Owner | Root file | Install behavior today | Run behavior today | Current classification | Target classification | Proof statement or proof gap |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `check` | `howl-linux-host` | `src/main.zig` via compiled harness dependency | No install wiring of its own | Does not run the harness | Host default audit/build step | `check` | Concrete proof: `check` depends only on the compiled host executable and therefore stays a non-running audit/build surface. |
| Installed harness executable | `howl-linux-host` | `src/main.zig` | `installHarnessArtifact()` installs `howl_term_<optimize>` into the custom `harness/` install dir (`build.zig:204-210`) | No direct run behavior | Dev-only harness artifact | Dev-only `install` artifact | Concrete proof: package comment and spec both place host ownership on harness/runtime work, not shipped product ABI (`build.zig:1-4`; `build-test-architecture-spec.md:46-53`). |
| `run` | `howl-linux-host` | `src/main.zig` | No install wiring of its own | Runs the compiled host executable, forwarding `b.args` if present (`build.zig:225-229`) | Manual host harness execution | `run` | Concrete proof: public step exists and is explicit, which matches the host-harness contract requirement. |
| `stress:rain` | `howl-linux-host` | `../utils/tools/ascii_rain_stress.zig` | No install wiring | Runs `ascii_rain_stress` with forwarded `b.args` only (`build.zig:219-223`) | Stress run surface | `stress:<name>` | Concrete proof: root is a terminal traffic generator with metrics reporting and hostile stream emission (`ascii_rain_stress.zig:48-96`, `157-165`). |
| `stress:rain:ascii` | `howl-linux-host` | `../utils/tools/ascii_rain_stress.zig` | No install wiring | Runs the same `ascii_rain_stress` executable with `--ascii --metrics --flush-every 1` (`build.zig:224-227`) | Stress run surface | `stress:<name>` | Concrete proof: same stress harness root, specialized by CLI args. |
| `stress:rain:mixed` | `howl-linux-host` | `../utils/tools/ascii_rain_stress.zig` | No install wiring | Runs the same `ascii_rain_stress` executable with `--mixed --metrics --flush-every 1` (`build.zig:228-230`) | Stress run surface | `stress:<name>` | Concrete proof: same stress harness root, specialized by CLI args. |
| `stress:rain:visual` | `howl-linux-host` | `../utils/tools/visual_rain_stress.zig` | No install wiring | Runs `visual_rain_stress` with forwarded `b.args`, or `--metrics` by default (`build.zig:232-238`) | Stress run surface | `stress:<name>` | Concrete proof: root is a visibly recognizable rendering stress generator, not a unit test (`visual_rain_stress.zig:52-115`, `199-207`). |
| `test` | `howl-linux-host` | Aggregate over `test:unit` and `test:integration` | No install wiring of its own | Runs host unit and integration surfaces | Aggregate test step | `test` | Concrete proof: the aggregate now covers the host-owned accepted test families without routing stress surfaces through test semantics. |
| `test:unit` | `howl-linux-host` | Aggregate over `src/test/test_entry.zig`, `src/terminal/render/retained.zig`, `src/display/renderer/render_surface.zig`, and `src/test_root.zig` | No install wiring of its own | Runs four unit-class test binaries | Host-local unit aggregate | `test:unit` | Concrete proof: `howl-linux-host/build.zig:265-312` wires four separate test binaries into the package `test:unit` step. |
| `test:unit:build` | `howl-linux-host` | Aggregate over `src/test/test_entry.zig`, `src/terminal/render/retained.zig`, `src/display/renderer/render_surface.zig`, and `src/test_root.zig` | No install wiring of its own | Does not run them | Build-only mirror | `test:unit:build` | Concrete proof: `howl-linux-host/build.zig:305-308` stages four compiled unit-class artifacts and does not install them. |
| `test:integration` | `howl-linux-host` | `src/test/integration_entry.zig` through `build_support/host_tests.zig` | No install wiring of its own | Runs `test-integration` only (`build.zig:310-333`) | Host integration aggregate | `test:integration` | Concrete proof: this package-local surface is the host-owned cross-package ABI seam proof routed through the harness test module. |
| `test:integration:build` | `howl-linux-host` | `src/test/integration_entry.zig` through `build_support/host_tests.zig` | No install wiring of its own | Does not run it | Build-only mirror | `test:integration:build` | Concrete proof: the step depends only on the compiled integration test artifact and does not install it. |
| Host test root `test-unit` | `howl-linux-host` | `src/test/test_entry.zig` | Staged only when `test:unit:build` is invoked | Run as one Zig test binary by `test:unit` | Host compile-smoke test surface | `test:unit` if retained as owner-local smoke | Concrete proof: `src/test/test_entry.zig:1-5` only `refAllDecls` the imported `cli_args`, `config_env`, and `tab_bar` modules. |
| Host test root `test-retained-render` | `howl-linux-host` | `src/terminal/render/retained.zig` | Staged only when `test:unit:build` is invoked | Run as one Zig test binary by `test:unit` | Host retained-render unit surface | `test:unit` | Concrete proof: `howl-linux-host/build.zig:275-285` wires `src/terminal/render/retained.zig` directly as a separate unit-class test root. |
| Host test root `test-render-surface` | `howl-linux-host` | `src/display/renderer/render_surface.zig` | Staged only when `test:unit:build` is invoked | Run as one Zig test binary by `test:unit` | Host render-surface unit surface | `test:unit` | Concrete proof: `howl-linux-host/build.zig:286-294` wires `src/display/renderer/render_surface.zig` directly as a separate unit-class test root. |
| Host test root `test-terminal-context` | `howl-linux-host` | `src/test_root.zig` | Staged only when `test:unit:build` is invoked | Run as one Zig test binary by `test:unit` | Host context/unit aggregate | `test:unit` | Concrete proof: `src/test_root.zig:1-13` imports `test/host.zig` and exposes host-owned test modules through one package-local root. |

### Package Mismatches Recorded

- `test:unit` is already a multi-root class aggregate, so any governing law requiring one module-wide test entrypoint is false for current source.

## `howl-vt`

### Plain `zig build` Today

- `howl-vt/build.zig` does not override `b.default_step`, so plain `zig build` is the package install step.
- Today plain `zig build` installs the dynamic library artifact `howl_vt` and the public header `include/howl_vt.h` (`howl-vt/build.zig:60-68`).
- Today plain `zig build` does not run tests, simulations, or the benchmark.

### Ledger

| Entry | Owner | Root file | Install behavior today | Run behavior today | Current classification | Target classification | Proof statement or proof gap |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Plain `zig build` / package install | `howl-vt` | `src/libhowl_vt.zig` plus `include/howl_vt.h` | Installs `libhowl_vt` and `include/howl_vt.h` (`build.zig:60-68`) | Does not run anything | Product install surface | `install` | Concrete proof: package ships exported C symbols from `src/libhowl_vt.zig` and a public header (`src/libhowl_vt.zig:3-37`; `include/howl_vt.h:1-444`). |
| Shipped ABI library artifact `howl_vt` | `howl-vt` | `src/libhowl_vt.zig` | Installed by plain `zig build`; also installed again by `ffi:build` (`build.zig:60-68`) | No run behavior | Product artifact | Product `install` artifact | Concrete proof: root exports the VT C ABI entrypoints such as terminal lifecycle, feed, surface copy, selection, graphics, runtime progress, and input encoders (`src/libhowl_vt.zig:3-37`). |
| Shipped ABI header `include/howl_vt.h` | `howl-vt` | `include/howl_vt.h` | Installed by plain `zig build` through `b.installFile()` (`build.zig:68`) | No run behavior | Product artifact | Product `install` artifact | Concrete proof: header declares the public VT handle, surface, selection, graphics, and input ABI. |
| `ffi:build` | `howl-vt` | `src/libhowl_vt.zig` | Installs the same dynamic library artifact via `addInstallArtifact()` (`build.zig:65-67`) | Does not run anything | FFI build step with install behavior | No accepted canonical public step family | Mismatch: current step name says build, but behavior is install. The canonical contract does not accept `ffi:build` as a public step family. |
| `test` | `howl-vt` | Aggregate over `test:abi` and `test:unit` | No install wiring of its own | Runs the VT ABI and unit suites only | Routine aggregate test step | `test` | Concrete proof: the public aggregate avoids simulation execution; snapshot behavior lives in unit tests. |
| `test:unit` | `howl-vt` | `src/howl_vt.zig` | No install wiring of its own | Runs the `test-unit` Zig test binary (`build.zig:34-50`) | Large owner-local correctness suite under a unit label | `test:unit` | Concrete proof: `src/howl_vt.zig` now curates owner-true sibling test files rooted under `src/` and no longer depends on generic parser/action/screen bucket paths or the ABI root. |
| `test:unit:build` | `howl-vt` | `src/howl_vt.zig` | Installs the `test-unit` test binary via `addInstallArtifact()` (`build.zig:47-49`) | Does not run it | Build-only mirror in name, install step in behavior | `test:unit:build` | Mismatch: current step is named as build-only, but today it installs the test artifact. |
| Unit test root `test-unit` | `howl-vt` | `src/howl_vt.zig` | Installed only when `test:unit:build` is invoked | Run by `test:unit` | Curated owner-local unit root | `test:unit` | Concrete proof: root imports parser, screen, selection, terminal, and owner-true sibling test files such as `screen_test.zig`, `terminal_modes_test.zig`, `terminal_osc_test.zig`, and `terminal_surface_test.zig`, while ABI tests remain only under `src/test/abi.zig`. |
| `simulate` | `howl-vt` | `src/simulation/main.zig` | No install wiring of its own | Runs `howl_vt_simulate` with forwarded `b.args` | Deterministic simulation/replay surface | `simulate` | Proof gap: current run exposes a parser assertion failure. The surface is correctly named but not yet green evidence. |
| `simulate:build` | `howl-vt` | `src/simulation/main.zig` | No install wiring of its own | Does not run it | Build-only mirror | `simulate:build` | Concrete proof: compiles the deterministic simulation executable without running the workload. |
| Simulation executable `howl_vt_simulate` | `howl-vt` | `src/simulation/main.zig` | No install wiring | Run by `simulate` | Simulation executable root | `simulate` / `simulate:build` pair | Concrete proof: root exposes CLI-selected `smoke`, `protocol`, and `scrollback` deterministic workload modes. |
| Shared scrollback simulation helper | `howl-vt` | `src/simulation/scrollback.zig` | Never installed directly | Not runnable directly; imported by `simulate` | VT-owned deterministic workload helper | Shared helper for `simulate` only | Concrete proof: file provides seeded scrollback churn helpers for deterministic simulation. |
| `benchmark:m7_baseline` | `howl-vt` | `src/terminal_benchmark_main.zig` | No install wiring | Runs the benchmark executable with forwarded `b.args` (`build.zig:145-159`) | Benchmark run surface | `benchmark:<name>` | Concrete proof: public step now uses canonical benchmark naming and runs a measurement-only VT-owned surface. |
| `benchmark:m7_baseline:build` | `howl-vt` | `src/terminal_benchmark_main.zig` | No install wiring | Does not run it | Benchmark build surface | `benchmark:<name>:build` | Concrete proof: public step now compiles the VT benchmark executable without mixing benchmark work into test/proof language. |
| Benchmark executable `m7_baseline` | `howl-vt` | `src/terminal_benchmark_main.zig` delegating to `src/test/terminal_benchmark.zig` | No install wiring | Run by `benchmark:m7_baseline` | Benchmark executable root | `benchmark:<name>` with matching `:build` mirror | Concrete proof: root delegates to benchmark main, which measures throughput and allocation behavior over replay and synthetic fixtures (`terminal_benchmark_main.zig:1-6`; `test/terminal_benchmark.zig:1-712`). |

### Package Mismatches Recorded

- `test:unit` is broader than its label because the root imports FFI coverage and regression-flavored modules.

## `howl-render`

### Plain `zig build` Today

- `howl-render/build.zig` does not override `b.default_step`, so plain `zig build` is the package install step.
- Today plain `zig build` installs the dynamic library artifact `howl_render` and the public header `include/howl_render.h` (`howl-render/build.zig:154-162`).
- Today plain `zig build` does not run tests or the benchmark.

### Ledger

| Entry | Owner | Root file | Install behavior today | Run behavior today | Current classification | Target classification | Proof statement or proof gap |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Plain `zig build` / package install | `howl-render` | `src/libhowl_render.zig` plus `include/howl_render.h` | Installs `libhowl_render` and `include/howl_render.h` (`build.zig:154-162`) | Does not run anything | Product install surface | `install` | Concrete proof: package ships exported C symbols from `src/libhowl_render.zig` and a public render header. |
| Shipped ABI library artifact `howl_render` | `howl-render` | `src/libhowl_render.zig` | Installed by plain `zig build`; also installed again by `ffi:build` (`build.zig:154-161`) | No run behavior | Product artifact | Product `install` artifact | Concrete proof: root exports surface-text, prepared-surface, publish/prepare/submit/retire, metrics, and handle entrypoints (`src/libhowl_render.zig:4-35`). |
| Shipped ABI header `include/howl_render.h` | `howl-render` | `include/howl_render.h` | Installed by plain `zig build` through `b.installFile()` (`build.zig:162`) | No run behavior | Product artifact | Product `install` artifact | Concrete proof: header declares the render surface, prepared surface, geometry, damage, draw, and submit ABI. |
| `ffi:build` | `howl-render` | `src/libhowl_render.zig` | Installs the same dynamic library artifact via `addInstallArtifact()` (`build.zig:159-161`) | Does not run anything | FFI build step with install behavior | No accepted canonical public step family | Mismatch: current step name says build, but behavior is install. The canonical contract does not accept `ffi:build` as a public step family. |
| `test` | `howl-render` | Aggregate over `test:unit` and `test:abi` | No install wiring of its own | Runs distinct render unit and ABI binaries | Aggregate test step | `test` | Concrete proof: `howl-render/build.zig:85-99` wires separate unit and ABI test artifacts into the package `test` step. |
| `test:unit` | `howl-render` | `src/test_unit.zig` | No install wiring of its own | Runs `test-unit` | Owner-local unit root | `test:unit` | Concrete proof: `howl-render/build.zig:37-59` wires `src/test_unit.zig` as the dedicated unit-class test root. |
| `test:unit:build` | `howl-render` | `src/test_unit.zig` | No install wiring of its own | Does not run it | Build-only mirror | `test:unit:build` | Concrete proof: `howl-render/build.zig:92-93` depends only on the compiled unit test artifact and run step. |
| Unit test root `test-unit` | `howl-render` | `src/test_unit.zig` plus `src/test/unit/root.zig` | No install wiring of its own | Run by `test:unit` | Owner-local unit root | `test:unit` | Concrete proof: `src/test_unit.zig:1-3` imports only `src/test/unit/root.zig`, which reaches the render-surface realizer, emitter, and geometry tests. |
| `test:abi` | `howl-render` | `src/test_abi.zig` | No install wiring of its own | Runs `test-abi` | Shipped ABI contract root | `test:abi` | Concrete proof: `howl-render/build.zig:61-83` wires `src/test_abi.zig` as the dedicated ABI-class test root. |
| `test:abi:build` | `howl-render` | `src/test_abi.zig` | No install wiring of its own | Does not run it | Build-only mirror | `test:abi:build` | Concrete proof: `howl-render/build.zig:94-95` depends only on the compiled ABI test artifact and run step. |
| ABI test root `test-abi` | `howl-render` | `src/test_abi.zig` plus `src/test/ffi.zig` | No install wiring of its own | Run by `test:abi` | Shipped ABI root | `test:abi` | Concrete proof: `src/test_abi.zig:1-6` ref-all-decls `libhowl_render.zig` and imports `src/test/ffi.zig`, which proves exported render FFI contracts and layout/status facts. |
| `benchmark:render` | `howl-render` | `src/benchmark_main.zig` delegating to `src/test/benchmark.zig` | No install wiring of its own | Runs `render_benchmark` with forwarded `b.args` | Benchmark run surface | `benchmark:<name>` | Concrete proof: `howl-render/build.zig:123-149` now wires a dedicated benchmark root separate from proof roots. |
| `benchmark:render:build` | `howl-render` | `src/benchmark_main.zig` | No install wiring | Does not run it | Benchmark build surface | `benchmark:<name>:build` | Concrete proof: the benchmark build step compiles only the dedicated benchmark executable root. |
| Benchmark executable `render_benchmark` | `howl-render` | `src/benchmark_main.zig` delegating to `src/test/benchmark.zig` | No install wiring | Run by `benchmark:render` | Benchmark executable root | `benchmark:<name>` with matching `:build` mirror | Concrete proof: `src/benchmark_main.zig:1` exports only benchmark `main`, and `src/test/benchmark.zig` remains the measurement workload owner. |

### Package Mismatches Recorded


## `howl-pty`

### Plain `zig build` Today

- `howl-pty/build.zig` does not override `b.default_step`, so plain `zig build` is the package install step.
- Today plain `zig build` installs the dynamic library artifact `howl_pty` and the public header `include/howl_pty.h` (`howl-pty/build.zig:63-71`).
- Today plain `zig build` does not run tests.

### Ledger

| Entry | Owner | Root file | Install behavior today | Run behavior today | Current classification | Target classification | Proof statement or proof gap |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Plain `zig build` / package install | `howl-pty` | `src/libhowl_pty.zig` plus `include/howl_pty.h` | Installs `libhowl_pty` and `include/howl_pty.h` (`build.zig:63-71`) | Does not run anything | Product install surface | `install` | Concrete proof: package ships exported C symbols from `src/libhowl_pty.zig` and a public PTY header. |
| Shipped ABI library artifact `howl_pty` | `howl-pty` | `src/libhowl_pty.zig` | Installed by plain `zig build`; also installed again by `ffi:build` (`build.zig:63-70`) | No run behavior | Product artifact | Product `install` artifact | Concrete proof: root exports PTY session lifecycle, snapshot, resize, signal, input, pump, wait, read, and transport-limit entrypoints (`src/libhowl_pty.zig:3-19`). |
| Shipped ABI header `include/howl_pty.h` | `howl-pty` | `include/howl_pty.h` | Installed by plain `zig build` through `b.installFile()` (`build.zig:71`) | No run behavior | Product artifact | Product `install` artifact | Concrete proof: header declares the public PTY session handle, snapshot, outbound pump, read result, and transport-limit ABI. |
| `ffi:build` | `howl-pty` | `src/libhowl_pty.zig` | Installs the same dynamic library artifact via `addInstallArtifact()` (`build.zig:68-70`) | Does not run anything | FFI build step with install behavior | No accepted canonical public step family | Mismatch: current step name says build, but behavior is install. The canonical contract does not accept `ffi:build` as a public step family. |
| `test` | `howl-pty` | Aggregate over `test:unit`, `test:abi`, and `test:integration` (`build.zig:71-87`) | No install wiring of its own | Runs PTY unit, ABI, and integration surfaces | Aggregate test step | `test` | Concrete proof: `howl-pty/build.zig:85-87` wires all three child classes into the package `test` step. |
| `test:unit` | `howl-pty` | `src/libhowl_pty.zig` | No install wiring of its own | Runs the `test-unit` Zig test binary (`build.zig:18-27`, `83-84`) | Owner-local correctness suite | `test:unit` | Concrete proof: `src/libhowl_pty.zig:21-24` imports `test/session.zig` and `test/pty.zig` through the unit-class root. |
| `test:unit:build` | `howl-pty` | `src/libhowl_pty.zig` | No install wiring of its own | Does not run it | Build-only mirror | `test:unit:build` | Concrete proof: `howl-pty/build.zig:83` depends only on the compiled unit test artifact. |
| Unit test root `test-unit` | `howl-pty` | `src/libhowl_pty.zig` | Built only when `test:unit:build` is invoked | Run by `test:unit` | Owner-local unit root | `test:unit` | Concrete proof: tests exercise PTY-owned transport and session behavior directly through the package-local root. |
| `test:integration` | `howl-pty` | `src/libhowl_pty_integration.zig` | No install wiring of its own | Runs the `test-integration` Zig test binary (`build.zig:54-69`, `81-82`) | PTY integration surface | `test:integration` pending package-ownership review | Concrete proof: current build exposes an explicit PTY integration root distinct from unit and ABI. |
| `test:integration:build` | `howl-pty` | `src/libhowl_pty_integration.zig` | No install wiring of its own | Does not run it | Build-only mirror | `test:integration:build` | Concrete proof: `howl-pty/build.zig:81` depends only on the compiled integration test artifact. |

### Package Mismatches Recorded

- PTY currently owns an explicit `test:integration` class, so any law or ledger text limiting integration to hosts is false for current source.

## Cross-Package Current-State Findings

### Current Plain `zig build` Semantics By Package

| Package | Plain `zig build` today | Contract alignment |
| --- | --- | --- |
| `howl-linux-host` | Runs `check`, which builds the default host harness executable without running it | Aligned with host-package default semantics |
| `howl-vt` | Installs shipped VT dynamic library and header | Aligned with product-package default semantics |
| `howl-render` | Installs shipped render dynamic library and header | Aligned with product-package default semantics |
| `howl-pty` | Installs shipped PTY dynamic library and header | Aligned with product-package default semantics |

### Repeated Mismatches Against The Canonical Contract

- `howl-render` still exposes non-canonical `test:render` and `test:render:build` public step names.
- `howl-vt` keeps a broad unit root by design, but the imported proofs now sit in owner-true sibling files instead of generic bucket paths.

### Proof Gaps Worth Preserving In Review

- Several current roots are compile-smoke surfaces rather than explicit behavior proofs, especially in `howl-linux-host`.
- Several aggregate steps have narrower or broader meaning than their names imply.
- Canonical step presence is improved, but proof quality still varies by package root and should keep being audited at the package owner boundary.

## Ledger Boundary

- This document is an inventory and audit baseline only.
- It does not rename steps.
- It does not prescribe implementation changes.
- It does not choose migration order beyond recording target classifications from the canonical contract.
