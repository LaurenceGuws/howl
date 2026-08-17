# howl-flutter

Disposable Flutter native pressure client for the frozen `howl-session` v1 wire, currently proven on Linux and Android.

This package is deliberately experimental, not core. It connects directly to an
already-running Howl byte-stream endpoint, negotiates `text_snapshot`, strictly
decodes bounded `text_v1` state in Dart, and paints that semantic state using
Flutter presentation policy. Native TCP is currently restricted to exact IPv4
loopback (`tcp://127.0.0.1:PORT`); a bare path or `unix:/path` remains a temporary
Linux parity oracle. Named physical keys and semantic pointer facts travel through
negotiated `typed_input`; terminal escape encoding remains owned by the canonical
VT. It owns no PTY, VT, shell, network/auth layer, or session lifetime.

Canonical resize is opt-in. With `HOWL_GEOMETRY_LEADER=1`, this client explicitly
assigns its control connection as resize leader before sending rows/columns.
Without that flag, window resizing is presentation-only. Platform text input now
stages active IME composition locally and sends committed Unicode through the
existing committed-text lane. Printable text is never inferred from physical key
labels. The editor keeps two private guard scalars around the platform cursor so
IME document edits become observable without leaking editor state: left/right guard
deletion maps to semantic Backspace/Delete, while committed CR/LF maps to semantic
Enter. Stock Android LatinIME has proved Backspace, Enter, and printable text through
that path; suggestions and autocorrect remain deliberately disabled.

Run a Linux client against a loopback TCP session with:

```sh
HOWL_ENDPOINT=tcp://127.0.0.1:43127 flutter run -d linux
```

For Android, networking remains `dart:io`; there is no Kotlin networking, protocol,
or terminal implementation. The one native leaf is IME visibility. Android uses
Flutter's visible-password/no-suggestions character editor, matching the intent of
Termux's optional `enforce-char-based-input` mode rather than its default `TYPE_NULL`
path. That lets Flutter expose document deletion to Dart while keeping suggestions
out of the terminal editor. `MainActivity` receives one `show` MethodChannel request
and applies the Termux-shaped native sequence to the real `FlutterView`: coalesced
300 ms delay, `requestFocus`, `restartInput`, then `showSoftInput(view, 0)`. All
composition, committed Unicode, and terminal edit semantics remain in Dart.

The Android shell otherwise remains the stock `FlutterActivity` embedding plus the
normal `INTERNET` permission. A Termux-owned `howl-sessiond` on the same phone can
therefore be reached directly over Android loopback:

```sh
flutter build apk --release \
  --dart-define=HOWL_ENDPOINT=tcp://127.0.0.1:43127
```

The same `HOWL_ENDPOINT` define works for `flutter run` on an Android device. Primary-screen
finger drag is client-local scrollback over the negotiated history window. Live
observation continues on its original long-poll while a third observer is opened
only for nonzero history offsets; history requests use revision zero so they return
immediately, and the viewport anchors by retained row identity while new PTY output
arrives. Returning to offset zero closes that history connection. Touch scroll is
intentionally inert on the alternate screen until the client has explicit canonical
mouse-tracking state; Howl does not guess application mouse policy from screen mode.

Mouse, stylus, and inverted-stylus press/release/move events use the frozen semantic
mouse input family rather than host-generated escape bytes. Flutter maps the centered
painted grid to zero-based cells plus logical-pixel coordinates and refuses pointer
coordinates when the requested grid is clipped by the viewport. Primary, tertiary,
and secondary host buttons map to left, middle, and right; side buttons remain
unrepresented rather than being relabeled. The canonical VT alone decides whether a
semantic event is suppressed or encoded as normal SGR, button-motion SGR, or SGR
pixel coordinates. Pointer wheel remains deliberately unforwarded while touch
scrollback and application wheel ownership cannot be distinguished without guessing.

During transport parity, the older Unix oracle remains available on Linux as either a
bare path or `unix:/path/to/session.sock`. `HOWL_SOCKET` is accepted only as a
temporary legacy launch fallback while that oracle remains.

Protocol tests consume the tracked language-neutral vectors from
`../howl-session/protocol/v1-vectors.json`.
