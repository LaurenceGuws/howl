# Useless LOC Sprint Scope

Owner: workspace root.

Purpose:

- Define the full, auditable sprint to remove useless LOC across Howl before more implementation work.
- Keep the sprint broad and explicit: dead code, duplication, unnecessary deep abstractions, owner-false boundaries, and production/test mixing are all in scope.
- No production-code changes should start from this sprint without first fitting into this scope.

Accepted inputs:

- `AGENTS.md`
- `loop.txt`
- `reference-index.md`
- `project-memory.md`
- `./style.nu ./howl-* -s prod --by-file`
- TigerBeetle readings:
  - `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
  - `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`

User direction:

- Howl is much younger than Alacritty but already has roughly double the LOC.
- The gap is presumed to be mostly dead code, duplication, and unnecessary deep abstractions.
- We want small, concise, pragmatic code.
- The sole sprint focus is making production code smaller, more pragmatic, more intentional.
- Files, folders, and owners should be as shallow as possible while still surviving TigerBeetle gates and idiomatic Zig naming.
- Cast at the source, then keep datatypes consistent through the pipeline; repeated downstream casts are presumed waste and should be removed when owner-truth permits.
- Prefer direct owner datatypes over redefining dependent-repo shapes locally when the product boundary does not require a local copy.
- Zig module shaping is debt when only the C ABI product surface is needed.
- Production code should be clearly separated from everything around it.
- Test-heavy is acceptable, but if code exists only for tests it should move away from real production owners or be deleted.
- The sprint is not a maybe-here-maybe-there cleanup. Everything is in scope.
- The sprint must be sequential, planned, auditable work.
- Research and English scope documentation come first. No production edits should start the sprint without the documented full scope.

Sprint definition:

- This sprint removes useless LOC repository-wide.
- Nothing in the categories below is treated as out of scope.
- The sprint is complete only when every item below has been either:
  - removed,
  - merged into a smaller true owner,
  - moved out of production ownership when it exists only for tests or harnesses,
  - or explicitly recorded as a source-backed keeper with evidence.

In-scope debt classes:

1. Dead code.
   - Unused wrappers.
   - Unused re-export layers.
   - Trampoline files that only forward one symbol with no ownership value.
   - Helper code that no call site needs anymore.

2. Duplicated logic.
   - Repeated constructor families.
   - Repeated build-step plumbing.
   - Repeated test aggregation.
   - Repeated policy calculation across owners.

3. Unnecessary deep abstractions.
   - Namespace wrappers that do not own state or mutation.
   - Convenience umbrella files that only add import hops.
   - Multi-step indirection for test roots or build wiring when one direct owner path is enough.

4. Production/test mixing debt.
   - Large production files carrying inline test blocks, fake types, test harness state, or test-only helpers.
   - Benchmark or simulation code living under `src/test` when it is not a proof surface.
   - Product roots acting as test aggregators when a sibling or curated root can own the proof lane.

5. Owner-false file boundaries.
   - Files that coordinate too many unrelated responsibilities.
   - Files whose imports already reveal smaller real owners that should exist separately.
   - Files whose names are ownership-neutral buckets rather than real owners.

6. Type and cast churn.
   - Repeated casts through a pipeline instead of casting once at the true boundary.
   - Local datatype mirrors where the real owner datatype can flow directly.
   - Zig-shaped module surfaces where the ABI boundary already owns the contract.

Repository-wide findings to preserve:

## Confirmed dead wrapper candidates

- `howl-linux-host/src/terminal/texture.zig`
  - one-line alias to `display/renderer/render_surface.zig`
  - no inbound imports found
- `howl-linux-host/src/window_chrome.zig`
  - re-export wrapper only
  - no inbound imports found
- `howl-linux-host/src/display.zig`
  - re-export wrapper only
  - no inbound imports found
- `howl-linux-host/src/display/renderer.zig`
  - re-export wrapper only
  - no inbound imports found

## Confirmed duplicated logic clusters

- `howl-vt/src/terminal.zig`
- `howl-vt/src/howl_vt.zig`
  - overlapping test aggregation through two roots

- `howl-vt/src/terminal.zig`
  - repeated terminal init families

- `howl-vt/src/screen.zig`
  - repeated screen init families

- `howl-pty/build.zig`
- `howl-vt/build.zig`
- `howl-render/build.zig`
- `howl-linux-host/build.zig`
  - repeated package step plumbing

## Confirmed deep abstraction debt

- `howl-linux-host/build_support/host_tests.zig`
- `howl-linux-host/src/host_test_root.zig`
- `howl-linux-host/src/integration_test_root.zig`
  - stacked host test indirection

- `howl-render/src/text/text.zig`
  - broad umbrella facade over many real owners

- `howl-linux-host/src/display.zig`
- `howl-linux-host/src/display/renderer.zig`
- `howl-linux-host/src/window_chrome.zig`
  - namespace wrappers only

## Confirmed production/test mixing debt

- `howl-linux-host/src/terminal/context.zig`
  - large inline test region with fake types and test-only helpers
- `howl-linux-host/src/main.zig`
  - large inline test region with fake tabs and app-loop proofs
- `howl-linux-host/src/display/renderer/render_surface.zig`
  - large inline renderer proof region mixed into production owner
- `howl-render/src/prepared/render_surface_emitter.zig`
  - heavy inline tests inside production owner
- `howl-render/src/prepared/owner.zig`
  - heavy inline tests inside production owner
- `howl-render/src/session/text.zig`
  - heavy inline tests inside production owner
- `howl-pty/src/pty/posix.zig`
  - inline tests inside production transport owner
- `howl-render/src/benchmark_main.zig`
- `howl-render/src/test/benchmark.zig`
  - benchmark split still routes through `src/test`

## Confirmed owner-false boundaries

- `howl-linux-host/src/terminal/context.zig`
  - one owner currently coordinates PTY lifecycle, wait-thread state, render surface state, geometry, links, selection, cursor blink, title sync, and host interaction policy
- `howl-render/src/text/text.zig`
  - umbrella facade, not a real owner
- `howl-linux-host/src/host_test_root.zig`
  - broad host test bucket, not a real owner

Additional current evidence from the prod style report:

- Highest pure production LOC concentrations remain in:
  - `howl-render/src/text/raster/special.zig`
  - `howl-linux-host/src/terminal/context.zig`
  - `howl-linux-host/src/display/renderer/render_surface.zig`
  - `howl-render/src/render/render_surface_realizer.zig`
  - `howl-render/src/prepared/render_surface_emitter.zig`
  - `howl-render/src/text/scene.zig`
  - `howl-linux-host/src/main.zig`
  - `howl-vt/src/parser/string_control.zig`
  - `howl-vt/src/parser/events.zig`
  - `howl-vt/src/parser/main.zig`

Sprint sequence:

This sprint is sequential. The order below is the execution order. None of these categories is optional.

1. Delete confirmed dead wrappers and dead re-export layers.
   - `howl-linux-host/src/terminal/texture.zig`
   - `howl-linux-host/src/window_chrome.zig`
   - `howl-linux-host/src/display.zig`
   - `howl-linux-host/src/display/renderer.zig`

2. Remove host test-root indirection that exists only to point at other roots.
   - `howl-linux-host/build_support/host_tests.zig`
   - `howl-linux-host/src/host_test_root.zig`
   - `howl-linux-host/src/integration_test_root.zig`
   - fold test-root selection directly into `howl-linux-host/build.zig`

3. Remove `src/test` benchmark ownership from render.
   - move `howl-render/src/test/benchmark.zig` to a non-test owner path
   - simplify or delete trampoline behavior in `howl-render/src/benchmark_main.zig`

4. Remove duplicated VT test aggregation.
   - keep one curated VT unit root
   - stop importing overlapping `_test.zig` files from both:
     - `howl-vt/src/terminal.zig`
     - `howl-vt/src/howl_vt.zig`

5. Remove inline test/fake scaffolding from the largest polluted production owners.
   - `howl-linux-host/src/terminal/context.zig`
   - `howl-linux-host/src/main.zig`
   - `howl-linux-host/src/display/renderer/render_surface.zig`
   - `howl-render/src/prepared/render_surface_emitter.zig`
   - `howl-render/src/prepared/owner.zig`
   - `howl-render/src/session/text.zig`
   - `howl-pty/src/pty/posix.zig`

6. Delete convenience umbrella layers that add no owner truth.
   - `howl-render/src/text/text.zig`
   - update all call sites to direct owner imports

7. Split owner-false buckets whose imports already reveal the real seams.
   - `howl-linux-host/src/terminal/context.zig`
   - split by actual owner seams already visible in source:
     - PTY runtime/progress
     - retained render submission
     - layout/resize
     - title sync
     - overlay/scrollbar
     - link/selection interaction
     - cursor blink activity

8. Deduplicate repeated constructor families.
   - `howl-vt/src/terminal.zig`
   - `howl-vt/src/screen.zig`

9. Deduplicate repeated package build plumbing after test-root and owner cleanup settles.
   - `howl-pty/build.zig`
   - `howl-vt/build.zig`
   - `howl-render/build.zig`
   - `howl-linux-host/build.zig`

10. Audit the remaining top prod-LOC files one by one for dead branches, repeated tables, repeated switch ladders, and keeper-vs-debt proof.
   - start from the current style report top list
   - every file must be marked as either:
     - reduced now,
     - reduced by a preceding structural cut,
     - or explicitly justified as remaining necessary complexity

Audit rules during implementation:

- No production edits without a promoted slice from this scope.
- No “acceptable for now” wrappers if the file does not own state or mutation.
- No test-only helpers left in production owners.
- No benchmark or simulation code hidden behind proof paths.
- Every kept abstraction must answer: what exact owner truth does this file preserve that direct imports would not?
- Material-yield bar:
  - reject micro-cuts that only remove a handful of lines unless they unlock a broader accepted cut immediately
  - for top prod files, prefer either a meaningful reduction or an explicit keeper verdict recorded quickly
- Cast discipline:
  - cast once at the narrowest true source boundary, then keep the datatype stable through the rest of the pipeline
  - repeated cast ladders and owner-false local type mirrors are presumed debt until proved necessary by ABI or product boundaries

Completion criteria:

- Confirmed dead wrappers are deleted.
- No production owner contains fake types or helpers that exist only for tests.
- No broad convenience namespace file remains without source-backed owner truth.
- VT test aggregation is singular and non-duplicated.
- Render benchmark code no longer lives under `src/test`.
- Host terminal context is no longer a giant owner-false bucket.
- The build files no longer repeat avoidable step-plumbing patterns.
- The top prod-LOC report is materially smaller and every remaining large file has an explicit keeper rationale.
- Workspace verification passes after each accepted slice and at sprint close:
  - `zig build test`
  - `zig build check`

Stop conditions:

- Stop if a proposed deletion changes the shipped C ABI or product consequences.
- Stop if a proposed split needs new owner vocabulary not already evidenced by current imports, references, or product boundaries.
- Stop if a candidate “abstraction” turns out to be the only current place preserving a real invariant, and that invariant has not yet been reassigned to a true owner.
