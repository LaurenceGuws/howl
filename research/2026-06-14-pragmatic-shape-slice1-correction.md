# Pragmatic Shape Slice 1 Correction

Status:

- Active correction research artifact for rejected pragmatic-shape Slice 1.
- Orchestrator session id: `orch-2026-06-14-six-target-pragmatic-shape-01`.
- Researcher session id: `research-2026-06-14-six-target-pragmatic-shape-01`.
- Reviewer session id: `review-2026-06-14-six-target-pragmatic-shape-01`.
- Trigger: reviewer rejection of Slice 1 because `support.zig` still exposes ownership-probing `anytype` and context-extraction wrappers.
- No Slice 1 acceptance is authorized until this correction is reviewer-accepted and the execution scope is reseeded.

Required output:

- Exact inventory of remaining ownership-probing wrappers in `howl-render/src/text/ft_hb/support.zig`.
- Exact remaining callers that still depend on those wrappers.
- Exact allowed-file expansion required to finish the cleanup without compatibility shims.
- Exact tests, non-goals, stop conditions, and receipt fields for the corrected Slice 1.
