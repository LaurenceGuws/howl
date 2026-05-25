# Build/Test Architecture Migration Scratchpad

Owner: workspace root.

Source:

- `build-test-architecture-blocker-scratchpad.md`
- architecture research memo derived from all package `build.zig` files and TigerBeetle posture

Purpose:

- Scope the full repo-wide build/test architecture migration into promotion-ready steps.
- Preserve direct-cutover discipline.
- Keep package ownership and ABI-first boundaries explicit.

## Fixed Decisions

- `howl-linux-host` is a laboratory harness, not a product-facing app package.
- `runtime-proof` is not an accepted repo-wide verification category.
- No compatibility aliases are allowed.
- All naming and behavior changes cut over directly in one coherent change per slice.

## Target Taxonomy

### Build-Step Taxonomy

- `install`
- `check`
- `run`
- `test`
- `test:unit`
- `test:abi`
- `test:integration`
- `test:regression`
- `test:<class>:build`
- `fuzz`
- `fuzz:build`
- `stress:<name>`
- `stress:<name>:build`
- `benchmark:<name>`
- `benchmark:<name>:build`

### Verification Taxonomy

- `unit`
- `abi`
- `integration`
- `regression`
- `fuzz`
- `stress`
- `benchmark`

## Global Migration Constraints

- Direct cutover only.
- No new umbrella runtime layer.
- No Zig-shaped host bypass around ABI boundaries.
- Package-level build contracts stay owner-local.
- Workspace-root orchestration is allowed only for audit/build coordination, not for changing runtime boundaries.
- Every promoted slice must update code, step names, docs, and scripts together when they are affected.
- Artifact-placement normalization is not a standalone sweep; each package-local migration slice must prove product artifacts vs dev-only artifacts directly.

## Contract Meaning

- `install`: installs shipped product artifacts only.
- `check`: default non-running verification/build audit step; never runs stress, fuzz, or benchmarks.
- `run`: operator-facing manual execution path for a runnable harness/app.
- `test`: aggregate of accepted test families only.
- `test:unit`: owner-local logic tests.
- `test:abi`: tests that prove the shipped C ABI contract.
- `test:integration`: cross-package behavior through the shipped ABI seam.
- `test:regression`: targeted bug-history or expensive correctness suites.
- `fuzz`: runs fuzz surfaces.
- `stress:<name>`: runs stress harnesses.
- `benchmark:<name>`: runs measurement surfaces and are never treated as proof of correctness.

## Slice Template

- `Targets`
- `Depends on`
- `Out of scope`
- `Proof of done`

## Migration Slices

### 1. Write The Canonical Build/Test Architecture Contract

Targets:

- `/home/home/personal/projects/howl/build-test-architecture-spec.md`

Depends on:

- none

Out of scope:

- no current-state inventory table
- no code edits
- no package-specific rename plan beyond naming contract

Proof of done:

- one checked-in spec defines:
  - package default semantics
  - workspace-root semantics
  - accepted build-step taxonomy
  - accepted verification taxonomy
  - package ownership matrix
  - product-vs-dev artifact install policy
  - direct-cutover/no-alias rules

### 2. Build The Current-State Verification Ledger

Targets:

- `/home/home/personal/projects/howl/build-test-verification-ledger.md`
- `/home/home/personal/projects/howl/howl-linux-host/build.zig`
- `/home/home/personal/projects/howl/howl-vt/build.zig`
- `/home/home/personal/projects/howl/howl-render/build.zig`
- `/home/home/personal/projects/howl/howl-pty/build.zig`

Depends on:

- 1

Out of scope:

- no renames or migration edits

Proof of done:

- every current meaningful step, executable root, test root, and installed artifact across the four package build files is listed with:
  - owner
  - root file
  - install behavior
  - run behavior
  - current classification
  - target classification
  - proof statement or proof gap

### 3. Normalize Host Default Step And Install Contract

Targets:

- `/home/home/personal/projects/howl/howl-linux-host/build.zig`

Depends on:

- 1
- 2

Out of scope:

- stress-root relocation
- host unit/integration split

Proof of done:

- plain `zig build` in `howl-linux-host` has one explicit harness-default meaning
- `check`, `run`, and install behavior are documented and implemented coherently
- the primary host binary is not treated as a casual product app install path

### 4. Move Host Stress Roots Under Stress Ownership

Targets:

- `/home/home/personal/projects/howl/howl-linux-host/build.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/stress/ascii_rain_stress.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/stress/visual_rain_stress.zig`

