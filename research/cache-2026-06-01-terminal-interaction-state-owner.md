# Terminal Interaction State Owner Cache

Date: 2026-06-01

## Sources Read

- `AGENTS.md`
- `loop.txt`
- `research/2026-06-01-terminal-input-sprint.md`
- `howl-linux-host/src/terminal/context.zig`
- `howl-linux-host/src/terminal/links.zig`
- `howl-linux-host/src/terminal/selection.zig`

## Current-Code Facts

- `terminal/links.zig` already owned hyperlink hover behavior, cursor switching, hover decoration, and link opening.
- `terminal/selection.zig` already owned host mouse selection behavior.
- Before this cut, `Context` stored link state as flat fields: link cursor activity, hovered link cell, and hover publish pending.
- Before this cut, `Context` stored selection state as flat fields: selection anchor and drag activity.
- The owner files mutated those flat fields through `anytype`, which hid ownership and made `Context` a broader interaction-state bucket.

## Accepted Shape

- Add `terminal_links.State` with only link-owned state.
- Add `terminal_selection.State` with only selection-owned state.
- Replace flat `Context` fields with `links: terminal_links.State` and `selection: terminal_selection.State`.
- Keep behavior in existing owner files; do not create a new broad terminal chrome/UI/overlay owner.

## Verification

- `zig build check`: passed.
- `zig build test --summary all`: passed, 130/130 tests.
- `zig build -Doptimize=ReleaseFast`: passed.
- `git diff --check`: passed.
- Changed-file line scan over 190 chars: passed.
- Reviewer accepted with no findings.
- Host commit: `2b314db host: move terminal interaction state to owners`.

## Follow-Up

- Continue reducing flat `Context` ownership only where an existing shallow owner already owns behavior.
- Do not introduce a broad terminal chrome/UI/overlay owner.
