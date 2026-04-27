# MVP Scope Alignment Checkpoints

## Product Gate

Run only on product repos:

```bash
./utils/hygene/architecture_guard.sh \
  howl-vt-core \
  howl-session \
  howl-term-surface \
  render/howl-render-core \
  render/howl-render-gl \
  render/howl-render-gles \
  render/howl-render-metal \
  render/howl-render-software \
  render/howl-render-vulkan \
  howl-hosts/howl-sdl-host \
  howl-hosts/howl-android-host
```

## Sprint 1 — MVP Scope Alignment and Cleanup

- [x] Parent authority states the corrected terminal-boundary model.
- [x] Session, terminal-boundary, render-core, render-gl, SDL host, and Android
      host repo-local scope/boundary/milestone docs match the corrected model.
- [x] Parent workflow/progress/queue docs point at the corrected sprint lane.
- [x] Current-target language is honest about runtime state, not stale milestone
      optimism. (Correction tickets CL-SE-1, CL-SE-2, CL-RC-1, CL-GL-1, CL-SDL-1,
      CL-AND-1 executed 2026-04-27.)
- [x] Naming/doc-comment/layout drift from prior partial sprints is reviewed and
      turned into explicit execution cuts. (MVP-S1-A2 audit complete 2026-04-27;
      12 bounded correction tickets published to ACTIVE_QUEUE.md.)
- [x] Residual debt is recorded as bounded findings, not implied by silence.
      (Findings recorded in MVP-S1-A2 report; tickets CL-* are the execution cuts.)

Sprint 1 closed 2026-04-27. Doc model, queue model, and reality model agree.

### Sprint 1 Residual Debt

These items are bounded and do not block Sprint 2 entry:

- **AH-R2, AH-R4 pending**: Android Java Activity/Surface/Input shell not yet
  implemented. Blocked on architect publication of M2 (surface lifecycle) scope.
  Android remains a proof host; this is not a Linux MVP blocker.
- **Renderer queues unpublished**: render-core M1-M5 execution queue and
  render-gl M6 execution queue await architect publication. Engineers must not
  self-assign scope from these repos until published.
- **L3: SF- ID cross-reference**: howl-term-surface scope docs reference SF-
  ticket IDs that are not yet published in any active queue. No action required
  until SF- tickets are published by architect.

## Sprint 2 — Scoped MVP Completion

- [x] SDL host renders real text through `howl-term` -> `render-core` ->
      `howl-render-gl`.
- [ ] GL and GLES text-path policy and capability evidence move in lockstep for Sprint 2 renderer work.
- [ ] PTY-lane parity is accounted for in every transport-affecting iteration (Linux POSIX PTY, Android bridge pressure, future ConPTY expectation or bounded debt).
- [x] SDL host runs an interactive shell with correct input, resize, and
      shutdown.
- [x] SDL and Android host caller-shape parity is preserved or bounded debt is recorded in the same iteration.
- [ ] Render-core and GL evidence reflect runtime truth, not just contract
      structure.
- [x] Android remains a working proof host over the same terminal-boundary API.
- [ ] Local release evidence covers the participating repos for the Linux MVP.

Sprint 2 closes only when the first Linux host matches the documented MVP exit
bar.

### Sprint 2 Progress Notes

**GL-R1 executed (2026-04-27):** Alpha blending enabled in `render/howl-render-gl/src/backend.zig`.
GL_ALPHA textures + GL_MODULATE without GL_BLEND produced solid foreground-color
rectangles. Fix: `glEnable(GL_BLEND)` + `glBlendFunc(GL_SRC_ALPHA,
GL_ONE_MINUS_SRC_ALPHA)` scoped to glyph draw calls. Runtime evidence: screenshot
pixel analysis at SDL window position shows anti-aliased glyph shapes (partial-transparency
values 2-175) at terminal cell positions, confirming shaped character rendering replaces
prior solid-block output. Commit: `render/howl-render-gl` `f27ebf5`.

**MVP-S2-A1 legibility closure (2026-04-27):** GL-R1 through GL-R7 + GL-R6-R1 executed.
Key fixes: GL_NEAREST texture filtering; glyph metric capture (bearing_x/bearing_y) and
baseline-aligned quad placement; HiDPI cell sizing from SDL display scale and actual
drawable/logical ratio; height-only FT sizing; light+autohint load flags; ghostty-style
baseline; font-advance-informed cell width; unified load-flag policy between rasterization
and metric queries. Runtime evidence: screenshot at MVP-S2-A1R3 shows legible bash shell
output. Tests: 12/12 render-gl, 45/45 sdl-host.

