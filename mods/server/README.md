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

The Server model and control service remain listener-free. Server owns an optional `server_terminal_service` interaction service beside each concrete Instance; Server routes already-connected streams by exact Session + Instance identity into that service.

The foreground listener/scheduler lives in
[hosts/server](../../hosts/server/README.md), outside this reusable package.

## Shared protocol

[server-protocol](../server-protocol/README.md) owns the bounded control wire and terminal interaction wire.
Client modules import that package directly, without this Server model or a host.

## Control service

`server_service` is a listener-free adopted-stream service around one borrowed
`Server`. It owns bounded control-client buffers and long-poll state, decodes
`server_protocol`, performs exact CRUD through the Server model, serializes the
read-only tree, and transfers an exact `(session_id, instance_id)` stream into
the Server-owned terminal service beside that Instance. It does not turn Instances itself: a higher runtime
must schedule control and Server terminal service turns independently.

The service borrows both Server and inherited environment lifetime. It creates no
listener, endpoint address, daemon, child process, authentication policy, route,
or supervision policy. On failed stream adoption the caller retains the fd; on
successful Instance attach the fd changes ownership directly from control service
to Server terminal service with no byte proxy.

## Ownership and shutdown boundaries

Server is an opaque allocated owner: `*Server` grants mutation and `*const Server`
grants observation. Runtime owns that one allocation directly. Session records remain
typed and internal, allocated lazily behind Server; no wrapper or public storage pointer
lends their ownership. Direct owner methods remain the mutation lane; tree views copy
identity/state and borrow const names.
Session names use the same model/wire contract: 1–64 ASCII bytes from `[A-Za-z0-9._-]`.
Invalid names change neither counts, identity issuance nor tree revision.

The listener/scheduler and its shutdown policy live in
[hosts/server](../../hosts/server/README.md). This package is optional reusable
orchestration above Instance, not part of the terminal core.
