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
