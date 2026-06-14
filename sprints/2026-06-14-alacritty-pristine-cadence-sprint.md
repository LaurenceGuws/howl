# Alacritty Pristine Cadence Sprint

Status:

- Active sprint contract.
- Orchestrator session id: `orch-2026-06-14-ascii-rain-performance-01`.
- Researcher session id: `research-2026-06-14-ascii-rain-performance-01`.
- Reviewer session id: `review-2026-06-14-ascii-rain-performance-01`.
- Planning seed receipt: root commit `9b2b4b0`.
- Accepted planning receipt: reviewer `review-2026-06-14-ascii-rain-performance-01` accepted the active refocus and 7-cut section plan after commit `9b2b4b0`.
- Sprint seed receipt: Cut 1 is now authorized for coder execution.

Goal:

- Beat Alacritty on the benchmark.
- Get there by making Howl pristine, pragmatic, and idiomatic rather than by chasing bucket slop.
- Remove bolted-on ownership, stale wake/present cadence, and fake narrow-cut progress before any micro-optimization is allowed.

Current section:

- Host/runtime present cadence and cursor truth.
- Prove whether Howl is replaying stale intermediate content/cursor states instead of presenting the latest current state under redraw pressure.
- Treat wake admission, runtime drive, retained submit, present completion, and cursor state as one real owner boundary.

Active constraints:

- Micro-optimization is banned until the codebase is much more pragmatic and idiomatic than Alacritty.
- Fake narrow cuts and fake small cuts are banned.
- The rejected ASCII-rain `direct_normal` next-step is not live authority.
- Proof remains required, but proof exists to name the real owner boundary, not to justify bucket tuning.

Current authorized step:

- Coder may implement Cut 1: make the present lifecycle explicit and single-owned.
- Cut 1 remains inside this sprint section and is the only authorized coder work right now.
