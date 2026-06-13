# Sprint: Render Folder Owner Structure

Date: 2026-06-13.

Owner: orchestrator.

Status: reviewer-accepted planning; planning commit-hash receipt pending; no implementation authorized until receipt closes.

Orchestrator session id: `orch-2026-06-13-render-folder-structure-01`.

Researcher session id: `research-2026-06-13-render-folder-structure-01`.

Reviewer session id: `review-2026-06-13-render-folder-structure-01`.

Commit-hash receipt: pending.

## Problem Statement

- `howl-render/src` still lacks disciplined folder and file structure even after the owner surgery sprint.
- The user wants only curated owner units directly under `src`, with shallow child folders used only for real subdomains or per-owner definitions.
- Current render naming and placement still looks undisciplined compared to Ghostty terminal structure.
- Empty or half-dead directories like `src/session/` are direct evidence that folder authority is still sloppy.
- Top-level roots, helper files, and child folders must be recut so the folder tree itself expresses true owner boundaries.

## User Direction

- Clean up file and folder locations and naming.
- Keep only curated owner units in `src`.
- Use shallow folders for per-owner definitions only.
- Study `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal` and its child folders for deliberate structure.
- Current render API still looks like a joke compared to a disciplined project; fix that accountable structure, not just code internals.

## Planning Boundary

- Research must re-prove current folder/file facts from current source after root `57bba4b` and current nested heads.
- Research must use Ghostty folder structure as explicit pressure, with Alacritty still governing renderer organization where more applicable.
- Planning must cover the full folder/file owner-structure problem, not a cosmetic rename subset, unless the user explicitly narrows scope.
- Planning must produce sequential slices with exact allowed files, required shape, tests, non-goals, stop conditions, accountable session ids, and commit-hash receipt demands.

## Execution Authorization

- The reviewer accepted the planning package in session `review-2026-06-13-render-folder-structure-01`.
- The accepted research artifact is `/home/home/personal/projects/howl/research/2026-06-13-render-folder-owner-structure-plan.md`.
- Planning commit-hash receipt is still pending, so no coder is authorized yet.
- After the planning receipt closes, orchestrator may seed only Slice 1 from the accepted research plan.
