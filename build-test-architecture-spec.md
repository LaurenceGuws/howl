# Build/Test Architecture Contract

Owner: workspace root.

Purpose:

- Define the canonical repo-wide contract for build steps, verification classes, install behavior, and ownership boundaries.
- Give reviewers one normative source for judging whether a new step, test surface, harness, or artifact belongs in the workspace.

## Scope

- This document defines the target architecture contract.
- This document does not record the current-state verification ledger.
- This document does not define migration order beyond rules needed to state the contract.
- This document is governed by `AGENTS.md`, `loop.txt`, `reference-index.md`, the promoted task in `current.txt`, and TigerBeetle's build/style posture.

## Fixed Decisions

- `howl-linux-host` is a laboratory harness, not a product-facing app package.
- `runtime-proof` is not an accepted repo-wide verification category.
- No compatibility aliases are allowed.
- Naming and behavior changes cut over directly in one coherent change per slice.
- No new umbrella runtime layer is allowed.
- No host or root build surface may bypass the ABI boundary with Zig-shaped convenience imports.

## Purpose And Product Boundary

- The product is the shipped C ABI surface.
- `howl-pty`, `howl-vt`, and `howl-render` are product packages because they own shipped ABI contracts.
- `howl-linux-host` is a developer-owned harness package for exercising those contracts on Linux.
- Build architecture must preserve the owner split in `AGENTS.md`:
  - `howl-pty` owns PTY transport behavior.
  - `howl-vt` owns terminal state and protocol truth.
  - `howl-render` owns render contracts and retained-frame behavior.
  - Hosts own runtime orchestration, wake policy, presentation cadence, and platform UX.

## Package Default Semantics

### Product Packages

- In `howl-pty`, `howl-vt`, and `howl-render`, plain `zig build` means `install`.
- In those packages, `install` installs shipped product artifacts only.
- In those packages, shipped product artifacts means the package's supported C ABI deliverables such as libraries, headers, and other ABI-facing install outputs required for embedding.
- In those packages, plain `zig build` must not implicitly run test, fuzz, stress, or benchmark surfaces.

### Host Harness Package

- In `howl-linux-host`, plain `zig build` is a developer convenience default for the laboratory harness package, not a product contract.
- Any artifact installed by `howl-linux-host` is a dev-only harness artifact.
- `howl-linux-host` install behavior must never be described as shipping the product.
- `howl-linux-host` must expose an explicit `run` step for manual harness execution.
- `howl-linux-host` must keep verification and install meaning separate: running the harness is not proof, and installing the harness is not product shipment.

## Workspace-Root Semantics

- The workspace root is an orchestration and audit boundary only.
- The workspace root does not own runtime behavior, host integration policy, or any product ABI.
- The workspace root may aggregate normalized package steps for auditability.
- The workspace root must not create a privileged integration path that bypasses package ABI seams.
- When a root `build.zig` exists, plain `zig build` at the workspace root means `check`.
- Root `check` is an aggregate non-running audit/build step.
- Root aggregate steps may depend only on canonical package-local steps.
- The workspace root must not install product artifacts of its own.
- The workspace root must not define a default `run` surface.

## Canonical Build-Step Taxonomy

Only the following public step families are accepted.

### Core Steps

- `install`: install shipped product artifacts for product packages, or explicit dev-only harness artifacts for a harness package.
- `check`: compile or audit the default supported owner surfaces without running long-lived or measurement workloads.
- `run`: manually execute a runnable harness or tool.
- `test`: aggregate accepted test families only.

### Test Families

- `test:unit`: run owner-local logic tests.
- `test:abi`: run tests that prove the shipped C ABI contract.
- `test:integration`: run cross-package behavior through the shipped ABI seam.
- `test:regression`: run targeted bug-history or expensive correctness suites.

### Build-Only Mirrors For Test Families

- `test:unit:build`
- `test:abi:build`
- `test:integration:build`
- `test:regression:build`

These steps compile the surface without running it.

### Fuzz

- `fuzz`: run fuzz surfaces.
- `fuzz:build`: compile fuzz surfaces without running them.

### Stress

- `stress:<name>`: run one named stress harness.
- `stress:<name>:build`: compile one named stress harness without running it.

### Benchmark

- `benchmark:<name>`: run one named benchmark surface.
- `benchmark:<name>:build`: compile one named benchmark surface without running it.

### Aggregate Runner Rule

- A package or the workspace root may define aggregate `stress` and `benchmark` steps only as dependency aggregators over canonical named steps.
- Aggregate `stress` and `benchmark` steps do not define new verification categories.

### Naming Rules

