# howl CLI

`howl` is a boring headless client for one concrete Howl Instance interaction stream. It renders no pixels and owns no PTY, VT, Instance, Session, Server, discovery, or supervision.

Current commands live under `howl instance ...` and expose snapshots, interaction state, semantic input, resize, focus, and signals over explicit Unix or numeric-IPv4 TCP endpoints. Higher-level Server/Session CRUD will return only when that orchestration layer has a truthful Server -> Sessions -> Instances model.
