# howl-server

`howl-server` owns one bounded collection of canonical Howl Sessions. It is the
collection/lifecycle authority beneath operator and graphical management clients;
it does not own terminal semantics, rendering, authentication, routing, or service
supervision.

The initial extracted cut intentionally preserves the existing static
`howl server RUNTIME_DIR NAME...` behavior unchanged while moving collection
ownership out of the CLI package. Dynamic lifecycle and the manager protocol are
later slices and must be proven at this boundary rather than reconstructed by
filesystem or process discovery.

## Manager protocol

`howl_server_protocol` owns the separate bounded HWLM management wire. HWLM v1
keeps collection lifecycle distinct from the HWLS terminal Session protocol and
defines exact server/session identity, roster, create/close/attach/shutdown and
result vocabulary. The current runtime has not adopted those operations yet.

`Registry` now owns the dynamic bounded collection model behind the future
manager: non-reused session ids, retained exited/failed records, exact close by
id, roster revisions, deterministic roster projection, and Session endpoint
cleanup. The foreground CLI entrypoint still uses the earlier static loop until
the manager listener is connected in the next slice.

The nonblocking manager listener now exercises HWLM against the authoritative
registry, including independent roster observation/control clients, dynamic
create/close, revision wakeups and the stopping state. The public `howl server`
entrypoint is switched to this owner in the following checkpoint.
