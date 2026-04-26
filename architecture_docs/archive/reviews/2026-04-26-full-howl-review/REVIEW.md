# Full Howl Architecture Review (2026-04-26)

## Intent

Reset the discipline loop from first principles:

1. Validate that every repo has explicit MVP ownership and API/coupling boundaries.
2. Verify code topology and imports align with those boundaries.
3. Identify drift causes in docs/workflow and publish corrective checkpoints.

## Scope

Repos audited:

- `howl-vt-core`
- `howl-session`
- `howl-term-surface`
- `render/howl-render-core`
- `render/howl-render-gl`
- `render/howl-render-gles`
- `render/howl-render-metal`
- `render/howl-render-software`
- `render/howl-render-vulkan`
- `howl-hosts/howl-sdl-host`
- `howl-hosts/howl-android-host`
- `utils/howl-microscope`
- `utils/howl-docs`
- `utils/howl-pm`

Parent authorities/checkins reviewed:

- `architecture_docs/archive/checkins/transition.md`
- `architecture_docs/archive/checkins/checkin1.md`
- `architecture_docs/archive/checkins/checkin2.md`
- `architecture_docs/archive/checkins/checkin3.md`
- `architecture_docs/archive/checkins/checkin4-architecture-discipline-2026-04-26.md`
- `architecture_docs/authority/MODULE_MAP.md`
- `architecture_docs/authority/DEPENDENCY_RULES.md`
- `architecture_docs/authority/INTEGRATION_FLOW.md`
- `architecture_docs/authority/MILESTONES.md`
- `architecture_docs/authority/ENGINEERING_CONVENTIONS.md`
- `architecture_docs/authority/CHECKIN_PROTOCOL.md`

## Findings (Ordered by Severity)

### High

1. **Render-core has reverse dependency pressure on surface.**
   - Evidence: `render/howl-render-core/src/root.zig` imports `howl_term_surface`.
   - This violates the intended direction (`surface -> render-core`, never reverse) and creates coupling ambiguity in frame ownership.

2. **Host seam still carries too much render/session policy.**
   - Evidence: `howl-hosts/howl-sdl-host/src/main.zig` imports `howl_session`, `vt_core`, `howl_render_core`, and executes frame planning directly.
   - The Linux host should own platform loop and composition, but should not be a second policy owner for render planning.

### Medium

1. **MVP topology is under-specified for several repos.**
   - `render/howl-render-core` and all renderer backends remain single-file `src/root.zig` modules.
   - This was acceptable for scaffold, but not a clear MVP end-state for maintainable ownership.
   - Current status: closed for renderer repos; see checkpoint FHR-P2.

2. **Symbol/doc convention enforcement is partial.**
   - `utils/hygene/architecture_guard.sh` enforces headers/file names/test-name tags/pattern bans.
   - It does not enforce `///` public docs, symbol naming policy, directory naming policy, or dependency direction.

3. **Android host scaffold lags hygiene and structure expectations.**
   - Minimal API exists but repo is not yet aligned to the same documentation and structural discipline bar as SDL host.

### Low

1. **Milestone language is mostly aligned but still heterogeneous by repo maturity.**
   - This is acceptable if the current target table remains synchronized and explicit.

## Repo-by-Repo MVP Readiness Snapshot

| Repo | Responsibility/API/Coupling Doc Clarity | Structural Layout Clarity | MVP Cohesion Status |
| --- | --- | --- | --- |
| `howl-vt-core` | strong | strong | green |
| `howl-session` | strong | medium (test-support mixed into `src/`) | yellow |
| `howl-term-surface` | strong | medium | yellow |
| `render/howl-render-core` | strong docs, weak code coupling alignment | weak (single-file monolith) | red |
| `render/howl-render-gl` | medium | weak (single-file) | yellow |
| `render/howl-render-gles` | medium | weak (single-file scaffold) | yellow |
| `render/howl-render-metal` | medium | weak (single-file scaffold) | yellow |
| `render/howl-render-software` | medium | weak (single-file scaffold) | yellow |
| `render/howl-render-vulkan` | medium | weak (single-file scaffold) | yellow |
| `howl-hosts/howl-sdl-host` | strong docs, medium coupling discipline | medium | yellow |
| `howl-hosts/howl-android-host` | medium | weak (scaffold) | red |
| `utils/howl-microscope` | strong | strong | green |
| `utils/howl-docs` | medium | medium | yellow |
| `utils/howl-pm` | medium | medium | yellow |

## Root Causes of Drift (Docs/Workflow)

1. **Missing parent-level MVP structure authority until now.**
   - Existing docs described ownership and dependency direction, but not required per-repo MVP topology shape.

2. **Guard/tooling gap against architecture drift.**
   - No automated local check currently validates forbidden cross-module import direction.

3. **Handover success criteria over-weight green tests vs. structural intent.**
   - Build/test pass can hide layering regressions (e.g., reverse dependency pressure).

4. **Scaffold repos were left in scaffold shape while milestone language advanced.**
   - This creates implicit ambiguity: “contract says executor” while code remains minimal stubs.

## Architectural Correction Direction

1. Keep module layering strict:
   - `host -> surface -> session -> vt_core`
   - `surface -> render-core -> backend`
   - no reverse edge from `render-core` to `surface`.

2. Define and enforce intentional MVP topology per repo.

3. For renderer lane:
   - core owns planning policy once,
   - backends execute only,
   - host stays composition/platform shell.

4. Keep transport portability cohesive:
   - PTY/bridge/conpty as transport implementations behind session contract.
