# Howl native CLI contract

`howl` is the native human/agent client for one already-running Howl session.
It is not a shell executor, session-discovery service, remote transport, renderer,
or compatibility wrapper around Remoter. It speaks the same frozen
`howl-session` client protocol as graphical clients and projects canonical
terminal state into a form that is pleasant to reason about.

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

The first CLI cut owns no session registry and performs no endpoint discovery.
That is deliberate. Session lifecycle/discovery must earn its contract from real
use rather than being bundled into the observation client.

## Commands

The intended first vocabulary is:

```text
howl version
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

There is intentionally no `exec`, `run`, `shell`, `command`, or equivalent.
To interact with a program running in the PTY, clients submit terminal input.
How the child shell interprets that input is not a Howl API.

Mouse input is part of the canonical session protocol but is intentionally not
in the first CLI mutation cut. Terminal coordinates can become semantically
stale while PTY output changes. The current wire has no server-enforced expected
terminal revision on mouse input, so a client-side observe-then-click check
would create false confidence. A future CLI mouse command must first gain an
atomic stale-target contract at the session boundary or another equally strong
mechanism.

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
    "hyperlinks": 0
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
silently claims otherwise. `detail` reports when styled, linked or multicell
facts exist so a caller knows when richer inspection may matter. Hyperlink URI
projection and compact style runs may be promoted later if real TUI dogfood
shows they routinely improve agent decisions.

`--text` emits only the readable rows for direct human consumption. It is an
explicit formatting choice rather than TTY-dependent magic.

## Rich snapshot

`snapshot --rich` exposes the lossless `text_v1` semantic snapshot: lifecycle and
authority envelope, full presentation/palette state, every bounded cell and
grapheme scalar, DEC/multicell geometry, styles/colors, hyperlink identities and
resolved hyperlink targets.

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

Normal machine-facing output is bounded JSON with explicit schema/version and
closed errors. Actions return a small receipt naming the requested operation and
the session result code. Human `--text` output is the only intentionally
unstructured path in the first cut.

Malformed endpoints, unsupported request families, invalid UTF-8/scalars,
oversized requests/snapshots, protocol disagreement, stale future pointer
contracts and server result failures all fail closed. A successful socket write
is never treated as proof that the terminal operation succeeded.

## Ownership and future Flutter seam

The first implementation may keep reusable protocol client code inside this
package while the boundary is being learned. Do not create a standalone
`howl-client` repository merely because Flutter might use it later.

If CLI/Android measurement later proves that shared native snapshot decoding,
history/diff processing or another hot path should be reused by Flutter, extract
that client engine only then. Flutter should remain strong where it is useful:
application lifecycle, IME, touch/gesture capture, accessibility and final UI
composition. Canonical terminal state and terminal-specific heavy work stay in
or move toward Zig without trading away visual quality or input latency.

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

The CLI installer owns only `howl`. It does not install `howl-sessiond`, the SSH
bridge, Remoter hooks, Fleet configuration, or graphical clients.

Physical Unicode key identity is explicit: use `U+0061` for the physical Unicode key `a`. Ordinary committed text remains `howl type`; a bare `a` is not accepted as a physical-key spelling.
