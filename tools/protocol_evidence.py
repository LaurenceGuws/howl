#!/usr/bin/env python3
"""Read-only, declaration-aware evidence checks for protocol_coverage.nu.

Reads normalized records as JSON on stdin and writes a diagnostic JSON array.
This is a bounded Zig lexical declaration check, not a proof of semantic parity.
Only the named source/proof paths are opened; no Zig code or subprocess runs.
"""

import json
import re
import sys
import tempfile
from pathlib import Path


# Build-owned test roots. See howl-vt/build.zig and howl-app/build.zig.
TEST_ROOTS = (
    "howl-vt/test_unit.zig",
    "howl-app/src/main.zig",
    "howl-app/src/terminal_output_test.zig",
)
# A reachable file is only meaningful as test evidence if the owning build
# still compiles the root; this narrow registration must track build.zig.
TEST_BUILD_ROOTS = {
    "howl-vt/test_unit.zig": ("howl-vt/build.zig", 'b.path("test_unit.zig")'),
    "howl-app/src/main.zig": ("howl-app/build.zig", 'b.path("src/main.zig")'),
    "howl-app/src/terminal_output_test.zig": (
        "howl-app/build.zig", 'b.path("src/terminal_output_test.zig")'
    ),
}
# Module imports have distinct Build authorities; only imports relevant to
# the two accepted test roots need resolving here.
MODULE_ROOTS = {
    "howl_vt": "howl-vt/src/howl_vt.zig",
    "howl_pty": "howl-pty/src/howl_pty.zig",
    "howl_text": "howl-text/src/text.zig",
    "howl_vt_output": "howl-vt/src/output/owner.zig",
    "howl_vt_output_commands": "howl-vt/src/output/commands.zig",
    "howl_vt_output_limits": "howl-vt/src/output/limits.zig",
    "output_state": "howl-vt/src/output/state.zig",
    "vt_clipboard_grammar": "howl-vt/src/clipboard_grammar.zig",
}
IDENTIFIER = re.compile(r"[A-Za-z_][A-Za-z_0-9]*")
DRIVE = re.compile(r"^[A-Za-z]:")


def string_value(value):
    """Unescape quoted Zig test names/imports without treating them as code."""
    result = []
    at = 0
    while at < len(value):
        if value[at] != "\\":
            result.append(value[at])
            at += 1
            continue
        at += 1
        if at >= len(value):
            break
        escaped = value[at]
        at += 1
        if escaped in ('"', "'", "\\"):
            result.append(escaped)
        elif escaped in ("n", "r", "t"):
            result.append({"n": "\n", "r": "\r", "t": "\t"}[escaped])
        elif escaped == "x" and at + 2 <= len(value):
            result.append(chr(int(value[at : at + 2], 16)))
            at += 2
        elif escaped == "u" and at < len(value) and value[at] == "{":
            end = value.find("}", at + 1)
            if end < 0:
                raise ValueError("unterminated Zig Unicode escape")
            result.append(chr(int(value[at + 1 : end], 16)))
            at = end + 1
        else:
            raise ValueError("unrecognized Zig string escape")
    return "".join(result)


def lex_zig(text):
    """Emit identifiers, significant punctuation and quoted strings, not decoys."""
    out = []
    i = 0
    while i < len(text):
        ch = text[i]
        if ch.isspace():
            i += 1
        elif text.startswith("//", i) or text.startswith("\\\\", i):
            end = text.find("\n", i)
            i = len(text) if end < 0 else end + 1
        elif ch in ("'", '"'):
            quote = ch
            i += 1
            start = i
            while i < len(text) and text[i] != quote:
                i += 2 if text[i] == "\\" else 1
            if i >= len(text):
                raise ValueError("unterminated Zig string or character")
            if quote == '"':
                out.append(("string", string_value(text[start:i])))
            i += 1
        else:
            match = IDENTIFIER.match(text, i)
            if match:
                out.append(("id", match.group()))
                i = match.end()
            else:
                if ch in "{}=(),.@":
                    out.append(("punct", ch))
                i += 1
    return out


