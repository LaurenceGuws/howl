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
