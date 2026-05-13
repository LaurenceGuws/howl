# Module C ABI Owner Table

Purpose: freeze the owner-true ABI split for the compile-time-only `howl-term` plan.

## Owner Table

| Responsibility | Owner | Why |
|---|---|---|
| Compile-time product composition and cross-host equality enforcement | `howl-term` | `howl-term` now exists to compose owner-true modules and fail compilation when shared host-facing vocabulary drifts. |
| PTY transport lifecycle, child I/O, resize delivery, control signals | `howl-pty` | PTY owns transport variants and transport behavior. |
| VT parser state, grid state, selection vocabulary, input constants | `howl-vt` | VT owns protocol and terminal-state vocabulary. |
| Render runtime scheduling state, retained-frame queue state, surface metrics | `howl-render` | Render owns prepare and submit scheduling, retained-base validation, and render metrics. |
| Renderer backend execution, target textures, text shaping, glyph upload work | `howl-render` | Backend execution belongs with the renderer owner, not terminal orchestration. |
| Render data model types such as frame snapshots, surface cells, geometry, and cursor payloads | `howl-render` | Render-facing model types must stay backend-neutral and renderer-owned. |
| Host event loop, redraw requests, wake policy, and presentation cadence | `howl-linux-host` | Scheduler policy is host-owned and remains explicit. |

## `howl-term` Boundary

`howl-term` must now stay compile-time-only.

`howl-term` may:
- re-export owner-true lower-module surfaces
- install compile-time equality assertions across those surfaces
- provide umbrella headers only when they add no runtime semantics

`howl-term` must not:
- own runtime lifecycle
- own VT runtime behavior
- own render queue mechanics
- own retained-frame validation
- own renderer backend execution
- reintroduce publish or prepare convenience wrappers that hide render ownership
