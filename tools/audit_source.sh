#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

status=0

root_publics=(
    'pub const Terminal = terminal.Terminal;'
    'pub const MutationSet = terminal.MutationSet;'
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
done < <(find howl-vt/src howl-session/src howl-pty/src -type f -name '*.zig' -print | sort)

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

# The Dart/native FFI surface is one explicit contract. Every runtime lookup must
# be declared, every declaration must exist as a Zig export, and iOS must retain
# every declared symbol through final Runner linking.
ffi_contract=howl-flutter/native/ffi-symbols.txt
if grep -Evq '^[a-z][a-z0-9_]*$' "$ffi_contract"; then
    printf '%s: invalid FFI symbol name\n' "$ffi_contract"
    status=1
fi
if [[ -n "$(sort "$ffi_contract" | uniq -d)" ]]; then
    printf '%s: duplicate FFI symbol\n' "$ffi_contract"
    status=1
fi
while IFS= read -r symbol; do
    [[ -n "$symbol" ]] || continue
    if ! grep -Fq "pub export fn $symbol(" howl-flutter/native/host.zig; then
        printf '%s: declared FFI symbol has no Zig export: %s\n' "$ffi_contract" "$symbol"
        status=1
    fi
    for config in howl-flutter/ios/Flutter/Debug.xcconfig howl-flutter/ios/Flutter/Release.xcconfig; do
        if ! grep -Fq "_$symbol" "$config"; then
            printf '%s: iOS linker does not retain FFI symbol %s\n' "$config" "$symbol"
            status=1
        fi
    done
done < "$ffi_contract"

while IFS= read -r literal; do
    symbol=${literal:1:${#literal}-2}
    if ! grep -Fxq "$symbol" "$ffi_contract"; then
        printf 'howl-flutter/lib: Dart FFI lookup is outside contract: %s\n' "$symbol"
        status=1
    fi
done < <(grep -RhoE "['\"]howl_native_[a-z0-9_]+['\"]" howl-flutter/lib --include='*.dart' | sort -u)

exit "$status"
