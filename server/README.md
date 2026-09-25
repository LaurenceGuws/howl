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

`server_runtime` is the optional foreground host around those modules. It owns exactly one Server control listener and cooperative scheduling across control plus all Instance services. The listener may be an owner-local Unix socket, loopback `tcp:PORT`, or one explicit caller-supplied numeric-IPv4 `tcp://ADDRESS:PORT`; the latter is route selection, not discovery or authentication. It owns no terminal grid, pane/split layout, renderer state, authentication, discovery, persistence or service-supervision policy.

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
pending writes or terminal deadlines contribute only their PTY fd to one aggregate poll.
Server control sockets contribute the exact readiness mask requested by `server_service`:
ordinary clients wait for input, queued responses wait for output, and parked tree
observers wait only for disconnect while tree-revision changes wake them explicitly.
The Server listener, those control sockets and dormant PTYs therefore share one aggregate
readiness wait. PTY output/EOF, control input/output and new Server connections wake the
runtime immediately. Leader exit is also reconciled over the bounded live set at the
one-second housekeeping deadline: a quiet descendant can retain the PTY after its
leader exits, so leader exit is not itself a PTY-readiness guarantee. Instances with internal client/timer/
write work use the bounded rotating direct-service lane. Retained
exited Instances remain attachable but disappear from all scheduler work once their PTY,
clients, terminal timers, consequences and publication work are quiescent; a later exact
attach makes that Instance serviceable again. The aggregate dormant wait has only a
bounded housekeeping timeout; it is not an input/output latency bound.

This is intentionally replaceable runtime scheduling policy, not Session or Instance semantics.

TCP accept policy is part of the runtime's interactive carriage contract. Every accepted
TCP stream has `TCP_NODELAY` enabled before it enters `server_service`; option failure
retires that accepted fd instead of silently degrading request/response latency. Exact
Instance attach transfers the same configured fd onward to HWLS. Unix listeners do not
receive TCP policy. Any deployment relay/proxy in front of the Server creates additional
TCP legs and must configure NODELAY on those owned sockets independently; endpoint
configuration cannot reach through a proxy and tune its sockets.

The runtime owns no terminal geometry. Each Instance keeps one canonical rows/columns
and cell-pixel lattice in its VT/PTy lifetime. A graphical client may compose multiple
Instances onto one surface and choose their individual geometries, but that pane/layout
composition remains entirely client-side.

## Ownership and shutdown boundaries

Server is an opaque allocated owner: `*Server` grants mutation and `*const Server`
grants observation. Runtime owns that one allocation directly. Session records remain
typed and internal, allocated lazily behind Server; no wrapper or public storage pointer
lends their ownership. Direct owner methods remain the mutation lane; tree views copy
identity/state and borrow const names.
Session names use the same model/wire contract: 1–64 ASCII bytes from `[A-Za-z0-9._-]`.
Invalid names change neither counts, identity issuance nor tree revision.

Unix listener startup refuses any existing pathname, including stale sockets. Removing
an explicitly identified stale endpoint is the caller's responsibility. The endpoint's
containing directory must be owner-controlled. Cleanup compares socket device/inode
identity before unlinking, so an older listener cannot remove a replacement endpoint;
this is not protection against hostile concurrent renames in a shared directory.

The foreground `howl server run` host handles SIGINT/SIGTERM by publishing only a
termination flag from the signal handler. The bounded runtime loop then returns through
ordinary reverse teardown, including the existing PTY process-group stop/escalation.
The aggregate wait yields on signal interruption; repeated termination signals do not
restart the idle timeout or postpone shutdown until signals stop.
SIGKILL and descendants that deliberately leave the owned group are not covered by
this ordinary shutdown contract. Client response/materialization failures retire that
client; canonical PTY/VT owner failures still propagate.
