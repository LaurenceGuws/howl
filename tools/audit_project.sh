#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

status=0

# Howl's public VT embedding root is intentionally curated. zig-audit owns generic
# sharp-construct detection; this project audit owns only Howl-specific structure.
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
    # Source-local zig-audit acknowledgement metadata may sit between /// docs and
    # the declaration it reviews; it is transparent to this Howl-specific rule.
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
        /^[[:space:]]*\/\/ zig-audit: acknowledge / { next }
        /^[[:space:]]*\/\/ reason:/ { next }
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
done < <(find howl-vt/src howl-instance/src howl-pty/src -type f -name '*.zig' -print | sort)

# Empty lifecycle names preserve no behavior or ownership and therefore add no contract.
empty_lifecycle_pattern='^[[:space:]]*(pub[[:space:]]+)?fn[[:space:]]+(deinit|reset|clear)'
empty_lifecycle_pattern+='[[:space:]]*\([^)]*\)[^{]*\{[[:space:]]*\}[[:space:]]*$'
while IFS=: read -r file line _; do
    printf '%s:%s: empty lifecycle hook\n' "$file" "$line"
    status=1
done < <(grep -RnE "$empty_lifecycle_pattern" howl-vt/src --include='*.zig' || true)

# The Dart/native FFI surface has one common mobile-safe contract plus a
# desktop-only Local ownership extension. Every declaration must exist as a
# Zig export; only the common contract is retained through final iOS linking.
ffi_contract=howl-flutter/native/ffi-symbols.txt
ffi_desktop_contract=howl-flutter/native/ffi-symbols-desktop.txt
for contract in "$ffi_contract" "$ffi_desktop_contract"; do
    if grep -Evq '^[a-z][a-z0-9_]*$' "$contract"; then
        printf '%s: invalid FFI symbol name\n' "$contract"
        status=1
    fi
    if [[ -n "$(sort "$contract" | uniq -d)" ]]; then
        printf '%s: duplicate FFI symbol\n' "$contract"
        status=1
    fi
    while IFS= read -r symbol; do
        [[ -n "$symbol" ]] || continue
        if ! grep -Fq "pub export fn $symbol(" howl-flutter/native/host.zig; then
            printf '%s: declared FFI symbol has no Zig export: %s\n' "$contract" "$symbol"
            status=1
        fi
    done < "$contract"
done
if [[ -n "$(comm -12 <(sort "$ffi_contract") <(sort "$ffi_desktop_contract"))" ]]; then
    printf 'Flutter FFI common/desktop contracts overlap\n'
    status=1
fi
while IFS= read -r symbol; do
    [[ -n "$symbol" ]] || continue
    for config in howl-flutter/ios/Flutter/Debug.xcconfig howl-flutter/ios/Flutter/Release.xcconfig; do
        if ! grep -Fq "_$symbol" "$config"; then
            printf '%s: iOS linker does not retain FFI symbol %s\n' "$config" "$symbol"
            status=1
        fi
    done
done < "$ffi_contract"

