# Physical Hyprland Fast race · 23 October 2026

Howl retains the lowest CPU use on rain. Foot is substantially cheaper for sparse
edits and anonymous memory. Alacritty leads CPU on plain and Unicode; Howl is
second on plain and third on Unicode. These are short repeated CPU observations,
not displayed-frame or responsiveness results.

## Track and artifacts

DP-1: Dell G2524H, physical Hyprland 0.56.2, 1920×1080, scale 1, 240 Hz,
empty workspace 5. All four terminals independently pass native corner qualification:
384×83 cells, 5×13 pixels each, 1920×1079 terminal lattice. One vertical pixel of
slack is distributed according to each terminal's padding policy.

Howl source: `9ea1ebcda79a2bf7acad57bf74bf3b00ad32c171`.
LLVM ReleaseFast SHA-256:
`96c631af889cefb99122825e48e233d18a649e6c1b8d8c9552870c892eedef36`.
Every runtime Zig module has explicit `-Ofast`; system libraries retain their
installed builds. The race artifact is an independent byte-identical copy.

- foot: foot version: 1.28.0 (Sep 08 2026, branch 'makepkg') +pgo +ime +graphemes +toplevel-tag +blur -assertions
- kitty: kitty 0.49.2 created by Kovid Goyal
- alacritty: alacritty 0.17.0 (94e7c887)
- producer: {"type":"tui_zoo.build/v1","zig_version":"0.17.0","optimize":"fast","zig_backend":"stage2_llvm"}

Per-process configurations retain the qualified documented recipes, including
Kitty's 4 ms repaint delay, 3 ms input batching and monitor sync, Foot's explicit
pixel size, and disabled Alacritty IPC. The same installed Iosevka regular face,
zero decorations/padding, opaque backgrounds and disabled cursor blink/motion
are used. No daily configuration changes.

Four lanes at 240 producer Hz: sparse 64 writes/frame on a populated scene,
plain 4096 writes/frame, Unicode 4096 writes/frame with backgrounds, and seeded
rain. Each trial is a fresh process and an eight-second producer run. Reversed
horse and workload orders give 32 timed observations.

## CPU

Percent of one logical core, summed process CPU clocks across each terminal and
its helpers/all threads. Producer, runner, coordinator and compositor are excluded.
100% is one fully occupied core. Table entries are medians of two runs.

| Workload | Howl Fast | Foot | Kitty | Alacritty |
|---|---:|---:|---:|---:|
| Sparse cells | 50.7% | 10.4% | 71.6% | 38.7% |
| Plain cells | 76.4% | 128.7% | 112.1% | 60.3% |
| Unicode + background | 125.3% | 178.9% | 82.4% | 72.7% |
| Rain 240 | 14.7% | 48.7% | 39.5% | 19.2% |

Independent analysis uses the first and last retained sample inside producer
start + 1 second through producer completion. This excludes warmup and the
post-completion drain sample. Preliminary live updates used the inherited
runner's longer window including that short drain. Both calculations remain in
`validated.json`; the tables use only producer-active samples and must not be
pooled directly with older drain-inclusive results.

| Workload | Terminal | Forward CPU | Reverse CPU |
|---|---|---:|---:|
| Sparse cells | Howl Fast | 50.11% | 51.23% |
| Sparse cells | Foot | 10.56% | 10.15% |
| Sparse cells | Kitty | 71.80% | 71.42% |
| Sparse cells | Alacritty | 38.89% | 38.55% |
| Plain cells | Howl Fast | 75.87% | 76.90% |
| Plain cells | Foot | 128.10% | 129.35% |
| Plain cells | Kitty | 111.63% | 112.60% |
| Plain cells | Alacritty | 64.66% | 55.99% |
| Unicode + background | Howl Fast | 125.60% | 124.90% |
| Unicode + background | Foot | 176.42% | 181.45% |
| Unicode + background | Kitty | 82.41% | 82.42% |
| Unicode + background | Alacritty | 74.04% | 71.31% |
| Rain 240 | Howl Fast | 14.68% | 14.72% |
| Rain 240 | Foot | 48.82% | 48.53% |
| Rain 240 | Kitty | 40.82% | 38.24% |
| Rain 240 | Alacritty | 19.59% | 18.81% |

