# Sparse and Unicode follow-up · 23 October 2026

Both performance targets remain open. Two scalar-reading candidates are withdrawn:
a repeatable isolated Unicode benefit did not establish a safe application benefit.
Accepted source and both installed LLVM Fast artifacts remain unchanged.

## Scope and profiles

The [physical race](HYPRLAND_FAST.md) established the targets: sparse CPU 50.67%
for Howl versus Foot 10.36%; Unicode/background 125.25% versus Alacritty 72.68%.
Those physical baseline numbers must not be mixed with the private diagnostics below.

DP-1 had returned to occupied workspace 4 when the diagnostic job checked it.
The job refused before launching a client; its failure is retained. This round
therefore uses an isolated KWin seat, 1920×1080 scale 1, 384×83 cells, 5×13 pixels,
the same fonts/configuration and a 240 Hz producer. It does not measure physical
presentation cadence, deadlines, latency or GPU time.

Eight diagnostic 15 s trials use two reversed orders: Howl/Foot sparse and
Howl/Alacritty Unicode/background. The 1 ms user CPU-clock sampler captures all
existing application threads. Every thread has zero lost/throttled samples,
enabled time equals running time, and no new unprofiled thread appears.
There are 30,010 raw leaf samples; 23,624 remain in the active interval after 1 s
warmup and before producer completion. Leaf samples are not inclusive function
time; the counters include user+system time and the collector tail.

| Diagnostic | Counter CPU, forward/reverse |
| --- | ---: |
| Howl sparse | 15.89% /15.66% |
| Foot sparse | 6.95% /6.93% |
| Howl Unicode/background | 52.93% /51.47% |
| Alacritty Unicode/background | 40.78% /40.46% |

Howl sparse GUI-thread CPU is 9.64/9.29%, while the canonical/preparation worker
uses 5.87/5.97%. Content building accounts for 19.0/20.9% of its active user leaf
samples, frame projection 10.2/9.3%, and Canvas command/geometry append 13.2/13.8%.
SDL and NVIDIA work are also substantial. Repeated scene work is the useful
sparse target; parsing alone cannot close this gap.

On Unicode, processBuffered plus writeCellDisposition account for 36.4/35.9%
of Howl's active user leaf samples; content building adds 11.7/12.9%.
Inline source attribution identifies repeated lead-cell resolution in grapheme
admission and generic fixed 26.6 glyph placement. This supports investigating
canonical and projection costs separately; it does not prove one cheap source
rewrite removes the attributed time.

Installed Foot and Alacritty ELFs are stripped. Their samples establish thread/
module budgets, not specific function attribution. Reference source inspection is
separate: Foot cb277178 retains per-cell cleanliness and expands dependencies for
overflowing glyphs; Alacritty 54214706 caches positioned glyph facts and batches
render items. Neither reference checkout is asserted to match its installed ELF.

## Candidates and acceptance

The first completed candidate separates already-resolved lead scalar copying
from public continuation-coordinate lookup. It adds no retained state. Exact
scalar/continuation/24-scalar-tail and absent-storage proofs pass, alongside
the VT and Fast desktop suites. Generated-code inspection also finds a new
out-of-line copyLeadScalars call in the public observation path.

The second candidate leaves that public path byte-exact. Four added lines reuse
the known codepoint when the previous lead has no combining scalars; cells with
tails use the existing complete reader. The Unicode machine, native interfaces,
allocation and retained state are unchanged. Existing VT/foreign/fuzz/simulation
proofs and all 152 Fast desktop tests pass.

Each ordinary cohort has 32 fresh 8 s process trials: four adjacent reversed pairs
per sparse/plain/Unicode/rain lane. No profiling or compilation overlaps timing.
CPU sums all application component threads/helpers, excludes producer/coordinator/
compositor, and is recomputed only between samples after 1 s warmup and before
producer completion. The final drain sample is excluded. Every run qualifies the
exact fullscreen/PTY grid and pinned artifact/configuration.

Positive changes below mean more CPU; medians are of paired relative changes.

