# Server control protocol

The zero-dependency server_protocol module owns bounded encoding and decoding
for Server -> Sessions -> Instances control: status/tree observation, Session
and Instance CRUD, and exact Instance attach. Session create carries a logical
name; process launch policy belongs to Instance create.

After attach succeeds, the same ordered stream speaks the unchanged Instance
HWLS protocol. This package owns no transport, listener, runtime, terminal grid,
authentication or lifecycle. Server and server-client use this exact module.
The protocol source and its embedded tests moved unchanged from the server package.
