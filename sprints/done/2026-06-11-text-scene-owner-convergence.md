# Sprint: Text Scene Owner Convergence

Date: 2026-06-11.

Owner: orchestrator.

Status: accepted and committed in `howl-render` `74db9a4`.

Orchestrator session id: `orch-2026-06-11-text-scene-owner-convergence-01`.
Planning orchestrator session id: `orch-2026-06-10-test-accountability-01`.
Planning researcher session ids:
- `research-2026-06-10-text-sprint-01`
- `research-2026-06-10-text-sprint-01-c1`
Execution reviewer session id: `review-2026-06-11-text-scene-owner-convergence-01`.
Planning reviewer session id: `review-2026-06-10-text-sprint-01`.
Required coder session id: `coder-2026-06-11-text-scene-owner-convergence-01`.
Required commit-hash receipt: fulfilled by `howl-render` commit `74db9a4`.

## Accepted Result

- `scene.zig` now owns behavioral draw construction for backgrounds, clears, cursor draws, and non-glyph decoration draws.
- `direct_scene.zig` is reduced to adapter/data-transport behavior.
- Clear-color policy is converged across normal-only and mixed or complex paths.

## Verification

- `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "scene emits background draws from non-continuation cells"`
- `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "scene emits explicit clears for transparent default backgrounds on partial damage"`
- `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "text preparation direct-renders pure normal cell text inputs"`
- `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "text preparation marks curly underline cells complex before shaping"`