def declarations(text):
    """Resolve top-level functions, struct-owned methods and named test declarations."""
    tokens = lex_zig(text)
    opening_types = {}
    for i in range(len(tokens) - 4):
        if tokens[i] != ("id", "const") or tokens[i + 1][0] != "id" or tokens[i + 2] != ("punct", "="):
            continue
        j = i + 3
        if tokens[j] in (("id", "extern"), ("id", "packed")):
            j += 1
        if j + 1 < len(tokens) and tokens[j] == ("id", "struct") and tokens[j + 1] == ("punct", "{"):
            opening_types[j + 1] = tokens[i + 1][1]

    methods = set()
    tests = set()
    imports = set()
    stack = []
    for i, token in enumerate(tokens):
        if token == ("punct", "{"):
            stack.append(opening_types.get(i))
        elif token == ("punct", "}"):
            if stack:
                stack.pop()
        elif token == ("id", "fn") and i + 2 < len(tokens) and tokens[i + 1][0] == "id" and tokens[i + 2] == ("punct", "("):
            qualifier = next((scope for scope in reversed(stack) if scope), "")
            methods.add((qualifier, tokens[i + 1][1]))
        elif token == ("id", "test") and i + 1 < len(tokens) and tokens[i + 1][0] == "string":
            if i + 2 < len(tokens) and tokens[i + 2] == ("punct", "{"):
                tests.add(tokens[i + 1][1])
        elif token == ("punct", "@") and i + 3 < len(tokens):
            if (tokens[i + 1] == ("id", "import") and tokens[i + 2] == ("punct", "(")
                    and tokens[i + 3][0] == "string"):
                imports.add(tokens[i + 3][1])
    return methods, tests, imports


def diag(record_id, rule, detail):
    return {"id": record_id, "rule": rule, "detail": detail}


class Evidence:
    def __init__(self, root, test_roots=TEST_ROOTS, build_roots=None):
        self.root = Path(root).resolve()
        self.test_roots = tuple(test_roots)
        self.build_roots = TEST_BUILD_ROOTS if build_roots is None else build_roots
        self.parsed = {}
        self.registered = None

    def checked_path(self, path):
        if (not isinstance(path, str) or not path or DRIVE.match(path)
                or Path(path).is_absolute() or "\\" in path or "\x00" in path
                or ".." in Path(path).parts or Path(path).suffix != ".zig"):
            return None
        target = (self.root / path).resolve()
        if (not target.is_relative_to(self.root) or not target.is_file()
                or path != target.relative_to(self.root).as_posix()):
            return None
        return target

    def source(self, path):
        if path not in self.parsed:
            target = self.checked_path(path)
            if target is None:
                return None
            self.parsed[path] = declarations(target.read_text(encoding="utf-8"))
        return self.parsed[path]

    def registered_tests(self):
        if self.registered is not None:
            return self.registered
        visited = set()
        stack = list(self.test_roots)
        while stack:
            relative = stack.pop()
            if relative in visited:
                continue
            parsed = self.source(relative)
            if parsed is None:
                continue
            visited.add(relative)
            for import_name in parsed[2]:
                if import_name.endswith(".zig"):
                    candidate = (Path(relative).parent / import_name).as_posix()
                else:
                    candidate = MODULE_ROOTS.get(import_name)
                if candidate is None:
                    continue
                target = self.checked_path(candidate)
                if target is not None:
                    stack.append(target.relative_to(self.root).as_posix())
        self.registered = visited
        return visited

    def validate(self, rows):
        problems = []
        for test_root in self.test_roots:
            if test_root not in self.build_roots:
                continue
            build_file, literal = self.build_roots[test_root]
            build_path = self.checked_path(build_file)
            # Build files are Zig sources, but check their own root registration
            # separately from whether the imported test file can be found.
            if build_path is None or literal not in build_path.read_text(encoding="utf-8"):
                problems.append(diag(test_root, "test_root_registration", f"{build_file} does not register {test_root}"))
        registered = self.registered_tests()
        for row in rows:
            record_id = row["id"]
            source = row.get("source")
            symbol = row.get("symbol")
            proof = row.get("proof")
            if bool(source) != bool(symbol):
                problems.append(diag(record_id, "source_pair", "source and symbol must be supplied together"))
            if source:
                parsed = self.source(source)
                if parsed is None:
                    problems.append(diag(record_id, "source_path", "source must be a repository-local Zig file"))
                elif not isinstance(symbol, str) or len(symbol.split(".")) > 2:
                    problems.append(diag(record_id, "source_declaration", "expected function or Type.method"))
                else:
                    qualifier, method = ("", symbol) if "." not in symbol else symbol.split(".")
                    if (qualifier, method) not in parsed[0]:
                        problems.append(diag(record_id, "source_declaration", f"{source} does not declare {symbol}"))
            if proof is None:
                continue
            if not isinstance(proof, dict):
                problems.append(diag(record_id, "proof_shape", "proof must be an object"))
                continue
            keys = set(proof)
            if keys - {"path", "symbol", "test"}:
                problems.append(diag(record_id, "proof_fields", f"unsupported proof fields: {sorted(keys - {'path', 'symbol', 'test'})}"))
            if ("symbol" in proof) == ("test" in proof):
                problems.append(diag(record_id, "proof_shape", "use exactly one of proof.symbol or proof.test"))
            name = proof.get("symbol", proof.get("test"))
            if not isinstance(name, str) or not name:
                problems.append(diag(record_id, "proof_shape", "proof must name a nonempty test"))
            path = proof.get("path")
            parsed = self.source(path)
            if parsed is None:
                problems.append(diag(record_id, "proof_path", "proof must be a repository-local Zig file"))
            else:
                if name not in parsed[1]:
                    problems.append(diag(record_id, "proof_declaration", f"{path} does not declare named test {name!r}"))
                if path not in registered:
                    problems.append(diag(record_id, "proof_reachability", f"{path} is not reachable from registered test roots"))
            if len(problems) >= 256:
                break
        return problems


