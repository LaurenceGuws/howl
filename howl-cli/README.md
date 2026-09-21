# Howl native CLI contract

`howl` is the native human/agent terminal CLI and operator surface for the
node-local `howl-server` collection owner. Client commands speak the same frozen
`howl-session` attach protocol as graphical clients and project canonical terminal
state into a form that is pleasant to reason about. `howl server` currently enters
the bounded server owner in the foreground; the CLI itself does not own PTY+VT
collection lifetime, rendering, remote transport, or Remoter compatibility policy.

The CLI is intentionally built before the durable graphical client. It should
teach us which canonical facts deserve first-class client vocabulary. Terminal
truth remains in `howl-session` + `howl-vt`; the CLI may project or serialize
that truth but never reconstruct it independently.

## Endpoint boundary

Every command addresses one explicit local endpoint:

```text
unix:/run/user/1000/howl/example.sock
tcp://127.0.0.1:43127
```

Unix and IPv4 loopback TCP are local client transports. Remote routing,
authentication and encryption stay outside Howl. An operator may use SSH or SSH
port forwarding to make a remote session locally reachable without teaching
Howl node names, Fleet topology, Mesh routes or credentials.

A foreground `howl server run` process owns the authoritative bounded Session
collection behind the separate HWLM manager protocol. `howl server` and
`howl session` are the operator surface over that live authority; direct terminal
commands still address explicit HWLS endpoints until managed attach lands.

## Commands

The intended first vocabulary is:

```text
howl version
howl server run RUNTIME_DIR [--listen unix|tcp:PORT] [--shell PATH] [--cwd PATH] [--rows N] [--columns N]
howl server status SERVER [--text]
howl server shutdown SERVER
howl session list SERVER [--text]
howl session show SERVER NAME [--text]
howl session create SERVER NAME [--shell PATH] [--command TEXT] [--cwd PATH] [--rows N --columns N]
howl session close SERVER NAME [--expect-id ID]
howl snapshot ENDPOINT [--after REVISION] [--history-offset ROWS] [--text|--rich]
howl state ENDPOINT
howl type ENDPOINT TEXT
printf '%s' 'text' | howl type ENDPOINT --stdin
howl paste ENDPOINT TEXT
printf '%s' 'text' | howl paste ENDPOINT --stdin
howl key ENDPOINT KEY|U+XXXX [--action press|repeat|release] [--mods MODS]
howl focus ENDPOINT in|out
howl resize ENDPOINT ROWS COLUMNS
howl signal ENDPOINT hangup|interrupt|resize-notify|kill|terminate
```

There is intentionally no client-side `exec`, `run`, or shell-evaluation
operation on a running terminal. Session creation may select one bounded child
command through the manager launch contract; after creation, attached clients
interact with the PTY only through terminal input and explicit Session controls.

Mouse input is part of the canonical session protocol but is intentionally not
in the first CLI mutation cut. Terminal coordinates can become semantically
stale while PTY output changes. The current wire has no server-enforced expected
terminal revision on mouse input, so a client-side observe-then-click check
would create false confidence. A future CLI mouse command must first gain an
atomic stale-target contract at the session boundary or another equally strong
mechanism.

## Multi-terminal server

`howl server run /run/user/1000/howl` starts with zero Sessions and publishes one
`howl.server/v2` startup receipt naming its HWLM manager endpoint, fresh server id,
PID and fixed capacity. The runtime lock rejects a second owner for the same
directory. The server remains alive with an empty collection.

HWLM v1 already owns dynamic create/close, exact non-reused Session ids, coherent
roster revisions, retained exited/failed records and bounded shutdown. One Session
failure does not retire the manager or healthy siblings. Each Session temporarily
continues to publish `unix:RUNTIME_DIR/NAME.sock` for ordinary HWLS attachment until
the direct managed-attach handoff lands.

The server is intentionally foreground. Daemonization, restart policy, remote
authentication/encryption and service discovery belong to external owners.

## Compact snapshot

Default `snapshot` emits one bounded JSON object optimized for reasoning rather
than protocol archaeology. Its initial shape is versioned but not a downstream
compatibility promise while the client is experimental:

