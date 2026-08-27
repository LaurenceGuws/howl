# howl-transport

Experimental AX transport for existing Howl sessions.

This leaf does not define terminal semantics and does not provide a smaller terminal API. It translates the frozen `howl-session` wire into agent-friendly structured records without discarding canonical state.

Current proof:

```text
howl-transport observe unix:/path/to/session.sock [HISTORY_OFFSET]
```

Observation emits ordered JSON records for the complete negotiated `text_v1` snapshot: snapshot/lifecycle/authority envelope, terminal presentation and 256-color palette, every semantic cell and grapheme scalar, DEC/multicell geometry, style/color attributes, hyperlinks, and the closing revision.

The endpoint is explicit. This experiment owns no discovery, session lifecycle, authentication, Fleet routing, renderer policy, or terminal-state reconstruction.

Next AX question: compose the existing input/focus/mouse/resize/signal state machines through the same transport without adding transport-local semantics.
