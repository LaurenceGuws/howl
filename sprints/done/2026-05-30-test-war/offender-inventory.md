# Test War Offender Inventory

Date: 2026-05-30

Owner: workspace root accountability first. Package owners execute only promoted slices.

Purpose: source-backed offender inventory for bringing Howl tests to TigerBeetle-entry-bar or better.
Tests are accountability artifacts. No cleanup is accepted unless proof shape, bounds, assertions,
negative space, and build truth improve.

## TigerBeetle Entry Bar

Required readings for every worker/reviewer before touching code:

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`

Applicable pressure:

- Every loop, queue, and scenario needs an explicit bound.
- Assertions must cover arguments, return values, preconditions, postconditions, and invariants.
- Tests must cover positive and negative space, valid data becoming invalid, and exact boundary values.
- Simulation/randomized testing is final defense, not a substitute for a precise mental model encoded in
  deterministic assertions and replayable seeds.
- Test names and comments must say why and how. Broad smoke roots and vague proof claims are failures.

## Research Agents

- Root/build/docs audit: `ses_18665e170ffe7WrXupMmRZe5p6`.
- PTY audit: `ses_18665e0f4ffe9gYgkJ3Z3eJxQC`.
- VT audit: `ses_18665e0ccffe0avJ03m1QOmxTd`.
- Render/host audit: `ses_18665e0b2ffeHdKEsNaHluR4MB`.

## Cross-Repo Severity Summary

### Critical

1. Root verification docs lie about current source.
   - Offenders: `build-test-verification-ledger.md`, `build-test-architecture-spec.md`,
     `build-test-architecture-plan.md`, stale VT regression policy scratchpad.
   - Damage: workers can seed deleted or false surfaces; proof claims no longer bind to source.

2. PTY production FFI imports test helpers.
   - Offenders: `howl-pty/src/ffi.zig`, `howl-pty/src/pty/pty_test.zig`.
   - Damage: shipped ABI translator depends on test-only doubles; FFI no longer translates contracts only.

3. Host and render build roots lie about test coverage.
   - Render constructs a dead `test-render` artifact not wired into canonical steps.
   - Host `test:unit` imports only a small handpicked set while many inline tests live elsewhere.

4. VT simulation/replay accountability is wrong.
   - The old broad `test:regression` bucket was bad, but deleting deterministic replay and leaving only
     `fuzz` language is also bad.
   - TigerBeetle wants deterministic simulation/replay with seeds and explicit invariants, not fake fuzz.

### High

5. ABI proof is weak across PTY, VT, and render.
   - Header structs/enums/functions are not exhaustively proved for size, align, offsets, constants,
     reserved-zero, null/invalid args, short buffers, handle lifecycle, and exported-symbol parity.

6. Runtime/process tests are hidden under unit labels.
   - PTY unit tests spawn `/bin/sh`, sleep, use threads, fork, and depend on OS scheduling.
   - Host integration roots are broad compile/load buckets rather than exact ABI seam proofs.

7. Unit roots are broad, hidden, or too narrow.
   - VT canonical unit root misses snapshot behavior while `terminal.zig` secretly imports it.
   - Render unit root contains only two geometry tests.
   - Host unit root excludes most inline owner tests.
   - PTY unit root aggregates through `libhowl_pty.zig` buckets.

8. Test helpers are ownerless buckets.
   - PTY `ScriptedPty`, `pty_test.zig`.
   - VT `screen_capture.zig`, `stream_harness.zig`, global `encode_scratch`.
   - Host `build_support/host_tests.zig`, broad `test/host.zig`.

9. Host app present extraction is incomplete.
   - `app/present.zig` uses `anytype` seams and unchecked casts.
   - `main.zig` keeps stale wrappers and many app-loop policy tests.

### Medium

10. Weak test names and overclaims remain widespread.
    - Examples: “plumbing”, “handle path”, “remain available”, “method signatures remain host-facing”,
      “sdl mod binding”, “special key binding”.

11. `check` steps often do not compile the proof surface.
    - VT `check` builds only shipped library.
    - PTY `check` does not compile C header consumers.
    - Render/host check semantics need exact artifact reachability review.

12. `test:build` compatibility/convenience remains unresolved.
    - Render keeps `test:build`; spec is not clear whether this is canonical or debt.

## Per-Repo Recovery Order

### Slice 1: Root Truth Reset

Goal: make project memory/docs/current slice stop lying before more workers act.

Files:

- `current.txt`
- `project-memory.md`
- `build-test-architecture-spec.md`
- `build-test-verification-ledger.md`
- `research/2026-05-30-hygiene-audit/build-test-architecture-plan.md`
- `research/2026-05-30-hygiene-audit/vt-regression-gate-policy.md`
- `research/2026-05-30-hygiene-audit/vt-regression-bucket-removal.md`

Required shape:

- Mark stale docs as superseded or rewrite them to current source.
- Remove root `test:regression` as an accepted active category unless a new exact simulation/replay
  policy is promoted.
- Record that `fuzz` is currently a misnamed deterministic simulation harness and must be fixed.
- Close completed `current.txt`; promote only one live slice.

Verification:

- `zig build check`
- `zig build test`
- `git diff --check`
- Grep: no active docs claim root/VT `test:regression` exists.

### Slice 2: VT Simulation Rename And Replay Policy

Goal: replace fake fuzz/regression vocabulary with TigerBeetle-style deterministic simulation shape.

Files:

- `build.zig`
- `howl-vt/build.zig`
- `howl-vt/src/fuzz/fuzz_tests.zig`
- `howl-vt/src/fuzz/protocol.zig`
- `howl-vt/src/fuzz/scrollback.zig`
- possible new path: `howl-vt/test/simulation/main.zig`, `protocol.zig`, `scrollback.zig`

Required shape:

- Rename `fuzz`/`fuzz:build` to exact simulation/replay naming, or create exact named simulation steps.
- Move harness out of product `src/fuzz` unless an accepted package convention says otherwise.
- Keep seeded deterministic replay with explicit bounds and failing-seed promotion policy.
- Add stronger invariants for scrollback/content/history beyond cursor/dimensions.

Verification:

- `howl-vt`: `zig build check`, `zig build test`, simulation build/run gate as named.
- Root matching gate if root aggregate is renamed.
- Grep: no fake `fuzz_tests` or `src/fuzz` if simulation is accepted.

### Slice 3: PTY Test Ownership Split

Goal: remove test helper imports from production and split deterministic unit from owned Unix integration.

Files:

- `howl-pty/build.zig`
- `howl-pty/src/ffi.zig`
- `howl-pty/src/libhowl_pty.zig`
- `howl-pty/src/pty/pty_test.zig`
- `howl-pty/src/test/*.zig`
- `howl-pty/src/pty/posix.zig`

Required shape:

- FFI translates contracts only. No production imports of test doubles.
- Deterministic unit roots exclude `/bin/sh`, fork, sleep, threads, wall-clock PTY.
- Owned Unix PTY tests move to explicit integration step/root.
- Helper doubles become bounded owner-specific proof tools with assertions.

Verification:

- `howl-pty`: `zig build check`, `zig build test`, `zig build test:unit`, `zig build test:abi`,
  explicit PTY integration gate if added.
- Grep: no production `@import` of test helper, no runtime/process APIs in unit roots.

### Slice 4: ABI Proof Matrices

Goal: prove the shipped C ABIs as product.

Packages:

- `howl-pty`
- `howl-vt`
- `howl-render`

Required shape:

- Size, align, field offsets for every public extern struct.
- Enum/constant parity for every public value.
- Reserved fields zero on every output path.
- Null handle, invalid pointer, invalid length, short buffer, limit reached, stale handle, wrong session,
  and consumed-handle cases where applicable.
- C header consumer and exported symbol proof where feasible.

Verification:

- Package `test:abi` gates and `check` compile ABI proof surfaces.

### Slice 5: Host/Render Build Truth

Goal: every constructed test artifact is reachable, and every advertised root states exactly what it proves.

Files:

- `howl-render/build.zig`
- `howl-render/src/test*.zig`
- `howl-linux-host/build.zig`
- `howl-linux-host/src/test*.zig`
- `howl-linux-host/build_support/host_tests.zig`

Required shape:

- Delete or wire render dead `test-render` artifact.
- Decide render `test:build` canonicality.
- Expand or rename host `test:unit`; no hidden partial unit root.
- Delete stale host `test/test_host.zig` if unreferenced.
- Replace broad host integration buckets with exact ABI seam roots.

### Slice 6: Host App Policy Extraction

Goal: finish moving app-loop policy tests out of `main.zig` and harden `app/present.zig`.

Required shape:

- No stale wrappers around `app/present.zig` unless they own real orchestration.
- No unchecked narrowing at present seam.
- No `anytype` structural buckets without explicit asserted contracts.
- Loop admission, wait, redraw/render intent, input forwarding, environment policy each live with exact owner.

## Immediate Recommendation

Promote **Slice 1: Root Truth Reset** first.

Reason:

- The root ledger/spec/current files are now known stale and actively dangerous.
- Any worker seeded from stale docs can recreate the deleted regression bucket or chase nonexistent steps.
- This slice is documentation/build-truth only and unlocks accountable package work.

## Accepted Low-Hanging Cleanup

Completed in the current worktree after this inventory:

- Root `test:regression` active mapping/docs were removed or marked historical.
- VT fake fuzz naming was replaced with deterministic `simulate` / `simulate:build` naming.
- VT simulation files moved from `howl-vt/src/fuzz/` to `howl-vt/src/simulation/`.
- Render dead `test-render` build artifact construction was deleted.
- Host stale unreferenced `howl-linux-host/src/test/test_host.zig` was deleted.

New exposed accountability bug:

- `zig build simulate` reaches the deterministic VT simulation and fails an existing parser assertion at
  `howl-vt/src/parser/main.zig:462` (`self.activeControlCount() == 0`). Treat this as the next
  simulation accountability slice. `simulate:build` is the current non-running compile gate.

## Stop Conditions For All Future Test War Work

- Stop if a proposed test root is a bucket instead of an owner.
- Stop if a build step name says more than it proves.
- Stop if a test deletes slow proof without replacing it with bounded deterministic replay or explicit
  source-backed rejection.
- Stop if helpers use unbounded dynamic storage or unchecked casts without proof.
- Stop if a test claims ABI proof without layout/value/error-path coverage.
