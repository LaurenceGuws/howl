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

- [ ] SDL host renders real text through `howl-term` -> `render-core` ->
      `howl-render-gl`.
- [ ] GL and GLES text-path policy and capability evidence move in lockstep for Sprint 2 renderer work.
- [ ] PTY-lane parity is accounted for in every transport-affecting iteration (Linux POSIX PTY, Android bridge pressure, future ConPTY expectation or bounded debt).
- [ ] SDL host runs an interactive shell with correct input, resize, and
      shutdown.
- [ ] SDL and Android host caller-shape parity is preserved or bounded debt is recorded in the same iteration.
- [ ] Render-core and GL evidence reflect runtime truth, not just contract
      structure.
- [ ] Android remains a working proof host over the same terminal-boundary API.
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

**Outstanding for A1 closure:** interactive legibility confirmation (readable bash
prompt), glyph atlas population log, full SDL-MVP-01 checklist verification by
observation.

## Stop Conditions

Stop and review if any cleanup or MVP ticket:

- changes public API names without an explicit contract update
- reintroduces direct host ownership of terminal-boundary behavior
- moves render planning policy out of `howl-render-core`
- moves session/transport policy into hosts
- treats Android proof-host work as permission to bypass Linux MVP runtime gaps
- claims MVP completion before SDL runtime behavior proves it
