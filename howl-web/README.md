# Howl Web

Web is a maintained experimental Howl canary alongside Flutter, not another
terminal engine. Its job is to pressure the same client, text and rendering
owners from a fast browser iteration loop. The node retains the canonical PTY
and VT. No browser platform policy belongs in either owner.

## Current checkpoint

Web now has two maintained Wasm lanes with deliberately different host contracts.
The zero-import freestanding wire module owns bounded Howl framing, snapshot
assembly and semantic control messages. The `wasm32-wasi` renderer lane owns the
real `howl-client.view -> howl-text -> howl-render.terminal.Content -> Canvas
Composer` path with the pinned FreeType/HarfBuzz target. The node still owns the
only canonical PTY and VT.

The live canary keeps independent live-observer and control wire modules, and
lazily opens a third history observer only while the client is scrolled away from
the live viewport. This lets long observations and canonical history requests
run without blocking semantic input. Complete framed snapshot bytes move directly
from the selected observer module into the renderer module; JavaScript neither
parses terminal cells, shapes text nor constructs terminal escape sequences. It
retains Canvas resources, submits the final command stream, and captures platform
input as Howl's existing semantic text, paste, key, focus and resize vocabulary.

A dedicated echo-only PTY proved committed Unicode text, semantic Enter and
Backspace, paste, focus transitions, canonical resize, observer disconnect and
reconnect. Resize leadership gives observation and terminal revisions distinct
meaning: releasing a leader may advance observation metadata while terminal
content remains at the same terminal revision. Backend resource residency follows
the already-proven Flutter lease rule, so an unchanged recovered frame needs no
atlas upload and superseded generations do not accumulate.

Live browser presentation prefers requestAnimationFrame, with a visible-page 50 ms timer fallback so a throttled mobile rAF cannot leave fresh complete snapshots unpainted indefinitely. The first display callback wins and cancels the other; latest-complete-frame coalescing remains bounded.

The browser input owner reuses Flutter's two-private-use-guard editor model for
IME composition and software Backspace/Delete. Physical browser keys map to the
frozen Howl key identities and modifier bits. Browser control mutations remain
strictly serialized, but adjacent committed text waiting behind an in-flight
request is coalesced up to the existing 4096-byte semantic bound; keys, paste,
focus and resize remain ordering barriers and the pending control queue is bounded. The compact phone toolbar exposes
one-shot Ctrl/Alt plus Esc, Tab and arrows; a real browser/PTY proof used the Ctrl
latch to send Ctrl+U and let the kernel TTY kill an unfinished line. Viewport
changes produce explicit canonical resize mutations through the same wire owner. Browser geometry follows the session's existing explicit resize authority instead of fighting it: a Web control connection claims geometry only when the latest canonical observation reports no leader, keeps resizing only while that control connection owns the local claim, and otherwise follows the leader's canonical geometry. A lost or raced claim returns `not_leader` as a normal control outcome so the browser becomes a follower rather than stealing authority back.

Copy is presentation-local rather than terminal input. The currently displayed
live/history observer exposes the same bounded conceal-safe
`howl-client.view.writeVisibleText` projection used by Flutter accessibility and
Copy, and the browser toolbar writes that UTF-8 text to the platform clipboard.
Wide-cell continuations, trailing blanks and SGR concealment therefore have one
shared owner; the Web status reports when the 64 KiB projection was truncated.
On physical Note10 v29, visible markers and Nerd glyphs copied successfully while
an exact concealed canonical marker remained absent from the clipboard.

