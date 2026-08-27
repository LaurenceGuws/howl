# howl-transport

Experimental AX transport for existing Howl sessions.

This leaf does not define terminal semantics and does not provide a smaller terminal API. It translates the frozen `howl-session` wire into agent-friendly structured records without discarding canonical state.

The endpoint is explicit. This experiment owns no discovery, session lifecycle, authentication, Fleet routing, renderer policy, terminal encoding, or terminal-state reconstruction.

## Lossless observation

```text
howl-transport observe unix:/path/to/session.sock [HISTORY_OFFSET]
```

Observation emits ordered JSON records for the complete negotiated `text_v1` snapshot: snapshot/lifecycle/authority envelope, terminal presentation and 256-color palette, every semantic cell and grapheme scalar, DEC/multicell geometry, style/color attributes, hyperlinks, and the closing revision.

## Stateful composition stream

```text
howl-transport stream unix:/path/to/session.sock
```

`stream` keeps exactly one real Howl client connection alive. It first emits the negotiated `welcome` record, including the real connection-local client ID, then accepts one NDJSON request per line. Requests map directly to the existing frozen wire operations:

- `observe`
- `input_bytes`
- `paste`
- semantic/physical `key`
- semantic `mouse`
- `focus`
- `assign_leader`
- `resize`
- `signal`

Each mutation emits the existing Howl `result` code. Each observation emits the same complete rich snapshot records as `observe`.

Keeping a real connection matters: resize leadership is connection-local Howl state. The transport does not emulate that state or hide it behind unrelated one-shot commands.

The black-box composition test drives the existing mode-sensitive session fixture through this surface. It proves normal/application cursor encoding, application keypad, focus reporting, pixel mouse reporting, bracketed binary paste, Kitty press/repeat/release, resize leadership, resize, and signal/child-exit composition without transport-owned terminal rules.
