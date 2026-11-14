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
if [[ $(grep -Ec '^[[:space:]]*pub (const|fn|inline fn|var|threadlocal)[[:space:]]' howl-vt/src/howl_vt.zig) -ne ${#root_publics[@]} ]]; then
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
done < <(find howl-vt/src howl-pty/src -type f -name '*.zig' -print | sort)

# Empty lifecycle names preserve no behavior or ownership and therefore add no contract.
empty_lifecycle_pattern='^[[:space:]]*(pub[[:space:]]+)?fn[[:space:]]+(deinit|reset|clear)'
empty_lifecycle_pattern+='[[:space:]]*\([^)]*\)[^{]*\{[[:space:]]*\}[[:space:]]*$'
while IFS=: read -r file line _; do
    printf '%s:%s: empty lifecycle hook\n' "$file" "$line"
    status=1
done < <(grep -RnE "$empty_lifecycle_pattern" howl-vt/src --include='*.zig' || true)

# Canonical machinery never imports Server communications or client ownership.
# The workspace may build every consumer; each core package remains independent.
python3 - <<'PYCORE' || status=1
from pathlib import Path
import re

# One pure OSC 52 grammar leaf is exported by VT for outside consumers.
# Keep it free of protocol, codec and process ownership.
grammar = Path("howl-vt/src/clipboard_grammar.zig")
grammar_imports = re.findall(r'@import\(\s*"([^"\n]+)"\s*\)', grammar.read_text())
if any(name not in ("std", "builtin") for name in grammar_imports):
    raise SystemExit(f"{grammar}: shared clipboard grammar imports non-pure ownership")
vt_build = Path("howl-vt/build.zig").read_text()
for exact in ('module.addImport("vt_clipboard_grammar", clipboard_grammar);',):
    if len(re.findall(r"^\s*" + re.escape(exact) + r"$", vt_build, re.MULTILINE)) != 1:
        raise SystemExit("VT must own the exact clipboard grammar module")

for package in ("howl-vt", "howl-pty", "howl-text"):
    root = Path(package)
    files = list((root / "src").rglob("*.zig")) + [root / "build.zig", root / "build.zig.zon"]
    for path in files:
        source = path.read_text()
        forbidden = re.search(
            r'(?:@import|addImport|b\.dependency)\(\s*"(?:server[^"]*|howl_client[^"]*|client_transport)"'
            r'|\.(?:server[a-z_]*|howl_client[a-z_]*|client_transport)\s*=\s*\.\{',
            source,
        )
        if forbidden:
            print(f"{path}: canonical package depends on Server/client communications")
            raise SystemExit(1)
        # Local core must never gain a wire/observation encoder under a new name.
        if path.suffix == ".zig" and "src" in path.parts:
            for imported in re.findall(r'@import\(\s*"([^"\n]+)"\s*\)', source):
                if imported.startswith(("howl_vt_codec", "terminal_observation_codec")):
                    print(f"{path}: direct terminal core imports observation transport codec")
                    raise SystemExit(1)

PYCORE

# The live VT and optional native owner are separate dependency capabilities.
python3 - <<'PYVTNATIVE' || status=1
from pathlib import Path
import re

root = Path("howl-vt/src").resolve()
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
                raise SystemExit(f"{path}: native VT bypasses curated live/public boundary")
            pending.append(target)
        elif name not in ("std", "builtin", "howl_vt", "vt_native_types", "howl_vt_native"):
            raise SystemExit(f"{path}: native VT imports noncanonical module {name}")
PYVTNATIVE

# Every tracked Zig build root must be reachable through package declarations.
# The external consumer intentionally depends inward on the distribution root;
# its independent invocation is owned by the root consumer gate.
python3 - <<'PYGRAPH' || status=1
from pathlib import Path
import re
import subprocess

root = Path.cwd()
tracked = subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard", "--", "*build.zig"], text=True).splitlines()
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
    if package not in {Path(name) for name in ("howl-vt", "howl-pty", "howl-text")}:
        continue
    for relative in re.findall(r'\.path\s*=\s*"([^"]+)"', Path(path).read_text()):
        dependency = (root / package / relative).resolve()
        require(dependency != (root / "howl-app").resolve(),
                f"{path}: reusable module depends on host {relative}")

for path, pattern, directory in (
    ("howl-app/src/main.zig", r'const version = "([^"]+)";', "howl-app"),
):
    match = re.search(pattern, Path(path).read_text())
    require(match is not None and match.group(1) == package_version(directory),
            f"{path}: advertised version differs from owning package")
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
print(f"Howl audit coverage: {len(packages)} active package roots / {len(sources)} active Zig files")
PYAUDIT

exit "$status"
