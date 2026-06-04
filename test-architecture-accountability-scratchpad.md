# Test Architecture Accountability Sprint

Owner: workspace root.

Accepted research:

- `research/cache-2026-06-04-test-architecture-accountability.md`

User direction:

- Accountability is the bare minimum.
- Style breaches are not cosmetic; they hide ownership, dead code, and
  undefined behavior.
- Honest explicit gaps are preferable to vague or unproven behavior.
- Sprint work must be fully researched, explicitly scoped, and completed
  sequentially.

Decisions:

- Howl test law follows curated package roots by test class, not a single
  module-wide test entrypoint rule.
- Benchmarks, simulations, stress surfaces, fuzzers, and similar non-proof
  surfaces must stay explicit and must not multiplex with unit or ABI roots.
- Owner-local tests may be inline in owner files or in sibling owner-true test
  files, but each test must be reached through exactly one curated root for its
  class.
- Duplicate roots proving the same owner/class combination are banned.

Non-goals:

- No product feature work.
- No opportunistic cleanup outside test architecture and proof wiring.
- No compatibility wrappers preserved just to avoid moving tests.

Sprint cuts:

1. Governing law and inventory documents.
   - Files:
     - `AGENTS.md`
     - `project-memory.md`
     - `build-test-verification-ledger.md`
     - `current.txt`
     - `test-architecture-accountability-scratchpad.md`
   - Outcome:
     - governing law corrected
     - current source inventory corrected
     - active slice promoted
2. Package-by-package root classification and target map.
   - Files:
     - package `build.zig` files
     - root test files in `howl-linux-host`, `howl-render`, `howl-vt`,
       `howl-pty`
   - Outcome:
     - one explicit target map for each package/test class
     - benchmark/test and ABI/unit mixing called out before edits
   - Accepted target map:
     - `howl-linux-host`
       - keep `test:unit` as an explicit class aggregate over four package-owned
         roots because current build already wires four distinct owner/class
         proofs with no benchmark or ABI mixing
       - keep `test:integration` explicit
      - `howl-render`
        - split the old shared render test root into dedicated roots:
          - `src/test_unit.zig`
          - `src/test_abi.zig`
          - `src/benchmark_main.zig`
       - keep `src/test/unit/root.zig`, `src/test/ffi.zig`, and
         `src/test/benchmark.zig` as owner-true subordinate imports
     - `howl-vt`
       - keep `src/howl_vt.zig` as the unit root
       - remove `ffi.zig` from the unit root so `test:abi` remains the only ABI
         class root
     - `howl-pty`
       - keep `src/libhowl_pty.zig`, `src/test/abi.zig`, and
         `src/libhowl_pty_integration.zig` as explicit class roots unless a
         later verification finding proves ownership duplication
3. Wiring reshape.
    - Files:
      - `build.zig`
      - `howl-render/build.zig`
      - `howl-render/src/test_unit.zig`
      - `howl-render/src/test_abi.zig`
      - `howl-render/src/benchmark_main.zig`
      - `howl-vt/src/howl_vt.zig`
    - Outcome:
      - class roots and imports obey the corrected law
    - Status:
      - completed for `howl-render`, `howl-vt`, and workspace root integration
        wording
4. Verification and closeout.
    - Outcome:
      - package gates rerun
      - durable memory updated
      - no stale doc law remains active
    - Remaining closeout:
      - rerun benchmark build for render
      - rerun workspace `check`
      - update durable memory with the completed source shape

Stop conditions:

- Stop if a package needs a new public test class not already justified by
  TigerBeetle pressure or current product boundary.
- Stop if a package root cannot be classified without inventing new ownership
  vocabulary.
- Stop if current code forces a product-direction choice that the sources do not
  answer.

Verification gates for the sprint:

- Workspace: `zig build check`, `zig build test`
- Package gates as affected by each cut

Completion criteria:

- Governing docs and current source agree on the test law.
- Each package root is classified by test class with explicit ownership.
- Mixed-class roots are either removed or deliberately replaced under the new
  law.
- Ledger and sprint memory match the final source tree.

Verification results:

- `howl-render`: `zig build test` passed.
- `howl-render`: `zig build benchmark:render:build` passed.
- `howl-vt`: `zig build test` passed.
- workspace: `zig build test:integration` passed.
- workspace: `zig build check` passed.
- workspace: `zig build test` passed on rerun.
- note: the first workspace `zig build test` hit a PTY integration timeout in
  `howl-pty/src/test/session_integration.zig`; package reruns and the final
  workspace rerun passed, so this remains a flaky-gate risk rather than a
  proven sprint regression.

Signoff:

- Governing law corrected in `AGENTS.md` and `project-memory.md`.
- Current source inventory corrected in `build-test-verification-ledger.md`.
- Render unit, ABI, and benchmark roots are now explicit and separate.
- VT unit root no longer imports `ffi.zig`.
- Workspace integration wording now matches current package ownership.