**PAR-R1 (2026-04-27):** GL text-path policy documented as authoritative evidence (load
flags, baseline/advance policy, capability reporting) in `render/howl-render-gl` ACTIVE_QUEUE.
GLES parity evidence tied to same checkpoint id in `render/howl-render-gles` ACTIVE_QUEUE.
No FreeType path active in GLES; no divergence risk at this revision.

**PAR-T1 (2026-04-27):** Transport parity checkpoint added to `howl-session` ACTIVE_QUEUE:
POSIX PTY current truth, Android bridge pressure (bounded to AH-R2), ConPTY expectation.
Cross-link added to `howl-android-host` ACTIVE_QUEUE referencing session PAR-T1 section.

**PAR-H1 (2026-04-27):** Host caller-shape parity checkpoint added to both `howl-sdl-host`
and `howl-android-host` ACTIVE_QUEUEs. Canonical operations: `start`, `stop`, `feedBytes`,
`feedKey`, `tick`, `resize`, `control`, `frameData`. SDL direct-session-call practice recorded
as bounded debt. Android proof-scaffold state recorded; no new divergence permitted.

**S2-RUNTIME-1 (2026-04-27):** SDL-MVP-02..07 runtime gate matrix added to `howl-sdl-host`
ACTIVE_QUEUE. Each item has: required runtime observation, supporting test commands, failure
signature, and current status.

**S2-A2 runtime closure (2026-04-27):** Runtime observations recorded in
`howl-hosts/howl-sdl-host/docs/engineer/EVIDENCE_S2_A2.md`:
SDL-MVP-04 confirmed (input routing), SDL-MVP-05 confirmed (rendered output),
SDL-MVP-06 confirmed (resize propagation, `stty size 34x52 -> 13x33`), SDL-MVP-07
confirmed (deterministic shutdown, no zombie process). SDL-MVP-03 remains partial by
design due PAR-H1 bounded debt (direct-session-call containment until terminal-boundary cut).

**S2-HOST-1 (2026-04-27):** SDL caller-shape containment rule added to `howl-sdl-host`
ACTIVE_QUEUE: containment-only, no expansion of direct-session-call surface. Closure
trigger defined: architect-published terminal-boundary composition cut. Android cross-link
added to `howl-android-host` ACTIVE_QUEUE.

**S2-TRANSPORT-1 (2026-04-27):** Session transport parity mini-checklist added to
`howl-session` ACTIVE_QUEUE with three mandatory checkpoints (POSIX PTY, Android bridge,
ConPTY). Android cross-link added to `howl-android-host` ACTIVE_QUEUE requiring the
checklist as a preface for any transport-adjacent work.

**MVP-S2-A3 closeout (2026-04-27):** Android AH-R2 + AH-R4 runtime shell closure and
validation completed in `howl-hosts/howl-android-host`. Java activity/surface/input path now
routes through canonical caller-shape operations only (`start`, `stop`, `feedBytes`, `feedKey`,
`tick`, `resize`, `control`, `frameData`) via `HowlSurfaceCalls` + JNI + Zig `Host`.
Deterministic local scripts added for `.so` build, APK assembly, install/launch, and log
tail/dump.

**PAR-A3-GLES (2026-04-27):** Android/GLES parity checkpoint recorded against SDL/GL text-path
policy. Current gap is bounded debt (`AH-GLES-1`): Android proof host is caller-shape complete
but does not yet run GLES text rendering. Closure trigger: first Android GLES text-path activation
must ship with same-iteration PAR-R1 parity update in both `howl-render-gles` and
`howl-android-host` ACTIVE_QUEUE docs, plus runtime evidence links.

## Stop Conditions

Stop and review if any cleanup or MVP ticket:

- changes public API names without an explicit contract update
- reintroduces direct host ownership of terminal-boundary behavior
- moves render planning policy out of `howl-render-core`
- moves session/transport policy into hosts
- treats Android proof-host work as permission to bypass Linux MVP runtime gaps
- claims MVP completion before SDL runtime behavior proves it
