# howl-server

`howl-server` owns one bounded collection of canonical Howl Sessions. It is the
collection/lifecycle authority beneath operator and graphical management clients;
it does not own terminal semantics, rendering, authentication, routing, or service
supervision.

`howl server run RUNTIME_DIR` enters this owner in the foreground with zero
Sessions. The process holds an exclusive runtime lock, publishes one HWLM manager
endpoint, remains healthy with an empty collection, and admits at most sixteen
retained Session records. A supervisor may restart the process; Howl does not
daemonize itself or promise Session persistence across a server restart.

## Manager protocol

`howl_server_protocol` owns the separate bounded HWLM management wire. HWLM v1
keeps collection lifecycle distinct from the HWLS terminal Session protocol and
defines exact server/session identity, revisioned roster observation,
create/close/attach/shutdown and result vocabulary.

The nonblocking manager listener and authoritative `Registry` implement the live
v1 collection semantics now used by `howl server run`:

- a fresh nonzero `server_id` identifies each owner-process lifetime;
- monotonically allocated nonzero `session_id` values are never reused within
  that lifetime;
- names are bounded unique human labels, not destructive-operation identities;
- dynamic create and exact-id close mutate one coherent roster revision;
- exited Sessions remain retained and attachable until explicit close;
- endpoint failures retain a bounded failed record while releasing the failed
  endpoint and leaving siblings alive;
- roster observation is request-driven long polling, with no unsolicited queue;
- a slow, malformed or disconnected manager client owns only its bounded client
  slot and cannot pace Session service;
- manager shutdown enters a stopping state, refuses new lifecycle mutations,
  gives bounded time for the acknowledgement to drain, then releases Sessions in
  reverse ownership order.

Unix manager sockets are mode 0600. Explicit TCP management listeners bind only
IPv4 loopback. Authentication, encryption, remote routing, service supervision and
discovery remain outside Howl.

Managed attach is direct: HWLM `attach(session_id)` transfers the manager's accepted
stream into the selected Session endpoint, which drains the small `attach_ready`
preface before parsing the unchanged HWLS handshake. There is no manager-side byte
proxy or second terminal protocol. A slow transferred client therefore occupies
only its ordinary bounded Session client slot and cannot pace canonical PTY/VT
progress or the manager.

Each managed Session also retains its explicit per-Session Unix HWLS endpoint under
`RUNTIME_DIR`. That is now an intentional local/debug access route rather than
discovery authority: managed clients use HWLM identity and attach, while an operator
can still target a known local Session endpoint directly. Both routes enter the same
Session client table and terminal truth.
