# howl-flutter

Flutter is the platform host for the native Howl client. It owns platform UI, visible viewport policy, IME/touch/stylus/pointer capture, and the final backend draw submission. It does **not** own the Howl wire, `text_v1`, terminal snapshots, terminal colors/styles/cursor policy, shaping, glyph rasterization, or terminal escape encoding.

The live terminal path is:

```text
howl-instance / howl-vt
        ↓
howl-client.rich → howl-client.view
        ↓
howl-render.terminal.Canvas → final terminal Frame
        ↓
app-private copied native-host frame
        ↓
Flutter resource lease + batched Canvas backend
```

`howl-flutter/native/` owns the version-locked application binding. Its opaque observer and control handles are private to the same Howl/Flutter build and are **not a stable public C ABI**. A successful blocking observation copies one complete final terminal frame into caller-owned memory. The native host admits at most seven visible terminal image resources, leaving the eighth terminal resource slot available for the glyph atlas. If a frame needs Host-recoverable image data which Flutter has not retained yet, the observer exposes one exact `image_id + generation` refill through the private `HIR1` side packet; Flutter decodes that RGBA resource into its ordinary `ui.Image` lease, reports the exact residency, and retries the same observation until every required external resource is resident. `HIR1` therefore remains deliberately one-resource-at-a-time even when the final frame contains several images or placements. The normal `HCR1` terminal-frame packet remains image-byte-free. Flutter never retains mutable native presentation pointers. It reports only the resources for which it still owns a live `ui.Image`; Terminal Canvas generations then decide whether recovery is needed.

Control is semantic. Flutter maps platform events to committed text, named/Unicode physical keys, focus, resize, signals, paste, and semantic mouse facts, then forwards them through `howl-client.actions`. Flutter does not generate terminal escape sequences. The canonical VT alone decides whether a semantic key/mouse event is suppressed or encoded for the child.

## Android

The accepted Android client is currently **arm64 only**. Build the native host and Flutter APK through the checked-in wrapper. Flutter native-assets plugins may publish helper libraries for additional ABIs; app packaging explicitly excludes the non-arm64 DataStore helper slices and the wrapper independently rejects any APK whose final `lib/` ABI set is not exactly `arm64-v8a`:

```sh
ZIG=/path/to/tracked/zig \
FLUTTER=/path/to/flutter \
ANDROID_NDK_ROOT=/path/to/android-ndk \
JAVA_HOME=/path/to/jdk21 \
./build-android.sh profile \
  --dart-define=HOWL_ENDPOINT=tcp://127.0.0.1:43127 \
  --dart-define=HOWL_GEOMETRY_LEADER=true
```

`HOWL_GEOMETRY_LEADER` accepts `1` or `true`. When enabled, viewport/font-size
changes are explicit serialized Instance resizes; attaching the client still does
not otherwise mutate canonical geometry.

The wrapper always performs a clean Flutter build with `--target-platform android-arm64`, verifies that no other ABI entered the APK, and requires `libhowl_native_host.so`. Gradle independently refuses a non-arm64 Flutter target or a missing generated host library.

Physical Note10 pressure also covers the route-less app shell: fresh app data opens the button-only connection shell, a saved Server endpoint persists through Android DataStore, no-argument relaunch returns to that selected Server browser, exact running-Instance selection transitions through Server attach into ordinary HWLS, and leaving the terminal closes its managed observer/control streams before returning to the browser. The test route may be supplied externally through ADB reverse, so Android shell qualification does not depend on WARP/LAN reachability.

`native/build-android.sh` builds the host explicitly; Gradle only verifies and packages the result. The native dependency furnace pins the pressure-proven FreeType and HarfBuzz revisions as static arm64 libraries and links them into one app-private host `.so`. Android does not depend on its private platform FreeType/HarfBuzz ABI.

The terminal font is presentation/deployment policy. The Android native host requires the externally provisioned app-private file:

```text
files/IosevkaTermNerdFont-Regular.ttf
```

and uses Android's `NotoNaskhArabic-Regular.ttf` plus `NotoSansCJK-Regular.ttc` as explicit system fallbacks. Missing sequences outside the configured faces degrade to a replacement glyph rather than failing the terminal frame. These system fonts are neither tracked nor bundled in this repository.

The native control canary is deterministic and does not rely on Android's vendor-specific shell text injector:

```sh
./native/run-control-canary.sh tcp://127.0.0.1:43127
```

It checks committed UTF-8, Enter, Backspace, Delete, Unicode physical key input, paste, focus, tracking-off semantic mouse behavior, resize, and the resulting canonical shell/geometry state.

On touch-first Android, the terminal reserves finger gestures for client-local
history and text-input focus rather than pretending a finger is a terminal
mouse. Mouse/stylus devices continue through canonical semantic mouse input.
Desktop primary drag becomes client-local absolute-row selection when canonical
mouse tracking is off; mouse-aware applications keep their semantic drag stream,
and Shift+drag explicitly forces local selection. Selected UTF-8 still comes from
the Instance's canonical text-extract contract. Selection paint follows the copied
text shape rather than filling intermediate rows to the terminal edge: hard row
breaks add one newline cell, empty selected rows are one cell, and soft wraps do
not invent a newline. Desktop wheel routing reads the Instance's
canonical interaction state: an active
history viewport stays local, mouse-aware applications receive semantic wheel
reports, DEC alternate-scroll becomes cursor-key input, and ordinary shell wheel
input navigates scrollback. Hover/click never eject an active history viewport. A
compact strip above the software keyboard exposes one-shot Ctrl/Alt latches plus
Esc, Tab, arrow keys, keyboard restore, the current raster-size cycle, Copy and
Paste; a latched modifier applies to the next special key or single committed
Unicode scalar, then clears.
The size control shows the current raster size and cycles `16px -> 12px -> 9px
-> 16px`. Those are three native presentation identities: Compact (9 px, 6x12
cell), Small (12 px, 8x15), and Normal (16 px, 10x20). A size change recreates
the private presentation host so `howl-text` rerasterizes at the target size
rather than scaling an old Flutter bitmap. A geometry-leading client also
resizes the canonical PTY to the resulting row/column count. The strip lives inside the
same visible-viewport owner as the terminal so IME/safe-area insets cannot hide
it or silently overlap terminal cells.

IME commits remain typing semantics: Android text edits are translated into
committed text and edit keys. The explicit Paste control is deliberately
different. It reads `text/plain` from the platform clipboard and sends one
canonical Howl semantic paste request, bounded to 65,535 UTF-8 bytes so the
outer input-kind byte still fits the frozen 64 KiB request ceiling. This keeps
bracketed-paste policy in the canonical VT instead of approximating a multi-line
paste as text plus synthetic Enter keys. Empty, unavailable or oversized
clipboard content is a client-local no-op rather than a terminal attach failure.

Copy is likewise presentation-local. With no active selection it writes the
current live or scrolled viewport's bounded `howl-client.view.writeVisibleText`
projection. With an active selection, Flutter retains only stable canonical
cell endpoints and asks the Instance client to extract the exact UTF-8 range. Viewport
scrolling therefore does not retarget selected text, and eviction, bank or
geometry changes invalidate rather than guess. Physical Note10 acceptance has
proved Material handles, floating toolbar, canonical selected-text Copy, and
two-row edge autoscroll across offscreen history.

The long-lived native observer/control pair also owns bounded transport
recovery. The private **v5** host ABI reports a machine failure class separately
from its human diagnostic. Only actual transport availability failures retry at
250 ms, 500 ms, 1 s, 2 s and then at most every 5 s. Cancellation stops the
retired lifetime, stale Server/Session/Instance identity returns managed
navigation to the Server browser, and font/data/resource/protocol failures remain
hard failures. A successful canonical frame resets the cadence. Each transport
lifetime has a generation, so queued control work from a dead connection is
discarded rather than replayed into its replacement. Physical Note10
qualification cut a localhost relay out from under the running app until the
canonical Instance had zero clients, then restored it; the same Flutter process
reattached, reclaimed 32x51 geometry and rendered the surviving Bash Instance
without an app restart.

Cancellation is owned before native construction begins. One app-owned native
Interrupt is shared by the live control and observer workers for that transport
generation; route/presentation teardown cancels it first, workers unwind and
close, and only then is the Interrupt destroyed. History and one-shot Server-tree
requests own separate Interrupt lifetimes, so abandoning scrollback or browsing
cannot cancel the live terminal. Control close is out-of-band from its serialized
command queue and therefore wakes an unanswered blocking request instead of
waiting behind it. The v5 ABI replaces the former host-derived cancellation
handle exports with `howl_native_interrupt_create/cancel/destroy`; Dart checks
`howl_native_host_version == 5` before using the binding.

