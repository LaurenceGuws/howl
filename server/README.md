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

This first cut is deliberately module-only. It owns no listener, daemon, discovery,
authentication, client protocol or service-supervision policy. Those layers must be
earned on top of this ownership model rather than smuggled into an Instance.
