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

Status: done. Audit complete 2026-04-27. Bounded correction tickets published below as
input to MVP-S1-A3. See report in parent conversation.

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

Status: pending. Input: correction tickets from MVP-S1-A2 audit (see below).

#### Correction Tickets (input to MVP-S1-A3 execution)

##### CL-SE-1: howl-session active queue and milestone progress reset
- **Intent**: Align ACTIVE_QUEUE.md and MILESTONE_PROGRESS.md with live-host revalidation model.
- **Target files**: `howl-session/docs/engineer/ACTIVE_QUEUE.md`, `howl-session/docs/architect/MILESTONE_PROGRESS.md`
- **Change type**: Documentation correction
- **Non-goals**: no session code changes; no milestone ladder changes
- **Stop conditions**: any change that implies M6 planning is the next step before live-host revalidation is established
- **Required validation**: architecture guard pass; no vague language introduced

##### CL-SE-2: howl-session MILESTONE_PROGRESS M6-M10 stale pause notes
- **Intent**: Replace "paused pending M5 closure" with accurate state — M5 is closed; current gate is live-host revalidation through the terminal boundary.
- **Target files**: `howl-session/docs/architect/MILESTONE_PROGRESS.md`
- **Change type**: Documentation correction
- **Non-goals**: no milestone ladder reordering
- **Stop conditions**: implies M6+ work is next before live-host revalidation is proven
- **Required validation**: text matches MILESTONE.md current target language

##### CL-SF-1: howl-term-surface M0 queue closeout
- **Intent**: Mark M0-A2 and M0-A3 as done (dirty.zig and tests_root.zig exist); confirm M0-A1 resolution against FRAME_QUERY_MODEL.md; advance queue to closeout.
- **Target files**: `howl-term-surface/docs/engineer/ACTIVE_QUEUE.md`
- **Change type**: Documentation correction
- **Non-goals**: no contract file creation; no new implementation
- **Stop conditions**: introduces new scope not covered by existing files
- **Required validation**: SURFACE_QUERY.md referenced in M0-A1 is either confirmed closed by FRAME_QUERY_MODEL.md or the gap is named explicitly

##### CL-RC-1: howl-render-core MILESTONE_PROGRESS reset to match code reality
- **Intent**: Align MILESTONE_PROGRESS.md to the current authority target (`M5` capability negotiation) and remove stale scaffold-reset language.
- **Target files**: `render/howl-render-core/docs/architect/MILESTONE_PROGRESS.md`
- **Change type**: Documentation correction
- **Non-goals**: no scope change to `app_architecture/authorities/MILESTONE.md`
- **Stop conditions**: progress board introduces a new target that conflicts with either parent `MILESTONES.md` or local MILESTONE authority
- **Required validation**: MILESTONE_PROGRESS target text matches local and parent current-target language

##### CL-RC-2: howl-render-core ACTIVE_QUEUE unblock for M1 execution
- **Intent**: Replace blocking reset notice with a concrete bounded queue entry aligned to the active target (`M5` capability negotiation correction lane).
- **Target files**: `render/howl-render-core/docs/engineer/ACTIVE_QUEUE.md`
- **Change type**: Queue publication (documentation)
- **Non-goals**: no implementation; no scope beyond architect-published target lane
- **Stop conditions**: queue target conflicts with CL-RC-1 progress state
- **Required validation**: architecture guard pass after any doc edits

##### CL-GL-1: howl-render-gl MILESTONE_PROGRESS reset to match code reality
- **Intent**: Align MILESTONE_PROGRESS.md to the current authority target (`M6` capability conformance) and remove stale architectural-reset language.
- **Target files**: `render/howl-render-gl/docs/architect/MILESTONE_PROGRESS.md`
- **Change type**: Documentation correction
- **Non-goals**: no milestone ladder changes; no code changes
- **Stop conditions**: progress board claims completed conformance evidence without matching artifacts
- **Required validation**: MILESTONE_PROGRESS target text matches local and parent current-target language

