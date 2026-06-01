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

Candidate files only; exact allowed files must be narrowed when promoted to `current.txt`:

- `howl-linux-host/src/terminal/context.zig`
- `howl-linux-host/src/terminal/render/retained.zig`
- `howl-linux-host/src/window/term_texture.zig`
- host test wiring only if needed to expose owner tests without weakening existing tests

Required shape will be derived from Slice 1, but must obey:

- Trusted renderer invariant violations assert/crash with precise local context.
- Real GL/backend/resource operating errors remain handled and fail closed.
- Stale `sidecar` vocabulary is removed or replaced only if Slice 1 proves the intended render-surface availability states.
- Boolean failure returns must not collapse invariant violations and operating errors into the same path.
- Tests must cover every remaining handled operating class and every converted invariant class.

Stop conditions:

- Stop if implementation needs a new render ABI status or changed ABI semantics.
- Stop if host must support untrusted external render-surface pointers in this path.
- Stop if tests would need to weaken existing unit or integration gates.

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
