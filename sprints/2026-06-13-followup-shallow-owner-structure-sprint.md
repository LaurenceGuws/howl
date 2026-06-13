# Sprint: Followup Shallow Owner Structure

Date: 2026-06-13.

Owner: orchestrator.

Status: planning seeded; no implementation authorized.

Orchestrator session id: `orch-2026-06-13-followup-shallow-structure-01`.

Researcher session id: `research-2026-06-13-followup-shallow-structure-01`.

Reviewer session id: `review-2026-06-13-followup-shallow-structure-01`.

Commit-hash receipt: root `66927e2`.

## Problem Statement

- The first all-src flattening pass is closed, but follow-up fake abstractions or needless depth may still survive.
- The next sprint should inspect the post-flattened workspace and identify the remaining shallow-depth cleanup with the same discipline pressure.
- The goal remains: shallow `src/` trees, true owner subdomains only, and no fake wrappers or convenience buckets.

## User Direction

- Continue.
- Keep deleting fake abstractions.
- Keep `src/` directories as shallow as possible.
- Use the deleted terminal wrapper as the model.

## Planning Boundary

- Research must re-prove current source shape after root close receipt `8fadea6` and current nested heads.
- All current package `src/` trees remain in scope for inspection.
- Planning must identify what survived the prior sprint and whether it is true owner depth or fake depth.
- Planning must produce exact sequential slices with allowed files, required shape, tests, non-goals, stop conditions, session ids, and receipt demands.

## Execution Authorization

- No coder is authorized.
- The researcher must write `/home/home/personal/projects/howl/research/2026-06-13-followup-shallow-owner-structure-plan.md`.
- The reviewer must gate that plan before any execution slice is seeded.
