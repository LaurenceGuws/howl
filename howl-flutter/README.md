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

The accepted Android client is currently **arm64 only**. Build the native host and Flutter APK through the checked-in wrapper:

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
cell endpoints and asks the session to extract the exact UTF-8 range. Viewport
scrolling therefore does not retarget selected text, and eviction, bank or
geometry changes invalidate rather than guess. Physical Note10 acceptance has
proved Material handles, floating toolbar, canonical selected-text Copy, and
two-row edge autoscroll across offscreen history.

The long-lived native observer/control pair also owns bounded transport
recovery. Endpoint attach failures and failures on an already-established
transport retry at 250 ms, 500 ms, 1 s, 2 s and then at most every 5 s. A
successful canonical frame resets that cadence. Each transport lifetime has a
generation, so queued control work from a dead connection is discarded rather
than replayed into its replacement. Platform/font/packet validation failures
remain hard failures. Physical Note10 qualification cut a localhost relay out
from under the running app until the canonical Instance had zero clients, then
restored it; the same Flutter process reattached, reclaimed 32x51 geometry and
rendered the surviving Bash Instance without an app restart.

Observer cancellation is out-of-band from the blocking observation request.
The private native host gives Flutter an independently owned duplicate of the
observer socket; superseding a presentation shuts down that duplicate to wake
the blocked receive, then the observer worker processes its ordinary close and
remains the sole owner which destroys the native Host. This prevents idle
presentation restarts from accumulating stale Instance clients without closing
the same fd from two owners.

TCP live presentation permits one pending native observation while Flutter waits for
`endOfFrame`. That pending result owns only copied bytes, including any refill
pixels; decoding `ui.Image` resources, adopting a lease, and retiring the previous
lease remain sequential. A failed pending future stays observable by the next
iteration, while observer cancellation can safely abandon it during restart or
disposal. There is no frame queue or unbounded asynchronous image retirement.

The Flutter host selects its existing native observation policy locally: Unix
uses live row deltas, raw-cache reuse and native request prearming, retaining
its display-boundary coalescing; TCP uses compressed complete snapshots. `useLiveDeltas` names that coupled native policy,
not Dart display scheduling. History remains on compressed snapshots. No policy
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

For an interactive Home/Linux comparison against the same local PTY as the Web
client, run from the repository root:

```sh
./tools/run-linux-canary.sh both
```

`flutter` and `web` are also accepted as single-client modes. The helper uses
Flutter 3.47.2, starts only loopback listeners, and stops its session/gateway
and Flutter process on Ctrl-C.

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
- managed mode connects one explicit Server endpoint, requests an exact
  `(session_id, instance_id)`, receives `attach_ready`, and hands that same stream
  into the ordinary HWLS client handshake.

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