while IFS= read -r literal; do
    symbol=${literal:1:${#literal}-2}
    if ! grep -Fxq "$symbol" "$ffi_contract" && ! grep -Fxq "$symbol" "$ffi_desktop_contract"; then
        printf 'howl-flutter/lib: Dart FFI lookup is outside contract: %s\n' "$symbol"
        status=1
    fi
done < <(grep -RhoE "['\"]howl_native_[a-z0-9_]+['\"]" howl-flutter/lib --include='*.dart' | sort -u)

# iOS native-host fonts intentionally mirror canonical howl-text fixture bytes.
# Keep the duplication explicit until an Xcode build proves a single-copy packaging
# path; drift between the two copies is never acceptable.
if ! cmp -s howl-text/testdata/symbols.ttf howl-flutter/ios/Runner/NativeFonts/IosevkaTermNerdFont-Regular.ttf; then
    printf 'iOS Iosevka font mirror drifted from howl-text canonical bytes\n'
    status=1
fi
if ! cmp -s howl-text/testdata/primary.ttf howl-flutter/ios/Runner/NativeFonts/NotoSans-Regular.ttf; then
    printf 'iOS Noto Sans font mirror drifted from howl-text canonical bytes\n'
    status=1
fi

# howl-host is the direct native performance canary, not another attachment
# frontend. Keep transport/orchestration machinery mechanically outside its
# build and source graph.
if grep -REn 'howl_client|server_client|remote_target' \
    howl-host/build.zig howl-host/build.zig.zon howl-host/src >/dev/null; then
    printf 'howl-host: direct canary depends on transported client/server machinery\n'
    status=1
fi
if ! grep -Fqx '        .client_sources = false,' howl-host/build.zig; then
    printf 'howl-host/build.zig: howl-render must disable transported client sources\n'
    status=1
fi

# Every tracked Zig build root must be reachable through package declarations.
# The external consumer intentionally depends inward on the distribution root;
# its independent invocation is owned by the root consumer gate.
python3 - <<'PYGRAPH' || status=1
from pathlib import Path
import re
import subprocess

root = Path.cwd()
tracked = subprocess.check_output(["git", "ls-files", "*build.zig"], text=True).splitlines()
build_roots = {(root / path).parent.resolve() for path in tracked}
visited = set()
pending = [root]
while pending:
    package = pending.pop()
    if package in visited:
        continue
    visited.add(package)
    manifest = package / "build.zig.zon"
    if not manifest.is_file():
        continue
    for relative in re.findall(r'\.path\s*=\s*"([^"]+)"', manifest.read_text()):
        dependency = (package / relative).resolve()
        if dependency.is_relative_to(root):
            pending.append(dependency)
missing = build_roots - visited - {root / "test/consumer"}
for package in sorted(missing):
    print(f"{package.relative_to(root)}/build.zig: absent from the root package graph")
raise SystemExit(bool(missing))
PYGRAPH

# VERSION is the single current-workspace release marker. Every current package
# and user-facing native client version must move with it; versioned embedding
# examples remain deliberately frozen at their named historical contract.
workspace_version=$(cat VERSION)
if [[ -z "$workspace_version" || "$workspace_version" == *$'\n'* ]]; then
    printf 'VERSION: expected one nonempty line\n'
    status=1
fi

while IFS= read -r manifest; do
    case "$manifest" in
        howl-vt/examples/*) continue ;;
    esac
    if ! grep -Fqx "    .version = \"$workspace_version\"," "$manifest"; then
        printf '%s: version does not match VERSION (%s)\n' "$manifest" "$workspace_version"
        status=1
    fi
done < <(git ls-files '*build.zig.zon' | sort)

if ! grep -Fqx "version: $workspace_version" project_version_scope.yml; then
    printf 'project_version_scope.yml: version does not match VERSION (%s)\n' "$workspace_version"
    status=1
fi
if ! grep -Fqx "pub const version = \"$workspace_version\";" howl-cli/src/howl_cli.zig; then
    printf 'howl-cli/src/howl_cli.zig: version does not match VERSION (%s)\n' "$workspace_version"
    status=1
fi
if ! grep -Fqx "APP_VERSION :: \"$workspace_version\"" howl-odin/main.odin; then
    printf 'howl-odin/main.odin: version does not match VERSION (%s)\n' "$workspace_version"
    status=1
fi

flutter_version=$(awk '/^version:[[:space:]]/ { print $2; exit }' howl-flutter/pubspec.yaml)
flutter_base=${flutter_version%%+*}
flutter_build=${flutter_version#*+}
if [[ "$flutter_base" != "$workspace_version" || "$flutter_build" == "$flutter_version" ||
      ! "$flutter_build" =~ ^[0-9]+$ ]]; then
    printf 'howl-flutter/pubspec.yaml: version must be VERSION+numeric-build (%s)\n' "$workspace_version"
    status=1
fi

exit "$status"
