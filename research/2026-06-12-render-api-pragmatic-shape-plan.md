Render API pragmatic shape plan

Date: 2026-06-12.
Status: active researcher target.
Role owner: researcher.
Orchestrator session id: `orch-2026-06-11-ascii-rain-honest-performance-02`.
Researcher session id: pending.
Reviewer session id: pending.
Planning commit-hash receipt: pending.

Question:

- What is the first render-API simplification slice that makes `howl-render` smaller and more pragmatic, while pulling its shape toward Alacritty and keeping Howl’s embeddable boundary honest?

Required reads:

- `/home/home/personal/projects/howl/AGENTS.md`
- `/home/home/personal/projects/howl/loop/flow.md`
- `/home/home/personal/projects/howl/loop/orcestrator.md`
- `/home/home/personal/projects/howl/loop/researcher.md`
- `/home/home/personal/projects/howl/loop/reviewer.md`
- `/home/home/personal/projects/howl/loop/coder.md`
- `/home/home/personal/projects/howl/reference-index.md`
- `/home/home/personal/projects/howl/sprints/current.txt`
- `/home/home/personal/projects/howl/loops/render-api-pragmatic-shape-live-loop.txt`
- current `howl-render` public roots and render API owners
- Alacritty render/content/text entry seams most relevant to render API shape
- Kitty only where UX/quality pressure matters

Stable reference anchors and owner seams:

- Alacritty first for renderer organization and API pressure.
- Current Howl render API roots, public exports, render-surface contracts, and prepared/emitter ownership.

Compact anchor map:

- Current Howl public render/API seams to inspect first:
  - `howl-render/src/root.zig`
  - `howl-render/src/api/`
  - `howl-render/src/prepared/`
  - `howl-render/src/render_surface*`
- Nearest Alacritty render/content seams to compare against first:
  - `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs`
  - `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs`
  - `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs`
  - `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/atlas.rs`
- First questions the research must answer:
  - which current Howl public render API owners have no Alacritty-shaped pressure
  - which current file boundaries are broader or more fragmented than Alacritty
  - which exported render-surface/public API facts can be collapsed or sharpened without violating the embeddable boundary
  - which Howl-only concepts are the biggest contributors to size without pragmatic payoff

Compact anchor-map requirement:

- The research output must contain a compact anchor map showing:
  - current Howl render API owners
  - nearest Alacritty concept/file boundaries
  - exact mismatch that makes Howl too large or non-pragmatic

Output contract:

- Produce one reviewer-acceptable first slice with:
  - exact allowed files
  - exact required shape
  - exact tests
  - exact non-goals
  - exact stop conditions
  - exact receipt fields
- Or stop and say why no honest first slice exists yet.

Required receipt fields:

- researcher session id
- sources read in order
- exact current Howl files inspected
- exact Alacritty reference files inspected
- compact anchor map with file references
- exact mismatch statement for the chosen first slice
- exact allowed files
- exact required shape
- exact tests
- exact non-goals
- exact stop conditions
- open proof gaps
- readiness judgment

Planning scope:

- Start with render API and its immediate owner seams.
- Favor subtraction, owner collapse, and pragmatic file/API boundaries.
- Do not broaden into whole-renderer rewrites in one step.

Explicit stop conditions:

- Stop if reference pressure cannot yet identify one accountable first slice.
- Stop if the first proposed slice depends on a user override against Alacritty without a receipt.
- Stop if the slice would require broad multi-owner invention rather than simplification.

Readiness judgment:

- Pending researcher pass.
