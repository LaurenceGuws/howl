# Runtime Debug Noise Cleanup Plan

Status:

- Active research artifact for planning.
- Researcher session id: `research-2026-06-14-runtime-debug-noise-01`.
- Reviewer session id: `review-2026-06-14-runtime-debug-noise-01`.
- Not accepted yet.
- No implementation is authorized from this file until reviewer acceptance is recorded and the orchestrator seeds execution slices.

Required output:

- Sources read in order.
- Exact target file and line references.
- Current-code facts.
- Reference facts and compact anchor map.
- Block-level inventory of debug-shaped code in:
  - `howl-render/src/surface/emitter.zig`
  - `howl-render/src/render_session.zig`
  - `howl-linux-host/src/terminal/surface.zig`
  - `howl-render/src/surface/realizer.zig`
- Classification for each candidate block:
  - runtime truth
  - proof-only scaffolding
  - benchmark-only scaffolding
  - stale migration residue
- Action for each candidate block:
  - delete
  - move to proof/benchmark root
  - retain as runtime truth
- Exact proof roots for each touched owner.
- Ordered execution slice plan with exact allowed files, required shape, tests, non-goals, stop conditions, session ids, and receipt fields.
- Risks, proof gaps, readiness judgment.
