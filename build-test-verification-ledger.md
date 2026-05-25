# Build/Test Verification Ledger

Owner: workspace root.

Purpose:

- Record the current repository state for build, run, test, fuzz, stress, benchmark, FFI, and install surfaces.
- Audit that current state against `build-test-architecture-spec.md` without proposing migration work in this document.

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

## `howl-linux-host`

### Plain `zig build` Today

- `howl-linux-host/build.zig` explicitly sets `b.default_step = steps.check` and then makes `check` depend on `b.getInstallStep()` (`howl-linux-host/build.zig:58-59`).
- Today plain `zig build` is a non-running build/install of the host harness executable.
- Today plain `zig build` does not run tests or stress harnesses.
- Today plain `zig build` still installs a dev-only harness artifact because `buildHostExe()` calls `installExe()` and `installExe()` adds the executable to the package install step (`howl-linux-host/build.zig:128-137`, `191-197`).

### Ledger

| Entry | Owner | Root file | Install behavior today | Run behavior today | Current classification | Target classification | Proof statement or proof gap |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `check` | `howl-linux-host` | `src/main.zig` via installed harness dependency | Indirectly installs the host executable because `check` depends on the package install step (`build.zig:58-59`) | Does not run the harness | Host default audit/build step with install side effect | `check` | Matches host default non-running posture, but its meaning is coupled to install side effects instead of being purely an audit/build surface. |
| Installed harness executable | `howl-linux-host` | `src/main.zig` | `buildHostExe()` installs `howl_term_<optimize>` into `bin/` through `installExe()` (`build.zig:128-137`, `191-197`) | No direct run behavior; consumed by `run` and by plain `zig build` through `check` | Dev-only harness artifact | Dev-only `install` artifact | Concrete proof: package comment and spec both place host ownership on harness/runtime work, not shipped product ABI (`build.zig:1-4`; `build-test-architecture-spec.md:46-53`). |
| `run` | `howl-linux-host` | `src/main.zig` | Depends on package install step before running (`build.zig:212-217`) | Runs the installed host executable, forwarding `b.args` if present | Manual host harness execution | `run` | Concrete proof: public step exists and is explicit, which matches the host-harness contract requirement. |
| `stress:rain` | `howl-linux-host` | `src/stress/ascii_rain_stress.zig` | No install wiring | Runs `ascii_rain_stress` with forwarded `b.args` only (`build.zig:219-223`) | Stress run surface | `stress:<name>` | Concrete proof: root is a terminal traffic generator with metrics reporting and hostile stream emission (`ascii_rain_stress.zig:48-96`, `157-165`). |
| `stress:rain:ascii` | `howl-linux-host` | `src/stress/ascii_rain_stress.zig` | No install wiring | Runs the same `ascii_rain_stress` executable with `--ascii --metrics --flush-every 1` (`build.zig:224-227`) | Stress run surface | `stress:<name>` | Concrete proof: same stress harness root, specialized by CLI args. |
| `stress:rain:mixed` | `howl-linux-host` | `src/stress/ascii_rain_stress.zig` | No install wiring | Runs the same `ascii_rain_stress` executable with `--mixed --metrics --flush-every 1` (`build.zig:228-230`) | Stress run surface | `stress:<name>` | Concrete proof: same stress harness root, specialized by CLI args. |
| `stress:rain:visual` | `howl-linux-host` | `src/stress/visual_rain_stress.zig` | No install wiring | Runs `visual_rain_stress` with forwarded `b.args`, or `--metrics` by default (`build.zig:232-238`) | Stress run surface | `stress:<name>` | Concrete proof: root is a visibly recognizable rendering stress generator, not a unit test (`visual_rain_stress.zig:52-115`, `199-207`). |
| `test` | `howl-linux-host` | Aggregate over `test:unit` only | No install wiring of its own | Runs whatever `test:unit` runs | Aggregate test step | `test` | Proof gap: the aggregate exists, but it still aggregates only `test:unit`; there is no separate host `test:integration` yet. |
| `test:unit` | `howl-linux-host` | Aggregate over one host test binary | No install wiring of its own | Runs `test-unit` only | Host-local unit aggregate | `test:unit` | Concrete proof: the step now contains only the host-owned smoke root and no longer routes stress-root suites through unit semantics. |
| `test:unit:build` | `howl-linux-host` | Aggregate over the same host test binary | Installs one test binary into a custom `debug/` destination | Does not run it | Build-only mirror in name, install step in behavior | `test:unit:build` | Mismatch: current step is named as build-only, but today it still installs a test artifact. |
| Host test root `test-unit` | `howl-linux-host` | `src/test/test_entry.zig` importing `src/test_root.zig` through `build_support/host_tests.zig` | Installed only when `test:unit:build` is invoked | Run as a Zig test binary by `test:unit` | Host compile-smoke test surface | `test:unit` if retained as owner-local smoke | Proof gap: `src/test/test_entry.zig` imports `Config`, `Input`, `Main`, `TerminalPanel`, `Thread`, and `Window`, so the root still states compile/load coverage more than an explicit behavior claim. |

