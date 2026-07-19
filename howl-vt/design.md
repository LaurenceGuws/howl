# howl-vt Design

Updated: 2026-07-18.

Shared rules: [`../AGENTS.md`](../AGENTS.md), [`../libs.yaml`](../libs.yaml)

## Purpose

`howl-vt` owns the host-neutral terminal model.

It parses terminal input streams, classifies parser events into semantic events, mutates
terminal state through concrete owners, owns selection truth, encodes host input according
to terminal modes, and exposes host-facing protocol consequences and visible-surface truth
through native Zig interfaces.

It does not own PTY transport, host wake policy, host event loops, render text shaping, or backend presentation.

## Embedding Surfaces

- The primary development contract is the `howl_vt` Zig module rooted at `src/howl_vt.zig`.
- Private implementation modules remain repo-local owners rather than direct embedding targets.
- This private project's native owner boundaries may change without notice.
- A future external ABI may be designed from scratch only after the native
  model earns a stable projection.

## Owners

- `src/terminal.zig` owns terminal lifecycle and composes parser, screen, host, kitty, selection, and input state.
- `src/stream_terminal.zig` owns byte-stream batching and parent routing into terminal-owned state.
- `src/parser.zig` and `src/parser/` own byte-step syntax recognition and
  parser-event materialization.
- `src/semantic_event.zig` owns the sole parser-to-domain mutation vocabulary;
  `src/route.zig` dispatches each event directly to its concrete owner.
- `src/screen.zig` and `src/screen/` own one-screen mutable state and screen mutation.
- `src/screen_set.zig` owns primary/alternate screen composition and visible-history projection.
- `src/selection.zig` and `src/selection_projection.zig` own selection state,
  mutation, visible projection, and copied text.
- `src/host_state.zig` owns retained host consequences; `src/host_apply.zig`
  mutates them from canonical semantic events.
- `src/input/` owns key/mouse/focus/paste input vocabulary and encoding.
- `src/csi*.zig`, `src/osc*.zig`, `src/dcs.zig`, and `src/report.zig` own the
  currently fragmented xterm-family control mapping and replies.
- `src/kitty/` owns kitty protocol state, parsing, and consequences.

## Main Flow

1. Host creates terminal state through the native Zig model.
2. Host feeds bytes from PTY transport into `Terminal.feed`.
3. Parser owners classify syntax into `SemanticEvent`; route dispatches it directly to screen, terminal mode, host, kitty, or report owners.
4. Host drains pending protocol consequences such as output, clipboard, title, and visible metadata through native owner methods.
5. Host copies visible-surface truth for render publication.
6. Host encodes keyboard, mouse, focus, and paste input through native VT input interfaces before sending bytes to PTY.

## Invariants

- VT owns terminal state truth; render and host must not invent terminal state.
- Selection coordinates are VT/history-aware and must be mutated through VT selection contracts.
- Dirty and snapshot identities are VT-owned and retired only through the acknowledged native path.
- Parser syntax, parser events, canonical semantic mutation vocabulary, concrete state mutation, and host consequences remain separate owners.
- String-control parsing accepts protocol-sized packets, unsupported SOS, PM,
  and APC payloads stream without retention, and concrete host owners bound
  every retained consequence independently.
- Runtime control signals and wake policy do not belong in VT.

## Non-Goals

- PTY process management or transport reads/writes.
- Host windows, input queues, event loops, or wake threads.
- Render glyph shaping, rasterization, or prepared surfaces.
- Backend presentation or graphics resources.
