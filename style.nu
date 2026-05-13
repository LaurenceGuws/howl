#!/usr/bin/env -S nu

def workspace-repos [] {
  let top = (
    ls
    | where type == dir and name =~ '^howl-' and name != 'howl-hosts'
    | get name
  )
  let hosts = (
    ls howl-hosts
    | where type == dir and name !~ '/vendor$'
    | get name
  )
  ['.'] | append $top | append $hosts
}

def default-roots [] {
  workspace-repos
}

def prefix-path [repo: string, path: string] {
  if $repo == '.' { $path } else { $"($repo)/($path)" }
}

def under-roots [path: string, roots: list<string>] {
  $roots | any {|root| $root == '.' or $path == $root or ($path | str starts-with $"($root)/") }
}

def allowed-style-file [path: string] {
  $path =~ '\.(zig|java|md|nu|py)$'
}

def gather-files [roots: list<string>] {
  $roots
  | each {|root|
      (do -i {
        ^rg --files $root -g '*.zig' -g '*.java' -g '*.md' -g '*.nu' -g '*.py' -g '!**/.git/**' -g '!**/.zig-cache/**' -g '!**/zig-out/**' -g '!**/zig-pkg/**' -g '!**/vendor/**'
      } | lines)
    }
  | flatten
  | uniq
}

def touched-paths [roots: list<string>] {
  workspace-repos
  | each {|repo|
      let changed = (do -i { ^git -C $repo diff --name-only --diff-filter=ACMR HEAD } | lines)
      let untracked = (do -i { ^git -C $repo ls-files --others --exclude-standard } | lines)
      $changed
      | append $untracked
      | uniq
      | each {|path| prefix-path $repo $path }
    }
  | flatten
  | where {|path| allowed-style-file $path }
  | where {|path| under-roots $path $roots }
  | uniq
}

def scan-files [files: list<string>, blame: bool, baseline: string] {
  if ($files | is-empty) {
    []
  } else {
    ^python utils/hygene/style_scan.py ...(if $blame { ['--blame'] } else { [] }) ...(if $baseline == '' { [] } else { ['--baseline', $baseline] }) ...$files
    | from json
  }
}

def sort-rows [rows: list<any>, field: string] {
  if $field == 'file' or $field == 'path' {
    $rows | sort-by path
  } else if $field == 'repo' {
    $rows | sort-by repo path
  } else {
    $rows | sort-by {|row| $row | get $field } --reverse
  }
}

def sum-field [rows: list<any>, field: string] {
  $rows | get $field | math sum
}

def summarize [rows: list<any>] {
  {
    path: '(sum)'
    repo: 'TOTAL'
    changed: ''
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

def summarize-repo [repo: string, rows: list<any>] {
  summarize $rows
  | update repo $repo
}

def group-by-repo [rows: list<any>] {
  $rows
  | group-by repo
  | transpose repo rows
  | sort-by repo
}

def repo-summary-view [rows: list<any>] {
  let repo_rows = (
    group-by-repo $rows
    | each {|group| summarize-repo $group.repo $group.rows }
  )
  ([ (summarize $rows) ] | append $repo_rows)
}

def positive-sum [rows: list<any>, field: string] {
  $rows | get $field | each {|value| if $value > 0 { $value } else { 0 } } | math sum
}

def negative-sum [rows: list<any>, field: string] {
  $rows | get $field | each {|value| if $value < 0 { 0 - $value } else { 0 } } | math sum
}

def touched-files-view [rows: list<any>] {
  $rows
  | each {|row|
      {
        path: $row.path
        repo: $row.repo
        usizes: $row.usizes
        usizes_added: (if $row.delta_usizes > 0 { $row.delta_usizes } else { 0 })
        long_funcs: $row.long_funcs
        long_funcs_added: (if $row.delta_long_funcs > 0 { $row.delta_long_funcs } else { 0 })
        asserts: $row.asserts
        asserts_removed: (if $row.delta_asserts < 0 { 0 - $row.delta_asserts } else { 0 })
      }
    }
  | sort-by path
}

def touched-repo-view [rows: list<any>] {
  $rows
  | group-by repo
  | transpose repo rows
  | each {|group|
      let items = $group.rows
      {
        repo: $group.repo
        touched_files: ($items | length)
        usizes_added: (positive-sum $items delta_usizes)
        long_funcs_added: (positive-sum $items delta_long_funcs)
        asserts_removed: (negative-sum $items delta_asserts)
      }
    }
  | sort-by repo
}

def failure-view [rows: list<any>] {
  touched-files-view $rows
  | where usizes_added > 0 or long_funcs_added > 0
}

def checkpoint-summary [rows: list<any>] {
  let failures = (failure-view $rows)
  [{
    status: (if ($failures | is-empty) { 'clean' } else { 'fail' })
    touched_files: ($rows | length)
    blocking_files: ($failures | length)
    assertion_warnings: ($rows | where delta_asserts < 0 | length)
  }]
}

def print-table [rows: list<any>] {
  if ($rows | is-empty) {
    print 'empty'
  } else {
    print ($rows | table)
  }
}

def print-repo-file-tables [rows: list<any>] {
  if ($rows | is-empty) {
    print 'empty'
  } else {
    group-by-repo $rows
    | each {|group|
        print $"## ($group.repo)"
        print (([ (summarize-repo $group.repo $group.rows) ] | append $group.rows) | table)
        print ''
      }
    | ignore
  }
}

def main [
  ...roots: string,
  --by-file(-a),
  --by-repo(-r),
  --touched-files(-t),
  --touched-repos(-p),
  --failures(-f),
  --blame(-b),
  --sort(-s): string = 'prod'
] {
  let selected_roots = if ($roots | is-empty) { default-roots } else { $roots }

  if $touched_repos {
    let touched_rows = (scan-files (touched-paths $selected_roots) false 'HEAD')
    print-table (touched-repo-view $touched_rows)
  } else if $touched_files or $failures {
    let touched_rows = (scan-files (touched-paths $selected_roots) false 'HEAD')
    let rows = if $failures { failure-view $touched_rows } else { touched-files-view $touched_rows }
    if $by_repo {
      print-repo-file-tables $rows
    } else {
      print-table $rows
    }
  } else if $by_file or $by_repo or $blame or $sort != 'prod' {
    let rows = (sort-rows (scan-files (gather-files $selected_roots) $blame '') $sort)
    if $by_repo and $by_file {
      print-repo-file-tables $rows
    } else if $by_repo {
      print-table (repo-summary-view $rows)
    } else {
      print-table ([ (summarize $rows) ] | append $rows)
    }
  } else {
    let touched_rows = (scan-files (touched-paths $selected_roots) false 'HEAD')
    print-table (checkpoint-summary $touched_rows)
  }
}
