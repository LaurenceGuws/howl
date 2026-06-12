# Sprint: Render API Pragmatic Shape

Date: 2026-06-12.

Owner: orchestrator.

Status: active sprint framing.

Orchestrator session id: `orch-2026-06-11-ascii-rain-honest-performance-02`.

Commit-hash receipt: pending.

## Problem Statement

- `howl-render` is too large, too Howl-specific, and too weak in product result for its size.
- The current renderer machinery is not small or pragmatic enough to justify continued micro-optimizations.
- The next sprint must make render API the example of a smaller, more pragmatic shape than Alacritty, while still learning from Alacritty first.

## User Direction

- Stop deferring around ASCII-rain micro-bottlenecks first.
- Tackle the larger blocker first: the oversized renderer.
- Shrink `howl-render`.
- Port Alacritty render/API shape into Zig where it fits.
- Start with render API.
- Make render API smaller and more pragmatic than Alacritty.

## Reference Pressure

- For render API design specifically:
  - Alacritty first for pragmatic, idiomatic renderer organization and API pressure.
  - Kitty second for UX and quality pressure.
  - Ghostty only for embedding pressure when the slice is explicitly about embedding.
- Existing Howl render shape is presumed wrong until references prove it right.

## Planning Boundary

- This sprint starts with reference-first planning, not implementation.
- No worker execution is authorized until researcher and reviewer accept one explicit slice.
- Accepted slices must favor subtraction, owner collapse, and clearer hot-path shape over one-off optimizations.

## Sequential Expectation

- 1. Research the Alacritty render/content/API shape against current `howl-render`.
- 2. Review and cut one narrow accepted simplification slice.
- 3. Implement and verify that slice.
- 4. Repeat until the renderer is materially smaller and more pragmatic.

## Immediate Goal

- Produce one accepted research artifact that identifies the first render-API simplification slice.

## Execution Authorization

- Execution is authorized only through exact slices seeded in the active loop.
- The first authorized move is research and reviewer planning for render API simplification.
