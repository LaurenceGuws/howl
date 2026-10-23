# Exact publication pixel sizing

24 October 2026. Control: 8f6e25e5, LLVM ReleaseFast app 97062703.
This is a bounded allocation/admission correction at the Render API and its
publication callers, not a general throughput or RSS improvement.

## Change and exact benefit

`try terminal.framePixelBytes(renderer, residency)` returns only the current
renderer-owned glyph upload bytes missing from exact backend residency. The
query shares frame construction's retained-residency predicate, including
identity, generation, format and extent. It validates the supplied residency and
requires an accepted Render frame. It retains no snapshot or lease; the caller
must use the same accepted state and residency for construction. Host-owned
image bytes remain separate. Empty residency requests all currently visible
glyph pixels, not a bound for future updates.

Instance and standalone native Render use the exact requirement rather than
reserving every visible glyph plane. Native Render still queries on its existing
bounded pixel-capacity retry. Instance retains its simpler up-front allocation
path. No VT, shaping, atlas capacity, frame construction, pacer, worker, resource
generation or immutable-lease contract changes.

The native regression has a 256x256 atlas and a 256KiB frame pixel ceiling.
A colour-only capture uploads 256KiB. With that colour plane resident, adding
alpha text needs only 64KiB of new pixels. The former 320KiB sizing request
incorrectly rejected the capture; the exact request succeeds. Losing both planes
still correctly exceeds the limit. A held colour frame remains byte-identical
through the newer capture, rejection and recovery.

An Instance proof holds the first 512x512 alpha publication, supplies its exact
backend residency, disables further allocation and publishes into another slot
whose pixel storage is cold. It succeeds without the formerly unnecessary 256KiB
allocation. Eviction restores the complete pixels. A mixed external-image and
atlas publication preserves both payloads while the old lease remains held.
These are deterministic allocation/admission facts, not process-RSS estimates.
Slots retain their high-water capacity, and future resource changes can require
that previously avoided storage. The maximum resource envelope is unchanged.

Render and Instance advance to 0.1.7-dev; Server's forwarding package advances
with the changed Zig signature. Native C layouts and operations are unchanged.

## Correctness and rejected implementation A

The first implementation extracted a common upload plan into the hot frame
constructor. 640 exact field/pixel frame pairs matched across ten frozen tracks,
but 160 paired fresh public-module processes rejected it: sparse prefix whole
feed/update/frame cost +10.60%, rain +3.01%; Render update alone +13.67%/+5.02%.
The precise compiler/layout cause is unproven. It was not installed.

The selected implementation changes the sizing query only, reusing the existing
exact residency predicate. The public-module probe does not call that query;
its ELF .text is byte-identical to the original control (955647 bytes,
SHA256 618db3dee2ae0fdeb71aa15345d0fdeb376be9aabffb76b9b8c3103f0d0c7660).
A second 640-frame comparison matches complete commands, cursor, uploads,
removals and pixel hashes. This protects the unchanged Render path; it does not
measure the new query. The app tests below exercise the actual publication caller.

The ten 64-frame tracks are ASCII, UTF-8, UTF-8/background, legacy Unicode/background,
sparse prefix, rain, emoji, combining, capped CJK256 and 4096-glyph churn. The last
uses explicit larger shape/atlas budgets; it establishes no default-desktop
4096-glyph admission. Tapes and source/binary hashes are pinned in the workstream.

## Ordinary app guards for selected implementation B

Private KWin, 1920x1080 scale1, native fullscreen384x83 cells at5x13pixels.
Two reversed-order pairs per case; fresh8second apps. CPU is terminal-component
user+system time after1second warmup and strictly inside the producer lifetime;
producer, runner and compositor are excluded. Two native four-corner captures
independently qualify the full grid. All ordinary app diagnostics are empty.

24 trials deliver39,040 producer frames with zero skipped slots. Five cases run
at240Hz; combining runs at20Hz to avoid comparing unequal saturated workloads.
CJK256 is the existing frozen32frame capped-alphabet replay, not the unchanged
4096-scalar TUI Zoo track. Matched producer bytes/counters remain explicit.

