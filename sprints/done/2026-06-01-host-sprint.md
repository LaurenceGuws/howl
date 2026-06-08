# Sprint: Linux Host Ownership And Failure Policy

Accepted research caches:

- `research/cache-2026-06-01-host-owner-inventory.md`
- `research/cache-2026-06-01-host-reference-shape.md`
- `research/cache-2026-06-01-host-failure-policy.md`

## Decision

The Linux host is not uniformly stale. It has maintained owner islands with tests, but the host boundary is structurally risky in three places:

- Owner-inventory cache: `terminal/context.zig` is a god aggregate for terminal lifecycle, input routing, render upload, diagnostics, clipboard/title/focus, selection/link/scrollbar, and cursor blink.
- Owner-inventory cache: `window/term_texture.zig` and `terminal/render/retained.zig` duplicate render-surface/resource validation responsibility.
- Failure-policy cache: failure handling mixes unclassified ABI/programmer invariant candidates, GL/backend operating-error candidates, unsupported host-feature candidates, and temporary diagnostics behind counters and boolean returns.

The failure-policy cache is not ready for broad failure-handling implementation planning. It is ready only for a proof-first classification step around the render-surface trust boundary. The owner-inventory and host-reference caches independently support planning for host owner-boundary research. The owner-inventory cache supports integration-test truth research.

## Non-Goals

- No product code changes from this scratchpad alone.
- No render-surface failure-policy refactor before render-surface failure classes are classified.
- No renaming, moving, or deleting host owners until the target owner and boundaries are source-backed.
- No changes to `howl-render`, `howl-vt`, or `howl-pty` in the host cleanup slices unless a separate ABI-product slice is promoted.
- No compatibility shims, aliases, umbrella runtime, manager, engine, controller, or generic `utils` owner.
- No weakening tests or treating import-only integration tests as behavioral proof.

## Orchestration Rule

- If a researcher, worker, or reviewer finds that the seed leaves ownership, naming, scope, test gates, or ABI consequences for them to design, they must stop and report that orchestration is needed.
- Subagents must not silently fill design gaps, broaden scope, choose new owner names, or turn an ambiguous path into implementation.
- The main agent owns converting accepted research into a scratchpad and `current.txt`; workers only implement accepted slices.

## Lane A Slice 1: Render-Surface Trust Boundary Classification

Owner: research, not implementation.

Purpose: classify every current render-surface host failure bucket before changing failure behavior.

Allowed source paths for research:

- `howl-render/include/howl_render.h`
- `howl-render/src/prepared/owner.zig`
- `howl-render/src/prepared/render_surface_emitter.zig`
- `howl-render/src/ffi/prepared_surface.zig`
- `howl-render/src/ffi/render_surface.zig`
- `howl-render/src/test/**`
- `howl-linux-host/src/terminal/render/retained.zig`
- `howl-linux-host/src/window/term_texture.zig`
- `howl-linux-host/src/terminal/context.zig`
- `docs/render-surface.md` if present

Required output:

- A new research cache under `research/cache-YYYY-MM-DD-render-surface-host-failure-classes.md`.
- Exact line-backed classification for each current host render-surface failure class:
  - trusted renderer invariant violation that should assert/crash in the in-tree Linux host
  - expected GL/backend/resource operating error that should fail closed
  - intentionally unsupported host feature that needs an explicit product decision
  - external/defensive C ABI validation state that must remain handled
- Explicit classification for these current names and paths:
  - `render_surface_no_sidecar_*` in `terminal/context.zig`
  - `render_surface_unsupported_shape_*` in `terminal/context.zig`
  - `PreparedRenderResourcePlanStatus` in `terminal/render/retained.zig`
  - `PreparedRenderSurfaceProbeStatus` in `terminal/render/retained.zig`
  - `RenderResourceStoreStatus` in `terminal/render/retained.zig`
  - `RenderResourceTextures.FailureBucket` in `window/term_texture.zig`
- Proof whether `howl_render_prepared_surface_render_surface(...)` returning no surface is a valid operating outcome after `HOWL_RENDER_SURFACE_EMIT_OK`, or an invariant violation.
- Proof whether Linux host is expected to defensively validate hostile render-surface pointers from external embedders, or only consume trusted surfaces produced by in-tree `howl-render`.
- Proof whether unsupported render-surface commands/resources are valid feature negotiation or renderer/host ABI drift.

