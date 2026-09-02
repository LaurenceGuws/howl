# howl-session wire contract

`howl-session` owns one node-local PTY and one canonical `howl-vt` terminal.
The framing below is transport-neutral. `howl-sessiond` accepts either its
established Unix stream path or an IPv4 loopback TCP listener selected with
`tcp:PORT`; `tcp:0` asks the kernel for a free port and prints the resolved
`tcp://127.0.0.1:PORT` endpoint. Both are local client transports. Remote
reachability, authentication and routing remain outside Howl; the existing
`howl-session-bridge` is a protocol-blind SSH/stdio adapter for the Unix path.

This document is the client contract for framing version 1 and session protocol
version 1. All multi-byte integers are unsigned big-endian unless a field is
explicitly described as signed. Reserved bytes and reserved bits must be zero.

The tracked byte corpus is `protocol/v1-vectors.json`. A clean-room Python
decoder that does not import, execute, or inspect the Zig implementation lives
at `tools/validate_vectors.py`.

## Framing

Every message is one 12-byte header followed immediately by `payload_len`
payload bytes. There are no transport delimiters between frames.

| Offset | Bytes | Meaning |
| --- | ---: | --- |
| 0 | 4 | ASCII `HWLS` |
| 4 | 1 | framing version, currently `1` |
| 5 | 1 | frame kind |
| 6 | 2 | reserved, zero |
| 8 | 4 | payload length |

One frame payload is at most 1 MiB. The node-local endpoint accepts at most
64 KiB in one **client request** payload. A client must therefore keep every
outbound frame payload at or below 65,536 bytes even though response frames may
be larger. One materialized observation response, including frame headers, is
bounded to 4 MiB.

Frame kinds are:

| Value | Kind | Direction |
| ---: | --- | --- |
| 1 | `hello` | client → endpoint |
| 2 | `welcome` | endpoint → client |
| 3 | `observe` | client → endpoint |
| 4 | `snapshot_begin` | endpoint → client |
| 5 | `snapshot_data` | endpoint → client |
| 6 | `snapshot_end` | endpoint → client |
| 7 | `input` | client → endpoint |
| 8 | `assign_leader` | client → endpoint |
| 9 | `resize` | client → endpoint |
| 10 | `signal` | client → endpoint |
| 11 | `result` | endpoint → client |
| 12 | `interaction_state` | client → endpoint |
| 13 | `interaction_state_snapshot` | endpoint → client |

Invalid magic, framing version, reserved header bits, frame kind, or a declared
payload above 1 MiB is a framing failure. The endpoint closes a connection on a
framing failure or an inbound request payload above 64 KiB.

## Attach handshake

The first client frame is an empty `hello`. The frame header version is the
complete Howl wire compatibility boundary; there is no second protocol-version
or feature-negotiation matrix. When the wire changes, change the frame version
instead of accumulating compatibility branches for clients Howl does not
maintain.

The endpoint replies with `welcome`, exactly eight bytes containing one nonzero
connection-local client id. That id is not a durable node identity. It exists
only for this endpoint connection lifetime and for explicit authority such as
geometry leadership.

## Interaction state

Some terminal modes do not alter visible cells but do alter how the same next
semantic input is encoded. A client may therefore send an empty
`interaction_state` frame to observe that coherent mode-directed state without
perturbing the terminal. This is semantic state, not a second snapshot format.

The endpoint replies with one `interaction_state_snapshot` payload of exactly 20
bytes:

| Offset | Bytes | Meaning |
| --- | ---: | --- |
| 0 | 8 | canonical `terminal_revision` at which this state was copied |
| 8 | 4 | interaction boolean flags below |
| 12 | 1 | mouse tracking: `0=off`, `1=x10`, `2=normal`, `3=button_event`, `4=any_event` |
| 13 | 1 | mouse protocol: `0=none`, `1=utf8`, `2=sgr`, `3=sgr_pixel`, `4=urxvt` |
| 14 | 1 | signed `modify_other_keys` state, two's-complement `i8` |
| 15 | 1 | active-screen Kitty keyboard flags, high bit reserved zero |
| 16 | 2 | xterm key-format resource 4 value |
| 18 | 1 | xterm pointer mode, `0..3` |
| 19 | 1 | reserved, zero |

