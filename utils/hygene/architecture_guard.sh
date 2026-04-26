#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
allowlist_file="$script_dir/architecture_guard.allowlist"

usage() {
  cat <<'EOF'
usage: architecture_guard.sh [--allowlist FILE] [repo ...]

Checks each repo for:
  - missing //! file headers in src/**/*.zig
  - forbidden source filename patterns (uppercase or hyphen)
  - forbidden milestone/ticket labels in new test names
  - forbidden compatibility patterns: compat[^ib]|fallback|workaround|shim

Exit codes:
  0  no violations
  1  policy violation(s) found
  2  usage or configuration error
EOF
}

allowlist_match() {
  local file_path="$1"
  local test_name="$2"

  [[ -f "$allowlist_file" ]] || return 1

  while IFS='|' read -r path_re name_re; do
    path_re="${path_re#${path_re%%[![:space:]]*}}"
    path_re="${path_re%${path_re##*[![:space:]]}}"
    name_re="${name_re#${name_re%%[![:space:]]*}}"
    name_re="${name_re%${name_re##*[![:space:]]}}"

    [[ -z "$path_re" || "${path_re:0:1}" == "#" ]] && continue
    [[ -z "$name_re" ]] && continue

    if [[ "$file_path" =~ $path_re ]] && [[ "$test_name" =~ $name_re ]]; then
      return 0
    fi
  done < "$allowlist_file"

  return 1
}

check_file_header() {
  local file_path="$1"

  local first_nonempty
  first_nonempty="$(awk 'NF { print; exit }' "$file_path" || true)"
  if [[ -z "$first_nonempty" ]]; then
    echo "  $file_path: missing //! header (file is empty)"
    return 1
  fi

  if [[ "$first_nonempty" != '//!'* ]]; then
    echo "  $file_path: missing //! file header"
    return 1
  fi

  return 0
}

check_test_names() {
  local file_path="$1"
  local repo_violations="$2"

  while IFS=: read -r line_no line_text; do
    local test_name
    if [[ "$line_text" =~ ^[[:space:]]*test[[:space:]]+\"([^\"]+)\" ]]; then
      test_name="${BASH_REMATCH[1]}"
      if [[ "$test_name" =~ (M[0-9]+|[A-Z]{2,}-[A-Z0-9-]+) ]] && ! allowlist_match "$file_path" "$test_name"; then
        echo "  $file_path:$line_no: forbidden ticket/milestone tag in test name: $test_name"
        repo_violations=$((repo_violations + 1))
      fi
    fi
  done < <(rg -n --no-heading '^[[:space:]]*test[[:space:]]+"[^"]+"' "$file_path" || true)

  echo "$repo_violations"
}

check_repo() {
  local repo_path="$1"
  local src_dir="$repo_path/src"
  local repo_name
  repo_name="$(basename "$repo_path")"
  local repo_violations=0
  local file_count=0

  if [[ ! -d "$src_dir" ]]; then
    echo "[$repo_name] FAIL: missing src/ directory"
    return 1
  fi

  while IFS= read -r -d '' file_path; do
    file_count=$((file_count + 1))

    local rel_path="${file_path#"$repo_path"/}"
    local base_name
    base_name="$(basename "$file_path")"

    if [[ "$base_name" =~ [A-Z-] ]]; then
      echo "  $rel_path: forbidden source filename pattern"
      repo_violations=$((repo_violations + 1))
    fi

    if ! check_file_header "$file_path"; then
      repo_violations=$((repo_violations + 1))
    fi

    local test_violation_count
    test_violation_count="$(check_test_names "$file_path" 0)"
    if [[ "$test_violation_count" != "0" ]]; then
      repo_violations=$((repo_violations + test_violation_count))
    fi
  done < <(find "$src_dir" -type f -name '*.zig' -print0)

  while IFS= read -r match_line; do
    echo "  ${match_line#"$repo_path"/}"
    repo_violations=$((repo_violations + 1))
  done < <(rg -n --no-heading -g '*.zig' -e 'compat[^ib]|fallback|workaround|shim' "$src_dir" || true)

  if [[ "$repo_violations" -eq 0 ]]; then
    echo "[$repo_name] PASS: $file_count Zig files checked, 0 violations"
    return 0
  fi

  echo "[$repo_name] FAIL: $repo_violations violation(s) across $file_count Zig files"
  return 1
}

main() {
  local repos=()

  while (($#)); do
    case "$1" in
      --allowlist)
        if (($# < 2)); then
          echo "error: --allowlist requires a file path" >&2
          usage >&2
          exit 2
        fi
        allowlist_file="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        repos+=("$1")
        shift
        ;;
    esac
  done

  if [[ "${#repos[@]}" -eq 0 ]]; then
    repos+=(".")
  fi

  local failures=0
  for repo in "${repos[@]}"; do
    if ! check_repo "$repo"; then
      failures=$((failures + 1))
    fi
  done

  if [[ "$failures" -eq 0 ]]; then
    echo "architecture_guard: PASS"
    exit 0
  fi

  echo "architecture_guard: FAIL ($failures repo(s) with violations)" >&2
  exit 1
}

main "$@"
