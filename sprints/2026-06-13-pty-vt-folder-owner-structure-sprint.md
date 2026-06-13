# Sprint: PTY VT Folder Owner Structure

Date: 2026-06-13.

Owner: orchestrator.

Status: remaining plan reviewer-accepted after explicit user override; plan repair receipt pending.

Orchestrator session id: `orch-2026-06-13-pty-vt-folder-structure-01`.

Researcher session id: `research-2026-06-13-pty-vt-folder-structure-01`.

Reviewer session id: `review-2026-06-13-pty-vt-folder-structure-01`.

Commit-hash receipt: root `efbd9ad`.

## Problem Statement

- PTY is small enough that PTY and VT folder/file owner cleanup can be planned together in one accountable sprint.
- `howl-pty/src` and `howl-vt/src` still likely carry folder/file placement debt compared to Ghostty's deliberate `terminal/` and `termio/` structure.
- The goal is not behavior redesign first; it is to cut the folder tree and top-level owner set so PTY and VT read with the same discipline and intent as the references.
- Ghostty is the primary source pressure for VT and PTY/termio seams; Alacritty sharpens PTY/runtime/event-loop boundaries where useful.

## User Direction

- PTY and VT together are the next cleanup target.
- PTY is small, so do them together.
- Clean up file and folder locations and naming with discipline and intent.
- Keep only curated owner units under `src` and use shallow child folders only for true subdomains or per-owner definitions.

## Planning Boundary

- Research must re-prove current PTY and VT tree facts from current source after root `39e0e82` and current nested heads.
- Ghostty terminal and termio structure is the main folder/file pressure.
- Alacritty terminal/event_loop/tty pressure is secondary where it sharpens PTY or runtime folder boundaries.
- Planning must cover the full PTY+VT folder/file structure problem, not cosmetic rename subsets, unless the user explicitly narrows scope.
- Planning must produce sequential slices with exact allowed files, required shape, tests, non-goals, stop conditions, accountable session ids, and commit-hash receipt demands.

## Reviewer Gate

- Research plan accepted after reviewer repair.
- Reviewer finding repaired: VT unit proofs under `src/**/*_test.zig` must move out of `src` in Slice 2, and later slices must update proof imports directly against moved owner paths.

## Execution Authorization

- Slice 3 is authorized through the live-loop execution contract only.
- The accepted slice plan is `/home/home/personal/projects/howl/research/2026-06-13-pty-vt-folder-owner-structure-plan.md`.
- No other PTY or VT work is authorized.

## Slice Receipts

- Slice 1, `PTY proof-root relocation out of src`: `howl-pty` `13b7fbd`; root `2718455`.
- Slice 2, `VT proof and non-product roots out of src`: `howl-vt` `556ab69`; root `921f630`.
- Slice 3, `VT terminal core root establishment`: `howl-vt` `20fb714`; root `4a4fec4`.

## Explicit User Override

- User decision: Slice 5 must delete `howl-vt/src/terminal/` and move all of its contents back into `howl-vt/src/` because `terminal/` makes the folders one level deeper for no reason.
- Reference overridden: Ghostty-shaped `src/terminal/` VT-core subdomain pressure.
- Reason: the user rejected the extra Howl folder depth as unjustified.
- Orchestrator session id: `orch-2026-06-13-pty-vt-folder-structure-01`.
- Approval receipt: user message in the active conversation, quoted in the active research artifact.