```json
{
  "schema": "howl.snapshot/v1",
  "revision": 418,
  "terminal_revision": 901,
  "geometry": {"rows": 24, "columns": 100},
  "viewport": {
    "screen": "primary",
    "history_offset": 0,
    "history_count": 87,
    "history_row_base": 1204
  },
  "cursor": {
    "row": 17,
    "column": 4,
    "shape": "block",
    "visible": true,
    "blink": true
  },
  "lifecycle": {"stream_closed": false, "child_exited": false},
  "resize": {"leader_present": false, "you_are_leader": false},
  "lines": ["$ nvim", "..."],
  "wrapped_rows": [0],
  "line_geometry": [],
  "detail": {
    "styled_cells": 42,
    "linked_cells": 0,
    "multicell_cells": 0,
    "hyperlinks": 0,
    "images": 0,
    "image_placements": 0
  }
}
```

`lines` has exactly `geometry.rows` entries. Each entry is readable terminal text
for that semantic row with ordinary trailing blank cells removed. Empty rows are
empty strings, preserving row identity without flooding the output with spaces.
Wide/multicell continuation cells are not duplicated as extra characters.
`wrapped_rows` preserves soft-wrap identity so a visual row break is never
silently presented as a child-program newline. `line_geometry` contains only
non-single-width DEC rows, with row index plus the canonical double-width or
double-height identity.

The compact projection is intentionally lossy in presentation detail, but never
silently claims otherwise. `detail` reports when styled, linked, multicell, or
terminal-image facts exist so a caller knows when richer inspection may matter.
Hyperlink URI projection and compact style runs may be promoted later if real
TUI dogfood shows they routinely improve agent decisions.

`--text` emits only the readable rows for direct human consumption. It is an
explicit formatting choice rather than TTY-dependent magic.

## Rich snapshot

`snapshot --rich` exposes the coherent framing-v9 snapshot: `text_v1`
lifecycle/authority and terminal-text records, the `graphics_v2` cell lattice,
image identities and placements, and one bounded `properties_v1` packet. The
properties record emits readable valid-UTF-8 title/progress plus lossless
`packet_hex` for icon, directory, remote host, shell identity/marks, and all other
property bytes. These labels do not confer process, path, or execution authority.

Exact RGBA bytes are not copied into every snapshot; graphical clients fetch a
named image generation on demand through the separate bounded resource request.
The CLI and endpoint must use the same framing version.

The rich form may remain NDJSON because streaming bounded records is useful for
forensic inspection and tests. It is explicitly *not* the default AX surface.
Rich formatting consumes `howl-client.rich` directly: the frozen wire is decoded
once by the UI-agnostic native engine and the CLI only chooses this diagnostic
record presentation.

## Revision semantics

A snapshot has two identities:

- `revision` is the endpoint observation revision and changes for observable
  session envelope/authority state as well as terminal changes.
- `terminal_revision` is the canonical VT semantic revision.

`snapshot --after REVISION` maps directly to the session protocol's bounded
request-driven observation. It waits for a later observable revision rather than
polling or reconstructing changes client-side.

`state` returns the separately negotiated canonical interaction state together
with its `terminal_revision`. A caller may correlate it with a snapshot without
probing the PTY to infer hidden modes.

Text, paste, key, focus and signal actions are live terminal operations. They do
not require an unchanged screen revision: changing PTY output does not by itself
make normal typing stale. Coordinate-sensitive actions must not inherit that
assumption; pointer targeting remains deferred as described above.

## Interaction state

`state` exposes the complete canonical interaction facts already carried by the
session wire, including:

- application cursor and keypad modes;
- newline and Meta behavior;
- key-up / Kitty keyboard flags;
- bracketed paste and paste events;
- focus reporting;
- mouse tracking and mouse protocol;
- termios signal routing;
- alternate scroll and in-band resize notifications.

These facts come from `howl-vt`. The CLI must never infer them by sending escape
sequences, perturbing the application or reconstructing parser history.

## Input semantics

`type` is committed UTF-8 text and maps to canonical `InputKind.bytes`. It is not
raw PTY injection: `howl-vt` remains the input encoder/authority for the event.
`--stdin` is preferred for multiline or shell-sensitive text.

`paste` maps to canonical `InputKind.paste`, so `howl-vt` decides whether
bracketed-paste wrapping or other terminal consequences apply.

