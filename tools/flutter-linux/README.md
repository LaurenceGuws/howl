# Flutter Linux refresh-rate patch

Howl pins Flutter with FVM. Flutter 3.47.4's Linux GTK embedder does not install
an embedder `vsync_callback`, so the engine falls back to
`VsyncWaiterFallback`, which is fixed at 60 Hz even when the Flutter view is on
a higher-refresh display.

Howl carries a temporary Linux-only engine patch until upstream Flutter ships an
equivalent fix on stable.

## Scope

The patch in `flutter-3.47.4-linux-vsync.patch` is based on the refresh-rate
portion of Flutter PR #192342. It carries these upstream commits:

- `261daf45cf14a339ea2686dfe1812c081d3aad07` — drive Linux vsync at the display refresh rate
- `ffbfdeee3bcde76c786bf3e63f13dc7e10195afa` — guard teardown with a null display monitor
- `23ca11b8b0fe53feeaf584bd1302e96feb289c5f` — correct tick snapping before the phase
- `fc16fbeadb2048daf4e6faeafd9490bf1436b3d8` — treat a null GDK monitor as unknown

It intentionally does **not** carry PR commits 2/4, which change Wayland parent
surface presentation. That is a separate optimization and Howl has not shown a
need for it.

Howl adds one small local invariant on top: when the refresh interval changes,
the new interval may not begin before the previously reported frame interval
has ended. This avoids a backwards Flutter frame timestamp during a 60 -> 240
Hz transition.

## Known limitation

Flutter 3.47.4 updates a view's display ID through its existing window-metrics
path. On GTK3/Wayland, moving a window between monitors with the **same scale**
may not generate a geometry/scale notification, so the refresh interval may not
follow that move immediately.

This is accepted for Howl's current Home setup. The 1x 240 Hz Dell and
fractionally-scaled 60 Hz Samsung do generate the required update. Do not grow
this patch to solve same-scale Wayland monitor migration until Howl actually
needs it.

The callback is refresh-rate-matched timer scheduling, not hardware-vsync phase
synchronization.

## Proven behavior on Home

With Flutter 3.47.4 on the same running probe/window:

- stock Linux engine on 240 Hz Dell: 16,666.7 us frame cadence (60 Hz)
- patched engine on Dell: 4,166.7 us steady cadence (240 Hz)
- move patched window to fractional-scale Samsung: 16,666.7 us (60 Hz)
- move it back to Dell: 4,166.7 us (240 Hz)

The targeted Flutter Linux engine tests include the refresh-rate transition
monotonicity case.

## Build ownership

Do not edit an FVM SDK checkout in place. `prepare-engine.sh` creates a disposable
checkout under `temp/` and hydrates Flutter engine dependencies. The first sync
is several GiB and the first C++ build is expensive. Subsequent patch rebuilds
are small; after the initial build, changing this patch relinked the GTK engine
in seconds.

On Home, keep native builds constrained (`-j2`, about two cores). Prefer Colt
for repeated engine furnace work once the workflow is stable.

```bash
tools/flutter-linux/prepare-engine.sh

tools/flutter-linux/build-engine.sh profile
```

The profile output is:

```text
temp/flutter-engine-3.47.4/engine/src/out/host_profile
```

Run Howl against it with:

```bash
cd howl-flutter
fvm flutter run -d linux --profile \
  --local-engine-src-path="$PWD/../temp/flutter-engine-3.47.4/engine/src" \
  --local-engine=host_profile \
  --local-engine-host=host_profile \
  --dart-entrypoint-args tcp://127.0.0.1:43127
```

## Retirement

After a Flutter upgrade, first run the stock cadence check. If stock Linux
Flutter follows the active display refresh rate, delete this patch and the
custom-engine tooling rather than rebasing it by habit.