### Package Mismatches Recorded

- No public `test:integration` surface exists even though the host package owns cross-package integration proof in the canonical contract.
- `test:unit:build` installs artifacts instead of being build-only in behavior.

## `howl-vt`

### Plain `zig build` Today

- `howl-vt/build.zig` does not override `b.default_step`, so plain `zig build` is the package install step.
- Today plain `zig build` installs the dynamic library artifact `howl_vt` and the public header `include/howl_vt.h` (`howl-vt/build.zig:60-68`).
- Today plain `zig build` does not run tests, fuzzers, or the benchmark.

### Ledger

| Entry | Owner | Root file | Install behavior today | Run behavior today | Current classification | Target classification | Proof statement or proof gap |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Plain `zig build` / package install | `howl-vt` | `src/libhowl_vt.zig` plus `include/howl_vt.h` | Installs `libhowl_vt` and `include/howl_vt.h` (`build.zig:60-68`) | Does not run anything | Product install surface | `install` | Concrete proof: package ships exported C symbols from `src/libhowl_vt.zig` and a public header (`src/libhowl_vt.zig:3-37`; `include/howl_vt.h:1-444`). |
| Shipped ABI library artifact `howl_vt` | `howl-vt` | `src/libhowl_vt.zig` | Installed by plain `zig build`; also installed again by `ffi:build` (`build.zig:60-68`) | No run behavior | Product artifact | Product `install` artifact | Concrete proof: root exports the VT C ABI entrypoints such as terminal lifecycle, feed, surface copy, selection, graphics, runtime progress, and input encoders (`src/libhowl_vt.zig:3-37`). |
| Shipped ABI header `include/howl_vt.h` | `howl-vt` | `include/howl_vt.h` | Installed by plain `zig build` through `b.installFile()` (`build.zig:68`) | No run behavior | Product artifact | Product `install` artifact | Concrete proof: header declares the public VT handle, surface, selection, graphics, and input ABI. |
| `ffi:build` | `howl-vt` | `src/libhowl_vt.zig` | Installs the same dynamic library artifact via `addInstallArtifact()` (`build.zig:65-67`) | Does not run anything | FFI build step with install behavior | No accepted canonical public step family | Mismatch: current step name says build, but behavior is install. The canonical contract does not accept `ffi:build` as a public step family. |
| `test` | `howl-vt` | Aggregate over `test:unit` only (`build.zig:45-50`) | No install wiring of its own | Runs whatever `test:unit` runs | Aggregate test step | `test` | Proof gap: `test` does not aggregate the regression suite today. |
| `test:unit` | `howl-vt` | `src/howl_vt.zig` | No install wiring of its own | Runs the `test-unit` Zig test binary (`build.zig:34-50`) | Large owner-local correctness suite under a unit label | Split target is `test:unit`, plus any ABI-specific assertions should live under `test:abi`, plus regression cases should live under `test:regression` | Mismatch: `src/howl_vt.zig` imports `ffi` and `snapshot_regression` directly (`src/howl_vt.zig:16-35`), so the current unit step mixes owner-local tests with FFI/ABI-flavored and regression-flavored coverage. |
| `test:unit:build` | `howl-vt` | `src/howl_vt.zig` | Installs the `test-unit` test binary via `addInstallArtifact()` (`build.zig:47-49`) | Does not run it | Build-only mirror in name, install step in behavior | `test:unit:build` | Mismatch: current step is named as build-only, but today it installs the test artifact. |
| Unit test root `test-unit` | `howl-vt` | `src/howl_vt.zig` | Installed only when `test:unit:build` is invoked | Run by `test:unit` | Mixed owner-local test root | Primary target is `test:unit`; some imported coverage wants `test:abi` and `test:regression` classification | Concrete proof: root imports parser, screen, selection, terminal, and multiple test modules, including `snapshot_regression` and `terminal_end_to_end`; it also imports `ffi` (`src/howl_vt.zig:1-35`). |
| `test:regression` | `howl-vt` | `src/test/scrollback_regression.zig` | No install wiring of its own | Runs the `test-regression` Zig test binary (`build.zig:70-91`) | Regression test surface | `test:regression` | Concrete proof: root explicitly states deterministic seeded churn, high-churn invariants, and canonical logical content preservation as the test claim (`scrollback_regression.zig:4-31`). |
| `test:regression:build` | `howl-vt` | `src/test/scrollback_regression.zig` | Installs the regression test binary via `addInstallArtifact()` (`build.zig:88-90`) | Does not run it | Build-only mirror in name, install step in behavior | `test:regression:build` | Mismatch: current step is named as build-only, but today it installs the test artifact. |
| Regression test root `test-regression` | `howl-vt` | `src/test/scrollback_regression.zig` | Installed only when `test:regression:build` is invoked | Run by `test:regression` | Regression | `test:regression` | Concrete proof: root depends on `src/fuzz/scrollback.zig` helpers to prove deterministic replay and preservation invariants, which fits expensive correctness coverage better than unit. |
| `fuzz` | `howl-vt` | `src/fuzz/fuzz_tests.zig` | No install wiring of its own | Runs `howl_vt_fuzz` with forwarded `b.args` (`build.zig:93-110`) | Fuzz surface | `fuzz` | Concrete proof: root dispatches `smoke`, `protocol`, and `scrollback` fuzz modes and drives generated/scenario inputs (`fuzz_tests.zig:24-94`). |
| `fuzz:build` | `howl-vt` | `src/fuzz/fuzz_tests.zig` | Installs the `howl_vt_fuzz` executable via `addInstallArtifact()` (`build.zig:105-107`) | Does not run it | Build-only mirror in name, install step in behavior | `fuzz:build` | Mismatch: current step is named as build-only, but today it installs the fuzz executable. |
| Fuzz executable `howl_vt_fuzz` | `howl-vt` | `src/fuzz/fuzz_tests.zig` | Installed only when `fuzz:build` is invoked | Run by `fuzz` | Fuzz executable root | `fuzz` / `fuzz:build` pair | Concrete proof: root imports `protocol.zig` and `scrollback.zig` fuzz helpers and exposes CLI fuzzer selection. |
| `terminal-benchmark` | `howl-vt` | `src/terminal_benchmark_main.zig` | No install wiring | Runs the benchmark executable with forwarded `b.args` (`build.zig:112-124`) | Benchmark run surface | `benchmark:<name>` | Mismatch: current public name is outside the canonical benchmark naming family, and there is no matching build-only mirror. |
| Benchmark executable `m7_baseline` | `howl-vt` | `src/terminal_benchmark_main.zig` delegating to `src/test/terminal_benchmark.zig` | No install wiring | Run by `terminal-benchmark` | Benchmark executable root | `benchmark:<name>` with matching `:build` mirror | Concrete proof: root delegates to benchmark main, which measures throughput and allocation behavior over replay and synthetic fixtures (`terminal_benchmark_main.zig:1-6`; `test/terminal_benchmark.zig:1-712`). |

