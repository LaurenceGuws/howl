# Sprint: Text Empty Clear Background Repair

Date: 2026-06-11.

Owner: orchestrator.

Status: accepted and committed in `howl-render` `5a88a10`.

Orchestrator session id: `orch-2026-06-11-text-empty-clear-background-repair-01`.
Execution reviewer session id: `review-2026-06-11-text-empty-clear-background-repair-01`.
Required coder session id: `coder-2026-06-11-text-empty-clear-background-repair-01`.
Required commit-hash receipt: fulfilled by `howl-render` commit `5a88a10`.

## Accepted Result

- Cleared `empty` cells now survive renderable ownership long enough for scene clear and background policy to use their background truth.
- Blank glyph sprite emission stays suppressed on the preserved empty-cell path.
- Partial-damage clear spans no longer fall back to black when they have a surviving cleared-cell background witness.

## Verification

- `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "sparse cells keep empty background witnesses for scene ownership"`
- `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "text preparation partial damage clears use empty default background truth"`
- `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "text preparation publication clears use empty default background truth"`
- `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "text preparation direct-renders pure normal cell text inputs"`
