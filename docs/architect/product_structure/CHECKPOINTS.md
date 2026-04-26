# Product Structure Checkpoints

## Gate

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

## Checkpoint List

- [ ] Root files are thin export/wiring files.
- [ ] Conformance tests have behavior-owned names and are not hidden in root unless they are trivial module wiring checks.
- [ ] SDL executable entrypoint delegates durable behavior to named modules.
- [ ] Session implementation is split by lifecycle, I/O, resize/control, and state ownership.
- [ ] Renderer backends state backend-specific execution constraints in local contracts.
- [ ] Android host adds no JNI/native symbols until native-call names are contract-approved.
- [ ] No product repo active docs use vague boundary words banned by the guard.
- [ ] All public declarations have useful consumer-facing `///` docs, not filler.

## Stop Conditions

Stop and review if a cleanup:

- changes public API names without an explicit contract update.
- moves behavior only to reduce line count without improving ownership.
- adds platform types to shared modules.
- adds renderer planning policy outside `howl-render-core`.
- adds session/transport policy to host entrypoints.
