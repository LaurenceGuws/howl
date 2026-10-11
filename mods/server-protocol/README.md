# Server protocols

The zero-dependency server_protocol module owns bounded encoding and decoding
for Server -> Sessions -> Instances control: status/tree observation, Session
and Instance CRUD, and exact Instance attach. Session create carries a logical
name; process launch policy belongs to Instance create.

After attach succeeds, the same ordered stream speaks this package's terminal
wire, exposed as server_protocol.terminal. This package owns no transport, listener, runtime, terminal grid,
authentication or lifecycle. Server and server-client use this exact module.

[Terminal wire reference](docs/terminal-wire.md) and its language-neutral vectors
are owned here. The wire formats remain unchanged by this ownership move.