def self_test():
    with tempfile.TemporaryDirectory(prefix="howl-protocol-evidence-") as directory:
        root = Path(directory)
        (root / "owner.zig").write_text(
            'const std = @import("std");\n'
            'pub const Owner = struct {\n'
            '    pub fn valid(self: *Owner) void { _ = self; }\n'
            '};\n'
            'fn topLevel() void {}\n'
            'const string = "fn phantom() void {} test \\"decoy\\" {}";\n'
            '// fn fake() void {}\n'
            '\\\\test "multiline decoy" {}\n'
            'test "live test" {}\n',
            encoding="utf-8",
        )
        (root / "wrong.zig").write_text('test "other file test" {}\n')
        (root / "tests.zig").write_text('const owner = @import("owner.zig");\ntest "registered" { _ = owner; }\n')
        (root / "test_root.zig").write_text('_ = @import("tests.zig");\n')
        evidence = Evidence(root, ("test_root.zig",), {})
        def row(symbol="Owner.valid", proof="live test", path="owner.zig", source="owner.zig"):
            return {"id": "fixture", "source": source, "symbol": symbol, "proof": {"path": path, "symbol": proof}}
        def check(expected, entry):
            rules = {item["rule"] for item in evidence.validate([entry])}
            assert rules == expected, (expected, rules, entry)
        check(set(), row())
        check(set(), row("topLevel"))
        check({"source_declaration"}, row("Owner.phantom"))
        check({"source_declaration"}, row("Other.valid"))
        check({"source_declaration"}, row("fake"))
        check({"proof_declaration"}, row(proof="decoy"))
        check({"proof_declaration"}, row(proof="multiline decoy"))
        check({"proof_declaration"}, row(proof="other file test"))
        check({"proof_reachability"}, row(path="wrong.zig", proof="other file test"))
        check({"source_path"}, row(source="../owner.zig"))
        check({"proof_path"}, row(path="../owner.zig"))
        check({"proof_fields"}, {**row(), "proof": {"path": "owner.zig", "symbol": "live test", "line": 999}})
        check({"proof_shape"}, {**row(), "proof": {"path": "owner.zig", "symbol": "live test", "test": "live test"}})
        with tempfile.TemporaryDirectory(prefix="howl-protocol-outside-") as outside:
            target = Path(outside) / "existing.zig"
            target.write_text('fn valid() void {}\n', encoding="utf-8")
            (root / "outside_link.zig").symlink_to(target)
            check({"source_path"}, row(source="outside_link.zig"))
        check({"proof_path"}, row(path="./owner.zig"))
        build_file = root / "build.zig"
        build_checks = {"test_root.zig": ("build.zig", 'b.path("test_root.zig")')}
        build_guard = Evidence(root, ("test_root.zig",), build_checks)
        assert {x["rule"] for x in build_guard.validate([row()])} == {"test_root_registration"}
        build_file.write_text('const root = b.path("test_root.zig");\\n', encoding="utf-8")
        assert build_guard.validate([row()]) == []
        return "16 positive/negative fixture cases passed"


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        print(self_test())
        return
    if len(sys.argv) != 2:
        raise SystemExit("usage: protocol_evidence.py ROOT_DIR | --self-test")
    records = json.load(sys.stdin)
    if not isinstance(records, list):
        raise SystemExit("expected normalized protocol record array")
    print(json.dumps(Evidence(sys.argv[1]).validate(records), ensure_ascii=False))


if __name__ == "__main__":
    main()