TCP live presentation permits one pending native observation while Flutter waits for
`endOfFrame`. That pending result owns only copied bytes, including any refill
pixels; decoding `ui.Image` resources, adopting a lease, and retiring the previous
lease remain sequential. A failed pending future stays observable by the next
iteration, while observer cancellation can safely abandon it during restart or
disposal. There is no frame queue or unbounded asynchronous image retirement.

The Flutter host selects its existing native observation policy locally: Unix
uses live row deltas, raw-cache reuse and native request prearming, retaining
its display-boundary coalescing; TCP uses framing-v10 packed complete snapshots.
`useLiveDeltas` names that coupled native policy, not Dart display scheduling.
Complete history snapshots also use packed carriage. Packed transport reconstructs
exact frozen `text_v1` before the native rich decoder, so Canvas/semantic ownership
is unchanged. No policy
is imposed on the Web, Odin or Vulkan hosts, and canonical Instance progress never
waits for a client display boundary.

Android accessibility is projected from the same immutable `howl-client.view`
used by the native renderer; Flutter does not OCR its Canvas or maintain a
second terminal model. The private native host reserves one bounded ~5 MiB
worst-case Canvas/semantic packet for the shared maintained-client command
envelope. Its alpha atlas scales with physical raster density from 192x192 at
1x through 768x768 at the 4x ceiling; one reusable 32 MiB observation arena owns
rich-snapshot decode and immutable-view projection scratch. Dart asks the
version-locked native host for the exact required output-buffer size rather than
mirroring that bound.
Interior blanks and visual row boundaries are
preserved, trailing blank cells/rows are trimmed, wide-cell continuations are
not duplicated, and SGR-concealed cells project as blanks. If that semantic
allowance is exhausted the visual frame still succeeds and the accessibility
node discloses that its visible-text projection was truncated.

## Linux

Native Linux uses GTK's exact text-edit deltas rather than interpreting queued
cumulative editor snapshots as new terminal text. Active composition stays local
until its final transition, including commits normalized by Flutter into insertion
or non-text updates. Private guard characters never enter the terminal. Android
and iOS keep their existing full-value IME and backspace-runway path.

The former combined Linux Flutter/Web helper was removed with the standalone
per-Instance listener topology. Flutter now uses its explicit direct or Server-selected
routes documented below, while the Web gateway performs its own exact Server attach.
Neither client requires a private Session daemon or per-Instance listener.

Build the native host first, then the normal route-agnostic Flutter bundle:

```sh
ZIG=/path/to/tracked/zig ./native/build-linux.sh
flutter build linux --release
```

Select the route when the artifact runs:

```sh
# direct HWLS Instance
./build/linux/x64/release/bundle/howl_flutter tcp://127.0.0.1:43127

# Server browser -> exact Session + Instance -> same-stream HWLS
./build/linux/x64/release/bundle/howl_flutter --server tcp://127.0.0.1:43130
```

`HOWL_ENDPOINT` / `HOWL_SOCKET` are direct-route environment fallbacks.
`HOWL_SERVER_ENDPOINT` selects Server-browser mode. A compiled endpoint remains an
optional deployment override, not a requirement of the standard artifact.

The Linux bundle installs `libhowl_native_host.so` into its existing `$ORIGIN/lib` directory and refuses to build if the native host is missing. Linux uses the system FreeType/HarfBuzz libraries.

Font discovery is exact rather than permissive. `HOWL_FONT`,
`HOWL_FALLBACK_FONT`, and `HOWL_SECONDARY_FALLBACK_FONT` may name explicit
files. Otherwise fontconfig must actually resolve `IosevkaTerm Nerd Font`,
`Noto Sans Arabic`, and `Noto Sans CJK JP`; a silent family substitution is
rejected. The secondary Linux fallback gives the native client CJK coverage
without bundling that large system font into the app or the Web/PWA artifact.

A bare path or `unix:/path` remains a local Linux endpoint option. TCP accepts an explicit numeric IPv4 peer selected by platform/deployment policy; Howl performs no DNS, discovery, authentication, or route selection.

## iOS