## Observed anonymous resident peaks

MiB, maximum sampled terminal-component sum across each pair, including short
drain. These are sampled peaks, not allocator attribution, cold-start budgets,
continuous high-water measurements or complete GPU-memory measurements.

| Workload | Howl Fast | Foot | Kitty | Alacritty |
|---|---:|---:|---:|---:|
| Sparse cells | 97.3 | 23.4 | 134.2 | 88.4 |
| Plain cells | 95.0 | 23.6 | 135.4 | 89.5 |
| Unicode + background | 104.1 | 29.9 | 145.5 | 89.6 |
| Rain 240 | 88.1 | 23.4 | 136.3 | 87.2 |

PSS peaks, MiB, are separate because proportional shared/file-backed mappings
depend on native libraries, driver mappings and other processes:

| Workload | Howl Fast | Foot | Kitty | Alacritty |
|---|---:|---:|---:|---:|
| Sparse cells | 189.2 | 40.5 | 217.1 | 167.1 |
| Plain cells | 182.9 | 40.7 | 218.4 | 169.1 |
| Unicode + background | 197.2 | 49.6 | 230.7 | 172.6 |
| Rain 240 | 168.9 | 40.6 | 219.5 | 166.8 |

This does not isolate LLVM versus self-hosted generation or allocator behaviour.
Howl uses the same LLVM Fast artifact and Zig SMP allocator in every trial.
Foot's lower anonymous footprint remains a concrete gap to attribute.

## Cadence and limitations

The producers emit 61,435 frames with 5 skipped slots out of
61,440 scheduled slots. Misses are retained:

- Foot, unicode, round 0: 1918 frames, 2 skips, 239.748 producer Hz.
- Foot, unicode, round 1: 1918 frames, 2 skips, 239.748 producer Hz.
- Foot, plain, round 1: 1919 frames, 1 skips, 239.874 producer Hz.

All other timed trials emit 1920 frames with zero skips. Equal rain frame counts
have identical changed-cell counts. Unicode Foot comparisons include slightly
less emitted work and are not exact equal-frame comparisons. Producer cadence
is distinct from actual presentation: displayed timestamps, input latency,
GPU time and missed display deadlines are not measured.

Initial qualification caught a pattern painted during Foot's fullscreen resize:
the PTY already reported the new size while the one-shot pattern retained old
edges. Qualification now redraws its pattern until capture; all four then pass
exact corners. The failed attempt is retained.

After 21 completed trials, WMIO reports `graphical_seat_changed` during the next
Kitty window discovery. No timing had begun for that launch. The contained run
is reconciled; a fresh desktop observation verifies the same DP-1 geometry,
scale, refresh and empty workspace 5, then the remaining 11 trials resume.
No completed timed observation is replaced. `continuation.json` and both Walker
receipts retain the interruption; this is not one uninterrupted cohort.

Completed segments have sealed containment with zero resource limit events,
CPU throttling or output loss. Host load/pressure snapshots are retained. This
race launches no compiler or profiler. Other physical desktop activity is not
controlled; two short runs per lane do not support tight statistical claims.

Benchmark windows close and DP-1 returns clear on workspace 5. Other user windows,
source and installed binaries/configuration remain intact.

## Interpretation and retained evidence

Rain remains a strong workload on the physical 240 Hz track too. Sparse complete-
scene work remains a clear weakness. Dense plain is competitive here; Unicode
must improve relative to Kitty/Alacritty, and a sparse consumer must not worsen it.
Anonymous memory needs attribution independently of compiler choice. Keep the
current pacer as the first reuse experiment's control: this race supplies no
prepared-cut or actual-present evidence to select a replacement.

Raw evidence on Home:

`/home/home/.local/state/workstreams/howl-current/day-20261023/hyprland-race/`

Exact ELF/font/config hashes, original/continuation drivers, native captures,
32 sample sets and producer receipts, failed qualification/discovery records,
containment receipts and independent validation are retained. No product code
changes were made for this race.
