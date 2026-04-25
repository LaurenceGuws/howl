# Howl Milestone Map

This document defines the Howl development journey across modules.
It separates MVP scope from long-term scope so architect sessions can drive
work without reshaping the product boundary every batch.

## Product Goal

Howl is an embeddable terminal stack:

- a portable VT engine
- a session/process runtime
- a terminal surface composition layer
- reusable renderer core and backend renderers
- concrete hosts that provide windowing, input, lifecycle, and packaging

The first product target is a Linux desktop terminal host using SDL for
window/input and a decoupled renderer path.

## MVP Definition

MVP means a real terminal window on Linux that can run an interactive shell,
render text correctly enough for daily development workflows, handle resize and
keyboard input, and preserve deterministic behavior through the shared modules.

MVP does not mean every renderer backend is complete, every VT sequence is
implemented, or every future platform is shipped.

## Family Milestone Ladder

| ID | Name | Outcome |
| --- | --- | --- |
| `F0` | Workspace Authority | Parent module map, dependency rules, integration flow, and repo scopes are explicit. |
| `F1` | Core Package Baseline | Every planned module has an initialized repo, clean scaffold, local build/test, and matching remote. |
| `F2` | Session-Core Integration | Session owns process/transport lifecycle and drives VT core through public APIs. |
| `F3` | Surface Contract | Surface composes session, VT state, input routing, and frame production without host framework types. |
| `F4` | Render Core Contract | Backend-neutral render plan, glyph/cell layout model, damage model, and resource policy are defined. |
| `F5` | First Renderer Path | OpenGL renderer can consume render-core plans and draw terminal text/cursor in a host-owned context. |
| `F6` | First Host Loop | SDL host owns window/input/context/present loop and runs one terminal surface. |
| `F7` | MVP Terminal | Linux SDL host runs an interactive shell with resize, keyboard input, text rendering, scrollback path, and deterministic shutdown. |
| `F8` | MVP Quality Lock | Local evidence covers latency-sensitive loops, resize/input/render stability, leaks, and release packaging. |
| `F9` | Multi-Surface Readiness | Shared modules support multiple terminal surfaces without shared mutable state leaks. |
| `F10` | Renderer Portability | GLES, Vulkan, Metal, and software paths can share render-core contracts without duplicating terminal logic. |
| `F11` | Host Expansion | Additional hosts can integrate through surface/session/render contracts without changing lower layers. |
| `F12` | Best-In-Class Terminal Stack | Competitive latency, throughput, resource discipline, and protocol breadth are demonstrated with reproducible evidence. |

## Module Milestones

### `howl-vt-core`

MVP scope:

| ID | Outcome |
| --- | --- |
| `VT-M0` | Parser/model/runtime baseline is frozen and released. |
| `VT-M1` | Public API is consumed by session/surface only through exported symbols. |
| `VT-M2` | Feed/apply/reset/input/snapshot behavior remains deterministic under host-driven loops. |
| `VT-M3` | First-host gaps are fixed only when proven as portable terminal semantics. |
| `VT-M4` | MVP release tag documents supported VT/input/snapshot surface and known non-goals. |

Long-term scope:

| ID | Outcome |
| --- | --- |
| `VT-L1` | Broader VT protocol coverage based on real fixture failures. |
| `VT-L2` | Best-in-class parser throughput and memory discipline with reproducible benchmark evidence. |
| `VT-L3` | Rich terminal features such as hyperlinks, bracketed paste, advanced modes, images, and synchronized update where architecturally justified. |
| `VT-L4` | Cross-host conformance fixtures prove identical core behavior across all supported hosts. |

### `howl-session`

MVP scope:

| ID | Outcome |
| --- | --- |
| `SE-M0` | Lifecycle, queue, resize/control, transport, conformance, performance, reliability, operations, and snapshot contracts are clean and current. |
| `SE-M1` | Unix PTY transport can start a child shell, read output, write input, resize, signal, and stop deterministically. |
| `SE-M2` | Session drives `howl-vt-core` engine rather than retaining placeholder byte queues as product behavior. |
| `SE-M3` | Session exposes a frame/source state that surface can consume without platform or renderer types. |
| `SE-M4` | Session supports a single interactive terminal lifecycle for SDL host MVP. |