Pointer capture follows the same mobile policy as Flutter. Finger touch remains
browser/mobile UI input and never becomes a terminal mouse event. Mouse and pen
PointerEvents are mapped from the actually displayed Canvas content rectangle
back into canonical cell and logical-pixel coordinates, with out-of-bounds or
non-integral terminal geometry refused rather than guessed. Press/release
transitions remain ordered control barriers; high-rate pointer moves are
latest-wins with at most one move on the wire and one newer move retained
client-locally. Desktop wheel routing asks the canonical interaction-state
endpoint rather than inferring application modes: active client-local history
wins first, terminal mouse tracking receives semantic wheel input, DEC alternate
scroll becomes cursor-key input, and an ordinary shell enters local scrollback.
The Wasm owner serializes the frozen semantic mouse grammar; terminal
SGR/X10/etc. encoding remains solely in the canonical VT.
Desktop primary drag follows the same canonical mode split: with mouse tracking
off it creates a client-local absolute-row selection, while mouse-aware applications
keep their semantic drag stream. Shift+drag is the explicit local-selection override.
The highlight is presentation-only and text-shaped: each row stops after its
actual terminal content, hard row breaks paint one extra newline cell (so an
empty selected line is one cell), and soft wraps do not invent a newline. Copy
still requests canonical UTF-8 through Session's existing text-extract contract
rather than reconstructing text from Canvas pixels. DOM overlay boundaries are
snapped to shared device-pixel edges so CSS scaling cannot open seams between
adjacent selected rows.

The live browser shell also carries a bounded client-local telemetry flight recorder
for mobile canary diagnosis. It retains at most 768 metadata events and records
IME/input staging counts, control-queue coalescing/depth, control acknowledgement
latency, WebSocket lifecycle, renderer duration/cadence, lifecycle transitions and
large event-loop stalls. The recorder mechanically rejects raw text/content/error
message fields, never uploads telemetry, and exposes only a collapsed Telemetry
panel with compact-summary, full-log and Clear controls. The compact path emits
`howl.web-telemetry-summary/v1` JSON for physical canary diagnosis.

Web scrollback now reuses Flutter's client-local absolute-anchor model. Shell wheel
input changes only the requested `history_offset`; a lazy history observer asks the
canonical session for retained rows while the live observer continues advancing at
offset zero. New PTY output moves the requested offset to preserve the same absolute
top row. Keyboard/text input deliberately returns to live, while mouse hover/click
never discards an active history viewport. Returning to live closes the history
observer. One page therefore uses at most three WebSockets: live observer,
control, and transient history observer. The gateway admits six globally so a Safari page and
its newly launched standalone PWA may overlap during handoff; a seventh is refused.

The browser byte bridge is now maintained in `gateway/`. It binds loopback only,
serves a closed static route table and copies admitted binary WebSocket messages
to one explicit loopback Howl session without parsing the Howl protocol. Host,
Origin, WebSocket structure and connection/byte budgets fail closed before the
upstream socket opens. Public authentication still belongs to Cloudflare Access;
the optional Access-assertion check is an origin misrouting guard, not a second
identity system. Chromium is the primary fast acceptance lane; Safari/Home-Screen
is retained as the narrower WebKit/PWA platform canary.

## Build and check

For a local Linux PWA/Flutter comparison against one shared interactive PTY,
run from the repository root:

```sh
./tools/run-linux-canary.sh both
```

Use `web` to launch only the browser lane. The local PWA origin is kept stable
at `http://127.0.0.1:43129/`; the helper binds loopback only and tears down its
session and gateway on Ctrl-C.

Use the workspace `.zigversion` compiler, Node.js and Python 3 standard library:

```sh
cd howl-web
zig build check render-check gateway-check
zig build install render-web gateway-install
```

The artifact is `zig-out/bin/howl-web.wasm`. `check` instantiates the actual
module, verifies its exact exports and zero imports, checks all welcome split
positions and single-byte delivery, rejects invalid/truncated/oversized frames,
and runs real Canvas composition and clipping. Root core dependencies remain
unchanged; Web has its own gate just as the other experimental embedders do.

## Live canonical-session gate

Build and launch a **dedicated echo-only session**, not a working terminal:

```sh
(cd howl-session && zig build install -Doptimize=ReleaseSafe)
# From the Howl repository root, in a separate operator terminal:
howl-session/zig-out/bin/howl-sessiond tcp:0 /bin/sh 12 72 \
  "exec python3 -u '$PWD/howl-web/tests/echo.py'"
```

Use the exact loopback port printed by that process:

```sh
cd howl-web
zig build live -- ANNOUNCED_PORT
```

The gate sends committed Unicode text plus semantic Enter, Backspace, paste,
focus and resize operations, decodes the real PTY/VT response through Wasm one
byte at a time, and reconnects with a fresh client identity while preserving
terminal content and resized geometry. Resize is deliberately a two-request
operation inside Wasm: assign-leader succeeds before the follow-up resize frame is
published. Node hosts Wasm for this gate; Safari acceptance still requires the
real phone. Stop the dedicated session after testing.