The flags word uses these bits:

| Bit | Meaning |
| ---: | --- |
| 0 | keyboard action mode |
| 1 | auto repeat |
| 2 | newline mode |
| 3 | application cursor keys |
| 4 | application keypad |
| 5 | Meta sends Escape |
| 6 | report key-up |
| 7 | bracketed paste |
| 8 | focus reporting |
| 9 | termios signals |
| 10 | alternate scroll |
| 11 | paste events |
| 12 | in-band resize notifications |

Bits 13..31 are reserved and must be zero.

## Observation model

Observation is request-driven. A client has at most one outstanding `observe`.
There is no server-side stream queue per observer, so a slow observer never
paces the PTY or canonical VT.

`observe` has a 12-byte payload:

| Offset | Bytes | Meaning |
| --- | ---: | --- |
| 0 | 8 | `after_revision` |
| 8 | 4 | requested `history_offset` |

`after_revision = 0` always requests an immediate snapshot. Otherwise the
endpoint waits while the current observation revision is less than or equal to
`after_revision`, and responds when a newer revision exists. Asking for a
revision newer than the endpoint currently owns is malformed.

The requested history offset is clamped to canonical retained history. The
snapshot reports the effective history offset actually used.

Each observation is:

1. one `snapshot_begin`;
2. one or more `snapshot_data` transport chunks;
3. one `snapshot_end` with the same observation revision.

The endpoint materializes the coherent snapshot before emitting
`snapshot_begin`. PTY/VT progress may continue while those already-copied bytes
drain to the observer.

### `snapshot_begin`

The payload is exactly 38 bytes:

| Offset | Bytes | Meaning |
| --- | ---: | --- |
| 0 | 8 | observation `revision` |
| 8 | 8 | canonical terminal semantic `terminal_revision` |
| 16 | 4 | effective history offset |
| 20 | 4 | total retained history row count |
| 24 | 4 | history row base |
| 28 | 2 | rows in this snapshot |
| 30 | 2 | canonical columns |
| 32 | 2 | cursor row |
| 34 | 2 | cursor column |
| 36 | 1 | cursor shape |
| 37 | 1 | flags |

Cursor shapes emitted today are `0=block`, `1=underline`, `2=bar`, `3=none`.
Clients should render an unknown future shape with a safe fallback rather than
rejecting an otherwise valid snapshot.

Flag byte bits are:

| Bit | Meaning |
| ---: | --- |
| 0 | cursor visible |
| 1 | cursor blink enabled |
| 2 | alternate screen active |
| 3 | PTY stream closed |
| 4 | child exited |
| 5 | a resize leader exists |
| 6 | this client is the resize leader |
| 7 | reserved, zero |

`snapshot_end` is exactly eight bytes containing the observation revision from
`snapshot_begin`.

## `text_v1`

`text_v1` is the one renderer-complete snapshot representation. It remains
renderer-neutral: there are no font file names, glyph ids, GPU objects, Flutter
types, or window-system concepts on this wire.

The `snapshot_data` payloads are transport chunks only. Concatenate them in
order. The resulting bytes are:

| Offset | Bytes | Meaning |
| --- | ---: | --- |
| 0 | 4 | exact uncompressed body byte count, big-endian `u32` |
| 4 | variable | one zlib/DEFLATE stream containing the complete semantic body |

The declared uncompressed body is bounded to 4 MiB before allocation. The zlib
stream must finish exactly, with no trailing or unconsumed bytes, and inflate to
exactly the declared length. Every snapshot is independently decompressible; no
previous client revision is needed to recover or validate it. Compression is
part of `text_v1`, not an optional or negotiated alternative.

After inflation, the body is a concatenation of self-delimiting records. The
eight-byte record header is:

| Offset | Bytes | Meaning |
| --- | ---: | --- |
| 0 | 1 | record kind: `1=presentation`, `2=row`, `3=hyperlink` |
| 1 | 3 | reserved, zero |
| 4 | 4 | record payload length |

