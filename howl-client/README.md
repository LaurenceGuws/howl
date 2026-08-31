# howl-client

Reusable native Zig client engine for an already-running `howl-session`.

It owns local endpoint parsing, portable POSIX connection/handshake, bounded framed I/O,
coherent interaction-state retrieval, canonical semantic client operations including
mouse facts, and one lossless native `text_v1` snapshot model with compact and coarse
projections. The
coarse `view` projection owns one immutable allocation for a revision and exposes
rows, cells, scalars, hyperlinks, and presentation facts in batches. Its backing
layout is private: it is not a C/FFI ABI. These models retain typed terminal facts;
they do not choose JSON, a renderer, a font, a platform UI, or a shell-command
vocabulary.

Unix sockets and IPv4 loopback TCP are local endpoint mechanisms. Remote
reachability, authentication, routing, discovery, session lifecycle, PTY/VT
semantics, stale coordinate policy, UI, and rendering are deliberately outside
this package.

`howl-cli` consumes the engine and owns its human/agent command vocabulary plus
compact text/JSON and explicit rich diagnostic formatting. The earlier generic
NDJSON transport experiment was retired after its useful black-box proofs moved
to the CLI/client surfaces.

The measured Flutter/native pressure work is recorded in
`../docs/2026-08-30-native-client-flutter-seam.md`. It earned the opaque coarse native
view, explicit snapshot ownership, portable local socket implementation, and complete
semantic action surface used by the app-private Flutter host. No public FFI ABI or
native byte layout is accepted.
