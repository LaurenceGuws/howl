# VT Regression Bucket Removal

Current correction after the 2026-05-30 test-war audit:

- This file remains the historical source for deleting the broad
  `test:regression` bucket.
- Its acceptance of the remaining `fuzz` name is superseded. Current source still
  exposes that step, but the VT surface is misnamed deterministic
  simulation/replay work and needs a follow-up rename/policy slice.
- This document must not be read as solving deterministic simulation/replay
  accountability.

Date: 2026-05-30

Owner: `howl-vt` build/test taxonomy.

Purpose: remove the broad `test:regression` group. Its contents must move to reference-backed homes or
die.

## Sources Read

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `howl-vt/build.zig`
- `howl-vt/src/test/scrollback_regression.zig`
- `howl-vt/src/test_regression_snapshot.zig`
- `howl-vt/src/test/snapshot_behavior.zig`
- `howl-vt/src/fuzz/scrollback.zig`
- `utils/dev_references/terminals/ghostty/src/terminal/stream.zig`
- `utils/dev_references/terminals/ghostty/test/fuzz-libghostty/build.zig`
- `utils/dev_references/terminals/ghostty/test/fuzz-libghostty/src/fuzz_stream.zig`
- `utils/dev_references/terminals/alacritty/alacritty_terminal/src/term/mod.rs`

## Reference Findings

- Ghostty keeps exact parser/terminal regressions beside the owner as ordinary tests, for example
  `stream: tab clear with overflowing param` in `src/terminal/stream.zig`.
- Ghostty keeps fuzzing in explicit fuzzer build targets under `test/fuzz-libghostty`; it does not keep
  a broad `test:regression` bucket for expensive fuzz replay.
- Alacritty keeps scrollback behavior checks as local unit tests in the terminal owner (`term/mod.rs`),
  with explicit small scenarios such as clearing scrollback and display offsets.
- Neither reference justifies a separate slow `test:regression` build group.

## Howl Inventory

- `howl-vt/src/test_regression_snapshot.zig` was only a wrapper around the snapshot behavior tests.
- `snapshot_behavior.zig` contains ordinary deterministic terminal snapshot unit tests with small grid
  sizes and direct assertions. Its reference-backed home is `test:unit` through the existing internal VT
  test root.
- `howl-vt/src/test/scrollback_regression.zig` replays seeded random churn with large operation counts:
  `1_500`, five times `2_000`, plus canonical preservation default warmup/churn.
- The shared implementation for scrollback churn lives in `howl-vt/src/fuzz/scrollback.zig` and is already
  used by the explicit `fuzz` target. That is the reference-backed home for seeded search/churn logic.

## Decision

- Delete `test:regression` and `test:regression:build` from `howl-vt/build.zig`.
- Delete `howl-vt/src/test/scrollback_regression.zig`.
- Delete `howl-vt/src/test_regression_snapshot.zig`.
- Import `howl-vt/src/test/snapshot_behavior.zig` from the internal unit root so it runs under
  `zig build test:unit` and canonical `zig build test`.
- Keep `howl-vt/src/fuzz/scrollback.zig` and the explicit `fuzz`/`fuzz:build` targets.

## Non-Goals

- Do not create a new slow-test group.
- Do not shrink seeded replay counts to smuggle them into unit tests.
- Do not move fuzz helpers into ordinary unit tests.
- Do not change product behavior.

## Verification

- From `howl-vt`: `zig build check`.
- From `howl-vt`: `zig build test`.
- From `howl-vt`: `zig build test:unit`.
- From `howl-vt`: `zig build fuzz:build`.
- From root: `zig build check`.
- From root: `zig build test`.
- `git diff --check`.

## Grep Gates

- `rg 'test:regression|test_regression|regression' build.zig howl-vt/build.zig howl-vt/src` prints nothing except
  owner-local test names/comments if any exact unit test intentionally uses the word.
- `rg 'scrollback_regression|test_regression_snapshot' howl-vt` prints nothing.
- `rg 'snapshot_behavior' howl-vt/src/terminal.zig` proves snapshot tests are in the unit root.

## Stop Conditions

- Stop if snapshot tests are too slow for canonical `test:unit`.
- Stop if deleting scrollback replay removes the only explicit fuzz target build for scrollback churn.
