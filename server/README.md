# server

`server` is optional orchestration above the Howl terminal module family. It is not
Howl's identity and it is not required by `howl-vt`, `howl-pty`, `howl-instance`,
or a local terminal host.

The ownership tree is exact:

```text
Server
└── Sessions
    └── Instances
```

An Instance is one concrete Howl terminal occurrence. A Session is not an Instance:
it is a logical orchestration lifetime that may contain zero or more Instances. Creating
a Session never launches a shell. Shell, command, cwd and terminal geometry belong only
to explicit Instance creation.

The Server model and control service remain listener-free. A server-managed Instance owns an optional `howl_instance_service` interaction service beside its concrete Instance; Server routes already-connected streams by exact Session + Instance identity into that service.

`server_runtime` is the optional foreground host around those modules. It owns exactly one Server control listener and cooperative scheduling across control plus all Instance services. It owns no terminal grid, pane/split layout, renderer state, authentication, discovery, persistence or service-supervision policy.

## Control protocol

`server_protocol` is the experimental bounded orchestration wire. Its vocabulary
mirrors the ownership tree instead of collapsing it:

- `create_session(name)` creates only logical Session identity;
- `create_instance(session_id, launch...)` creates one concrete terminal Instance;
- `close_session(session_id)` and `close_instance(session_id, instance_id)` are distinct;
- `attach_instance(session_id, instance_id)` selects one exact Instance interaction stream;
- `tree_snapshot` serializes Server -> Sessions -> Instances with retained Instance state.

The protocol owns no listener or transport policy. After a successful Instance attach,
HWLS remains the unchanged Instance interaction protocol on that ordered stream.

## Control service

`server_service` is a listener-free adopted-stream service around one borrowed
`Server`. It owns bounded control-client buffers and long-poll state, decodes
`server_protocol`, performs exact CRUD through the Server model, serializes the
read-only tree, and transfers an exact `(session_id, instance_id)` stream into
that Instance's HWLS service. It does not turn Instances itself: a higher runtime
must schedule control and Instance service turns independently.

The service borrows both Server and inherited environment lifetime. It creates no
listener, endpoint address, daemon, child process, authentication policy, route,
or supervision policy. On failed stream adoption the caller retains the fd; on
successful Instance attach the fd changes ownership directly from control service
to Instance service with no byte proxy.

## Runtime

`server_runtime` owns one listener, one Server model, one control service, and the
bounded scheduling loop for every Instance interaction service in that process.
The listener accepts only Server control connections. Exact Instance attach transfers
the accepted stream directly into that Instance's HWLS service; no per-Instance
listener or byte proxy exists.

The scheduler separates readiness from service work. Running Instances with no clients,
pending writes or terminal deadlines contribute only their PTY fd to one aggregate poll
alongside the Server listener. PTY output/exit and new Server connections therefore wake
the runtime immediately without periodic per-Instance turns. Control clients and
Instances with client/timer/write work use the bounded rotating service lane. Retained
exited Instances remain attachable but disappear from all scheduler work once their PTY,
clients, terminal timers, consequences and publication work are quiescent; a later exact
attach makes that Instance serviceable again. The aggregate dormant wait has only a
bounded housekeeping timeout; it is not an input/output latency bound.

This is intentionally replaceable runtime scheduling policy, not Session or Instance semantics.

The runtime owns no terminal geometry. Each Instance keeps one canonical rows/columns
and cell-pixel lattice in its VT/PTy lifetime. A graphical client may compose multiple
Instances onto one surface and choose their individual geometries, but that pane/layout
composition remains entirely client-side.
