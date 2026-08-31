# howl-flutter

Flutter is the platform host for the native Howl client. It owns platform UI, visible viewport policy, IME/touch/stylus/pointer capture, and the final backend draw submission. It does **not** own the Howl wire, `text_v1`, terminal snapshots, terminal colors/styles/cursor policy, shaping, glyph rasterization, or terminal escape encoding.

The live terminal path is:

```text
howl-session / howl-vt
        ↓
howl-client.rich → howl-client.view
        ↓
howl-render.terminal.Content → canvas.Composer.Frame
        ↓
app-private copied native-host frame
        ↓
Flutter resource lease + batched Canvas backend
```

`howl-flutter/native/` owns the version-locked application binding. Its opaque observer and control handles are private to the same Howl/Flutter build and are **not a stable public C ABI**. A blocking observation copies one complete final-Canvas frame into caller-owned memory. Flutter never retains mutable native presentation pointers. It reports only the resources for which it still owns a live `ui.Image`; native Canvas generations then decide whether pixel uploads are needed.

Control is semantic. Flutter maps platform events to committed text, named/Unicode physical keys, focus, resize, signals, paste, and semantic mouse facts, then forwards them through `howl-client.actions`. Flutter does not generate terminal escape sequences. The canonical VT alone decides whether a semantic key/mouse event is suppressed or encoded for the child.

## Android

The accepted Android client is currently **arm64 only**. Build the native host and Flutter APK through the checked-in wrapper:

```sh
ZIG=/path/to/tracked/zig \
FLUTTER=/path/to/flutter \
ANDROID_NDK_ROOT=/path/to/android-ndk \
JAVA_HOME=/path/to/jdk21 \
./build-android.sh profile \
  --dart-define=HOWL_ENDPOINT=tcp://127.0.0.1:43127 \
  --dart-define=HOWL_GEOMETRY_LEADER=1
```

The wrapper always performs a clean Flutter build with `--target-platform android-arm64`, verifies that no other ABI entered the APK, and requires `libhowl_native_host.so`. Gradle independently refuses a non-arm64 Flutter target or a missing generated host library.

`native/build-android.sh` builds the host explicitly; Gradle only verifies and packages the result. The native dependency furnace pins the pressure-proven FreeType and HarfBuzz revisions as static arm64 libraries and links them into one app-private host `.so`. Android does not depend on its private platform FreeType/HarfBuzz ABI.

The terminal font is presentation/deployment policy. The Android native host requires the externally provisioned app-private file:

```text
files/IosevkaTermNerdFont-Regular.ttf
```

and currently uses Android's `NotoNaskhArabic-Regular.ttf` as the explicit fallback. The font is neither tracked nor bundled in this repository.

The native control canary is deterministic and does not rely on Android's vendor-specific shell text injector:

```sh
./native/run-control-canary.sh tcp://127.0.0.1:43127
```

It checks committed UTF-8, Enter, Backspace, Delete, Unicode physical key input, paste, focus, tracking-off semantic mouse behavior, resize, and the resulting canonical shell/geometry state.

## Linux

Build the native host first, then the normal Flutter bundle:

```sh
ZIG=/path/to/tracked/zig ./native/build-linux.sh
flutter build linux --release \
  --dart-define=HOWL_ENDPOINT=tcp://127.0.0.1:43127
```

The Linux bundle installs `libhowl_native_host.so` into its existing `$ORIGIN/lib` directory and refuses to build if the native host is missing. Linux uses the system FreeType/HarfBuzz libraries.

Font discovery is exact rather than permissive. `HOWL_FONT` and `HOWL_FALLBACK_FONT` may name explicit files. Otherwise fontconfig must actually resolve `IosevkaTerm Nerd Font` and `Noto Sans Arabic`; a silent family substitution is rejected.

A bare path or `unix:/path` remains a local Linux endpoint option. TCP remains restricted to exact IPv4 loopback.

## iOS

The iOS runner remains an honest platform-pressure target. The same native observer/control host object has compiled and linked for arm64 iPhoneOS, and physical iPhone pressure proved final-Canvas resource lifetime with a first 16 KiB atlas publication followed by an identical sparse frame with zero re-upload.

That does **not** change iOS remote-session reachability. Actual iOS remote terminal policy remains SSH-only until a separate transport experiment earns another contract. The accepted Flutter client therefore does not invent a direct remote Canvas or Howl TCP path on iOS.

## Ownership notes

- `howl-session` + `howl-vt` remain canonical terminal truth and never wait for Flutter.
- `howl-client.rich` remains the single `text_v1` byte parser.
- `howl-client.view` is immutable, explicitly owned native semantic state.
- `howl-text` owns native metrics, fallback, shaping, glyph identity, and rasterization.
- `howl-render.terminal.Content` owns bounded shape/atlas caches and emits complete Canvas state.
- Flutter owns only platform capture, viewport/history UX, copied resource lifetime, and backend batching.
- The app-private host packet and FFI symbols are version-locked implementation details, not compatibility surfaces.

The measurement and migration evidence is recorded in `../docs/2026-08-30-native-client-flutter-seam.md`.