The iOS runner remains an honest platform-pressure target. The same native observer/control host object has compiled and linked for arm64 iPhoneOS, and physical iPhone pressure proved final-Canvas resource lifetime with a first 16 KiB atlas publication followed by an identical sparse frame with zero re-upload.

iOS remains a client only: it does not own a PTY, shell, or Unix userland. The native Howl client may connect to an explicitly configured numeric IPv4 TCP peer; deployment/Fleet policy owns how that private route is made reachable. No DNS, discovery, listener, or authentication policy is added to Howl itself.

## App shell and saved Server routes

Flutter now has a deliberately small application shell around the terminal canary.
Its default posture is still terminal-first: when the drawer is closed, the active
terminal or Server browser receives the full body surface. One compact menu button
opens the drawer; edge-drag drawer opening is disabled so platform back/navigation
gestures, especially on iOS, keep their native meaning.

The shell owns only app navigation and saved Server endpoints. It does not own a
Server mirror, Session lifecycle, Instance geometry, terminal grid, pane/split model,
or discovery protocol. Saved Server records are ordinary app preferences containing
a human label plus an explicit validated Howl endpoint. Add/edit/remove and the last
selected saved Server persist across launches. No credentials or secrets are stored.

A standard artifact may launch with no endpoint at all. In that state the shell shows
a small connection empty-state and the drawer can configure a Server. A saved selected
Server becomes the startup surface on the next no-argument launch. Explicit launch
routes still override that startup choice:

```text
howl_flutter ENDPOINT           direct HWLS Instance
howl_flutter --server ENDPOINT  transient Server browser
```

Selecting a Server performs the existing validated one-shot native tree query.
Selecting a running Instance turns the body into the unchanged terminal canary via
`ManagedHowlInstanceTarget`. The drawer remains available on top of that terminal and
provides a simple Back to Server action. Exited Instances remain lifecycle history in
the browser and are not openable.

## Ownership notes

- `howl-instance` + `howl-vt` remain canonical terminal truth and never wait for Flutter.
- `howl-client.rich` remains the single `text_v1` byte parser.
- `howl-client.view` is immutable, explicitly owned native semantic state.
- `howl-text` owns native metrics, fallback, ordinary shaping/rasterization, and the Kitty-derived generated terminal drawing glyphs.
- `howl-render.terminal.Content` owns bounded shape/atlas caches and emits complete Canvas state.
- Flutter owns only platform capture, viewport/history UX, copied resource lifetime, and backend batching.
- The app-private host packet and FFI symbols are version-locked implementation details, not compatibility surfaces.

The measurement and migration evidence is recorded in `../docs/2026-08-30-native-client-flutter-seam.md`.

## Server-managed Instance construction

The app-private native host now has two connection constructors with one common
presentation/control implementation:

- direct mode connects an explicit HWLS Instance endpoint exactly as before;
- managed mode connects one explicit Server endpoint, checks the expected
  `server_id` against its welcome, requests the exact `(session_id, instance_id)`,
  receives `attach_ready`, and hands that same stream into the ordinary HWLS
  client handshake.

After that handoff, observer/control/rendering code is identical to direct mode.
The native seam does not proxy bytes and does not import Server layout or geometry
state. Server routing chooses an Instance; that Instance remains the sole owner of
its canonical terminal geometry.

The Dart Server surface is deliberately thin. `NativeServerTree.fetch` performs one
validated native `server-client` query and returns a typed read-only tree. Flutter
does not parse `server_protocol` bytes or retain a second authoritative Server model.
The browser shows Session labels and retained Instance lineage; exited Instances stay
visible but cannot be opened. Selecting a running Instance creates one
`ManagedHowlInstanceTarget`, after which the existing terminal observer/control path
is reused unchanged.

Server identifiers and tree revisions remain opaque decimal strings in Dart so full
unsigned 64-bit identity survives the language boundary. Session/Instance ids are
used only as exact routing identities. Pane/split layout and visible surface
composition remain app-side presentation concerns.

Browser selections retain the Server incarnation as decimal text. Both native
observer/control constructors receive its full u64 bit pattern before Session and
Instance IDs, compare the Server welcome before attach, and retain it on reconnect.
Stale incarnation is a failed target, not automatic reselection or authentication.
This changes the two managed-create FFI signatures; Dart/native artifacts must be
rebuilt together. Existing Flutter recovery classification and worker cancellation
publication remain separate follow-up work.
