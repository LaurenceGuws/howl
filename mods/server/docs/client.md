# server-client

`server-client` is the boring native client for one explicit Server control stream.
It owns private Unix/numeric-IPv4 TCP transport and both bounded Server control
and terminal interaction clients. `server_client.terminal` supplies terminal actions,
observations, selection, search, image retrieval and consequence handling.

It can inspect status/tree state, create or close Sessions and Instances, and attach
one exact nonzero (server_id, session_id, instance_id). A client keeps a catalog/CRUD
control connection and opens one independent connection for each attachment.
Successful attachment returns the same connected stream in an established terminal
Connection plus the full ready identity. It owns no listener, canonical lifetime,
discovery, authentication or supervision policy.

Target retains endpoint and all three nonzero identities. attach(allocator, target,
diagnostic, interrupt) checks the expected Server incarnation against welcome before
sending attach. Endpoint reuse never selects a new Server implicitly. Fresh control
browsing may learn the current incarnation from an endpoint.

Transport connect, Server welcome and attachment-ready share one 15-second setup
deadline and caller-owned Interrupt. Ready ends native construction; established
observations have no construction deadline. An ordinary control constructor instead
finishes at welcome, so idle control does not retain an expired setup deadline.
Attaching later starts its own bounded admission scope. The Web gateway forwards the
same ready response as the first binary WebSocket message; Wasm uses it directly.
There is no second terminal hello/welcome.

Connection.attachInstance consumes that setup connection on success. Local pre-send
validation and a fully validated typed rejection permit reuse. Framing, transport,
allocation or inconsistent attachment responses retire it; deinit remains safe.
Detaching releases only that attachment. Closing an Instance through Server control
is the explicit lifetime operation.

## Module boundary

Production server_client imports server_protocol and its own private transport
and terminal modules. The client imports no Instance, PTY or Server model. The family's model/service modules
are used only by integration proofs; they are not imported by the client module.
The same package owns the independently selected server_runtime listener/scheduler.

## Terminal interaction

It owns explicit endpoint parsing, portable POSIX connection and attachment, bounded framed I/O,
coherent interaction-state retrieval, canonical semantic client operations including
mouse facts, and one lossless Server v2 snapshot model with frozen `text_v1`,
`graphics_v2`, and complete bounded `properties_v1` state. Its rich, cached, and
coarse projections retain property bytes with the same snapshot lifetime.
Complete packed observation is transport-only: Server v2 `observe_packed`
inflates `text_pack_v1`, reconstructs byte-identical frozen `text_v1`, then reuses
the same rich decoder as compressed/raw complete snapshots. Revision-relative
`RawCache` remains a distinct local/live optimization; there is still one semantic
snapshot model.

The coarse `view` projection owns one immutable allocation for a revision and
exposes rows, cells, scalars, hyperlinks, images, properties, and presentation facts
in batches. It resolves transported style bits, cursor-shape values, DEC row geometry,
and the Kitty image-placeholder scalar into semantic helpers before presentation code
consumes them. Its backing layout is private: it is not a C/FFI ABI. These models retain typed terminal facts;
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
selection, or listener policy in the terminal client. Instance
lifecycle, PTY/VT semantics, stale coordinate policy, UI, and rendering remain
outside that transport-neutral client.


The optional `server_client_render` adapter consumes these transported views through
canonical howl-render. Desktop Local ownership belongs to the consuming host.
