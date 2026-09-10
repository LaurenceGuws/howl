# Howl Web gateway

This package owns the node-local browser transport edge for the experimental
Howl Web client. It is deliberately protocol-blind: after a bounded HTTP/WebSocket
upgrade it copies binary bytes between the browser and one explicit loopback Howl
session endpoint. It never parses Howl frames, owns a PTY, interprets terminal
state, discovers sessions, or chooses routes.

The process binds **only `127.0.0.1`**. Public delivery belongs to the existing
Cloudflare Tunnel and Access owners; do not bind this gateway to a non-loopback
address or treat the presence of a Cloudflare header as cryptographic
authentication by itself.

## Admission

Before opening the upstream terminal connection the gateway requires:

- exact `Host`;
- exact WebSocket `Origin`;
- HTTP/1.1 GET with no request body;
- WebSocket version 13, one valid 16-byte nonce, and exact upgrade tokens;
- when `--require-access` is selected, a nonempty `Cf-Access-Jwt-Assertion`
  injected by the already-enforcing Cloudflare Access application.

The last check is an origin misrouting guard. Cloudflare Access remains the
authentication authority, matching Remoter's established tunnel boundary. The
origin is not independently exposed on any network interface.

At most six simultaneous WebSockets are admitted. One Howl Web page uses two
steady sockets (live observation + control), lazily adds a third while terminal
image resources are resident, and may use a fourth only while canonical history
is active. Six therefore still permits a normal two-page/Safari-to-standalone
handoff with image resources, while history during such a handoff remains an
explicit bounded capacity edge rather than silently growing transport. One
message is at most 64 KiB, one connection may send
at most 1 MiB and receive at most 8 MiB, and upstream reads are emitted as at
most 16 KiB binary WebSocket messages. Text and fragmented browser messages fail
closed. Ordinary HTTP concurrency is bounded to eight connections.

Static serving is an exact route table only. There is no filesystem path derived
from a request target, redirect, proxy route, directory listing, or fallback SPA
path.

## Build and prove

```sh
zig build check test
zig build install -Doptimize=ReleaseSafe
```

`test` includes a Python-standard-library black-box proof. Denied Host, Origin,
Access and malformed WebSocket requests are verified to make zero upstream
connections. A fully admitted binary connection echoes opaque bytes through a
fake loopback upstream, text is rejected, six simultaneous WebSockets are admitted,
and a seventh is refused.

The executable is:

```text
zig-out/bin/howl-web-gateway
```

Usage:

```text
howl-web-gateway LISTEN_PORT SESSION_PORT EXPECTED_HOST EXPECTED_ORIGIN SITE_DIR WIRE_WASM [--require-access]
```

All ports and paths are explicit. The public canary uses a dedicated echo-only
Howl session first; a normal interactive shell is not an authentication test.
