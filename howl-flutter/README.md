# howl-flutter

Disposable Flutter/Linux pressure client for the frozen `howl-session` v1 wire.

This package is deliberately experimental, not core. It connects directly to an
already-running Unix socket, negotiates `text_snapshot`, strictly decodes bounded
`text_v1` state in Dart, and paints that semantic state using Flutter presentation
policy. Named physical keys travel through negotiated `typed_input`; terminal
escape encoding remains owned by the canonical VT. It owns no PTY, VT, shell,
network/auth layer, or session lifetime.

Canonical resize is opt-in. With `HOWL_GEOMETRY_LEADER=1`, this client explicitly
assigns its control connection as resize leader before sending rows/columns.
Without that flag, window resizing is presentation-only. Platform text input now
stages active IME composition locally and sends only committed Unicode text through
the existing committed-text input lane. Printable text is never inferred from
physical key labels. Soft-keyboard editing actions such as Enter, Backspace, Delete,
suggestions, and autocorrect remain deliberately unclaimed until Android pressure
proves their semantics.

Run against a local session with:

```sh
HOWL_SOCKET=/path/to/session.sock flutter run -d linux
```

Protocol tests consume the tracked language-neutral vectors from
`../howl-session/protocol/v1-vectors.json`.