Records may cross `snapshot_data` transport-chunk boundaries because those
boundaries have no semantic meaning. Record order is strict: exactly one
presentation record, exactly `snapshot_begin.rows` row records, then zero or
more hyperlink resolver records. Every nonzero hyperlink id referenced by a row
must resolve exactly once before `snapshot_end`.

### Presentation record

The presentation payload is exactly 1,060 bytes:

| Offset | Bytes | Meaning |
| --- | ---: | --- |
| 0 | 8 | cursor age in nanoseconds |
| 8 | 1 | optional-color presence bits |
| 9 | 1 | presentation flags |
| 10 | 2 | reserved, zero |
| 12 | 1024 | 256 RGBA palette entries, four bytes each |
| 1036 | 4 | default foreground RGBA |
| 1040 | 4 | default background RGBA |
| 1044 | 4 | cursor RGBA slot |
| 1048 | 4 | cursor-text RGBA slot |
| 1052 | 4 | selection-background RGBA slot |
| 1056 | 4 | selection-foreground RGBA slot |

Cursor age uses `0xffffffffffffffff` when no absolute cursor movement timestamp
is tracked. Otherwise it is an age observed on the session node, so it remains
meaningful to a client with a different monotonic clock origin.

Optional-color presence bits are cursor `0x01`, cursor text `0x02`, selection
background `0x04`, and selection foreground `0x08`. Ignore an optional RGBA slot
when its presence bit is clear. Presentation flag `0x01` means DEC reverse-screen
mode; all other presentation flag bits are reserved.

### Row and cell records

A row starts with a four-byte prefix: wrapped, DEC line geometry, and exact
canonical column count. It is followed by exactly one cell entry for each
canonical column.

Each cell has a fixed 35-byte prefix followed by `scalar_count` four-byte Unicode
scalars:

| Offset | Bytes | Meaning |
| --- | ---: | --- |
| 0 | 1 | scalar count, `0..24` |
| 1 | 1 | multicell width, nonzero |
| 2 | 1 | multicell height, nonzero |
| 3 | 1 | multicell x, `< width` |
| 4 | 1 | multicell y, `< height` |
| 5 | 1 | retained OSC 66 subscale numerator, `0..15` |
| 6 | 1 | retained OSC 66 subscale denominator, `0..15` |
| 7 | 1 | retained OSC 66 vertical-align value, `0..3` |
| 8 | 1 | retained OSC 66 horizontal-align value, `0..3` |
| 9 | 1 | semantic-width flag, `0` or `1` |
| 10 | 1 | retained terminal font slot, `0..15` |
| 11 | 1 | baseline: `0=normal`, `1=raised`, `2=lowered` |
| 12 | 1 | underline style: straight/double/curly/dotted/dashed = `0..4` |
| 13 | 1 | protection: `0=none`, `1=iso`, `2=dec` |
| 14 | 2 | style bit mask |
| 16 | 5 | foreground semantic color |
| 21 | 5 | background semantic color |
| 26 | 5 | underline semantic color |
| 31 | 4 | hyperlink id, zero means none |
| 35 | `scalar_count × 4` | Unicode scalars |

Style bits are:

| Bit | Mask | Meaning |
| ---: | ---: | --- |
| 0 | `0x001` | bold |
| 1 | `0x002` | dim |
| 2 | `0x004` | italic |
| 3 | `0x008` | blink |
| 4 | `0x010` | fast blink |
| 5 | `0x020` | reverse cell colors |
| 6 | `0x040` | invisible |
| 7 | `0x080` | underline |
| 8 | `0x100` | strikethrough |

Bits above `0x100` are reserved in `text_v1`.

A semantic color is five bytes: one-byte kind followed by a four-byte value.
Kind `0=default` requires value zero. Kind `1=indexed` permits `0..255`. Kind
`2=rgb` uses the low 24 bits as `0xRRGGBB` and requires the high byte to be zero.

