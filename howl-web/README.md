# Howl Web

Web is a maintained experimental Howl canary alongside Flutter, not another
terminal engine. Its job is to pressure the same client, text and rendering
owners from a fast browser iteration loop. The node retains the canonical PTY
and VT. No browser platform policy belongs in either owner.

## Current checkpoint

This first main checkpoint owns a bounded freestanding Wasm byte pump and
repeatable gates against the real Howl wire, shared rich snapshot decoder and
Canvas Composer. It is a foundation, not yet an installed PWA or the complete
glyph renderer. The earlier loopback browser/WebSocket experiment established
the live path; its disposable gateways and captured runtime state are not
product source and are not promoted here.

`howl-client.rich.decodeFrames` is the shared byte-entry seam. Native socket
receivers and buffered browser responses use one decoder body. The Web canary
assembles at most one bounded response and decodes it after `snapshot_end`;
it does not turn blocking POSIX reads into browser callbacks or maintain a
second VT. Snapshot rendering currently exposes a diagnostic UTF-8 projection.

The current Wasm allocation is a coarse fixed 32 MiB canary budget. It contains
one bounded frame, one at-most-4-MiB response, a 20-MiB temporary decode/Composer
arena, a 64-KiB diagnostic text projection and bounded input/output buffers.
There is no memory growth or imported host function. These are explicit test
budgets, not a final renderer footprint or a claim to admit every legal large
terminal within this canary's projection limit.

## Build and check

Use the workspace `.zigversion` compiler and Node.js:

```sh
cd howl-web
zig build check
zig build install
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

## Next boundaries

1. Target-build the real FreeType/HarfBuzz dependencies in the `howl-text` owner
   and support retained font bytes instead of imposing host filesystem paths.
2. Consume the shared client view and actual terminal renderer to produce Canvas
   state. Browser glyphs are not an undisclosed replacement for `howl-text`.
3. Supply the browser byte-pump host and a separately owned WebSocket gateway.
   Use explicit operation and queue bounds, independent observation/control,
   and honest disconnect/error states.
4. Prove private authenticated HTTPS/WSS delivery before exposing a terminal;
   then obtain real iPhone input, lifecycle and rendering acceptance.

Flutter remains a native-platform regression client. Web is the preferred fast
canary, not a reason to remove useful native coverage or weaken core contracts.
