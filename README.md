# Howl

Howl is a small native terminal **module family**. It is not a tmux identity and it
is not inherently a Server. The smallest useful embedding is `howl-vt` by itself;
a local shell may compose PTY + VT through `howl-instance` without importing or
knowing about Session or Server machinery.

## Ownership model

The terminal layers are deliberately narrow:

| Package | Owns |
| --- | --- |
| `howl-vt` | terminal parsing, semantic state, history, images, input encoding, replies, consequences |
| `howl-pty` | Linux PTY transport and child-process lifecycle |
| `howl-instance` | optional batteries-included composition of **one concrete terminal occurrence**: one PTY + one canonical VT + explicit geometry |
| `howl-text` | font metrics, fallback, shaping, source clusters, glyph lookup, bounded alpha rasterization |

An **Instance** is the terminal lifetime. It owns the authoritative rows/columns and
cell-pixel geometry for that PTY/VT. It is not a Session, listener, daemon, Server,
window, pane, or product identity.

Observers and clients may disconnect, stall, or disappear without pacing canonical
Instance progress. Attaching a client never silently resizes an Instance; geometry is
an explicit Instance mutation.

## Optional orchestration

Persistent multi-Instance orchestration is a separate optional layer:

```text
Server
├── Session "work"
│   ├── Instance 1  exited
│   └── Instance 2  running
└── Session "logs"
    └── Instance 1  running
```

A **Session** is lifecycle identity/labeling for an Instance lineage. It owns no PTY,
VT, HWLS service, geometry, renderer, pane, split, or surface layout. Session creation
never launches a shell.

A hosted **Server runtime** owns exactly one control listener, the Server tree, and
bounded scheduling across all Instance services. It starts with zero Sessions and zero
Instances. It owns no terminal grid or presentation composition. Graphical clients may
place several Instances on one surface, but that layout remains client-side and only
results in explicit per-Instance geometry mutations.

There is no per-Instance listener in the Server runtime. A Server client requests an
exact `(session_id, instance_id)` and the accepted control stream is transferred into
that Instance's ordinary HWLS service. After `attach_ready`, the same byte stream speaks
unchanged HWLS. No Server-side byte proxy sits in the terminal path.

Transport reachability, authentication, discovery, public routing and service
supervision remain outside Howl.

## Native clients

`howl-client` is the reusable UI-neutral client for one explicit Instance HWLS stream.
It owns bounded framed I/O, snapshot/state/action/search/selection/image/consequence
clients and shared Unix/numeric-IPv4 transport mechanics. It owns no terminal or
orchestration lifetime.

`server-client` is the corresponding native client for one explicit Server control
stream. It owns typed Server status/tree decoding, Session/Instance CRUD and exact
Instance attach.

`howl-cli` builds the machine-friendly `howl` executable with two deliberately distinct
command families:

```text
howl instance ...   # interaction with one Instance, direct or exact Server-routed
howl server ...     # Server tree / Session / Instance orchestration
```

The CLI is a frontend/composition root, not an architectural owner. Instance commands
share one target grammar: a direct HWLS endpoint or
`--server SERVER_ENDPOINT SERVER_ID SESSION_ID INSTANCE_ID`. The latter performs exact Server
attach only to obtain the Instance stream; snapshot/input/resize semantics remain
Instance-owned. In particular, `howl server session create` creates only logical Session identity, while
`howl server instance create` is the only orchestration command that accepts
shell/command/cwd/geometry.

## Maintained canaries

Flutter, Web, the native Vulkan Host and Odin clients are pressure canaries rather than
compatibility surfaces. They may iterate rapidly, but none may duplicate terminal
semantics or move presentation policy into VT/PTY/Instance/Server.

Flutter currently exercises both direct HWLS and Server-selected Instance routes. Its
small app shell may persist explicit labelled Server endpoints, but that is application
configuration, not Server discovery. The Vulkan Host and Odin desktop client also expose
explicit Server-selected Instance startup while preserving their direct/local performance
lanes; after attach their existing render/input workers remain ordinary HWLS clients.

The Web wire/renderer/gateway proofs remain maintained. The browser gateway reaches an
exact Server-selected Instance through `server-client` attach and then carries unchanged
HWLS over WebSocket; it does not require or recreate a per-Instance listener.

## Build

Howl uses the exact Zig version in `.zigversion`, supplied by Fleet on `PATH`:

```sh
test "$(zig version)" = "$(cat .zigversion)"
zig build check
zig build test
zig build protocol
zig build audit
```

Do not create a project-local Zig symlink or toolchain alias. Fleet owns the installed
compiler; the repository owns only the version pin.

Each tracked core module owns its own `build.zig` and proofs. Root gates curate the
local core and frozen wire vectors. Python 3 is used only as build-time evidence for
language-neutral protocol fixtures; it is not a Howl runtime dependency.

For the detailed current ownership rules, read `project_design.yml`,
`project_rules.yml`, and `project_source_map.yml`.
