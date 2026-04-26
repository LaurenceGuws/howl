# Parent Milestone Progress

This board tracks parent-level coordination state. Module-specific milestone
state stays in each child repo.

| Sprint | Status | Authority | Review | Current Queue |
| --- | --- | --- | --- | --- |
| Product structure hygiene | closed | `architecture_docs/authority/ENGINEERING_CONVENTIONS.md`, `architecture_docs/authority/MVP_STRUCTURE.md` | `docs/architect/product_structure/REVIEW.md` | `docs/engineer/ACTIVE_QUEUE.md` |
| MVP scope alignment and cleanup | active | `architecture_docs/authority/MILESTONES.md`, `architecture_docs/authority/MODULE_MAP.md`, `architecture_docs/authority/DEPENDENCY_RULES.md`, `architecture_docs/authority/INTEGRATION_FLOW.md`, `architecture_docs/authority/MVP_STRUCTURE.md` | `docs/architect/mvp_scope_alignment/REVIEW.md` | `docs/engineer/ACTIVE_QUEUE.md` |
| Scoped MVP completion | planned | same as above, plus participating child repo authorities | `docs/architect/mvp_scope_alignment/REVIEW.md` | `docs/engineer/ACTIVE_QUEUE.md` |

## Active Sprint Goal

Bring parent authority, child repo authorities, queue state, naming discipline,
and runtime status language back into one coherent model:

- hosts are platform shells
- the current `howl-term-surface` repo owns the effective `howl-term` boundary
- session remains the shared runtime
- render-core remains the sole render-policy owner
- backends remain thin executors
- Android remains a proof host, not the first Linux MVP blocker

## Next Sprint Goal

Finish the first scoped Linux MVP honestly:

- SDL host shows real text
- SDL host runs an interactive shell correctly
- resize/input/shutdown are stable
- release evidence reflects runtime truth
