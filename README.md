# Howl

Howl is a small native terminal **module family**. It is not a tmux identity and it
is not inherently a Server. The smallest useful embedding is `howl-vt` by itself;
a local shell may compose PTY + VT through `howl-instance` without importing or
knowing about Session or Server machinery.

## Repository layout and release snapshot

Reusable packages live in [mods/](mods/README.md); application and runtime
composition lives in [hosts/](hosts/README.md). Core is an ownership/capability
designation, not a synonym for every package in mods.

The Server, Protocol, Client and their Codec, CLI, Web and Odin products now
live in the independently versioned sibling howl-sessions repository. This
repository exports terminal primitives and direct-local hosts only.

Each package owns its build.zig.zon version. [snapshot.json](snapshot.json) records
the exact tested package versions and Zig pin; VERSION names that combination.
The Git revision fixes all source bytes in this one-repository snapshot. Packages
may advance independently; update the changed package and its snapshot entry.
The audit also checks host-advertised versions against their owning packages.
This layout freeze preserves the qualified terminal runtime; it does not promote
experimental hosts or orchestration to stable core.

Independent core source releases use
[`tools/package-release`](tools/package-release) and the
[`release-overlays`](tools/release-overlays/README.md). Each archive contains
one module's tracked source at an exact commit; Render and Instance release
manifests pin their core dependencies by immutable artifact URL and Zig hash.
The sibling package paths in this source checkout are for local development,
not the released dependency contract.

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

## Product boundary and maintained hosts

Howl's VT, PTY, Instance, Text and Render can be embedded without a Session,
Server, socket or observation serialization. Optional Server -> Sessions ->
Instances orchestration is a separately released consumer in howl-sessions;
it depends down on Howl and never changes this local composition.

Local howl-app uses a Zig/SDL frontend with its own Instance and immutable
Render publications. howl-host directly exercises VT observation through
Text, Render, Vulkan and Wayland without client transport or server routing.

The former Flutter source remains in hosts/howl-flutter strictly as an
**inactive, unsupported bring-up reference**. Its native/Dart/iOS build and
installation scripts are not current interfaces. It is absent from the
active build, snapshot and release inventory. The exact audit exception for
its native root is temporary; no other package receives that exemption.

Server-facing native clients, CLI, browser and Odin ownership now live in
howl-sessions, including the extracted terminal observation codec. That
codec consumes VT's pure OSC 52 grammar rather than living inside VT.

The optional [standalone VT native contract](mods/howl-vt/native.md) and
[standalone Render native contract](mods/howl-render/native.md) remain
independently qualified C interfaces for foreign embedders. They do not
introduce Server, socket, GUI scheduling or client ownership into the core.

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

VERSION names the current tested workspace snapshot. Individual package/client
versions are checked against their own manifests and snapshot.json, rather than
being forced to match VERSION. Historical embedding examples remain frozen at
their named contracts.

`.zig-audit.json` uses schema 2 and ruleset 3 over the accepted core source, its build
glue, and the VT unit-proof root. Intentional sharp constructs are acknowledged beside
the exact source with a reason. Every active child has its own required audit;
only the exact old Flutter native copybook root is exempt from active checks.

Each maintained Zig package owns complete checks, tests, audits and its public
consumer graph. The root forwards those child gates and the independent
VT embedding example, howl-app and howl-host. The root does not compile or
install historical Flutter, and does not build any moved Server product.

The root distribution exports exact child-owned Zig module identities,
including VT's pure OSC 52 grammar, and the tested native VT, Instance and
Render artifacts. It does not re-create modules, or export Server client,
protocol, terminal codec, CLI or remote host artifacts. Consumers should
pin immutable module releases and provide matching dependency options
(notably Render's bundled_text=false where sharing with Instance).

The test/consumer package imports the root as a separate distribution
consumer, verifies VT/Instance/Text/Render identity and exercises the
real VT/Instance/Render native C headers and artifacts. It is included in
root check and test; no old Server client ABI is required.
For the detailed current ownership rules, read `project_design.yml`,
`project_rules.yml`, and `project_source_map.yml`.