Only the lead coordinate of a grapheme/multicell rectangle carries scalars.
Continuation coordinates (`x != 0` or `y != 0`) carry `scalar_count = 0`.
This prevents duplicate graphemes for wide and OSC 66 cells. Blank lead cells
may also have zero scalars.

### Hyperlink resolver records

The payload is:

| Offset | Bytes | Meaning |
| --- | ---: | --- |
| 0 | 4 | link id, `1..4096` |
| 4 | 2 | URI byte length, `1..2048` |
| 6 | variable | exact URI bytes |

Only hyperlink ids referenced by rows are emitted. Clients should therefore
build the resolver table per snapshot rather than assuming a node-global table.

## Input

Every `input` frame begins with a one-byte input kind:

| Value | Kind |
| ---: | --- |
| 1 | raw bytes |
| 2 | paste |
| 3 | physical key |
| 4 | mouse |
| 5 | focus |

Raw bytes are the explicit exact-byte input lane and are passed unchanged to
the canonical input owner. Paste is semantic input: the remaining payload is exact paste
content, and the canonical VT decides whether bracketed-paste framing applies.

For key, mouse, and focus events, **the client sends physical meaning, not
terminal escape sequences**. The canonical `howl-vt` on the session node owns
application cursor/keypad modes, modifyOtherKeys, Kitty keyboard flags, mouse
protocols, focus reporting, bracketed paste, and every other mode-sensitive
encoding decision.

### Physical key body

After input kind `3`, the fixed key header is 20 bytes followed by exact legacy
bytes and committed UTF-8 text:

| Offset | Bytes | Meaning |
| --- | ---: | --- |
| 0 | 1 | key identity kind: `1=named`, `2=unicode` |
| 1 | 1 | action: `1=press`, `2=repeat`, `3=release` |
| 2 | 1 | modifier bits |
| 3 | 1 | optional-scalar presence bits |
| 4 | 4 | named-key number or Unicode scalar |
| 8 | 4 | shifted Unicode scalar, or zero if absent |
| 12 | 4 | alternate-layout Unicode scalar, or zero if absent |
| 16 | 2 | legacy byte length, `0..511` |
| 18 | 2 | committed UTF-8 byte length, `0..64` |
| 20 | variable | legacy bytes, then committed UTF-8 bytes |

Presence bit `0x01` means the shifted scalar is present; `0x02` means the
alternate-layout scalar is present. When a presence bit is clear, its four-byte
storage must be zero. Unicode values must be valid scalar values, never surrogate
halves.

The 511-byte legacy ceiling is deliberate. The canonical VT owns a 512-byte key
scratch and may need to prepend one ESC for Meta behavior. Do not raise this
limit to 512 in a client.

Modifier bits are shift `0x01`, alt `0x02`, control `0x04`, super `0x08`, hyper
`0x10`, meta `0x20`, caps lock `0x40`, and num lock `0x80`. All eight bits are
defined.

Named-key numbers are frozen as follows:

| Value | Name | Value | Name |
| ---: | --- | ---: | --- |
| 1 | enter | 30 | f2 |
| 2 | tab | 31 | f3 |
| 3 | backspace | 32 | f4 |
| 4 | escape | 33 | f5 |
| 5 | up | 34 | f6 |
| 6 | down | 35 | f7 |
| 7 | left | 36 | f8 |
| 8 | right | 37 | f9 |
| 9 | insert | 38 | f10 |
| 10 | delete | 39 | f11 |
| 11 | home | 40 | f12 |
| 12 | end | 41 | keypad_0 |
| 13 | page_up | 42 | keypad_1 |
| 14 | page_down | 43 | keypad_2 |
| 15 | left_shift | 44 | keypad_3 |
| 16 | right_shift | 45 | keypad_4 |
| 17 | left_control | 46 | keypad_5 |
| 18 | right_control | 47 | keypad_6 |
| 19 | left_alt | 48 | keypad_7 |
| 20 | right_alt | 49 | keypad_8 |
| 21 | left_super | 50 | keypad_9 |
| 22 | right_super | 51 | keypad_decimal |
| 23 | left_hyper | 52 | keypad_add |
| 24 | right_hyper | 53 | keypad_subtract |
| 25 | left_meta | 54 | keypad_multiply |
| 26 | right_meta | 55 | keypad_divide |
| 27 | caps_lock | 56 | keypad_separator |
| 28 | num_lock | 57 | keypad_equal |
| 29 | f1 | 58 | keypad_enter |

