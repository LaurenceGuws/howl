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

let bad_total = ($inventory | update total_records 667)
require-rule (protocol inventory diagnostics $catalogue $bad_total) inventory_total

let bad_pin = ($catalogue | update references.windows_terminal.revision "not-the-pinned-commit")
require-rule (protocol inventory diagnostics $bad_pin $inventory) reference_pin

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
  | update groups ($inventory.references.windows_terminal.groups | insert accepted_future 2))
let approved_inventory = ($inventory
  | update references.windows_terminal $expanded_ref
  | update total_groups 38
  | update total_records 668)
let approved = (protocol inventory diagnostics $approved_cat $approved_inventory)
if ($approved | length) != 0 {
  error make {msg: $"correctly approved future group failed: ($approved | to json -r)"}
}

let incomplete = ($approved_cat | update references.windows_terminal.groups.accepted_future.records
  ($approved_cat.references.windows_terminal.groups.accepted_future.records | reject "fixture.second"))
require-rule (protocol inventory diagnostics $incomplete $approved_inventory) branch_inventory

print "Protocol inventory: 8 accepted/negative fixtures passed"