- Public step names must state one meaning only.
- One step family must map to one verification or execution role.
- Multi-purpose names are not allowed.
- `runtime-proof` is forbidden.
- Ad hoc synonyms such as compatibility aliases, temporary parallel names, or legacy holdovers are forbidden.

## Canonical Verification Taxonomy

Only the following verification categories are accepted.

### `unit`

- Proves owner-local logic.
- Does not require a cross-package seam.
- Must not include stress or benchmark workloads.

### `abi`

- Proves the shipped C ABI contract of one product package.
- Must name the contract being proved.
- Must test the public ABI surface, not an internal Zig convenience path.

### `integration`

- Proves behavior across package boundaries through the shipped ABI seam.
- Must exercise real package interaction, not internal owner-local helpers.
- Must not bypass the ABI boundary with Zig-shaped imports.

### `regression`

- Proves a known correctness risk, bug history, or expensive scenario that should stay outside routine unit coverage.
- Is still correctness proof, not measurement.

### `fuzz`

- Searches for bugs by generating varied inputs.
- Is complementary evidence, not a substitute for assertions or explicit proof statements.

### `stress`

- Exercises load, pacing, or long-running pressure behavior.
- Is not a unit test and is not automatically a correctness proof of the full product.

### `benchmark`

- Measures behavior.
- Is never treated as proof of correctness.

## Ownership Boundaries For Verification Surfaces

### `howl-pty`

- Owns `unit` verification for PTY variants, child I/O, resize delivery, control signals, and transport state.
- Owns `abi` verification for the PTY C ABI it ships.
- May own `regression`, `fuzz`, `stress`, and `benchmark` surfaces only when they test PTY-owned behavior.
- Does not own cross-package host/runtime integration proof.

### `howl-vt`

- Owns `unit` verification for parser state, terminal state, selection, input encoding, and VT-surface truth.
- Owns `abi` verification for the VT C ABI it ships.
- May own `regression`, `fuzz`, `stress`, and `benchmark` surfaces only when they test VT-owned behavior.
- Does not own cross-package host/runtime integration proof.

### `howl-render`

- Owns `unit` verification for render contracts, geometry policy, retained-frame state, prepare/submit scheduling, render-surface contracts, and text shaping.
- Owns `abi` verification for the render C ABI it ships.
- May own `regression`, `fuzz`, `stress`, and `benchmark` surfaces only when they test render-owned behavior.
- Does not own cross-package host/runtime integration proof.

### `howl-linux-host`

- Owns `unit` verification for host-owned runtime helpers, event-loop policy, wake policy, and platform orchestration logic.
- Owns `integration` verification for cross-package behavior through shipped ABI seams.
- Owns host-side `regression`, `stress`, and `benchmark` surfaces for harness behavior and runtime pressure scenarios.
- Does not redefine package ABI proof on behalf of product packages.

### Workspace Root

- Owns no package-local verification surface.
- Owns no runtime integration implementation.
- May own aggregate audit steps only.

## Product-Vs-Dev Artifact Install Policy

### Product Artifacts

- Product artifacts are the shipped ABI deliverables from `howl-pty`, `howl-vt`, and `howl-render`.
- Product artifacts are the only artifacts that belong on a product install path.

### Dev-Only Artifacts

- Dev-only artifacts include host harness binaries, test binaries, regression harnesses, fuzzers, stress harnesses, benchmarks, helper tools, and build-only mirrors.
- Dev-only artifacts must not be installed as product artifacts.
- A `:build` step exists to compile a dev surface without implying install or proof.

### Install Rule

- `install` must not be used as a catch-all sink for every built executable.
- If an artifact is not part of the shipped ABI contract, it must stay off the product install path.
- Host harness installation, if provided, is a developer convenience and must remain clearly separate from product shipment semantics.

## Direct-Cutover / No-Alias Rule

- Step renames cut over directly.
- Artifact-placement changes cut over directly.
- Documentation, scripts, and build step names must change together when affected.
- Compatibility aliases are forbidden.
- Transitional duplicate names are forbidden.
- If a surface does not fit the accepted taxonomy, it must be reclassified or removed, not preserved under a special-case repo-wide label.

## How To Judge Future Additions

Judge every new build or verification addition against this contract in this order:

1. Does it preserve the ABI-first package boundary from `AGENTS.md`?
2. Does it fit one canonical build-step name without aliases or mixed meaning?
3. Does it fit one canonical verification category with an explicit proof statement?
4. Is it owned by the smallest true package owner?
5. Does its install behavior keep product artifacts and dev-only artifacts separate?
6. Does it avoid creating a root-level or host-level Zig bypass around the ABI seam?

If any answer is no, the addition is not acceptable in its proposed shape.
