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

The live canary instantiates two independent wire modules: one observer and one
control connection. This lets a long observation wait without blocking semantic
input. Complete framed snapshot bytes move directly from the observer module into
the renderer module; JavaScript neither parses terminal cells, shapes text nor
constructs terminal escape sequences. It retains Canvas resources, submits the
final command stream, and captures platform input as Howl's existing semantic
text, paste, key, focus and resize vocabulary.

A dedicated echo-only PTY proved committed Unicode text, semantic Enter and
Backspace, paste, focus transitions, canonical resize, observer disconnect and
reconnect. Resize leadership gives observation and terminal revisions distinct
meaning: releasing a leader may advance observation metadata while terminal
content remains at the same terminal revision. Backend resource residency follows
the already-proven Flutter lease rule, so an unchanged recovered frame needs no
atlas upload and superseded generations do not accumulate.

The browser input owner reuses Flutter's two-private-use-guard editor model for
IME composition and software Backspace/Delete. Physical browser keys map to the
frozen Howl key identities and modifier bits. The compact phone toolbar exposes
one-shot Ctrl/Alt plus Esc, Tab and arrows; a real browser/PTY proof used the Ctrl
latch to send Ctrl+U and let the kernel TTY kill an unfinished line. Viewport
changes produce explicit canonical resize mutations through the same wire owner.

The browser byte bridge is now maintained in `gateway/`. It binds loopback only,
serves a closed static route table and copies admitted binary WebSocket messages
to one explicit loopback Howl session without parsing the Howl protocol. Host,
Origin, WebSocket structure and connection/byte budgets fail closed before the
upstream socket opens. Public authentication still belongs to Cloudflare Access;
the optional Access-assertion check is an origin misrouting guard, not a second
identity system. Safari acceptance is not yet claimed.

## Build and check

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

## Maintained gateway and PWA shell

`gateway/` owns the loopback HTTP/WebSocket origin. Its black-box test proves that
rejected Host, Origin, Access and WebSocket requests cause zero upstream terminal
connections; only admitted binary WebSockets cross the byte-pump boundary. The
full contract and standalone commands live in `gateway/README.md`.

`render-web` includes a manifest, the existing Howl iOS icon, the tracked Fira
Code terminal font, its redistribution notices and a small service worker. The
service worker is network-first while online and caches only successful,
non-redirected same-origin app responses. An Access login/redirect is therefore
never stored as application content. With the origin stopped, the complete v3
shell relaunches into an explicit `DISCONNECTED` state with no terminal frame but
keeps the keyboard toolbar and IME owner available; after the gateway returns,
the page-level Reconnect control restores observer/control connections without a
page reload.

## Secure delivery and next boundary

The canary hostname is already behind a whole-host Cloudflare Access application
and the existing Home tunnel. The Access application was created before DNS and
before tunnel ingress. Home's `cloudflared` ingress additionally requires the
exact Access audience before forwarding to the loopback gateway. Anonymous HTTP,
a forged assertion and an anonymous WebSocket upgrade all stop at Access. The
origin normally remains stopped outside a bounded canary run.

The next acceptance is intentionally human: start one echo-only origin, authenticate
in Safari, add Howl to the Home Screen, and verify actual iPhone composition,
Backspace/Delete, the Ctrl toolbar, paste, soft-keyboard viewport resize, rotation,
lock/resume, offline shell and reconnect. Pointer/mouse semantics and a normal
interactive shell come only after that canary is healthy.

Flutter remains the native regression client. Web is the preferred fast canary,
not a reason to weaken or duplicate the core owners.

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
zero-import freestanding Wasm. The text target uses WASI libc, exception handling,
exactly four admitted host functions and bounded memory growth (64 MiB initial,
96 MiB maximum). `text/web/runtime.mjs` is the restricted text host reused by Node and browser canaries; it grants no filesystem or socket access. These are honest current
canary limits, not a finished renderer memory budget.

The shared renderer, maintained fail-closed transport, semantic browser input,
Access delivery edge and offline-capable PWA shell are now proven outside Safari.
The remaining acceptance for this canary is the actual iPhone lifecycle and input
pass; it has not been inferred from Chromium.
