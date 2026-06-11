# Sprint: Text Empty Clear Background Repair

Date: 2026-06-11.

Owner: orchestrator.

Status: active execution slice.

Orchestrator session id: `orch-2026-06-11-text-empty-clear-background-repair-01`.
Execution reviewer session id: `review-2026-06-11-text-empty-clear-background-repair-01`.
Required coder session id: `coder-2026-06-11-text-empty-clear-background-repair-01`.
Required commit-hash receipt: required before slice acceptance.

## User Direction

- Diagnose the new background defect seen in curses-style delete and clear workloads after the completed text sprint.
- Continue autonomously unless reviewer returns `user needed`.

## Problem

- Delete-heavy partial updates now produce black or wrong-color background rectangles under apps like `/usr/bin/rain`.
- Current render path keeps semantic empty/default-background truth in source mapping, but still drops `empty` cells before the scene background and clear owners run.
- That leaves partial-damage clear spans with no surviving background witness, so clear fallback collapses to black.

## Exact Slice

Slice name: `text-empty-clear-background-repair`.

## Allowed Files

- `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/scene.zig`

## Required Shape

- Keep cleared `empty` cells alive through renderable ownership so scene background and clear policy can see their background truth.
- Do not revive blank glyph rasterization just to preserve background ownership.
- Prove that partial-damage cleared spans use terminal background truth rather than black fallback when the dirty region contains cleared default-background cells.

## Required Assertions

- Assert blank or empty cells preserved for scene ownership do not emit sprite draws in the direct-normal lane.
- Assert partial-damage clear color derives from surviving cleared-cell background truth when such a witness exists.

## Required Tests

- `zig build test:unit -- "sparse cells keep empty background witnesses for scene ownership"`
- `zig build test:unit -- "text preparation partial damage clears use empty default background truth"`
- `zig build test:unit -- "text preparation direct-renders pure normal cell text inputs"`

Run from:

- `/home/home/personal/projects/howl/howl-render`

## Non-Goals

- No new text owner redesign.
- No ABI changes.
- No host-side renderer work.

## Stop Conditions

- Stop if the fix needs files outside the allowed set.
- Stop if preserving cleared background truth requires changing shipped source or publication ABI layouts.

## Reviewer Gate

- Reviewer must reject any fix that restores mapper-side hacks instead of preserving ownership through renderables.
- Reviewer must reject any fix that reintroduces blank glyph sprite emission.
- Reviewer must reject any proof that does not cover partial-damage cleared default-background cells.
