#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

status=0

# Howl's public VT embedding root is intentionally curated. zig-audit owns generic
# sharp-construct detection; this project audit owns only Howl-specific structure.
root_publics=(
    'pub const Terminal = terminal.Terminal;'
    'pub const selection = @import("selection.zig");'
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
if [[ $(grep -Ec '^[[:space:]]*pub (const|fn|inline fn|var|threadlocal)[[:space:]]' mods/howl-vt/src/howl_vt.zig) -ne ${#root_publics[@]} ]]; then
    printf 'mods/howl-vt/src/howl_vt.zig: curated embedding root changed\n'
    status=1
fi
for root_public in "${root_publics[@]}"; do
    if ! grep -Fxq "$root_public" mods/howl-vt/src/howl_vt.zig; then
        printf 'mods/howl-vt/src/howl_vt.zig: curated embedding root changed\n'
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
        /^[[:space:]]*pub (const|fn|inline fn|var|threadlocal)[[:space:]]/ {
            if (previous !~ /^[[:space:]]*\/\/\//) {
                printf "%s:%d: undocumented public declaration\n", FILENAME, NR
                failed = 1
            }
            if ($0 ~ /^[[:space:]]*pub (inline )?fn[[:space:]]/) {
                signature = $0
                signature_line = NR
                if ($0 ~ /\{[[:space:]]*$/) check_signature()
            }
        }
        { previous = $0 }
        END { exit failed }
    ' "$file" || status=1
done < <(find mods/howl-vt/src mods/howl-instance/src mods/howl-pty/src -type f -name '*.zig' -print | sort)

# Empty lifecycle names preserve no behavior or ownership and therefore add no contract.
empty_lifecycle_pattern='^[[:space:]]*(pub[[:space:]]+)?fn[[:space:]]+(deinit|reset|clear)'
empty_lifecycle_pattern+='[[:space:]]*\([^)]*\)[^{]*\{[[:space:]]*\}[[:space:]]*$'
while IFS=: read -r file line _; do
    printf '%s:%s: empty lifecycle hook\n' "$file" "$line"
    status=1
done < <(grep -RnE "$empty_lifecycle_pattern" mods/howl-vt/src --include='*.zig' || true)

# The Dart/native FFI surface has one common mobile-safe contract plus a
# desktop-only Local ownership extension. Every declaration must exist as a
# Zig export; only the common contract is retained through final iOS linking.
ffi_contract=hosts/howl-flutter/native/ffi-symbols.txt
ffi_desktop_contract=hosts/howl-flutter/native/ffi-symbols-desktop.txt
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
        if ! grep -Fq "pub export fn $symbol(" hosts/howl-flutter/native/host.zig; then
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
    for config in hosts/howl-flutter/ios/Flutter/Debug.xcconfig hosts/howl-flutter/ios/Flutter/Release.xcconfig; do
        if ! grep -Fq "_$symbol" "$config"; then
            printf '%s: iOS linker does not retain FFI symbol %s\n' "$config" "$symbol"
            status=1
        fi
    done
done < "$ffi_contract"

while IFS= read -r literal; do
    symbol=${literal:1:${#literal}-2}
    if ! grep -Fxq "$symbol" "$ffi_contract" && ! grep -Fxq "$symbol" "$ffi_desktop_contract"; then
        printf 'hosts/howl-flutter/lib: Dart FFI lookup is outside contract: %s\n' "$symbol"
        status=1
    fi
done < <(grep -RhoE "['\"]howl_native_[a-z0-9_]+['\"]" hosts/howl-flutter/lib --include='*.dart' | sort -u)

# iOS native-host fonts intentionally mirror canonical howl-text fixture bytes.
# Keep the duplication explicit until an Xcode build proves a single-copy packaging
# path; drift between the two copies is never acceptable.
if ! cmp -s mods/howl-text/testdata/symbols.ttf hosts/howl-flutter/ios/Runner/NativeFonts/IosevkaTermNerdFont-Regular.ttf; then
    printf 'iOS Iosevka font mirror drifted from howl-text canonical bytes\n'
    status=1
fi
if ! cmp -s mods/howl-text/testdata/primary.ttf hosts/howl-flutter/ios/Runner/NativeFonts/NotoSans-Regular.ttf; then
    printf 'iOS Noto Sans font mirror drifted from howl-text canonical bytes\n'
    status=1
fi

# howl-host is the direct native performance canary, not another attachment
# frontend. Keep transport/orchestration machinery mechanically outside its
# build and source graph.
if grep -REn 'howl_client|server_client|remote_target' \
    hosts/howl-host/build.zig hosts/howl-host/build.zig.zon hosts/howl-host/src >/dev/null; then
    printf 'howl-host: direct canary depends on transported client/server machinery\n'
    status=1
fi
if grep -REn 'howl_render|howl_vt' hosts/howl-host/build.zig hosts/howl-host/build.zig.zon >/dev/null; then
    printf 'howl-host: direct canary must consume VT/Render through howl-instance composition\n'
    status=1
fi

# Canonical machinery never imports Server communications or client ownership.
# The workspace may build every consumer; each core package remains independent.
python3 - <<'PYCORE' || status=1
from pathlib import Path
import re

# One exact pure grammar leaf may be shared by live VT and optional codec.
# Keep this exemption narrow and prove it cannot import runtime ownership.
grammar = Path("mods/howl-vt/src/clipboard_grammar.zig")
grammar_imports = re.findall(r'@import\(\s*"([^"\n]+)"\s*\)', grammar.read_text())
if any(name not in ("std", "builtin") for name in grammar_imports):
    raise SystemExit(f"{grammar}: shared clipboard grammar imports non-pure ownership")
vt_build = Path("mods/howl-vt/build.zig").read_text()
for exact in (
    'module.addImport("vt_clipboard_grammar", clipboard_grammar);',
    'codec.addImport("vt_clipboard_grammar", clipboard_grammar);',
):
    if len(re.findall(r"^\s*" + re.escape(exact) + r"$", vt_build, re.MULTILINE)) != 1:
        raise SystemExit("VT and codec must share the exact child-owned clipboard grammar module")

for package in ("howl-vt", "howl-pty", "howl-instance", "howl-text", "howl-render"):
    root = Path("mods") / package
    files = list((root / "src").rglob("*.zig")) + [root / "build.zig", root / "build.zig.zon"]
    for path in files:
        source = path.read_text()
        forbidden = re.search(
            r'(?:@import|addImport|b\.dependency)\(\s*"(?:server[^"]*|howl_client[^"]*|client_transport|howl_instance_protocol|howl_instance_service)"'
            r'|\.(?:server[a-z_]*|howl_client[a-z_]*|client_transport)\s*=\s*\.\{',
            source,
        )
        if forbidden:
            print(f"{path}: canonical package depends on Server/client communications")
            raise SystemExit(1)
        # Codec source is separately selected; it never enters normal core roots.
        if path.suffix == ".zig" and "src" in path.parts:
            codec_root = Path("mods/howl-vt/src/codec.zig").resolve()
            codec_dir = codec_root.parent / "codec"
            codec_source = path.resolve() == codec_root or path.resolve().is_relative_to(codec_dir)
            for imported in re.findall(r'@import\(\s*"([^"\n]+)"\s*\)', source):
                target = (path.parent / imported).resolve() if imported.endswith(".zig") else None
                imports_codec = imported.startswith("howl_vt_codec") or (
                    target is not None and (target == codec_root or target.is_relative_to(codec_dir))
                )
                if not codec_source and imports_codec:
                    print(f"{path}: direct local core imports optional observation codec")
                    raise SystemExit(1)
                if codec_source and imported not in ("std", "builtin", "vt_clipboard_grammar") and (
                    target is None or not target.is_relative_to(codec_dir)
                ):
                    print(f"{path}: optional observation codec imports a live/presentation owner")
                    raise SystemExit(1)

PYCORE

# The live VT and optional native owner are separate dependency capabilities.
python3 - <<'PYINSTANCEABI'
from pathlib import Path
import re
base = Path("mods/howl-instance/src").resolve()
roots = ["instance.zig", "headless.zig", "runtime.zig", "native.zig", "native_frames.zig"]
seen = set()
def visit(path):
    path = path.resolve()
    if path in seen:
        return
    seen.add(path)
    if path.name == "abi_owner.zig":
        raise SystemExit("Instance direct/native-helper graph imports private C ownership")
    for name in re.findall(r'@import\("([^"]+)"\)', path.read_text()):
        if name == "instance_abi_owner":
            raise SystemExit("Instance direct/native-helper graph imports private C ownership")
        if name.endswith(".zig"):
            child = (path.parent / name).resolve()
            if child.is_relative_to(base):
                visit(child)
for root in roots:
    visit(base / root)
PYINSTANCEABI

# Optional Render ownership cannot enter direct local or existing schema roots.
python3 - <<'PYRENDEROWNER' || status=1
from pathlib import Path
import re
base = Path("mods/howl-render/src").resolve()
def names(path):
    return re.findall(r'@import\(\s*"([^"\n]+)"\s*\)', path.read_text())
owner_files = {base / "native_owner.zig", base / "native_fonts.zig", base / "abi.zig"}
seen = set()
def visit(path):
    path = path.resolve()
    if path in seen:
        return
    seen.add(path)
    if path in owner_files:
        raise SystemExit("Render direct/schema graph imports optional ownership")
    for name in names(path):
        if name == "howl_render_owner_native":
            raise SystemExit("Render direct/schema graph imports optional ownership")
        if name.endswith(".zig"):
            child = (path.parent / name).resolve()
            if child.is_relative_to(base):
                visit(child)
for root in ("root.zig", "renderer.zig", "terminal_vt.zig", "adapter.zig", "native.zig"):
    visit(base / root)
allowed = {"std", "howl_render", "howl_render_native", "howl_vt_native"}
for path in owner_files:
    for name in names(path):
        if path.name == "abi.zig" and name == "howl_render_owner_native":
            continue
        if name not in allowed and (path.parent / name).resolve() not in owner_files:
            raise SystemExit(f"{path}: standalone owner imports an unrelated runtime")
    # No scheduler/backend policy, even disguised behind the otherwise allowed std.
    if re.search(r'\bstd\.(?:Thread|Io|process|posix|time)\b', path.read_text()):
        raise SystemExit(f"{path}: standalone owner contains runtime scheduling/process policy")
PYRENDEROWNER

python3 - <<'PYVTNATIVE' || status=1
from pathlib import Path
import re

root = Path("mods/howl-vt/src").resolve()
def imports(path):
    return re.findall(r'@import\(\s*"([^"\n]+)"\s*\)', path.read_text())
def relative(path, name):
    target = (path.parent / name).resolve()
    if not target.is_relative_to(root):
        raise SystemExit(f"{path}: VT import escapes its source owner")
    return target

pending = [root / "howl_vt.zig"]
seen = set()
while pending:
    path = pending.pop()
    if path in seen:
        continue
    seen.add(path)
    if path.name.startswith("native") or path.name == "abi.zig":
        raise SystemExit(f"{path}: live VT imports optional native ownership")
    for name in imports(path):
        if name.endswith(".zig"):
            pending.append(relative(path, name))
        elif name not in ("std", "builtin", "vt_clipboard_grammar"):
            raise SystemExit(f"{path}: live VT imports noncanonical module {name}")

pending = [root / "native.zig", root / "abi.zig"]
seen = set()
while pending:
    path = pending.pop()
    if path in seen:
        continue
    seen.add(path)
    source = path.read_text()
    if re.search(r'\bstd\.(?:process|posix|Io)\b', source):
        raise SystemExit(f"{path}: native VT imports process or I/O runtime ownership")
    if path.name != "abi.zig" and "std.heap.c_allocator" in source:
        raise SystemExit(f"{path}: native helper acquires ABI libc allocator")
    for name in imports(path):
        if name.endswith(".zig"):
            target = relative(path, name)
            if not target.name.startswith("native"):
                raise SystemExit(f"{path}: native VT bypasses curated live/public or codec boundary")
            pending.append(target)
        elif name not in ("std", "builtin", "howl_vt", "vt_native_types", "howl_vt_native"):
            raise SystemExit(f"{path}: native VT imports noncanonical module {name}")
PYVTNATIVE

# Server clients consume communications; process/Instance owners are test fixtures.
python3 - <<'PYCLIENT' || status=1
from pathlib import Path
import re

root = Path("mods/server/src/client")
files = list(root.rglob("*.zig"))
for path in files:
    if path.name == "render_test.zig":
        continue
    if re.search(r'@import\(\s*"(?:howl_instance|howl_instance_headless|howl_pty|howl_vt|server|server_model|server_runtime|server_service|server_terminal_service)"', path.read_text()):
        raise SystemExit(f"{path}: Server client imports canonical process or service ownership")
PYCLIENT

# Flutter's desktop worker cannot regain an internal client/service/wire route.
python3 - <<'PYLOCAL' || status=1
from pathlib import Path
import re

path = Path("hosts/howl-flutter/native/local.zig")
imports = re.findall(r'@import\(\s*"([^"]+)"', path.read_text())
for name in imports:
    if name not in ("std", "builtin", "howl_instance"):
        raise SystemExit(f"{path}: Local worker imports noncanonical owner {name}")
PYLOCAL

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

# Each package owns its version; the snapshot records the tested combination.
python3 - <<'PYSNAPSHOT' || status=1
from pathlib import Path
import json
import re
import subprocess

def require(condition, message):
    if not condition:
        raise SystemExit(message)

root = Path.cwd()
snapshot = json.loads(Path("snapshot.json").read_text())
require(set(snapshot) == {"schema", "version", "zig", "packages"}, "snapshot.json: unexpected fields")
require(snapshot["schema"] == 1, "snapshot.json: unsupported schema")
require(snapshot["version"] == Path("VERSION").read_text().strip(), "snapshot.json: VERSION mismatch")
require(snapshot["zig"] == Path(".zigversion").read_text().strip(), "snapshot.json: compiler mismatch")

def package_version(directory):
    manifest = Path(directory) / "build.zig.zon"
    match = re.search(r'\.version\s*=\s*"([^"]+)"', manifest.read_text())
    require(match is not None, f"{manifest}: missing version")
    return match.group(1)

require(package_version(".") == snapshot["version"], "build.zig.zon: workspace snapshot version mismatch")
tracked = subprocess.check_output(["git", "ls-files", "*build.zig.zon"], text=True).splitlines()
packages = {str(Path(path).parent): package_version(Path(path).parent)
            for path in tracked if Path(path).parent != Path(".")}
require(snapshot["packages"] == packages, "snapshot.json: package inventory/version mismatch")

for path in tracked:
    package = Path(path).parent
    if not str(package).startswith("mods/"):
        continue
    for relative in re.findall(r'\.path\s*=\s*"([^"]+)"', Path(path).read_text()):
        dependency = (root / package / relative).resolve()
        require(not dependency.is_relative_to(root / "hosts"),
                f"{path}: reusable module depends on host {relative}")

for path, pattern, directory in (
    ("hosts/howl-cli/src/howl_cli.zig", r'pub const version = "([^"]+)";', "hosts/howl-cli"),
    ("hosts/howl-app/src/main.zig", r'const version = "([^"]+)";', "hosts/howl-app"),
    ("hosts/howl-odin/main.odin", r'APP_VERSION :: "([^"]+)"', "hosts/howl-odin/native"),
):
    match = re.search(pattern, Path(path).read_text())
    require(match is not None and match.group(1) == package_version(directory),
            f"{path}: advertised version differs from owning package")
flutter = re.search(r'^version:\s*(\S+)', Path("hosts/howl-flutter/pubspec.yaml").read_text(), re.M)
require(flutter is not None, "Flutter: missing version")
base, separator, number = flutter.group(1).partition("+")
require(base == package_version("hosts/howl-flutter/native") and separator and number.isdigit(),
        "Flutter: expected owning package version plus numeric build")
require(f'version: {snapshot["version"]}' in Path("project_version_scope.yml").read_text().splitlines(),
        "project_version_scope.yml: workspace snapshot version mismatch")
PYSNAPSHOT

# A passing local checker must cover every owned Zig file, not only files with
# findings. Package scopes partition Git-owned source; nested build roots audit
# themselves and the root audit composes their named gates.
python3 - <<'PYAUDIT' || status=1
from pathlib import Path
import json
import re
import subprocess

root = Path.cwd()
tracked = subprocess.check_output(["git", "ls-files"], text=True).splitlines()
packages = sorted({Path(path).parent for path in tracked if path.endswith("/build.zig") or path == "build.zig"})
sources = subprocess.check_output(
    ["git", "ls-files", "--cached", "--others", "--exclude-standard", "--", "*.zig"],
    text=True,
).splitlines()

def under(path, prefix):
    return path == prefix or path.startswith(prefix.rstrip("/") + "/")

scopes = {}
for package in packages:
    config_path = package / ".zig-audit.json"
    if not config_path.is_file():
        raise SystemExit(f"{package}: missing package zig-audit config")
    config = json.loads(config_path.read_text())
    if config.get("schema") != 2 or config.get("source") != "git" or config.get("minimum_ruleset", 0) < 3:
        raise SystemExit(f"{config_path}: expected Git source acknowledgements at ruleset 3 or newer")
    if set(config) - {"schema", "source", "minimum_ruleset", "include", "exclude"}:
        raise SystemExit(f"{config_path}: unexpected config field")
    for field in ("include", "exclude"):
        values = config.get(field, [])
        if not isinstance(values, list) or any(not isinstance(value, str) for value in values):
            raise SystemExit(f"{config_path}: {field} must contain source paths")
    scopes[package] = config
    build = (package / "build.zig").read_text()
    if package != Path(".") and (
        'b.step("audit",' not in build or 'check.dependOn(audit)' not in build
        or 'zig_audit.setCwd(b.path("."))' not in build
        or 'audit.dependOn(&zig_audit.step)' not in build
    ):
        raise SystemExit(f"{package}/build.zig: missing package-local audit/check gate")
    manifest = (package / "build.zig.zon").read_text()
    if '".zig-audit.json"' not in manifest[manifest.index(".paths"):]:
        raise SystemExit(f"{package}/build.zig.zon: audit config absent from source distribution")

for source in sources:
    path = Path(source)
    ancestors = [package for package in packages if path.is_relative_to(package)]
    owner = max(ancestors, key=lambda package: len(package.parts))
    selected = []
    for package in ancestors:
        relative = str(path.relative_to(package))
        config = scopes[package]
        included = not config.get("include") or any(under(relative, prefix) for prefix in config["include"])
        excluded = any(under(relative, prefix) for prefix in config.get("exclude", []))
        if included and not excluded:
            selected.append(package)
    if selected != [owner]:
        raise SystemExit(f"{source}: expected only {owner} audit coverage, got {selected}")
print(f"Howl audit coverage: {len(packages)} package roots / {len(sources)} Zig files")
PYAUDIT

exit "$status"
