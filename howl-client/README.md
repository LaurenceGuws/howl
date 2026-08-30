# howl-client

Reusable native Zig client engine for an already-running `howl-session`.

It owns local endpoint parsing, connection/handshake, bounded framed I/O, coherent
interaction-state retrieval, canonical non-coordinate client operations, and both
compact and lossless native `text_v1` snapshot models. The models retain typed
terminal facts; they do not choose JSON, a renderer, a font, a platform UI, or a
shell-command vocabulary.

Unix sockets and IPv4 loopback TCP are local endpoint mechanisms. Remote
reachability, authentication, routing, discovery, session lifecycle, PTY/VT
semantics, stale coordinate policy, UI, and rendering are deliberately outside
this package.

`howl-cli` consumes the engine and owns its human/agent command vocabulary and
compact JSON/text formatting. `howl-transport` is retained as an experimental
NDJSON/black-box pressure tool; it formats the engine's rich model rather than
parsing the session wire independently.
