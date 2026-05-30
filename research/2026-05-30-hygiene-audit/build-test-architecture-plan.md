# Build/Test Architecture Plan

Date: 2026-05-30

Owner: workspace root.

Purpose: close the build/test architecture blocker with a TigerBeetle-derived verification taxonomy
for Howl. Terminal references inform test category ideas only; TigerBeetle supplies the hard gates.

## Sources Read

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `reference-index.md`
- `project-memory.md` build/test architecture blocker
- `build.zig`
- `howl-pty/build.zig`
- `howl-vt/build.zig`
- `howl-render/build.zig`
- `howl-linux-host/build.zig`
- `howl-render/src/test.zig`
- `howl-linux-host/src/test/test_entry.zig`
- `howl-linux-host/src/test/integration_entry.zig`
- Ghostty owner-local tests under `utils/dev_references/terminals/ghostty/src/terminal/*.zig`
- Ghostty owner-local tests under `utils/dev_references/terminals/ghostty/src/termio/*.zig`

## TigerBeetle Law Applied

- Every verification surface must have an owner and a bounded purpose.
- Every build step must state exactly what it proves.
- Unit tests prove owner-local invariants, positive/negative space, and assertion-backed contracts.
- ABI tests prove shipped C headers, exported C symbols, layout, values, and FFI translation.
- Integration tests prove package-boundary behavior through shipped ABIs only.
- Regression tests preserve named historical failures and may be slower, but they still need exact
  owners and bounds.
- Fuzz, stress, and benchmark steps are not substitutes for deterministic tests. They are named extra
  surfaces with explicit caps, arguments, and owners.
- Root build orchestration aggregates package-owned steps only. It must not import package internals.

## Current Inventory

### Root

- `build.zig` aggregates package-local `check`, `test`, `test:unit`, `test:abi`,
  `test:integration`, `test:regression`, `fuzz`, `stress`, and `benchmark` steps by invoking package
  builds with `zig build <step>`.
- Root default step is `check`.
- This is the correct ownership direction: root orchestrates and audits, packages own build details.

### PTY

- `howl-pty/build.zig` exposes `check`, `test`, `test:unit`, `test:unit:build`, `test:abi`, and
  `test:abi:build`.
- `test:unit` currently roots at `src/libhowl_pty.zig`.
- `test:abi` roots at `src/test/abi.zig` and imports `src/ffi.zig` with header include paths.
- `check` builds the shipped dynamic C ABI library and installs the public header on install.

### VT

- `howl-vt/build.zig` exposes `check`, `test`, `test:unit`, `test:unit:build`, `test:abi`,
  `test:abi:build`, `test:regression`, `test:regression:build`, `fuzz`, `fuzz:build`, and
  `benchmark:m7_baseline`.
- `test:unit` roots at `src/howl_vt.zig`, a build-owned internal unit-test root.
- `test:abi` roots at `src/test/abi.zig` and imports `src/ffi.zig` with C ABI options.
- `test:regression` has named scrollback and snapshot regression roots.
- `fuzz` builds `src/fuzz/fuzz_tests.zig` against the internal VT root.
- `check` builds the shipped dynamic C ABI library and installs the public header on install.

### Render

- `howl-render/build.zig` exposes `check`, `test`, `test:build`, `benchmark:render`, and
  `benchmark:render:build`.
- `src/test.zig` aggregates `libhowl_render.zig`, `test/ffi.zig`, and `test/unit.zig` in one test
  root, and also exposes benchmark `main` from `test/benchmark.zig`.
- Render does not yet expose `test:unit`, `test:unit:build`, `test:abi`, or `test:abi:build`, even
  though root mappings expect render `test:unit` and `test:abi`.
- `check` builds the shipped dynamic C ABI library and also builds tests and benchmark binaries.

### Linux Host

- `howl-linux-host/build.zig` exposes `check`, `run`, `test`, `test:unit`, `test:unit:build`,
  `test:integration`, `test:integration:build`, stress run/build steps, and host executable install.
- Host unit tests root at `src/test/test_entry.zig`, importing selected owner modules directly.
- Host integration tests root at `src/test/integration_entry.zig`, importing `host` from
  `build_support/host_tests.zig` and linking through shipped PTY/VT/render libraries and translated C
  headers.
- This is the correct category split: host unit tests for host-owned pure owners; host integration
  tests for embedding seams through ABIs.

## Accepted Taxonomy

### `check`

Purpose: compile the shipped package surface and any fast compile-only proof targets required to keep
the package honest.

Rules:

- Product libraries: build the shipped dynamic C ABI library from `src/libhowl_*.zig`.
- Host: build the host executable through shipped ABI dependencies.
- `check` may depend on `*:build` proof steps only when those proofs are fast and deterministic.
- `check` must not run fuzz, stress, or benchmarks.
- `check` must not install as its proof; install is a packaging side effect.

### `test`

Purpose: run all deterministic correctness tests that should pass in ordinary local and CI validation.

Rules:

- `test` depends on package-owned deterministic test categories only.
- `test` does not run fuzz, stress, or benchmarks.
- `test` may include regression tests only if their runtime is bounded enough for ordinary validation;
  otherwise regression stays a named explicit step.

### `test:unit`

Purpose: owner-local invariant and behavior tests.

Rules:

- Unit tests may import internal owner files through package-owned internal roots.
- Unit tests must stay owner-local or protocol-local; they must not become hidden integration tests.
- Owner-local tests should live with the owner where visibility allows, matching the Ghostty pattern of
  tests in terminal/termio owner files.
- Do not make private helpers public only for unit tests. Move helpers to exact owners if tests need a
  different file.

