# Sprint: Resize Shape And State-Machine Proof

Date: 2026-06-01

Owner: orchestrator

Status: planning

## Accepted Caches

- `research/cache-2026-06-01-resize-flow-alacritty.md`
- `research/cache-2026-06-01-resize-test-invariants-review.md`

## User Direction

- Clone Alacritty's resize shape first.
- Then define and add state-machine test cases that prove the intended shape.
- Stop doing coding work without orchestration accountability.
- KISS, DRY, idiomatic shallow ownership is mandated.
- Do not dance around current missing ownership or missing tests when they appear.

## Problem

Resize currently reaches render-surface submit without an end-to-end proof of ownership, sequencing, retained-base validity, host texture validity, and present ack. Runtime logs showed repeated `glyph_failure` after resize with `resource_plan_status=ok`, indicating the current code and tests do not prove the resize-to-present state machine.

## Accepted Shape To Clone From Alacritty

Alacritty source shape:

- Resize events record pending display state; they do not directly perform GL work.
- Display update applies size changes, terminal/PTTY resize, damage, and queued renderer resize.
- Renderer/GL resize is processed immediately before draw.
- Draw uses the current size info.

Howl shape, respecting the C ABI/render-surface boundary:

- Host input/event owner records resize and host geometry changes.
- Display/window owners own pixel/logical geometry and present cadence.
- `terminal/render/surface_layout.zig` owns terminal geometry commit through C ABI, including PTY/VT resize delivery and render geometry sync.
- `howl-render` owns geometry epoch, retained prepare/submit validity, full/partial damage classification, and render-surface contracts.
- `display/renderer/render_surface.zig` owns host GL resource realization and host terminal texture lifecycle.
- `app/present.zig` owns present reason, present token routing, and ack cadence.

Howl-specific invariant forced by the embeddable render-surface boundary:

- After any resize that invalidates the host terminal texture dimensions, the next accepted render surface must either be full/retained-safe or patch upload must be rejected until a matching retained host surface exists.

## Non-Goals

- No behavior fix before a state-machine proof slice is accepted.
- No broad runtime, manager, controller, engine, chrome, UI, overlay, or utility owner.
- No Zig-shaped host shortcut around the C ABI.
- No public ABI change in the test-harness slice.
- No duplicate test roots or side-entry tests.
- No diagnostics-only fake progress.

## Cut 1: Alacritty Shape Contract Review

Owner: orchestrator + reviewer, no worker implementation.

Purpose: promote a reviewer-accepted contract for how Howl maps Alacritty's resize shape into the C ABI render-surface architecture.

Allowed files:

- `research/2026-06-01-resize-shape-test-sprint.md`
- `current.txt`

Required decisions:

- State whether geometry commit belongs in `terminal/render/surface_layout.zig` for this sprint.
- State whether host texture validity remains in `display/renderer/render_surface.zig`.
- State whether full/partial damage validity belongs in `howl-render/src/source/prepare_request.zig` / retained prepare owners.
- State whether present ack proof remains in `app/present.zig` and `terminal/context.zig` tests.

Reviewer gates:

- Alacritty comparison is present and source-backed.
- Howl-only differences are explained by C ABI/render-surface boundary.
- No worker is asked to invent owner names, paths, or policy.

## Cut 2: Deterministic Resize Success State-Machine Test Harness

Owner: worker only after Cut 1 is reviewed and `current.txt` contains an exact contract.

Purpose: add one deterministic test path proving resize -> geometry sync -> prepare -> render surface token -> host upload decision -> submit -> present -> ack.

Likely allowed files, to be narrowed in `current.txt` after reviewer acceptance:

- `howl-linux-host/src/terminal/context.zig`
- `howl-linux-host/src/terminal/render/surface_layout.zig`
- `howl-linux-host/src/terminal/render/retained.zig`
- `howl-linux-host/src/app/present.zig`
- `howl-linux-host/src/display/renderer/render_surface.zig`
- `howl-render/src/source/prepare_request.zig` only if the proof must assert source classification directly through existing module tests.

Required proof path:

- Start from a clean terminal/render state with known geometry.
- Apply a resize that changes render surface dimensions.
- Commit geometry exactly once.
- Observe a non-zero geometry epoch.
- Produce or model one prepared surface for the new geometry.
- Verify render surface token and prepared info agree.
- Verify host surface dimensions equal prepared/render-surface dimensions.
- Verify upload succeeds only for a full/retained-safe surface after texture-size invalidation.
- Submit and record a non-zero snapshot.
- Submit display present for `.terminal_frame`.
- Verify present pending blocks a second submit.
- Verify wrong present token does not ack.
- Verify matching present token acks exactly the submitted snapshot.
- Verify pending state clears after ack.

Required assertions:

- Geometry epoch increments exactly once for the resize.
- PTY/VT resize delivery is called once when grid changes.
- Prepared token, render surface token, host submit decision, and ack snapshot use the same geometry/snapshot lineage.
- No patch surface is accepted on a newly allocated or size-invalidated host terminal texture.
- Debug counters match actual path events: prepare/probe/resource/upload/present/ack success and zero failure counters.
- Bounds are explicit for all dimension conversions into `u16` render ABI dimensions.

Test shape constraints:

- Use existing module test entrypoints only.
- Use deterministic fakes, not SDL/OpenGL runtime.
- Keep fakes owner-local and small; no generic bucket state.
- Fakes must record ordered state transitions, not just return booleans.

Stop conditions:

- Stop if the harness needs a new runtime/controller/manager abstraction.
- Stop if deterministic tests require host imports of internal `howl-render` Zig modules outside existing module ownership.
- Stop if the first test can only prove isolated helpers rather than the resize-to-present state machine.
- Stop if `resource_epoch` must become meaningful before the success path can be honestly asserted.
- Stop if the test needs a duplicate root or weakened gates.

## Cut 3: Resize Stale/Failure State-Machine Tests

Owner: worker only after Cut 2 is accepted and committed.

Purpose: prove negative space after the success path exists.

Candidate tests:

- Resize after prepare before submit: stale prepared handle must not submit; next prepare must be full/new-geometry.
- Resize while present pending: submit is blocked until matching ack; wrong token leaves state blocked.
- Host surface creation failure: width/height truth remains zero; no submit; counters record failure.
- Resource realization failure: no host upload; resource state rolls back or retires according to owner contract.
- Host upload failure after realization: no submit; retained state does not silently advance; retry path can recover with a valid full frame.
- Partial frame on changed host surface: rejected or converted to full before upload.

Stop conditions:

- Stop if a failure test encodes current broken behavior as expected behavior.
- Stop if a fake bypasses the C ABI consequence being tested.
- Stop if counters are asserted without proving the path event occurred.

## Cut 4: Behavior Fix Only After Tests Prove The Contract

Owner: worker only after tests expose the exact failing invariant.

Possible fix areas, not authorized yet:

- Force full prepare/source publication on geometry epoch changes that invalidate retained host texture state.
- Tighten patch upload gate so all patch classes require a matching retained host surface.
- Clarify or implement `resource_epoch` semantics if tests prove it is required.

Stop conditions:

- Stop if fixing requires public ABI change without an explicit ABI slice.
- Stop if fixing requires broad presentation/runtime redesign.
- Stop if the failure bucket is actually GL/context readiness rather than retained geometry/patch invalidation.

## Verification Gates For Worker Slices

From `howl-linux-host` when host files change:

- `zig build check`
- `zig build test --summary all`
- `zig build -Doptimize=ReleaseFast`
- `git diff --check`

From workspace root when root or submodule pointers change:

- `./status.sh`

Line gate:

- Changed Zig files must have zero lines over 190 chars.

Reviewer gates:

- Product code changes require reviewer acceptance.
- Test-only slices still require reviewer acceptance because they define product invariants.
- Commits happen only after verification and reviewer acceptance.

## Signoff

- Research cache accepted: yes.
- Reviewer cache accepted: yes.
- Scratchpad reviewer status: pending.
- Current active cut: Cut 1, Alacritty shape contract review.
- Implementation status: not started.
