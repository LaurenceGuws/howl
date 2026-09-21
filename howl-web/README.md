# Howl Web

Web is a maintained experimental browser canary, not another terminal engine and not a
Server implementation. It pressures the same Instance client, text, Terminal Canvas and
browser-host boundaries from Wasm/JavaScript.

## Current ownership

The browser owns presentation and browser input policy only. Canonical terminal truth
remains in one Howl **Instance**:

```text
Instance
  PTY + VT + canonical geometry + HWLS
        ↓
explicit client stream
        ↓
Web wire/Wasm → shared text/render/Terminal Canvas → browser
```

JavaScript never parses terminal cells, shapes terminal text, or constructs terminal
escape sequences. It hosts Wasm, owns browser resources and UI state, and submits the
existing semantic Howl input vocabulary.

The Web package owns no PTY, VT, Instance, Session, Server, authentication, discovery,
or service-supervision lifetime.

## Maintained gates

These are current and supported as repository proofs:

```sh
cd howl-web
zig build check
zig build render-check
zig build text-check
zig build gateway-check
```

`zig build check` validates the zero-import freestanding wire module, including framing,
split delivery, bounded snapshots and semantic control messages.

`zig build render-check` pressure-tests the shared
`howl-client.view -> howl-text -> howl-render.terminal.Content -> Terminal Canvas`
path in Wasm.

`zig build text-check` compares target-built native/Wasm text metrics, shaping, source
clusters, glyph positions and alpha masks.

`zig build gateway-check` proves the loopback HTTP/WebSocket carrier policy: rejected
Host/Origin/Access/WebSocket requests cause zero upstream terminal connections and only
admitted binary WebSockets cross the protocol-blind byte-pump boundary.

Buildable browser artifacts remain available through:

```sh
zig build render-web
zig build text-web
zig build gateway-install
```

## Live gateway route

The maintained browser gateway now follows the same Server topology as Flutter and the
native CLI. It accepts one loopback Server port plus exact Session and Instance IDs,
performs the bounded `server-client` attach handshake, consumes `attach_ready`, and then
bridges ordinary HWLS bytes without further protocol interpretation.

The browser remains unaware of Server framing. Its existing observer/control/history/
image WebSockets each become independent HWLS clients of the selected Instance through
the gateway. Server still publishes no per-Instance listener and the gateway introduces
no Server-side byte proxy.

The gateway black-box gate proves fail-closed admission before any Server connection,
exact identity attachment for all admitted WebSockets, bounded capacity and long-lived
binary streaming. A real-runtime canary additionally proved:

```text
real Server -> real Session -> real Instance
           -> Web gateway -> WebSocket HWLS hello -> real HWLS welcome
```

The low-level `zig build live -- PORT` Node/Wasm check is intentionally narrower: it
still expects a caller-supplied disposable **direct HWLS** endpoint and is retained only
as a wire pressure tool. It is not the browser product route and must not motivate a
per-Instance listener or standalone Instance daemon.

## Browser interaction policy

The maintained browser host preserves the same client-side policies already pressure-
proved in Flutter/Web canaries:

- semantic committed text, paste, key, focus, resize and mouse actions;
- explicit resize authority, with `not_leader` treated as a normal follower outcome;
- local history viewport state while canonical history remains Instance-owned;
- presentation-local selection/highlight and conceal-safe visible-text projection;
- browser touch kept as UI input while mouse/pen may become semantic terminal mouse;
- bounded reconnect/telemetry state that never becomes terminal truth;
- terminal images and glyph resources following exact generation/residency contracts.

Browser pane/layout composition, if introduced, remains browser presentation state. It
does not create Server geometry or Session pane semantics.

## Gateway and delivery boundary

`gateway/` binds loopback, serves a closed static route table and bridges binary
WebSocket messages to one explicit upstream byte stream without parsing HWLS. Public
identity remains an external delivery-edge concern such as Cloudflare Access; the
gateway's optional assertion check is only an origin-misrouting guard.

Chromium remains the fast browser acceptance lane. Safari/Home-Screen remains the
narrower WebKit/PWA platform canary. Neither browser is allowed to redefine terminal or
Server ownership.
