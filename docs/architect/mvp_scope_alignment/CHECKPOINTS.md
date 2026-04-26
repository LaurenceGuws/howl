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
- [ ] Current-target language is honest about runtime state, not stale milestone
      optimism. (Correction tickets CL-SE-1, CL-SE-2, CL-RC-1, CL-GL-1, CL-SDL-1,
      CL-AND-1 address this per-repo; pending MVP-S1-A3 execution.)
- [x] Naming/doc-comment/layout drift from prior partial sprints is reviewed and
      turned into explicit execution cuts. (MVP-S1-A2 audit complete 2026-04-27;
      13 bounded correction tickets published to ACTIVE_QUEUE.md.)
- [ ] Residual debt is recorded as bounded findings, not implied by silence.
      (Findings recorded in MVP-S1-A2 report; tickets CL-* are the execution cuts.)

Sprint 1 closes only when the doc model, queue model, and reality model match.

## Sprint 2 — Scoped MVP Completion

- [ ] SDL host renders real text through `howl-term` -> `render-core` ->
      `howl-render-gl`.
- [ ] SDL host runs an interactive shell with correct input, resize, and
      shutdown.
- [ ] Render-core and GL evidence reflect runtime truth, not just contract
      structure.
- [ ] Android remains a working proof host over the same terminal-boundary API.
- [ ] Local release evidence covers the participating repos for the Linux MVP.

Sprint 2 closes only when the first Linux host matches the documented MVP exit
bar.

## Stop Conditions

Stop and review if any cleanup or MVP ticket:

- changes public API names without an explicit contract update
- reintroduces direct host ownership of terminal-boundary behavior
- moves render planning policy out of `howl-render-core`
- moves session/transport policy into hosts
- treats Android proof-host work as permission to bypass Linux MVP runtime gaps
- claims MVP completion before SDL runtime behavior proves it
