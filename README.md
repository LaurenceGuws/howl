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
| `howl-pty` | platform process-terminal transport and child lifecycle: Linux PTY or Windows ConPTY |
| `howl-instance` | optional batteries-included composition of **one concrete terminal occurrence**: one platform process-terminal transport + one canonical VT + explicit geometry |
| `howl-text` | font metrics, fallback, shaping, source clusters, glyph lookup, bounded alpha rasterization |

An **Instance** is the terminal lifetime. It owns the authoritative rows/columns and
cell-pixel geometry for that process-terminal/VT pair. It is not a Session, listener, daemon, Server,
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

`howl-client` provides the reusable UI-neutral `howl_client` module for one explicit
Instance HWLS stream. That ordinary client owns bounded framed I/O,
snapshot/state/action/search/selection/image/consequence clients and shared
Unix/numeric-IPv4 transport mechanics, with no terminal or orchestration lifetime. The
separate optional `howl_local` module owns one listener-free desktop Local Instance
backed by Linux PTY or Windows ConPTY; importing the ordinary client never opts a
consumer into process ownership.

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

Flutter currently exercises desktop Local, direct HWLS, and Server-selected Instance
routes. Linux and Windows Local own one listener-free in-process Instance; Android and
iOS remain client-only. Its small app shell may persist explicit labelled Server
endpoints, but that is application configuration, not Server discovery. Odin also
exposes explicit Server-selected Instance startup while preserving its Local/direct
lanes; after attach its existing render/input workers remain ordinary HWLS clients.

howl-app is the direct Zig/SDL daily-shell replacement beside Odin. Its first
Local path borrows immutable canonical Render leases without the internal C ABI;
Odin remains the daily app until the shell and attachment capabilities are qualified.

The Vulkan Host is deliberately different: it is the native direct-embed performance
canary only. It owns one in-process Instance and projects canonical VT observation
directly through text/render/Vulkan/Wayland. Its build disables transported client
render sources and contains no howl-client, server-client, endpoint, Session, Server,
or HWLS route.

The Web wire/renderer/gateway proofs remain maintained. The browser gateway reaches an
exact Server-selected Instance through `server-client` attach and then carries unchanged
HWLS over WebSocket; it does not require or recreate a per-Instance listener.

### Current consequence consumers

`howl-client` provides the generic HWLS consequence client, but host policy is opt-in.
Current maintained source has one explicit product policy owner:

| Surface | Consequence authority today |
| --- | --- |
| Odin desktop | claims explicit authority; surfaces bell/attention notifications as modest window attention, replies empty/default/dark/screen-cell facts to required queries, and consumes the remaining host-neutral occurrences |
| Flutter | no explicit authority; Instance deterministic headless policy applies |
| Web | no explicit authority; Instance deterministic headless policy applies |
| Vulkan Host | no explicit authority; Instance deterministic headless policy applies |
| CLI | exposes no product host policy; Instance deterministic headless policy applies |

Direct `howl-vt` embedders are outside that Instance fallback and must choose their own
policy if they want host side effects or replies.

## VT protocol coverage

`protocol_coverage.yml` is the pinned behavior census, not a loose TODO list. Each
reference behavior records Howl support (`full`, `partial`, `missing`, or
`unassessed`), disposition (`active`, `delegated`, `deferred`, `excluded`, or
`none`), ownership, source symbol, proof, and a residual/rationale when behavior is
intentionally incomplete or divergent.

The companion Nushell query surface keeps the 4k-line catalogue inspectable:

```sh
nu --no-config-file -c 'source protocol_coverage.nu; protocol summary'
nu --no-config-file -c 'source protocol_coverage.nu; protocol gaps'
nu --no-config-file -c 'source protocol_coverage.nu; protocol query --disposition deferred'
nu --no-config-file -c 'source protocol_coverage.nu; protocol show REFERENCE_ID'
```

`protocol gaps` is the actionable view: a classified partial/missing record is not a
gap when it is deliberately delegated, deferred, or excluded with an owned reason.
`zig build protocol` validates the catalogue. It is deliberately separate from the
portable core `zig build check` gate so a core builder does not need Nushell merely to
compile and audit Howl.

## Build

Howl uses the exact Zig version in `.zigversion`, supplied by Fleet on `PATH`. The root check gate also requires `zig-audit` with stable ruleset 3 or newer:

```sh
test "$(zig version)" = "$(cat .zigversion)"
zig build check
zig build test
zig build protocol
zig build audit
```

Do not create a project-local Zig symlink or toolchain alias. Fleet owns the installed
compiler; the repository owns only the version pin.

`VERSION` is the current workspace release marker. The Howl project audit requires all
current `build.zig.zon` manifests, `project_version_scope.yml`, the native CLI,
Odin app metadata, and Flutter's base version to agree with it; versioned embedding
examples remain deliberately frozen at their named historical contract.

`.zig-audit.json` uses schema 2 and ruleset 3 over the accepted core source, its build
glue, and the VT unit-proof root. Intentional sharp constructs are acknowledged beside
the exact source with a reason. Experimental clients remain outside the root core audit
until promoted; their package-local gates still own their proofs.

Each maintained Zig package owns its complete checks, tests and public consumer
graph. Root `check` and `test` depend directly on those child steps, including the
native bridges, CLI/Server, Vulkan host, versioned VT example, and Web's nested
text/render/gateway proofs. `test` includes VT simulation and protocol validation.
Live desktop/browser sessions and benchmarks retain explicit opt-in entrypoints.

Targeted child steps are available at the root, for example
`zig build howl_odin:test` or `zig build howl_web:render-check`. Web canaries retain
their explicit Wasm target; native packages receive the root target and optimization.
Root execution requires the children's ordinary tools and native libraries, including
Node, Python, Wayland's pinned scanner, SPIR-V tools, FreeType and HarfBuzz.

The repository root is also the distribution boundary for downstream Zig consumers.
It forwards the exact child module objects and installable artifacts; it does not
recreate their source/module graphs. For example:

```zig
const howl = b.dependency("howl", .{
    .target = target,
    .optimize = optimize,
});
root.addImport("howl_instance", howl.module("howl_instance"));
root.addImport("howl_vt", howl.module("howl_vt"));
root.addImport("howl_render", howl.module("howl_render"));
root.addImport("howl_text", howl.module("howl_text"));
```

The public child names are retained, including `howl_local`, the Instance wire/service
modules, Server modules, client transport, Vulkan and Wayland. Native binaries,
bridge libraries/objects and Web Wasm artifacts are available through
`howl.artifact(name)`. Importing a module does not link unrelated public modules.
The distribution root forwards `howl_render` in its direct-VT configuration, without
transported `howl-client` source adapters. Consumers that explicitly need Render's
transported-client facade depend on the `howl-render` child package with
`client_sources=true` instead.
Consumers should pin an immutable repository tag or commit.

`zig build consumer` runs the separate package in `test/consumer`, which imports
the distribution root, resolves its artifacts and proves compatible VT/Instance
and text/renderer type identities. Root checks and tests include this proof.

For the detailed current ownership rules, read `project_design.yml`,
`project_rules.yml`, and `project_source_map.yml`.