### Package Mismatches Recorded

- No public `test:abi` surface exists even though `howl-vt` ships a C ABI and owns ABI proof in the canonical contract.
- `ffi:build` is a non-canonical public step and installs instead of being build-only.
- `test:unit:build`, `test:regression:build`, and `fuzz:build` all install artifacts instead of being build-only in behavior.
- `test` does not aggregate `test:regression` today.
- `test:unit` is broader than its label because the root imports FFI coverage and regression-flavored modules.
- `terminal-benchmark` is a benchmark surface outside the canonical `benchmark:<name>` family and has no `:build` mirror.

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
| `test` | `howl-render` | Aggregate over `test:render`, `test:runtime-proof`, and `test:unit` (`build.zig:126-141`) | No install wiring of its own | Runs all three child test steps | Aggregate test step | `test` | Mismatch: aggregate includes forbidden `runtime-proof` naming and two overlapping owner-local suites. |
| `test:render` | `howl-render` | `src/howl_render.zig` | No install wiring of its own | Runs `test-render` (`build.zig:127-139`) | Repo-local render correctness suite | `test:unit` | Mismatch: current public name is not in the canonical step taxonomy. |
| `test:render:build` | `howl-render` | `src/howl_render.zig` | Installs the `test-render` test binary (`build.zig:128-134`) | Does not run it | Build-only mirror in name, install step in behavior | Closest target is `test:unit:build` | Mismatch: current step name is non-canonical and current behavior installs. |
| Render test root `test-render` | `howl-render` | `src/howl_render.zig` | Installed only when `test:render:build` is invoked | Run by `test:render` | Owner-local correctness suite | `test:unit` | Concrete proof: root imports geometry, viewport, input, pipeline, queue, surface, surface buffer, surface text, contract, text pipeline, and text modules (`src/howl_render.zig:1-25`). |
| `test:runtime-proof` | `howl-render` | `src/non_prod.zig` with `entry = .runtime_proof` (`build.zig:102-141`) | No install wiring of its own | Runs `test-runtime-proof` | Forbidden public verification category | No accepted canonical target classification | Mismatch: `runtime-proof` is explicitly forbidden by the canonical contract. |
| `test:runtime-proof:build` | `howl-render` | `src/non_prod.zig` with `entry = .runtime_proof` | Installs the `test-runtime-proof` test binary (`build.zig:129-136`) | Does not run it | Forbidden public verification category with build-only name and install behavior | No accepted canonical target classification | Mismatch: forbidden category and install-vs-build naming mismatch both apply. |
| Runtime-proof test root `test-runtime-proof` | `howl-render` | `src/non_prod.zig` | Installed only when `test:runtime-proof:build` is invoked | Run by `test:runtime-proof` | Duplicate owner-local suite under forbidden name | No accepted canonical target classification | Concrete proof: `src/non_prod.zig` runs the same imported unit suite for both `.unit` and `.runtime_proof` entries (`src/non_prod.zig:6-17`). This is not a distinct proof class. |
| `test:unit` | `howl-render` | `src/non_prod.zig` with `entry = .unit` (`build.zig:44-57`, `126-141`) | No install wiring of its own | Runs `test-unit` | Owner-local correctness suite | `test:unit` | Proof gap: root includes `std.testing.refAllDecls(@import("howl_render.zig"))` and imports `test/unit.zig` (`src/non_prod.zig:6-17`). It proves some owner-local logic, but it overlaps heavily with `test:render`. |
| `test:unit:build` | `howl-render` | `src/non_prod.zig` with `entry = .unit` | Installs the `test-unit` test binary (`build.zig:131-138`) | Does not run it | Build-only mirror in name, install step in behavior | `test:unit:build` | Mismatch: current step is named as build-only, but today it installs the test artifact. |
| Unit test root `test-unit` | `howl-render` | `src/non_prod.zig` plus `src/test/unit.zig` | Installed only when `test:unit:build` is invoked | Run by `test:unit` | Owner-local unit root | `test:unit` | Concrete proof: `test/unit.zig` states deterministic geometry and clamp behavior claims (`test/unit.zig:6-26`), while `src/non_prod.zig` also pulls in broader render module coverage. |
| `render-benchmark` | `howl-render` | `src/non_prod.zig` with `entry = .benchmark` and `main = @import("test/benchmark.zig").main` (`src/non_prod.zig:4`) | No install wiring of its own | Runs `render_benchmark` with forwarded `b.args` (`build.zig:164-188`) | Benchmark run surface | `benchmark:<name>` | Mismatch: current public name is outside the canonical benchmark naming family. |
| `render-benchmark:build` | `howl-render` | `src/non_prod.zig` with `entry = .benchmark` | Installs the `render_benchmark` executable (`build.zig:185-187`) | Does not run it | Benchmark build step in name, install step in behavior | `benchmark:<name>:build` | Mismatch: current public name is outside the canonical benchmark naming family, and current behavior installs. |
| Benchmark executable `render_benchmark` | `howl-render` | `src/non_prod.zig` delegating to `src/test/benchmark.zig` | Installed only when `render-benchmark:build` is invoked | Run by `render-benchmark` | Benchmark executable root | `benchmark:<name>` with matching `:build` mirror | Concrete proof: benchmark root measures run time, allocation counts, glyph/scene preparation phases, and workload summaries (`test/benchmark.zig:1-965`). |

