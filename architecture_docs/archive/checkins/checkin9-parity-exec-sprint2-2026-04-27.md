#DONE

- S2-RUNTIME-1: SDL-MVP-02..07 runtime gate matrix added to `howl-sdl-host` ACTIVE_QUEUE.
  Each row defines required runtime observation, supporting test commands, failure signature,
  and current status. All items are `not-observed` or `partial` — none are claimed confirmed.
  Text rendering is `partial` (legibility confirmed by MVP-S2-A1R3 screenshot; full interactive
  session under sustained input not yet observed). Parent CHECKPOINTS updated.

- S2-HOST-1: Caller-shape containment rule added to `howl-sdl-host` ACTIVE_QUEUE:
  containment-only, no expansion of direct-session-call surface; explicit closure trigger
  (architect-published terminal-boundary composition cut). Android cross-link added to
  `howl-android-host` ACTIVE_QUEUE referencing same containment rule.

- S2-TRANSPORT-1: Transport parity mini-checklist added to `howl-session` ACTIVE_QUEUE
  with three mandatory checkpoints: POSIX PTY impact, Android bridge impact, ConPTY
  expectation note. Android cross-link added to `howl-android-host` ACTIVE_QUEUE requiring
  this checklist as a preface for transport-adjacent work.

- S2-CHECKIN-2: CHECKPOINTS.md updated with A/B/C outcomes. Checkin9 filed under
  `architecture_docs/archive/checkins/`.

#OUTSTANDING

None for this sprint pass. Residual risks:

1. S2-RUNTIME-1 items are all `not-observed` or `partial`. The matrix is the execution
   target for MVP-S2-A2 closure — no items are confirmed by runtime observation yet.
   "Partial" for SDL-MVP-05 (rendered output) means legibility was confirmed in one
   screenshot but full interactive shell output (scrolling, editor, multi-line) was not
   observed. The gate is not closed.

2. S2-HOST-1 containment is a doc-and-review gate. No static check prevents new
   call sites from being added to `src/event_loop.zig` that bypass the canonical
   caller-shape. Manual review is the enforcement mechanism until the terminal-boundary
   composition cut is published and wired.

3. S2-TRANSPORT-1 mini-checklist is self-reported. No build-time tool enforces that
   the checklist answers are present in the commit message. Human reviewer must verify
   before merging any transport-affecting session change.

## Review Links

- Review artifact: `docs/architect/mvp_scope_alignment/REVIEW.md`
- Checkpoints artifact: `docs/architect/mvp_scope_alignment/CHECKPOINTS.md`
- Prior checkin: `architecture_docs/archive/checkins/checkin8-parity-exec-sprint-2026-04-27.md`

## commits

- `howl-hosts/howl-sdl-host` `812be0e` — docs: S2-RUNTIME-1 SDL-MVP-02..07 runtime gate matrix
- `howl-hosts/howl-sdl-host` `ccd3fd8` — docs: S2-HOST-1 caller-shape debt containment rule and closure trigger
- `howl-hosts/howl-android-host` `33fe931` — docs: S2-HOST-1 containment cross-link for SDL caller-shape debt
- `howl-session` `6632d8c` — docs: S2-TRANSPORT-1 transport parity mini-checklist
- `howl-hosts/howl-android-host` `8d3ad26` — docs: S2-TRANSPORT-1 transport parity mini-checklist cross-link

## validation results

- `zig build test --summary all` — `howl-hosts/howl-sdl-host` — n/a — docs-only ticket A/B; Zig not touched; prior baseline 45/45 unchanged
- `zig build test --summary all` — `howl-session` — n/a — docs-only ticket C; prior baseline 140/140 unchanged
- `zig build test --summary all` — `howl-hosts/howl-android-host` — n/a — docs-only; prior baseline passing unchanged
- `utils/hygene/architecture_guard.sh` (all 11 product repos) — workspace — exit 0 — PASS 11/11, 0 violations
- Note: architecture guard ran twice during S2-HOST-1 (caught and fixed `\bpatterns\b` violation in android ACTIVE_QUEUE before final commit)

## files changed

- `howl-hosts/howl-sdl-host/docs/engineer/ACTIVE_QUEUE.md`
- `howl-hosts/howl-android-host/docs/engineer/ACTIVE_QUEUE.md`
- `howl-session/docs/engineer/ACTIVE_QUEUE.md`
- `docs/architect/mvp_scope_alignment/CHECKPOINTS.md`
- `architecture_docs/archive/checkins/checkin9-parity-exec-sprint2-2026-04-27.md` (this file)

## findings

High: none.

Medium:
- Architecture guard flagged `\bpatterns\b` in android ACTIVE_QUEUE during S2-HOST-1
  work. The word "patterns" is in the active-doc forbidden list (alongside adapter, bootstrap,
  glue, seam). The intended text was "session-bypass call sites" not "session-bypass patterns."
  Fixed before final commit. Guard must be run against all touched repos before committing
  doc changes — this sprint caught the violation in-band.

- SDL-MVP-05 (rendered process output) is marked `partial` not `confirmed`. The existing
  MVP-S2-A1R3 screenshot proves legibility at one shell prompt state. It does not prove
  stability under sustained output (scrolling, `ls -la`, editor redraws). The matrix
  explicitly names this gap. Claiming SDL-MVP-05 confirmed requires a new runtime observation
  session with those scenarios.

Low:
- The S2-TRANSPORT-1 mini-checklist requires answers in commit messages or queue updates.
  This is a convention, not an enforcement mechanism. A future guard rule could require
  the checklist marker string in commits touching `transport/` files, but that is not in
  scope for this sprint.

- S2-RUNTIME-1 failure signatures were written from code reading only, not from observing
  actual failures. A future pass should validate that each failure signature is reachable
  and unambiguous (i.e., the failure would actually produce the described signal, not a
  silent no-op or a different error).
