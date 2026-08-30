# howl-client

Reusable native Zig client mechanics for an already-running `howl-session`.

It owns local endpoint parsing, connection/handshake, bounded framed I/O, and the
client identity/features negotiated by the frozen session wire. Unix sockets and
IPv4 loopback TCP are local endpoint mechanisms. Remote reachability,
authentication, routing, discovery, session lifecycle, PTY/VT semantics, UI, and
rendering are deliberately outside this package.

This package exists so native clients such as `howl-cli` and experimental
protocol pressure tools do not each grow their own socket/framing implementation.