##### CL-GL-2: howl-render-gl ACTIVE_QUEUE unblock for next execution
- **Intent**: Replace blocking notice with a bounded queue entry aligned to the active target (`M6` capability conformance correction lane).
- **Target files**: `render/howl-render-gl/docs/engineer/ACTIVE_QUEUE.md`
- **Change type**: Queue publication (documentation)
- **Non-goals**: no implementation; no target invention by engineers
- **Stop conditions**: queue target conflicts with CL-GL-1 progress state
- **Required validation**: architecture guard pass

##### CL-SDL-1: howl-sdl-host ACTIVE_QUEUE next-gate language correction
- **Intent**: Replace "M10 remains architect-owned" as the only gate with an explicit reference to the real MVP gate: visible text rendering, correct input, resize, and shutdown through the terminal boundary.
- **Target files**: `howl-hosts/howl-sdl-host/docs/engineer/ACTIVE_QUEUE.md`
- **Change type**: Documentation correction
- **Non-goals**: no code changes; no milestone ladder changes
- **Stop conditions**: implies M10 is the only outstanding gate before MVP; ignores runtime quality gap
- **Required validation**: language is consistent with parent MILESTONES.md "SDL-MVP-01 through SDL-MVP-07" runtime requirements

##### CL-SDL-2: howl-sdl-host/src/presentation.zig doc-comment ownership correction
- **Intent**: Fix `//! Ownership: host shell rendering pipeline (backend capabilities, plan building).` — "plan building" is inaccurate; plan building is owned by howl-render-core via howl-term-surface.render_contract; the host's presentation module is a call-through.
- **Target files**: `howl-hosts/howl-sdl-host/src/presentation.zig` (line 2)
- **Change type**: Doc-comment correction (one line)
- **Non-goals**: no behavior change; no API change
- **Stop conditions**: change introduces new ownership language
- **Required validation**: architecture guard pass; `zig build` pass

##### CL-AND-1: howl-android-host MILESTONE_PROGRESS advance from M0 to M1
- **Intent**: Update MILESTONE_PROGRESS.md to reflect that host.zig, android_calls.zig, and input.zig constitute M1 (Android boundary contract) work that is implemented.
- **Target files**: `howl-hosts/howl-android-host/docs/architect/MILESTONE_PROGRESS.md`
- **Change type**: Documentation correction
- **Non-goals**: no milestone ladder changes; no code changes
- **Stop conditions**: claims M1 is fully done before Java lifecycle shell is implemented
- **Required validation**: progress board matches AH-R batch intent (host handle aligned with TerminalSurface)

##### CL-AND-2: howl-android-host ACTIVE_QUEUE PSH-B1-E8 ticket format correction
- **Intent**: Rename PSH-B1-E8 to AH-PKG-1 (or similar consistent AH-prefix scheme) and assign explicit status. PSH- prefix is a stale naming convention from a prior project.
- **Target files**: `howl-hosts/howl-android-host/docs/engineer/ACTIVE_QUEUE.md`
- **Change type**: Documentation correction (queue naming)
- **Non-goals**: no scope change to ticket intent; no code changes
- **Stop conditions**: changes ticket scope while renaming
- **Required validation**: all queue entries have consistent ID format and explicit status

##### CL-AND-3: android_calls.zig global mutable singleton documentation
- **Intent**: Add explicit doc-comment on `var host_instance: ?*host_module.Host` stating the single-instance constraint and no thread-safety guarantee. Update ANDROID_HOST_SHELL.md to document this known limit.
- **Target files**: `howl-hosts/howl-android-host/src/android_calls.zig` (line 9), `howl-hosts/howl-android-host/app_architecture/contracts/ANDROID_HOST_SHELL.md`
- **Change type**: Doc-comment addition + contract clarification
- **Non-goals**: no behavior change; no mutex introduction
- **Stop conditions**: introduces behavioral changes or thread-safety claims not backed by code
- **Required validation**: architecture guard pass; `zig build test --summary all` pass

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
