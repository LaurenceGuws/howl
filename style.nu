#!/usr/bin/env -S nu

def default-roots [] {
  workspace-repos
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

def allowed-style-file [path: string] {
  $path =~ '\.(zig|java|md|nu|py)$'
}

def prefix-path [repo: string, path: string] {
  if $repo == '.' { $path } else { $"($repo)/($path)" }
}

def under-roots [path: string, roots: list<string>] {
  $roots | any {|root| $root == '.' or $path == $root or ($path | str starts-with $"($root)/") }
}

def touched-files [roots: list<string>] {
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
  {
    status: (if ($failures | is-empty) { 'clean' } else { 'fail' })
    touched_files: ($rows | length)
    blocking_files: ($failures | length)
    assertion_warnings: ($rows | where delta_asserts < 0 | length)
    failures: $failures
  }
}

def combined-deep-view [rows: list<any>, sort: string] {
  let repo_rows = (
    sort-rows (group-by-repo $rows) $sort
    | each {|row|
        {
          kind: 'repo'
          repo: $row.repo
          path: ''
          changed: $row.changed
          files: $row.files
          lines: $row.lines
          blank: $row.blank
          comments: $row.comments
          code: $row.code
          tests: $row.tests
          prod: $row.prod
          asserts: $row.asserts
          usizes: $row.usizes
          funcs: $row.funcs
          long_funcs: $row.long_funcs
          test_blocks: $row.test_blocks
        }
      }
  )

  let total_row = (
    summarize $rows
    | insert kind 'total'
    | insert path ''
    | insert changed ''
  )

  let file_rows = (
    sort-rows $rows $sort
    | each {|row|
        {
          kind: 'file'
          repo: $row.repo
          path: $row.path
          changed: $row.changed
          files: $row.files
          lines: $row.lines
          blank: $row.blank
          comments: $row.comments
          code: $row.code
          tests: $row.tests
          prod: $row.prod
          asserts: $row.asserts
          usizes: $row.usizes
          funcs: $row.funcs
          long_funcs: $row.long_funcs
          test_blocks: $row.test_blocks
        }
      }
  )

  $repo_rows | append $total_row | append $file_rows
}

def primary-mode [
  by_file: bool,
  by_repo: bool,
  deep: bool,
  touched_files: bool,
  touched_repos: bool,
  failures: bool
] {
  let selected = [
    { name: 'by-file', on: $by_file }
    { name: 'by-repo', on: $by_repo }
    { name: 'deep', on: $deep }
    { name: 'touched-files', on: $touched_files }
    { name: 'touched-repos', on: $touched_repos }
    { name: 'failures', on: $failures }
  ] | where on

  if ($selected | length) > 1 {
    error make {
      msg: 'pick one primary mode'
      label: {
        text: ($selected | get name | str join ', ')
        span: (metadata $selected).span
      }
    }
  }

  if ($selected | is-empty) {
    'default'
  } else {
    $selected.0.name
  }
}

def ensure-valid-refinements [mode: string, blame: bool, sort: string] {
  if $blame and ($mode == 'default' or $mode == 'failures' or $mode == 'touched-files' or $mode == 'touched-repos') {
    error make { msg: '--blame only applies to deep inspection modes' }
  }

  if $sort != 'prod' and ($mode == 'default' or $mode == 'failures' or $mode == 'touched-files' or $mode == 'touched-repos') {
    error make { msg: '--sort only applies to deep inspection modes' }
  }
}

def main [
  ...roots: string,
  --by-file(-a),
  --by-repo(-r),
  --deep(-d),
  --touched-files(-t),
  --touched-repos(-p),
  --failures(-f),
  --blame(-b),
  --sort(-s): string = 'prod'
] {
  let selected_roots = if ($roots | is-empty) { default-roots } else { $roots }
  let mode = (primary-mode $by_file $by_repo $deep $touched_files $touched_repos $failures)
  ensure-valid-refinements $mode $blame $sort
  let touched = (touched-files $selected_roots)
  let touched_rows = (scan-files $touched false 'HEAD')

  if $mode == 'touched-repos' {
    touched-repo-view $touched_rows
  } else if $mode == 'touched-files' {
    touched-files-view $touched_rows
  } else if $mode == 'failures' {
    failure-view $touched_rows
  } else if $mode == 'deep' or $mode == 'by-repo' or $mode == 'by-file' {
    let files = gather-files $selected_roots
    let rows = (scan-files $files $blame '')

    if $mode == 'deep' {
      combined-deep-view $rows $sort
    } else if $mode == 'by-repo' {
      let repo_rows = (sort-rows (group-by-repo $rows) $sort)
      $repo_rows | append (summarize $rows)
    } else {
      let file_rows = (sort-rows $rows $sort)
      $file_rows | append (summarize $rows)
    }
  } else {
    checkpoint-summary $touched_rows
  }
}
