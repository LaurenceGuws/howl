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

The module remains listener-free. A server-managed Instance owns an optional `howl_instance_service` interaction service beside its concrete Instance; Server routes already-connected streams by exact Session + Instance identity into that service. Transport acceptance, addresses, discovery, authentication and service supervision remain outside this ownership layer.

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