| Lane | Paired app CPU changes |
| --- | --- |
| sparse | -0.78%, -0.38% |
| ascii | +0.36%, -6.33% |
| utf8-bg | -5.74%, +2.36% |
| rain | -0.77%, +0.01% |
| cjk-256 | +0.64%, +1.73% |
| combining | -0.02%, -2.01% |

The small primary cohort does not establish a general throughput win. CJK's two
adverse samples and the mixed ASCII/UTF-8 results prompted an independent24trial
follow-up:46,080frames, all1920frames/trial, zero misses and empty diagnostics.

| Lane | Four independent paired changes | Median |
| --- | --- | --- |
| ascii | +0.09%, -2.80%, -0.10%, +0.26% | -0.00% |
| utf8-bg | -0.67%, +0.50%, +0.16%, -0.15% | +0.00% |
| cjk-256 | -0.09%, +4.67%, +1.19%, -0.69% | +0.55% |

Do not silently discard the CJK+4.67% outlier or describe the API as proven free.
ASCII and UTF-8 follow-up medians are effectively flat; CJK remains mixed with
a small positive median. The change is selected for the deterministic admission
fix and avoided scratch allocations, not for a CPU speedup. Anonymous peaks are
mixed (roughly86–104MiB in the primary cohort); no general memory reduction is
established. There are no displayed-frame deadline, latency or physical240Hz claims.

## Rejected demand-driven Instance variant C

A second Instance experiment mirrored native Render: first try existing storage,
then compute exact sizing after one bounded PixelLimit. External-image copying
moved after successful preparation to survive private-buffer growth. It passed
the complete source graph and a strengthened mixed-image/held-lease proof.

Its separate24trial app cohort emitted39,040frames with zero misses, but sparse
CPU rose+1.38/+2.56% and rain+0.35/+5.68%. Other lanes were small or mixed; the
apparently cheaper steady path did not earn the added retry/copy sequencing.
The implementation was withdrawn; its stronger geometry-correct image test
remains. No C artifact was installed. A missing cell-pixel lattice in the first
image fixture produced InvalidView and was fixed in the fixture, never by relaxing
the renderer's geometry check.

## Qualification and evidence

Required Render/Instance Safe and Fast proofs, LLVM Fast app153tests, root
check/test/consumer/protocol, source audits, Howl structural audit, formatting and
whitespace checks are exercised. Coverage includes exact and one-byte-short pixel
storage, either independently missing plane, stale identity metadata, invalid and
duplicate residency, native allocation-failure campaigns, cold-slot publication,
eviction, external images, bounded failure recovery and immutable held leases.

The initial4GiB full gate passed but recorded2096memory.max reclaim events, no
OOM or CPU throttling. The final6GiB qualification passes341/341root steps with1129reported tests
plus cached proofs,76reported Instance tests in each Safe/Fast gate and153Fast
app tests. Render Safe/Fast proofs are cached from their earlier passing runs.
Peak cgroup charge is4.032GB with zero limit events, OOM or throttling. No build
or instrumentation was run alongside the ordinary app timing cohorts. Failed
fixtures, rejected patches, all pairs and outliers remain separate evidence.

Raw scripts, pins, comparisons and sealed Walker receipts:

    ~/.local/state/workstreams/howl-current/night-20261024/publication-sizing/

Key records: inputs.json, probe-text.json, oracles-B.json, live-validation.json,
followup-B-summary.json, live-validation-C.json, candidate-A.patch,
candidate-B.patch, candidate-C.patch, and the final qualification/install receipts.
The original default-atlas capacity and complete sparse-paint reuse questions in
[ATLAS_WORKING_SET.md](ATLAS_WORKING_SET.md) remain open.

The fresh final app build is byte-identical to the B artifact used for both
ordinary app cohorts: SHA256
`1adc2bebbb8d5bf10f08faed05be8991ec4c2b155ce75aee06d7a00c80285cc3`.
The rejected C artifact and its scores are not substituted for that binary.
