# Howl

Howl is a small native Zig terminal family for persistent Unix work shared by humans and agents.

The core idea is simple: **the session lives on the node, not in the client.** One session owns one authoritative PTY and one authoritative VT. Linux and Android nodes can own that work; Linux, Android, agents, and later iOS clients attach to it instead of reconstructing terminal truth from byte streams or duplicating terminal state.

## Core

| Package | Owns |
| --- | --- |
| `howl-vt` | Terminal parsing, semantic state, history, images, input encoding, replies, and protocol consequences |
| `howl-session` | One canonical PTY/VT lifetime, ordered I/O, explicit geometry, signals, child state, and headless policy |
| `howl-pty` | Linux-kernel PTY transport and child-process lifecycle, used directly on Linux and Android |
| `howl-text` | Tracked module for native font metrics, fallback, shaping, source-cluster identity, glyph lookup, and bounded natural alpha rasterization |

The portable session v1 client contract and language-neutral golden vectors live in `howl-session/README.md`.

The session API is deliberately opaque. Embedders can inspect semantic state and submit input or explicit control mutations, but cannot reach the PTY or VT owner directly. A disconnected or slow observer must never block the shell.

## Attachment model

The session/client boundary is the frozen Howl framed byte stream, independent of the kernel PTY underneath it. Unix sockets and IPv4 loopback TCP are local client transports; loopback is especially useful when an Android client shares the host network namespace with a Linux session. Remote reachability, authentication and routing remain outside Howl. The existing protocol-blind SSH/stdio bridge carries the same byte stream when a session must be reached from another node.

Attaching is observational. It never silently resizes the PTY. Geometry is explicit canonical session state.

## Native CLI

`howl-cli/` is the active native human/agent client experiment. It builds the `howl` executable with compact semantic `snapshot`, canonical `state`, committed `type`, semantic `paste`, typed `key`, `focus`, explicit `resize`, and fixed `signal` operations. `snapshot --rich` retains the complete lossless `text_v1` view when compact text is not enough. The CLI owns no shell execution, session discovery, remote transport, renderer, Remoter integration, or Captain Control integration.
Install the pushed native CLI as a regular user-owned command with `./howl-cli/install --promote`; the CLI project owns only `~/.local/bin/howl`.

## Experimental packages

`howl-render`, `howl-vk`, `howl-wayland`, `howl-flutter`, and `howl-web` are experiments, not compatibility surfaces and not part of the root core gate. They may be replaced or deleted when better client architecture demands it.

## Build

Howl uses the exact Zig version in `.zigversion`, supplied by Fleet on `PATH`:

```sh
test "$(zig version)" = "$(cat .zigversion)"
zig build
zig build test
```

Do not create a project-local Zig symlink or toolchain alias. Fleet owns the installed compiler; the repository owns only the version pin.

Each tracked core module owns its own `build.zig` and proofs. `howl-text/`
lives in this repository alongside VT, Session, and PTY. Root checks and tests
include it directly; renderer and native hosts consume the same local source.
There is no separate text-repository fetch or historical-source fallback.

Core `check`/`test` gates also use Python 3's standard library to validate the
language-neutral session wire corpus. Python is build-time evidence only and is
not a Howl runtime dependency.