Stop conditions:

- Stop if `howl-render` ABI/tests do not prove the trust boundary.
- Stop if any failure class cannot be classified without a product decision.
- Stop if classification implies a render ABI semantic change; record a separate ABI slice instead.

Readiness gate:

- Researcher marks cache ready for planning.
- Reviewer accepts that every listed failure class has a line-backed classification.

## Lane A Slice 2: Render-Surface Failure Policy Cleanup

Owner: worker after Slice 1 is accepted.

Purpose: encode the accepted Slice 1 classification in host behavior and tests.

Accepted classification cache:

- `research/cache-2026-06-01-render-surface-host-failure-classes.md`

Allowed files:

- `howl-linux-host/src/terminal/context.zig`
- `howl-linux-host/src/terminal/render/retained.zig`
- `howl-linux-host/src/window/term_texture.zig`

Tests must live in the same three files. No host test wiring changes are in scope for this slice.

Required shape:

- Preserve C ABI defensive behavior in `howl-render`. This host slice changes only how the in-tree Linux host treats trusted render-produced surfaces.
- In the in-tree Linux host path, convert trusted render-surface invalidity to `std.debug.assert(...)` where the invalidity is local and boolean, or `std.debug.panic(...)` where a status/tag must be printed for diagnosis.
- Keep GL/backend/resource realization failures handled and fail-closed. `RenderResourceTextures.FailureBucket.gl_error` remains an operating class.
- Keep reserved `HOWL_RENDER_RESOURCE_GLYPH_ATLAS_COLOR` rejected as unsupported. Do not add color glyph support or feature negotiation.
- Do not assert on external/dead/null C ABI handles in render library FFI. The Linux host path may assert after its own prepared-handle stability proof.
- Rename host-only `sidecar` vocabulary exactly:
  - `render_surface_no_sidecar_count` -> `render_surface_unavailable_count`
  - `render_surface_no_sidecar_null_count` -> `render_surface_unavailable_null_count`
  - `render_surface_no_sidecar_call_failed_count` -> `render_surface_unavailable_call_failed_count`
  - `render_surface_no_sidecar_unsupported_count` -> `render_surface_unavailable_unsupported_count`
  - `render_surface_no_sidecar_invalid_count` -> `render_surface_unavailable_invalid_count`
  - `render_surface_no_sidecar_overflow_count` -> `render_surface_unavailable_overflow_count`
  - `render_surface_no_sidecar_other_count` -> `render_surface_unavailable_other_count`
  - `recordRenderSurfaceNoSidecar(...)` -> `recordRenderSurfaceUnavailable(...)`
  - diagnostic text `no_sidecar` -> `unavailable`
- Do not split boolean returns generally. Only change named functions below.
- `terminal/context.zig` must stop treating `.ok`, `.idle`, null surface, call failed, unsupported command/resource, invalid spans/order/upload/resource, or overflow as equal “no sidecar” buckets in the trusted path.
- `terminal/render/retained.zig` must preserve validation helpers where needed for tests/defensive proof, but trusted prepared-upload flow must not continue as if invalid trusted render surfaces were ordinary runtime failures.
- `window/term_texture.zig` must keep GL errors handled and fail-closed, while invalid spans/order/command shape/upload bounds/tombstone/capacity from trusted surfaces become invariant failures or are impossible before GL realization.

Exact function changes:

- `terminal/context.zig`:
  - In `ContextSubmitBackend.upload(...)`, after `self.term.render.preparedUpload(&upload)` has succeeded and `prepared_handle` stability has been asserted by `submitPreparedLockedWith(...)`, treat `prepared_upload.render_surface == null` as invariant unless the accepted classification says the status is a renderer emission fail-closed result before a surface exists.
  - Replace the call to `recordRenderSurfaceNoSidecar(...)` with `recordRenderSurfaceUnavailable(...)` and make that function panic for trusted-path statuses classified as invariant by `cache-2026-06-01-render-surface-host-failure-classes.md:84-92`.
  - Keep `backend_upload_failed` as a handled `SubmitPreparedResult` only for GL/backend operating failure.
  - In `uploadRenderSurfaceCommands(...)`, when no shape path matches, call a new `panicUnsupportedTrustedRenderSurfaceShape(...)` instead of only incrementing unsupported-shape counters.
  - Keep shape counters only as pre-panic diagnostic fields for the panic message or tests; do not let the trusted path continue after unsupported shape.
