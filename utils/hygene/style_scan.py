import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass, asdict


ASSERT_RE = re.compile(r"\bassert\s*\(")
USIZE_RE = re.compile(r"\busize\b")
FN_RE = re.compile(r"\bfn\b")


RELEVANT_BASELINE_FIELDS = (
    "asserts",
    "usizes",
    "funcs",
    "long_funcs",
    "test_blocks",
)


@dataclass
class Counts:
    files: int = 0
    lines: int = 0
    blank: int = 0
    comments: int = 0
    code: int = 0
    tests: int = 0
    prod: int = 0
    asserts: int = 0
    usizes: int = 0
    funcs: int = 0
    long_funcs: int = 0
    test_blocks: int = 0


def main() -> int:
    blame = False
    baseline_rev: str | None = None
    files: list[str] = []
    args = iter(sys.argv[1:])
    for arg in args:
        if arg == "--blame":
            blame = True
        elif arg == "--baseline":
            baseline_rev = next(args)
        else:
            files.append(arg)

    rows = [scan_file(path, blame, baseline_rev) for path in files]
    json.dump(rows, sys.stdout)
    return 0


def scan_file(path: str, blame: bool, baseline_rev: str | None) -> dict:
    source = read_source(path)

    counts = count_source(path, source)
    row = {
        "path": normalize(path),
        "repo": repo_name(path),
        "changed": git_last_changed(path) if blame else "",
        **asdict(counts),
    }
    if baseline_rev is not None:
        row |= baseline_metrics(path, baseline_rev)
    return row


def read_source(path: str) -> str:
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        return handle.read()


def baseline_metrics(path: str, rev: str) -> dict:
    source = baseline_source(path, rev)
    counts = Counts() if source is None else count_source(path, source)
    metrics: dict[str, int] = {}
    for field in RELEVANT_BASELINE_FIELDS:
        value = getattr(counts, field)
        metrics[f"base_{field}"] = value
        metrics[f"delta_{field}"] = getattr(count_source(path, read_source(path)), field) - value
    return metrics


def count_source(path: str, source: str) -> Counts:
    counts = Counts(files=1)
    lines = source.splitlines()
    test_lines = top_level_test_lines(source) if path.endswith(".zig") else set()
    path_is_test = is_test_path(path)

    counts.asserts = len(ASSERT_RE.findall(strip_comments_and_strings(source))) if path.endswith(".zig") else 0
    counts.usizes = len(USIZE_RE.findall(strip_comments_and_strings(source))) if path.endswith(".zig") else 0
    if path.endswith(".zig"):
        funcs, long_funcs = count_functions(source)
        counts.funcs = funcs
        counts.long_funcs = long_funcs
        counts.test_blocks = count_test_blocks(source)

    for index, line in enumerate(lines, start=1):
        counts.lines += 1
        stripped = line.strip()
        if stripped == "":
            counts.blank += 1
            continue

        if is_comment_line(path, stripped):
            counts.comments += 1
            continue

        counts.code += 1
        if path_is_test or index in test_lines:
            counts.tests += 1

    counts.prod = counts.code - counts.tests
    return counts


def normalize(path: str) -> str:
    if path.startswith("./"):
        return path[2:]
    return path


def repo_name(path: str) -> str:
    root = git_repo_root(path)
    if root is None:
        norm = normalize(path)
        parts = norm.split("/")
        return parts[0] if len(parts) > 1 else "root"

    repo = os.path.basename(root)
    parent = os.path.basename(os.path.dirname(root))
    if parent == "howl-hosts":
        return f"howl-hosts/{repo}"
    if repo.startswith("howl-"):
        return repo
    return "root"


def is_test_path(path: str) -> bool:
    parts = normalize(path).split("/")
    return "test" in parts or "fuzz" in parts


def is_comment_line(path: str, stripped: str) -> bool:
    if path.endswith(".md"):
        return True
    if stripped.startswith("//"):
        return True
    if path.endswith((".py", ".nu")) and stripped.startswith("#"):
        return True
    return False


