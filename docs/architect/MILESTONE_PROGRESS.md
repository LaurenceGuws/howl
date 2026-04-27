# Parent Milestone Progress

This board tracks parent-level coordination state. Module-specific milestone
state stays in each child repo.

| Sprint | Status | Authority | Review | Current Queue |
| --- | --- | --- | --- | --- |
| Product structure hygiene | closed | `architecture_docs/authority/ENGINEERING_CONVENTIONS.md`, `architecture_docs/authority/MVP_STRUCTURE.md` | `docs/architect/product_structure/REVIEW.md` | `docs/engineer/ACTIVE_QUEUE.md` |
| MVP scope alignment and cleanup | closed | `architecture_docs/authority/MILESTONES.md`, `architecture_docs/authority/MODULE_MAP.md`, `architecture_docs/authority/DEPENDENCY_RULES.md`, `architecture_docs/authority/INTEGRATION_FLOW.md`, `architecture_docs/authority/MVP_STRUCTURE.md` | `docs/architect/mvp_scope_alignment/REVIEW.md` | `docs/engineer/ACTIVE_QUEUE.md` |
| Scoped MVP completion | active | same as above, plus participating child repo authorities | `docs/architect/mvp_scope_alignment/REVIEW.md` | `docs/engineer/ACTIVE_QUEUE.md` |

## Active Sprint Goal

Finish the first scoped Linux MVP through runtime truth:

- SDL host shows real text through `howl-term` -> `render-core` -> `howl-render-gl`
- SDL host runs an interactive shell with correct input, resize, and shutdown
- render-core and GL evidence reflect runtime truth, not just contract structure
- Android remains a working proof host over the same terminal-boundary API
- release evidence reflects runtime truth, not milestone labels

## Closed Sprint Goals

**MVP scope alignment and cleanup** (closed 2026-04-27): Brought parent
authority, child repo authorities, queue state, naming discipline, and runtime
status language into one coherent model. Residual debt recorded in
`docs/architect/mvp_scope_alignment/CHECKPOINTS.md`.
