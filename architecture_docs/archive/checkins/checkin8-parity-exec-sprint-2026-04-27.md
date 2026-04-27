#DONE

- PAR-R1: GL text-path policy (load flags, baseline, advance, capability) documented as
  authoritative evidence in `render/howl-render-gl` ACTIVE_QUEUE. GLES parity evidence
  tied to same PAR-R1 checkpoint id/date in `render/howl-render-gles` ACTIVE_QUEUE.
  Both repos confirm no divergence risk at this revision. No code changes — evidence only.

- PAR-T1: Transport parity checkpoint added to `howl-session` ACTIVE_QUEUE with explicit
  POSIX PTY truth, Android bridge pressure statement, and ConPTY expectation. Cross-link
  added to `howl-android-host` ACTIVE_QUEUE. No platform-specific transport policy was
  moved into session core. No code changes.

- PAR-H1: Canonical host caller-shape operations (`start`, `stop`, `feedBytes`, `feedKey`,
  `tick`, `resize`, `control`, `frameData`) added to both `howl-sdl-host` and
  `howl-android-host` ACTIVE_QUEUEs. SDL direct-session-call pattern recorded as bounded
  debt. Android proof-scaffold state recorded; no new divergence permitted. No code changes.

- PAR-C1: CHECKPOINTS.md Sprint 2 progress updated with R1/T1/H1 outcomes. Checkin filed
  as `checkin8-parity-exec-sprint-2026-04-27.md`.

#OUTSTANDING

None for this sprint iteration.

Residual risk: parity enforcement remains document-and-gate driven. No static analysis
tool enforces the GL/GLES load-flag equivalence, transport interface boundary, or
caller-shape equivalence at build time. Manual review is the enforcement mechanism for
this sprint. Automation would require: (a) a cross-repo lint rule checking glyph_load_flags
usage, (b) a transport-interface conformance test in howl-session, (c) a caller-shape
conformance test shared between sdl-host and android-host. None of these are in scope for
this sprint; they are explicit future guard candidates.

## Review Links

- Review artifact: `docs/architect/mvp_scope_alignment/REVIEW.md`
- Checkpoints artifact: `docs/architect/mvp_scope_alignment/CHECKPOINTS.md`

## commits

- `render/howl-render-gl` `957d3a7` — docs: PAR-R1 GL text-path policy evidence checkpoint (load flags, baseline, advance, capability)
- `render/howl-render-gles` `9a1b675` — docs: PAR-R1 GLES parity evidence checkpoint tied to GL PAR-R1 revision
- `howl-session` `3d4653c` — docs: PAR-T1 transport parity checkpoint (POSIX PTY truth, Android bridge pressure, ConPTY expectation)
- `howl-hosts/howl-android-host` `2ae53b4` — docs: PAR-T1 transport parity cross-link to session checkpoint (Android bridge bounded debt)
- `howl-hosts/howl-sdl-host` `d85b22f` — docs: PAR-H1 host caller-shape parity checkpoint (canonical howl-term operations, bounded debt recorded)
- `howl-hosts/howl-android-host` `6a3a52f` — docs: PAR-H1 host caller-shape parity checkpoint (canonical operations, bounded debt recorded)

## validation results

- `zig build test --summary all` — `render/howl-render-gl` — exit 0 — 12/12 tests passed
- `zig build test --summary all` — `render/howl-render-gles` — exit 0 — 6/6 tests passed (build summary: 3/3 steps)
- `zig build test --summary all` — `howl-hosts/howl-sdl-host` — exit 0 — 45/45 tests passed
- `zig build` — `howl-session` — n/a (docs-only change, no Zig modified) — skipped by design
- `zig build` — `howl-hosts/howl-android-host` — n/a (docs-only change, no Zig modified) — skipped by design
- `utils/hygene/architecture_guard.sh render/howl-render-gl render/howl-render-gles` — workspace — exit 0 — PASS (2/2 repos, 0 violations)
- `utils/hygene/architecture_guard.sh howl-session` — workspace — exit 0 — PASS (1/1 repos, 0 violations)
- `utils/hygene/architecture_guard.sh howl-hosts/howl-android-host` — workspace — exit 0 — PASS (1/1 repos, 0 violations)
- `utils/hygene/architecture_guard.sh howl-hosts/howl-sdl-host` — workspace — exit 0 — PASS (1/1 repos, 0 violations)

## files changed

- `render/howl-render-gl/docs/engineer/ACTIVE_QUEUE.md`
- `render/howl-render-gles/docs/engineer/ACTIVE_QUEUE.md`
- `howl-session/docs/engineer/ACTIVE_QUEUE.md`
- `howl-hosts/howl-android-host/docs/engineer/ACTIVE_QUEUE.md` (two commits: PAR-T1 + PAR-H1)
- `howl-hosts/howl-sdl-host/docs/engineer/ACTIVE_QUEUE.md`
- `docs/architect/mvp_scope_alignment/CHECKPOINTS.md`
- `architecture_docs/archive/checkins/checkin8-parity-exec-sprint-2026-04-27.md` (this file)

## findings

High: none.

Medium:
- SDL host direct-session-call pattern is bounded debt against the PAR-H1 caller-shape
  invariant. `SdlHost` in `event_loop.zig` calls session operations directly rather than
  through a composed `howl-term` instance. This is a pre-existing structural gap,
  not introduced in this sprint. It is now explicitly recorded and must not be extended.

- GLES text execution is not active: `backend.execute()` in `howl-render-gles` accepts
  `RenderPlan` and records stats only; no fill/glyph/cursor drawing paths exist. The
  GLES-MVP-01 milestone ("lockstep with GL text-path policy and capability reporting")
  requires that when GLES activates its text path, it adopts the same `glyph_load_flags`
  and `glyph_metric_flags` constants (or a promoted shared raster module). The parity
  marker test in GLES-P1 enforces this as a human-readable invariant; no compile-time
  enforcement exists yet.

Low:
- Transport parity enforcement is doc-and-gate driven. No conformance test in
  `howl-session` statically proves that all transport implementations satisfy the same
  interface contract. The `Transport` vtable type is the current boundary; a future
  conformance test suite would make this machine-checkable.
- Android host AH-R2 (minimal Java Activity/Surface/Input shell) remains pending,
  blocked on architect queue publication for M2 surface lifecycle scope. This is
  pre-existing bounded debt, not introduced in this sprint.
