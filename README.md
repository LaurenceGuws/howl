# Howl

Howl is a small native Zig terminal family for persistent Unix work shared by humans and agents.

The core idea is simple: **the session lives on the node, not in the client.** One session owns one authoritative PTY and one authoritative VT. Linux and Android nodes can own that work; Linux, Android, agents, and later iOS clients attach to it instead of reconstructing terminal truth from byte streams or duplicating terminal state.

## Core

| Package | Owns |
| --- | --- |
| `howl-vt` | Terminal parsing, semantic state, history, images, input encoding, replies, and protocol consequences |
| `howl-session` | One canonical PTY/VT lifetime, ordered I/O, explicit geometry, signals, child state, and headless policy |
| `howl-pty` | Linux-kernel PTY transport and child-process lifecycle, used directly on Linux and Android |
| `howl-cli` | Bounded non-GUI operator/agent client of the frozen session wire |
| `howl-text` | Standalone pinned package for native font metrics, fallback, shaping, source-cluster identity, glyph lookup, and bounded natural alpha rasterization |

The portable session v1 client contract and language-neutral golden vectors live in `howl-session/README.md`.

The session API is deliberately opaque. Embedders can inspect semantic state and submit input or explicit control mutations, but cannot reach the PTY or VT owner directly. A disconnected or slow observer must never block the shell.

## Attachment model

The session/client boundary is the frozen Howl framed byte stream, independent of the kernel PTY underneath it. Unix sockets remain a temporary local oracle, while `howl-sessiond` now also supports IPv4 loopback TCP as the portable native-client transport under active Linux/Android proof. SSH remains an optional secure way to reach a remote byte stream; the existing Unix stdio bridge stays until a TCP remote replacement is independently proven.

Attaching is observational. It never silently resizes the PTY. Geometry is explicit canonical session state.

## Operator and agent CLI

The installed non-GUI entrypoint is `~/.local/bin/howl`. It is an ordinary client
of `howl-sessiond`; Remoter and Captain Control do not relay or own terminal state.
TCP endpoints remain IPv4 loopback only. Remote agents first reach the node through
existing transport, then run the same CLI a human would.

```text
howl sessions [--json]
howl observe SESSION [--json]
howl paste SESSION TEXT|--stdin
howl key SESSION KEY [press|repeat|release] [--mods ctrl,shift]
howl chord SESSION ctrl+c
howl hold SESSION KEY --for 2s
howl sequence SESSION --stdin
howl signal SESSION interrupt
howl resize SESSION ROWS COLUMNS
```

`key` invocations are deliberately stateless. Use `chord`, `hold`, or one
`sequence` process when a physical key must remain held across another event or
a wait. Sequence steps are only `down KEY`, `repeat KEY`, `up KEY`, and
`wait DURATION`; controlled failure releases still-held keys in reverse press
order. The canonical VT continues to decide terminal escape/control encoding.

Named daemons opt into discovery with `HOWL_SESSION_NAME`; `howl sessions`
validates the daemon PID and real session handshake before reporting it.

Install or verify candidates with:

```sh
./install-user --check
./install-user --promote
```

Promotion copies `howl`, `howl-sessiond`, and `howl-session-bridge` into
`~/.local/bin`, records their installed hashes, and refuses to overwrite a
locally changed installed binary. It requires clean pushed `main`; no source
symlink is part of the runtime.

## Experimental packages

`howl-render`, `howl-vk`, `howl-wayland`, `howl-gtk`, and `howl-flutter` are experiments, not compatibility surfaces and not part of the root core gate. They may be replaced or deleted when better client architecture demands it.

## Build

Howl uses the exact Zig version in `.zigversion`, supplied by Fleet on `PATH`:

```sh
test "$(zig version)" = "$(cat .zigversion)"
zig build
zig build test
```

Do not create a project-local Zig symlink or toolchain alias. Fleet owns the installed compiler; the repository owns only the version pin.

Each local child package owns its own `build.zig` and proofs. `howl-text` lives
in its own repository; the root, renderer, and GTK pressure client consume the
exact published commit pinned in their package metadata.

Core `check`/`test` gates also use Python 3's standard library to validate the
language-neutral session wire corpus. Python is build-time evidence only and is
not a Howl runtime dependency.
