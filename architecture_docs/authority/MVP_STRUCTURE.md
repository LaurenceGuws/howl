# Howl MVP Structural Layout Authority

This document defines the required module structure for Linux MVP closure.
It is parent-level authority for repo intent, public API boundaries, and allowed coupling.

## Rules

1. Every module must have an intentional `src/` topology aligned with its ownership.
2. Public API ownership must be explicit and stable at MVP boundary points.
3. Coupling is one-way by design; reverse imports are architecture violations.
4. Host repos may compose modules, but must not absorb lower-layer policy ownership.

## MVP Structure Matrix

| Repo | MVP Responsibility | Required Public API Boundary | Required `src/` Topology (MVP) | Allowed Coupling |
| --- | --- | --- | --- | --- |
| `howl-vt-core` | Portable VT semantics and deterministic terminal state | `vt_core` exports only | parser/event/model/screen/runtime split | no upstream module deps |
| `howl-session` | Session lifecycle + transport orchestration around VT | `howl_session` exports only | session + transport split; test-support isolated | may depend on `vt_core` only |
| `howl-term-surface` | Embeddable terminal composition API | `howl_term_surface` exports only | lifecycle/input/frame composition split | may depend on `howl-session` + `vt_core` |
| `render/howl-render-core` | Backend-neutral planning policy | `howl_render_core` exports only | split into types/theme/planner modules; thin `root.zig` | must not depend on surface/session/host repos |
| `render/howl-render-gl` | GL backend executor | `howl_render_gl` exports only | backend lifecycle + execution modules; thin `root.zig` | may depend on `howl-render-core` only |
| `render/howl-render-gles` | GLES backend executor | `howl_render_gles` exports only | backend lifecycle + execution modules; thin `root.zig` | may depend on `howl-render-core` only |
| `render/howl-render-metal` | Metal backend executor | `howl_render_metal` exports only | backend lifecycle + execution modules; thin `root.zig` | may depend on `howl-render-core` only |
| `render/howl-render-vulkan` | Vulkan backend executor | `howl_render_vulkan` exports only | backend lifecycle + execution modules; thin `root.zig` | may depend on `howl-render-core` only |
| `render/howl-render-software` | Software backend executor/reference | `howl_render_software` exports only | backend lifecycle + execution modules; thin `root.zig` | may depend on `howl-render-core` only |
| `howl-hosts/howl-sdl-host` | Linux host shell composition and platform loop | host-local app API only | split config/host-loop/platform entry/render handoff modules | may depend on surface + selected renderer backend |
| `howl-hosts/howl-android-host` | Android lifecycle/input/surface/process integration | host-local app API only | split host/input/platform-surface/process integration modules | may depend on surface + selected renderer backend |
| `utils/howl-microscope` | External comparison harness | CLI/report APIs only | cli/dsl/runner/report split | no product runtime ownership |
| `utils/howl-docs` | Documentation tooling | docs tool APIs only | frontend/tooling split | no product runtime ownership |
| `utils/howl-pm` | Package/release metadata tooling | CLI/provider APIs only | cmd/internal/provider split | no product runtime ownership |

## Cohesion Rules for Redundant Paths

### PTY / Transport Cohesion

1. PTY/process implementations are transport implementations, not session policy.
2. Linux POSIX PTY, Android container integration, and future ConPTY must remain behind the same session transport contract.
3. Host repos choose transport implementation; session core remains host-neutral.

### Renderer Backend Cohesion

1. Render policy exists once in `howl-render-core`.
2. Backends execute plans and report capability; they do not reinterpret terminal frame semantics.
3. Host repos call one render API per frame; host code must not duplicate render planning policy.

## Immediate Structural Debt Markers

The following are considered active debt until closed by checkpoint:

1. Any reverse dependency from `render-core` to `howl-term-surface`.
2. Any host-local duplication of render planning policy that should be core-owned.
3. Missing public API doc coverage in scaffold backends and host stubs.

## Closed Structural Debt

1. Renderer repos no longer use single-file `src/root.zig` structure:
   - `render/howl-render-core` owns `types.zig`, `theme.zig`, and `planner.zig`.
   - `render/howl-render-gl` owns contract, backend, glyph raster, GL draw, and binding modules.
   - scaffold renderer backends own types and execution modules with thin roots.