## Shared terminal-renderer target

`zig build render-check` proves the actual shared renderer on a bounded semantic
view. `zig build render-web` additionally builds the local live browser artifact
under `render/zig-out/live-web/`. The live renderer accepts only complete bounded
Howl snapshot responses, decodes through `howl-client.rich`, projects the shared
client view, shapes/rasterizes through `howl-text`, publishes terminal Content,
and derives a Canvas Composer frame.

The current live renderer uses coarse canary budgets: 128 MiB initial / 192 MiB
maximum Wasm memory, a 24 MiB persistent Zig arena, a 20 MiB transient decode
arena and a 1024x1024 alpha atlas. The Fira-backed browser proof stayed at 134,873,088 bytes
after initialization and across input/reconnect. These are explicit pressure-test
ceilings, not a final footprint target.

The browser backend keeps one exact lease of resources referenced by the current
frame. It acknowledges residency only after successfully drawing that frame; a
failed draw therefore cannot cause the renderer to assume an upload exists. This
matches the native Flutter resource-lifetime contract.

Terminal images use the same lease without entering the renderer's recovery
pixels. The live renderer admits at most seven visible terminal image resources
plus the glyph atlas and retains the protocol's bounded placement set. A
complete v4 graphics snapshot may cause it to report one exact missing external
Canvas resource plus its canonical terminal `image_id + generation`. The
browser lazily opens one dedicated third Howl wire connection, demand-fetches
that exact RGBA8 generation into the wire instance's bounded scratch, creates
the ordinary Canvas backend resource, reports exact residency, and retries the
same immutable snapshot. Several cold image resources therefore refill
serially through the same connection; the eighth render attempt is reserved for
the final frame after at most seven refills. Only the successful drawn frame is
acknowledged. The steady observer remains free to coalesce newer live snapshots
while an asynchronous refill is in flight.

The browser presentation path reuses one alpha-compositing scratch Canvas instead
of allocating a temporary Canvas per glyph command. Live snapshots are still
observed canonically, but unpainted browser frames are coalesced to the newest
complete snapshot at `requestAnimationFrame` cadence so a fast terminal cannot
force Safari to synchronously paint more frames than the display can present.
History snapshots remain explicit client requests rather than part of this live
presentation coalescing.

The live Web font set keeps Fira Code as the terminal metrics/primary face,
loads the tracked Noto Sans fixture as the first ordered fallback, then uses the
unmodified Nerd Fonts 3.4.0 symbols-only face for terminal PUA/icon coverage.
Web presentation now owns the same normal/small/compact raster choices as the
Flutter client: 16 px, 12 px and 9 px. The toolbar zoom control recreates only
the private Wasm renderer at the selected native font lattice; it does not
reconnect Session or control transport. Geometry authority remains a separate
`Lead` action. Keep browser/page zoom at 100% for terminal quality: shrinking an
18 px (or any other) rasterized Canvas through browser/CSS scaling visibly
softens the glyph alpha mask. When Web leads at 9 px, the Fira Code metrics are
6x12 pixels per cell, allowing a 157-column terminal to occupy 942 CSS/device
pixels on the 1x Dell without bitmap resampling.
The symbols face adds about 2.5 MB to the cached PWA shell but does not change
cell metrics; the earlier physical Note10 v27/v28 18 px A/B kept the same 11x23
cell and 32x51 geometry while replacing prompt tofu with the canonical Nerd glyphs. The
renderer grew by only one 64 KiB Wasm memory page in that run. Provenance,
checksum and the complete redistribution license are tracked under
`render/fonts/` and the license is linked from the Web shell. `howl-render`
still owns the final missing-sequence policy: if no configured face covers a
sequence, it shapes U+FFFD instead of failing the frame.

## Maintained gateway and PWA shell

`gateway/` owns the loopback HTTP/WebSocket origin. Its black-box test proves that
rejected Host, Origin, Access and WebSocket requests cause zero upstream terminal
connections; only admitted binary WebSockets cross the byte-pump boundary. The
full contract and standalone commands live in `gateway/README.md`.

