# Reusable modules

A module is machinery an embedder can consume without adopting a product's
entrypoint, window, listener, or application lifetime. A Zig package may expose
several modules. Being here does not make a package terminal core.

| Packages | Ownership |
| --- | --- |
| howl-vt, howl-pty, howl-instance, howl-text | accepted terminal foundations |
| howl-render | shared terminal-to-frame presentation machinery |
| server-client | Server control and terminal clients with private transport |
| server-protocol | pure shared Server control and terminal wire |
| server | optional Server/Session model and adopted control/terminal streams above Instance |
| howl-vk, howl-wayland | experimental graphics/platform libraries |

The Server model/service is reusable optional orchestration. Its wire is a
separate zero-dependency package, so clients can import it without the Server
runtime. Listener and scheduling policy belongs to [hosts/server](../hosts/server/README.md).
The server-client integration proofs use the model/service as fixtures;
production server-client imports only the protocol and transport modules.

Each package owns its public build exports, version, dependencies and proofs.
Package versions are recorded in the root [snapshot](../snapshot.json).
No reusable module package may depend upward on a hosts package.