- `terminal/render/retained.zig`:
  - Add exact helper `trustedResourcePlanStatusAction(status: PreparedRenderResourcePlanStatus) TrustedRenderSurfaceAction`.
  - Add exact helper `trustedProbeStatusAction(status: PreparedRenderSurfaceProbeStatus) TrustedRenderSurfaceAction`.
  - Add exact helper `trustedStoreStatusAction(status: RenderResourceStoreStatus) TrustedRenderSurfaceAction`.
  - Add exact enum `TrustedRenderSurfaceAction = enum { ok, invariant, reserved_unsupported, defensive }`.
  - Helpers must encode the accepted classifications from `cache-2026-06-01-render-surface-host-failure-classes.md:101-134` exactly. `ok` statuses return `.ok`; reserved color glyph atlas cases return `.reserved_unsupported` only where the caller has exact resource-kind proof; initial `.idle` and trusted invalid statuses return `.invariant`; defensive is for helper tests/external validation only and must not be returned by the trusted host submit path.
  - Do not remove existing validation functions in this slice.
- `window/term_texture.zig`:
  - Add exact helper `trustedTextureFailureAction(bucket: RenderResourceTextures.FailureBucket, resource_kind: ?u32) TrustedTextureFailureAction`.
  - Add exact enum `TrustedTextureFailureAction = enum { invariant, operating, reserved_unsupported, defensive }`.
  - Helper must classify `gl_error` as `.operating`; `unsupported_resource_format` as `.reserved_unsupported` only when `resource_kind == HOWL_RENDER_RESOURCE_GLYPH_ATLAS_COLOR`, otherwise `.invariant`; all other buckets from `cache-2026-06-01-render-surface-host-failure-classes.md:135-145` are `.invariant` in the trusted path.
  - In `realizeSurface(...)`, keep fail-closed return for `.operating`; panic/assert for `.invariant`; preserve reserved color glyph atlas rejection as unsupported/fail-closed without adding support.
  - In `uploadRenderSurfaceFillOnly(...)` and `uploadRenderSurfaceFillPatch(...)`, shape/host-surface preconditions remain assertions in the trusted caller; `uploadFillCommand(...) == false` must be treated as invariant unless caused by `glGetError()`, which remains operating.
  - In `uploadRenderSurfaceSprites(...)`, `uploadRenderSurfaceSpritePatch(...)`, `uploadRenderSurfaceGlyphs(...)`, and `uploadRenderSurfaceGlyphPatch(...)`, a failed shape predicate after the caller selected that shape is invariant.
  - In `uploadRenderSurfaceCommands(...)`, these are operating/fail-closed: framebuffer generation failure, incomplete framebuffer, and final `glGetError() != 0`.
  - In `uploadRenderSurfaceCommands(...)`, these are invariant in the trusted path: host-surface size/id mismatch after `ensureSurface(...)`, missing texture slot for command/glyph resource, future upload after command use, draw command validation failure, and unknown command kind.
  - In `drawSpriteCommand(...)`, `spriteUploadCoversCommand(...) == false` is invariant in the trusted path.
  - In `drawGlyphCommand(...)`, missing glyph texture slot and glyph atlas rect outside slot dimensions are invariant in the trusted path.
  - In shape predicates `renderSurfaceFillOnly(...)`, `renderSurfaceFillPatch(...)`, `renderSurfaceSprite(...)`, `renderSurfaceSpritePatch(...)`, `renderSurfaceGlyphs(...)`, and `renderSurfaceGlyphPatch(...)`, `false` remains a classifier result only while selecting the shape. Once `context.zig` has selected a shape branch, subsequent upload failure from that branch must not be collapsed into generic backend failure unless it is one of the named GL operating failures.

Required tests:

- `terminal/render/retained.zig` tests:
  - `trusted resource plan status actions classify invariant statuses`
  - `trusted probe status actions classify invariant statuses`
  - `trusted store status actions classify invariant statuses`
  - These tests must cover every enum tag in `PreparedRenderResourcePlanStatus`, `PreparedRenderSurfaceProbeStatus`, and `RenderResourceStoreStatus`.
- `window/term_texture.zig` tests:
  - `trusted texture failure actions classify gl error as operating`
  - `trusted texture failure actions classify trusted invalid buckets as invariants`
  - `trusted texture failure action preserves reserved color glyph unsupported`
  - `trusted texture upload command failures distinguish gl operating from invariant validation`
  - These tests must cover every `RenderResourceTextures.FailureBucket` tag.
- `terminal/context.zig` tests:
  - `render surface unavailable diagnostics use render surface vocabulary`
  - `trusted render surface unavailable ok and idle are invariant actions`
  - `trusted unsupported render surface shape does not continue as upload failure`
- Do not add panic-catching tests unless the project already has a local panic test helper. Prefer testing the exact classifier helpers and using asserts/panic only in production trusted-path call sites.
- Existing unit, retained-render, term-texture, terminal-context, and integration test gates must not be weakened or filtered.

Verification:

- From `howl-linux-host`: `zig build check`
- From `howl-linux-host`: `zig build test --summary all`
- From `howl-linux-host`: `zig build -Doptimize=ReleaseFast`
- From `howl-linux-host`: `git diff --check`
- From workspace root: tracked `.zig` line scan must print `TOTAL 0` for lines over 190 chars.

Stop conditions:

- Stop if implementation needs a new render ABI status or changed ABI semantics.
- Stop if host must support untrusted external render-surface pointers in this path.
- Stop if tests would need to weaken existing unit or integration gates.
- Stop if an assertion would fire for a documented GL/backend operating error.
- Stop if color glyph atlas support becomes necessary to make tests pass.

## Lane B Slice 1: Host Owner Boundary Map

Owner: planning/research.

Purpose: produce a worker-ready split map for the over-owned host files without editing product code.

Inputs:

- `research/cache-2026-06-01-host-owner-inventory.md`
- `research/cache-2026-06-01-host-reference-shape.md`

Required output:

- A scratchpad section or separate cache that maps each over-owned function/field to its true owner:
  - `terminal/context.zig`
  - `window/term_texture.zig`
  - `main.zig`
  - `input/input.zig`
  - `window/present.zig`
- A scratchpad section or separate cache that maps each misnamed owner to its true name/boundary:
  - `input/window.zig`
- Function length and assertion-density facts for `terminal/context.zig`, `window/term_texture.zig`, `main.zig`, and `input/input.zig` before planning touches those files, per owner-inventory proof gap.
- A proposed first implementation split that does not move behavior across ABI boundaries.

Stop conditions:

- Stop if the proposed owner names are generic or banned.
- Stop if the split requires broad runtime behavior changes instead of owner-preserving movement.
- Stop if test ownership cannot be preserved.

## Lane C Slice 1: Integration Test Truth

Owner: planning/research.

Purpose: replace false confidence from import-only integration tests with a source-backed test plan.

Inputs:

- `howl-linux-host/src/test/integration_entry.zig`
- `howl-linux-host/build.zig`
- host owner/test facts from the owner inventory cache

Required output:

- Classify current host test gates: unit, integration, stress, runtime reproduction.
- Identify which product risks have behavioral tests and which are import-only.
- Propose exact first behavioral integration test slice with owner, files, and gate.

Stop conditions:

- Stop if a proposed integration test would require SDL/GL environment assumptions not available in CI/local gates.
- Stop if the test would weaken existing unit gates or duplicate owner tests.

## Lane B Slice 2: Event Loop And Window Wake Owner

Owner: worker after this scratchpad/current slice is promoted.

Purpose: remove event-loop wait/poll/wake ownership from `input/` and create the source-backed host event-loop owner plus concrete SDL window wake owner.

Accepted cache:

- `research/cache-2026-06-01-host-owner-boundary-map.md`

Required files:

- `howl-linux-host/src/event_loop.zig`
- `howl-linux-host/src/polling/window_wake.zig`
- `howl-linux-host/src/input/wake.zig`
- `howl-linux-host/src/input/input.zig`
- `howl-linux-host/src/main.zig`
- `howl-linux-host/src/terminal/context.zig`
- `howl-linux-host/src/terminal/pty/wait_thread.zig`
- `howl-linux-host/src/terminal/scrollbar.zig`
- `howl-linux-host/src/terminal/render/surface_layout.zig`
- `howl-linux-host/src/test/host.zig`
- `howl-linux-host/src/test_root.zig`

Required shape:

- `event_loop.zig` owns event-loop policy, wake event classification, quit state, bounded SDL pump turn, clock/timer facade, and PTY wake handoff target.
- `polling/window_wake.zig` owns direct SDL window event-loop wake/wait/poll/time/timer/semaphore calls only.
- Delete `input/wake.zig` after moving behavior.
- Remove `window_state`, `pumpWindow`, `waitAndDrainEvents`, `drainPendingEvents`, and `wakeWindow` from `input/input.zig`.
- Keep input event classification, key/mouse/text conversion, bounded queues, focus/geometry flags, redraw requests, and binding behavior in `input/input.zig`.
- `terminal/pty/wait_thread.zig` must store and wake `*EventLoop.State`, not `*Input`.
- `terminal/context.zig` may keep the `Context` owner name for this slice, but it must thread `*EventLoop.State` to the PTY wait-thread init path.
- `polling/sdl.zig`, `app/wake.zig`, `app_wake`, and `chrome_wake` are rejected names for this slice.
- No `polling/signal.zig` or `polling/ipc.zig` until there is current Howl product behavior and tests for those paths.

Required tests:

- Event-loop test: wake event is consumed and not classified as input.
- Event-loop test: quit event sets quit state and returns `.quit`.
- Event-loop test: bounded drain does not exceed the SDL event-turn limit.
- Event-loop test: `requestQuit()` sets quit and pushes wake through fake ops.
- Update PTY wait-thread tests so wake coalescing and acknowledgement target the event-loop wake seam.

Stop conditions:

- Stop if `event_loop.zig` starts owning terminal runtime progress, PTY read/write, VT mutation, render submission, presentation, tabs, or window GL state.
- Stop if PTY wait-thread still targets input wake after the slice.
- Stop if input still owns SDL wait/poll/wake or wake event registration after the slice.
- Stop if signal/IPC polling is added.
- Stop if any C ABI changes appear.

## Lane B Slice 3: Terminal Context Owner Research

Owner: research, not implementation.

Purpose: replace the vague `terminal/context.zig` owner with source-backed terminal host owners after the event-loop/window-wake slice lands.

Required research:

- Read Ghostty first for VT-core and terminal host shape, then Alacritty for host runtime shape, then current Howl `terminal/context.zig`.
- Map every major `Context` field and function group to its smallest true owner.
- Propose exact owner file names, allowed files, tests, ABI consequences, and first implementation split.
- Preserve ABI boundary: no host shortcut into `howl-pty`, `howl-vt`, or `howl-render` internals.

Stop conditions:

- Stop if proposed names are generic or banned.
- Stop if a split would weaken the app control spine, PTY wait-thread discipline, or render ABI boundary.
- Stop if test gates are not exact.

## Planning Order

1. Lane A failure-policy implementation is blocked until Lane A Slice 1 is accepted.
2. Lane B host owner-boundary research can proceed independently from Lane A because the owner-inventory and host-reference caches are ready for constrained planning.
3. Lane C integration-test truth can proceed independently from Lane A and Lane B because the owner-inventory cache proves import-only integration risk.
4. Do not promote implementation from any lane until that lane has an accepted cache, accepted scratchpad section, exact allowed files, tests, and stop conditions.

## Open Product Decisions

Reference-cache open decisions:

- Is the Linux host an ABI harness forever, or is it becoming a product host with TigerBeetle-static allocation expectations?
- Is fixed 60Hz frame pacing an intentional harness constraint or stale debt?
- Is synchronous present token modeling a deliberate future-backend proof seam or accidental complexity?

Failure-policy-cache open decisions:

- Should malformed optional config fields silently default, warn, or reject config?
- Should external embedders be able to hand arbitrary render-surface pointers to host code, or is the Linux host only consuming trusted in-tree prepared surfaces?