`legacy_text` is an exact byte sequence supplied by the platform key system for
legacy terminal behavior. It may contain ESC or C0 bytes and is not UTF-8
validated. `text` is committed text for extended keyboard protocols and must be
valid UTF-8. Either may be empty.

### Mouse body

After input kind `4`, the mouse body is exactly 19 bytes:

| Offset | Bytes | Meaning |
| --- | ---: | --- |
| 0 | 1 | event kind: `1=press`, `2=release`, `3=move`, `4=wheel` |
| 1 | 1 | button: none/left/middle/right/wheel_up/wheel_down = `0..5` |
| 2 | 1 | modifier bits, same as key input |
| 3 | 1 | held-button mask; only low three bits are valid |
| 4 | 4 | signed big-endian `i32` cell row |
| 8 | 2 | cell column |
| 10 | 1 | presence; bit `0x01` means both pixel coordinates are present |
| 11 | 4 | pixel x, or zero when absent |
| 15 | 4 | pixel y, or zero when absent |

Pixel x and y are an all-or-nothing pair. When presence bit `0x01` is clear,
both stored values must be zero. The VT decides whether the active mouse mode
uses cell coordinates, pixel coordinates, or no report at all.

### Focus body

After input kind `5`, exactly one byte follows: `1=focus in`, `2=focus out`.
The VT emits no terminal bytes when focus reporting is disabled by the child.

## Resize leadership

Geometry has one optional explicit leader. Attach does not resize and does not
elect a leader. There is no fallback election and no largest-viewport rule.

`assign_leader` is exactly eight bytes containing a client id. Client id zero
clears leadership. A nonzero id must name an attached client or the endpoint
returns `no_such_client`.

`resize` is exactly four bytes: rows `u16`, then columns `u16`. Only the current
leader may change canonical PTY geometry.
A nonleader receives `not_leader`. If the leader disconnects, leadership becomes
empty and the last canonical geometry remains unchanged.

## Signals and results

`signal` is one byte. Defined values are:

| Value | Signal |
| ---: | --- |
| 1 | hangup |
| 2 | interrupt |
| 3 | resize_notify |
| 9 | kill |
| 15 | terminate |

The session translates these semantic values to the node process-group boundary;
host-specific errno values never cross the wire.

`result` is exactly two bytes: the original frame kind, then a result code:

| Value | Result |
| ---: | --- |
| 0 | ok |
| 1 | malformed |
| 2 | unsupported |
| 3 | no_such_client |
| 4 | not_leader |
| 5 | rejected |

Malformed post-handshake commands are reported as bounded semantic results where
the endpoint can safely retain the connection. Recognized request families that
the endpoint does not implement return `unsupported`. Framing/attach failures
are connection-level failures instead.

## Ownership rules for a client implementation

A client owns framing, connection-local state, UI-local state, and physical input capture.
The session node owns the PTY, canonical VT, terminal protocol modes, process
lifecycle, canonical geometry, and deterministic host consequences. Presentation
code may shape and draw `text_v1`, but must not reinterpret terminal modes or
write PTY escape bytes for typed input.

The minimal client implementation order is:

1. stream-safe 12-byte frame reader/writer and frame-version validation;
2. empty `hello`, `welcome`, and connection-local client identity;
3. request-driven `observe`, bounded zlib inflate, and `text_v1` record decoding;
4. semantic key/mouse/focus plus paste/raw-byte input;
5. explicit resize leadership, history offsets, and interaction-state queries as needed.

Before connecting a new language implementation, run the independent corpus:

```sh
cd howl-session
python3 tools/validate_vectors.py protocol/v1-vectors.json
```

The validator is build-time evidence only. Python is not a Howl runtime
dependency.