### Package Mismatches Recorded

- `runtime-proof` is still publicly exposed through `test:runtime-proof` and `test:runtime-proof:build`, which is directly out of contract.
- `ffi:build` is a non-canonical public step and installs instead of being build-only.
- `test:render` and `test:render:build` are non-canonical public step names.
- `test:unit`, `test:render`, and `test:runtime-proof` overlap heavily instead of mapping cleanly to one meaning each.
- No public `test:abi` surface exists even though `howl-render` ships a C ABI and owns ABI proof in the canonical contract.
- `test:unit:build`, `test:render:build`, `test:runtime-proof:build`, and `render-benchmark:build` all install artifacts instead of being build-only in behavior.
- `render-benchmark` is a benchmark surface outside the canonical `benchmark:<name>` family.

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
| `test` | `howl-pty` | Aggregate over `test:unit` only (`build.zig:46-51`) | No install wiring of its own | Runs whatever `test:unit` runs | Aggregate test step | `test` | Proof gap: no separate ABI test aggregation exists today. |
| `test:unit` | `howl-pty` | `src/howl_pty.zig` | No install wiring of its own | Runs the `test-unit` Zig test binary (`build.zig:35-51`) | Owner-local correctness suite | `test:unit` | Concrete proof: root imports `test/session.zig` and `test/pty.zig` (`src/howl_pty.zig:2-4`), and those tests cover session state, transport write/read behavior, pump modes, typed control signals, and build-selected PTY transport (`grep` matches in `src/test/session.zig` and `src/test/pty.zig`). |
| `test:unit:build` | `howl-pty` | `src/howl_pty.zig` | Installs the `test-unit` test binary via `addInstallArtifact()` (`build.zig:47-49`) | Does not run it | Build-only mirror in name, install step in behavior | `test:unit:build` | Mismatch: current step is named as build-only, but today it installs the test artifact. |
| Unit test root `test-unit` | `howl-pty` | `src/howl_pty.zig` | Installed only when `test:unit:build` is invoked | Run by `test:unit` | Owner-local unit root | `test:unit` | Concrete proof: tests exercise PTY-owned transport and session behavior directly, which fits the package owner split in `AGENTS.md`. |

