# server-client

`server-client` is the boring native client for one explicit Server control stream.
It owns private Unix/numeric-IPv4 TCP transport and both bounded Server control
and terminal interaction clients. `server_client.terminal` supplies terminal actions,
observations, selection, search, image retrieval and consequence handling.

It can inspect status/tree state, create or close Sessions, create or close Instances,
and attach one exact `(server_id, session_id, instance_id)`. Successful attach consumes the Server
control connection and returns the same connected byte stream after `attach_ready`;
the caller may then hand that stream to `server_client.terminal` for HWLS interaction. There is no
proxy and this package owns no listener, Server/Session/Instance lifetime, discovery,
authentication, or supervision policy.

`Target` retains endpoint plus all three nonzero identities. `attach(allocator,
target, diagnostic, interrupt)` compares the expected Server incarnation with the
welcome **before sending attach**, returning `StaleServerIncarnation` on mismatch.
Every observer/control/reconnect lane must retain the same selected target; endpoint
reuse never implicitly selects a new Server. Fresh control browsing/CRUD may still
learn the current identity from an endpoint.

Transport connect, Server welcome, attach, and the ordinary HWLS welcome share one
15-second deadline and caller-owned Interrupt. Server welcome retains that scope;
choosing a control operation instead completes Server-only construction and permits
indefinite established observations. Attaching later on an established control
connection starts a fresh bounded attach/HWLS scope. HWLS alone completes native
Instance construction. The protocol-blind Web gateway ends its native scope at attach
because the browser owns HWLS construction.

`Connection.attachInstance(expected_server_id, identity)` consumes on success.
Only local pre-send validation and a fully validated typed rejection permit reuse.
Framing, transport, allocation, or inconsistent attach responses retire and close the
connection; further operations return `ConnectionRetired` and `deinit` remains safe.
A create-instance success for a different Session also retires the connection.

## Package boundary

Production server_client imports server_protocol and its own private transport
and terminal modules. The client imports no Instance, PTY or Server model. The model/service dependency in this package's build
is used only by integration proofs; it is not imported by the client module.
The server listener/scheduler is hosted separately under hosts/server.

## Terminal interaction

It owns explicit endpoint parsing, portable POSIX connection/handshake, bounded framed I/O,
coherent interaction-state retrieval, canonical semantic client operations including
mouse facts, and one lossless framing-v10 snapshot model with frozen `text_v1`,
`graphics_v2`, and complete bounded `properties_v1` state. Its rich, cached, and
coarse projections retain property bytes with the same snapshot lifetime.
Complete packed observation is transport-only: framing-v10 `observe_packed`
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
