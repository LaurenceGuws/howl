# howl-client

Reusable native Zig client engine for an already-running `howl-session`.

It owns explicit endpoint parsing, portable POSIX connection/handshake, bounded framed I/O,
coherent interaction-state retrieval, canonical semantic client operations including
mouse facts, and one lossless framing-v9 snapshot model with `text_v1`,
`graphics_v2`, and complete bounded `properties_v1` state. Its rich, cached, and
coarse projections retain property bytes with the same snapshot lifetime.
The coarse `view` projection owns one immutable allocation for a revision and
exposes rows, cells, scalars, hyperlinks, images, properties, and presentation facts
in batches. Its backing
layout is private: it is not a C/FFI ABI. These models retain typed terminal facts;
they do not choose JSON, a renderer, a font, a platform UI, or a shell-command
vocabulary.

`search` owns exact client-local matching over one immutable projected row. It
returns stable canonical selection points rather than rendered byte offsets,
handles UTF-8/wide cells, and excludes concealed text. It deliberately does not
invent a cross-soft-wrap search contract; retained-history paging and search UI
remain presentation-client policy.

`selection.Range.textSpan` projects stable endpoints using canonical `RowShape`
facts from the same presented revision. It trims empty row tails and retains one
hard-newline marker without changing the canonical extraction request. It needs
no socket access or allocation during a selection gesture.

Unix sockets remain local endpoint mechanisms. TCP accepts explicit numeric IPv4
peers supplied by the caller; there is no DNS, discovery, authentication, route
selection, or listener policy here. Session lifecycle, PTY/VT semantics, stale
coordinate policy, UI, and rendering are deliberately outside this package.

## Optional native SSH carrier

`Connection.connect` / `connectDiagnosed` remain socket-only. A native embedder
may explicitly call `Connection.connectNative(allocator, io, endpoint,
&diagnostic)` to also accept:

```text
ssh://[user@]host[:port]/absolute/session.sock[?bridge=/absolute/howl-session-bridge]
```

The first implementation is **Linux plus installed OpenSSH**. The authority is
an explicit SSH alias or ASCII hostname (an IPv6 destination may be configured
behind an alias). Paths are literal ASCII without spaces/percent encoding in
this first spelling. Unknown queries, passwords, ambiguous authorities and
control bytes are rejected before launching anything. The bridge defaults to
`howl-session-bridge` on the remote command PATH; an absolute override selects a
staged/matching binary without installing or discovering one.

OpenSSH uses its operator configuration and agent, with BatchMode and strict
host-key verification, no transport PTY, agent/X11 forwarding, local forwards,
background master or local-command hook. Prepared noninteractive authentication
is required; unlocking/enrollment and interactive auth UI are not implemented by
this carrier. The embedder supplies one I/O runtime that outlives its connections. The carrier
never installs/restores process-global signal handlers per route.
Each native connection owns its SSH process group, binary stdio
socket and bounded sleeping stderr drain. Closing/canceling a connection never
signals or terminates the independently managed remote Howl Session. The Howl
handshake has a 15-second total deadline; initial SSH connect is bounded to ten
seconds. Existing open observers remain cancellable long polls rather than idle
connections that time out.

The remote command is exactly one quoted bridge path and one quoted Session
socket, not arbitrary shell source supplied by the caller. stderr never enters
Howl framing; connection-failure diagnostics retain a sanitized 512-byte tail.
No automatic route fallback, input replay, Session creation or remote deployment.
Linux broken socket writes use per-send SIGPIPE suppression, not a process-global
signal handler. Carrier cleanup reaps its child and configured proxy group.

Native connection opening/I/O is still blocking and belongs on an embedder I/O
worker. This API is not a universal asynchronous route registry. The Web byte
entry and socket-only mobile host remain free of subprocess requirements.
A library-backed mobile SSH exec channel could carry the same Howl frames; an
SSH shell/remote PTY feeding a local VT is a different, also valid topology.
A local OS PTY is not required merely because the terminal engine is local.
Actual mobile library wiring, local iOS process/PTY support and broad native GUI
slow-route/reconnect acceptance remain separate work.

`howl-cli` consumes the engine and owns its human/agent command vocabulary plus
compact text/JSON and explicit rich diagnostic formatting. The earlier generic
NDJSON transport experiment was retired after its useful black-box proofs moved
to the CLI/client surfaces.

The measured Flutter/native pressure work is recorded in
`../docs/2026-08-30-native-client-flutter-seam.md`. It earned the opaque coarse native
view, explicit snapshot ownership, portable local socket implementation, and complete
semantic action surface used by the app-private Flutter host. No public FFI ABI or
native byte layout is accepted.

`rich.decodeFrames(allocator, bytes)` decodes exactly one complete bounded framed
snapshot without opening a socket. Native `rich.receive` and this byte-entry API
share one decoder body. The returned rich snapshot owns its memory; the encoded
input is borrowed only for the call. The Web canary uses this seam after bounded
asynchronous assembly, not a second VT or a copied `text_v1` implementation.