### Package Mismatches Recorded

- No public `test:abi` surface exists even though `howl-pty` ships a C ABI and owns ABI proof in the canonical contract.
- `ffi:build` is a non-canonical public step and installs instead of being build-only.
- `test:unit:build` installs its artifact instead of being build-only in behavior.

## Cross-Package Current-State Findings

### Current Plain `zig build` Semantics By Package

| Package | Plain `zig build` today | Contract alignment |
| --- | --- | --- |
| `howl-linux-host` | Runs `check`, which depends on install and therefore builds/installs the host harness executable without running it | Partially aligned: non-running default is good, but install side effect remains coupled into `check` |
| `howl-vt` | Installs shipped VT dynamic library and header | Aligned with product-package default semantics |
| `howl-render` | Installs shipped render dynamic library and header | Aligned with product-package default semantics |
| `howl-pty` | Installs shipped PTY dynamic library and header | Aligned with product-package default semantics |

### Repeated Mismatches Against The Canonical Contract

- Product packages expose `ffi:build`, which is not an accepted canonical public step family.
- Multiple `:build` steps currently install artifacts instead of only compiling them.
- No product package currently exposes a public `test:abi` step even though the product is the shipped C ABI.
- `howl-render` still exposes forbidden `runtime-proof` naming publicly.
- `howl-linux-host` currently lacks a public `test:integration` surface.
- `howl-linux-host` currently routes stress-root test binaries through `test:unit`.
- Benchmark naming is not normalized to the canonical `benchmark:<name>` family in `howl-vt` and `howl-render`.

### Proof Gaps Worth Preserving In Review

- Several current roots are compile-smoke surfaces rather than explicit behavior proofs, especially in `howl-linux-host`.
- Several aggregate steps have narrower or broader meaning than their names imply.
- ABI coverage exists unevenly: some internal FFI tests appear inside broader suites, but no package exposes the canonical package-owned `test:abi` public surface today.

## Ledger Boundary

- This document is an inventory and audit baseline only.
- It does not rename steps.
- It does not prescribe implementation changes.
- It does not choose migration order beyond recording target classifications from the canonical contract.
