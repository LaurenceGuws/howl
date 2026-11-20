# In-memory inventory corruption tests. Source protocol_coverage.nu before this.
# No live catalogue/manifest mutation, no repository checkout or network.
let catalogue = (open protocol_coverage.yml)
let inventory = (open protocol_coverage_inventory.yml)

def require-rule [diagnostics: list<record>, rule: string] {
  if $rule not-in ($diagnostics | get rule) {
    error make {msg: $"expected inventory diagnostic ($rule), got ($diagnostics | to json -r)"}
  }
}

let accepted = (protocol inventory diagnostics $catalogue $inventory)
if ($accepted | length) != 0 {
  error make {msg: $"accepted inventory failed: ($accepted | to json -r)"}
}
let reviewed_ids = {
  osc52_clipboard: [windows_terminal.osc52.set windows_terminal.osc52.query_ignored]
  da1_clipboard_write: [windows_terminal.da1.clipboard_write_advertisement]
  osc9_progress: [windows_terminal.osc9.task_progress]
}
for group in ($reviewed_ids | transpose name ids) {
  let observed = ($catalogue.references.windows_terminal.groups | get $group.name | get records | columns | sort)
  if $observed != ($group.ids | sort) {
    error make {msg: $"Windows reference group ($group.name) differs from the reviewed command IDs"}
  }
}
let ghostty_ids = ($catalogue.references.ghostty.groups.osc7501_status.records | columns | sort)
if $ghostty_ids != ([ghostty.osc7501.status_query ghostty.osc7501.status_report] | sort) {
  error make {msg: "Ghostty OSC 7501 group differs from the two reviewed branch IDs"}
}
let kitty_delta_ids = {
  dispatch_osc_program_status: [kitty_delta.osc.program_status]
  indexed_graphics_formats: [kitty_delta.graphics.format_indexed8 kitty_delta.graphics.format_indexed16]
  transient_usage_hint: [kitty_delta.graphics.usage_hint_transient]
}
for group in ($kitty_delta_ids | transpose name ids) {
  let observed = ($catalogue.references.kitty_delta.groups | get $group.name | get records | columns | sort)
  if $observed != ($group.ids | sort) {
    error make {msg: $"Kitty delta group ($group.name) differs from the reviewed new semantic IDs"}
  }
}

let bad_total = ($inventory | update total_records 673)
require-rule (protocol inventory diagnostics $catalogue $bad_total) inventory_total

let bad_pin = ($catalogue | update references.windows_terminal.revision "not-the-pinned-commit")
require-rule (protocol inventory diagnostics $bad_pin $inventory) reference_pin

let wrong_delta_baseline = ($inventory | update references.kitty_delta.base_revision "not-the-baseline")
require-rule (protocol inventory diagnostics $catalogue $wrong_delta_baseline) delta_baseline
let wrong_delta_scope = ($catalogue | update references.kitty_delta.kind snapshot)
require-rule (protocol inventory diagnostics $wrong_delta_scope $inventory) reference_scope
let wrong_delta_pin = ($catalogue | update references.kitty_delta.revision "moving-head")
require-rule (protocol inventory diagnostics $wrong_delta_pin $inventory) reference_pin

let incomplete_roster = ($inventory | update references.ghostty.group_ids {})
require-rule (protocol inventory diagnostics $catalogue $incomplete_roster) branch_roster_scope

let original_query = ($catalogue.references.windows_terminal.groups.osc52_clipboard.records
  | get "windows_terminal.osc52.query_ignored")
let substituted = ($catalogue.references.windows_terminal.groups.osc52_clipboard.records
  | reject "windows_terminal.osc52.query_ignored"
  | insert "windows_terminal.osc52.impostor" $original_query)
let wrong_ids = ($catalogue | update references.windows_terminal.groups.osc52_clipboard.records $substituted)
require-rule (protocol inventory diagnostics $wrong_ids $inventory) branch_roster

let bad_count = ($inventory | update references.windows_terminal.groups.osc52_clipboard 3)
require-rule (protocol inventory diagnostics $catalogue $bad_count) reference_count
require-rule (protocol inventory diagnostics $catalogue $bad_count) inventory_total

let fewer = ($catalogue | update references.windows_terminal.groups
  ($catalogue.references.windows_terminal.groups | reject osc9_progress))
require-rule (protocol inventory diagnostics $fewer $inventory) group_inventory

let too_many = ($catalogue | update references.windows_terminal.groups
  ($catalogue.references.windows_terminal.groups | insert unexpected $catalogue.references.windows_terminal.groups.osc9_progress))
require-rule (protocol inventory diagnostics $too_many $inventory) group_inventory

let seed_group = {
  source: "terminal/adapter/adaptDispatch.cpp"
  line: 3558
  census: {semantic_branches: 2}
  recognition: implemented
  records: {
    "fixture.first": {raw: "OSC fixture;1", effect: "synthetic branch", howl: {support: unassessed}}
    "fixture.second": {raw: "OSC fixture;2", effect: "synthetic branch", howl: {support: unassessed}}
  }
}
let approved_cat = ($catalogue | update references.windows_terminal.groups
  ($catalogue.references.windows_terminal.groups | insert accepted_future $seed_group))
let expanded_ref = ($inventory.references.windows_terminal
  | update total_records 6
  | update groups ($inventory.references.windows_terminal.groups | insert accepted_future 2)
  | update group_ids ($inventory.references.windows_terminal.group_ids | insert accepted_future ["fixture.first" "fixture.second"]))
let approved_inventory = ($inventory
  | update references.windows_terminal $expanded_ref
  | update total_groups 42
  | update total_records 674)
let approved = (protocol inventory diagnostics $approved_cat $approved_inventory)
if ($approved | length) != 0 {
  error make {msg: $"correctly approved future group failed: ($approved | to json -r)"}
}

let incomplete = ($approved_cat | update references.windows_terminal.groups.accepted_future.records
  ($approved_cat.references.windows_terminal.groups.accepted_future.records | reject "fixture.second"))
require-rule (protocol inventory diagnostics $incomplete $approved_inventory) branch_inventory

print "Protocol inventory: accepted/rejected subtree fixtures passed"
