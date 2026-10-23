# Font coverage and fallback cost — 23 October 2026

The existing public howl-text API already accepts 24 ordered fallback paths.
The desktop supplies Arabic, CJK and an automatic emoji face; its saved settings
expose only the first two fallbacks. Most of the missing script coverage is a
host recipe limitation. One independent variation-selector defect belongs to
the text module and is corrected by this checkpoint.

## Public-module qualification

An external LLVM Fast consumer imports the actual public howl_text build module.
It decomposes the earlier 66 slot samples into 102 cell sequences, keeping each
combining/emoji grapheme intact. No private font handles are inspected.
For each sequence it checks faceFor, shapes through that selected face and
requires successful validated nonzero glyph identities. It also checks nominal
coverage for every one of the 4,096 generated CJK scalars.

The primary is the installed Iosevka Nerd Font Regular at ten pixels.
The baseline adds Noto Sans Arabic, Noto Sans CJK JP and Noto Color Emoji.
The expanded diagnostic recipe appends Noto Sans Armenian, Georgian, Ethiopic,
Thai, Hebrew, Devanagari and Symbols 2. Exact paths and hashes are retained in
the evidence. This is an explicit diagnostic recipe, not new desktop defaults.

| Recipe | Missing before selector correction | Missing after |
| --- | ---: | ---: |
| Three fallbacks | 15/102 | 11/102 |
| Ten fallbacks | 5/102 | 1/102 |

The wider list fixes the ten missing Georgian/Ethiopic/Thai/Hebrew/Devanagari
cells. Armenian already resolves through the primary. Both lists cover all
4,096 churn scalars. Four text-selector samples account for the text-module
correction: copyright, sun, heart and airplane followed by VS15.

The remaining character is U+20000. Fontconfig advertises no installed font for
that character; fc-match nevertheless returns a nearest font, so matching
success must never be treated as proof of coverage. A suitable font is a
separate race dependency. The producer's difficult case remains intact.

These are coverage/shaping probes, not a screen oracle or proof of equal
contextual layout, glyph appearance, rasterization or painted work among horses.

## Selector correction

Previously face selection required explicit base-plus-selector mappings in
some configured font. It returned MissingGlyph even when the base character was
available. Render then substituted its replacement glyph.

Selection now prefers an exact complete sequence across the ordered faces.
Only if that fails does it retry nominal base coverage for unsupported selectors.
The original sequence and source clusters reach HarfBuzz unchanged; missing bases
and lone selectors retain their existing errors. An explicit variant in a later
fallback continues to outrank an earlier nominal base.

This follows Unicode's unsupported-variation guidance:
https://www.unicode.org/faq/vs.html

HarfBuzz's default handling removes unresolved selectors from the output:
https://harfbuzz.github.io/harfbuzz-hb-buffer.html#hb-buffer-set-not-found-variation-selector-glyph

The licensed-fixture regression fails before the change (55/56 text tests)
and passes afterward (56/56). It checks explicit-fallback priority, BMP and
supplementary selectors, unchanged nominal advance/source clusters, and missing
base behavior. The full root check/test/consumer/protocol/audit graph passes
341 steps with 1,229 reported tests plus cached proofs. The LLVM Fast desktop
check/test/audit/install graph passes 14 steps and 153 tests.

A private native Howl capture at 1920x1080 /384x83 shows all four former
replacement samples as base glyphs. All 66 terminal-reported width probes still
match two cells. Existing desktop script coverage remains limited because this
checkpoint does not replace its fallback recipe. A base glyph is not a promise
that an unsupported requested text/emoji variant became available.

## Cost: modest construction, measurable raw shaping difference

There are 24 initial fresh processes and 32 pinned before/after processes.
Pinned runs use eight reversed pairs per recipe, one CPU, warmed OS font files,
one FontSet and no renderer shape cache. Every process shapes the sample corpus,
checks churn coverage, then times 100,000 direct shapes of primary ASCII A.
All outliers are retained, including a +38.75% before/after baseline pair.

After the correction, median construction is 1.509 ms with three fallbacks and
1.563 ms with ten. Loaded RSS medians are 20.98 and 21.79 MiB; anonymous medians
are 1.551 and 1.594 MiB. Paired median added construction is 0.076 ms, RSS
806 KiB and anonymous memory 44 KiB. These are snapshots before the shaping
corpus, without raster or atlas allocation, and include the process baseline.

| Comparison | Paired median raw primary-shaping time | Adverse pairs |
| --- | ---: | ---: |
| Wider list, old selection | +2.26% | 7/8 |
| Wider list, corrected selection | +3.62% | 7/8 |
| Selector correction, three fallbacks | +0.81% | 4/8 |
| Selector correction, ten fallbacks | +0.28% | 7/8 |

The wider list is not free in this probe, even though A resolves to the first
face. The mechanism is not attributed. These short direct-shape loops do not
establish application CPU regressions or equivalence. Renderer cache hits avoid
this face walk and shaping altogether; actual terminal workloads must earn
their own results.

FontSet eagerly opens FT/HB faces. Desktop matching panes share a presentation
owner for a recipe and physical size, but style variants have distinct font sets.
Do not multiply RSS linearly: file-backed mappings can be shared. Do budget
native faces, per-style private state, cold misses and raster/atlas growth.

## Next ownership cut

1. **Text source identity:** express collection-face selection. Fontconfig returns
   both file and index; the current path/memory constructors always pass zero to
   FreeType. On this host Noto CJK JP, KR and SC are the same TTC at indices
   0, 1 and 2. A path alone loses that selection. This is distinct from the
   returned u8 face slot within a FontSet.
2. **Desktop recipe:** replace the two script-specific slots with a bounded,
   ordered fallback list and deliberate automatic discovery. Resolve system
   choices when constructing/replacing the recipe; pass explicit sources into
   howl-text. Preserve primary metrics and existing transactional replacement.
   Text faces should precede generic emoji fallback where that is the intended
   presentation; explicit variation matches still take priority.
3. **Desktop consistency:** settings, saved recipes, installed-font chooser and
   SDL UI/previews must consume the same source identities and fallback recipe.
4. **Fair race gate:** qualify selected faces, missing glyphs, widths and rendered
   samples, then run matched cold/warm and ASCII/UTF-8/background trials. Supply
   the missing supplementary CJK face or retain an explicit coverage limitation.

Fontconfig discovery and host settings stay in the desktop. The text module
owns font-source identity, loading and selection. VT remains the authority for
terminal occupancy and graphemes. No new font-count API is needed for this corpus.

Evidence, frozen before/after consumers, all process samples, source baselines,
screenshots and sealed cgroup receipts:

    ~/.local/state/workstreams/howl-current/day-20261023/font-coverage/

Disposable diagnostic executables/source/cache are removed once the conclusions
are sealed; receipts, manifests and emitted sample records remain.
