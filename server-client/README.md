# server-client

`server-client` is the boring native client for one explicit Server control stream.
It shares `client-transport` for Unix/numeric-IPv4 TCP carriage and speaks only the
bounded `server_protocol` orchestration wire.

It can inspect status/tree state, create or close Sessions, create or close Instances,
and attach one exact `(session_id, instance_id)`. Successful attach consumes the Server
control connection and returns the same connected byte stream after `attach_ready`;
the caller may then hand that stream to the ordinary HWLS Instance client. There is no
proxy and this package owns no listener, Server/Session/Instance lifetime, discovery,
authentication, or supervision policy.
