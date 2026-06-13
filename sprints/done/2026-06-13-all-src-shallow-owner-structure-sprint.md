Historical authority: sprint artifact for the 2026-06-13 all-src shallow owner structure sprint.

Why superseded or done: sprint closed with final root receipts `5b7b48d` and `8fadea6`.

Must not be used for: current follow-up shallow-depth cleanup authority, execution authorization, or live planning.

# Sprint: All Src Shallow Owner Structure

Date: 2026-06-13.

Owner: orchestrator.

Status: closed.

## Slice Receipts

- Slice 1, `PTY src/pty/ Depth Deletion`: `howl-pty` `714d41c`; root `3e0b50e`.
- Slice 2, `VT Fake Folder Deletion`: `howl-vt` `da25b16`; root `861d909`.
- Slice 3, `Render Root Geometry And Text Classification Flattening`: `howl-render` `d4445e3`; root `100be01`.
- Slice 4, `Host One-Extra-Depth Deletion`: `howl-linux-host` `4b0b995`; root `5bc58e4`.
- Slice 5, `Workspace Aggregate Verification And Empty-Directory Audit`: root `5b7b48d`.

## Close Status

- Sprint implementation complete.
- Final close receipt: `5b7b48d`.

Orchestrator session id: `orch-2026-06-13-all-src-shallow-structure-01`.

Researcher session id: `research-2026-06-13-all-src-shallow-structure-01`.

Reviewer session id: `review-2026-06-13-all-src-shallow-structure-01`.

Commit-hash receipt: root `16a877d`.

## Problem Statement

- Restart the folder-depth cleanup at workspace scale.
- Every package `src/` tree should be as shallow as possible without losing owner truth.
- Fake abstraction directories and needless wrapper folders must be deleted, like the final removal of `howl-vt/src/terminal/`.
- The sprint must identify real owners, true subdomains, and fake depth across all current `src/` trees before implementation.

## User Direction

- "restart the sprint"
- "I want the dir's in all the src/ dirs as shallow as possible"
- "delete fake abstrations"
- "Like we just did with the terminal folder"

## Planning Boundary

- Research must re-prove current source shape after PTY+VT close receipt `2ec1f24` and nested package heads.
- All package `src/` directories in the workspace are in planning scope.
- Planning must distinguish true owner subdomains from fake abstraction/wrapper depth.
- Planning must produce sequential slices with exact allowed files, required shape, tests, non-goals, stop conditions, session ids, and commit-hash receipt demands.

## Execution Authorization

- Slice 2 is authorized through the live-loop execution contract only.
- The accepted plan is `/home/home/personal/projects/howl/research/2026-06-13-all-src-shallow-owner-structure-plan.md`.
- No other slice is authorized.

## Planning Receipts

- Sprint seed: root `16a877d`.
- Sprint seed receipt: root `3425e62`.
- Planning package acceptance: root `c69e039`.
