#DONE

- MVP-S2-A3 closed: Android proof host now runs through the same terminal-boundary
  caller shape as SDL (`start`, `stop`, `feedBytes`, `feedKey`, `tick`, `resize`,
  `control`, `frameData`) with no new bypass surface.
- AH-R2 runtime corrections landed: Android key routing now maps to canonical terminal keys,
  unsupported key events are ignored, key-up no longer duplicates key-down, and JNI empty-byte
  feed no longer risks null-pointer slicing.
- A3-E2 deterministic local Android workflow landed with explicit scripts for `.so` build,
  APK assembly, install/launch, and log tail/dump.
- A3-E3 parity checkpoint recorded in Android queue and parent checkpoints with bounded debt
  `AH-GLES-1` plus an explicit closure trigger.
- Parent closeout artifacts updated: parent ACTIVE_QUEUE and CHECKPOINTS now mark A3 as closed.

#OUTSTANDING

- `AH-GLES-1` remains open: Android proof host does not yet execute a GLES text path, so
  parity against active SDL/GL text runtime remains bounded debt until renderer integration.
- `MVP-S2-A4` remains open (quality lock/release evidence lane).

## Review Links

- Parent queue: `docs/engineer/ACTIVE_QUEUE.md`
- Parent checkpoints: `docs/architect/mvp_scope_alignment/CHECKPOINTS.md`
- Android queue: `howl-hosts/howl-android-host/docs/engineer/ACTIVE_QUEUE.md`

## commits

- `howl-hosts/howl-android-host` `b930a7b` — AH-R2 runtime caller-shape closure (key routing + JNI empty-feed safety + tests)
- `howl-hosts/howl-android-host` `f6a33f6` — A3-E2 deterministic local deploy/reload/log scripts
- `howl-hosts/howl-android-host` `67c0c16` — A3-E3 Android/GLES parity checkpoint + milestone/queue updates

## validation results

- `zig build test --summary all` — `howl-hosts/howl-android-host` — PASS `10/10`
- `./gradlew :app:compileDebugJavaWithJavac :app:testDebugUnitTest --no-daemon`
  — `howl-hosts/howl-android-host` — PASS
- `./utils/hygene/architecture_guard.sh` (11 product repos) — workspace — PASS `11/11`, `0 violations`

## files changed

- `howl-hosts/howl-android-host/app/src/main/java/dev/howl/android/HowlActivity.java`
- `howl-hosts/howl-android-host/app/src/main/java/dev/howl/android/InputClassifier.java`
- `howl-hosts/howl-android-host/app/src/test/java/dev/howl/android/HowlActivityTest.java`
- `howl-hosts/howl-android-host/app/src/test/java/dev/howl/android/InputClassifierTest.java`
- `howl-hosts/howl-android-host/src/android_calls.zig`
- `howl-hosts/howl-android-host/scripts/android-env.sh`
- `howl-hosts/howl-android-host/scripts/build-native.sh`
- `howl-hosts/howl-android-host/scripts/assemble-debug.sh`
- `howl-hosts/howl-android-host/scripts/deploy-debug.sh`
- `howl-hosts/howl-android-host/scripts/logcat-debug.sh`
- `howl-hosts/howl-android-host/scripts/package-debug.sh`
- `howl-hosts/howl-android-host/docs/architect/MILESTONE_PROGRESS.md`
- `howl-hosts/howl-android-host/docs/engineer/ACTIVE_QUEUE.md`
- `docs/engineer/ACTIVE_QUEUE.md`
- `docs/architect/mvp_scope_alignment/CHECKPOINTS.md`
- `architecture_docs/archive/checkins/checkin11-s2-a3-android-proof-host-closure-2026-04-27.md`

## findings

High: none.

Medium:
- Android host runtime parity is closed at caller shape, but renderer parity is still
  bounded debt (`AH-GLES-1`) until Android GLES text-path activation ships with PAR-R1 evidence.

Low:
- Android deploy script defaults to live log tail after launch, which is expected for local
  debug flow but requires `HOWL_ANDROID_LOG_MODE=dump` for non-interactive runs.
