# Full Howl Review Checkpoints

## Objective

Close architecture drift at the workspace level so repo intent cannot be mistaken in future agent workflows.

## Execution Sequence

### FHR-P0 — Authority Lock

1. Keep `architecture_docs/authority/MVP_STRUCTURE.md` as parent authority.
2. Ensure every future handover cites:
   - active review file
   - active checkpoints file
   - `CHECKIN_PROTOCOL.md` validation block.

### FHR-P1 — Dependency Direction Enforcement (Local Only)

1. Extend `utils/hygene/architecture_guard.sh` with import-direction checks:
   - fail if `render-core` imports `howl-term-surface`.
   - fail if backend repos import host/session/surface repos.
   - fail if core/session import renderer/host repos.
2. Keep enforcement local-only (no remote CI).

### FHR-P2 — Renderer Lane Structural Closure

1. `render/howl-render-core`:
   - split monolithic `src/root.zig` into intentional modules:
     - `types.zig`
     - `theme.zig`
     - `planner.zig`
     - `frame_adapter.zig`
     - thin `root.zig` exports/tests
   - remove direct dependency on `howl-term-surface`.
   - use plain core-owned input types at boundary.
2. `render/howl-render-{gl,gles,metal,vulkan,software}`:
   - keep thin root exports
   - add internal module split for execution/resource lifecycle
   - no policy duplication from render-core.

### FHR-P3 — Host/Surface Seam Closure

1. `howl-term-surface` should own frame-to-plan adaptation seam (or an explicitly documented equivalent boundary).
2. `howl-sdl-host` should be reduced to:
   - platform loop
   - input mapping
   - composition calls
   - present/swap
3. Document exact allowed imports in host and surface authorities.

### FHR-P4 — Naming and Docstring Enforcement

1. Add local hygiene checks for:
   - public symbol naming policy
   - required `///` docs for stable public symbols
   - directory naming rules under `src/`.
2. Keep a scoped allowlist mechanism for legacy cases only.

### FHR-P5 — Scaffold Repo Convergence

1. Lift `howl-android-host` to parity with SDL host discipline baseline:
   - file headers
   - explicit module split plan
   - contracts matching intended MVP boundary.
2. Keep render scaffold repos explicit about stub status vs MVP-ready status.

## Stop Conditions

1. If a proposed split would force compatibility shims, stop and redesign the split.
2. If dependency-direction checks produce high false positives, freeze rule and document exact limitation.
3. If a closure step requires cross-repo API churn outside declared milestone scope, stop and publish architect decision.

## Acceptance Criteria

1. Full workspace guard passes for all active product repos.
2. `render-core` no longer imports `howl-term-surface`.
3. Host render/session policy duplication is removed or explicitly bounded and justified in authority docs.
4. Every repo has explicit MVP structural layout and coupling boundaries in authority docs.

