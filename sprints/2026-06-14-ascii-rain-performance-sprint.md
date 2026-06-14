# ASCII Rain Performance Sprint

Status:

- Active performance sprint contract.
- Orchestrator session id: `orch-2026-06-14-ascii-rain-performance-01`.
- Researcher session id: `research-2026-06-14-ascii-rain-performance-01`.
- Reviewer session id: `review-2026-06-14-ascii-rain-performance-01`.
- Planning seed receipt: pending.
- Accepted planning receipt: pending.
- Sprint seed receipt: pending.

Goal:

- Get Howl as close to Alacritty as possible on the current ASCII rain benchmark.
- Stop only when Alacritty is matched or the next real debt blocker becomes clear.
- Require measured runtime proof before every optimization pass.
- Use the sprint to pressure fake owners out of the hot path; when proof exposes a mixed hot owner, clean that owner before optimizing through bad style.

Explicit user override:

- The user explicitly overrode the normal researcher-first planning order for this sprint.
- Authorized iteration order for this sprint only:
  1. coder hotspot proof
  2. researcher and reviewer interpretation using proof plus Alacritty
  3. coder fix slice
  4. reviewer correctness and benchmark review
  5. coder cleanup slice removing probes
  6. coder next bottleneck proof
  7. repeat

Authoritative benchmark:

- `python3 utils/tools/rain-bench/benchmark_terminals.py --build`

Active iteration state:

- Iteration 1 proof stage is complete.
- Iteration 1 optimization implementation was reviewed and rejected.
- Current stage is post-proof interpretation of corrected slice 29 at `direct_normal.appendResolvedGlyph(...)`.
- The controlling active loop artifact is `loops/ascii-rain-performance-live-loop.txt`.
- The active research artifact is `research/2026-06-14-ascii-rain-performance-plan.md`.

Current authorized slice:

- Authorized next step: interpret proof slice 29 and authorize only the next exact local move supported by that receipt.
- No optimization slice is authorized until that fake-owner cleanup lands and cleaned-code proof names the next target.
