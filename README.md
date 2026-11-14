# Howl

Howl is a small native terminal **module family**. It is not a tmux identity and it
is not inherently a Server. The smallest useful embedding is `howl-vt` by itself;
a local shell composes PTY + VT directly and may borrow VT-owned Text output
without importing or knowing about Session or Server machinery.

## Repository layout and release snapshot

The four maintained packages are direct children of this repository:
`howl-vt`, `howl-pty`, `howl-text`, and `howl-app`.
Each owns its own build, version, proofs and release boundary.
Core is an ownership/capability designation, not a directory name.

The Server, Protocol, Client and their Codec, CLI, Web and Odin products now
live in the independently versioned sibling howl-sessions repository. This
repository exports terminal primitives and the direct-local `howl-app`.

Each package owns its build.zig.zon version. [snapshot.json](snapshot.json) records
the exact tested package versions and Zig pin; VERSION names that combination.
The Git revision fixes all source bytes in this one-repository snapshot. Packages
may advance independently; update the changed package and its snapshot entry.
The audit also checks host-advertised versions against their owning packages.
The root composes their qualified gates without changing package ownership.

Independent core source releases use
[`tools/package-release`](tools/package-release). Each archive contains one
module's tracked source at an exact commit. Published historical Instance and
Render source/ABI artifacts remain recoverable through their immutable Git
releases; they are not maintained products in this snapshot.

## Ownership model

The terminal layers are deliberately narrow:

| Package | Owns |
| --- | --- |
| `howl-vt` | terminal parsing, semantic state, history, images, input encoding, replies, consequences |
| `howl-pty` | platform process-terminal transport and child lifecycle: Linux PTY or Windows ConPTY |
| `howl-text` | font metrics, fallback, shaping, source clusters, glyph lookup, bounded alpha rasterization |
| `howl-app` | local SDL shell, one PTY/VT per pane, direct VT/Text output, host scheduling and presentation |

A host owns its terminal's PTY lifetime, mutable VT, geometry and consequences.
VT owns canonical semantic state and an optional direct-output factory that borrows
Text only when the caller selects it. The host owns GPU resources, UI, window and
platform lifecycle. Observers cannot pace canonical progress or silently resize VT.

## Product boundary and maintained hosts

Howl's VT, PTY and Text can be embedded without a Session, Server, socket or
observation serialization. Optional Server/Session orchestration is a separate
product in howl-sessions and never changes this local composition.

Local howl-app uses a Zig/SDL frontend with app-owned PTY, canonical VT and
Text, borrowing VT's direct output for checked immutable drawing cuts.

Server-facing native clients, CLI, browser and Odin ownership now live in
howl-sessions, including the extracted terminal observation codec. That
codec consumes VT's pure OSC 52 grammar rather than living inside VT.

The optional [standalone VT native contract](howl-vt/native.md) remains
independently qualified for C embedders. It introduces no Server, socket,
GUI scheduling or client ownership into the core.

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
VT embedding example and howl-app. The root does not compile or
install historical Flutter, and does not build any moved Server product.

The root distribution exports exact child-owned Zig module identities,
including VT's pure OSC 52 grammar and standalone VT native artifact.
It does not re-create the optional VT/Text output owner as a public root
module or export Server client, protocol, terminal codec, CLI or remote host
artifacts. Consumers should pin immutable module releases.

The test/consumer package imports the root as a separate distribution
consumer, verifies VT/PTY/Text identity and exercises the real VT native C
header and artifact. Independent VT/Text direct-output owner, shared-store
and glyph-cache proofs run in the root check/test graph.
For the detailed current ownership rules, read `project_design.yml`,
`project_rules.yml`, and `project_source_map.yml`.
