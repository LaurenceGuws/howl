# Render Test Build Coverage

Date: 2026-05-30

Owner: `howl-render`.

Purpose: decide whether render `test:build` and `check` still prove the right compile-only test
surface after `test:unit` and `test:abi` were split.

## Sources Read

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `research/2026-05-30-hygiene-audit/build-test-architecture-plan.md`
- `howl-render/build.zig`
- `howl-pty/build.zig`
- `howl-vt/build.zig`

## Current State

- `howl-render/build.zig` now has category run/build steps for `test:unit` and `test:abi`.
- `test` aggregates `test:unit` and `test:abi`.
- `test:build` still depends directly on the old combined `test-render` compile step.
- `check` depends on the shipped render C ABI library, `test:build`, and benchmark build.
- PTY and VT expose category build steps but do not expose a combined `test:build` aggregate.

## Decision

Keep render `test:build` as a convenience aggregate, but make it aggregate the category build steps.

Rationale:

- Root does not aggregate `test:build`, so this is package-local compatibility/convenience.
- After category split, `test:build` should prove the same deterministic test categories as `test`
  without running them.
- Building the old combined root is redundant and less auditable than building `test:unit:build` and
  `test:abi:build`.
- `check` can continue depending on `test:build` once `test:build` is a category aggregate.

## Implementation Slice

Exact file:

- `howl-render/build.zig`

Change:

- Replace `test_build_step.dependOn(&tests.step);` with:
  - `test_build_step.dependOn(test_unit_build_step);`
  - `test_build_step.dependOn(test_abi_build_step);`

Non-goals:

- Do not remove the old combined `test-render` root in this slice.
- Do not change `test` run behavior.
- Do not change product code, tests, C ABI, benchmark build, or root build mappings.

Verification:

- From `howl-render`: `zig build test:build`.
- From `howl-render`: `zig build test:unit:build`.
- From `howl-render`: `zig build test:abi:build`.
- From `howl-render`: `zig build check`.
- From root: `zig build check`.
- `git diff --check`.

Grep gates:

- `rg 'test_build_step\.dependOn|test_unit_build_step|test_abi_build_step|check_step\.dependOn' howl-render/build.zig`
- `rg 'test_build_step\.dependOn\(&tests\.step\)' howl-render/build.zig` prints nothing.

Stop conditions:

- Stop if `test:build` cannot build both category roots without changing product code.
- Stop if the old combined root is required for coverage not represented by `test:unit` or `test:abi`.