Depends on:

- 1
- 2
- 3

Out of scope:

- host unit/integration taxonomy cleanup

Proof of done:

- no host stress root remains under `src/fuzz/`
- stress source paths and step names agree
- stress roots are no longer implied to be fuzz surfaces

### 5. Add Explicit Host Stress Build Steps

Targets:

- `/home/home/personal/projects/howl/howl-linux-host/build.zig`

Depends on:

- 4

Out of scope:

- stress behavior changes

Proof of done:

- each runnable host stress surface has a matching `stress:<name>:build` step
- stress artifacts stay off the product install path

### 6. Remove Stress Suites From Host Unit Tests

Targets:

- `/home/home/personal/projects/howl/howl-linux-host/build.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/test/test_entry.zig`
- `/home/home/personal/projects/howl/howl-linux-host/build_support/host_tests.zig`

Depends on:

- 1
- 2
- 4
- 5

Out of scope:

- adding the final host integration surface

Proof of done:

- `test:unit` no longer runs stress roots
- `test:unit` no longer mixes host owner-local tests with non-unit surfaces

### 7. Add Host Integration Verification Surface

Targets:

- `/home/home/personal/projects/howl/howl-linux-host/build.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/test/test_entry.zig`
- `/home/home/personal/projects/howl/howl-linux-host/build_support/host_tests.zig`

Depends on:

- 6

Out of scope:

- root orchestration

Proof of done:

- `test:integration` exists
- it is the only host-owned step that proves cross-package behavior through shipped ABI seams

### 8. Normalize PTY Package Default Contract

Targets:

- `/home/home/personal/projects/howl/howl-pty/build.zig`

Depends on:

- 1
- 2

Out of scope:

- ABI suite additions beyond contract placement

Proof of done:

- plain `zig build` means shipped PTY ABI install only
- `check` exists
- redundant `ffi:build` semantics are removed or folded into canonical naming
- dev-only test artifacts do not install into the product prefix

### 9. Normalize VT Package Default Contract

Targets:

- `/home/home/personal/projects/howl/howl-vt/build.zig`

Depends on:

- 1
- 2

Out of scope:

- benchmark taxonomy cutover
- ABI suite additions

Proof of done:

- plain `zig build` means shipped VT ABI install only
- `check` exists
- redundant `ffi:build` semantics are removed or folded into canonical naming
- dev-only artifacts are not installed as product artifacts

### 10. Normalize Render Package Default Contract

Targets:

- `/home/home/personal/projects/howl/howl-render/build.zig`

Depends on:

- 1
- 2

Out of scope:

- runtime-proof reclassification
- benchmark taxonomy cutover
- root cleanup

Proof of done:

- plain `zig build` means shipped render ABI install only
- `check` exists
- redundant `ffi:build` semantics are removed or folded into canonical naming
- dev-only artifacts are kept off the product install path

### 11. Add PTY ABI Verification

Targets:

- `/home/home/personal/projects/howl/howl-pty/build.zig`
- exact PTY ABI test root chosen during implementation

Depends on:

- 8

Out of scope:

- host integration

Proof of done:

- `test:abi` exists in `howl-pty`
- its proof statement explicitly names the shipped PTY C ABI contract being verified

### 12. Add VT ABI Verification

Targets:

- `/home/home/personal/projects/howl/howl-vt/build.zig`
- exact VT ABI test root chosen during implementation

Depends on:

- 9

Out of scope:

- benchmark reclassification

Proof of done:

- `test:abi` exists in `howl-vt`
- its proof statement explicitly names the shipped VT C ABI contract being verified

### 13. Add Render ABI Verification

Targets:

- `/home/home/personal/projects/howl/howl-render/build.zig`
- exact render ABI test root chosen during implementation

Depends on:

- 10

Out of scope:

- runtime-proof reclassification

Proof of done:

- `test:abi` exists in `howl-render`
- its proof statement explicitly names the shipped render C ABI contract being verified

### 14. Reclassify VT Benchmark Surface

Targets:

- `/home/home/personal/projects/howl/howl-vt/build.zig`
- `/home/home/personal/projects/howl/howl-vt/src/terminal_benchmark_main.zig`

Depends on:

- 9

Out of scope:

- fuzz and regression behavior changes

Proof of done:

- the VT benchmark step family is renamed into canonical `benchmark:<name>` and `benchmark:<name>:build` taxonomy
- it is no longer mixed with test proof language

