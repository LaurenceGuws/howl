#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

status=0

root_publics=(
    'pub const Terminal = terminal.Terminal;'
    'pub const MutationSet = terminal.MutationSet;'
    'pub const render_journal = render_journal_mod;'
    'pub const ScalarStorage = scalar_storage.Storage;'
    'pub const UnicodeProperties = unicode_17.Properties;'
    'pub const unicodeProperties = unicode_17.properties;'
    'pub const scalar = struct {'
    '    pub const page_cells = scalar_storage.page_cells;'
    '    pub const bank_bytes = scalar_storage.scalar_bank_bytes;'
    '    pub const inline_scalars = scalar_storage.inline_scalars;'
    '    pub const maximum_scalars = scalar_storage.maximum_scalars;'
)
if [[ $(grep -Ec '^[[:space:]]*pub (const|fn|var|threadlocal)[[:space:]]' howl-vt/src/howl_vt.zig) -ne ${#root_publics[@]} ]]; then
    printf 'howl-vt/src/howl_vt.zig: curated embedding root changed\n'
    status=1
fi
for root_public in "${root_publics[@]}"; do
    if ! grep -Fxq "$root_public" howl-vt/src/howl_vt.zig; then
        printf 'howl-vt/src/howl_vt.zig: curated embedding root changed\n'
        status=1
        break
    fi
done

while IFS= read -r file; do
    if ! head -n 1 "$file" | grep -q '^//!'; then
        printf '%s:1: missing file owner contract\n' "$file"
        status=1
    fi

    # Public owner errors stay reviewable instead of widening through inference.
    awk '
        function check_signature() {
            if (signature ~ /\)[[:space:]]*![^=]/) {
                printf "%s:%d: public function has inferred error set\n", FILENAME, signature_line
                failed = 1
            }
            signature = ""
            signature_line = 0
        }
        signature != "" {
            signature = signature " " $0
            if ($0 ~ /\{[[:space:]]*$/) check_signature()
        }
        /^[[:space:]]*pub (const|fn|var|threadlocal)[[:space:]]/ {
            if (previous !~ /^[[:space:]]*\/\/\//) {
                printf "%s:%d: undocumented public declaration\n", FILENAME, NR
                failed = 1
            }
            if ($0 ~ /^[[:space:]]*pub fn[[:space:]]/) {
                signature = $0
                signature_line = NR
                if ($0 ~ /\{[[:space:]]*$/) check_signature()
            }
        }
        { previous = $0 }
        END { exit failed }
    ' "$file" || status=1
done < <(find howl-vt/src howl-host/src -type f -name '*.zig' -print | sort)

# Empty lifecycle names preserve no behavior or ownership and therefore add no contract.
empty_lifecycle_pattern='^[[:space:]]*(pub[[:space:]]+)?fn[[:space:]]+(deinit|reset|clear)'
empty_lifecycle_pattern+='[[:space:]]*\([^)]*\)[^{]*\{[[:space:]]*\}[[:space:]]*$'
while IFS=: read -r file line _; do
    printf '%s:%s: empty lifecycle hook\n' "$file" "$line"
    status=1
done < <(grep -RnE "$empty_lifecycle_pattern" howl-vt/src --include='*.zig' || true)

# Result discards are limited to compile-only root and parser test probes.
root_test_start=$(grep -n '^test[[:space:]]*{' howl-vt/src/howl_vt.zig | cut -d: -f1)
parser_test_start=$(grep -n '^test "parser' howl-vt/src/parser.zig | head -n 1 | cut -d: -f1)
parser_test_end=$(grep -n '^const StyleChange' howl-vt/src/parser.zig | cut -d: -f1)
while IFS=: read -r file line text; do
    allowed=false
    if [[ "$file" == howl-vt/src/howl_vt.zig &&
        "$line" -gt "$root_test_start" && "$text" == '    _ = terminal;' ]]; then
        allowed=true
    elif [[ "$file" == howl-vt/src/parser.zig &&
        "$line" -gt "$parser_test_start" && "$line" -lt "$parser_test_end" ]] &&
        [[ "$text" == '    _ = parser.next('* || "$text" == '    _ = parser.entryPhase('* ]]; then
        allowed=true
    fi
    if [[ "$allowed" == false ]]; then
        printf '%s:%s: discarded source result\n' "$file" "$line"
        status=1
    fi
done < <(grep -RnE '^[[:space:]]*_[[:space:]]*=' howl-vt/src --include='*.zig' || true)

diff -u tools/source_audit.allow <(
    git ls-files --cached --others --exclude-standard -z -- '*.zig' |
        while IFS= read -r -d '' file; do
            if [[ -f "$file" ]]; then printf '%s\0' "$file"; fi
        done |
        xargs -0 perl -ne '
            $raw=$_; chomp $raw; $code=$raw;
            $code =~ s/"(?:\\.|[^"\\])*"//g; $code =~ s{//.*$}{};
            $line=$raw; $line =~ s/^\s+|\s+$//g;
            while ($code =~ /\b(anytype|anyerror|anyopaque)\b/g) { print "$ARGV|$1|$line\n" }
            while ($code =~ /(?<![A-Za-z0-9_])_\s*=/g) { print "$ARGV|discard|$line\n" }
        ' |
        sort
) || { printf 'Howl sensitive source sites changed; review the exact allowlist.\n' >&2; status=1; }

exit "$status"
