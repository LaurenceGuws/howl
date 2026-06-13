Historical authority: sprint artifact for the 2026-06-12 whole-workspace minification sprint.

Why superseded or done: sprint closed with final receipt root commit `22454e3` recording Slice 13 root close `d19a88c`.

Must not be used for: current sprint authority, new render API ownership planning, or execution authorization.

# Sprint: Whole Workspace Minification

Date: 2026-06-12.

Owner: orchestrator.

Status: reviewer-accepted planning; first slice seeded for execution.

Orchestrator session id: `orch-2026-06-12-minify-sloppy-code-01`.

Researcher session id: `research-2026-06-12-minify-sloppy-code-01`.

Reviewer session id: `review-2026-06-12-minify-sloppy-code-01`.

Commit-hash receipt: planning package closed in root commit `aa2c3de`; no implementation commit yet.

## Problem Statement

- The workspace still contains sloppy code: duplicate facts, one-off wrappers, vague owners, bucket structs, long functions, broad control spines, mirror types, and local complexity that survived earlier narrow render cuts.
- The sprint goal is to make the codebase smaller and more idiomatic by replacing broad or hidden structure with simple local/shallow control spines and small, efficient, intuitive state/logic owners.
- This is whole-workspace planning, not implementation. No coder starts until research and reviewer settle exact sequential slices.

## User Direction

- Fully minify sloppy code.
- Prefer small and idiomatic code.
- Prefer simple local/shallow control spines.
- Prefer small, efficient, intuitive state and logic owners.
- Do not settle for partial cleanup language unless the user explicitly narrows scope.

## Planning Boundary

- Research must re-prove current facts from current source after root commit `de8f30c` and nested current heads.
- Historical render API artifacts are navigation only.
- Planning must cover the full problem and produce sequential slices with exact allowed files, required shape, tests, non-goals, stop conditions, and receipt fields.

## Execution Authorization

- The reviewer accepted the planning package in session `review-2026-06-12-minify-sloppy-code-01`.
- The accepted research artifact is `/home/home/personal/projects/howl/research/2026-06-12-whole-workspace-minification-plan.md`.
- The first executable slice is Slice 1, `render-emitter-duplicate-pass-collapse`.
- Execution is authorized only through the condensed contract in `/home/home/personal/projects/howl/loops/whole-workspace-minification-live-loop.txt`.
