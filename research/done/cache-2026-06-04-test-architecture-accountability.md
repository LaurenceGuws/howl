# 2026-06-04 Test Architecture Accountability

Owner: workspace root.

Purpose: record the current mismatch between Howl test law, current source, and
TigerBeetle test organization before the accountability sprint starts.

## Sources Read

1. `AGENTS.md`
2. `project-memory.md`
3. `build-test-verification-ledger.md`
4. `build.zig`
5. `howl-linux-host/build.zig`
6. `howl-linux-host/src/test/test_entry.zig`
7. `howl-linux-host/src/test_root.zig`
8. `howl-render/build.zig`
9. `howl-render/src/test.zig`
10. `howl-vt/build.zig`
11. `howl-vt/src/howl_vt.zig`
12. `howl-pty/build.zig`
13. `howl-pty/src/libhowl_pty.zig`
14. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
15. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
16. `utils/dev_references/zig_maturity/tigerbeetle/build.zig`
17. `utils/dev_references/zig_maturity/tigerbeetle/src/unit_tests.zig`

## Findings

- Current Howl law says `Each module has one curated test entrypoint`
  (`AGENTS.md:160`).
- That law is contradicted by current Howl source:
  - `howl-linux-host/build.zig:265-312` wires four separate test binaries into
    `test:unit`.
  - `howl-render/build.zig:37-75` wires `test:unit` and `test:abi` to the same
    root, `howl-render/src/test.zig`.
  - `howl-render/src/test.zig:3-9` also exports benchmark `main`, so one root
    currently multiplexes test classes and benchmark wiring.
  - `howl-vt/src/howl_vt.zig:22-46` mixes owner-local tests with `ffi.zig` in
    the `test:unit` root.
  - `howl-pty/build.zig:11-87` already has distinct unit, ABI, and integration
    roots.
- TigerBeetle does not follow the current Howl law either:
  - `utils/dev_references/zig_maturity/tigerbeetle/build.zig:878-995` wires
    multiple curated roots for `test:unit` and `test:integration`.
  - `.../build.zig:1020-1144` also wires explicit JNI, VOPR, and fuzz surfaces.
  - `utils/dev_references/zig_maturity/tigerbeetle/src/unit_tests.zig:1-71`
    aggregates many owner-local and sibling test files into one class root.
  - `.../unit_tests.zig:142-179` includes a quine that checks the curated unit
    import set and explicitly excludes other class roots.

## Current Package Root Map

- `howl-linux-host`
  - `test:unit` aggregate:
    - `src/test/test_entry.zig`
    - `src/terminal/render/retained.zig`
    - `src/display/renderer/render_surface.zig`
    - `src/test_root.zig`
  - `test:integration`:
    - `src/test/integration_entry.zig`
- `howl-render`
  - `test:unit`:
    - `src/test.zig`
  - `test:abi`:
    - `src/test.zig`
  - `benchmark:render`:
    - `src/test.zig`
- `howl-vt`
  - `test:unit`:
    - `src/howl_vt.zig`
  - `test:abi`:
    - `src/test/abi.zig`
- `howl-pty`
  - `test:unit`:
    - `src/libhowl_pty.zig`
  - `test:abi`:
    - `src/test/abi.zig`
  - `test:integration`:
    - `src/libhowl_pty_integration.zig`

## Contradictions That Block Sprint Execution

- Workers and reviewers cannot enforce `AGENTS.md:160-162` honestly because the
  tree already violates it.
- `project-memory.md:376-383` states class ownership, but current roots do not
  keep those classes clean.
- `build-test-verification-ledger.md` contains stale root facts for host,
  render, and PTY, so relying on it would encode false source truth.

## Required Law

- Tests are organized by curated package roots per test class, not by one
  universal module root.
- Owner-local tests may be inline in owner files or in sibling owner-true test
  files, but each test must be reachable through exactly one curated root for
  its class.
- Benchmarks, simulations, stress surfaces, fuzzers, and system scenarios are
  explicit named surfaces. They do not hide inside unit or ABI roots.
- Duplicate roots proving the same class/owner combination are banned.
- Test wiring remains ownership.

## Sprint Readiness

- Ready to start once the governing docs are updated to match the law above and
  the active sprint artifacts point at the corrected contract.
