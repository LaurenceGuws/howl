# Runtime Debug Noise Slice 2 Handle Correction

Status:

- Active correction research artifact for Slice 2 rejection.
- Orchestrator session id: `orch-2026-06-14-runtime-debug-noise-01`.
- Researcher session id: `research-2026-06-14-runtime-debug-noise-01`.
- Reviewer session id: `review-2026-06-14-runtime-debug-noise-01`.
- Trigger: reviewer rejection of Slice 2 due to missed adjacent prepare-handle timing in `howl-render/src/surface/handle.zig`.
- No Slice 2 acceptance is authorized until this correction is reviewer-accepted and the execution scope is reseeded.

Required output:

- Exact classification of `howl-render/src/surface/handle.zig:10-60` and `handle.zig:73-94`.
- Delete/retain decision with exact rationale.
- Exact allowed files for the reseeded Slice 2 correction.
- Exact proof roots and tests.
- Non-goals, stop conditions, and receipt fields.
