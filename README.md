# Howl

Howl is a small native Zig terminal family for persistent Unix work shared by humans and agents.

The core idea is simple: **the session lives on the node, not in the client.** One session owns one authoritative PTY and one authoritative VT. Linux and Android nodes can own that work; Linux, Android, agents, and later iOS clients attach to it instead of reconstructing terminal truth from byte streams or duplicating terminal state.

## Core

| Package | Owns |
| --- | --- |
| `howl-vt` | Terminal parsing, semantic state, history, images, input encoding, replies, and protocol consequences |
| `howl-session` | One canonical PTY/VT lifetime, ordered I/O, explicit geometry, signals, child state, and headless policy |
| `howl-pty` | Linux-kernel PTY transport and child-process lifecycle, used directly on Linux and Android |
| `howl-text` | Native font metrics, fallback, shaping, source-cluster identity, ligature classification, and bounded alpha rasterization |

The session API is deliberately opaque. Embedders can inspect semantic state and submit input or explicit control mutations, but cannot reach the PTY or VT owner directly. A disconnected or slow observer must never block the shell.

## Attachment model

The target local boundary is a Unix socket per session. A local client attaches directly. Remote syntax such as `host:session_id` will use SSH only as transport to a small bridge into the same node-local socket. SSH remains responsible for remote authentication and encryption.

Attaching is observational. It never silently resizes the PTY. Geometry is explicit canonical session state.

## Experimental packages

`howl-render`, `howl-vk`, and `howl-wayland` are experiments, not compatibility surfaces and not part of the root core gate. They may be replaced or deleted when better client architecture demands it.

## Build

Howl uses the exact Zig version in `.zigversion`:

```sh
version=$(cat .zigversion)
mkdir -p .zig
ln -sfn "$HOME/.local/share/zigup/$version/files/zig" .zig/zig
./.zig/zig build
./.zig/zig build test
```

Each child package also owns its own `build.zig` and proofs.