`key` uses typed physical-key identity and press/repeat/release semantics. Named
keys use the frozen `howl-session` vocabulary. Unicode physical keys may be added
only with the same validated scalar/modifier model; clients must not invent
escape sequences for application-cursor, keypad, modifyOtherKeys or Kitty modes.

`focus` submits the canonical semantic focus event.

`signal` uses the fixed process-group signal vocabulary and never synthesizes a
keyboard shortcut as a substitute for a requested signal.

## Resize authority

Resize remains explicit canonical session state. A one-shot CLI `resize` client
must assign its own real connection-local
client id as leader, request the new rows/columns, verify the result, then close.
A mere observation never assigns leadership or changes geometry.

Long-lived graphical clients may hold resize leadership while appropriate. The
CLI must not pretend leadership is durable beyond its actual connection.

## Output and errors

Normal machine-facing output is bounded JSON with explicit schema/version. Server
status, roster/session inspection and lifecycle actions use dedicated
`howl.server.*` schemas; 64-bit opaque/session/revision identities are serialized as
JSON strings so JavaScript consumers do not lose precision. Human formatting is
opt-in through `--text`.

Every command failure is caught at the executable boundary and emits one bounded
`howl.error/v1` JSON object on stderr instead of a Zig return trace. Manager
rejections preserve the stable HWLM result code (for example `name_exists` or
`stale_identity`), while transport failures preserve the connect stage, OS error
when available, and bounded SSH carrier diagnostic. Usage failures exit 64; other
failures exit nonzero. `--help`/`help` are successful stdout-only commands.

Malformed endpoints, unsupported request families, invalid UTF-8/scalars,
oversized requests/snapshots, protocol disagreement, stale identities and server
result failures all fail closed. A successful socket write is never treated as
proof that the requested operation succeeded.

## Shared client ownership

The in-tree `howl-client` module owns the shared native ordered-stream transport,
HWLS Session client, HWLM manager client, semantic actions, rich decoding,
raw-cache lifetime, and the opaque immutable coarse projection. Protocol ownership
stays separate even though socket/SSH/cancellation mechanics are shared. The CLI
consumes those clients and owns command vocabulary and diagnostic formatting only.

Native Flutter, Odin, and the Web decoding/rendering path reuse these boundaries.
Application lifecycle, IME, gestures, accessibility, and presentation remain with
their hosts. Building or testing the shared engine does not install a graphical
client or update its running Session endpoint.

## User installation

The CLI project owns one regular executable at `~/.local/bin/howl`:

```sh
./howl-cli/install --check
./howl-cli/install --promote
```

Promotion requires clean pushed `main`, builds `ReleaseSmall`, verifies
`howl.version/v1`, and atomically replaces only a binary proven by the current CLI
receipt or the exact legacy Howl installer receipt. Symlinks, unrelated commands,
and locally changed installed binaries are refused. The migration rule exists so
the retired pre-2026-08-30 `start`/`stop`/`sessions` CLI can be replaced without
teaching future installers to recognize its command vocabulary.

The CLI installer owns `howl`; `howl server` needs no `howl-sessiond` child. It does not install the SSH
bridge, Remoter hooks, Fleet configuration, or graphical clients.

Physical Unicode key identity is explicit: use `U+0061` for the physical Unicode key `a`. Ordinary committed text remains `howl type`; a bare `a` is not accepted as a physical-key spelling.


## Native SSH attachment (Linux)

The rebuilt CLI accepts the same semantic commands through an explicit SSH
carrier, for example:

```sh
howl snapshot 'ssh://user@host/run/user/1000/session.sock' --text
howl state 'ssh://host/run/user/1000/session.sock?bridge=/opt/howl/howl-session-bridge'
```

The target must already have an independently managed matching Howl Session and
bridge. OpenSSH aliases, keys and trust are operator-owned; noninteractive auth
and a known host are required. This is a binary exec channel, not `ssh` inside a
local shell, a remote login/PTY allocator, or a remote installer. Closing the CLI
closes only its route. Raw terminal data, images, semantic input and properties
retain the same shared client/wire owners. See `../howl-client/README.md` for the
bounded first endpoint spelling and its current limitations.
