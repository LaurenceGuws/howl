# howl CLI

`howl` is the machine-friendly native command surface for Howl. It owns no PTY, VT, Instance, Session, Server, listener, discovery, authentication, or supervision.

Two command families stay deliberately distinct:

- `howl instance ...` talks directly to one explicit HWLS Instance stream for snapshots, state, input, resize, focus, and signals.
- `howl server run LISTEN` hosts one foreground Server runtime and its single control listener.
- `howl server ...` client commands talk to one explicit Server control stream for status/tree inspection and exact Session/Instance lifecycle CRUD.

Server orchestration preserves the ownership tree. `server session create` creates only logical Session identity. `server instance create` is the only command that accepts shell/command/cwd/geometry. IDs and revisions are emitted as decimal JSON strings where they may exceed JavaScript's exact integer range.

The Server runtime owns no terminal geometry or presentation layout. `server instance create`
selects the initial canonical geometry for that Instance; later HWLS resize mutates that same
Instance geometry. Multiple Instances may be shown on one app surface, but panes/splits and
surface composition remain client-side.
