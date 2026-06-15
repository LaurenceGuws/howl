# Alacritty Pristine Cadence Sprint

Status:

- Active sprint contract.
- Orchestrator session id: `orch-2026-06-14-ascii-rain-performance-01`.
- Researcher session id: `research-2026-06-14-ascii-rain-performance-01`.
- Reviewer session id: `review-2026-06-14-ascii-rain-performance-01`.
- Planning seed receipt: root commit `9b2b4b0`.
- Accepted planning receipt: reviewer `review-2026-06-14-ascii-rain-performance-01` accepted the active refocus and 7-cut section plan after commit `9b2b4b0`.
- Sprint seed receipt: Cut 1 committed as `c925170`; Cut 2 committed as `93e9224`; Cut 3 committed as `3aa9621`; Cut 4 committed as `667fb1a`; Cut 5 committed as `16dc836`; Cut 6 committed as `5af42d9`; Cut 7 committed as `3e15ab4`, all accepted by reviewer `review-2026-06-14-ascii-rain-performance-01`.

Goal:

- Beat Alacritty on the benchmark.
- Get there by making Howl pristine, pragmatic, and idiomatic rather than by chasing bucket slop.
- Remove bolted-on ownership, stale wake/present cadence, fake narrow-cut progress, and untruthful cursor behavior before any micro-optimization is allowed.

Current section:

- Kitty cursor parity rewrite.
- Rewrite Howl cursor truth, rendering, cadence, protocol, config, and ABI to full Kitty cursor feature parity.
- Treat VT semantic cursor truth, render cursor presentation, host cadence, config, ABI seams, and multiple-cursor protocol/rendering as one real owner boundary.

Active constraints:

- Micro-optimization is banned until the codebase is much more pragmatic and idiomatic than Alacritty.
- Fake narrow cuts and fake small cuts are banned.
- The rejected ASCII-rain `direct_normal` next-step is not live authority.
- Proof remains required, but proof exists to name the real owner boundary, not to justify bucket tuning.
- Kitty cursor parity is the target with no default deferrals.

Current authorized step:

- The Kitty cursor parity worker-ready sprint document is accepted under the explicit user override to use Kitty pressure.
- Slice 1, rebuild VT semantic cursor truth and protocol vocabulary, is accepted and committed in `howl-vt` commit `15caf66` after reviewer acceptance.
- Slice 2, widen the VT/render ABI and publication seam for full cursor truth, is accepted and committed in `howl-vt` commit `82addbf`, `howl-render` commit `ec49cb2`, and `howl-linux-host` commit `7805b98` after reviewer acceptance.
- Slice 3, introduce render-owned cursor presentation data, is accepted and committed in `howl-render` commit `9f48e1d` after reviewer acceptance.
- Slice 4, rebuild cursor primitive emission for main cursor and cursor trail, is accepted and committed in `howl-render` commit `b04de62` after reviewer acceptance.
- Slice 5, rebuild host cadence, focus policy, inactivity stop, and cursor trail timing, is accepted and committed in `howl-linux-host` commit `8da1886` and `howl-render` commit `a13e92c` after reviewer acceptance.
- Slice 6, add Kitty cursor config parity and thread it through owners, is accepted and committed in `howl-linux-host` commit `bf52a3a` and `howl-render` commit `44ccb9f` after reviewer acceptance.
- Coder may implement Slice 7: complete multiple-cursor export, render mapping, and drawing parity.
- Slice 7 is the only authorized coder work right now.
