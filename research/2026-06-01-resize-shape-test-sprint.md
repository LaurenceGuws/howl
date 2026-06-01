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
- Howl's equivalent of Alacritty's renderer/GL resize immediately before draw is: host texture validity is checked or recreated after geometry/prepare and before present, inside the host submit/upload boundary. It must never happen directly in event handling or terminal geometry commit.

## Cut 1 Decisions

- Geometry commit belongs in `howl-linux-host/src/terminal/render/surface_layout.zig` for this sprint.
- Host texture validity and lifecycle belong in `howl-linux-host/src/display/renderer/render_surface.zig`.
- Geometry epoch and full/partial retained-safety classification belong in `howl-render`, with Cut 2 proof anchored first in `howl-render/src/source/prepare_request.zig`.
- Present token routing and ack proof belong in `howl-linux-host/src/app/present.zig` and `howl-linux-host/src/terminal/context.zig` tests.
- Host orchestration glue may be asserted in `howl-linux-host/src/terminal/context.zig`, but it must not absorb display renderer, C ABI render, PTY, or VT ownership.

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

## Cut 2A: Render-Side Resize Retained-Safety Proof

Owner: worker only after Cut 1 is reviewed and `current.txt` contains an exact contract.

Purpose: prove the first retained-safety invariant before any host resize/upload harness exists: a geometry epoch change cannot be dropped as `.none` solely because VT source content is otherwise identical.

Allowed files for the first promotable test slice:

- `howl-render/src/source/prepare_request.zig`

Exact test entrypoint:

- Curated root: `howl-render/src/test.zig`.
- Verification command from `howl-render`: `zig build test --summary all`.
- Owner-local tests may be added to `howl-render/src/source/prepare_request.zig` only if they are reached through `src/test.zig`; no new test root.

Exact first proof:

- Prove that a geometry epoch change with otherwise identical VT publication source does not classify as `.none` and cannot leave the next prepared surface relying on a stale retained host base.
- Use a small owner-local fake `PublicationSource` built through existing source test helpers in `howl-render/src/source/prepare_request.zig`; do not create a new test root or host fake runtime.
- The test must drive `PrepareRequests.acceptSource(...)` and `PrepareRequests.takePrepareRequest(...)`, not just call a helper classifier directly.

Non-goal for this first promotable slice:

- Do not drive `Context.renderTurn()`, host GL upload, or present ack yet. Those are later slices after the render-side retained-safety classification is proved.

Required first-slice proof path:

- Construct a prior published source and accept it at geometry epoch `1`.
- Construct a new source with the same cells/dirty metadata but pass geometry epoch `2`.
- Assert the new publication is queued when geometry changed, even if source content is otherwise equal.
- Assert `takePrepareRequest(2, submitted_token)` returns a request with `geometry_epoch == 2`.
- Assert the request is full/retained-safe: `damage_kind == .full`, `damage_base_seq == 0`, and `allow_retained_reuse == false` if geometry invalidates retained base.
- Assert a second identical source at geometry epoch `2`, after the full geometry-safe request has been taken and no newer submitted token exists, returns `published == false`, `queued == false`, and `damage_kind == .none` only if the active source already represents the same snapshot/content at geometry epoch `2`.

Required assertions:

- Geometry epoch is part of publication/prepare safety, not decorative metadata.
- Geometry-changed publication cannot be dropped as `.none` solely because VT cells match.
- Retained-base reuse is disabled across geometry changes unless the submitted retained base has the same geometry epoch and snapshot base.
- Damage kind is full when geometry changes without a safe retained base.

Test shape constraints:

- Use existing module test entrypoints only.
- Use deterministic fakes, not SDL/OpenGL runtime.
- Keep fakes owner-local and small; no generic bucket state.
- Fakes must record ordered state transitions, not just return booleans.

Stop conditions:

- Stop if the harness needs a new runtime/controller/manager abstraction.
- Stop if deterministic tests require host imports of internal `howl-render` Zig modules outside existing module ownership.
- Stop if the test calls only helper classification instead of driving `PrepareRequests.acceptSource(...)` and `PrepareRequests.takePrepareRequest(...)`.
- Stop if `resource_epoch` must become meaningful before the success path can be honestly asserted.
- Stop if the test needs a duplicate root or weakened gates.

## Cut 2B: Deterministic Resize Success State-Machine Test Harness

Owner: worker only after a fresh reviewer-accepted `current.txt` names this exact host test slice.

Purpose: add one deterministic host-level success-path test proving resize -> geometry sync -> prepare -> render surface token -> host upload decision -> submit -> present -> ack. This is the next planned resize harness cut; it is not a new research branch and it must not authorize opportunistic presentation/runtime redesign.

Allowed files for the promotable test slice:

- `howl-linux-host/src/terminal/context.zig`
- `howl-linux-host/src/test/host.zig` only if the existing terminal context test root fails to import the owner-local test.
- `howl-linux-host/src/test_root.zig` only if the existing terminal context test root fails to import the owner-local test.

Exact test entrypoint:

- Build wiring root: `howl-linux-host/src/test_root.zig`, through `terminalContextTestModule(...)` in `howl-linux-host/build.zig`.
- Owner-local test location: `howl-linux-host/src/terminal/context.zig`.
- Verification command from `howl-linux-host`: `zig build test:unit --summary all` for this cut's narrow gate, then full host gates before acceptance.
- No new test root, no side-entry test file, no build-step split.

Required fake shape:

- Use a single owner-local test harness in `terminal/context.zig`, near existing submit/present tests.
- Reuse or extend the existing owner-local fake seams already present in `terminal/context.zig`: `TestSubmitContext`, `TestSubmitTerm`, `TestSubmitRender`, and `submitPreparedLockedWith(...)`.
- The fake terminal/render object must record ordered transitions as explicit fields or a fixed-size operation array with bounded count. It must not be a generic `Context`, `State`, `Options`, `Diagnostics`, or `Manager` bucket.
- The fake backend must model the host upload decision at the submit boundary: it receives a prepared upload, records whether the previous host surface matched, records prepared/render-surface dimensions, returns a host surface with matching dimensions on success, and refuses to submit if upload fails.
- The fake present owner must use `app/present.zig` semantics: submit `.terminal_frame`, store one pending token, reject wrong completion, accept matching completion exactly once.
- Do not fake SDL events or GL. The test begins after host-owned resize intent has reached `Context.resize(...)`/terminal render orchestration, matching the existing planned state-machine harness scope.

Required success-path proof:

- Start from a clean terminal/render state with known geometry and no present pending.
- Apply one resize that changes render surface dimensions.
- Commit geometry once through the same terminal/render owner path that production uses for render turns; do not call `howl-render` internal Zig modules from host tests.
- Observe a non-zero geometry epoch after geometry sync.
- Prepare one surface for the new geometry.
- Assert prepared info has non-zero `snapshot_seq`, non-zero `dirty_epoch`/surface sequence where applicable, and `geometry_epoch` equal to the host retained geometry epoch.
- Assert the emitted render surface token has `snapshot_seq`, `surface_seq`, and `geometry_epoch` equal to the prepared info.
- Assert the render surface dimensions and host surface dimensions equal the resized render dimensions.
- Assert the first uploaded surface after host texture-size invalidation is full/retained-safe, or the host upload decision rejects it before render submit. For this success-path cut, the accepted path must be full/retained-safe and must submit.
- Submit once and assert the submitted snapshot is non-zero and equals the prepared/render-surface snapshot.
- Submit display present for `.terminal_frame`, record exactly one host-owned present token, and mark retained present pending.
- Assert a second submit while present is pending is blocked.
- Drain a wrong present token and assert no ack, no snapshot completion, and pending state remains.
- Drain the matching present token and assert exactly the submitted snapshot is acked once and pending state clears.

Required assertions:

- Geometry epoch is a state-machine transition shared by host retained state, prepared info, render surface token, and submit result.
- Host upload success is the only path that allows render submit to advance retained state.
- Host surface dimensions are truth after upload; stale dimensions may not be presented as terminal success.
- Present pending blocks submit until matching host token completion.
- Wrong host present token cannot ack or clear terminal retained state.
- Matching host present token acks exactly once.

Non-goals for this cut:

- Do not implement Cut 3 failure cases.
- Do not change product behavior unless the worker hits a stop condition and returns the exact missing invariant.
- Do not redesign `app/present.zig`, `display/display.zig`, event loop pacing, SDL handling, GL texture ownership, or render ABI semantics.
- Do not add public C ABI.
- Do not add diagnostics-only logging or temporary debugging as proof.
- Do not import internal `howl-render` Zig modules from the host test; use the shipped C ABI and existing host owner seams.

Stop conditions:

- Stop if the harness needs a new runtime/controller/manager abstraction.
- Stop if deterministic tests require host imports of internal `howl-render` Zig modules outside the C ABI boundary.
- Stop if the test can only prove isolated helpers rather than the resize-to-present state machine.
- Stop if the test needs a duplicate root or weakened gates.
- Stop if the existing fake seams in `terminal/context.zig` cannot honestly drive geometry -> prepare -> upload -> submit -> present -> ack without product behavior changes.
- Stop if the success path exposes that current behavior fails before present ack; return the exact transition, observed state, and smallest owner where the structural fix belongs.
- Stop if `resource_epoch` must become meaningful before the success path can be honestly asserted; record whether it is intentionally zero/ignored or requires a later ABI/product slice.

## Cut 3: Resize Stale/Failure State-Machine Tests

Owner: planning only. Not promotable until each failure case has a fresh reviewer-accepted `current.txt` with exact files, exact test entrypoint, and exact invariants.

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

Owner: planning only. Not promotable until tests expose the exact failing invariant and a fresh reviewer-accepted `current.txt` narrows files and behavior.

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
- Scratchpad reviewer status: accepted.
- Current active cut: Cut 2B, deterministic resize success state-machine test harness.
- Cut 2A implementation status: accepted and pushed in `howl-render` commit `300b4de`.
- Cut 2B implementation status: accepted and pushed in `howl-linux-host` commit `09b1651`.
- Verification status: passed: `zig build test:unit --summary all`, `zig build check`, `zig build test --summary all`, `zig build -Doptimize=ReleaseFast`, `git diff --check`, changed-file line scan.
