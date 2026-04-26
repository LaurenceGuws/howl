# Architecture Discipline Review (2026-04-26)

## Context

This review is a checkpoint after the renderer-lane architectural correction pass.
It focuses on drift prevention: milestone clarity, doc/code cohesion, naming/comment discipline, and workflow enforcement.

Linked checkin: `architecture_docs/checkins/checkin4-architecture-discipline-2026-04-26.md`

## Audit Scope

Repos sampled for code hygiene and layering discipline:

- `howl-vt-core`
- `howl-session`
- `howl-term-surface`
- `render/howl-render-core`
- `render/howl-render-gl`
- `howl-hosts/howl-sdl-host`

Family-level docs audited:

- `architecture_docs/MILESTONES.md`
- `architecture_docs/MODULE_MAP.md`
- `architecture_docs/DEPENDENCY_RULES.md`
- child `app_architecture/authorities/MILESTONE.md`

## What Is Healthy

1. Header doc hygiene in key source repos is currently strong.
   - All sampled `src/**/*.zig` files in the six key repos have `//!` file headers.
2. File naming hygiene in sampled `src/` trees is currently strong.
   - No uppercase/hyphen naming drift detected in file names.
3. Forbidden compatibility patterns are currently clean in sampled repos.
   - No `compat/fallback/workaround/shim` source matches in key repos.
4. Renderer ownership correction is directionally right.
   - `render-core` owns planning policy and capability gating.
   - host seam is mostly glue-only.

## Drift Findings

### D1: Milestone targets are stale or contradictory across repos

Evidence:

- `howl-term-surface/app_architecture/authorities/MILESTONE.md` still says `Current target is M0 scaffold closure`.
- `render/howl-render-core` and `render/howl-render-gl` still report `Current target is M0 scaffold reset closure` despite active M2/M3 work.
- Other renderer backends also remain pinned at M0 targets regardless of parent map progression.
- Parent `architecture_docs/MILESTONES.md` expresses a broader progression, but local current-target pointers do not consistently reflect real queue state.

Impact:

- Engineer handovers can be technically correct but contextually misaligned.
- Review quality degrades because “what phase are we in?” becomes ambiguous.

### D2: Style/naming/comment conventions are enforced socially, not by repo authority

Evidence:

- No parent-level architecture authority document currently defines Zig doc comment rules (`//!` vs `///`), symbol naming conventions, or ticket-tag policy in code/tests.
- Current conventions exist mostly in chat/operator process, not in versioned architecture authority.

Impact:

- Agent behavior drifts between sessions/models.
- New engineers cannot distinguish mandatory conventions from preferences.

### D3: Ticket/process traceability is inconsistent

Evidence:

- At least one recent batch grouped multiple ticket intentions into one commit on GL side.
- This was called out explicitly during handover reporting.

Impact:

- Root-cause review and rollback discipline weakens.
- Evidence-to-ticket mapping becomes fuzzy in larger correction sweeps.

### D4: Legacy milestone-ticket labels persist in VT tests

Evidence:

- `howl-vt-core/src/test/relay.zig` contains extensive ticket/milestone labels in test names (e.g., `M5-A2`, `M8-E2`, `M9-FX-*`).

Impact:

- Test names carry process history rather than pure behavior intent.
- Future refactors are harder because naming ties assertions to project management artifacts.

## Root-Cause Analysis (Docs/Workflow)

1. **Authority gap**: there is no explicit “Engineering Conventions Authority” doc at parent level.
2. **Enforcement gap**: there is no architecture guard script/local gate path for naming/comments/layering claims.
3. **State-sync gap**: no required update rule tying `Current Target` in child `MILESTONE.md` to active queue progress.
4. **Handover contract gap**: no mandatory ticket-to-commit isolation gate and no mandatory residual-risk section validated by reviewer.

## Long Sprint Checkpoint List

### P0 — Authority lock (must complete first)

1. Add `architecture_docs/ENGINEERING_CONVENTIONS.md` with normative rules:
   - Zig file/module doc rules (`//!`, `///`, comment scope)
   - naming conventions for files/folders/symbols
   - test naming policy (behavior-first, no milestone tags in new tests)
   - ticket/commit isolation policy
2. Add `architecture_docs/CHECKIN_PROTOCOL.md`:
   - required checkin fields
   - required links to review artifacts
   - required residual-risk statement
3. Update `architecture_docs/README.md` to list the two new authority docs.

### P1 — Milestone coherence lock

1. Normalize `Current Target` across all child `app_architecture/authorities/MILESTONE.md` files to real active phase.
2. Add a rule: every queue advancement must update `Current Target` in same commit set.
3. Add parent-level table mapping each repo current target to parent family phase.

### P2 — Automated discipline lock

1. Add `utils/hygene/architecture_guard.sh` as the parent-invokable local guard to fail on:
   - missing `//!` in `src/**/*.zig`
   - forbidden naming patterns in source file names
   - forbidden ticket tags in new test names (configurable exceptions for legacy files)
   - obvious dependency-direction violations (best-effort import checks)
2. Add per-repo local task wiring to run guard + build + tests through `utils/hygene`.
3. Make `utils/hygene` guard clean a mandatory closeout criterion for engineer handovers.

### P3 — Legacy cleanup and convergence

1. VT-core test naming cleanup: migrate milestone/ticket-labeled test names to behavior names.
2. Renderer docs consistency pass:
   - ensure `MILESTONE.md`, `ACTIVE_QUEUE.md`, and evidence docs all reflect same phase language.
3. Host/surface/session docs consistency pass:
   - ensure child scope docs align with parent module map wording.

## Acceptance Criteria for This Review Sprint

1. All authority docs merged and linked from parent README/checkin.
2. All child milestone `Current Target` values are synchronized with active queue reality.
3. Architecture guard runs clean via `utils/hygene` on the three active repos:
   - `howl-render-core`
   - `howl-render-gl`
   - `howl-sdl-host`
4. At least one legacy test file is migrated to behavior-first naming to prove convention migration is practical.

## Handover Notes for Engineer

- Treat this review as a discipline sprint, not a feature sprint.
- Do not expand product scope while conventions are being locked.
- Every engineering handover must include the `utils/hygene/architecture_guard.sh` result in the validation block defined by `architecture_docs/CHECKIN_PROTOCOL.md`.
- If a rule cannot be automated immediately, document why and add a temporary explicit review checklist item.