`render-web` includes a manifest, the existing Howl iOS icon, the tracked Fira
Code terminal font, its tracked Noto fallback, redistribution notices and a small
service worker. The service worker is network-first while online and caches only
successful, non-redirected same-origin app responses. An Access login/redirect is
therefore never stored as application content. The shell keeps an explicit Reload
control because installed mobile Web Apps may expose no browser refresh chrome or
gesture. A newly installed worker first caches the complete versioned shell and
requests `skipWaiting()`; Reload additionally promotes any already-waiting worker,
checks for a newer installation, explicitly promotes that worker too, and waits
for activation before navigating. `clients.claim()` then adopts open pages. This
bounded handoff exists because physical Brave can retain a fully installed worker
in `waiting` across ordinary reloads. With the origin stopped, the cached shell relaunches into an explicit
`DISCONNECTED` state with no terminal frame; after the gateway returns, the
page-level Reconnect control restores observer/control connections without a page
reload. On a visible-page transition, the browser host also performs two bounded
transport-health probes so Safari/iOS suspension can automatically rebuild a dead
observer/control pair; explicit Reconnect remains the fallback rather than an
unbounded retry loop.

## Secure delivery and next boundary

The canary hostname is already behind a whole-host Cloudflare Access application
and the existing Home tunnel. The Access application was created before DNS and
before tunnel ingress. Home's `cloudflared` ingress additionally requires the
exact Access audience before forwarding to the loopback gateway. Anonymous HTTP,
a forged assertion and an anonymous WebSocket upgrade all stop at Access. The
origin normally remains stopped outside a bounded canary run.

A normal interactive session is proven in Chromium through semantic Unicode
paste, physical keyboard input, bounded burst input, reconnect, canonical
scrollback and stable resize ownership. Safari/Home-Screen has separately proven
single-client input/viewport behavior and Safari-leader/Chromium-follower geometry
without resize ping-pong. Visible unexpected WebSocket closure self-heals through
bounded reconnect probes. The Note10 Web canary also physically proved the
pointer split under Neovim SGR mouse tracking: a real Android finger tap left the
canonical cursor unchanged, while Android's `stylus` source traversed Brave's pen
PointerEvent path and moved the canonical cursor to the addressed terminal row.

Flutter and Web remain sibling visual canaries rather than successors. Flutter
pressures the native TCP/client/platform-host path; Web pressures the
WebSocket/Wasm/browser path. Both reuse and challenge the same canonical session,
client, text and Canvas owners.

## Shared text target checkpoint

The real memory-font engine and pinned FreeType/HarfBuzz target build now live
in the tracked `howl-text` module. Run the maintained consumer proof here:

```sh
zig build text-check
zig build text-web
```

The first command compares target-built native and Wasm metrics, source clusters,
glyph positions, natural raster geometry and every alpha-mask byte. It also
checks real C nonlocal jumps, independent ownership after input overwrite,
invalid-input recovery, 50 repeated lifetimes without further memory growth,
and the browser runtime's range, descriptor, entropy and console bounds.

The second command builds `text/zig-out/text-web/` for a local browser check.
Serve only that directory on an explicitly selected loopback endpoint. The page
places masks returned by Howl; it does not call browser text shaping. Its Repeat
button rebuilds the font owner and reruns the native-reference comparison. This
local-only test includes a licensed font fixture and must not be confused with
the publicly deployable terminal application.

Keep the two target contracts distinct. The existing wire/Canvas gate is
zero-import freestanding Wasm. The text target uses WASI libc, exception handling plus reference types,
exactly four admitted host functions and bounded memory growth (64 MiB initial,
96 MiB maximum). `text/web/runtime.mjs` is the restricted text host reused by Node and browser canaries; it grants no filesystem or socket access. These are honest current
canary limits, not a finished renderer memory budget.

The shared renderer, maintained fail-closed transport, semantic browser input,
Access delivery edge, Chromium lifecycle and Safari/Home-Screen input/resize paths
are physically proven. Keep iPhone rounds scoped to WebKit/PWA-specific behavior
rather than using the phone as the primary Web development lane.
