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

- [x] Parent workflow lane is established in `docs/`.
- [x] Root files are thin export/wiring files.
- [x] Conformance tests have behavior-owned names and are not hidden in root unless they are trivial module wiring checks.
- [x] SDL executable entrypoint delegates durable behavior to named modules.
- [x] Session implementation is split by lifecycle, I/O, resize/control, and state ownership.
- [x] Renderer backends state backend-specific execution constraints in local contracts.
- [x] Android host adds no JNI/native symbols until native-call names are contract-approved.
- [x] No product repo active docs use vague boundary words banned by the guard.
- [x] All public declarations have useful consumer-facing `///` docs, not filler.

## Residual Risk

- Public-doc semantic depth is reviewed manually; the guard enforces presence and boundary vocabulary but cannot fully score domain clarity.

## Stop Conditions

Stop and review if a cleanup:

- changes public API names without an explicit contract update.
- moves behavior only to reduce line count without improving ownership.
- adds platform types to shared modules.
- adds renderer planning policy outside `howl-render-core`.
- adds session/transport policy to host entrypoints.