| Ordinary application lane | First candidate | Narrow candidate |
| --- | ---: | ---: |
| Sparse | -1.54% | -2.38% |
| Plain | -0.48% | -0.33% |
| Unicode/background | -2.38% | +4.66% |
| Rain 240 | +3.08% | -2.61% |

Isolated VT cohorts each have 80 fresh processes, eight adjacent reversed pairs
per lane, explicit Fast mode on every module and LLVM code generation. Each
process warms four fixtures and processes about 128 MiB on one recorded CPU.
Byte counts, repetitions and final checksums agree within every pair.

| Isolated VT lane | First median / slower pairs | Narrow median / slower pairs |
| --- | ---: | ---: |
| plain | +2.77% /7 of 8 | +0.28% /4 of 8 |
| colour | +0.90% /7 of 8 | +0.05% /4 of 8 |
| unicode | -7.33% /0 of 8 | -5.30% /1 of 8 |
| sparse | -0.10% /3 of 8 | -0.03% /3 of 8 |
| scroll | +2.29% /8 of 8 | +0.16% /5 of 8 |

The isolated Unicode fixture writes contiguous λ/e+acute/CJK clusters. The
application race performs random cursor moves, foreground/background changes and
a nine-member glyph mix including generated lines and emoji. A benefit on the
first is not a claim about the second.

The first candidate loses the cross-lane gate: rain increases 3.08% in the app,
while isolated plain/scroll regress 2.77/2.29%. The narrow version removes that
persistent isolated plain/scroll penalty but does not earn its target app gain.
The narrow application Unicode median is +4.66%, with all four pairs slower.
The extra call observed in the first candidate is not a proven causal explanation
for its rain penalty. Neither experiment justifies that attribution.
All paired observations, producer skipped slots and outliers remain in the raw
evidence. For example, narrow isolated Unicode has a +20.84% first pair before
seven improving pairs; colour contains a +81.24% pair. No outlier is removed,
no observer overhead is subtracted, and no new physical speedup is claimed.

## Decision

Keep the accepted pacer, module ownership and complete immutable frames.
Do not retain either candidate, the extra helper/test, a new cache, or an
optimization justified only by the sequential fixture.

The next major sparse experiment is the complete slice described in
[SYSTEM_TIMING.md](SYSTEM_TIMING.md): already-proved durable column evidence,
Render-owned dependency expansion, a bounded prepared-piece index, and Canvas
reconciliation against its last successfully painted state. Compare baseline,
evidence-only and the complete consumer. Retain flat complete reconstruction and
one backend lease; do not add shared command lifetimes or another worker first.

It must survive skipped/cancelling writes, cluster/overhang dependencies,
presentation/resource changes, resize and lost-target recovery, with exact pixel
comparison. Old/new ink and unchanged intersecting ink must be replayed without
double blending. No per-cell command-signature cache or per-dirty-rectangle
whole-command scan follows from this round. Sparse geometry/CPU savings must
repay source/preparation cost without dense/Unicode/rain or memory regressions.

## Evidence and retained state

Raw evidence on Home:

`/home/home/.local/state/workstreams/howl-current/day-20261023/two-gaps/`

This retains exact source snapshots/patches, qualified artifacts and hashes,
compiler commands, all profile records/maps/symbol attribution, both ordinary
cohorts and independent validators, both 80-process cohorts, failed/stopped attempts,
source restoration, installed-state checks and sealed Walker/Cairn receipts.

The accepted source is byte-exact to application source 9ea1ebc under baseline
documentation commit 2892b55. Daily and zig-out binaries remain independent
LLVM Fast copies with SHA-256
`96c631af889cefb99122825e48e233d18a649e6c1b8d8c9552870c892eedef36`.
No runtime artifact is installed by this round.

Restored-source root test/check/audit/protocol and formatting/diff checks pass.
All 335 graph steps succeed in Safe mode (799 reported tests plus cached proofs);
the sealed gate has zero containment
resource events, throttling or output loss. The two graphical cohorts and both
isolated cost jobs also finish without containment resource events or throttling.