Long-term scope:

| ID | Outcome |
| --- | --- |
| `SE-L1` | Multiple independent sessions can run without hidden shared state or allocator leaks. |
| `SE-L2` | Operational counters and snapshot/restore remain useful under real host loops. |
| `SE-L3` | Session supports richer process control and diagnostic capture without becoming host-specific. |
| `SE-L4` | Session becomes the stable backend runtime for editor, terminal, and future embedded surfaces. |

### `howl-term-surface`

MVP scope:

| ID | Outcome |
| --- | --- |
| `SF-M0` | Surface contract defines lifecycle, input routing, resize, frame production, and error boundaries. |
| `SF-M1` | Surface composes one session and one render path without importing host framework types. |
| `SF-M2` | Surface translates host input events into session/core input calls through plain data. |
| `SF-M3` | Surface produces a render-ready frame model from session/core state. |
| `SF-M4` | Surface supports one terminal widget for SDL host MVP. |

Long-term scope:

| ID | Outcome |
| --- | --- |
| `SF-L1` | Multiple surfaces can be orchestrated by hosts for tabs, panes, and embedded widgets. |
| `SF-L2` | Surface supports shared renderer resources without merging terminal state machines. |
| `SF-L3` | Surface provides stable integration for non-SDL hosts. |
| `SF-L4` | Surface becomes the primary embeddable terminal widget API. |

### `render/howl-render-core`

MVP scope:

| ID | Outcome |
| --- | --- |
| `RC-M0` | Backend-neutral render data types are explicit: viewport, grid, cell/glyph input, cursor, damage, and draw plan. |
| `RC-M1` | Text layout and glyph-run planning are independent of SDL/OpenGL/Metal/Vulkan types. |
| `RC-M2` | Damage model supports incremental redraw for typing and scrolling. |
| `RC-M3` | Atlas/cache policy hooks are defined without binding to one backend. |
| `RC-M4` | OpenGL backend can consume render-core output for MVP text rendering. |

Long-term scope:

| ID | Outcome |
| --- | --- |
| `RC-L1` | Shared renderer tests prove backend-neutral output stability. |
| `RC-L2` | Renderer core supports shaping, ligatures, wide glyphs, emoji constraints, decorations, and selection/cursor overlays. |
| `RC-L3` | Render planning has measurable allocation and latency discipline. |
| `RC-L4` | Backend ports reuse the same render-core contract without divergent terminal rendering logic. |

### `render/howl-render-gl`

MVP scope:

| ID | Outcome |
| --- | --- |
| `GL-M0` | GL renderer contract defines context ownership, init/resize/render/deinit, and resource lifetime. |
| `GL-M1` | Renderer consumes render-core plans without SDL imports. |
| `GL-M2` | Renderer draws text cells, cursor, selection background, and clear regions. |
| `GL-M3` | Renderer handles resize and resource rebuild deterministically. |
| `GL-M4` | Renderer supports MVP SDL host with acceptable latency and no steady-state leaks. |

Long-term scope:

| ID | Outcome |
| --- | --- |
| `GL-L1` | Glyph atlas and batch path are optimized and measured. |
| `GL-L2` | Renderer supports advanced decorations and high-DPI correctness. |
| `GL-L3` | GL path remains a portable baseline even if Vulkan becomes the primary Linux performance path. |

### `render/howl-render-gles`

MVP scope:

| ID | Outcome |
| --- | --- |
| `GLES-M0` | Repo scaffold and API shape match render backend contract. |
| `GLES-M1` | Deferred until Android or GLES host work becomes active. |

Long-term scope:

| ID | Outcome |
| --- | --- |
| `GLES-L1` | GLES backend consumes render-core plans without GL desktop assumptions. |
| `GLES-L2` | Android/mobile constraints are reflected in renderer resource policy. |

### `render/howl-render-metal`

MVP scope:

| ID | Outcome |
| --- | --- |
| `MTL-M0` | Repo scaffold and API shape match render backend contract. |
| `MTL-M1` | Deferred until macOS/iOS host work becomes active. |

