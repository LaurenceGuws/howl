# Parent Active Queue

## Current State

Active sprint is `MVP-S1` (MVP scope alignment and cleanup).
Next sprint is `MVP-S2` (scoped MVP completion).

## Read Before Execution

- `architecture_docs/authority/ENGINEERING_CONVENTIONS.md`
- `architecture_docs/authority/MILESTONES.md`
- `architecture_docs/authority/MVP_STRUCTURE.md`
- `architecture_docs/authority/MODULE_MAP.md`
- `architecture_docs/authority/DEPENDENCY_RULES.md`
- `architecture_docs/authority/INTEGRATION_FLOW.md`
- `docs/architect/WORKFLOW.md`
- `docs/architect/mvp_scope_alignment/REVIEW.md`
- `docs/architect/mvp_scope_alignment/CHECKPOINTS.md`
- `docs/engineer/REPORT_CHECKLIST.md`

## Sprint: MVP Scope Alignment and Cleanup

Goal: align current module state, repo-local docs, naming, file ownership,
layout, and queue reality to the corrected `howl-term` boundary model before
claiming visible MVP completion.

### MVP-S1-A1: Parent and Child Authority Sync

Status: done architect-side.

Intent:
- update parent authority to the corrected terminal-boundary model
- update participating MVP repo scope/boundary/milestone docs to match
- record the decision trail in a new parent checkin

Targets:
- `architecture_docs/authority/*`
- `howl-session/app_architecture/authorities/*`
- `howl-term-surface/app_architecture/authorities/*`
- `render/howl-render-core/app_architecture/authorities/*`
- `render/howl-render-gl/app_architecture/authorities/*`
- `howl-hosts/howl-sdl-host/app_architecture/authorities/*`
- `howl-hosts/howl-android-host/app_architecture/authorities/*`

### MVP-S1-A2: Repo Reality Audit and Cleanup Queue

Status: next.

Intent:
- audit each MVP repo for stale milestone claims, stale queue claims, ambiguous
  naming, and topology drift caused by previous half-finished sprints
- publish only bounded correction tickets tied to specific repos/files
- distinguish doc debt, topology debt, and real behavior debt

Primary targets:
- `howl-session`
- `howl-term-surface`
- `render/howl-render-core`
- `render/howl-render-gl`
- `howl-hosts/howl-sdl-host`
- `howl-hosts/howl-android-host`

Non-goals:
- no broad feature work yet
- no optimistic MVP claims

Stop conditions:
- audit findings are vague or not tied to files/contracts
- queue invents new scope outside the corrected model

### MVP-S1-A3: Naming and Ownership Corrections

Status: pending.

Intent:
- execute bounded cleanup tickets from the audit
- remove ambiguous or stale naming in files, symbols, doc comments, and local
  workflow docs
- tighten ownership signals where previous sprints left mixed language behind

Non-goals:
- no cross-module rearchitecture beyond the corrected boundary model
- no hidden behavior changes under naming cleanup

### MVP-S1-A4: Sprint Closeout

Status: pending.

Intent:
- close Sprint 1 only when parent docs, child docs, queue state, and reported
  runtime truth agree
- publish the exact Sprint 2 execution lane for visible MVP closure

Required validation:
- product hygiene guard passes for reviewed product repos
- handover reports cite real validation and real residual debt

## Sprint: Scoped MVP Completion

Goal: finish the first Linux MVP through runtime truth, not architectural wishful
thinking.

### MVP-S2-A1: SDL Text Path Closure

Status: planned.

Intent:
- complete real text rendering through `howl-term` -> `render-core` ->
  `howl-render-gl`
- remove remaining block-only presentation gaps

### MVP-S2-A2: SDL Interactive Shell Closure

Status: planned.

Intent:
- close the shell loop: process output, keyboard/text input, resize, redraw,
  and shutdown
- prove the Linux host is actually usable

### MVP-S2-A3: Android Proof-Host Closure

Status: planned.

Intent:
- keep Android as a valid peer proof host over the same terminal boundary
- do not let Android-specific work retake ownership from shared modules

### MVP-S2-A4: MVP Quality Lock

Status: planned.

Intent:
- publish participating-repo evidence, release steps, and known limits only
  after runtime truth is closed
