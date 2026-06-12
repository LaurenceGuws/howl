#!/usr/bin/env python3
import argparse
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path


sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parent
SCAN_PATH = ROOT / "utils" / "hygene" / "style_scan.py"


def load_scanner():
    spec = importlib.util.spec_from_file_location("style_scan", SCAN_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"failed to load {SCAN_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def main() -> int:
    parser = argparse.ArgumentParser(description="Emit Howl style metrics as full machine-readable records.")
    parser.add_argument("roots", nargs="*", help="Repo/path roots to scan. Defaults to howl-* repos.")
    parser.add_argument("--by-file", "-a", action="store_true", help="Emit file rows with a leading sum row.")
    parser.add_argument("--by-repo", "-r", action="store_true", help="Emit repo summary rows.")
    parser.add_argument("--touched-files", "-t", action="store_true", help="Emit baseline deltas for touched files.")
    parser.add_argument("--touched-repos", "-p", action="store_true", help="Emit baseline deltas summarized by repo.")
    parser.add_argument("--failures", "-f", action="store_true", help="Emit touched files that added usize or long functions.")
    parser.add_argument("--blame", "-b", action="store_true", help="Include last changed timestamp per file.")
    parser.add_argument("--sort", "-s", default="prod", help="Sort field. Defaults to prod.")
    parser.add_argument("--format", choices=("json", "ndjson", "paths"), default="json", help="Output format. Defaults to json.")
    args = parser.parse_args()

    os.chdir(ROOT)
    scanner = load_scanner()
    roots = args.roots if args.roots else default_roots()

    if args.touched_repos:
        rows = scan_files(scanner, touched_paths(roots), False, "HEAD")
        output_rows = touched_repo_view(rows)
    elif args.touched_files or args.failures:
        rows = scan_files(scanner, touched_paths(roots), False, "HEAD")
        output_rows = failure_view(rows) if args.failures else touched_files_view(rows)
    else:
        rows = sort_rows(scan_files(scanner, gather_files(roots), args.blame, None), args.sort)
        if args.by_repo and not args.by_file:
            output_rows = repo_summary_view(rows)
        else:
            output_rows = [summarize(rows)] + rows

    write_output(output_rows, args.format)
    return 0


def default_roots() -> list[str]:
    return [entry.name for entry in ROOT.iterdir() if entry.is_dir() and entry.name.startswith("howl-")]


def gather_files(roots: list[str]) -> list[str]:
    command = [
        "rg",
        "--files",
        *roots,
        "-g", "*.zig",
        "-g", "*.java",
        "-g", "*.md",
        "-g", "*.nu",
        "-g", "*.py",
        "-g", "!**/.git/**",
        "-g", "!**/.zig-cache/**",
        "-g", "!**/zig-out/**",
        "-g", "!**/zig-pkg/**",
        "-g", "!**/vendor/**",
    ]
    return sorted(unique(run_lines(command)))


def touched_paths(roots: list[str]) -> list[str]:
    paths: list[str] = []
    for repo in default_roots():
        changed = run_lines(["git", "-C", repo, "diff", "--name-only", "--diff-filter=ACMR", "HEAD"])
        untracked = run_lines(["git", "-C", repo, "ls-files", "--others", "--exclude-standard"])
        for path in unique(changed + untracked):
            prefixed = f"{repo}/{path}"
            if allowed_style_file(prefixed) and under_roots(prefixed, roots):
                paths.append(prefixed)
    return sorted(unique(paths))


def scan_files(scanner, files: list[str], blame: bool, baseline: str | None) -> list[dict]:
    return [scanner.scan_file(path, blame, baseline) for path in files]


def allowed_style_file(path: str) -> bool:
    return path.endswith((".zig", ".java", ".md", ".nu", ".py"))


def under_roots(path: str, roots: list[str]) -> bool:
    for root in roots:
        if root == "." or path == root or path.startswith(f"{root}/"):
            return True
    return False


def sort_rows(rows: list[dict], field: str) -> list[dict]:
    if field in ("file", "path"):
        return sorted(rows, key=lambda row: row["path"])
    if field == "repo":
        return sorted(rows, key=lambda row: (row["repo"], row["path"]))
    return sorted(rows, key=lambda row: row.get(field, 0), reverse=True)


def summarize(rows: list[dict]) -> dict:
    fields = (
        "files",
        "lines",
        "blank",
        "comments",
        "code",
        "tests",
        "prod",
        "proof",
        "test_hooks",
        "benchmark",
        "asserts",
        "usizes",
        "anytypes",
        "casts",
        "funcs",
        "long_funcs",
        "test_blocks",
        "structs_top_level",
        "bucket_named_structs",
        "bucket_struct_lines",
    )
    row = {"path": "(sum)", "repo": "TOTAL", "changed": ""}
    for field in fields:
        row[field] = sum(item.get(field, 0) for item in rows)
    return row


def repo_summary_view(rows: list[dict]) -> list[dict]:
    groups: dict[str, list[dict]] = {}
    for row in rows:
        groups.setdefault(row["repo"], []).append(row)
    return [summarize(rows)] + [summarize_repo(repo, groups[repo]) for repo in sorted(groups)]


def summarize_repo(repo: str, rows: list[dict]) -> dict:
    row = summarize(rows)
    row["repo"] = repo
    return row


def touched_files_view(rows: list[dict]) -> list[dict]:
    return sorted(
        [
            {
                "path": row["path"],
                "repo": row["repo"],
                "usizes": row["usizes"],
                "usizes_added": max(row.get("delta_usizes", 0), 0),
                "long_funcs": row["long_funcs"],
                "long_funcs_added": max(row.get("delta_long_funcs", 0), 0),
                "asserts": row["asserts"],
                "asserts_removed": max(-row.get("delta_asserts", 0), 0),
            }
            for row in rows
        ],
        key=lambda row: row["path"],
    )


def touched_repo_view(rows: list[dict]) -> list[dict]:
    groups: dict[str, list[dict]] = {}
    for row in rows:
        groups.setdefault(row["repo"], []).append(row)
    output: list[dict] = []
    for repo in sorted(groups):
        items = groups[repo]
        output.append(
            {
                "repo": repo,
                "touched_files": len(items),
                "usizes_added": sum(max(row.get("delta_usizes", 0), 0) for row in items),
                "long_funcs_added": sum(max(row.get("delta_long_funcs", 0), 0) for row in items),
                "asserts_removed": sum(max(-row.get("delta_asserts", 0), 0) for row in items),
            }
        )
    return output


def failure_view(rows: list[dict]) -> list[dict]:
    return [row for row in touched_files_view(rows) if row["usizes_added"] > 0 or row["long_funcs_added"] > 0]


def write_output(rows: list[dict], output_format: str) -> None:
    if output_format == "json":
        json.dump(rows, sys.stdout, indent=2)
        sys.stdout.write("\n")
    elif output_format == "ndjson":
        for row in rows:
            sys.stdout.write(json.dumps(row, separators=(",", ":")) + "\n")
    else:
        for row in rows:
            if "path" in row:
                sys.stdout.write(row["path"] + "\n")


def run_lines(command: list[str]) -> list[str]:
    result = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode != 0:
        return []
    return [line for line in result.stdout.splitlines() if line]


def unique(items: list[str]) -> list[str]:
    seen: set[str] = set()
    output: list[str] = []
    for item in items:
        if item in seen:
            continue
        seen.add(item)
        output.append(item)
    return output


if __name__ == "__main__":
    raise SystemExit(main())
