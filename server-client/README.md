# server-client

`server-client` is the boring native client for one explicit Server control stream.
It shares `client-transport` for Unix/numeric-IPv4 TCP carriage and speaks only the
bounded `server_protocol` orchestration wire.

It can inspect status/tree state, create or close Sessions, create or close Instances,
and attach one exact `(server_id, session_id, instance_id)`. Successful attach consumes the Server
control connection and returns the same connected byte stream after `attach_ready`;
the caller may then hand that stream to the ordinary HWLS Instance client. There is no
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
