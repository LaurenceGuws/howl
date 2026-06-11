# Sprint: Text Style Attrs Render Policy Owner

Date: 2026-06-11.

Owner: orchestrator.

Status: accepted and committed in `howl-render` `3a79b00`.

Orchestrator session id: `orch-2026-06-11-text-style-attrs-render-policy-owner-01`.
Planning orchestrator session id: `orch-2026-06-10-test-accountability-01`.
Planning researcher session ids:
- `research-2026-06-10-text-sprint-01`
- `research-2026-06-10-text-sprint-01-c1`
- `research-2026-06-10-text-sprint-01-c2`
- `research-2026-06-10-text-sprint-01-c3`
Execution reviewer session id: `review-2026-06-11-text-style-attrs-render-policy-owner-01`.
Planning reviewer session id: `review-2026-06-10-text-sprint-01`.
Required coder session id: `coder-2026-06-11-text-style-attrs-render-policy-owner-01`.
Required commit-hash receipt: fulfilled by `howl-render` commit `3a79b00`.

## Accepted Result

- Dim and invisible now cross the text seam as semantic style facts.
- `text/scene.zig` is the single render-time dim policy owner using Kitty `dim_opacity = 0.4` as alpha-only policy.
- Prepared realization consumes draw alpha unchanged and no longer carries independent dim policy.

## Verification

- `cd /home/home/personal/projects/howl/howl-render && zig build test:abi -- "source text input maps publication style attrs dim and invisible"`
- `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "text scene applies kitty dim opacity at render-time for sprite draws"`
- `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "render surface surface emitter realizes kitty dim alpha sprite equal to full rgba oracle"`
- `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "render surface prepared owner surface equals kitty dim rgba oracle"`
- `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "publication cell map keeps default background truth through inverse and selection"`
