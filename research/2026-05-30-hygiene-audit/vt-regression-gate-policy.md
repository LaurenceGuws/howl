# VT Regression Gate Policy

Date: 2026-05-30

Owner: `howl-vt` and workspace root.

Purpose: decide whether VT regression tests are part of canonical deterministic `test` or remain an
explicit slow proof surface.

## Sources Read

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `research/2026-05-30-hygiene-audit/build-test-architecture-plan.md`
- `howl-vt/build.zig`
- `howl-vt/src/test/scrollback_regression.zig`
- `howl-vt/src/test_regression_snapshot.zig`
- `howl-vt/src/test/snapshot_regression.zig`
- `howl-vt/src/fuzz/scrollback.zig`

## Current Wiring

- `howl-vt` `test` currently depends on `test:abi` and `test:unit` only.
- `test:regression` runs two deterministic roots:
  - `test-regression-scrollback` from `src/test/scrollback_regression.zig`.
  - `test-regression-snapshot` from `src/test_regression_snapshot.zig`.
- Root `test:regression` aggregates only `howl-vt` `test:regression`.

## Bound Inventory

- Scrollback regression uses fixed seeds and fixed operation counts:
  - deterministic seeded churn: seed `0x6f686f776c5f7363`, `1_500` ops, run twice.
  - high-churn invariants: five fixed seeds, `2_000` ops each.
  - canonical preservation: fixed seed `0x7a6964655f726566` with default options.
- Shared scrollback verifier has explicit dimensions and operation bounds:
  - `RowsMin = 1`, `RowsMax = 80`.
  - `ColsMin = 1`, `ColsMax = 220`.
  - default history capacity `4096`.
  - default warmup bursts `320`.
  - default churn ops `400`.
  - write bursts cap lines to `8` and line bytes to `90`.
- Snapshot regression is ordinary deterministic terminal-state proof code with fixed small grid sizes
  in visible tests and no external fixtures.

## Decision

VT regression tests are deterministic and bounded, but not bounded tightly enough for canonical
ordinary `howl-vt` `test` today.

Rationale:

- TigerBeetle requires explicit bounds; these regression roots encode fixed seeds, fixed operation
  counts, and finite dimensions.
- TigerBeetle also requires verification surfaces to have honest purpose and bounded work. The current
  regression work is intentionally expensive enough that `zig build test:regression` exceeded the
  ordinary 120s verification budget during review.
- Therefore `test:regression` remains an explicit named proof surface until a later slice either
  reduces the deterministic scenario cost or establishes a separate slow-test policy.

## Implementation Slice

Exact file:

- `howl-vt/build.zig`

Change:

- No build-code change is accepted in this slice.
- Keep `test:regression` explicit and outside canonical `test`.

Non-goals:

- Do not change regression test bodies.
- Do not move regression roots.
- Do not add runtime knobs.
- Do not add fuzz, stress, or benchmark to `test`.

Verification:

- From `howl-vt`: `zig build test:regression`.
- From `howl-vt`: `zig build test` remains unchanged.
- From root: `zig build test` remains unchanged.
- `git diff --check`.

Grep gates:

- `rg 'test_regression_step|test_step\.dependOn' howl-vt/build.zig`
- `rg 'fuzz_step|baseline_step|test_step\.dependOn' howl-vt/build.zig` supports review that fuzz and benchmark are not pulled into `test`.

Stop conditions:

- Stop if `zig build test:regression` is flaky or exceeds ordinary deterministic test expectations.
- Stop if adding regression to `test` requires changing tests or product code.
