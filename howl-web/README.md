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

The live loopback canary instantiates two independent wire modules: one observer
and one control connection. This lets a long observation wait without blocking
committed input. Complete framed snapshot bytes move directly from the observer
module into the renderer module; JavaScript neither parses terminal cells nor
shapes text. It retains Canvas resources, submits the final command stream, and
captures ordinary browser input.

A dedicated echo-only PTY proved real committed input, Unicode rendering, observer
disconnect/reconnect with a fresh client identity, recovery of the same canonical
revision, and zero atlas re-upload for an unchanged recovered frame. Backend
resource residency follows the already-proven Flutter lease rule: each completed
frame names the exact resource generations still live, so superseded atlas
generations do not accumulate.

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

The gate sends committed Unicode text, decodes the real PTY/VT response through
Wasm one byte at a time, disconnects and obtains a fresh client identity while
recovering the same canonical revision and text. Node hosts Wasm for this gate;
it does not establish Safari, keyboard, graphics or WebSocket acceptance by
itself. Stop the dedicated session after testing.

## Shared terminal-renderer target

`zig build render-check` proves the actual shared renderer on a bounded semantic
view. `zig build render-web` additionally builds the local live browser artifact
under `render/zig-out/live-web/`. The live renderer accepts only complete bounded
Howl snapshot responses, decodes through `howl-client.rich`, projects the shared
client view, shapes/rasterizes through `howl-text`, publishes terminal Content,
and derives a Canvas Composer frame.

The current live renderer uses coarse canary budgets: 128 MiB initial / 192 MiB
maximum Wasm memory, a 24 MiB persistent Zig arena, a 20 MiB transient decode
arena and a 1024x1024 alpha atlas. The browser proof stayed at 134,742,016 bytes
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

`render-web` now includes a manifest, the existing Howl iOS icon and a small service
worker. The service worker is network-first while online and caches only successful,
non-redirected same-origin app responses. An Access login/redirect is therefore
never stored as application content. With the origin stopped, the cached shell
relaunches into an explicit `DISCONNECTED` state with no terminal frame; after the
gateway returns, the page-level Reconnect control can restore observer/control
connections without reloading.

## Next boundaries

1. Put the maintained loopback gateway behind a whole-host Cloudflare Access app
   and the existing Home tunnel, with the Access policy created before the tunnel
   ingress is made reachable.
2. Broaden browser control from committed lines to the existing semantic key,
   paste, focus, resize and pointer actions without duplicating terminal encoding.
3. Obtain real Safari/Home-Screen input, lifecycle, rotation and reconnect evidence
   on the iPhone.

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

The shared renderer, maintained loopback transport and offline-capable PWA shell
are now proven. The remaining product work is Cloudflare Access delivery and full
semantic browser input, followed by actual Safari/iPhone acceptance.
