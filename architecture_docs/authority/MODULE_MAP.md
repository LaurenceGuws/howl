# Howl Module Map

This document defines what each module owns at the family level.
It is the cross-repo ownership map.

## Module Table

| Module | Primary Responsibility | Owns API Surface | Consumes | Produces |
| --- | --- | --- | --- | --- |
| `howl-vt-core` | VT parser/model/runtime semantics and deterministic terminal state transitions | `vt_core` package/module API | none (foundational) | terminal state behavior, input/control encoding semantics, deterministic contracts |
| `howl-session` | Session lifecycle and transport orchestration around terminal runtime | `howl-session` public session/transport API | `howl-vt-core` public API | host-callable lifecycle surface, transport boundaries, conformance/perf/reliability evidence |
| `howl-term` | Primary embeddable terminal boundary (`howl-term`) for one terminal instance/widget | terminal/widget API for host apps | `howl-session`, `howl-vt-core`, renderer-facing frame model, selected backend path | stable terminal instance API (input + lifecycle + frame handoff + render orchestration) |
| `render/howl-render-core` | Backend-agnostic render core logic (layout pipeline/draw list model/atlas policy hooks) | render-core API used by backend implementations | frame model from surface | backend-agnostic render plan/data |
| `render/howl-render-gl` | OpenGL backend implementation | GL backend API | `howl-render-core` | GPU draw execution for GL targets |
| `render/howl-render-gles` | OpenGL ES backend implementation | GLES backend API | `howl-render-core` | GPU draw execution for GLES targets |
| `render/howl-render-metal` | Metal backend implementation | Metal backend API | `howl-render-core` | GPU draw execution for Metal targets |
| `render/howl-render-vulkan` | Vulkan backend implementation | Vulkan backend API | `howl-render-core` | GPU draw execution for Vulkan targets |
| `render/howl-render-software` | Software renderer backend implementation | software backend API | `howl-render-core` | CPU raster/render execution and reference output |
| `howl-hosts/howl-sdl-host` | Concrete Linux SDL host app (window/input/platform loop) | host app interface and wiring | one or more `howl-term` instances and selected backend wiring | runnable host application |
| `howl-hosts/howl-android-host` | Concrete Android host app (Android lifecycle/input/surface integration) | Android host interface and platform boundary | one or more `howl-term` instances, mobile renderer backend, Android process/container integration | Android terminal host application |
| `howl-hosts` (container) | Workspace grouping for host repos only | none | none | organization only |
| `utils/howl-docs` | User-facing documentation site | docs site content/build surface | released module docs and assets | public Howl documentation |
| `utils/howl-microscope` | Local diagnostics and inspection tooling | probe/inspection commands | local module builds and artifacts | review evidence and diagnostic captures |
| `utils/howl-pm` | Local package/release metadata tooling | package/release helper commands | module repos, tags, release metadata | release manifests and module version reports |
| `utils/hygene` | Local hygiene scripts | script entrypoints | workspace files | local hygiene reports |

## Notes

- `howl-term` is the current repo name for the boundary that is effectively the
  embeddable `howl-term` product surface.
- Hosts own app-level orchestration of multiple terminal instances; the terminal
  boundary owns one terminal instance/widget at a time.
- GL and GLES backend lanes must move together for text-path policy and
  capability semantics during scoped MVP work.
- Child repos should document their own scope and invariants only.
- Cross-module fit, ownership boundaries, and dependency direction are documented here.
- This map avoids duplicated cross-repo non-goal text in child repos.
