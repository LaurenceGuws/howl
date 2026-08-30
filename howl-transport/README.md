# howl-transport

Experimental AX transport for existing Howl sessions.

This leaf does not define terminal semantics and does not provide a smaller terminal API. It translates the frozen `howl-session` wire into agent-friendly structured records without discarding canonical state.

The endpoint is explicit. Unix paths and numeric `tcp://IPV4:PORT` targets are accepted; wildcard and hostname TCP targets are rejected. This experiment owns no discovery, session lifecycle, authentication, Fleet routing, renderer policy, terminal encoding, or terminal-state reconstruction. Fleet callers normally supply an accepted Mesh address.

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
- `interaction_state`
- `input_bytes`
- `paste`
- semantic/physical `key`
- semantic `mouse`
- `focus`
- `assign_leader`
- `resize`
- `signal`

Each mutation emits the existing Howl `result` code. Each terminal observation emits the same complete rich snapshot records as `observe`. `interaction_state` emits the separately negotiated coherent mode state correlated to its canonical `terminal_revision`; it does not infer modes from cells or escape-sequence history.

Keeping a real connection matters: resize leadership is connection-local Howl state. The transport does not emulate that state or hide it behind unrelated one-shot commands.

The black-box composition test drives the existing mode-sensitive session fixture through this surface. It proves normal/application cursor encoding, application keypad, focus reporting, pixel mouse reporting, bracketed binary paste, Kitty press/repeat/release, resize leadership, resize, and signal/child-exit composition without transport-owned terminal rules.

A second black-box observability proof constructs two sessions with byte-for-byte-equivalent visible semantic snapshots but different bracketed-paste mode. `interaction_state` distinguishes them before input, and the same semantic paste then produces the two predicted PTY byte sequences. This protects the AX invariant that an agent must not infer invisible state by perturbing the session.
