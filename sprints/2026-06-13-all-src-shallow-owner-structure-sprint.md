# Sprint: All Src Shallow Owner Structure

Date: 2026-06-13.

Owner: orchestrator.

Status: planning seeded; no implementation authorized.

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

- No coder is authorized.
- The researcher must write `/home/home/personal/projects/howl/research/2026-06-13-all-src-shallow-owner-structure-plan.md`.
- The reviewer must gate that research package before any implementation slice is seeded.