### `test:abi`

Purpose: shipped C ABI contract tests.

Rules:

- ABI tests use public headers, translated C structs, exported-symbol roots, and FFI translators.
- ABI tests own layout, enum value, handle/status, null-pointer, and translation proof.
- ABI tests must not import host convenience modules or internal Zig package roots except explicit FFI
  translator modules needed to compare C/Zig contracts.
- Every C ABI package should expose `test:abi` and `test:abi:build`.

### `test:integration`

Purpose: cross-package embedding behavior through shipped ABIs.

Rules:

- Host integration tests are the primary integration owner because hosts embed PTY, VT, and render.
- Integration tests consume PTY/VT/render through shipped libraries and translated headers, not direct
  Zig imports.
- Product packages should not grow integration tests that import hosts.

### `test:regression`

Purpose: named historical bug proofs whose setup or runtime is too specific for ordinary unit tests.

Rules:

- Regression tests must name the failure or scenario they preserve.
- Regression tests stay deterministic and bounded.
- Regression tests may be package-specific and optional from root `test` until runtime policy is set.

### `fuzz`

Purpose: bounded exploratory search for assertion failures and state-machine mismatches.

Rules:

- Fuzzers are owned by the package whose state machine they exercise.
- Fuzz runs must expose explicit iteration/input/time caps before they become root default gates.
- Fuzz does not replace deterministic positive/negative tests.

### `stress`

Purpose: hostile workload drivers for host/render/terminal runtime behavior.

Rules:

- Stress runs are explicit opt-in steps.
- Stress binaries must have default finite modes or require explicit arguments.
- Stress is never a substitute for `check` or `test`.

### `benchmark`

Purpose: measurement-only executables.

Rules:

- Benchmarks may compile under `check` only as build proofs, not run proofs.
- Benchmark run steps are explicit and never part of deterministic correctness gates.

## Build-Step Contract

Every package should expose this normalized deterministic set when applicable:

- `check`
- `test`
- `test:unit`
- `test:unit:build`
- `test:abi`
- `test:abi:build`

Optional named surfaces:

- `test:integration`, `test:integration:build`
- `test:regression`, `test:regression:build`
- `fuzz`, `fuzz:build`
- `stress:*`, `stress:*:build`
- `benchmark:*`, `benchmark:*:build`

Root may aggregate only steps that exist in package builds. Missing mapped steps are build-contract
bugs, not optional behavior.

## Gaps

- Render build step taxonomy is inconsistent with the root contract: root maps render `test:unit` and
  `test:abi`, but `howl-render/build.zig` currently exposes only `test` and `test:build`.
- Render `src/test.zig` mixes ABI and unit tests into one root. This blocks root category audit.
- Render benchmark `main` shares the same root source as tests through `src/test.zig`; this is
  convenient but obscures whether benchmark compile proves benchmark-only code or the full test root.
- VT `test:regression` is not part of root `test`; this may be correct, but the runtime bound policy
  is not documented beyond “slow regression tests”.
- Host app-owner tests still live in `src/main.zig`; extracting them remains blocked unless helpers
  move to exact owners or the build/test taxonomy adds a principled app test root without public
  helper aliases.

## First Worker-Ready Slice

Name: `Normalize Render Test Categories`.

Owner: `howl-render`.

Why first:

- Root already maps render `test:unit` and `test:abi`, so current source has a concrete build-contract
  mismatch.
- Render already has separate `src/test/unit.zig` and `src/test/ffi.zig` files.
- The slice can add category steps without changing product code, C ABI, or test behavior.

Exact files:

- `howl-render/build.zig`
- `howl-render/src/test.zig` only if needed to preserve the all-tests aggregate cleanly
- Optional new test roots if build.zig cannot point directly at existing files without duplication:
  `howl-render/src/test/unit_entry.zig` and `howl-render/src/test/abi_entry.zig`
- `libs.yaml` only if build/test owner metadata is added later; not required for the first slice

Required shape:

- Add `test:unit` and `test:unit:build` for `src/test/unit.zig` plus any owner decl coverage required
  for unit proofs.
- Add `test:abi` and `test:abi:build` for `src/test/ffi.zig` plus `libhowl_render.zig` C ABI decl
  coverage if currently proved by `src/test.zig`.
- Keep `test` as the aggregate of `test:unit` and `test:abi`.
- Keep root `zig build test`, `zig build test:unit`, and `zig build test:abi` working.
- Do not change exported C symbols, headers, render owners, or test assertions.

Stop conditions:

- Stop if splitting render tests requires making private render helpers public.
- Stop if `test/ffi.zig` depends on unit-only imports in a way that requires moving product code.
- Stop if benchmark compilation requires a separate design decision.
- Stop if root `test:abi` or `test:unit` has been intentionally disabled elsewhere; record the source
  proof instead of forcing a shape.

Verification:

- `zig build check`
- `zig build test`
- `zig build test:unit`
- `zig build test:abi`
- `git diff --check`

Grep gates:

- `rg 'test:unit|test:abi|test:unit:build|test:abi:build' howl-render/build.zig`
- `rg 'test:unit|test:abi' build.zig howl-render/build.zig`
- `rg 'pub fn|pub const' howl-render/src/test`
  must support review that no broad public helper alias was added just for tests.

## Later Slices

- Decide whether VT regression tests are part of canonical `test` or remain explicit slow proofs, with
  a documented runtime bound.
- Decide host app-owner test placement after build/test root taxonomy is stable; do not expose private
  app helpers for tests.
- Add durable grep/audit gates only after the build system has an accepted owner for generated or
  scripted checks.
