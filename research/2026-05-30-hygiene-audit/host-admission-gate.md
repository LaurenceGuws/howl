# Host Admission Gate

Date: 2026-05-30

## Purpose

Prevent fake host progress. Future host hygiene slices must prove exact ownership before editing
`howl-linux-host/src/main.zig` or splitting host control flow.

## Sources Read

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `AGENTS.md`
- `loop.txt`
- `project-memory.md` host sections
- `research/2026-05-30-hygiene-audit/roadmap.md` Slice 5.1

## Gate Rules

- `main.zig` remains the app/event-loop owner unless a slice proves a smaller exact owner with
  source and reference backing.
- Do not add top-level app structs, managers, controllers, runtimes, or convenience buckets to
  `main.zig`.
- Do not split `main.zig` merely because it is large.
- Future extractions must name the exact state they own, its invariants, its tests, and its caller
  boundary before implementation.
- Host code consumes PTY, VT, and render only through shipped C ABI contracts and build-owned
  translated modules.
- Per-terminal `Context` remains the embedded terminal widget/session aggregate unless a slice proves
  a narrower owner.
- Main-thread sequencing and wait/present admission stay centralized; leaf owners do not seize loop
  policy.

## Required Slice Seed For Host Code Movement

Every host implementation slice must name:

- exact files and symbols read before editing;
- exact fields/functions moved or intentionally left in place;
- source-order reference facts from Alacritty, Ghostty, TigerBeetle, or official docs;
- tests that prove behavior;
- grep gates proving no `manager`, `controller`, `runtime`, `types.zig`, or Zig-shaped ABI bypass was
  introduced;
- stop conditions for event-loop, render-turn, clipboard, PTY, VT, or render boundary creep.

## Accepted Host Direction Preserved

- Top-level app/event processor owns event-loop dispatch, tab/window list, scheduler/pacing, and
  routing.
- Per-terminal context owns one embedded terminal widget/session and exposes exact effects to the app.
- Window/display/present owners own backend realization and presentation.
- Input owner translates SDL events into host input events but must not own terminal widget policy.
- Cross-thread/wake paths stay bounded and explicit.

## Grep Gate

- `rg 'main\.zig|app ownership|runtime|controller|manager' research/2026-05-30-hygiene-audit/host-admission-gate.md`

## Verification

- `git diff --check`
