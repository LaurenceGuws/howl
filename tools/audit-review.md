# Package audit and acknowledgement review — 2026-10-11

Reviewed against layout freeze `1d46f6446c7f6c89d94992a7f0854d4351393c92`.
Zig `0.17.0-dev.1980+e78ea8f2c`; zig-audit `0.3.0`, stable ruleset 3.

## Coverage

Every one of the 25 maintained Zig build roots has a schema-2 Git-source
`.zig-audit.json`, a package-local `zig build audit` gate, and an audit dependency
from `zig build check`. Each scope includes all owned Zig source, including
tests, simulations, benchmarks and handwritten foreign ABI declarations.
Nested build roots own their own scopes. The workspace audit composes the
package gates and the external consumer audit.

`tools/audit_project.sh` independently checks the scopes: all 197 Git-owned Zig
files must have exactly one audit owner. It also checks local gate wiring and
config inclusion in each package's distributed `.paths`. Actual negative probes
confirmed rejection of a missing config, an excluded owned source directory,
and overlapping scopes.

The checker reports files containing acknowledged findings; a passing
`0 acknowledged / 0 files` package still has its owned source audited.

| Build root | Owned Zig files | Current acknowledgements |
| --- | ---: | ---: |
| . | 2 | 6 |
| hosts/howl-app | 20 | 21 |
| hosts/howl-cli | 10 | 2 |
| hosts/howl-flutter/native | 2 | 37 |
| hosts/howl-host | 13 | 146 |
| hosts/howl-odin/native | 2 | 161 |
| hosts/howl-web | 2 | 1 |
| hosts/howl-web/gateway | 2 | 2 |
| hosts/howl-web/render | 3 | 0 |
| hosts/howl-web/text | 2 | 0 |
| hosts/server | 2 | 13 |
| mods/client-transport | 4 | 18 |
| mods/howl-client | 19 | 47 |
| mods/howl-instance | 6 | 30 |
| mods/howl-pty | 3 | 31 |
| mods/howl-render | 11 | 24 |
| mods/howl-text | 14 | 30 |
| mods/howl-vk | 7 | 84 |
| mods/howl-vt | 53 | 227 |
| mods/howl-vt/examples/0.1.4-dev | 3 | 0 |
| mods/howl-wayland | 5 | 0 |
| mods/server | 5 | 10 |
| mods/server-client | 3 | 3 |
| mods/server-protocol | 2 | 0 |
| test/consumer | 2 | 20 |
| **Total** | **197** | **913** |

## Earlier acknowledgements

All 432 existing markers were checked against their current source and owner
contracts. None was mechanically stale at the starting revision; several
reasons claimed more than their source established.

| Disposition | Count | Result |
| --- | ---: | --- |
| Removed | 10 | Seven fallible reply encoders now return an error; three pointer adaptations use the existing type directly. |
| Replaced | 2 | PTY argv adaptation uses an explicit const cast; image-test cancellation failure stops the proof before joining. |
| Reason corrected | 46 | Reasons now name actual bounds, ABI preconditions, fixture failures or deliberate cleanup policy. |
| Retained | 374 | Existing operation and justification still apply at this checkpoint. |

The removal of seven `catch unreachable` acknowledgements in
`mods/howl-vt/src/fixed_report.zig` is the main behavior correction: these public
helpers accept caller-supplied scratch, so sufficient capacity was not assured.
They now return the existing `ReplyLimit` error. A regression proof exercises
all seven encoding sites with short scratch and checks that prior replies stay
unchanged.

Other bounded corrections remove pointer/integer round trips in PTY argument
helpers, redundant Flutter array/opaque-pointer casts and a host `allowzero`
pointer. Linux host descriptor cleanup accepts `EINTR` without retrying a
possibly reused descriptor. Invalid server result tags and malformed simulation
seeds return existing input errors. Failed image-fixture cancellation cannot
silently proceed into a potentially blocked join.

Corrected reasons explicitly distinguish ordinary test allocation/I/O failure
from impossible states, FreeType-owned allocation extent from locally checked
geometry, and matching live foreign handles from arbitrary raw pointers.
Clipboard base64, Windows I/O counts, PTY environment/termios pointers, logger
format capacity and Instance request/frame bounds now state their concrete
preconditions. PTY/ConPTY cleanup retains its explicit fail-stop policy when
process ownership cannot be proven retired.

## Newly covered source

The initial complete census found 972 undocumented public declarations and
505 uncovered sensitive constructs. Public declarations now have source-local
documentation, including the Vulkan ABI and Flutter/Odin exports. Source-local
acknowledgements were added for 491 remaining sensitive constructs after bounded
code corrections. These reasons describe the operation's actual caller
contract, capacity invariant or foreign lifetime. They do not grant validation
of arbitrary foreign addresses.

Six deprecated Flutter build options remain acknowledged because the native
platform scripts still supply them. Revising that packaging contract is a
separate decision.

## Validation and checkpoint scope

Passed `zig build check test -j2`, `zig build audit -j2`, Zig formatting,
shell syntax and Git whitespace checks. The complete source partition and all
package audits pass.

Package names, fingerprints, versions, dependency relationships, compiler pin
and workspace snapshot remain unchanged. Manifest edits only distribute the
audit configs. The installed application remains 14,084,278 bytes with SHA-256
`9d2d44bfc583cff0d5d24bd40604bdbfb34133cf47535bb77151cc5f5d794dad`.

Detailed baseline, per-site dispositions, coverage probes and gate output are
retained in the active Howl workstream's `audit-20261011` evidence. Current
source-local reasons remain the maintained acknowledgement record.
