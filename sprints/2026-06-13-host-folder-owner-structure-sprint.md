# Sprint: Host Folder Owner Structure

Date: 2026-06-13.

Owner: orchestrator.

Status: reviewer-accepted planning; planning commit-hash receipt pending; no implementation authorized until receipt closes.

Orchestrator session id: `orch-2026-06-13-host-folder-structure-01`.

Researcher session id: `research-2026-06-13-host-folder-structure-01`.

Reviewer session id: `review-2026-06-13-host-folder-structure-01`.

Commit-hash receipt: pending.

## Problem Statement

- `howl-linux-host/src` is now the next obvious file/folder structure offender.
- The user wants the same discipline applied to the host tree that was just applied to render: curated top-level owners only, shallow child folders only where they are real subdomains or per-owner definitions, and intentional naming/location truth.
- Alacritty host/runtime/display/window/input organization is the primary reference pressure here, not Ghostty terminal internals.
- Current host top-level tree likely mixes real owners with weak roots, misplaced headers, and test/root placement debt.

## User Direction

- The next offender for the same cleanup is the host.
- Clean up file and folder locations and naming with discipline and intent.
- Keep only curated owner units under `src`.
- Use shallow child folders for real subdomains only.
- Compare against projects with intentional host/runtime tree structure, especially Alacritty.

## Planning Boundary

- Research must re-prove current host tree facts from current source after root `52418d9` and current nested heads.
- Alacritty host/runtime/display/window/input organization is the main folder/file pressure.
- Ghostty is secondary only where Alacritty has no directly comparable host shape.
- Planning must cover the full host folder/file structure problem, not cosmetic rename subsets, unless the user explicitly narrows scope.
- Planning must produce sequential slices with exact allowed files, required shape, tests, non-goals, stop conditions, accountable session ids, and commit-hash receipt demands.

## Execution Authorization

- The reviewer accepted the planning package in session `review-2026-06-13-host-folder-structure-01`.
- The accepted research artifact is `/home/home/personal/projects/howl/research/2026-06-13-host-folder-owner-structure-plan.md`.
- Planning commit-hash receipt is still pending, so no coder is authorized yet.
- After the planning receipt closes, orchestrator may seed only Slice 1 from the accepted research plan.