Long-term scope:

| ID | Outcome |
| --- | --- |
| `MTL-L1` | Metal backend consumes render-core plans without host UI coupling. |
| `MTL-L2` | Apple platform renderer quality matches shared render-core evidence. |

### `render/howl-render-vulkan`

MVP scope:

| ID | Outcome |
| --- | --- |
| `VK-M0` | Repo scaffold and API shape match render backend contract. |
| `VK-M1` | Deferred until GL MVP exposes the stable renderer contract and measurement baseline. |

Long-term scope:

| ID | Outcome |
| --- | --- |
| `VK-L1` | Vulkan backend becomes a Linux performance candidate after render-core and GL path mature. |
| `VK-L2` | Vulkan path proves lower latency or better throughput before replacing GL as default. |

### `render/howl-render-software`

MVP scope:

| ID | Outcome |
| --- | --- |
| `SW-M0` | Repo scaffold and API shape match render backend contract. |
| `SW-M1` | Deferred unless required for tests, diagnostics, or headless render evidence. |

Long-term scope:

| ID | Outcome |
| --- | --- |
| `SW-L1` | Software backend supports deterministic render tests and diagnostics. |
| `SW-L2` | Software output can serve as a reference path for renderer correctness. |

### `howl-hosts/howl-sdl-host`

MVP scope:

| ID | Outcome |
| --- | --- |
| `SDL-M0` | Host scaffold has no zig-init leftovers and owns only window/input/context/present loop. |
| `SDL-M1` | SDL window and GL context lifecycle are deterministic. |
| `SDL-M2` | SDL input maps to plain host actions and terminal input data. |
| `SDL-M3` | Host composes one surface, one session, and one GL renderer. |
| `SDL-M4` | Host runs an interactive shell through session PTY transport. |
| `SDL-M5` | Host handles resize, redraw, shutdown, and error reporting cleanly. |
| `SDL-M6` | MVP package/release can be built and run locally. |

Long-term scope:

| ID | Outcome |
| --- | --- |
| `SDL-L1` | Multi-window/tab/pane orchestration is host-owned and uses multiple surfaces. |
| `SDL-L2` | Host supports renderer backend selection when multiple backends are production-ready. |
| `SDL-L3` | Host quality evidence covers latency, scrolling smoothness, CPU use, and memory stability. |
| `SDL-L4` | Linux host becomes the reference implementation for future hosts. |

## MVP Execution Order

1. `howl-session`: replace placeholder feed/apply behavior with real VT core drive path and complete Unix PTY loop.
2. `howl-term-surface`: define and implement first surface contract around one session and one render frame model.
3. `howl-render-core`: define backend-neutral frame/render plan data from surface output.
4. `howl-render-gl`: draw render-core plans in a host-owned GL context.
5. `howl-sdl-host`: own SDL window/input/context/present and compose the first terminal.
6. `howl-vt-core`: fix only proven portable semantic gaps found by real host pressure.
7. Family release: lock MVP behavior with local evidence, tags, and release notes.

## Architect Steering Rules

1. Parent docs own cross-module sequencing and dependency direction.
2. Child repos own their local contracts, tests, and active queues.
3. Work must not jump to long-term goals until the MVP dependency chain that
   goal relies on is complete.
4. Renderer backend work must not duplicate render-core logic.
5. Host work must not absorb session, VT, or renderer-core responsibilities.
6. Session work must not import host or renderer types.
7. Surface work is the composition boundary, not a dumping ground for platform
   code or backend-specific rendering.
8. New module dependencies require updates to `MODULE_MAP.md`,
   `DEPENDENCY_RULES.md`, and this milestone map in the same commit series.

## MVP Exit Bar

The MVP is complete only when:

- one SDL host binary opens a terminal window
- a shell process runs through session-owned PTY transport
- keyboard input reaches the process
- process output reaches VT core and renders through surface/render-core/GL
- resize updates PTY, VT dimensions, surface frame, renderer viewport, and host
  presentation
- shutdown releases process/session/renderer/window resources deterministically
- local build/test evidence passes in all participating repos
- release notes state supported scope and known missing long-term features
