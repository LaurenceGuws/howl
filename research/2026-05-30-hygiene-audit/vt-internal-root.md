# VT Internal Root Decision

Date: 2026-05-30

## Question

Decide whether `howl-vt/src/howl_vt.zig` is a test aggregator, internal package root, or stale
Zig-shaped lane.

## Sources Read

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `research/2026-05-30-hygiene-audit/roadmap.md` Slice 7.3
- `howl-vt/build.zig`
- `howl-vt/src/howl_vt.zig`
- `libs.yaml`
- grep gate: `rg '@import\("howl_vt\.zig"\)|howl_vt\.zig' howl-vt howl-linux-host`

## Findings

- No source imports `@import("howl_vt.zig")`.
- `howl-linux-host` has no dependency on `howl_vt.zig`.
- `howl-vt/build.zig` creates `internal_mod` with root `src/howl_vt.zig` for `test-unit`.
- `howl-vt/build.zig` separately creates the shipped C ABI module from `src/libhowl_vt.zig` and uses
  that for the dynamic library/check step.
- `howl_vt.zig` imports exact owners and test files in a root `test` block.
- `howl_vt.zig` has a few public aliases (`Parser`, `ParserOwnedActions`, `ScreenSet`, `Terminal`) but
  the build comments state repo-local Zig roots may exist for tests/proofs and are not embedder-facing
  contracts.
- `libs.yaml` does not list `howl_vt.zig` as a public root; it lists `libhowl_vt.zig`.

## Decision

Retain `howl-vt/src/howl_vt.zig` as a build-owned internal unit-test root for now.

It is not a host integration target and not a shipped ABI root. Deleting it would require choosing a
replacement unit-test root or changing build/test taxonomy, which belongs to the build/test
architecture blocker rather than this hygiene slice.

## Guardrails

- Do not add host imports of `howl_vt.zig`.
- Do not advertise `howl_vt.zig` as a Zig package API.
- Keep `libhowl_vt.zig` as the C ABI public root.
- If test taxonomy is redesigned, re-evaluate whether `howl_vt.zig` should remain the unit-test root.

## Verification

- `git diff --check`
- `rg '@import\("howl_vt\.zig"\)|howl_vt\.zig' howl-vt howl-linux-host`

## Follow-Up

No implementation slice is promoted from this scratchpad.