### 15. Reclassify VT Remaining Special Verification Surfaces

Targets:

- `/home/home/personal/projects/howl/howl-vt/build.zig`
- `/home/home/personal/projects/howl/howl-vt/src/fuzz/fuzz_tests.zig`
- `/home/home/personal/projects/howl/howl-vt/src/test/scrollback_regression.zig`
- `/home/home/personal/projects/howl/howl-vt/src/fuzz/scrollback.zig`

Depends on:

- 9
- 12
- 14

Out of scope:

- root orchestration

Proof of done:

- VT fuzz, regression, and helper roots all map cleanly into accepted taxonomy
- each has an explicit proof statement and no ambiguous labels

### 16. Remove Render Runtime-Proof Taxonomy

Targets:

- `/home/home/personal/projects/howl/howl-render/build.zig`
- `/home/home/personal/projects/howl/howl-render/src/non_prod.zig`

Depends on:

- 10
- 13

Out of scope:

- benchmark taxonomy cleanup

Proof of done:

- no `runtime-proof` step name remains
- each former runtime-proof surface is reclassified into `test:unit`, `test:integration`, or `test:regression`
- each reclassified surface has an explicit proof statement

### 17. Reclassify Render Benchmark Surface

Targets:

- `/home/home/personal/projects/howl/howl-render/build.zig`
- `/home/home/personal/projects/howl/howl-render/src/non_prod.zig`

Depends on:

- 10

Out of scope:

- full root split

Proof of done:

- render benchmark step names are cut over to canonical benchmark taxonomy
- they are clearly non-proof measurement surfaces

### 18. Split Render Multi-Purpose Non-Product Root

Targets:

- `/home/home/personal/projects/howl/howl-render/build.zig`
- `/home/home/personal/projects/howl/howl-render/src/non_prod.zig`

Depends on:

- 16
- 17

Out of scope:

- ABI behavior changes

Proof of done:

- public build taxonomy no longer depends on one ambiguous multi-purpose root
- each remaining root has one owner-true verification role

### 19. Add Workspace-Root Build Orchestration

Targets:

- `/home/home/personal/projects/howl/build.zig`

Depends on:

- 3
- 7
- 8
- 9
- 10
- 11
- 12
- 13
- 15
- 18

Out of scope:

- CI script changes outside root build entrypoints

Proof of done:

- root `build.zig` exists
- root default is `check`
- root steps aggregate normalized package steps only
- root does not create any privileged Zig-shaped integration path around the ABI boundary

### 20. Add Root Aggregate Audit Surface

Targets:

- `/home/home/personal/projects/howl/build.zig`
- `/home/home/personal/projects/howl/build-test-architecture-spec.md`
- `/home/home/personal/projects/howl/build-test-verification-ledger.md`

Depends on:

- 19

Out of scope:

- package-local behavior changes

Proof of done:

- root aggregate steps such as `test`, `test:unit`, `test:abi`, `test:integration`, `test:regression`, `fuzz`, `stress`, and `benchmark` each have:
  - a stable package mapping
  - an explicit proof statement in the architecture docs

## Promotion Order

1. Write the canonical build/test architecture contract
2. Build the current-state verification ledger
3. Normalize host default step and install contract
4. Move host stress roots under stress ownership
5. Add explicit host stress build steps
6. Remove stress suites from host unit tests
7. Add host integration verification surface
8. Normalize PTY package default contract
9. Normalize VT package default contract
10. Normalize render package default contract
11. Add PTY ABI verification
12. Add VT ABI verification
13. Add render ABI verification
14. Reclassify VT benchmark surface
15. Reclassify VT remaining special verification surfaces
16. Remove render runtime-proof taxonomy
17. Reclassify render benchmark surface
18. Split render multi-purpose non-product root
19. Add workspace-root build orchestration
20. Add root aggregate audit surface

## Acceptance Gate For Each Promotion

- The slice changes one architectural concern in one owner scope.
- The exact files and roots touched are named in advance.
- The proof statement for every changed step is explicit.
- Product-vs-dev artifact placement is proven for that owner scope.
- Step names, docs, and helper scripts cut over in the same change when affected.
- No compatibility alias remains.
- No ABI-boundary bypass is introduced.

## Not Yet Promoted

- Next promotion should be slice 1 only.
- Do not promote slice 2 together with slice 1.
- Do not promote any code-touching slice before slices 1 and 2 exist.
