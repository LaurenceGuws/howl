#!/usr/bin/env -S nu

def default-roots [] {
  let top = (ls | where type == dir and name =~ '^howl-' | get name)
  let hosts = (ls howl-hosts | where type == dir and name =~ '^howl-' | get name | each {|it| $"howl-hosts/($it)" })
  $top | append $hosts
}

def gather-files [roots: list<string>] {
  $roots
  | each {|root|
      (do -i {
        ^rg --files $root -g '*.zig' -g '*.java' -g '*.md' -g '!**/.git/**' -g '!**/.zig-cache/**' -g '!**/zig-out/**' -g '!**/zig-pkg/**' -g '!**/vendor/**'
      } | lines)
    }
  | flatten
  | uniq
}

def sort-rows [rows: list<any>, field: string] {
  if $field == 'file' or $field == 'path' {
    $rows | sort-by path
  } else if $field == 'repo' {
    $rows | sort-by repo
  } else {
    $rows | sort-by {|row| $row | get $field } --reverse
  }
}

def sum-field [rows: list<any>, field: string] {
  $rows | get $field | math sum
}

def summarize [rows: list<any>] {
  {
    repo: 'TOTAL'
    files: (sum-field $rows files)
    lines: (sum-field $rows lines)
    blank: (sum-field $rows blank)
    comments: (sum-field $rows comments)
    code: (sum-field $rows code)
    tests: (sum-field $rows tests)
    prod: (sum-field $rows prod)
    asserts: (sum-field $rows asserts)
    usizes: (sum-field $rows usizes)
    funcs: (sum-field $rows funcs)
    long_funcs: (sum-field $rows long_funcs)
    test_blocks: (sum-field $rows test_blocks)
  }
}

def group-by-repo [rows: list<any>] {
  $rows
  | group-by repo
  | transpose repo rows
  | each {|group|
      let items = $group.rows
      {
        repo: $group.repo
        files: (sum-field $items files)
        lines: (sum-field $items lines)
        blank: (sum-field $items blank)
        comments: (sum-field $items comments)
        code: (sum-field $items code)
        tests: (sum-field $items tests)
        prod: (sum-field $items prod)
        asserts: (sum-field $items asserts)
        usizes: (sum-field $items usizes)
        funcs: (sum-field $items funcs)
        long_funcs: (sum-field $items long_funcs)
        test_blocks: (sum-field $items test_blocks)
        changed: ($items | get changed | where $it != '' | sort | last | default '')
      }
    }
}

def main [
  ...roots: string,
  --by-file(-a),
  --by-repo(-r),
  --blame(-b),
  --sort(-s): string = 'prod'
] {
  let selected_roots = if ($roots | is-empty) { default-roots } else { $roots }
  let files = gather-files $selected_roots
  let rows = (
    ^python utils/hygene/style_scan.py ...(if $blame { ['--blame'] } else { [] }) ...$files
    | from json
  )

  if $by_repo and $by_file {
    let repo_rows = (sort-rows (group-by-repo $rows) $sort)
    let file_rows = (sort-rows $rows $sort)
    {
      repos: $repo_rows
      files: $file_rows
      total: (summarize $rows)
    }
  } else if $by_repo {
    let repo_rows = (sort-rows (group-by-repo $rows) $sort)
    $repo_rows | append (summarize $rows)
  } else if $by_file {
    let file_rows = (sort-rows $rows $sort)
    $file_rows | append (summarize $rows)
  } else {
    summarize $rows
  }
}