def git_last_changed(path: str) -> str:
    directory = os.path.dirname(path) or "."
    base = os.path.basename(path)
    result = subprocess.run(
        ["git", "-C", directory, "log", "-1", "--format=%ai", "--", base],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return ""
    return result.stdout.strip()[:19]


def baseline_source(path: str, rev: str) -> str | None:
    root = git_repo_root(path)
    if root is None:
        return None
    rel = os.path.relpath(os.path.abspath(path), root).replace(os.sep, "/")
    result = subprocess.run(
        ["git", "-C", root, "show", f"{rev}:{rel}"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return None
    return result.stdout


def git_repo_root(path: str) -> str | None:
    directory = os.path.dirname(os.path.abspath(path)) or "."
    result = subprocess.run(
        ["git", "-C", directory, "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return None
    return result.stdout.strip()


def strip_comments_and_strings(source: str) -> str:
    out: list[str] = []
    i = 0
    in_string = False
    in_char = False
    in_comment = False
    while i < len(source):
        c = source[i]
        if c == "\n":
            in_comment = False
            out.append(c)
            i += 1
            continue
        if in_comment:
            i += 1
            continue
        if in_string:
            if c == "\\" and i + 1 < len(source):
                i += 2
                continue
            if c == '"':
                in_string = False
            i += 1
            continue
        if in_char:
            if c == "\\" and i + 1 < len(source):
                i += 2
                continue
            if c == "'":
                in_char = False
            i += 1
            continue
        if c == "/" and i + 1 < len(source) and source[i + 1] == "/":
            in_comment = True
            i += 2
            continue
        if c == '"':
            in_string = True
            i += 1
            continue
        if c == "'":
            in_char = True
            i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def top_level_test_lines(source: str) -> set[int]:
    lines: set[int] = set()
    i = 0
    line = 1
    brace_depth = 0
    in_string = False
    in_char = False
    in_comment = False
    while i < len(source):
        c = source[i]
        if c == "\n":
            in_comment = False
            line += 1
            i += 1
            continue
        if in_comment:
            i += 1
            continue
        if in_string:
            if c == "\\" and i + 1 < len(source):
                i += 2
                continue
            if c == '"':
                in_string = False
            i += 1
            continue
        if in_char:
            if c == "\\" and i + 1 < len(source):
                i += 2
                continue
            if c == "'":
                in_char = False
            i += 1
            continue
        if c == "/" and i + 1 < len(source) and source[i + 1] == "/":
            in_comment = True
            i += 2
            continue
        if c == '"':
            in_string = True
            i += 1
            continue
        if c == "'":
            in_char = True
            i += 1
            continue
        if c == "{":
            brace_depth += 1
            i += 1
            continue
        if c == "}":
            brace_depth -= 1
            i += 1
            continue
        if brace_depth == 0 and source.startswith("test", i) and word_boundary(source, i, 4):
            start_line = line
            end = find_body_end(source, find_body_start(source, i + 4))
            end_line = source.count("\n", 0, end) + 1
            for current in range(start_line, end_line + 1):
                lines.add(current)
            i = end
            line = end_line
            continue
        i += 1
    return lines


def count_test_blocks(source: str) -> int:
    return len(re.findall(r"(?m)^\s*test\b", strip_comments_and_strings(source)))


def count_functions(source: str) -> tuple[int, int]:
    clean = strip_comments_and_strings(source)
    count = 0
    long_count = 0
    index = 0
    while True:
        match = FN_RE.search(clean, index)
        if match is None:
            break
        count += 1
        start = find_body_start(clean, match.end())
        if start is None:
            index = match.end()
            continue
        end = find_body_end(clean, start)
        start_line = clean.count("\n", 0, match.start()) + 1
        end_line = clean.count("\n", 0, end) + 1
        if end_line - start_line + 1 > 70:
            long_count += 1
        index = end
    return count, long_count


def find_body_start(source: str, start: int) -> int | None:
    for index in range(start, len(source)):
        c = source[index]
        if c == "{":
            return index
        if c == ";":
            return None
    return None


def find_body_end(source: str, start: int | None) -> int:
    if start is None:
        return len(source)
    depth = 1
    index = start + 1
    while index < len(source):
        c = source[index]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return index + 1
        index += 1
    return len(source)


def word_boundary(source: str, index: int, length: int) -> bool:
    prev_ok = index == 0 or not ident_char(source[index - 1])
    next_index = index + length
    next_ok = next_index >= len(source) or not ident_char(source[next_index])
    return prev_ok and next_ok


def ident_char(char: str) -> bool:
    return char.isalnum() or char == "_"


if __name__ == "__main__":
    raise SystemExit(main())
